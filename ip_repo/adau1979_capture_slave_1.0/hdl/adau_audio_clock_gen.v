`timescale 1 ns / 1 ps

// Fractional-N audio clock source for the two ADAU1979 serial ports.
// The phase accumulator gives an exact average output frequency from the
// AXI clock; LRCLK is derived from BCLK so the two clocks stay coherent.
module adau_audio_clock_gen #(
    parameter integer CLK_HZ  = 100000000,
    parameter integer BCLK_HZ = 3072000
)(
    input  wire clk,
    input  wire rstn,
    input  wire enable,
    output wire bclk,
    output reg  lrclk
);

    localparam [63:0] PHASE_INC_CALC =
        ((64'd4294967296 * BCLK_HZ) + (CLK_HZ / 2)) / CLK_HZ;
    localparam [31:0] PHASE_INC = PHASE_INC_CALC[31:0];

    reg [31:0] phase;
    reg        bclk_d;
    reg [5:0]  bclk_rise_count;

    assign bclk = enable ? phase[31] : 1'b0;

    always @(posedge clk) begin
        if (!rstn) begin
            phase          <= 32'd0;
            bclk_d         <= 1'b0;
            bclk_rise_count <= 6'd0;
            lrclk         <= 1'b0;
        end else if (!enable) begin
            phase          <= 32'd0;
            bclk_d         <= 1'b0;
            bclk_rise_count <= 6'd0;
            lrclk         <= 1'b0;
        end else begin
            phase  <= phase + PHASE_INC;
            bclk_d <= phase[31];

            // Toggle LRCLK every 32 BCLK rising edges: 3.072 MHz / 64.
            if (!bclk_d && phase[31]) begin
                if (bclk_rise_count == 6'd31) begin
                    bclk_rise_count <= 6'd0;
                    lrclk <= ~lrclk;
                end else begin
                    bclk_rise_count <= bclk_rise_count + 1'b1;
                end
            end
        end
    end

endmodule
