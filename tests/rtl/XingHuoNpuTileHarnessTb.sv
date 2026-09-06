module XingHuoNpuTileHarnessTb;
    import XorExpectedPkg::*;
    localparam time HALF_PERIOD = 5ns;

    logic clock;
    logic reset = 1'b1;
    logic [7:0] btn = '0;
    logic [7:0] dip = '0;
    logic [15:0] custom_in = '0;
    wire [7:0] led;
    wire [3:0] hex7seg_0;
    wire [3:0] hex7seg_1;
    wire [15:0] custom_out;

    MPSoCDigitalHarness dut (.*);
    initial begin
        clock = 1'b0;
        forever #(HALF_PERIOD) clock = ~clock;
    end

    logic request_toggle = 1'b0;

    task automatic command(input logic [2:0] opcode, input logic [7:0] payload);
        integer timeout;
        begin
            custom_in = {1'b1, 3'b000, opcode, request_toggle, payload};
            repeat (3) @(negedge clock);
            #2ns;
            request_toggle = ~request_toggle;
            custom_in = {1'b1, 3'b000, opcode, request_toggle, payload};
            timeout = 0;
            while ((custom_out[8] !== request_toggle) && timeout < 32) begin
                @(posedge clock);
                #1ns;
                timeout = timeout + 1;
            end
            if (timeout == 32) $fatal(1, "harness command timeout");
        end
    endtask

    integer timeout;
    initial begin
        repeat (3) @(posedge clock);
        #1ns;
        if (led !== 8'h00 || hex7seg_0 !== 4'h0 || hex7seg_1 !== 4'h0)
            $fatal(1, "official harness reset state is incorrect");

        reset = 1'b0;
        custom_in[15] = 1'b1;
        repeat (5) @(posedge clock);
        #1ns;
        if (!custom_out[14]) $fatal(1, "harness did not enter external mode");

        // 通过真实官方Shared RAM模型写、读一个字节。
        command(3'd0, 8'h90);
        command(3'd1, 8'ha5);
        @(posedge clock); #1ns;
        command(3'd0, 8'h90);
        command(3'd2, 8'h00);
        if (custom_out[7:0] !== 8'ha5)
            $fatal(1, "official shared RAM path failed");

        // 使用固定网络运行XOR(1,0)。
        command(3'd4, 8'h01);
        timeout = 0;
        while (!custom_out[10] && timeout < 160) begin
            @(posedge clock); #1ns;
            timeout = timeout + 1;
        end
        if (timeout == 160 || custom_out[13] !== XOR_CLASS_10)
            $fatal(1, "XOR failed through official harness");

        // Harness必须捕获Tile的LED/数码管更新值。
        repeat (2) @(posedge clock); #1ns;
        if (led[0] !== 1'b1 || led[1] !== 1'b1)
            $fatal(1, "official LED hold path failed");

        $display("XINGHUO NPU TILE HARNESS TEST PASS");
        $finish;
    end
endmodule
