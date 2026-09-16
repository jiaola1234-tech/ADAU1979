`timescale 1 ns / 1 ps

module i2c_master_write8 #
(
    parameter integer CLK_HZ = 50000000,
    parameter integer I2C_HZ = 100000
)
(
    input  wire       clk,
    input  wire       rstn,

    input  wire       start,
    input  wire [6:0] dev_addr,
    input  wire [7:0] reg_addr,
    input  wire [7:0] wr_data,
    output reg        busy,
    output reg        done,
    output reg        ack_error,
    output reg [6:0]  last_dev_addr,
    output reg [7:0]  last_reg_addr,
    output reg [7:0]  last_wr_data,
    output reg [2:0]  ack_bits,
    output wire [4:0] debug_state,
    output wire [2:0] debug_byte_idx,
    output wire [2:0] debug_bit_idx,
    output reg        debug_ack_sample_pulse,
    output reg        debug_ack_sample_sda,

    input  wire       sda_i,
    output reg        scl_oe_n,
    output reg        sda_oe_n
);

    localparam integer HALF_DIV = CLK_HZ / (I2C_HZ * 2);
    localparam integer DIV_WIDTH = 16;
    localparam [DIV_WIDTH-1:0] HALF_DIV_COUNT = HALF_DIV;

    localparam [4:0] ST_IDLE      = 5'd0;
    localparam [4:0] ST_START_A   = 5'd1;
    localparam [4:0] ST_START_B   = 5'd2;
    localparam [4:0] ST_LOAD      = 5'd3;
    localparam [4:0] ST_BIT_LOW   = 5'd4;
    localparam [4:0] ST_BIT_HIGH  = 5'd5;
    localparam [4:0] ST_ACK_LOW   = 5'd6;
    localparam [4:0] ST_ACK_HIGH  = 5'd7;
    localparam [4:0] ST_NEXT      = 5'd8;
    localparam [4:0] ST_STOP_A    = 5'd9;
    localparam [4:0] ST_STOP_B    = 5'd10;
    localparam [4:0] ST_DONE      = 5'd11;

    reg [4:0] state;
    reg [DIV_WIDTH-1:0] div_cnt;
    reg tick;

    reg [7:0] byte_data;
    reg [2:0] byte_idx;
    reg [2:0] bit_idx;
    (* ASYNC_REG = "TRUE" *) reg [1:0] sda_sync;

    assign debug_state = state;
    assign debug_byte_idx = byte_idx;
    assign debug_bit_idx = bit_idx;

    always @(posedge clk) begin
        if (!rstn)
            sda_sync <= 2'b11;
        else
            sda_sync <= {sda_sync[0], sda_i};
    end

    always @(posedge clk) begin
        if (!rstn) begin
            div_cnt <= {DIV_WIDTH{1'b0}};
            tick <= 1'b0;
        end else if (busy) begin
            if (div_cnt == HALF_DIV_COUNT - 1'b1) begin
                div_cnt <= {DIV_WIDTH{1'b0}};
                tick <= 1'b1;
            end else begin
                div_cnt <= div_cnt + 1'b1;
                tick <= 1'b0;
            end
        end else begin
            div_cnt <= {DIV_WIDTH{1'b0}};
            tick <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (!rstn) begin
            state <= ST_IDLE;
            scl_oe_n <= 1'b1;
            sda_oe_n <= 1'b1;
            byte_data <= 8'd0;
            byte_idx <= 3'd0;
            bit_idx <= 3'd7;
            busy <= 1'b0;
            done <= 1'b0;
            ack_error <= 1'b0;
            last_dev_addr <= 7'd0;
            last_reg_addr <= 8'd0;
            last_wr_data <= 8'd0;
            ack_bits <= 3'd0;
            debug_ack_sample_pulse <= 1'b0;
            debug_ack_sample_sda <= 1'b1;
        end else begin
            done <= 1'b0;
            debug_ack_sample_pulse <= 1'b0;

            case (state)
                ST_IDLE: begin
                    scl_oe_n <= 1'b1;
                    sda_oe_n <= 1'b1;
                    busy <= 1'b0;
                    if (start) begin
                        busy <= 1'b1;
                        ack_error <= 1'b0;
                        last_dev_addr <= dev_addr;
                        last_reg_addr <= reg_addr;
                        last_wr_data <= wr_data;
                        ack_bits <= 3'd0;
                        byte_idx <= 3'd0;
                        state <= ST_START_A;
                    end
                end

                ST_START_A: begin
                    scl_oe_n <= 1'b1;
                    sda_oe_n <= 1'b1;
                    if (tick)
                        state <= ST_START_B;
                end

                ST_START_B: begin
                    scl_oe_n <= 1'b1;
                    sda_oe_n <= 1'b0;
                    if (tick)
                        state <= ST_LOAD;
                end

                ST_LOAD: begin
                    scl_oe_n <= 1'b0;
                    sda_oe_n <= 1'b0;
                    case (byte_idx)
                        3'd0: byte_data <= {dev_addr, 1'b0};
                        3'd1: byte_data <= reg_addr;
                        default: byte_data <= wr_data;
                    endcase
                    bit_idx <= 3'd7;
                    if (tick)
                        state <= ST_BIT_LOW;
                end

                ST_BIT_LOW: begin
                    scl_oe_n <= 1'b0;
                    sda_oe_n <= byte_data[bit_idx];
                    if (tick)
                        state <= ST_BIT_HIGH;
                end

                ST_BIT_HIGH: begin
                    scl_oe_n <= 1'b1;
                    sda_oe_n <= byte_data[bit_idx];
                    if (tick) begin
                        if (bit_idx == 3'd0)
                            state <= ST_ACK_LOW;
                        else begin
                            bit_idx <= bit_idx - 1'b1;
                            state <= ST_BIT_LOW;
                        end
                    end
                end

                ST_ACK_LOW: begin
                    scl_oe_n <= 1'b0;
                    sda_oe_n <= 1'b1;
                    if (tick)
                        state <= ST_ACK_HIGH;
                end

                ST_ACK_HIGH: begin
                    scl_oe_n <= 1'b1;
                    sda_oe_n <= 1'b1;
                    if (tick) begin
                        debug_ack_sample_pulse <= 1'b1;
                        debug_ack_sample_sda <= sda_sync[1];
                        ack_bits[byte_idx] <= !sda_sync[1];
                        if (sda_sync[1])
                            ack_error <= 1'b1;
                        state <= ST_NEXT;
                    end
                end

                ST_NEXT: begin
                    scl_oe_n <= 1'b0;
                    sda_oe_n <= 1'b1;
                    if (tick) begin
                        if (byte_idx == 3'd2)
                            state <= ST_STOP_A;
                        else begin
                            byte_idx <= byte_idx + 1'b1;
                            state <= ST_LOAD;
                        end
                    end
                end

                ST_STOP_A: begin
                    scl_oe_n <= 1'b0;
                    sda_oe_n <= 1'b0;
                    if (tick)
                        state <= ST_STOP_B;
                end

                ST_STOP_B: begin
                    scl_oe_n <= 1'b1;
                    sda_oe_n <= 1'b0;
                    if (tick) begin
                        sda_oe_n <= 1'b1;
                        state <= ST_DONE;
                    end
                end

                ST_DONE: begin
                    scl_oe_n <= 1'b1;
                    sda_oe_n <= 1'b1;
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
