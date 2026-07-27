<#
.SYNOPSIS
    Corre el testbench UVM de la RAM AXI4-Full en Vivado 2019.2 sobre Windows.

.DESCRIPTION
    Equivalente a scripts/run_uvm.sh, pero pensado como una corrida de CI/CD
    manual: prepara el entorno, actualiza el repo, compila, simula todos los
    tests y deja TODO lo generado en la carpeta exports\.

    Pasos que ejecuta:
      1. Localiza Vivado 2019.2 y carga su entorno (settings64.bat)
      2. Clona o actualiza el repositorio
      3. xvlog  - analiza el RTL y el testbench
      4. xelab  - elabora el snapshot
      5. xsim   - corre cada test
      6. Parsea el reporte de UVM y arma un resumen
      7. Copia logs, waveforms y cobertura a exports\<timestamp>\

    NOTA: el archivo es ASCII a proposito. Windows PowerShell 5.1 lee los .ps1
    sin BOM como ANSI, asi que cualquier acento o caracter de dibujo saldria
    corrupto en consola.

.PARAMETER Test
    Test a correr. Por defecto corre todos los de la lista.

.PARAMETER Repo
    URL del repositorio a clonar. Si se omite y el script ya esta dentro de un
    clon, usa ese.

.PARAMETER WorkDir
    Donde clonar. Por defecto, la carpeta actual.

.PARAMETER VivadoPath
    Raiz de la instalacion de Vivado. Si se omite, la busca en las rutas
    tipicas de instalacion.

.PARAMETER Gui
    Abre la GUI de XSim en vez de correr en batch. Solo con un test a la vez.

.PARAMETER NoPull
    No hace git pull; usa el arbol de trabajo tal como esta.

.EXAMPLE
    .\scripts\run_uvm_windows.ps1
    Corre todos los tests y exporta resultados.

.EXAMPLE
    .\scripts\run_uvm_windows.ps1 -Test smoke_test -Gui
    Abre la GUI de XSim con el smoke test.

.EXAMPLE
    .\scripts\run_uvm_windows.ps1 -Repo https://github.com/Team-Diseno-de-Alto-Nivel/mp6160-uvm-dpi-image-accelerator.git -WorkDir C:\work
    Clona limpio en C:\work y corre todo.
#>

[CmdletBinding()]
param(
    [string] $Test,
    [string] $Repo,
    [string] $WorkDir,
    [string] $VivadoPath,
    [switch] $Gui,
    [switch] $NoPull,
    [string] $Verbosity = "UVM_MEDIUM"
)

$ErrorActionPreference = "Stop"

# Tests definidos en docs/PlanUVM.md. base_test es la clase base, no se corre
# suelta.
$AllTests = @("smoke_test", "burst_test", "narrow_test", "error_test", "random_test")

$Snapshot  = "tb_snap"
$TopModule = "tb_top"

# -----------------------------------------------------------------------------
# Utilidades de salida
# -----------------------------------------------------------------------------

function Write-Step { param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Ok   { param([string]$Message) Write-Host "    $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "    $Message" -ForegroundColor Yellow }
function Write-Err  { param([string]$Message) Write-Host "    $Message" -ForegroundColor Red }

function Fail {
    param([string]$Message)
    Write-Host ""
    Write-Err "ERROR: $Message"
    exit 1
}

# -----------------------------------------------------------------------------
# Paso 1 - Entorno de Vivado
# -----------------------------------------------------------------------------
# settings64.bat exporta variables en una sesion de cmd. PowerShell no hereda
# nada de un .bat, asi que el truco es correrlo en cmd, volcar el entorno
# resultante con `set`, y reimportarlo aca.

function Import-VivadoEnvironment {
    param([string]$Root)

    $candidates = @()
    if ($Root) {
        $candidates += $Root
    } else {
        $candidates += @(
            "C:\Xilinx\Vivado\2019.2",
            "D:\Xilinx\Vivado\2019.2",
            "C:\Program Files\Xilinx\Vivado\2019.2",
            "C:\Xilinx\Vitis\2019.2\Vivado"
        )
    }

    $settings = $null
    foreach ($candidate in $candidates) {
        $probe = Join-Path $candidate "settings64.bat"
        if (Test-Path $probe) { $settings = $probe; break }
    }

    if (-not $settings) {
        Write-Err "No encontre settings64.bat de Vivado 2019.2."
        Write-Err "Rutas probadas:"
        foreach ($c in $candidates) { Write-Err "  $c" }
        Fail "Pasa la ruta con -VivadoPath 'C:\ruta\a\Vivado\2019.2'"
    }

    Write-Ok "settings64.bat: $settings"

    $cmdLine = '"' + $settings + '" && set'
    $dump = & cmd.exe /c $cmdLine
    if ($LASTEXITCODE -ne 0) {
        Fail "settings64.bat fallo con codigo $LASTEXITCODE"
    }

    foreach ($line in $dump) {
        if ($line -match '^([^=]+)=(.*)$') {
            [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
        }
    }

    foreach ($tool in @("xvlog", "xelab", "xsim")) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            Fail "$tool no quedo en el PATH tras cargar el entorno de Vivado."
        }
    }

    # La bandera de version cambia entre releases de XSim, asi que esto es
    # informativo y nunca debe abortar la corrida.
    $reported = $null
    foreach ($flag in @("--version", "-version")) {
        try {
            $out = & xvlog $flag 2>$null | Select-Object -First 1
            if ($LASTEXITCODE -eq 0 -and $out) { $reported = $out; break }
        } catch { }
    }

    if ($reported) {
        Write-Ok "$reported"
        if ($reported -notmatch "2019\.2") {
            Write-Warn "Se esperaba Vivado 2019.2. El testbench apunta a UVM 1.2;"
            Write-Warn "en otras versiones puede haber diferencias de biblioteca."
        }
    } else {
        Write-Warn "No pude leer la version de xvlog (no es un problema)."
    }
}

# -----------------------------------------------------------------------------
# Paso 2 - Repositorio
# -----------------------------------------------------------------------------

function Resolve-Repository {
    param([string]$RepoUrl, [string]$Target)

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Fail "git no esta en el PATH. Instala Git for Windows."
    }

    # Sin -Repo: asumimos que el script corre desde adentro del clon.
    if (-not $RepoUrl) {
        $here = Split-Path -Parent $PSScriptRoot
        if (-not (Test-Path (Join-Path $here ".git"))) {
            Fail "El script no esta dentro de un clon de git y no se paso -Repo."
        }
        Write-Ok "Usando el clon existente: $here"

        if (-not $NoPull) {
            Push-Location $here
            try {
                $branch = (& git rev-parse --abbrev-ref HEAD)
                Write-Ok "Rama: $branch - actualizando"
                & git pull --ff-only
                if ($LASTEXITCODE -ne 0) {
                    Write-Warn "git pull fallo; sigo con el arbol local tal cual."
                }
            } finally { Pop-Location }
        }
        return $here
    }

    # Con -Repo: clonar (o actualizar si ya existe).
    if (-not $Target) { $Target = (Get-Location).Path }
    $name = [System.IO.Path]::GetFileNameWithoutExtension($RepoUrl)
    $dest = Join-Path $Target $name

    if (Test-Path (Join-Path $dest ".git")) {
        Write-Ok "El clon ya existe: $dest"
        if (-not $NoPull) {
            Push-Location $dest
            try { & git pull --ff-only } finally { Pop-Location }
        }
    } else {
        Write-Ok "Clonando $RepoUrl -> $dest"
        & git clone $RepoUrl $dest
        if ($LASTEXITCODE -ne 0) { Fail "git clone fallo." }
    }

    return $dest
}

# -----------------------------------------------------------------------------
# Paso 3 - Analisis y elaboracion
# -----------------------------------------------------------------------------
# Las herramientas de XSim escriben su propio log (xvlog.log, xelab.log,
# xsim.log) en el directorio de trabajo. Aprovechamos eso en vez de redirigir
# con 2>&1: en PowerShell, el stderr de un ejecutable nativo redirigido asi se
# convierte en ErrorRecord y, con ErrorActionPreference=Stop, aborta el script
# aunque la herramienta haya terminado bien.

function Invoke-Compile {
    param([string]$RepoRoot, [string]$RunDir)

    $fileList = Join-Path $RepoRoot "src\tb\files.f"
    if (-not (Test-Path $fileList)) { Fail "No existe $fileList" }

    # xvlog resuelve las rutas del filelist relativas al CWD, no al .f - por eso
    # hay que pararse siempre en el mismo lugar (build\uvm), igual que en
    # run_uvm.sh.
    Push-Location $RunDir
    try {
        Write-Step "xvlog - analizando fuentes"
        & xvlog -sv -L uvm -f $fileList
        if ($LASTEXITCODE -ne 0) { Fail "xvlog fallo. Ver $RunDir\xvlog.log" }
        Write-Ok "Analisis OK"

        Write-Step "xelab - elaborando $TopModule"
        # -relax hace a XSim menos estricto con construcciones que usa UVM 1.2.
        & xelab -L uvm -timescale 1ns/1ps -relax -s $Snapshot $TopModule
        if ($LASTEXITCODE -ne 0) { Fail "xelab fallo. Ver $RunDir\xelab.log" }
        Write-Ok "Elaboracion OK"
    } finally { Pop-Location }
}

# -----------------------------------------------------------------------------
# Paso 4 - Simulacion
# -----------------------------------------------------------------------------
# xsim devuelve 0 aunque UVM reporte errores, asi que el veredicto sale de
# parsear el reporte final de UVM:
#
#     UVM_ERROR :    0
#     UVM_FATAL :    0

function Get-UvmCount {
    param([string]$LogPath, [string]$Severity)

    if (-not (Test-Path $LogPath)) { return $null }

    $line = Select-String -Path $LogPath -Pattern "^$Severity\s*:" |
            Select-Object -Last 1

    if (-not $line) { return $null }
    if ($line.Line -match '(\d+)\s*$') { return [int]$matches[1] }
    return $null
}

function Invoke-Test {
    param([string]$RunDir, [string]$TestName)

    Push-Location $RunDir
    try {
        if ($Gui) {
            Write-Step "xsim (GUI) - $TestName"
            & xsim $Snapshot --gui `
                -testplusarg "UVM_TESTNAME=$TestName" `
                -testplusarg "UVM_VERBOSITY=$Verbosity"
            return [pscustomobject]@{
                Test = $TestName; Errors = 0; Fatals = 0; Passed = $true
            }
        }

        Write-Step "xsim - $TestName"
        & xsim $Snapshot -R `
            -testplusarg "UVM_TESTNAME=$TestName" `
            -testplusarg "UVM_VERBOSITY=$Verbosity"

        # xsim reescribe xsim.log en cada corrida: lo preservamos por test.
        $testLog = "$TestName.log"
        if (Test-Path "xsim.log") {
            Copy-Item -Path "xsim.log" -Destination $testLog -Force
        }

        $errors = Get-UvmCount -LogPath $testLog -Severity "UVM_ERROR"
        $fatals = Get-UvmCount -LogPath $testLog -Severity "UVM_FATAL"

        if ($null -eq $errors -or $null -eq $fatals) {
            Write-Err "No aparecio el reporte final de UVM - la simulacion aborto."
            return [pscustomobject]@{
                Test = $TestName; Errors = -1; Fatals = -1; Passed = $false
            }
        }

        $passed = ($errors -eq 0 -and $fatals -eq 0)
        if ($passed) {
            Write-Ok "PASS - UVM_ERROR: $errors, UVM_FATAL: $fatals"
        } else {
            Write-Err "FAIL - UVM_ERROR: $errors, UVM_FATAL: $fatals"
        }

        return [pscustomobject]@{
            Test = $TestName; Errors = $errors; Fatals = $fatals; Passed = $passed
        }
    } finally { Pop-Location }
}

# -----------------------------------------------------------------------------
# Paso 5 - Exportar artefactos
# -----------------------------------------------------------------------------

function Export-Artifacts {
    param([string]$RepoRoot, [string]$RunDir, [object[]]$Results, [string]$Stamp)

    $exportDir = Join-Path (Join-Path $RepoRoot "exports") $Stamp
    $logsDir   = Join-Path $exportDir "logs"
    New-Item -ItemType Directory -Force -Path $logsDir | Out-Null

    Get-ChildItem -Path $RunDir -Filter "*.log" -ErrorAction SilentlyContinue |
        Copy-Item -Destination $logsDir -Force

    $waves = @(Get-ChildItem -Path $RunDir -Filter "*.wdb" -ErrorAction SilentlyContinue)
    if ($waves.Count -gt 0) {
        $waveDir = Join-Path $exportDir "waveforms"
        New-Item -ItemType Directory -Force -Path $waveDir | Out-Null
        $waves | Copy-Item -Destination $waveDir -Force
        Write-Ok "Waveforms exportadas: $($waves.Count)"
    }

    $covSrc = Join-Path $RunDir "xsim.covdb"
    if (Test-Path $covSrc) {
        Copy-Item -Path $covSrc -Destination (Join-Path $exportDir "coverage") -Recurse -Force
        Write-Ok "Cobertura exportada"
    }

    $commit = "desconocido"
    $branch = "desconocida"
    Push-Location $RepoRoot
    try {
        $c = & git rev-parse --short HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $c) { $commit = $c }
        $b = & git rev-parse --abbrev-ref HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $b) { $branch = $b }
    } catch { } finally { Pop-Location }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("Testbench UVM - RAM AXI4-Full")
    [void]$sb.AppendLine("=============================")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Fecha     : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    [void]$sb.AppendLine("Host      : $env:COMPUTERNAME")
    [void]$sb.AppendLine("Rama      : $branch")
    [void]$sb.AppendLine("Commit    : $commit")
    [void]$sb.AppendLine("Simulador : Vivado XSim (UVM 1.2)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Resultados")
    [void]$sb.AppendLine("----------")

    foreach ($r in $Results) {
        $verdict = "FAIL"
        if ($r.Passed) { $verdict = "PASS" }
        [void]$sb.AppendLine(("{0,-14} {1,-6} UVM_ERROR={2,-4} UVM_FATAL={3}" -f `
            $r.Test, $verdict, $r.Errors, $r.Fatals))
    }

    $failed = @($Results | Where-Object { -not $_.Passed }).Count
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Total: $($Results.Count) tests, $failed fallidos")

    [System.IO.File]::WriteAllText((Join-Path $exportDir "summary.txt"), $sb.ToString())

    return $exportDir
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

Write-Host ""
Write-Host "======================================================"
Write-Host "  Testbench UVM - RAM AXI4-Full - Vivado 2019.2"
Write-Host "======================================================"

Write-Step "Cargando entorno de Vivado"
Import-VivadoEnvironment -Root $VivadoPath

Write-Step "Preparando repositorio"
$repoRoot = Resolve-Repository -RepoUrl $Repo -Target $WorkDir

$runDir = Join-Path $repoRoot "build\uvm"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

Invoke-Compile -RepoRoot $repoRoot -RunDir $runDir

$testsToRun = $AllTests
if ($Test) { $testsToRun = @($Test) }

if ($Gui -and $testsToRun.Count -gt 1) {
    Fail "-Gui necesita un solo test. Usa -Test <nombre>."
}

$results = @()
foreach ($t in $testsToRun) {
    $results += Invoke-Test -RunDir $runDir -TestName $t
}

if ($Gui) { exit 0 }

Write-Step "Exportando artefactos"
$stamp     = Get-Date -Format "yyyyMMdd-HHmmss"
$exportDir = Export-Artifacts -RepoRoot $repoRoot -RunDir $runDir `
                              -Results $results -Stamp $stamp

Write-Host ""
Write-Host "------------------------------------------------------"
foreach ($r in $results) {
    $verdict = "FAIL"; $color = "Red"
    if ($r.Passed) { $verdict = "PASS"; $color = "Green" }
    Write-Host ("  {0,-14} {1}" -f $r.Test, $verdict) -ForegroundColor $color
}
Write-Host "------------------------------------------------------"
Write-Host "  Exportado en: $exportDir"
Write-Host ""

$failedCount = @($results | Where-Object { -not $_.Passed }).Count
if ($failedCount -gt 0) {
    Write-Err "$failedCount test(s) fallaron."
    exit 1
}

Write-Ok "Todos los tests pasaron."
exit 0
