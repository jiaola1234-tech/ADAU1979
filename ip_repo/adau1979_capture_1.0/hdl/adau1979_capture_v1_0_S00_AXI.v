`timescale 1 ns / 1 ps

module adau1979_capture_v1_0_S00_AXI #
(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 6,
    parameter integer SLOT_BITS = 32,
    parameter integer WORD_BITS = 24,
    parameter integer LR_POLARITY = 1,
    parameter integer I2S_DELAY = 1,
    parameter integer FIFO_ADDR_WIDTH = 10,
    parameter integer CLK_HZ = 50000000,
    parameter integer I2C_HZ = 100000,
    parameter [6:0] U1_I2C_ADDR = 7'h11,
    parameter [6:0] U2_I2C_ADDR = 7'h31
)
(
    input  wire        adau_bclk,
    input  wire        adau_lrclk,
    input  wire [3:0]  adau_sdata,
    output wire        adau_pd_rst,
    input  wire        adau_sda_i,
    output wire        adau_scl_oe_n,
    output wire        adau_sda_oe_n,
    output wire [63:0] i2c_debug,

    output wire [255:0] m00_axis_tdata,
    output wire [31:0]  m00_axis_tkeep,
    output wire         m00_axis_tlast,
    input  wire         m00_axis_tready,
    output wire         m00_axis_tvalid,
    input  wire         m00_axis_aresetn,
    input  wire         m00_axis_aclk,

    input  wire  S_AXI_ACLK,
    input  wire  S_AXI_ARESETN,
    input  wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_AWADDR,
    input  wire [2 : 0] S_AXI_AWPROT,
    input  wire  S_AXI_AWVALID,
    output wire  S_AXI_AWREADY,
    input  wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_WDATA,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1 : 0] S_AXI_WSTRB,
    input  wire  S_AXI_WVALID,
    output wire  S_AXI_WREADY,
    output wire [1 : 0] S_AXI_BRESP,
    output wire  S_AXI_BVALID,
    input  wire  S_AXI_BREADY,
    input  wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_ARADDR,
    input  wire [2 : 0] S_AXI_ARPROT,
    input  wire  S_AXI_ARVALID,
    output wire  S_AXI_ARREADY,
    output wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_RDATA,
    output wire [1 : 0] S_AXI_RRESP,
    output wire  S_AXI_RVALID,
    input  wire  S_AXI_RREADY
);

    localparam integer ADDR_LSB = (C_S_AXI_DATA_WIDTH/32) + 1;
    localparam integer OPT_MEM_ADDR_BITS = 3;

    reg [C_S_AXI_ADDR_WIDTH-1 : 0] axi_awaddr;
    reg axi_awready;
    reg axi_wready;
    reg [1 : 0] axi_bresp;
    reg axi_bvalid;
    reg [C_S_AXI_ADDR_WIDTH-1 : 0] axi_araddr;
    reg axi_arready;
    reg [C_S_AXI_DATA_WIDTH-1 : 0] axi_rdata;
    reg [1 : 0] axi_rresp;
    reg axi_rvalid;
    reg aw_en;

    reg [31:0] slv_reg0;
    reg [31:0] slv_reg1;
    reg [31:0] slv_reg2;
    reg [31:0] slv_reg3;
    reg [31:0] slv_reg4;
    reg [31:0] slv_reg5;
    reg [31:0] slv_reg6;
    reg [31:0] slv_reg7;
    reg [31:0] slv_reg8;
    reg [31:0] slv_reg9;
    reg [31:0] slv_reg10;
    // The internal FIFO holds 2^FIFO_ADDR_WIDTH audio frames.  Keep the
    // power-on packet length within that tested buffer size.
    localparam [31:0] DEFAULT_SAMPLE_LEN = (32'd1 << FIFO_ADDR_WIDTH);
    wire slv_reg_rden;
    wire slv_reg_wren;
    reg [31:0] reg_data_out;
    integer byte_index;

    wire [31:0] i2s_frame_count;
    wire [31:0] i2s_sync_error_count;
    wire [31:0] fifo_overflow_count;
    wire [31:0] fifo_level;
    wire fifo_full;
    wire packet_done;
    wire [31:0] packet_count;
    wire init_busy;
    wire init_done;
    wire init_error;
    wire [7:0] init_step;
    wire [31:0] i2c_ack_error_count;
    wire [6:0] i2c_last_dev_addr;
    wire [7:0] i2c_last_reg_addr;
    wire [7:0] i2c_last_wr_data;
    wire [2:0] i2c_last_ack_bits;
    wire [3:0] i2c_debug_state;
    wire i2c_debug_pll_dev_idx;
    wire i2c_debug_pll_busy;
    wire i2c_debug_pll_done;
    wire i2c_debug_pll_ack_error;
    wire [7:0] i2c_debug_pll_read_data;
    wire [7:0] i2c_debug_pll_poll_count;
    wire [4:0] i2c_debug_wr_state;
    wire [2:0] i2c_debug_wr_byte_idx;
    wire [2:0] i2c_debug_wr_bit_idx;
    wire i2c_debug_wr_ack_sample_pulse;
    wire i2c_debug_wr_ack_sample_sda;

    // ILA probe bus.  This is intentionally not an AXI register: it exposes
    // the live I2C pin/control state and the last completed write transaction.
    assign i2c_debug = {
        init_step,                 // [63:56]
        init_busy,                 // [55]
        init_done,                 // [54]
        init_error,                // [53]
        adau_pd_rst,               // [52]
        adau_sda_i,                // [51]
        adau_scl_oe_n,             // [50] 1 = released (open drain)
        adau_sda_oe_n,             // [49] 1 = released (open drain)
        i2c_last_dev_addr,         // [48:42]
        i2c_last_reg_addr,         // [41:34]
        i2c_last_wr_data,           // [33:26]
        i2c_last_ack_bits,          // [25:23]
        i2c_debug_wr_state,         // [22:18]
        i2c_debug_wr_byte_idx,      // [17:15]
        i2c_debug_wr_bit_idx,       // [14:12]
        i2c_debug_wr_ack_sample_pulse, // [11]
        i2c_debug_wr_ack_sample_sda,   // [10]
        i2c_debug_state,             // [9:6]
        i2c_debug_pll_dev_idx,       // [5]
        i2c_debug_pll_busy,          // [4]
        i2c_debug_pll_ack_error,     // [3]
        i2c_debug_pll_done,          // [2]
        i2c_debug_pll_poll_count[1:0] // [1:0]
    };

    reg init_start_req;
    reg init_start_d0;
    reg init_start_d1;
    reg init_start_d2;
    wire init_start_pulse = init_start_d1 & ~init_start_d2;
    reg packet_done_d0;
    reg packet_done_d1;
    reg packet_done_d2;
    wire packet_done_axi = packet_done_d1 & ~packet_done_d2;

    assign S_AXI_AWREADY = axi_awready;
    assign S_AXI_WREADY = axi_wready;
    assign S_AXI_BRESP = axi_bresp;
    assign S_AXI_BVALID = axi_bvalid;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RDATA = axi_rdata;
    assign S_AXI_RRESP = axi_rresp;
    assign S_AXI_RVALID = axi_rvalid;

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_awready <= 1'b0;
            aw_en <= 1'b1;
        end else begin
            if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en) begin
                axi_awready <= 1'b1;
                aw_en <= 1'b0;
            end else if (S_AXI_BREADY && axi_bvalid) begin
                aw_en <= 1'b1;
                axi_awready <= 1'b0;
            end else begin
                axi_awready <= 1'b0;
            end
        end
    end

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN)
            axi_awaddr <= {C_S_AXI_ADDR_WIDTH{1'b0}};
        else if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en)
            axi_awaddr <= S_AXI_AWADDR;
    end

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN)
            axi_wready <= 1'b0;
        else if (~axi_wready && S_AXI_WVALID && S_AXI_AWVALID && aw_en)
            axi_wready <= 1'b1;
        else
            axi_wready <= 1'b0;
    end

    assign slv_reg_wren = axi_wready && S_AXI_WVALID && axi_awready && S_AXI_AWVALID;

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            slv_reg0 <= 32'd0;
            slv_reg1 <= DEFAULT_SAMPLE_LEN;
            init_start_req <= 1'b0;
        end else begin
            init_start_req <= 1'b0;
            slv_reg0[1] <= 1'b0;
            if (packet_done_axi)
                slv_reg0[0] <= 1'b0;

            if (slv_reg_wren) begin
                case (axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB])
                    4'h0: begin
                        for (byte_index = 0; byte_index <= 3; byte_index = byte_index + 1)
                            if (S_AXI_WSTRB[byte_index])
                                slv_reg0[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                        if (S_AXI_WDATA[1])
                            init_start_req <= 1'b1;
                    end
                    4'h1: begin
                        for (byte_index = 0; byte_index <= 3; byte_index = byte_index + 1)
                            if (S_AXI_WSTRB[byte_index])
                                slv_reg1[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    end
                    default: begin
                    end
                endcase
            end
        end
    end

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            init_start_d0 <= 1'b0;
            init_start_d1 <= 1'b0;
            init_start_d2 <= 1'b0;
            packet_done_d0 <= 1'b0;
            packet_done_d1 <= 1'b0;
            packet_done_d2 <= 1'b0;
        end else begin
            init_start_d0 <= init_start_req;
            init_start_d1 <= init_start_d0;
            init_start_d2 <= init_start_d1;
            packet_done_d0 <= packet_done;
            packet_done_d1 <= packet_done_d0;
            packet_done_d2 <= packet_done_d1;
        end
    end

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            slv_reg2 <= 32'd0;
            slv_reg3 <= 32'd0;
            slv_reg4 <= 32'd0;
            slv_reg5 <= 32'd0;
            slv_reg6 <= 32'd0;
            slv_reg7 <= 32'd0;
            slv_reg8 <= 32'd0;
            slv_reg9 <= 32'd0;
            slv_reg10 <= 32'd0;
        end else begin
            slv_reg2 <= {
                16'd0,
                init_step,
                3'd0,
                fifo_full,
                init_error,
                init_done,
                init_busy,
                slv_reg0[0]
            };
            slv_reg3 <= i2s_frame_count;
            slv_reg4 <= packet_count;
            slv_reg5 <= fifo_level;
            slv_reg6 <= fifo_overflow_count;
            slv_reg7 <= i2s_sync_error_count + i2c_ack_error_count;
            slv_reg8 <= {25'd0, i2c_last_dev_addr};
            slv_reg9 <= {16'd0, i2c_last_reg_addr, i2c_last_wr_data};
            slv_reg10 <= {29'd0, i2c_last_ack_bits};
        end
    end

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_bvalid <= 1'b0;
            axi_bresp <= 2'b0;
        end else if (axi_awready && S_AXI_AWVALID && ~axi_bvalid && axi_wready && S_AXI_WVALID) begin
            axi_bvalid <= 1'b1;
            axi_bresp <= 2'b0;
        end else if (S_AXI_BREADY && axi_bvalid) begin
            axi_bvalid <= 1'b0;
        end
    end

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_arready <= 1'b0;
            axi_araddr <= {C_S_AXI_ADDR_WIDTH{1'b0}};
        end else if (~axi_arready && S_AXI_ARVALID) begin
            axi_arready <= 1'b1;
            axi_araddr <= S_AXI_ARADDR;
        end else begin
            axi_arready <= 1'b0;
        end
    end

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_rvalid <= 1'b0;
            axi_rresp <= 2'b0;
        end else if (axi_arready && S_AXI_ARVALID && ~axi_rvalid) begin
            axi_rvalid <= 1'b1;
            axi_rresp <= 2'b0;
        end else if (axi_rvalid && S_AXI_RREADY) begin
            axi_rvalid <= 1'b0;
        end
    end

    assign slv_reg_rden = axi_arready & S_AXI_ARVALID & ~axi_rvalid;

    always @(*) begin
        case (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB])
            4'h0: reg_data_out = slv_reg0;
            4'h1: reg_data_out = slv_reg1;
            4'h2: reg_data_out = slv_reg2;
            4'h3: reg_data_out = slv_reg3;
            4'h4: reg_data_out = slv_reg4;
            4'h5: reg_data_out = slv_reg5;
            4'h6: reg_data_out = slv_reg6;
            4'h7: reg_data_out = slv_reg7;
            4'h8: reg_data_out = slv_reg8;
            4'h9: reg_data_out = slv_reg9;
            4'hA: reg_data_out = slv_reg10;
            default: reg_data_out = 32'd0;
        endcase
    end

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN)
            axi_rdata <= 32'd0;
        else if (slv_reg_rden)
            axi_rdata <= reg_data_out;
    end

    adau1979_i2c_init #(
        .CLK_HZ(CLK_HZ),
        .I2C_HZ(I2C_HZ),
        .U1_ADDR(U1_I2C_ADDR),
        .U2_ADDR(U2_I2C_ADDR)
    ) adau1979_i2c_init_i (
        .clk(S_AXI_ACLK),
        .rstn(S_AXI_ARESETN),
        .init_start(init_start_pulse),
        .init_busy(init_busy),
        .init_done(init_done),
        .init_error(init_error),
        .init_step(init_step),
        .ack_error_count(i2c_ack_error_count),
        .last_dev_addr(i2c_last_dev_addr),
        .last_reg_addr(i2c_last_reg_addr),
        .last_wr_data(i2c_last_wr_data),
        .last_ack_bits(i2c_last_ack_bits),
        .debug_state(i2c_debug_state),
        .debug_pll_dev_idx(i2c_debug_pll_dev_idx),
        .debug_pll_busy(i2c_debug_pll_busy),
        .debug_pll_done(i2c_debug_pll_done),
        .debug_pll_ack_error(i2c_debug_pll_ack_error),
        .debug_pll_read_data(i2c_debug_pll_read_data),
        .debug_pll_poll_count(i2c_debug_pll_poll_count),
        .debug_wr_state(i2c_debug_wr_state),
        .debug_wr_byte_idx(i2c_debug_wr_byte_idx),
        .debug_wr_bit_idx(i2c_debug_wr_bit_idx),
        .debug_wr_ack_sample_pulse(i2c_debug_wr_ack_sample_pulse),
        .debug_wr_ack_sample_sda(i2c_debug_wr_ack_sample_sda),
        .adau_pd_rst(adau_pd_rst),
        .adau_sda_i(adau_sda_i),
        .adau_scl_oe_n(adau_scl_oe_n),
        .adau_sda_oe_n(adau_sda_oe_n)
    );

    adau1979_capture_core #(
        .SLOT_BITS(SLOT_BITS),
        .WORD_BITS(WORD_BITS),
        .LR_POLARITY(LR_POLARITY),
        .I2S_DELAY(I2S_DELAY),
        .FIFO_ADDR_WIDTH(FIFO_ADDR_WIDTH)
    ) adau1979_capture_core_i (
        .clk(m00_axis_aclk),
        .rstn(m00_axis_aresetn),
        .capture_enable(slv_reg0[0] & init_done),
        .init_done(init_done),
        .sample_len(slv_reg1),
        .bclk(adau_bclk),
        .lrclk(adau_lrclk),
        .sdata(adau_sdata),
        .m_axis_tdata(m00_axis_tdata),
        .m_axis_tkeep(m00_axis_tkeep),
        .m_axis_tlast(m00_axis_tlast),
        .m_axis_tready(m00_axis_tready),
        .m_axis_tvalid(m00_axis_tvalid),
        .i2s_frame_count(i2s_frame_count),
        .i2s_sync_error_count(i2s_sync_error_count),
        .fifo_overflow_count(fifo_overflow_count),
        .fifo_level(fifo_level),
        .fifo_full(fifo_full),
        .packet_done(packet_done),
        .packet_count(packet_count)
    );

endmodule
