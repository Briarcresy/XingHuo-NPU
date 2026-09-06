module XingHuoNpuTile_sva_tb;
    logic clock;
    logic reset = 1'b1;
    logic [7:0] io_btn = '0;
    logic [7:0] io_dip = '0;
    logic [15:0] io_customIn = '0;
    wire [7:0] io_led;
    wire io_ledUpdate;
    wire [3:0] io_hex7seg_0;
    wire [3:0] io_hex7seg_1;
    wire io_hex7segUpdate;
    wire [15:0] io_customOut;
    wire [7:0] io_ramAddr;
    wire io_ramWen;
    wire [7:0] io_ramWdata;
    logic [7:0] io_ramRdata;
    logic [7:0] memory [0:255];
    logic request_toggle = 1'b0;

    initial begin
        clock = 1'b0;
        forever #5ns clock = ~clock;
    end
    always_comb io_ramRdata = memory[io_ramAddr];
    always_ff @(posedge clock) if (io_ramWen && !reset)
        memory[io_ramAddr] <= io_ramWdata;

    XingHuoNpuTile dut (.*);

    task automatic command(input logic [2:0] opcode, input logic [7:0] payload);
        integer timeout;
        begin
            io_customIn = {1'b1, 3'b000, opcode, request_toggle, payload};
            repeat (3) @(negedge clock);
            #2ns;
            request_toggle = ~request_toggle;
            io_customIn = {1'b1, 3'b000, opcode, request_toggle, payload};
            timeout = 0;
            while ((io_customOut[8] !== request_toggle) && timeout < 32) begin
                @(posedge clock); #1ns;
                timeout = timeout + 1;
            end
            if (timeout == 32) $fatal(1, "SVA stimulus command timeout");
        end
    endtask

    integer index;
    integer timeout;
    initial begin
        for (index=0; index<256; index=index+1) memory[index] = 8'h00;
        repeat (3) @(posedge clock);
        reset = 1'b0;
        io_customIn[15] = 1'b1;
        repeat (5) @(posedge clock);
        command(3'd4, 8'h02); // 固定网络运行XOR(0,1)。
        timeout = 0;
        while (!io_customOut[10] && timeout < 160) begin
            @(posedge clock); #1ns;
            timeout = timeout + 1;
        end
        if (timeout == 160 || !io_customOut[13])
            $fatal(1, "Tile SVA stimulus produced wrong XOR result");
        $display("NPU TILE SVA TEST PASS");
        $finish;
    end
endmodule
