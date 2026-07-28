// axi4_monitor — watches the write and read paths independently and
// publishes one axi4_seq_item per completed burst on its analysis port.
//
// Samples exclusively through vif.monitor_cb, the clocking block defined in
// axi4_if.sv — never the raw signals directly.
//
// `included from axi4_pkg.sv, after axi4_seq_item.sv.

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
            @(vif.monitor_cb);
            if (vif.monitor_cb.awvalid === 1'b1 && vif.monitor_cb.awready === 1'b1) begin
                item          = axi4_seq_item::type_id::create("wr_item");
                item.is_write = 1'b1;
                item.addr     = vif.monitor_cb.awaddr;
                item.beats    = vif.monitor_cb.awlen + 1;
                item.data.delete();
                item.strb.delete();

                forever begin
                    @(vif.monitor_cb);
                    if (vif.monitor_cb.wvalid === 1'b1 && vif.monitor_cb.wready === 1'b1) begin
                        // Push every lane, strobed or not — the scoreboard
                        // needs the strobe bit to know which bytes to apply.
                        // Filtering here would also desync data[] from byte
                        // position once a strobe is low.
                        for (int lane = 0; lane < BYTES_PER_BEAT; lane++) begin
                            item.data.push_back(vif.monitor_cb.wdata[lane*8 +: 8]);
                            item.strb.push_back(vif.monitor_cb.wstrb[lane]);
                        end
                        if (vif.monitor_cb.wlast === 1'b1) break;
                    end
                end

                forever begin
                    @(vif.monitor_cb);
                    if (vif.monitor_cb.bvalid === 1'b1 && vif.monitor_cb.bready === 1'b1) begin
                        item.resp = vif.monitor_cb.bresp;
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
            @(vif.monitor_cb);
            if (vif.monitor_cb.arvalid === 1'b1 && vif.monitor_cb.arready === 1'b1) begin
                item          = axi4_seq_item::type_id::create("rd_item");
                item.is_write = 1'b0;
                item.addr     = vif.monitor_cb.araddr;
                item.beats    = vif.monitor_cb.arlen + 1;
                item.data.delete();

                forever begin
                    @(vif.monitor_cb);
                    if (vif.monitor_cb.rvalid === 1'b1 && vif.monitor_cb.rready === 1'b1) begin
                        for (int lane = 0; lane < BYTES_PER_BEAT; lane++)
                            item.data.push_back(vif.monitor_cb.rdata[lane*8 +: 8]);
                        item.resp = vif.monitor_cb.rresp;
                        if (vif.monitor_cb.rlast === 1'b1) break;
                    end
                end

                ap.write(item);
            end
        end
    endtask

endclass
