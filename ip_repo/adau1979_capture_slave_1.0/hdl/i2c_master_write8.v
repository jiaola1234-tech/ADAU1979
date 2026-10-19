`timescale 1 ns / 1 ps

module i2c_master_write8 #
(
    parameter integer CLK_HZ = 50000000,
    parameter integer I2C_HZ = 100000,
    // 1 = abort the frame on a NACK; 0 = keep clocking the complete
    // address/register/data frame and only expose the sampled ACK bits for
    // diagnostics.  Bring-up can use 0 when the device ACK line is being
    // investigated and writes must continue regardless of ACK.
    parameter integer CHECK_ACK = 1
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
    // I2C bus clear (bus recovery): nine SCL pulses with SDA released, then a
    // STOP.  Entered only when SDA is still low while the bus should be idle,
    // i.e. when a slave did not release it.  Without this the design has no way
    // to recover and every following transaction fails in exactly the same way.
    localparam [4:0] ST_BC_LOW    = 5'd12;
    localparam [4:0] ST_BC_HIGH   = 5'd13;
    localparam [4:0] ST_BC_STOP_A = 5'd14;
    localparam [4:0] ST_BC_STOP_B = 5'd15;
    // A complete write transaction is retried up to three times when any
    // of its three ACK slots is NACKed.  The retry starts only after a STOP,
    // so the slave always sees a clean transaction boundary.
    localparam [4:0] ST_RETRY_WAIT = 5'd16;
    localparam integer MAX_ATTEMPTS = 3;

    reg [4:0] state;
    reg [DIV_WIDTH-1:0] div_cnt;
    reg tick;

    reg [7:0] byte_data;
    reg [2:0] byte_idx;
    reg [2:0] bit_idx;
    reg [3:0] bc_cnt;
    reg [1:0] attempt_count;
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
            bc_cnt <= 4'd0;
            attempt_count <= 2'd0;
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
                        attempt_count <= 2'd0;
                        byte_idx <= 3'd0;
                        // Bus health check: the master has released SDA at this
                        // point, so a low level means someone else is holding
                        // the bus.  Recover it before issuing the real START.
                        if (!sda_sync[1]) begin
                            bc_cnt <= 4'd0;
                            state <= ST_BC_LOW;
                        end else begin
                            state <= ST_START_A;
                        end
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
                        // Standard 100 kHz ninth clock: one tick (5 us) high,
                        // exactly like the eight data bits, with SDA sampled at
                        // the end of that single high phase.  The earlier "ACK
                        // timing experiment" stretched this phase to two ticks
                        // (10 us) to push the sample point later; it has been
                        // reverted so the bus carries a uniform 100 kHz
                        // waveform again.
                        debug_ack_sample_pulse <= 1'b1;
                        debug_ack_sample_sda <= sda_sync[1];
                        ack_bits[byte_idx] <= !sda_sync[1];
                        if (CHECK_ACK && sda_sync[1]) begin
                            // No slave ACK: stop clocking this transaction
                            // immediately.  Continuing would clock the
                            // remaining bytes into a device that is not
                            // responding and only produce a fake transaction
                            // that pollutes later analysis.
                            ack_error <= 1'b1;
                            state <= ST_STOP_A;
                        end else begin
                            // With CHECK_ACK=0, a high SDA is still recorded
                            // in ack_bits as NACK, but it does not terminate
                            // the transaction.  The next byte is sent anyway.
                            state <= ST_NEXT;
                        end
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
                        // A NACK aborts the current frame.  Retry the entire
                        // frame (address + register + data), rather than
                        // resuming at the byte that failed.  This preserves
                        // the ADAU register protocol and gives the bus a STOP
                        // between attempts.  attempt_count is zero-based:
                        // 0->1 is the second attempt, 1->2 is the third.
                        if (ack_error && (attempt_count < (MAX_ATTEMPTS - 1))) begin
                            attempt_count <= attempt_count + 1'b1;
                            ack_error <= 1'b0;
                            ack_bits <= 3'd0;
                            byte_idx <= 3'd0;
                            state <= ST_RETRY_WAIT;
                        end else begin
                            state <= ST_DONE;
                        end
                    end
                end

                ST_DONE: begin
                    scl_oe_n <= 1'b1;
                    sda_oe_n <= 1'b1;
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= ST_IDLE;
                end

                // Leave both lines released for one half-period after STOP
                // before issuing a retry.  This gives SDA time to return high
                // through the pull-up and prevents a repeated START from
                // being confused with the preceding STOP.
                ST_RETRY_WAIT: begin
                    scl_oe_n <= 1'b1;
                    sda_oe_n <= 1'b1;
                    if (tick) begin
                        if (!sda_sync[1]) begin
                            // If a slave is still holding SDA, use the normal
                            // bus-clear sequence before retrying.
                            bc_cnt <= 4'd0;
                            state <= ST_BC_LOW;
                        end else begin
                            state <= ST_START_A;
                        end
                    end
                end

                // ---- I2C bus clear -------------------------------------------
                // Nine SCL pulses with SDA released, followed by a STOP.  This
                // is the standard recovery for a slave holding SDA low (for
                // example it was left mid-byte by a previous master).  SDA is
                // never driven here, so the sequence is harmless when nothing
                // is holding the bus; it costs about 55 us and only runs when
                // the idle check in ST_IDLE actually sampled SDA low.
                // Observable on the ILA as wr_state = 12..15 in i2c_debug[22:18].
                ST_BC_LOW: begin
                    scl_oe_n <= 1'b0;
                    sda_oe_n <= 1'b1;
                    if (tick)
                        state <= ST_BC_HIGH;
                end

                ST_BC_HIGH: begin
                    scl_oe_n <= 1'b1;
                    sda_oe_n <= 1'b1;
                    if (tick) begin
                        if (bc_cnt == 4'd8)
                            state <= ST_BC_STOP_A;
                        else begin
                            bc_cnt <= bc_cnt + 1'b1;
                            state <= ST_BC_LOW;
                        end
                    end
                end

                ST_BC_STOP_A: begin
                    scl_oe_n <= 1'b1;
                    sda_oe_n <= 1'b0;   // SDA low while SCL is high
                    if (tick)
                        state <= ST_BC_STOP_B;
                end

                ST_BC_STOP_B: begin
                    scl_oe_n <= 1'b1;
                    sda_oe_n <= 1'b1;   // SDA released while SCL high = STOP
                    if (tick)
                        state <= ST_START_A;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
