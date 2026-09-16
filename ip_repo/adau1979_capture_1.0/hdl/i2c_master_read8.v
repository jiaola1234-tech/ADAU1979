`timescale 1 ns / 1 ps

// I2C register-address write followed by a repeated-start single-byte read.
// The master assumes open-drain pins and does not support clock stretching.
module i2c_master_read8 #(
    parameter integer CLK_HZ = 50000000,
    parameter integer I2C_HZ = 100000
) (
    input  wire       clk,
    input  wire       rstn,
    input  wire       start,
    input  wire [6:0] dev_addr,
    input  wire [7:0] reg_addr,
    output reg        busy,
    output reg        done,
    output reg        ack_error,
    output reg [7:0]  rd_data,
    input  wire       sda_i,
    output reg        scl_oe_n,
    output reg        sda_oe_n
);

    localparam integer HALF_DIV = CLK_HZ / (I2C_HZ * 2);
    localparam integer DIV_WIDTH = 16;
    localparam [DIV_WIDTH-1:0] HALF_DIV_COUNT = HALF_DIV;

    localparam [4:0] ST_IDLE          = 5'd0;
    localparam [4:0] ST_START_A       = 5'd1;
    localparam [4:0] ST_START_B       = 5'd2;
    localparam [4:0] ST_TX_LOAD       = 5'd3;
    localparam [4:0] ST_TX_LOW        = 5'd4;
    localparam [4:0] ST_TX_HIGH       = 5'd5;
    localparam [4:0] ST_TX_ACK_LOW    = 5'd6;
    localparam [4:0] ST_TX_ACK_HIGH   = 5'd7;
    localparam [4:0] ST_RESTART_A     = 5'd8;
    localparam [4:0] ST_RESTART_B     = 5'd9;
    localparam [4:0] ST_RX_LOW        = 5'd10;
    localparam [4:0] ST_RX_HIGH       = 5'd11;
    localparam [4:0] ST_RX_NACK_LOW  = 5'd12;
    localparam [4:0] ST_RX_NACK_HIGH = 5'd13;
    localparam [4:0] ST_STOP_A        = 5'd14;
    localparam [4:0] ST_STOP_B        = 5'd15;
    localparam [4:0] ST_DONE          = 5'd16;

    reg [4:0] state;
    reg [DIV_WIDTH-1:0] div_cnt;
    reg tick;
    reg [7:0] byte_data;
    reg [1:0] tx_idx;
    reg [2:0] bit_idx;
    (* ASYNC_REG = "TRUE" *) reg [1:0] sda_sync;

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
            busy <= 1'b0;
            done <= 1'b0;
            ack_error <= 1'b0;
            rd_data <= 8'd0;
            scl_oe_n <= 1'b1;
            sda_oe_n <= 1'b1;
            byte_data <= 8'd0;
            tx_idx <= 2'd0;
            bit_idx <= 3'd7;
        end else begin
            done <= 1'b0;

            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    scl_oe_n <= 1'b1;
                    sda_oe_n <= 1'b1;
                    if (start) begin
                        busy <= 1'b1;
                        ack_error <= 1'b0;
                        rd_data <= 8'd0;
                        tx_idx <= 2'd0;
                        bit_idx <= 3'd7;
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
                        state <= ST_TX_LOAD;
                end

                ST_TX_LOAD: begin
                    scl_oe_n <= 1'b0;
                    sda_oe_n <= 1'b0;
                    case (tx_idx)
                        2'd0: byte_data <= {dev_addr, 1'b0};
                        2'd1: byte_data <= reg_addr;
                        default: byte_data <= {dev_addr, 1'b1};
                    endcase
                    bit_idx <= 3'd7;
                    if (tick)
                        state <= ST_TX_LOW;
                end

                ST_TX_LOW: begin
                    scl_oe_n <= 1'b0;
                    sda_oe_n <= byte_data[bit_idx];
                    if (tick)
                        state <= ST_TX_HIGH;
                end

                ST_TX_HIGH: begin
                    scl_oe_n <= 1'b1;
                    sda_oe_n <= byte_data[bit_idx];
                    if (tick) begin
                        if (bit_idx == 3'd0)
                            state <= ST_TX_ACK_LOW;
                        else begin
                            bit_idx <= bit_idx - 1'b1;
                            state <= ST_TX_LOW;
                        end
                    end
                end

                ST_TX_ACK_LOW: begin
                    scl_oe_n <= 1'b0;
                    sda_oe_n <= 1'b1;
                    if (tick)
                        state <= ST_TX_ACK_HIGH;
                end

                ST_TX_ACK_HIGH: begin
                    scl_oe_n <= 1'b1;
                    sda_oe_n <= 1'b1;
                    if (tick) begin
                        if (sda_sync[1]) begin
                            ack_error <= 1'b1;
                            state <= ST_STOP_A;
                        end else if (tx_idx == 2'd0) begin
                            tx_idx <= 2'd1;
                            state <= ST_TX_LOAD;
                        end else if (tx_idx == 2'd1) begin
                            state <= ST_RESTART_A;
                        end else begin
                            bit_idx <= 3'd7;
                            state <= ST_RX_LOW;
                        end
                    end
                end

                ST_RESTART_A: begin
                    scl_oe_n <= 1'b1;
                    sda_oe_n <= 1'b1;
                    if (tick)
                        state <= ST_RESTART_B;
                end

                ST_RESTART_B: begin
                    scl_oe_n <= 1'b1;
                    sda_oe_n <= 1'b0;
                    if (tick) begin
                        tx_idx <= 2'd2;
                        state <= ST_TX_LOAD;
                    end
                end

                ST_RX_LOW: begin
                    scl_oe_n <= 1'b0;
                    sda_oe_n <= 1'b1;
                    if (tick)
                        state <= ST_RX_HIGH;
                end

                ST_RX_HIGH: begin
                    scl_oe_n <= 1'b1;
                    sda_oe_n <= 1'b1;
                    if (tick) begin
                        rd_data[bit_idx] <= sda_sync[1];
                        if (bit_idx == 3'd0)
                            state <= ST_RX_NACK_LOW;
                        else begin
                            bit_idx <= bit_idx - 1'b1;
                            state <= ST_RX_LOW;
                        end
                    end
                end

                // One-byte read: the master terminates with NACK.
                ST_RX_NACK_LOW: begin
                    scl_oe_n <= 1'b0;
                    sda_oe_n <= 1'b1;
                    if (tick)
                        state <= ST_RX_NACK_HIGH;
                end

                ST_RX_NACK_HIGH: begin
                    scl_oe_n <= 1'b1;
                    sda_oe_n <= 1'b1;
                    if (tick)
                        state <= ST_STOP_A;
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
                    busy <= 1'b0;
                    done <= 1'b1;
                    scl_oe_n <= 1'b1;
                    sda_oe_n <= 1'b1;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
