<#
.SYNOPSIS
    Runs the AXI4-Full RAM's UVM testbench in Vivado 2019.2 on Windows.

.DESCRIPTION
    Equivalent to scripts/run_uvm.sh, but shaped as a manual CI/CD run: sets up
    the environment, updates the repo, compiles, simulates every test and leaves
    everything it produced under exports\.

    Steps:
      1. Locate Vivado 2019.2 and load its environment (settings64.bat)
      2. Clone or update the repository
      3. xvlog  - analyse the RTL and the testbench
      4. xelab  - elaborate the snapshot
      5. xsim   - run each test
      6. Parse UVM's report and build a summary
      7. Copy logs, waveforms and coverage into exports\<timestamp>\

    NOTE: this file is ASCII on purpose. Windows PowerShell 5.1 reads .ps1 files
    without a BOM as ANSI, so any accent or box-drawing character would come out
    corrupted on the console.

.PARAMETER Test
    Test to run. Runs every test in the list by default.

.PARAMETER Repo
    Repository URL to clone. If omitted and the script already sits inside a
    clone, that clone is used.

.PARAMETER WorkDir
    Where to clone. Defaults to the current folder.

.PARAMETER VivadoPath
    Vivado installation root. If omitted, the usual install paths are probed.

.PARAMETER Gui
    Opens the XSim GUI instead of running in batch. One test at a time only.

.PARAMETER NoPull
    Skips git pull; uses the working tree as it is.

.EXAMPLE
    .\scripts\run_uvm_windows.ps1
    Runs every test and exports the results.

.EXAMPLE
    .\scripts\run_uvm_windows.ps1 -Test smoke_test -Gui
    Opens the XSim GUI with the smoke test.

.EXAMPLE
    .\scripts\run_uvm_windows.ps1 -Repo https://github.com/Team-Diseno-de-Alto-Nivel/mp6160-uvm-dpi-image-accelerator.git -WorkDir C:\work
    Clones fresh into C:\work and runs everything.
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

# Tests defined in docs/PlanUVM.md. base_test is the base class, never run alone.
$AllTests = @("smoke_test", "burst_test", "narrow_test", "error_test", "random_test")

$Snapshot  = "tb_snap"
$TopModule = "tb_top"

# -----------------------------------------------------------------------------
# Output helpers
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
# Step 1 - Vivado environment
# -----------------------------------------------------------------------------
# settings64.bat exports variables into a cmd session. PowerShell inherits
# nothing from a .bat, so the trick is to run it under cmd, dump the resulting
# environment with `set`, and re-import it here.

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
        Write-Err "Could not find Vivado 2019.2 settings64.bat."
        Write-Err "Paths probed:"
        foreach ($c in $candidates) { Write-Err "  $c" }
        Fail "Pass the path with -VivadoPath 'C:\path\to\Vivado\2019.2'"
    }

    Write-Ok "settings64.bat: $settings"

    $cmdLine = '"' + $settings + '" && set'
    $dump = & cmd.exe /c $cmdLine
    if ($LASTEXITCODE -ne 0) {
        Fail "settings64.bat failed with code $LASTEXITCODE"
    }

    foreach ($line in $dump) {
        if ($line -match '^([^=]+)=(.*)$') {
            [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
        }
    }

    foreach ($tool in @("xvlog", "xelab", "xsim")) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            Fail "$tool is not on the PATH after loading the Vivado environment."
        }
    }

    # The version flag differs across XSim releases, so this is informational
    # and must never abort the run.
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
            Write-Warn "Expected Vivado 2019.2. The testbench targets UVM 1.2;"
            Write-Warn "other versions may ship a different library."
        }
    } else {
        Write-Warn "Could not read the xvlog version (not a problem)."
    }
}

# -----------------------------------------------------------------------------
# Step 2 - Repository
# -----------------------------------------------------------------------------

function Resolve-Repository {
    param([string]$RepoUrl, [string]$Target)

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Fail "git is not on the PATH. Install Git for Windows."
    }

    # Without -Repo: assume the script runs from inside the clone.
    if (-not $RepoUrl) {
        $here = Split-Path -Parent $PSScriptRoot
        if (-not (Test-Path (Join-Path $here ".git"))) {
            Fail "The script is not inside a git clone and -Repo was not given."
        }
        Write-Ok "Using the existing clone: $here"

        if (-not $NoPull) {
            Push-Location $here
            try {
                $branch = (& git rev-parse --abbrev-ref HEAD)
                Write-Ok "Branch: $branch - updating"
                & git pull --ff-only
                if ($LASTEXITCODE -ne 0) {
                    Write-Warn "git pull failed; continuing with the local tree as is."
                }
            } finally { Pop-Location }
        }
        return $here
    }

    # With -Repo: clone, or update if it already exists.
    if (-not $Target) { $Target = (Get-Location).Path }
    $name = [System.IO.Path]::GetFileNameWithoutExtension($RepoUrl)
    $dest = Join-Path $Target $name

    if (Test-Path (Join-Path $dest ".git")) {
        Write-Ok "Clone already exists: $dest"
        if (-not $NoPull) {
            Push-Location $dest
            try { & git pull --ff-only } finally { Pop-Location }
        }
    } else {
        Write-Ok "Cloning $RepoUrl -> $dest"
        & git clone $RepoUrl $dest
        if ($LASTEXITCODE -ne 0) { Fail "git clone fallo." }
    }

    return $dest
}

# -----------------------------------------------------------------------------
# Step 3 - Analysis and elaboration
# -----------------------------------------------------------------------------
# The XSim tools write their own logs (xvlog.log, xelab.log, xsim.log) into the
# working directory. We use those instead of redirecting with 2>&1: in
# PowerShell, a native executable's stderr redirected that way becomes an
# ErrorRecord and, with ErrorActionPreference=Stop, aborts the script even when
# the tool finished fine.

function Invoke-Compile {
    param([string]$RepoRoot, [string]$RunDir)

    $fileList = Join-Path $RepoRoot "src\tb\files.f"
    if (-not (Test-Path $fileList)) { Fail "$fileList does not exist" }

    # xvlog resolves filelist paths relative to the CWD, not to the .f file, so
    # we always stand in the same place (build\uvm), same as run_uvm.sh.
    Push-Location $RunDir
    try {
        Write-Step "xvlog - analizando fuentes"
        & xvlog -sv -L uvm -f $fileList
        if ($LASTEXITCODE -ne 0) { Fail "xvlog failed. See $RunDir\xvlog.log" }
        Write-Ok "Analysis OK"

        Write-Step "xelab - elaborando $TopModule"
        # -relax makes XSim less strict about constructs UVM 1.2 relies on.
        & xelab -L uvm -timescale 1ns/1ps -relax -s $Snapshot $TopModule
        if ($LASTEXITCODE -ne 0) { Fail "xelab failed. See $RunDir\xelab.log" }
        Write-Ok "Elaboration OK"
    } finally { Pop-Location }
}

# -----------------------------------------------------------------------------
# Step 4 - Simulation
# -----------------------------------------------------------------------------
# xsim exits 0 even when UVM reports errors, so the verdict comes from parsing
# UVM's final report:
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

        # xsim rewrites xsim.log on every run, so keep a copy per test.
        $testLog = "$TestName.log"
        if (Test-Path "xsim.log") {
            Copy-Item -Path "xsim.log" -Destination $testLog -Force
        }

        $errors = Get-UvmCount -LogPath $testLog -Severity "UVM_ERROR"
        $fatals = Get-UvmCount -LogPath $testLog -Severity "UVM_FATAL"

        if ($null -eq $errors -or $null -eq $fatals) {
            Write-Err "No UVM final report found - the simulation aborted."
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
# Step 5 - Export artifacts
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
        Write-Ok "Waveforms exported: $($waves.Count)"
    }

    $covSrc = Join-Path $RunDir "xsim.covdb"
    if (Test-Path $covSrc) {
        Copy-Item -Path $covSrc -Destination (Join-Path $exportDir "coverage") -Recurse -Force
        Write-Ok "Coverage exported"
    }

    $commit = "unknown"
    $branch = "unknown"
    Push-Location $RepoRoot
    try {
        $c = & git rev-parse --short HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $c) { $commit = $c }
        $b = & git rev-parse --abbrev-ref HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $b) { $branch = $b }
    } catch { } finally { Pop-Location }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("UVM testbench - AXI4-Full RAM")
    [void]$sb.AppendLine("=============================")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Date      : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    [void]$sb.AppendLine("Host      : $env:COMPUTERNAME")
    [void]$sb.AppendLine("Branch    : $branch")
    [void]$sb.AppendLine("Commit    : $commit")
    [void]$sb.AppendLine("Simulator : Vivado XSim (UVM 1.2)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Results")
    [void]$sb.AppendLine("-------")

    foreach ($r in $Results) {
        $verdict = "FAIL"
        if ($r.Passed) { $verdict = "PASS" }
        [void]$sb.AppendLine(("{0,-14} {1,-6} UVM_ERROR={2,-4} UVM_FATAL={3}" -f `
            $r.Test, $verdict, $r.Errors, $r.Fatals))
    }

    $failed = @($Results | Where-Object { -not $_.Passed }).Count
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Total: $($Results.Count) tests, $failed failed")

    [System.IO.File]::WriteAllText((Join-Path $exportDir "summary.txt"), $sb.ToString())

    return $exportDir
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

Write-Host ""
Write-Host "======================================================"
Write-Host "  UVM testbench - AXI4-Full RAM - Vivado 2019.2"
Write-Host "======================================================"

Write-Step "Loading Vivado environment"
Import-VivadoEnvironment -Root $VivadoPath

Write-Step "Preparing repository"
$repoRoot = Resolve-Repository -RepoUrl $Repo -Target $WorkDir

$runDir = Join-Path $repoRoot "build\uvm"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

Invoke-Compile -RepoRoot $repoRoot -RunDir $runDir

$testsToRun = $AllTests
if ($Test) { $testsToRun = @($Test) }

if ($Gui -and $testsToRun.Count -gt 1) {
    Fail "-Gui needs a single test. Use -Test <name>."
}

$results = @()
foreach ($t in $testsToRun) {
    $results += Invoke-Test -RunDir $runDir -TestName $t
}

if ($Gui) { exit 0 }

Write-Step "Exporting artifacts"
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
Write-Host "  Exported to: $exportDir"
Write-Host ""

$failedCount = @($results | Where-Object { -not $_.Passed }).Count
if ($failedCount -gt 0) {
    Write-Err "$failedCount test(s) failed."
    exit 1
}

Write-Ok "All tests passed."
exit 0
