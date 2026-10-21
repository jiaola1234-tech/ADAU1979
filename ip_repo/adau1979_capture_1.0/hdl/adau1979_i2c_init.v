`timescale 1 ns / 1 ps

// Sequential dual-device initialization with one shared hardware reset.
// I2C_ADDR is the 7-bit address. The I2C engines add the R/W bit internally.
module adau1979_i2c_init #(
    parameter integer DUAL_ENABLE = 1,
    parameter integer DEVICE_A_ADDR = 17,
    parameter integer DEVICE_B_ADDR = 49,
    parameter integer AUDIO_MASTER = 0,
    parameter integer CLK_HZ = 50000000,
    parameter integer I2C_HZ = 100000
) (
    input wire clk, input wire rstn, input wire init_start,
    output reg init_busy, output reg init_done, output reg init_error,
    output reg [7:0] init_step, output reg [31:0] ack_error_count,
    output wire [6:0] last_dev_addr, output wire [7:0] last_reg_addr,
    output wire [7:0] last_wr_data, output wire [2:0] last_ack_bits,
    output wire [3:0] debug_state, output wire debug_pll_dev_idx,
    output wire debug_pll_busy, output wire debug_pll_done,
    output wire debug_pll_ack_error, output wire [7:0] debug_pll_read_data,
    output wire [7:0] debug_pll_poll_count,
    output wire [6:0] debug_pll_dev_addr,
    output wire debug_pll_read_addr_ack, output wire debug_pll_read_data_valid,
    output reg verify_fail, output reg [1:0] verify_fail_code,
    output reg [6:0] verify_fail_dev_addr, output reg [7:0] verify_fail_reg_addr,
    output reg [7:0] verify_fail_expected, output reg [7:0] verify_fail_actual,
    output wire [4:0] debug_wr_state, output wire [2:0] debug_wr_byte_idx,
    output wire [2:0] debug_wr_bit_idx,
    output wire debug_wr_ack_sample_pulse, output wire debug_wr_ack_sample_sda,
    output reg debug_write_done, output wire debug_write_ack_error,
    output wire debug_verify_done, output wire debug_verify_read_addr_ack,
    output wire debug_verify_read_data_valid, output wire [7:0] debug_verify_read_data,
    output wire debug_verify_ack_error, output reg adau_pd_rst,
    output reg [7:0] diag_read_data0, output reg [7:0] diag_read_data1,
    output reg [7:0] diag_read_data4, output reg [7:0] diag_read_data5,
    output reg [7:0] diag_read_data6, output reg [4:0] diag_read_valid,
    output reg [4:0] diag_read_error, output reg diag_read_done,
    output wire [63:0] device_status,
    output wire [79:0] device_readback,
    output wire [31:0] device_probe_status,
    input wire adau_sda_i, output wire adau_scl_oe_n, output wire adau_sda_oe_n
);
    reg dev_idx;
    wire [6:0] I2C_ADDR = dev_idx ? DEVICE_B_ADDR : DEVICE_A_ADDR;
    wire is_master = (dev_idx == AUDIO_MASTER);
    reg [39:0] readback [0:1];
    reg [4:0] read_valid [0:1], read_error [0:1];
    reg [1:0] pll_locked, writes_ok, verified, read_done;
    reg [1:0] probe_attempted, probe_done, probe_ack;
    reg probing;
    // Per-device 16-bit diagnostic: addr[14:8], ACK[2], done[1], attempted[0].
    assign device_probe_status = {
        1'b0, DEVICE_B_ADDR[6:0], 5'd0, probe_ack[1], probe_done[1], probe_attempted[1],
        1'b0, DEVICE_A_ADDR[6:0], 5'd0, probe_ack[0], probe_done[0], probe_attempted[0]};
    wire [31:0] status_a = {8'd0, DEVICE_A_ADDR[6:0], (AUDIO_MASTER==0),
        1'b1, verified[0], writes_ok[0], pll_locked[0], read_error[0],
        read_valid[0], read_done[0], (init_busy && !dev_idx)};
    wire [31:0] status_b = {8'd0, DEVICE_B_ADDR[6:0], (AUDIO_MASTER==1),
        (DUAL_ENABLE!=0), verified[1], writes_ok[1], pll_locked[1], read_error[1],
        read_valid[1], read_done[1], (init_busy && dev_idx)};
    assign device_status = {status_b, status_a};
    assign device_readback = {readback[1], readback[0]};
    // Legacy diagnostics at 0x40..0x54 always describe logical device A.
    always @(*) begin
        {diag_read_data6,diag_read_data5,diag_read_data4,diag_read_data1,diag_read_data0}=readback[0];
        diag_read_valid=read_valid[0]; diag_read_error=read_error[0]; diag_read_done=read_done[0];
    end
    reg [7:0] expected_read;
    localparam integer POWERUP_WAIT_CYCLES = CLK_HZ / 10;
    localparam integer PLL_WAIT_CYCLES = CLK_HZ / 50;
    localparam integer PLL_POLL_INTERVAL_CYCLES = CLK_HZ / 1000;
    localparam integer PLL_POLL_LIMIT = 20;
    localparam [31:0] POWERUP_WAIT_COUNT = POWERUP_WAIT_CYCLES;
    localparam [31:0] PLL_WAIT_COUNT = PLL_WAIT_CYCLES;
    localparam [31:0] PLL_POLL_INTERVAL_COUNT = PLL_POLL_INTERVAL_CYCLES;
    localparam [3:0] ST_RESET_LOW=4'd0, ST_RESET_HIGH=4'd1, ST_IDLE=4'd2,
                     ST_LOAD=4'd3, ST_START=4'd4, ST_WAIT=4'd5,
                     ST_DELAY=4'd6, ST_DONE=4'd7, ST_PLL_START=4'd8,
                     ST_PLL_WAIT=4'd9, ST_PLL_DELAY=4'd10, ST_FAIL=4'd11,
                     ST_DIAG_START=4'd12, ST_DIAG_WAIT=4'd13,
                     ST_MASTER_SETTLE=4'd14, ST_PROBE_WAIT=4'd15;

    reg [3:0] state;
    reg [31:0] wait_cnt, pll_poll_count;
    reg [7:0] script_idx, reg_addr, reg_data, read_reg_addr;
    reg [2:0] diag_idx;
    reg i2c_start, pll_read_start, started_once;
    wire i2c_busy, i2c_done, i2c_ack_error;
    wire [6:0] i2c_last_dev_addr;
    wire [7:0] i2c_last_reg_addr, i2c_last_wr_data;
    wire [2:0] i2c_last_ack_bits;
    wire [4:0] i2c_debug_wr_state;
    wire [2:0] i2c_debug_wr_byte_idx, i2c_debug_wr_bit_idx;
    wire i2c_debug_wr_ack_sample_pulse, i2c_debug_wr_ack_sample_sda;
    wire write_scl_oe_n, write_sda_oe_n;
    wire pll_busy, pll_done, pll_ack_error;
    wire [7:0] pll_read_data;
    wire pll_read_addr_ack, pll_read_data_valid, pll_scl_oe_n, pll_sda_oe_n;

    wire read_failed = pll_ack_error || !pll_read_addr_ack || !pll_read_data_valid;
    task record_failure;
        input [1:0] code;
        input [7:0] addr, expected, actual;
        begin
            init_error<=1; verify_fail<=1; verify_fail_code<=code;
            verify_fail_dev_addr<=I2C_ADDR; verify_fail_reg_addr<=addr;
            verify_fail_expected<=expected; verify_fail_actual<=actual;
            state<=ST_FAIL;
        end
    endtask

    // The same read engine is used first for PLL polling and then for the
    // fixed post-initialization register readback sequence.
    assign debug_pll_dev_idx=dev_idx; assign debug_pll_busy=pll_busy;
    assign debug_pll_done=pll_done; assign debug_pll_ack_error=pll_ack_error;
    assign debug_pll_read_data=pll_read_data;
    assign debug_pll_poll_count=pll_poll_count[7:0];
    assign debug_pll_read_addr_ack=pll_read_addr_ack;
    assign debug_pll_read_data_valid=pll_read_data_valid;
    assign debug_pll_dev_addr=I2C_ADDR;
    assign debug_write_ack_error=i2c_ack_error;
    assign debug_verify_done=pll_done && state==ST_DIAG_WAIT;
    assign debug_verify_read_addr_ack=pll_read_addr_ack;
    assign debug_verify_read_data_valid=pll_read_data_valid;
    assign debug_verify_read_data=pll_read_data;
    assign debug_verify_ack_error=pll_ack_error;
    assign last_dev_addr=i2c_last_dev_addr; assign last_reg_addr=i2c_last_reg_addr;
    assign last_wr_data=i2c_last_wr_data; assign last_ack_bits=i2c_last_ack_bits;
    assign debug_state=state; assign debug_wr_state=i2c_debug_wr_state;
    assign debug_wr_byte_idx=i2c_debug_wr_byte_idx;
    assign debug_wr_bit_idx=i2c_debug_wr_bit_idx;
    assign debug_wr_ack_sample_pulse=i2c_debug_wr_ack_sample_pulse;
    assign debug_wr_ack_sample_sda=i2c_debug_wr_ack_sample_sda;
    assign adau_scl_oe_n=pll_busy ? pll_scl_oe_n : write_scl_oe_n;
    assign adau_sda_oe_n=pll_busy ? pll_sda_oe_n : write_sda_oe_n;

    i2c_master_write8 #(.CLK_HZ(CLK_HZ), .I2C_HZ(I2C_HZ), .CHECK_ACK(1))
    i2c_master_write8_i (
        .clk(clk), .rstn(rstn), .start(i2c_start), .address_only(probing), .dev_addr(I2C_ADDR),
        .reg_addr(probing ? 8'hFF : reg_addr), .wr_data(reg_data), .busy(i2c_busy), .done(i2c_done),
        .ack_error(i2c_ack_error), .last_dev_addr(i2c_last_dev_addr),
        .last_reg_addr(i2c_last_reg_addr), .last_wr_data(i2c_last_wr_data),
        .ack_bits(i2c_last_ack_bits), .debug_state(i2c_debug_wr_state),
        .debug_byte_idx(i2c_debug_wr_byte_idx), .debug_bit_idx(i2c_debug_wr_bit_idx),
        .debug_ack_sample_pulse(i2c_debug_wr_ack_sample_pulse),
        .debug_ack_sample_sda(i2c_debug_wr_ack_sample_sda), .sda_i(adau_sda_i),
        .scl_oe_n(write_scl_oe_n), .sda_oe_n(write_sda_oe_n)
    );

    i2c_master_read8 #(.CLK_HZ(CLK_HZ), .I2C_HZ(I2C_HZ)) i2c_master_pll_read8_i (
        .clk(clk), .rstn(rstn), .start(pll_read_start), .dev_addr(I2C_ADDR),
        .reg_addr(read_reg_addr), .busy(pll_busy), .done(pll_done),
        .ack_error(pll_ack_error), .rd_data(pll_read_data),
        .read_addr_ack(pll_read_addr_ack), .read_data_valid(pll_read_data_valid),
        .sda_i(adau_sda_i), .scl_oe_n(pll_scl_oe_n), .sda_oe_n(pll_sda_oe_n)
    );

    // 48 kHz, 24-bit I2S in 32-bit slots; this device is the serial clock
    // master. Registers 0x0A..0x0D enable all four analog input paths.
    // After PLL lock, the same reader is pointed at the five diagnostic
    // registers requested by the PS software.
    always @(*) begin
        reg_addr=8'h00; reg_data=8'h00;
        read_reg_addr=8'h01;
        case (script_idx)
            8'd0:  begin reg_addr=8'h00; reg_data=8'h00; end
            8'd1:  begin reg_addr=8'h01; reg_data=8'h43; end
            8'd2:  begin reg_addr=8'h04; reg_data=8'hBF; end
            8'd3:  begin reg_addr=8'h05; reg_data=8'h02; end
            8'd4:  begin reg_addr=8'h06; reg_data=is_master ? 8'h01 : 8'h00; end
            8'd5:  begin reg_addr=8'h07; reg_data=8'h10; end
            8'd6:  begin reg_addr=8'h08; reg_data=8'h32; end
            8'd7:  begin reg_addr=8'h0A; reg_data=8'hA0; end
            8'd8:  begin reg_addr=8'h0B; reg_data=8'hA0; end
            8'd9:  begin reg_addr=8'h0C; reg_data=8'hA0; end
            8'd10: begin reg_addr=8'h0D; reg_data=8'hA0; end
            8'd11: begin reg_addr=8'h09; reg_data=8'hF0; end
            8'd12: begin reg_addr=8'h0E; reg_data=8'h02; end
            8'd13: begin reg_addr=8'h1A; reg_data=8'h0F; end
            8'd14: begin reg_addr=8'h00; reg_data=8'h01; end
            default: begin reg_addr=8'h00; reg_data=8'h00; end
        endcase
        case (diag_idx)
            3'd0: read_reg_addr=8'h00;
            3'd1: read_reg_addr=8'h01;
            3'd2: read_reg_addr=8'h04;
            3'd3: read_reg_addr=8'h05;
            3'd4: read_reg_addr=8'h06;
            default: read_reg_addr=8'h01;
        endcase
        case (diag_idx)
            0: expected_read=8'h01;
            1: expected_read=8'hC3; // PLL_LOCK plus the configured lower seven bits
            2: expected_read=8'hBF;
            3: expected_read=8'h02;
            4: expected_read=is_master ? 8'h01 : 8'h00;
            default: expected_read=0;
        endcase
        if ((state==ST_PLL_START) || (state==ST_PLL_WAIT) ||
            (state==ST_PLL_DELAY))
            read_reg_addr=8'h01;
    end

    always @(posedge clk) begin
        if (!rstn) begin
            state<=ST_RESET_LOW; wait_cnt<=0; pll_poll_count<=0;
            script_idx<=0; i2c_start<=0; pll_read_start<=0; started_once<=0;
            init_busy<=1; init_done<=0; init_error<=0; init_step<=0;
            ack_error_count<=0; verify_fail<=0; verify_fail_code<=0;
            verify_fail_dev_addr<=0; verify_fail_reg_addr<=0;
            verify_fail_expected<=0; verify_fail_actual<=0;
            debug_write_done<=0; adau_pd_rst<=0;
            dev_idx<=DUAL_ENABLE ? (AUDIO_MASTER==0) : 0;
            readback[0]<=0; readback[1]<=0;
            read_valid[0]<=0; read_valid[1]<=0; read_error[0]<=0; read_error[1]<=0;
            pll_locked<=0; writes_ok<=0; verified<=0; read_done<=0; diag_idx<=0;
            probe_attempted<=0; probe_done<=0; probe_ack<=0; probing<=1;
        end else begin
            i2c_start<=0; pll_read_start<=0; debug_write_done<=0;
            case (state)
                ST_RESET_LOW: begin
                    init_busy<=1; init_done<=0; adau_pd_rst<=0;
                    wait_cnt<=wait_cnt+1'b1;
                    if (wait_cnt>=POWERUP_WAIT_COUNT) begin wait_cnt<=0; state<=ST_RESET_HIGH; end
                end
                ST_RESET_HIGH: begin
                    adau_pd_rst<=1; wait_cnt<=wait_cnt+1'b1;
                    if (wait_cnt>=POWERUP_WAIT_COUNT) begin
                        wait_cnt<=0; script_idx<=0; init_step<=0; init_error<=0; state<=ST_START;
                    end
                end
                ST_IDLE: begin
                    init_busy<=0;
                    if (init_start || !started_once) begin
                        init_busy<=1; init_done<=0; init_error<=0; ack_error_count<=0;
                        script_idx<=0; init_step<=0; verify_fail<=0;
                        dev_idx<=DUAL_ENABLE ? (AUDIO_MASTER==0) : 0;
                        readback[0]<=0; readback[1]<=0;
                        read_valid[0]<=0; read_valid[1]<=0; read_error[0]<=0; read_error[1]<=0;
                        pll_locked<=0; writes_ok<=0; verified<=0; read_done<=0;
                        probe_attempted<=0; probe_done<=0; probe_ack<=0; probing<=1;
                        diag_idx<=0; state<=ST_RESET_LOW;
                    end
                end
                ST_LOAD: begin
                    init_step<=script_idx;
                    if (script_idx>=8'd15) begin writes_ok[dev_idx]<=1; wait_cnt<=0; state<=ST_DELAY; end
                    else state<=ST_START;
                end
                ST_START: if (!i2c_busy) begin
                    i2c_start<=1;
                    if (probing) begin probe_attempted[dev_idx]<=1; state<=ST_PROBE_WAIT; end
                    else state<=ST_WAIT;
                end
                ST_PROBE_WAIT: if (i2c_done) begin
                    probe_done[dev_idx]<=1;
                    probe_ack[dev_idx]<=!i2c_ack_error && i2c_last_ack_bits[0];
                    probing<=0;
                    if (i2c_ack_error || !i2c_last_ack_bits[0]) begin
                        ack_error_count<=ack_error_count+1'b1;
                        // FF denotes the address-only phase, not a register access.
                        record_failure(1,8'hFF,8'h01,8'h00);
                    end else state<=ST_LOAD;
                end
                ST_MASTER_SETTLE: begin
                    // Keep shared PD/RST high and both engines idle for 100 ms.
                    if (wait_cnt>=POWERUP_WAIT_COUNT-1) begin wait_cnt<=0; state<=ST_START; end
                    else wait_cnt<=wait_cnt+1'b1;
                end
                ST_WAIT: if (i2c_done) begin
                    debug_write_done<=1;
                    if (i2c_ack_error) begin
                        ack_error_count<=ack_error_count+1'b1;
                        record_failure(1,reg_addr,reg_data,8'hFF);
                    end else begin script_idx<=script_idx+1'b1; state<=ST_LOAD; end
                end
                ST_DELAY: begin
                    wait_cnt<=wait_cnt+1'b1;
                    if (wait_cnt>=PLL_WAIT_COUNT) begin
                        wait_cnt<=0; pll_poll_count<=0; state<=ST_PLL_START;
                    end
                end
                ST_PLL_START: if (!pll_busy) begin pll_read_start<=1; state<=ST_PLL_WAIT; end
                ST_PLL_WAIT: if (pll_done) begin
                    if (read_failed) begin
                        ack_error_count<=ack_error_count+1'b1;
                        record_failure(1,8'h01,8'hC3,pll_read_data);
                    end
                    else if (pll_read_data[7]) begin
                        pll_locked[dev_idx]<=1; diag_idx<=0; state<=ST_DIAG_START;
                    end
                    else if (pll_poll_count>=PLL_POLL_LIMIT-1) record_failure(2,8'h01,8'hC3,pll_read_data);
                    else begin pll_poll_count<=pll_poll_count+1'b1; wait_cnt<=0; state<=ST_PLL_DELAY; end
                end
                ST_PLL_DELAY: begin wait_cnt<=wait_cnt+1'b1; if (wait_cnt>=PLL_POLL_INTERVAL_COUNT) state<=ST_PLL_START; end
                ST_DIAG_START: begin
                    if (!pll_busy) begin pll_read_start<=1; state<=ST_DIAG_WAIT; end
                end
                ST_DIAG_WAIT: if (pll_done) begin
                    // Keep the actual byte even on error; valid distinguishes bus success.
                    readback[dev_idx][diag_idx*8 +: 8] <= pll_read_data;
                    read_valid[dev_idx][diag_idx] <= !read_failed;
                    if (read_failed || pll_read_data!=expected_read) begin
                        read_error[dev_idx][diag_idx]<=1;
                        read_done[dev_idx]<=1;
                        if (read_failed) ack_error_count<=ack_error_count+1'b1;
                        record_failure(read_failed ? 2'd1 : 2'd3,read_reg_addr,
                                       expected_read,pll_read_data);
                    end else if (diag_idx==4) begin
                        read_done[dev_idx]<=1; verified[dev_idx]<=1; state<=ST_DONE;
                    end else begin diag_idx<=diag_idx+1'b1; state<=ST_DIAG_START; end
                end
                ST_DONE: begin
                    if (DUAL_ENABLE && !is_master) begin
                        // The slave is fully verified. Switch address, never pulse shared PD/RST.
                        dev_idx<=AUDIO_MASTER; script_idx<=0; diag_idx<=0;
                        wait_cnt<=0; pll_poll_count<=0; probing<=1; state<=ST_MASTER_SETTLE;
                    end else begin
                        started_once<=1; init_done<=verified[0] && (!DUAL_ENABLE || verified[1]);
                        init_busy<=0; state<=ST_IDLE;
                    end
                end
                ST_FAIL: begin init_done<=0; started_once<=1; init_busy<=0; state<=ST_IDLE; end
                default: state<=ST_RESET_LOW;
            endcase
        end
    end
endmodule
