module XingHuoNpuTileTb;
    import XorExpectedPkg::*;
    localparam time HALF_PERIOD = 5ns;

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
    logic [7:0] host_memory [0:255];

    // 官方构建仍会生成UserDesignDut并单独检查接口；功能测试直接实例化用户模块，
    // 因而同一测试也能由本项目自己的Makefile复用。
    XingHuoNpuTile dut (.*);

    initial begin
        clock = 1'b0;
        forever #(HALF_PERIOD) clock = ~clock;
    end
    always_comb io_ramRdata = host_memory[io_ramAddr];
    always_ff @(posedge clock) begin
        if (io_ramWen) host_memory[io_ramAddr] <= io_ramWdata;
    end

    // 第二个实例把去抖时间缩短，仅用于可行时间内验证完整手动交互。
    logic [7:0] manual_btn = '0;
    logic [7:0] manual_dip = '0;
    logic [15:0] manual_custom_in = '0;
    wire [7:0] manual_led;
    wire manual_led_update;
    wire [3:0] manual_hex0;
    wire [3:0] manual_hex1;
    wire manual_hex_update;
    wire [15:0] manual_custom_out;
    wire [7:0] manual_ram_addr;
    wire manual_ram_wen;
    wire [7:0] manual_ram_wdata;
    logic [7:0] manual_ram_rdata;
    logic [7:0] manual_memory [0:255];

    XingHuoNpuTile #(.BUTTON_DEBOUNCE_CYCLES(2)) manual_dut (
        .clock(clock), .reset(reset),
        .io_led(manual_led), .io_ledUpdate(manual_led_update),
        .io_btn(manual_btn), .io_dip(manual_dip),
        .io_hex7seg_0(manual_hex0), .io_hex7seg_1(manual_hex1),
        .io_hex7segUpdate(manual_hex_update),
        .io_customOut(manual_custom_out), .io_customIn(manual_custom_in),
        .io_ramAddr(manual_ram_addr), .io_ramWen(manual_ram_wen),
        .io_ramWdata(manual_ram_wdata), .io_ramRdata(manual_ram_rdata)
    );

    always_comb manual_ram_rdata = manual_memory[manual_ram_addr];
    always_ff @(posedge clock) begin
        if (manual_ram_wen)
            manual_memory[manual_ram_addr] <= manual_ram_wdata;
    end

    logic host_request = 1'b0;

    task automatic host_command(input logic [2:0] opcode, input logic [7:0] payload);
        integer timeout;
        begin
            // 数据先稳定三个目标时钟，再在非采样边沿翻转请求。
            io_customIn = {1'b1, 3'b000, opcode, host_request, payload};
            repeat (3) @(negedge clock);
            #2ns;
            host_request = ~host_request;
            io_customIn = {1'b1, 3'b000, opcode, host_request, payload};
            timeout = 0;
            while ((io_customOut[8] !== host_request) && timeout < 200) begin
                @(posedge clock);
                #1ns;
                timeout = timeout + 1;
            end
            if (timeout == 200) $fatal(1, "external request was not acknowledged");
        end
    endtask

    task automatic host_set_address(input logic [7:0] address);
        host_command(3'd0, address);
    endtask

    task automatic host_write(input logic [7:0] value);
        begin
            host_command(3'd1, value);
            // ACK已表示写入完成；这一拍仅为正常主机处理间隔。
            @(posedge clock);
            #1ns;
        end
    endtask

    task automatic host_write_word(input logic [7:0] address,
                                   input logic [63:0] value, input integer size);
        host_set_address(address);
        for (integer byte_number=0; byte_number<size; byte_number++)
            host_write(value[byte_number*8 +: 8]);
    endtask

    task automatic check_network_vector(input NetworkVector v, input integer number);
        logic [7:0] value;
        host_write_word(8'h00, {32'b0, v.activation}, 4);
        host_write_word(8'h10, {32'b0, v.weight1}, 4);
        host_write_word(8'h14, v.bias1, 8);
        host_write_word(8'h1c, {56'b0, v.shift1}, 1);
        host_write_word(8'h30, {32'b0, v.weight2}, 4);
        host_write_word(8'h34, v.bias2, 8);
        host_write_word(8'h3c, {56'b0, v.shift2}, 1);
        host_command(3'd3, 0);
        // START的ACK之后等待busy，避免上次任务的sticky done造成假通过。
        repeat (2) @(negedge clock);
        if (!io_customOut[9] || io_customOut[10])
            $fatal(1, "network %0d did not start", number);
        wait_host_done();
        for (integer byte_number=0; byte_number<4; byte_number++) begin
            host_read(8'h20 + 8'(byte_number), value);
            if (value !== v.hidden[byte_number*8 +: 8])
                $fatal(1, "network %0d hidden byte %0d mismatch", number, byte_number);
            host_read(8'h40 + 8'(byte_number), value);
            if (value !== v.result[byte_number*8 +: 8])
                $fatal(1, "network %0d result byte %0d mismatch", number, byte_number);
        end
        host_read(8'h44, value);
        if (value !== {7'b0, v.classification} || io_customOut[13] !== v.classification)
            $fatal(1, "network %0d classification mismatch", number);
        host_read(8'h45, value);
        if (value !== (8'h01 | ((v.error_code != 0) ? 8'h04 : 8'h00)))
            $fatal(1, "network %0d status mismatch", number);
        host_read(8'h46, value);
        if (value !== v.error_code || io_customOut[12] !== (v.error_code != 0))
            $fatal(1, "network %0d error mismatch", number);
    endtask

    task automatic reset_tiles;
        @(negedge clock);
        reset = 1;
        io_customIn = 0;
        manual_custom_in = 0;
        manual_btn = 0;
        io_btn = 0;
        host_request = 0;
        repeat (3) @(negedge clock);
        if (io_ramWen || manual_ram_wen || io_customOut[10:8] != 0)
            $fatal(1, "reset did not clear transaction state");
        reset = 0;
        repeat (5) @(negedge clock);
    endtask

    // 观察已发出的手动事务，确保模式切换不会丢弃已接受的写入/启动。
    integer observed_manual_writes;
    integer observed_manual_starts;
    initial begin
        observed_manual_writes = 0;
        observed_manual_starts = 0;
    end
    always @(posedge clock) begin
        if (!reset && manual_dut.manual_ram_write_request) begin
            observed_manual_writes++;
            if (!manual_ram_wen || manual_ram_addr !== manual_dut.manual_ram_address
                || manual_ram_wdata !== manual_dut.manual_ram_write_data)
                $fatal(1, "mode switch discarded an accepted manual RAM write");
        end
        if (!reset && manual_dut.manual_start_demo) begin
            observed_manual_starts++;
            if (!manual_dut.controller_start_demo)
                $fatal(1, "mode switch discarded an accepted manual start");
        end
    end

    task automatic host_start_demo(input logic [1:0] xor_input);
        host_command(3'd4, {6'b0, xor_input});
    endtask

    task automatic host_read(input logic [7:0] address, output logic [7:0] value);
        begin
            host_set_address(address);
            host_command(3'd2, 8'h00);
            value = io_customOut[7:0];
        end
    endtask

    task automatic program_host_xor_01;
        integer byte_number;
        logic [7:0] weight1 [0:3];
        logic [7:0] weight2 [0:3];
        begin
            weight1[0]=8'h01; weight1[1]=8'hff;
            weight1[2]=8'hff; weight1[3]=8'h01;
            weight2[0]=8'hff; weight2[1]=8'h01;
            weight2[2]=8'hff; weight2[3]=8'h01;
            host_set_address(8'h00);
            host_write(8'h00); host_write(8'h01);
            host_write(8'h00); host_write(8'h00);
            host_set_address(8'h10);
            for (byte_number=0; byte_number<4; byte_number=byte_number+1)
                host_write(weight1[byte_number]);
            host_set_address(8'h14);
            for (byte_number=0; byte_number<8; byte_number=byte_number+1)
                host_write(8'h00);
            host_set_address(8'h1c); host_write(8'h00);
            host_set_address(8'h30);
            for (byte_number=0; byte_number<4; byte_number=byte_number+1)
                host_write(weight2[byte_number]);
            host_set_address(8'h34); host_write(8'h01);
            for (byte_number=1; byte_number<8; byte_number=byte_number+1)
                host_write(8'h00);
            host_set_address(8'h3c); host_write(8'h00);
        end
    endtask

    task automatic wait_host_done;
        integer timeout;
        begin
            timeout = 0;
            while (!io_customOut[10] && timeout < 160) begin
                @(posedge clock);
                #1ns;
                timeout = timeout + 1;
            end
            if (timeout == 160) $fatal(1, "XOR network timed out in external mode");
        end
    endtask

    task automatic check_demo(
        input logic [1:0] xor_input,
        input logic expected_class,
        input logic [31:0] expected_result
    );
        begin
            host_start_demo(xor_input);
            wait_host_done();
            if (io_customOut[13] !== expected_class)
                $fatal(1, "wrong XOR class for input %b", xor_input);
            if ({host_memory[8'h43], host_memory[8'h42],
                 host_memory[8'h41], host_memory[8'h40]} !== expected_result)
                $fatal(1, "wrong XOR matrix output for input %b", xor_input);
            host_command(3'd5, 8'h00);
            @(posedge clock);
            #1ns;
        end
    endtask

    task automatic manual_press(input integer index);
        begin
            manual_btn[index] = 1'b1;
            repeat (7) @(posedge clock);
            #1ns;
            manual_btn[index] = 1'b0;
            repeat (7) @(posedge clock);
            #1ns;
        end
    endtask

    task automatic manual_set_address(input logic [7:0] address);
        begin
            manual_dip = address;
            manual_press(2);
        end
    endtask

    task automatic manual_write(input logic [7:0] value);
        begin
            manual_dip = value;
            manual_press(0);
        end
    endtask

    task automatic manual_wait_done;
        integer timeout;
        begin
            timeout = 0;
            while (!manual_custom_out[10] && timeout < 180) begin
                @(posedge clock);
                #1ns;
                timeout = timeout + 1;
            end
            if (timeout == 180) $fatal(1, "XOR network timed out in manual mode");
        end
    endtask

    task automatic check_manual_demo(
        input logic [1:0] xor_input,
        input logic expected_class,
        input logic [31:0] expected_result
    );
        begin
            manual_press(6);
            manual_dip = {6'b0, xor_input};
            manual_press(7);
            manual_wait_done();
            if (manual_custom_out[13] !== expected_class)
                $fatal(1, "wrong manual XOR class for input %b", xor_input);
            if ({manual_memory[8'h43], manual_memory[8'h42],
                 manual_memory[8'h41], manual_memory[8'h40]} !== expected_result)
                $fatal(1, "wrong manual XOR output for input %b", xor_input);
        end
    endtask

    task automatic program_manual_xor_01;
        integer index;
        logic [7:0] weight1 [0:3];
        logic [7:0] weight2 [0:3];
        begin
            weight1[0]=8'h01; weight1[1]=8'hff;
            weight1[2]=8'hff; weight1[3]=8'h01;
            weight2[0]=8'hff; weight2[1]=8'h01;
            weight2[2]=8'hff; weight2[3]=8'h01;

            manual_set_address(8'h00);
            manual_write(8'h00); manual_write(8'h01);
            manual_write(8'h00); manual_write(8'h00);
            manual_set_address(8'h10);
            for (index=0; index<4; index=index+1) manual_write(weight1[index]);
            manual_set_address(8'h14);
            for (index=0; index<8; index=index+1) manual_write(8'h00);
            manual_set_address(8'h1c); manual_write(8'h00);
            manual_set_address(8'h30);
            for (index=0; index<4; index=index+1) manual_write(weight2[index]);
            manual_set_address(8'h34);
            manual_write(8'h01);
            for (index=1; index<8; index=index+1) manual_write(8'h00);
            manual_set_address(8'h3c); manual_write(8'h00);
        end
    endtask

    integer index;
    logic [7:0] readback;
    initial begin
        for (index=0; index<256; index=index+1) begin
            host_memory[index] = 8'(index) ^ 8'ha5;
            manual_memory[index] = 8'(index) ^ 8'h5a;
        end

        repeat (3) @(posedge clock);
        #1ns;
        reset = 1'b0;
        repeat (5) @(posedge clock);
        #1ns;

        // External Host Mode：模式请求、读写握手和四种固定XOR输入。
        io_customIn[15] = 1'b1;
        repeat (5) @(posedge clock);
        #1ns;
        if (!io_customOut[14]) $fatal(1, "external mode was not selected");

        host_set_address(8'h80);
        host_write(8'h5a);
        if (host_memory[8'h80] !== 8'h5a)
            $fatal(1, "external sequential RAM write failed");
        host_set_address(8'h80);
        host_command(3'd2, 8'h00);
        if (io_customOut[7:0] !== 8'h5a)
            $fatal(1, "external RAM read failed");

        // 外部设备逐字节写入完整两层网络参数并自动运行。
        program_host_xor_01();
        host_command(3'd3, 8'h00);
        wait_host_done();
        if (io_customOut[13] !== XOR_CLASS_01
            || {host_memory[8'h43], host_memory[8'h42],
                host_memory[8'h41], host_memory[8'h40]} !== XOR_OUTPUT_01)
            $fatal(1, "external programmable XOR failed");
        // 结果必须能通过协议读取，不能只依赖Testbench窥视RAM。
        for (index=0; index<4; index=index+1) begin
            host_read(8'h20 + index[7:0], readback);
            if (readback !== XOR_HIDDEN_01[index*8 +: 8])
                $fatal(1, "external hidden-result readback failed");
            host_read(8'h40 + index[7:0], readback);
            if (readback !== XOR_OUTPUT_01[index*8 +: 8])
                $fatal(1, "external final-result readback failed");
        end
        host_command(3'd5, 8'h00);

        check_demo(2'b00, XOR_CLASS_00, XOR_OUTPUT_00);
        check_demo(2'b01, XOR_CLASS_01, XOR_OUTPUT_01);
        check_demo(2'b10, XOR_CLASS_10, XOR_OUTPUT_10);
        check_demo(2'b11, XOR_CLASS_11, XOR_OUTPUT_11);

        // Manual Mode：逐字节输入完整两层参数，然后只按一次BTN3自动运行。
        program_manual_xor_01();
        manual_press(3);
        manual_wait_done();
        if (manual_custom_out[13] !== 1'b1)
            $fatal(1, "manual programmable XOR classification failed");
        if ({manual_memory[8'h43], manual_memory[8'h42],
             manual_memory[8'h41], manual_memory[8'h40]} !== XOR_OUTPUT_01)
            $fatal(1, "manual programmable XOR output failed");

        // 页面0必须直接显示分类、done和状态，Update依照契约持续有效。
        if (!manual_led_update || !manual_hex_update
            || manual_led[0] !== 1'b1 || manual_led[1] !== 1'b1)
            $fatal(1, "manual LED/status display is incorrect");
        manual_press(4);
        if ({manual_hex1, manual_hex0} !== manual_ram_addr)
            $fatal(1, "manual address display page is incorrect");

        // 固定参数Demo通过同一个按键流程验证完整XOR真值表。
        check_manual_demo(2'b00, XOR_CLASS_00, XOR_OUTPUT_00);
        check_manual_demo(2'b01, XOR_CLASS_01, XOR_OUTPUT_01);
        check_manual_demo(2'b10, XOR_CLASS_10, XOR_OUTPUT_10);
        check_manual_demo(2'b11, XOR_CLASS_11, XOR_OUTPUT_11);

        // busy期间提出模式切换请求，必须延迟到完整两层网络结束。
        manual_press(6);
        manual_dip = 8'h01;
        manual_press(7);
        if (!manual_custom_out[9]) $fatal(1, "manual demo did not become busy");
        manual_custom_in[15] = 1'b1;
        repeat (8) begin
            @(posedge clock); #1ns;
            if (manual_custom_out[9] && manual_custom_out[14])
                $fatal(1, "mode changed while network was busy");
        end
        manual_wait_done();
        repeat (4) @(posedge clock);
        #1ns;
        if (!manual_custom_out[14])
            $fatal(1, "deferred external-mode request was not applied at idle");

        // 所有数据均通过外部协议写入/读回；连续任务检验旧结果与错误不泄漏。
        for (index=0; index<NETWORK_CASES; index++)
            check_network_vector(NETWORK_VECTORS[index], index);
        $display("TWO-LAYER GOLDEN MODEL PASS: %0d cases", NETWORK_CASES);

        host_set_address(8'hff);
        host_write(8'hc3);
        host_write(8'h3c);
        host_set_address(8'hff);
        host_command(3'd2, 0);
        if (io_customOut[7:0] !== 8'hc3) $fatal(1, "read ff failed");
        host_command(3'd2, 0);
        if (io_customOut[7:0] !== 8'h3c) $fatal(1, "address wrap failed");

        // 忙时请求保持到空闲后处理；不得在网络独占RAM时提前应答或写入。
        host_set_address(8'h90);
        host_start_demo(2'b01);
        fork
            host_write(8'h69);
            begin
                repeat (4) @(negedge clock);
                if (!io_customOut[9]) $fatal(1, "busy command test missed busy");
                while (io_customOut[9]) begin
                    if (io_customOut[8] === host_request)
                        $fatal(1, "busy request acknowledged before idle");
                    @(negedge clock);
                end
            end
        join
        if (host_memory[8'h90] !== 8'h69) $fatal(1, "deferred write lost");

        // 在每一个计算阶段中断并重新运行，RAM不复位。
        for (integer offset=0; offset<85; offset++) begin
            reset_tiles();
            io_customIn[15] = 1;
            repeat (5) @(negedge clock);
            program_host_xor_01();
            host_command(3'd3, 0);
            repeat (offset) @(negedge clock);
            reset_tiles();
            io_customIn[15] = 1;
            repeat (5) @(negedge clock);
            check_demo(2'b10, XOR_CLASS_10, XOR_OUTPUT_10);
        end

        // 扫描去抖按钮与模式请求的相对时序，包括接受事务的同一拍。
        for (integer button_number=0; button_number<=7; button_number+=7) begin
            for (integer offset=0; offset<12; offset++) begin
                reset_tiles();
                manual_dip = 8'h01;
                repeat (4) @(negedge clock);
                fork
                    manual_press(button_number);
                    begin
                        repeat (offset) @(negedge clock);
                        #1ns;
                        manual_custom_in[15] = 1;
                    end
                join
                repeat (100) @(negedge clock);
                if (!manual_custom_out[14]) $fatal(1, "mode handover stalled");
            end
        end
        if (observed_manual_writes == 0 || observed_manual_starts == 0)
            $fatal(1, "manual boundary coverage was empty");
        $display("TILE BOUNDARY PASS: wrap, busy request, 85 reset offsets, 24 mode offsets");
        $display("XINGHUO NPU TILE UNIT TEST PASS");
        $finish;
    end
endmodule
