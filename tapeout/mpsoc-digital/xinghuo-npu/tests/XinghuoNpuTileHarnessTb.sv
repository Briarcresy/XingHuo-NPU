module XinghuoNpuTileHarnessTb;

  localparam time HALF_PERIOD = 5ns;

  logic clock = 1'b0;
  logic reset = 1'b1;
  logic [7:0] btn = '0;
  logic [7:0] dip = '0;
  logic [15:0] custom_in = '0;
  wire [7:0] led;
  wire [3:0] hex7seg_0;
  wire [3:0] hex7seg_1;
  wire [15:0] custom_out;

  always #(HALF_PERIOD) clock = ~clock;

  MPSoCDigitalHarness dut (.*);

  task automatic host_command(input logic [1:0] opcode, input logic [7:0] payload);
    logic next_toggle;
    begin
      next_toggle = ~custom_in[8];
      @(negedge clock);
      custom_in[7:0] = payload;
      custom_in[10:9] = opcode;
      repeat (2) @(posedge clock);
      @(negedge clock);
      custom_in[8] = next_toggle;
      wait (custom_out[8] == next_toggle);
      @(negedge clock);
    end
  endtask

  task automatic host_read_check(input logic [7:0] address, input logic [7:0] expected);
    begin
      host_command(2'b00, address);
      #1ns;
      if (custom_out[7:0] !== expected)
        $fatal(1, "shared RAM read mismatch at address 0x%02x", address);
    end
  endtask

  initial begin
    repeat (3) @(posedge clock);
    #1ns;
    // 官方 Harness 在 reset 期间把 LED/数码管保持寄存器清零；custom_out
    // 则直接来自 Tile，因此仍可检查接口版本。
    if (led !== 8'h00 || custom_out[15:12] !== 4'b0001)
      $fatal(1, "Tile reset/interface version behavior is incorrect");

    @(negedge clock);
    reset = 1'b0;

    // 验证真实 harness 中的 Tile -> 共享 RAM 写、RAM -> Tile 异步读通路。
    host_command(2'b00, 8'h55);
    host_command(2'b01, 8'hA6);
    host_read_check(8'h55, 8'hA6);

    if (custom_out[9] || custom_out[10])
      $fatal(1, "idle status is incorrect");

    $display("XINGHUO NPU TILE HARNESS TEST PASS");
    $finish;
  end

endmodule
