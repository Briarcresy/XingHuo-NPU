// 将有限的LED和两个十六进制数码管组织成多个可翻页的观察窗口。
module DisplayController (
    input  logic        external_mode,
    input  logic [ 3:0] display_page,
    input  logic [ 7:0] manual_address,
    input  logic [ 7:0] current_ram_data,
    input  logic        network_busy,
    input  logic        core_busy,
    input  logic        done,
    input  logic        error,
    input  logic        classification,
    input  logic [31:0] hidden_result,
    input  logic [31:0] final_result,
    output logic [ 7:0] led_value,
    output logic [ 3:0] hex_low,
    output logic [ 3:0] hex_high
);
    always_comb begin
        led_value = 8'h00;
        hex_low   = display_page;
        hex_high  = 4'h0;

        case (display_page)
            4'd0: begin
                led_value = {
                    2'b00, external_mode, error, core_busy, network_busy, done, classification
                };
                hex_low = {3'b000, classification};
                hex_high = 4'h0;
            end
            4'd1: begin
                led_value = current_ram_data;
                hex_low   = manual_address[3:0];
                hex_high  = manual_address[7:4];
            end
            4'd2: led_value = hidden_result[7:0];
            4'd3: led_value = hidden_result[15:8];
            4'd4: led_value = hidden_result[23:16];
            4'd5: led_value = hidden_result[31:24];
            4'd6: led_value = final_result[7:0];
            4'd7: led_value = final_result[15:8];
            4'd8: led_value = final_result[23:16];
            4'd9: led_value = final_result[31:24];
            4'd10: begin
                led_value = {7'b0, classification};
                hex_low   = {3'b000, classification};
                hex_high  = 4'hc;
            end
            default: begin
            end
        endcase
    end
endmodule
