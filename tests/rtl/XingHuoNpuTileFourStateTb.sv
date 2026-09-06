`timescale 1ns/1ps
// Icarus四态RTL/真实ICS55单元零延迟门级共用测试。不访问DUT内部信号。
module XingHuoNpuTileFourStateTb;
    reg clock = 0;
    always #5 clock = ~clock;
    reg reset = 1;
    reg [7:0] io_btn = 0, io_dip = 0;
    reg [15:0] io_customIn = 0;
    wire [7:0] io_led, io_ramAddr, io_ramWdata;
    wire io_ledUpdate, io_hex7segUpdate, io_ramWen;
    wire [3:0] io_hex7seg_0, io_hex7seg_1;
    wire [15:0] io_customOut;
    reg [7:0] memory [0:255]; // 故意不初始化：复位不清除SoC RAM。
    wire [7:0] io_ramRdata = memory[io_ramAddr];
    XingHuoNpuTile dut (.*);
    always @(posedge clock) if (io_ramWen) memory[io_ramAddr] <= io_ramWdata;
    reg request_toggle = 0;
    integer file_handle, fields, count, k;
    reg [31:0] activation, weight1, weight2, hidden, result;
    reg [63:0] bias1, bias2;
    reg [7:0] shift1, shift2, error_code, classification, value;
    reg [1023:0] vector_file;
    reg [1023:0] trace_file;
    initial begin
        if ($value$plusargs("trace=%s", trace_file)) begin
            $dumpfile(trace_file);
            $dumpvars(0, XingHuoNpuTileFourStateTb);
        end
    end

    task command(input [2:0] opcode, input [7:0] payload);
        integer timeout;
        begin
            io_customIn = {1'b1, 3'b0, opcode, request_toggle, payload};
            repeat (3) @(negedge clock);
            #2;
            request_toggle = ~request_toggle;
            io_customIn[8] = request_toggle;
            timeout = 0;
            while (io_customOut[8] !== request_toggle && timeout < 200) begin
                @(negedge clock);
                timeout = timeout + 1;
            end
            if (timeout == 200) $fatal(1, "four-state host timeout");
        end
    endtask
    task write_word(input [7:0] address, input [63:0] data, input integer size);
        integer n;
        begin
            command(0, address);
            for (n=0; n<size; n=n+1) command(1, data[n*8 +: 8]);
        end
    endtask
    task read_byte(input [7:0] address, output [7:0] data);
        begin
            command(0, address);
            command(2, 0);
            data = io_customOut[7:0];
        end
    endtask
    task wait_done;
        integer timeout;
        begin
            repeat (2) @(negedge clock);
            timeout = 0;
            while (io_customOut[10] !== 1'b1 && timeout < 160) begin
                @(negedge clock);
                timeout = timeout + 1;
            end
            if (timeout == 160) $fatal(1, "four-state network timeout");
        end
    endtask
    initial begin
        if (!$value$plusargs("vectors=%s", vector_file))
            vector_file = "build/sim/network_vectors.txt";
        file_handle = $fopen(vector_file, "r");
        if (!file_handle) $fatal(1, "cannot open vectors");
        repeat (4) @(negedge clock);
        reset = 0;
        io_customIn[15] = 1;
        repeat (5) @(negedge clock);
        // 未初始化RAM条件下固定Demo也必须成功，且不向结果传播X。
        command(4, 1);
        wait_done();
        read_byte(8'h40, value);
        if (value !== 0 || io_customOut[13] !== 1'b1)
            $fatal(1, "demo depends on uninitialized RAM: byte=%h status=%h hidden=%h%h%h%h output=%h%h%h%h",
                value, io_customOut, memory[8'h23], memory[8'h22], memory[8'h21], memory[8'h20],
                memory[8'h43], memory[8'h42], memory[8'h41], memory[8'h40]);
        count = 0;
        while (!$feof(file_handle)) begin
            fields = $fscanf(file_handle, "%h %h %h %h %h %h %h %h %h %h %h\n",
                activation, weight1, bias1, shift1, weight2, bias2, shift2,
                hidden, result, error_code, classification);
            if (fields != 11) $fatal(1, "malformed vector");
            write_word(8'h00, {32'b0, activation}, 4);
            write_word(8'h10, {32'b0, weight1}, 4);
            write_word(8'h14, bias1, 8);
            write_word(8'h1c, {56'b0, shift1}, 1);
            write_word(8'h30, {32'b0, weight2}, 4);
            write_word(8'h34, bias2, 8);
            write_word(8'h3c, {56'b0, shift2}, 1);
            command(3, 0);
            wait_done();
            for (k=0; k<4; k=k+1) begin
                read_byte(8'h20 + 8'(k), value);
                if (value !== hidden[k*8 +: 8])
                    $fatal(1, "four-state vector %0d hidden mismatch", count);
                read_byte(8'h40 + 8'(k), value);
                if (value !== result[k*8 +: 8])
                    $fatal(1, "four-state vector %0d output mismatch", count);
            end
            read_byte(8'h44, value);
            if (value !== classification) $fatal(1, "class mismatch");
            read_byte(8'h46, value);
            if (value !== error_code) $fatal(1, "error code mismatch");
            count = count + 1;
        end
        $fclose(file_handle);
        if (count != 160) $fatal(1, "incomplete four-state vector coverage");
        // 写入状态中途复位：RAM没有reset输入，必须由Tile屏蔽写使能。
        command(4, 1);
        wait (io_ramWen === 1'b1);
        @(negedge clock);
        reset = 1;
        #1;
        if (io_ramWen !== 1'b0) $fatal(1, "RAM write during reset");
        repeat (3) @(negedge clock);
        io_customIn = 0;
        request_toggle = 0;
        reset = 0;
        repeat (5) @(negedge clock);
        io_customIn[15] = 1;
        repeat (5) @(negedge clock);
        command(4, 0);
        wait_done();
        if (io_customOut[13] !== 0) $fatal(1, "post-reset recovery failed");
        $display("FOUR STATE TILE PASS: %0d vectors, unknown RAM, reset recovery", count);
        $finish;
    end
    initial begin
        #20000000;
        $fatal(1, "four-state test watchdog");
    end
endmodule
