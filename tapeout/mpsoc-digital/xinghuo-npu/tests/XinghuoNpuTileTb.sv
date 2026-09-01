module XinghuoNpuTileTb;

  localparam time HALF_PERIOD = 5ns;

  logic clock = 1'b0;
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
  wire [7:0] io_ramRdata;

  logic [7:0] memory [0:255];
  assign io_ramRdata = memory[io_ramAddr];

  always #(HALF_PERIOD) clock = ~clock;
  always_ff @(posedge clock)
    if (io_ramWen)
      memory[io_ramAddr] <= io_ramWdata;

  UserDesignDut dut (.*);

  task automatic host_command(input logic [1:0] opcode, input logic [7:0] payload);
    logic next_toggle;
    begin
      next_toggle = ~io_customIn[8];
      @(negedge clock);
      io_customIn[7:0] = payload;
      io_customIn[10:9] = opcode;
      repeat (2) @(posedge clock);
      @(negedge clock);
      io_customIn[8] = next_toggle;
      wait (io_customOut[8] == next_toggle);
      @(negedge clock);
    end
  endtask

  task automatic host_write(input logic [7:0] data);
    begin
      host_command(2'b01, data);
    end
  endtask

  initial begin
    repeat (3) @(posedge clock);
    @(negedge clock);
    reset = 1'b0;

    // A=[[1,2],[3,4]], W=[[5,6],[7,8]], bias={1,-2}, shift=0。
    host_command(2'b00, 8'h00);
    host_write(8'h01);
    host_write(8'h02);
    host_write(8'h03);
    host_write(8'h04);
    host_write(8'h05);
    host_write(8'h06);
    host_write(8'h07);
    host_write(8'h08);
    host_write(8'h01);
    host_write(8'h00);
    host_write(8'h00);
    host_write(8'h00);
    host_write(8'hFE);
    host_write(8'hFF);
    host_write(8'hFF);
    host_write(8'hFF);
    host_write(8'h00);

    host_command(2'b11, 8'h01);
    wait (io_customOut[10]);
    @(posedge clock);
    #1ns;

    if ({memory[8'h23], memory[8'h22], memory[8'h21], memory[8'h20]} !== 32'h302C1414)
      $fatal(1, "NPU result in shared RAM is incorrect");
    if (io_customOut[9] || !io_ledUpdate || !io_hex7segUpdate)
      $fatal(1, "Tile status outputs are incorrect");

    $display("XINGHUO NPU TILE UNIT TEST PASS");
    $finish;
  end

endmodule
