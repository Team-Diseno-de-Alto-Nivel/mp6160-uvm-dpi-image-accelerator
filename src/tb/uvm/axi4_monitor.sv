// axi4_monitor — watches the write and read paths independently and
// publishes one axi4_seq_item per completed burst on its analysis port.
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
