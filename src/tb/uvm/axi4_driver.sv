// axi4_driver — drives axi4_seq_item onto the AXI4 interface.
//
// Covers the same AXI subset the DPI bridge's BFM uses: INCR bursts,
// full-width beats, all byte strobes set. No narrow transfers, no
// FIXED/WRAP.
//
// Drives and samples through vif.driver_cb, the clocking block defined in
// axi4_if.sv — never the raw signals directly.
//
// `included from axi4_pkg.sv, after axi4_seq_item.sv.

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
        @(vif.driver_cb);

        forever begin
            seq_item_port.get_next_item(req);
            if (req.is_write) drive_write(req);
            else               drive_read(req);
            seq_item_port.item_done();
        end
    endtask

    task idle_signals();
        vif.driver_cb.awvalid <= 1'b0;
        vif.driver_cb.wvalid  <= 1'b0;
        vif.driver_cb.wlast   <= 1'b0;
        vif.driver_cb.bready  <= 1'b0;
        vif.driver_cb.arvalid <= 1'b0;
        vif.driver_cb.rready  <= 1'b0;
    endtask

    task drive_write(axi4_seq_item item);
        int unsigned idx;

        // Write address channel
        vif.driver_cb.awid    <= '0;
        vif.driver_cb.awaddr  <= item.addr;
        vif.driver_cb.awlen   <= item.beats - 1;
        vif.driver_cb.awsize  <= BURST_SIZE;
        vif.driver_cb.awburst <= BURST_INCR;
        vif.driver_cb.awvalid <= 1'b1;
        do @(vif.driver_cb); while (vif.driver_cb.awready !== 1'b1);
        vif.driver_cb.awvalid <= 1'b0;

        // Write data channel
        for (int unsigned beat = 0; beat < item.beats; beat++) begin
            for (int lane = 0; lane < BYTES_PER_BEAT; lane++) begin
                idx = beat * BYTES_PER_BEAT + lane;
                vif.driver_cb.wdata[lane*8 +: 8] <= (idx < item.data.size())
                                                    ? item.data[idx] : 8'h00;
            end
            vif.driver_cb.wstrb  <= '1;
            vif.driver_cb.wlast  <= (beat == item.beats - 1);
            vif.driver_cb.wvalid <= 1'b1;
            do @(vif.driver_cb); while (vif.driver_cb.wready !== 1'b1);
            // Drop valid while the next beat is assembled. Holding it high
            // lets the slave consume a beat with stale data — the exact bug
            // that deadlocked the DPI bridge.
            vif.driver_cb.wvalid <= 1'b0;
            vif.driver_cb.wlast  <= 1'b0;
        end

        // Write response channel
        vif.driver_cb.bready <= 1'b1;
        do @(vif.driver_cb); while (vif.driver_cb.bvalid !== 1'b1);
        item.resp  = vif.driver_cb.bresp;
        vif.driver_cb.bready <= 1'b0;
    endtask

    task drive_read(axi4_seq_item item);
        // Read address channel
        vif.driver_cb.arid    <= '0;
        vif.driver_cb.araddr  <= item.addr;
        vif.driver_cb.arlen   <= item.beats - 1;
        vif.driver_cb.arsize  <= BURST_SIZE;
        vif.driver_cb.arburst <= BURST_INCR;
        vif.driver_cb.arvalid <= 1'b1;
        do @(vif.driver_cb); while (vif.driver_cb.arready !== 1'b1);
        vif.driver_cb.arvalid <= 1'b0;

        // Read data channel
        item.data.delete();
        vif.driver_cb.rready <= 1'b1;
        for (int unsigned beat = 0; beat < item.beats; beat++) begin
            do @(vif.driver_cb); while (vif.driver_cb.rvalid !== 1'b1);
            for (int lane = 0; lane < BYTES_PER_BEAT; lane++)
                item.data.push_back(vif.driver_cb.rdata[lane*8 +: 8]);
            item.resp = vif.driver_cb.rresp;
            if (vif.driver_cb.rlast === 1'b1) break;
        end
        vif.driver_cb.rready <= 1'b0;
    endtask

endclass
