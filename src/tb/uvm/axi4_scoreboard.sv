// axi4_scoreboard — associative reference model, one byte per address.
//
// `included from axi4_pkg.sv, after axi4_seq_item.sv.

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
