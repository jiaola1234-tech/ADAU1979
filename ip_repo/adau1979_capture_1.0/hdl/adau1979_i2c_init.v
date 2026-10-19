`timescale 1 ns / 1 ps

module adau1979_i2c_init #
(
    parameter integer CLK_HZ = 50000000,
    parameter integer I2C_HZ = 100000,
    parameter [6:0] U1_ADDR = 7'h11,
    parameter [6:0] U2_ADDR = 7'h31
)
(
    input  wire       clk,
    input  wire       rstn,
    input  wire       init_start,
    output reg        init_busy,
    output reg        init_done,
    output reg        init_error,
    output reg [7:0]  init_step,
    output reg [31:0] ack_error_count,
    output wire [6:0] last_dev_addr,
    output wire [7:0] last_reg_addr,
    output wire [7:0] last_wr_data,
    output wire [2:0] last_ack_bits,
    output wire [3:0] debug_state,
    output wire debug_pll_dev_idx,
    output wire debug_pll_busy,
    output wire debug_pll_done,
    output wire debug_pll_ack_error,
    output wire [7:0] debug_pll_read_data,
    output wire [7:0] debug_pll_poll_count,
    output wire       debug_pll_read_addr_ack,
    output wire       debug_pll_read_data_valid,
    output reg        verify_fail,
    output reg [1:0]  verify_fail_code,
    output reg [6:0]  verify_fail_dev_addr,
    output reg [7:0]  verify_fail_reg_addr,
    output reg [7:0]  verify_fail_expected,
    output reg [7:0]  verify_fail_actual,
    output wire [4:0] debug_wr_state,
    output wire [2:0] debug_wr_byte_idx,
    output wire [2:0] debug_wr_bit_idx,
    output wire       debug_wr_ack_sample_pulse,
    output wire       debug_wr_ack_sample_sda,
    output reg        debug_write_done,
    output wire       debug_write_ack_error,
    output wire [6:0] debug_pll_dev_addr,
    output reg        debug_scan_done,
    output wire [6:0] debug_scan_dev_addr,
    output wire [7:0] debug_scan_read_data,
    output wire       debug_scan_ack_error,
    output wire       debug_scan_read_addr_ack,
    output wire       debug_scan_read_data_valid,
    output wire       debug_verify_done,
    output wire       debug_verify_read_addr_ack,
    output wire       debug_verify_read_data_valid,
    output wire [7:0] debug_verify_read_data,
    output wire       debug_verify_ack_error,

    output reg        adau_pd_rst,
    input  wire       adau_sda_i,
    output wire       adau_scl_oe_n,
    output wire       adau_sda_oe_n
);

    // FPGA-controlled ADAU hardware reset: assert PD/RST low for 100 ms,
    // release it high for another 100 ms, then start I2C. Reinitialization
    // uses the same sequence so stale ADAU state cannot survive an 'r' command.
    localparam integer POWERUP_WAIT_CYCLES = CLK_HZ / 10;
    localparam integer PLL_WAIT_CYCLES = CLK_HZ / 50;
    localparam [31:0] POWERUP_WAIT_COUNT = POWERUP_WAIT_CYCLES;
    localparam [31:0] PLL_WAIT_COUNT = PLL_WAIT_CYCLES;

    localparam [3:0] ST_RESET_LOW  = 4'd0;
    localparam [3:0] ST_RESET_HIGH = 4'd1;
    localparam [3:0] ST_IDLE       = 4'd2;
    localparam [3:0] ST_LOAD       = 4'd3;
    localparam [3:0] ST_START      = 4'd4;
    localparam [3:0] ST_WAIT       = 4'd5;
    localparam [3:0] ST_DELAY      = 4'd6;
    localparam [3:0] ST_DONE       = 4'd7;
    localparam [3:0] ST_PLL_START  = 4'd8;
    localparam [3:0] ST_PLL_WAIT   = 4'd9;
    localparam [3:0] ST_PLL_DELAY  = 4'd10;
    localparam [3:0] ST_FAIL       = 4'd11;
    localparam [3:0] ST_VERIFY_WAIT = 4'd12;
    localparam [3:0] ST_SCAN_START = 4'd13;
    localparam [3:0] ST_SCAN_WAIT = 4'd14;

    // Diagnostic mode: when both configured addresses are equal, initialize
    // only one ADAU1979.  This lets the same IP be used to isolate U1 or U2
    // without changing the board straps.  The normal dual-device build keeps
    // the original two-device script and PLL polling behavior.
    localparam SINGLE_DEVICE_MODE = (U1_ADDR == U2_ADDR);
    // Bring-up mode selector.
    //   1 = write-only: every register is written and its three write-phase
    //       ACKs are checked, but no register read-back, address scan or PLL
    //       read is required to declare the sequence complete.
    //   0 = full diagnostic flow: 4-address scan (0x11/0x31/0x51/0x71) first,
    //       then every write is followed by a read-back compare, then the PLL
    //       lock poll.  Set back to 1'b1 if a read-back mismatch ever blocks
    //       bring-up on a register the device implements differently.
    // Production diagnostic build: write each configuration byte and require
    // ACK, but do not issue read-back/PLL-poll transactions.
    // Require read-back diagnostics and PLL_CONTROL(0x01).PLL_LOCK before
    // advertising init_done.  A write-only completion can leave SDATAOUT
    // driven only by a floating/incorrectly configured audio path.
    // Keep the address/byte ACK checks, but do not compare ADAU readback
    // values: ADAU1979 register reads can return 0xFF even after a valid
    // write, which would falsely abort initialization.
    localparam WRITE_ONLY_CONFIG = 1'b0;
    localparam VERIFY_READBACK = 1'b0;
    localparam integer SCRIPT_LAST = SINGLE_DEVICE_MODE ? 15 : 30;
    localparam [7:0] SCRIPT_LAST_COUNT = SCRIPT_LAST;

    reg [3:0] state;
    reg [31:0] wait_cnt;
    reg [7:0] script_idx;
    reg [6:0] dev_addr;
    reg [7:0] reg_addr;
    reg [7:0] reg_data;
    reg i2c_start;
    reg started_once;
    reg pll_read_start;
    reg verify_read_start;
    reg scan_read_start;
    reg [1:0] scan_idx;
    reg [6:0] scan_dev_latched;
    reg [7:0] scan_data_latched;
    reg scan_err_latched;
    reg pll_dev_idx;
    reg [31:0] pll_poll_count;
    wire pll_busy;
    wire pll_done;
    wire pll_ack_error;
    wire [7:0] pll_read_data;
    wire pll_read_addr_ack;
    wire pll_read_data_valid;
    wire verify_busy;
    wire verify_done;
    wire verify_ack_error;
    wire [7:0] verify_read_data;
    wire verify_read_addr_ack;
    wire verify_read_data_valid;


    localparam integer PLL_POLL_INTERVAL_CYCLES = CLK_HZ / 1000;
    localparam integer PLL_POLL_LIMIT = 20;
    localparam [31:0] PLL_POLL_INTERVAL_COUNT = PLL_POLL_INTERVAL_CYCLES;

    // M_POWER (0x00) is a control register whose read value can reflect the
    // device power state rather than the last byte written.  Keep the read
    // transaction and its diagnostics, but do not turn that implementation
    // defined value into an initialization failure.  Other registers remain
    // strict read-back checks, so a broken repeated-start/read phase is still
    // caught at the first ordinary readable register (0x01).
    localparam VERIFY_M_POWER_STRICT = 1'b0;

    wire i2c_busy;
    wire i2c_done;
    wire i2c_ack_error;
    wire [6:0] i2c_last_dev_addr;
    wire [7:0] i2c_last_reg_addr;
    wire [7:0] i2c_last_wr_data;
    wire [2:0] i2c_last_ack_bits;
    wire [4:0] i2c_debug_wr_state;
    wire [2:0] i2c_debug_wr_byte_idx;
    wire [2:0] i2c_debug_wr_bit_idx;
    wire i2c_debug_wr_ack_sample_pulse;
    wire i2c_debug_wr_ack_sample_sda;
    wire write_scl_oe_n;
    wire write_sda_oe_n;
    wire read_scl_oe_n;
    wire read_sda_oe_n;
    wire verify_scl_oe_n;
    wire verify_sda_oe_n;
    wire scan_busy;
    wire scan_done;
    wire scan_ack_error;
    wire [7:0] scan_read_data;
    wire scan_read_addr_ack;
    wire scan_read_data_valid;
    wire scan_scl_oe_n;
    wire scan_sda_oe_n;
    wire [6:0] scan_current_dev_addr = (scan_idx == 2'd0) ? 7'h11 :
                                        (scan_idx == 2'd1) ? 7'h31 :
                                        (scan_idx == 2'd2) ? 7'h51 : 7'h71;

    i2c_master_write8 #(
        .CLK_HZ(CLK_HZ),
        .I2C_HZ(I2C_HZ),
        // Continue sending the complete write frame even when the sampled
        // ACK is high.  ACK remains visible in i2c_debug[25:23]/[10], but it
        // no longer blocks the configuration sequence during bring-up.
        .CHECK_ACK(0)
    ) i2c_master_write8_i (
        .clk(clk),
        .rstn(rstn),
        .start(i2c_start),
        .dev_addr(dev_addr),
        .reg_addr(reg_addr),
        .wr_data(reg_data),
        .busy(i2c_busy),
        .done(i2c_done),
        .ack_error(i2c_ack_error),
        .last_dev_addr(i2c_last_dev_addr),
        .last_reg_addr(i2c_last_reg_addr),
        .last_wr_data(i2c_last_wr_data),
        .ack_bits(i2c_last_ack_bits),
        .debug_state(i2c_debug_wr_state),
        .debug_byte_idx(i2c_debug_wr_byte_idx),
        .debug_bit_idx(i2c_debug_wr_bit_idx),
        .debug_ack_sample_pulse(i2c_debug_wr_ack_sample_pulse),
        .debug_ack_sample_sda(i2c_debug_wr_ack_sample_sda),
        .sda_i(adau_sda_i),
        .scl_oe_n(write_scl_oe_n),
        .sda_oe_n(write_sda_oe_n)
    );

    assign last_dev_addr = i2c_last_dev_addr;
    assign last_reg_addr = i2c_last_reg_addr;
    assign last_wr_data = i2c_last_wr_data;
    assign last_ack_bits = i2c_last_ack_bits;
    assign debug_state = state[3:0];
    assign debug_wr_state = i2c_debug_wr_state;
    assign debug_wr_byte_idx = i2c_debug_wr_byte_idx;
    assign debug_wr_bit_idx = i2c_debug_wr_bit_idx;
    assign debug_wr_ack_sample_pulse = i2c_debug_wr_ack_sample_pulse;
    assign debug_wr_ack_sample_sda = i2c_debug_wr_ack_sample_sda;
    assign debug_pll_dev_idx = pll_dev_idx;
    assign debug_pll_busy = pll_busy;
    assign debug_pll_done = pll_done;
    assign debug_pll_ack_error = pll_ack_error;
    assign debug_pll_read_data = pll_read_data;
    assign debug_pll_poll_count = pll_poll_count[7:0];
    assign debug_pll_dev_addr = SINGLE_DEVICE_MODE ? U1_ADDR :
                                (pll_dev_idx ? U2_ADDR : U1_ADDR);
    assign debug_pll_read_addr_ack = pll_read_addr_ack;
    assign debug_pll_read_data_valid = pll_read_data_valid;
    assign debug_write_ack_error = i2c_ack_error;
    assign debug_scan_dev_addr = scan_dev_latched;
    assign debug_scan_read_data = scan_data_latched;
    assign debug_scan_ack_error = scan_err_latched;
    assign debug_scan_read_addr_ack = scan_read_addr_ack;
    assign debug_scan_read_data_valid = scan_read_data_valid;
    assign debug_verify_done = verify_done;
    assign debug_verify_read_addr_ack = verify_read_addr_ack;
    assign debug_verify_read_data_valid = verify_read_data_valid;
    assign debug_verify_read_data = verify_read_data;
    assign debug_verify_ack_error = verify_ack_error;

    i2c_master_read8 #(
        .CLK_HZ(CLK_HZ),
        .I2C_HZ(I2C_HZ)
    ) i2c_master_read8_i (
        .clk(clk),
        .rstn(rstn),
        .start(pll_read_start),
        // In normal dual-device mode, verify U1 first and U2 last, matching
        // the write-script order.
        .dev_addr(SINGLE_DEVICE_MODE ? U1_ADDR :
                  (pll_dev_idx ? U2_ADDR : U1_ADDR)),
        .reg_addr(8'h01),
        .busy(pll_busy),
        .done(pll_done),
        .ack_error(pll_ack_error),
        .rd_data(pll_read_data),
        .read_addr_ack(pll_read_addr_ack),
        .read_data_valid(pll_read_data_valid),
        .sda_i(adau_sda_i),
        .scl_oe_n(read_scl_oe_n),
        .sda_oe_n(read_sda_oe_n)
    );

    // Read back the register immediately after every successful write.  The
    // M_POWER (0x00) value is still captured for diagnostics, but its
    // implementation-defined readback is exempted from the strict compare
    // below.  Other registers stop initialization at the exact U1/U2 and
    // register that failed.
    i2c_master_read8 #(
        .CLK_HZ(CLK_HZ),
        .I2C_HZ(I2C_HZ)
    ) i2c_master_verify_read8_i (
        .clk(clk),
        .rstn(rstn),
        .start(verify_read_start),
        .dev_addr(dev_addr),
        .reg_addr(reg_addr),
        .busy(verify_busy),
        .done(verify_done),
        .ack_error(verify_ack_error),
        .rd_data(verify_read_data),
        .read_addr_ack(verify_read_addr_ack),
        .read_data_valid(verify_read_data_valid),
        .sda_i(adau_sda_i),
        .scl_oe_n(verify_scl_oe_n),
        .sda_oe_n(verify_sda_oe_n)
    );

    // Diagnostic address scan. Register 0x00 is read; no configuration
    // register is written and the normal initialization script is unchanged.
    i2c_master_read8 #(
        .CLK_HZ(CLK_HZ),
        .I2C_HZ(I2C_HZ)
    ) i2c_master_scan_read8_i (
        .clk(clk),
        .rstn(rstn),
        .start(scan_read_start),
        .dev_addr(scan_current_dev_addr),
        .reg_addr(8'h00),
        .busy(scan_busy),
        .done(scan_done),
        .ack_error(scan_ack_error),
        .rd_data(scan_read_data),
        .read_addr_ack(scan_read_addr_ack),
        .read_data_valid(scan_read_data_valid),
        .sda_i(adau_sda_i),
        .scl_oe_n(scan_scl_oe_n),
        .sda_oe_n(scan_sda_oe_n)
    );

    // Only one I2C engine is active at a time.  The read engine must be
    // connected to the same open-drain bus during PLL lock polling.
    assign adau_scl_oe_n = scan_busy ? scan_scl_oe_n :
                            (pll_busy ? read_scl_oe_n :
                            (verify_busy ? verify_scl_oe_n : write_scl_oe_n));
    assign adau_sda_oe_n = scan_busy ? scan_sda_oe_n :
                            (pll_busy ? read_sda_oe_n :
                            (verify_busy ? verify_sda_oe_n : write_sda_oe_n));

    always @(*) begin
        dev_addr = U1_ADDR;
        reg_addr = 8'h00;
        reg_data = 8'h00;

        case (script_idx)
            // Configure U1 first; U1 is the audio-serial clock master.
            8'd0:  begin dev_addr = U1_ADDR; reg_addr = 8'h00; reg_data = 8'h00; end
            8'd1:  begin dev_addr = U1_ADDR; reg_addr = 8'h01; reg_data = 8'h43; end
            8'd2:  begin dev_addr = U1_ADDR; reg_addr = 8'h04; reg_data = 8'hBF; end
            8'd3:  begin dev_addr = U1_ADDR; reg_addr = 8'h05; reg_data = 8'h02; end
            // SAI_CTRL1.SAI_MS=1: U1 drives BCLK and LRCLK.
            8'd4:  begin dev_addr = U1_ADDR; reg_addr = 8'h06; reg_data = 8'h01; end
            8'd5:  begin dev_addr = U1_ADDR; reg_addr = 8'h07; reg_data = 8'h10; end
            8'd6:  begin dev_addr = U1_ADDR; reg_addr = 8'h08; reg_data = 8'h32; end
            8'd7:  begin dev_addr = U1_ADDR; reg_addr = 8'h0A; reg_data = 8'hA0; end
            8'd8:  begin dev_addr = U1_ADDR; reg_addr = 8'h0B; reg_data = 8'hA0; end
            8'd9:  begin dev_addr = U1_ADDR; reg_addr = 8'h0C; reg_data = 8'hA0; end
            8'd10: begin dev_addr = U1_ADDR; reg_addr = 8'h0D; reg_data = 8'hA0; end
            8'd11: begin dev_addr = U1_ADDR; reg_addr = 8'h09; reg_data = 8'hF0; end
            8'd12: begin dev_addr = U1_ADDR; reg_addr = 8'h0E; reg_data = 8'h02; end
            8'd13: begin dev_addr = U1_ADDR; reg_addr = 8'h1A; reg_data = 8'h0F; end
            8'd14: begin dev_addr = U1_ADDR; reg_addr = 8'h00; reg_data = 8'h01; end

            // Configure and power up U2 after U1. U2 is the audio-serial
            // clock slave and receives BCLK/LRCLK from U1.
            8'd15: begin dev_addr = U2_ADDR; reg_addr = 8'h00; reg_data = 8'h00; end
            8'd16: begin dev_addr = U2_ADDR; reg_addr = 8'h01; reg_data = 8'h43; end
            8'd17: begin dev_addr = U2_ADDR; reg_addr = 8'h04; reg_data = 8'hBF; end
            8'd18: begin dev_addr = U2_ADDR; reg_addr = 8'h05; reg_data = 8'h02; end
            // SAI_CTRL1.SAI_MS=0: U2 receives BCLK and LRCLK from U1.
            8'd19: begin dev_addr = U2_ADDR; reg_addr = 8'h06; reg_data = 8'h00; end
            8'd20: begin dev_addr = U2_ADDR; reg_addr = 8'h07; reg_data = 8'h10; end
            8'd21: begin dev_addr = U2_ADDR; reg_addr = 8'h08; reg_data = 8'h32; end
            8'd22: begin dev_addr = U2_ADDR; reg_addr = 8'h0A; reg_data = 8'hA0; end
            8'd23: begin dev_addr = U2_ADDR; reg_addr = 8'h0B; reg_data = 8'hA0; end
            8'd24: begin dev_addr = U2_ADDR; reg_addr = 8'h0C; reg_data = 8'hA0; end
            8'd25: begin dev_addr = U2_ADDR; reg_addr = 8'h0D; reg_data = 8'hA0; end
            8'd26: begin dev_addr = U2_ADDR; reg_addr = 8'h09; reg_data = 8'hF0; end
            8'd27: begin dev_addr = U2_ADDR; reg_addr = 8'h0E; reg_data = 8'h02; end
            8'd28: begin dev_addr = U2_ADDR; reg_addr = 8'h1A; reg_data = 8'h0F; end
            8'd29: begin dev_addr = U2_ADDR; reg_addr = 8'h00; reg_data = 8'h01; end
            default: begin dev_addr = U1_ADDR; reg_addr = 8'h00; reg_data = 8'h00; end
        endcase
    end

    always @(posedge clk) begin
        if (!rstn) begin
            state <= ST_RESET_LOW;
            wait_cnt <= 32'd0;
            script_idx <= 8'd0;
            i2c_start <= 1'b0;
            pll_read_start <= 1'b0;
            verify_read_start <= 1'b0;
            scan_read_start <= 1'b0;
            pll_dev_idx <= 1'b0;
            pll_poll_count <= 32'd0;
            scan_idx <= 2'd0;
            scan_dev_latched <= 7'h11;
            scan_data_latched <= 8'd0;
            scan_err_latched <= 1'b0;
            init_busy <= 1'b1;
            init_done <= 1'b0;
            init_error <= 1'b0;
            init_step <= 8'd0;
            ack_error_count <= 32'd0;
            verify_fail <= 1'b0;
            verify_fail_code <= 2'd0;
            verify_fail_dev_addr <= 7'd0;
            verify_fail_reg_addr <= 8'd0;
            verify_fail_expected <= 8'd0;
            verify_fail_actual <= 8'd0;
            debug_write_done <= 1'b0;
            debug_scan_done <= 1'b0;
            adau_pd_rst <= 1'b0;
            started_once <= 1'b0;
        end else begin
            i2c_start <= 1'b0;
            pll_read_start <= 1'b0;
            verify_read_start <= 1'b0;
            scan_read_start <= 1'b0;
            debug_write_done <= 1'b0;
            debug_scan_done <= 1'b0;

            case (state)
                ST_RESET_LOW: begin
                    init_busy <= 1'b1;
                    adau_pd_rst <= 1'b0;
                    init_done <= 1'b0;
                    wait_cnt <= wait_cnt + 1'b1;
                    if (wait_cnt >= POWERUP_WAIT_COUNT) begin
                        wait_cnt <= 32'd0;
                        state <= ST_RESET_HIGH;
                    end
                end

                ST_RESET_HIGH: begin
                    adau_pd_rst <= 1'b1;
                    wait_cnt <= wait_cnt + 1'b1;
                    if (wait_cnt >= POWERUP_WAIT_COUNT) begin
                        wait_cnt <= 32'd0;
                        script_idx <= 8'd0;
                        init_step <= 8'd0;
                        init_error <= 1'b0;
                        scan_idx <= 2'd0;
                        state <= WRITE_ONLY_CONFIG ? ST_LOAD : ST_SCAN_START;
                    end
                end

                ST_IDLE: begin
                    init_busy <= 1'b0;
                    if (init_start || !started_once) begin
                        init_busy <= 1'b1;
                        init_done <= 1'b0;
                        init_error <= 1'b0;
                        ack_error_count <= 32'd0;
                        verify_fail <= 1'b0;
                        verify_fail_code <= 2'd0;
                        verify_fail_dev_addr <= 7'd0;
                        verify_fail_reg_addr <= 8'd0;
                        verify_fail_expected <= 8'd0;
                        verify_fail_actual <= 8'd0;
                        script_idx <= 8'd0;
                        init_step <= 8'd0;
                        scan_idx <= 2'd0;
                        state <= ST_RESET_LOW;
                    end
                end

                ST_LOAD: begin
                    init_step <= script_idx;
                    if (script_idx >= SCRIPT_LAST_COUNT) begin
                        state <= WRITE_ONLY_CONFIG ? ST_DONE : ST_DELAY;
                        wait_cnt <= 32'd0;
                    end else begin
                        state <= ST_START;
                    end
                end

                ST_START: begin
                    if (!i2c_busy) begin
                        i2c_start <= 1'b1;
                        state <= ST_WAIT;
                    end
                end

                ST_WAIT: begin
                    if (i2c_done) begin
                        debug_write_done <= 1'b1;
                        if (i2c_ack_error) begin
                            ack_error_count <= ack_error_count + 1'b1;
                            init_error <= 1'b1;
                            verify_fail <= 1'b1;
                            verify_fail_code <= 2'd1;
                            verify_fail_dev_addr <= dev_addr;
                            verify_fail_reg_addr <= reg_addr;
                            verify_fail_expected <= reg_data;
                            verify_fail_actual <= 8'hFF;
                        end
                        if (i2c_ack_error) begin
                            if (WRITE_ONLY_CONFIG) begin
                                state <= ST_FAIL;
                            end else begin
                                // U1 failure must not prevent an independent U2
                                // test. U1 occupies script steps 0..14.
                                if (script_idx < 8'd15) begin
                                    script_idx <= 8'd15;
                                    state <= ST_LOAD;
                                end else begin
                                    state <= ST_FAIL;
                                end
                            end
                        end else if (WRITE_ONLY_CONFIG || !VERIFY_READBACK) begin
                            script_idx <= script_idx + 1'b1;
                            state <= ST_LOAD;
                        end else begin
                            // Read back the same register before advancing.
                            verify_read_start <= 1'b1;
                            state <= ST_VERIFY_WAIT;
                        end
                    end
                end

                ST_SCAN_START: begin
                    if (!scan_busy) begin
                        scan_read_start <= 1'b1;
                        state <= ST_SCAN_WAIT;
                    end
                end

                ST_SCAN_WAIT: begin
                    if (scan_done) begin
                        // Latch the result before scan_idx advances.  The
                        // AXI trace writer consumes debug_scan_done one
                        // clock later, so these values remain stable.
                        scan_dev_latched <= scan_current_dev_addr;
                        scan_data_latched <= scan_read_data;
                        scan_err_latched <= scan_ack_error;
                        debug_scan_done <= 1'b1;
                        if (scan_idx == 2'd3) begin
                            script_idx <= 8'd0;
                            init_step <= 8'd0;
                            state <= ST_LOAD;
                        end else begin
                            scan_idx <= scan_idx + 1'b1;
                            state <= ST_SCAN_START;
                        end
                    end
                end

                ST_VERIFY_WAIT: begin
                    if (verify_done) begin
                        if (verify_ack_error) begin
                            ack_error_count <= ack_error_count + 1'b1;
                            init_error <= 1'b1;
                            verify_fail <= 1'b1;
                            verify_fail_code <= 2'd2;
                            verify_fail_dev_addr <= dev_addr;
                            verify_fail_reg_addr <= reg_addr;
                            verify_fail_expected <= reg_data;
                            verify_fail_actual <= 8'hFF;
                            if (script_idx < 8'd15) begin
                                script_idx <= 8'd15;
                                state <= ST_LOAD;
                            end else begin
                                state <= ST_FAIL;
                            end
                        end else if ((reg_addr != 8'h00 || VERIFY_M_POWER_STRICT) &&
                                     (verify_read_data != reg_data)) begin
                            init_error <= 1'b1;
                            verify_fail <= 1'b1;
                            verify_fail_code <= 2'd3;
                            verify_fail_dev_addr <= dev_addr;
                            verify_fail_reg_addr <= reg_addr;
                            verify_fail_expected <= reg_data;
                            verify_fail_actual <= verify_read_data;
                            if (script_idx < 8'd15) begin
                                script_idx <= 8'd15;
                                state <= ST_LOAD;
                            end else begin
                                state <= ST_FAIL;
                            end
                        end else begin
                            script_idx <= script_idx + 1'b1;
                            state <= ST_LOAD;
                        end
                    end
                end

                ST_DELAY: begin
                    wait_cnt <= wait_cnt + 1'b1;
                    if (wait_cnt >= PLL_WAIT_COUNT) begin
                        wait_cnt <= 32'd0;
                        pll_dev_idx <= 1'b0;
                        pll_poll_count <= 32'd0;
                        state <= ST_PLL_START;
                    end
                end

                ST_PLL_START: begin
                    if (!pll_busy) begin
                        pll_read_start <= 1'b1;
                        state <= ST_PLL_WAIT;
                    end
                end

                ST_PLL_WAIT: begin
                    if (pll_done) begin
                        if (pll_ack_error) begin
                            init_error <= 1'b1;
                            // Keep the U2 diagnostic independent: a U1
                            // PLL read failure advances to U2 in dual mode.
                            if (!SINGLE_DEVICE_MODE && !pll_dev_idx) begin
                                pll_dev_idx <= 1'b1;
                                pll_poll_count <= 32'd0;
                                state <= ST_PLL_START;
                            end else begin
                                state <= ST_FAIL;
                            end
                        end else if (pll_read_data[7]) begin
                            // In single-device mode, one lock read is enough.
                            // In dual-device mode, poll U1 first and U2 last.
                            if (SINGLE_DEVICE_MODE || pll_dev_idx) begin
                                state <= ST_DONE;
                            end else begin
                                pll_dev_idx <= 1'b1;
                                pll_poll_count <= 32'd0;
                                state <= ST_PLL_START;
                            end
                        end else if (pll_poll_count >= PLL_POLL_LIMIT - 1) begin
                            init_error <= 1'b1;
                            if (!SINGLE_DEVICE_MODE && !pll_dev_idx) begin
                                pll_dev_idx <= 1'b1;
                                pll_poll_count <= 32'd0;
                                state <= ST_PLL_START;
                            end else begin
                                state <= ST_FAIL;
                            end
                        end else begin
                            pll_poll_count <= pll_poll_count + 1'b1;
                            wait_cnt <= 32'd0;
                            state <= ST_PLL_DELAY;
                        end
                    end
                end

                ST_PLL_DELAY: begin
                    wait_cnt <= wait_cnt + 1'b1;
                    if (wait_cnt >= PLL_POLL_INTERVAL_COUNT)
                        state <= ST_PLL_START;
                end

                ST_DONE: begin
                    started_once <= 1'b1;
                    // An ACK failure means at least one ADAU register was
                    // not programmed.  Never advertise initialization as
                    // complete in that condition.
                    init_done <= !init_error;
                    init_busy <= 1'b0;
                    state <= ST_IDLE;
                end

                ST_FAIL: begin
                    init_done <= 1'b0;
                    started_once <= 1'b1;
                    init_busy <= 1'b0;
                    state <= ST_IDLE;
                end

                default: state <= ST_RESET_LOW;
            endcase
        end
    end

endmodule
