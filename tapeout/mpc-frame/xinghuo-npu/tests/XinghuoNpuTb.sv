// 中文：这是“单元测试”，只检查你的电路，不经过 FrameTop。
//       标有“通常保留”的部分负责搭建测试环境；标有“按设计修改”的部分
//       是你为自己的功能编写输入和检查结果的位置。
// English: This is the unit test. It checks only your circuit, without FrameTop.
//          Keep the test setup unless you know it must change. Edit the marked
//          stimulus/check section to match your circuit.


module XinghuoNpuTb;
    localparam int IO_WIDTH = 66;
    localparam time HALF_PERIOD = 5ns;

    logic clock = 1'b0;
    logic reset = 1'b1;
    logic [IO_WIDTH-1:0] io_in = '0;
    wire [IO_WIDTH-1:0] io_out;
    wire [IO_WIDTH-1:0] io_oe;

    always #(HALF_PERIOD) clock = ~clock;

    // UserDesignDut由MPC-Frame构建工具连接到design.json声明的用户顶层。
    UserDesignDut #(
        .IO_WIDTH(IO_WIDTH)
    ) dut (
        .clock (clock),
        .reset (reset),
        .io_in (io_in),
        .io_out(io_out),
        .io_oe (io_oe)
    );

    task automatic write_register(input logic [4:0] address, input logic [7:0] data);
        begin
            @(negedge clock);
            io_in[12:8] = address;
            io_in[7:0]  = data;
            io_in[13]   = 1'b1;
            io_in[14]   = 1'b0;
            @(posedge clock);
            #1ns;
            @(negedge clock);
            io_in[13] = 1'b0;
        end
    endtask

    task automatic read_register(input logic [4:0] address, output logic [7:0] data);
        begin
            @(negedge clock);
            io_in[12:8] = address;
            io_in[13]   = 1'b0;
            io_in[14]   = 1'b1;
            #1ns;
            if (io_oe[7:0] !== 8'hff) $fatal(1, "read data bus is not enabled");
            data = io_out[7:0];
            @(negedge clock);
            io_in[14] = 1'b0;
        end
    endtask

    task automatic load_word32(input logic [4:0] base_address, input logic [31:0] value);
        begin
            write_register(base_address + 0, value[7:0]);
            write_register(base_address + 1, value[15:8]);
            write_register(base_address + 2, value[23:16]);
            write_register(base_address + 3, value[31:24]);
        end
    endtask

    task automatic load_word64(input logic [4:0] base_address, input logic [63:0] value);
        begin
            write_register(base_address + 0, value[7:0]);
            write_register(base_address + 1, value[15:8]);
            write_register(base_address + 2, value[23:16]);
            write_register(base_address + 3, value[31:24]);
            write_register(base_address + 4, value[39:32]);
            write_register(base_address + 5, value[47:40]);
            write_register(base_address + 6, value[55:48]);
            write_register(base_address + 7, value[63:56]);
        end
    endtask

    initial begin
        logic [31:0] result;
        logic [7:0] read_data;
        integer wait_cycles;

        repeat (3) @(posedge clock);
        @(negedge clock);
        reset = 1'b0;

        // 不读数据时只有busy和done两个固定状态输出开启。
        #1ns;
        if (io_oe[7:0] !== 8'h00 || io_oe[16:15] !== 2'b11)
            $fatal(1, "default output-enable mapping is incorrect");
        if (io_oe[IO_WIDTH-1:17] !== '0) $fatal(1, "unused payload outputs must be released");

        // A=[[1,2],[3,4]]，W=[[5,6],[7,8]]，Bias=[1,-2]，shift=0。
        load_word32(5'h00, 32'h04030201);
        load_word32(5'h04, 32'h08070605);
        load_word64(5'h08, 64'hfffffffe00000001);
        write_register(5'h10, 8'd0);
        write_register(5'h11, 8'b00000001);

        wait_cycles = 0;
        while (io_out[16] !== 1'b1 && wait_cycles < 32) begin
            @(posedge clock);
            #1ns;
            wait_cycles = wait_cycles + 1;
        end
        if (io_out[16] !== 1'b1) $fatal(1, "NPU operation timed out");

        read_register(5'h14, read_data);
        result[7:0] = read_data;
        read_register(5'h15, read_data);
        result[15:8] = read_data;
        read_register(5'h16, read_data);
        result[23:16] = read_data;
        read_register(5'h17, read_data);
        result[31:24] = read_data;
        if (result !== 32'h302c1414)
            $fatal(1, "NPU result mismatch: actual=%08h expected=302c1414", result);

        write_register(5'h11, 8'b00000010);
        read_register(5'h12, read_data);
        if (read_data[1:0] !== 2'b00)
            $fatal(1, "status register did not clear done: %02h", read_data);

        $display("XINGHUO NPU MPC-FRAME UNIT TEST PASS");
        $finish;
    end
endmodule


