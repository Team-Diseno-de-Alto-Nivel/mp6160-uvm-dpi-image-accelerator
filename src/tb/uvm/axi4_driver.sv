// axi4_driver — drives axi4_seq_item onto the AXI4 interface.
//
// Covers the same AXI subset the DPI bridge's BFM uses: INCR bursts,
// full-width beats, all byte strobes set. No narrow transfers, no
// FIXED/WRAP.
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
        @(posedge vif.aclk);

        forever begin
            seq_item_port.get_next_item(req);
            if (req.is_write) drive_write(req);
            else               drive_read(req);
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
