// axi4_pkg — the whole UVM environment for axi4_ram.
//
// PLACEHOLDER (#9 through #12). Everything lives in one package on purpose:
// this is a skeleton nobody has been able to elaborate yet (no Vivado on the
// machine it was written on), so keeping the surface small matters more than
// following the one-class-per-file convention. Whoever picks up #9 should split
// it into separate files as it grows.
//
// What actually works: smoke_test drives a real write and read back, checked by
// the scoreboard. The other four tests are placeholders that emit a UVM_WARNING
// naming what is missing and finish without error — visible in the log, but not
// counted as a failure, since the run scripts only look at UVM_ERROR/UVM_FATAL.
//
// Targets Vivado XSim, which ships UVM 1.2 (not IEEE 1800.2): no register layer,
// no advanced factory usage.

`ifndef AXI4_PKG_SV
`define AXI4_PKG_SV

package axi4_pkg;

    import uvm_pkg::*;
`include "uvm_macros.svh"

    localparam BYTES_PER_BEAT = 8;
    localparam BURST_SIZE     = 3;       // log2(BYTES_PER_BEAT)
    localparam BURST_INCR     = 2'b01;

    // ── Sequence item ────────────────────────────────────────────────────────

    class axi4_seq_item extends uvm_sequence_item;

        // Stimulus
        rand bit          is_write;
        rand bit [31:0]   addr;
        rand int unsigned beats;         // 1..256
        bit [7:0]         data[$];       // bytes, filled by the sequence

        // Observed response
        bit [1:0]         resp;

        `uvm_object_utils(axi4_seq_item)

        // Aligned to the bus width and inside the testbench's reduced 64 KB
        // MEM_DEPTH.
        // TODO(#12): relax for narrow_test and error_test.
        constraint c_addr  { addr[2:0] == 3'b000; addr < 32'h0001_0000; }
        constraint c_beats { beats inside {[1:16]}; }

        function new(string name = "axi4_seq_item");
            super.new(name);
        endfunction

        function string convert2string();
            return $sformatf("%s addr=0x%08h beats=%0d bytes=%0d resp=%0d",
                             is_write ? "WRITE" : "READ",
                             addr, beats, data.size(), resp);
        endfunction

    endclass

    // ── Driver ───────────────────────────────────────────────────────────────
    // Covers the same AXI subset the DPI bridge's BFM uses: INCR bursts,
    // full-width beats, all byte strobes set. No narrow transfers, no
    // FIXED/WRAP.

    class axi4_driver extends uvm_driver #(axi4_seq_item);

        `uvm_component_utils(axi4_driver)

        virtual axi4_if vif;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db #(virtual axi4_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "axi4_driver: virtual interface not configured")
        endfunction

        task run_phase(uvm_phase phase);
            idle_signals();
            wait (vif.aresetn === 1'b1);
            @(posedge vif.aclk);

            forever begin
                seq_item_port.get_next_item(req);
                if (req.is_write) drive_write(req);
                else              drive_read(req);
                seq_item_port.item_done();
            end
        endtask

        task idle_signals();
            vif.awvalid <= 1'b0;
            vif.wvalid  <= 1'b0;
            vif.wlast   <= 1'b0;
            vif.bready  <= 1'b0;
            vif.arvalid <= 1'b0;
            vif.rready  <= 1'b0;
        endtask

        task drive_write(axi4_seq_item item);
            int unsigned idx;

            // Write address channel
            vif.awid    <= '0;
            vif.awaddr  <= item.addr;
            vif.awlen   <= item.beats - 1;
            vif.awsize  <= BURST_SIZE;
            vif.awburst <= BURST_INCR;
            vif.awvalid <= 1'b1;
            do @(posedge vif.aclk); while (vif.awready !== 1'b1);
            vif.awvalid <= 1'b0;

            // Write data channel
            for (int unsigned beat = 0; beat < item.beats; beat++) begin
                for (int lane = 0; lane < BYTES_PER_BEAT; lane++) begin
                    idx = beat * BYTES_PER_BEAT + lane;
                    vif.wdata[lane*8 +: 8] <= (idx < item.data.size())
                                              ? item.data[idx] : 8'h00;
                end
                vif.wstrb  <= '1;
                vif.wlast  <= (beat == item.beats - 1);
                vif.wvalid <= 1'b1;
                do @(posedge vif.aclk); while (vif.wready !== 1'b1);
                // Drop valid while the next beat is assembled. Holding it high
                // lets the slave consume a beat with stale data — the exact bug
                // that deadlocked the DPI bridge.
                vif.wvalid <= 1'b0;
                vif.wlast  <= 1'b0;
            end

            // Write response channel
            vif.bready <= 1'b1;
            do @(posedge vif.aclk); while (vif.bvalid !== 1'b1);
            item.resp  = vif.bresp;
            vif.bready <= 1'b0;
        endtask

        task drive_read(axi4_seq_item item);
            // Read address channel
            vif.arid    <= '0;
            vif.araddr  <= item.addr;
            vif.arlen   <= item.beats - 1;
            vif.arsize  <= BURST_SIZE;
            vif.arburst <= BURST_INCR;
            vif.arvalid <= 1'b1;
            do @(posedge vif.aclk); while (vif.arready !== 1'b1);
            vif.arvalid <= 1'b0;

            // Read data channel
            item.data.delete();
            vif.rready <= 1'b1;
            for (int unsigned beat = 0; beat < item.beats; beat++) begin
                do @(posedge vif.aclk); while (vif.rvalid !== 1'b1);
                for (int lane = 0; lane < BYTES_PER_BEAT; lane++)
                    item.data.push_back(vif.rdata[lane*8 +: 8]);
                item.resp = vif.rresp;
                if (vif.rlast === 1'b1) break;
            end
            vif.rready <= 1'b0;
        endtask

    endclass

    // ── Monitor ──────────────────────────────────────────────────────────────
    // Watches the write and read paths independently and publishes one item per
    // completed burst.

    class axi4_monitor extends uvm_monitor;

        `uvm_component_utils(axi4_monitor)

        virtual axi4_if vif;
        uvm_analysis_port #(axi4_seq_item) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap = new("ap", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db #(virtual axi4_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "axi4_monitor: virtual interface not configured")
        endfunction

        task run_phase(uvm_phase phase);
            wait (vif.aresetn === 1'b1);
            fork
                observe_writes();
                observe_reads();
            join
        endtask

        task observe_writes();
            axi4_seq_item item;
            forever begin
                @(posedge vif.aclk);
                if (vif.awvalid === 1'b1 && vif.awready === 1'b1) begin
                    item          = axi4_seq_item::type_id::create("wr_item");
                    item.is_write = 1'b1;
                    item.addr     = vif.awaddr;
                    item.beats    = vif.awlen + 1;
                    item.data.delete();

                    forever begin
                        @(posedge vif.aclk);
                        if (vif.wvalid === 1'b1 && vif.wready === 1'b1) begin
                            for (int lane = 0; lane < BYTES_PER_BEAT; lane++)
                                if (vif.wstrb[lane] === 1'b1)
                                    item.data.push_back(vif.wdata[lane*8 +: 8]);
                            if (vif.wlast === 1'b1) break;
                        end
                    end

                    forever begin
                        @(posedge vif.aclk);
                        if (vif.bvalid === 1'b1 && vif.bready === 1'b1) begin
                            item.resp = vif.bresp;
                            break;
                        end
                    end

                    ap.write(item);
                end
            end
        endtask

        task observe_reads();
            axi4_seq_item item;
            forever begin
                @(posedge vif.aclk);
                if (vif.arvalid === 1'b1 && vif.arready === 1'b1) begin
                    item          = axi4_seq_item::type_id::create("rd_item");
                    item.is_write = 1'b0;
                    item.addr     = vif.araddr;
                    item.beats    = vif.arlen + 1;
                    item.data.delete();

                    forever begin
                        @(posedge vif.aclk);
                        if (vif.rvalid === 1'b1 && vif.rready === 1'b1) begin
                            for (int lane = 0; lane < BYTES_PER_BEAT; lane++)
                                item.data.push_back(vif.rdata[lane*8 +: 8]);
                            item.resp = vif.rresp;
                            if (vif.rlast === 1'b1) break;
                        end
                    end

                    ap.write(item);
                end
            end
        endtask

    endclass

    // ── Agent ────────────────────────────────────────────────────────────────

    typedef uvm_sequencer #(axi4_seq_item) axi4_sequencer;

    class axi4_agent extends uvm_agent;

        `uvm_component_utils(axi4_agent)

        axi4_sequencer sequencer;
        axi4_driver    driver;
        axi4_monitor   monitor;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            monitor = axi4_monitor::type_id::create("monitor", this);
            // Always active: the DUT is the slave, the testbench is the master.
            sequencer = axi4_sequencer::type_id::create("sequencer", this);
            driver    = axi4_driver::type_id::create("driver", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            driver.seq_item_port.connect(sequencer.seq_item_export);
        endfunction

    endclass

    // ── Scoreboard ───────────────────────────────────────────────────────────
    // Associative reference model, one byte per address.

    class axi4_scoreboard extends uvm_scoreboard;

        `uvm_component_utils(axi4_scoreboard)

        uvm_analysis_imp #(axi4_seq_item, axi4_scoreboard) item_imp;

        bit [7:0]    model [int unsigned];
        int unsigned checks;
        int unsigned mismatches;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            item_imp = new("item_imp", this);
        endfunction

        function void write(axi4_seq_item item);
            if (item.is_write) apply_write(item);
            else               check_read(item);
        endfunction

        function void apply_write(axi4_seq_item item);
            // TODO(#10): honour partial WSTRB — bytes with the strobe low must
            // keep their previous value. The driver always sets all strobes, so
            // this is not exercised yet.
            foreach (item.data[i])
                model[item.addr + i] = item.data[i];
        endfunction

        function void check_read(axi4_seq_item item);
            int unsigned a;
            bit [7:0]    expected;

            foreach (item.data[i]) begin
                a = item.addr + i;
                // An address never written reads back zero from the DUT.
                expected = model.exists(a) ? model[a] : 8'h00;
                checks++;

                if (item.data[i] !== expected) begin
                    mismatches++;
                    `uvm_error("SB_MISMATCH",
                        $sformatf("addr=0x%08h expected=0x%02h actual=0x%02h",
                                  a, expected, item.data[i]))
                end
            end
        endfunction

        function void report_phase(uvm_phase phase);
            super.report_phase(phase);
            `uvm_info("SB_SUMMARY",
                $sformatf("%0d bytes checked, %0d mismatches", checks, mismatches),
                UVM_LOW)
        endfunction

    endclass

    // ── Functional coverage ──────────────────────────────────────────────────

    class axi4_coverage extends uvm_subscriber #(axi4_seq_item);

        `uvm_component_utils(axi4_coverage)

        bit          cp_is_write;
        int unsigned cp_beats;

        covergroup cg_burst;
            option.per_instance = 1;

            direction: coverpoint cp_is_write {
                bins write = {1};
                bins read  = {0};
            }

            length: coverpoint cp_beats {
                bins single    = {1};
                bins short_len = {[2:15]};
                bins medium    = {[16:63]};
                bins long_len  = {[64:255]};
                bins maximum   = {256};
            }
        endgroup

        // TODO(#11): cross direction x length, plus covergroups for AWSIZE,
        // AWBURST, WSTRB, response codes, and aligned vs unaligned addresses.
        // Targets are in docs/PlanUVM.md.

        function new(string name, uvm_component parent);
            super.new(name, parent);
            cg_burst = new();
        endfunction

        function void write(axi4_seq_item t);
            cp_is_write = t.is_write;
            cp_beats    = t.beats;
            cg_burst.sample();
        endfunction

        function void report_phase(uvm_phase phase);
            super.report_phase(phase);
            `uvm_info("COV_SUMMARY",
                $sformatf("cg_burst coverage: %0.2f%%", cg_burst.get_coverage()),
                UVM_LOW)
        endfunction

    endclass

    // ── Environment ──────────────────────────────────────────────────────────

    class axi4_env extends uvm_env;

        `uvm_component_utils(axi4_env)

        axi4_agent      agent;
        axi4_scoreboard scoreboard;
        axi4_coverage   coverage;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent      = axi4_agent::type_id::create("agent", this);
            scoreboard = axi4_scoreboard::type_id::create("scoreboard", this);
            coverage   = axi4_coverage::type_id::create("coverage", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            agent.monitor.ap.connect(scoreboard.item_imp);
            agent.monitor.ap.connect(coverage.analysis_export);
        endfunction

    endclass

    // ── Sequences ────────────────────────────────────────────────────────────

    virtual class axi4_base_seq extends uvm_sequence #(axi4_seq_item);

        function new(string name = "axi4_base_seq");
            super.new(name);
        endfunction

        task write_burst(input bit [31:0] addr, input int unsigned beats);
            axi4_seq_item item;
            item          = axi4_seq_item::type_id::create("wr");
            item.is_write = 1'b1;
            item.addr     = addr;
            item.beats    = beats;
            for (int i = 0; i < beats * BYTES_PER_BEAT; i++)
                item.data.push_back($urandom_range(0, 255));
            start_item(item);
            finish_item(item);
        endtask

        task read_burst(input bit [31:0] addr, input int unsigned beats);
            axi4_seq_item item;
            item          = axi4_seq_item::type_id::create("rd");
            item.is_write = 1'b0;
            item.addr     = addr;
            item.beats    = beats;
            start_item(item);
            finish_item(item);
        endtask

    endclass

    // Write then read back. The scoreboard does the comparison.
    class axi4_smoke_seq extends axi4_base_seq;

        `uvm_object_utils(axi4_smoke_seq)

        function new(string name = "axi4_smoke_seq");
            super.new(name);
        endfunction

        task body();
            `uvm_info("SMOKE", "single-beat write then read back", UVM_LOW)
            write_burst(32'h0000_0000, 1);
            read_burst(32'h0000_0000, 1);

            `uvm_info("SMOKE", "four-beat burst write then read back", UVM_LOW)
            write_burst(32'h0000_0100, 4);
            read_burst(32'h0000_0100, 4);
        endtask

    endclass

    // TODO(#12): axi4_burst_seq  — INCR of 1/2/16/256 beats, FIXED, back-to-back
    // TODO(#12): axi4_narrow_seq — AWSIZE below the bus width, partial WSTRB
    // TODO(#12): axi4_error_seq  — addresses past MEM_DEPTH, expecting SLVERR
    // TODO(#12): axi4_random_seq — constrained random stimulus

    // ── Tests ────────────────────────────────────────────────────────────────
    // These names are hardcoded in scripts/run_uvm.sh and
    // scripts/run_uvm_windows.ps1. Do not rename without updating both.

    class axi4_base_test extends uvm_test;

        `uvm_component_utils(axi4_base_test)

        axi4_env env;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = axi4_env::type_id::create("env", this);
        endfunction

        function void report_phase(uvm_phase phase);
            uvm_report_server svr = uvm_report_server::get_server();
            super.report_phase(phase);
            if (svr.get_severity_count(UVM_ERROR) == 0 &&
                svr.get_severity_count(UVM_FATAL) == 0)
                `uvm_info("RESULT", "TEST PASSED", UVM_NONE)
            else
                `uvm_info("RESULT", "TEST FAILED", UVM_NONE)
        endfunction

    endclass

    // The only test with real stimulus.
    class smoke_test extends axi4_base_test;

        `uvm_component_utils(smoke_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        task run_phase(uvm_phase phase);
            axi4_smoke_seq seq;
            phase.raise_objection(this);
            seq = axi4_smoke_seq::type_id::create("seq");
            seq.start(env.agent.sequencer);
            #200ns;
            phase.drop_objection(this);
        endtask

    endclass

    // Placeholders. Each says exactly what it is missing. When implementing,
    // drop the UVM_WARNING and start the corresponding sequence.

    class burst_test extends axi4_base_test;
        `uvm_component_utils(burst_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            `uvm_warning("NOT_IMPLEMENTED",
                "burst_test is a placeholder (#12): needs INCR bursts of 1/2/16/256 beats, FIXED, and back-to-back transfers with no bubbles")
            #100ns;
            phase.drop_objection(this);
        endtask
    endclass

    class narrow_test extends axi4_base_test;
        `uvm_component_utils(narrow_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            `uvm_warning("NOT_IMPLEMENTED",
                "narrow_test is a placeholder (#12): needs AWSIZE below the bus width and partial WSTRB. The DUT does not support them yet either (#6)")
            #100ns;
            phase.drop_objection(this);
        endtask
    endclass

    class error_test extends axi4_base_test;
        `uvm_component_utils(error_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            `uvm_warning("NOT_IMPLEMENTED",
                "error_test is a placeholder (#12): needs out-of-range accesses expecting SLVERR. The DUT answers OKAY today (#6)")
            #100ns;
            phase.drop_objection(this);
        endtask
    endclass

    class random_test extends axi4_base_test;
        `uvm_component_utils(random_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            `uvm_warning("NOT_IMPLEMENTED",
                "random_test is a placeholder (#12): needs the constrained random sequence")
            #100ns;
            phase.drop_objection(this);
        endtask
    endclass

endpackage

`endif  // AXI4_PKG_SV
