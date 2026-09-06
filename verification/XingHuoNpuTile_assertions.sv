module XingHuoNpuTile_assertions (
    input logic        clock,
    input logic        reset,
    input logic [15:0] io_customOut,
    input logic [ 7:0] io_ramAddr,
    input logic        io_ramWen,
    input logic [ 7:0] io_ramWdata,
    input logic [ 7:0] io_led,
    input logic        io_ledUpdate,
    input logic [ 3:0] io_hex7seg_0,
    input logic [ 3:0] io_hex7seg_1,
    input logic        io_hex7segUpdate,
    input logic        manual_ram_write_request,
    input logic        host_ram_write_request,
    input logic        manual_start_programmable,
    input logic        manual_start_demo,
    input logic        host_start_programmable,
    input logic        host_start_demo,
    input logic        controller_start_programmable,
    input logic        controller_start_demo
);
    wire network_busy = io_customOut[9];
    wire network_done = io_customOut[10];
    wire external_mode = io_customOut[14];

    assert property (@(posedge clock) reset |=> !io_ramWen)
        else $error("reset did not suppress RAM writes");

    assert property (@(posedge clock) reset |-> !io_ramWen)
        else $error("RAM write leaked into reset sampling edge");

    assert property (@(posedge clock) disable iff (reset)
        manual_ram_write_request |-> (!external_mode && io_ramWen))
        else $error("manual write lost during mode handover");
    assert property (@(posedge clock) disable iff (reset)
        host_ram_write_request |-> (external_mode && io_ramWen))
        else $error("host write lost during mode handover");
    assert property (@(posedge clock) disable iff (reset)
        (manual_start_programmable || manual_start_demo) |-> !external_mode)
        else $error("manual start lost during mode handover");
    assert property (@(posedge clock) disable iff (reset)
        (host_start_programmable || host_start_demo) |-> external_mode)
        else $error("host start lost during mode handover");
    assert property (@(posedge clock) disable iff (reset)
        (!network_busy && (controller_start_programmable || controller_start_demo))
        |=> network_busy)
        else $error("accepted network start did not become busy");

    assert property (@(posedge clock) disable iff (reset)
        network_done |-> !network_busy)
        else $error("network done and busy are asserted together");

    assert property (@(posedge clock) disable iff (reset)
        $past(network_busy) |-> $stable(external_mode))
        else $error("input mode changed while the network was busy");

    // 网络运行期间只允许写隐藏值、最终输出、类别、状态和错误区域。
    assert property (@(posedge clock) disable iff (reset)
        (network_busy && io_ramWen) |->
        (((io_ramAddr >= 8'h20) && (io_ramAddr <= 8'h23))
        || ((io_ramAddr >= 8'h40) && (io_ramAddr <= 8'h46))))
        else $error("network controller wrote outside its RAM result regions");

    assert property (@(posedge clock)
        !$isunknown({io_customOut, io_ramAddr, io_ramWen, io_ramWdata,
                     io_led, io_ledUpdate, io_hex7seg_0,
                     io_hex7seg_1, io_hex7segUpdate}))
        else $error("Tile output contains X or Z");
endmodule

bind XingHuoNpuTile XingHuoNpuTile_assertions tile_assertions (.*);
