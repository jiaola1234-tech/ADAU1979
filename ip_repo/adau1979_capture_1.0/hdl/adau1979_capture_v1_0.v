`timescale 1 ns / 1 ps

module adau1979_capture_v1_0 #
(
    parameter integer C_S00_AXI_DATA_WIDTH = 32,
    parameter integer C_S00_AXI_ADDR_WIDTH = 6,
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
    output wire        adau_scl,
    inout  wire        adau_sda,
    output wire [63:0] i2c_debug,
    output wire        i2c_scl_dbg,
    output wire        i2c_sda_dbg,

    output wire [255:0] m00_axis_tdata,
    output wire [31:0]  m00_axis_tkeep,
    output wire         m00_axis_tlast,
    input  wire         m00_axis_tready,
    output wire         m00_axis_tvalid,
    input  wire         m00_axis_aresetn,
    input  wire         m00_axis_aclk,

    input  wire  s00_axi_aclk,
    input  wire  s00_axi_aresetn,
    input  wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_awaddr,
    input  wire [2 : 0] s00_axi_awprot,
    input  wire  s00_axi_awvalid,
    output wire  s00_axi_awready,
    input  wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_wdata,
    input  wire [(C_S00_AXI_DATA_WIDTH/8)-1 : 0] s00_axi_wstrb,
    input  wire  s00_axi_wvalid,
    output wire  s00_axi_wready,
    output wire [1 : 0] s00_axi_bresp,
    output wire  s00_axi_bvalid,
    input  wire  s00_axi_bready,
    input  wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_araddr,
    input  wire [2 : 0] s00_axi_arprot,
    input  wire  s00_axi_arvalid,
    output wire  s00_axi_arready,
    output wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_rdata,
    output wire [1 : 0] s00_axi_rresp,
    output wire  s00_axi_rvalid,
    input  wire  s00_axi_rready
);

    wire adau_sda_i;
    wire adau_scl_oe_n;
    wire adau_sda_oe_n;

    // Keep I2C open-drain behavior explicit at the IP top level so Vivado
    // inserts complete input/output buffers for the external bidirectional pins.
    // ADAU1979 does not use clock stretching in this design, so SCL only
    // needs an open-drain output buffer.  SDA remains bidirectional for ACK
    // and register reads.
    OBUFT adau_scl_obuf (
        .I(1'b0),
        .T(adau_scl_oe_n),
        .O(adau_scl)
    );

    IOBUF adau_sda_iobuf (
        .I(1'b0),
        .O(adau_sda_i),
        .T(adau_sda_oe_n),
        .IO(adau_sda)
    );

    // Fabric-safe debug taps.  Do not probe the external OBUFT/IOBUF pins
    // directly: Vivado's implementation DRC rejects those loads.  SCL is
    // open-drain, so its logical level is high when released and low when
    // driven.  SDA is the IOBUF input sample, including slave ACKs.
    assign i2c_scl_dbg = ~adau_scl_oe_n;
    assign i2c_sda_dbg = adau_sda_i;

    adau1979_capture_v1_0_S00_AXI #(
        .C_S_AXI_DATA_WIDTH(C_S00_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S00_AXI_ADDR_WIDTH),
        .SLOT_BITS(SLOT_BITS),
        .WORD_BITS(WORD_BITS),
        .LR_POLARITY(LR_POLARITY),
        .I2S_DELAY(I2S_DELAY),
        .FIFO_ADDR_WIDTH(FIFO_ADDR_WIDTH),
        .CLK_HZ(CLK_HZ),
        .I2C_HZ(I2C_HZ),
        .U1_I2C_ADDR(U1_I2C_ADDR),
        .U2_I2C_ADDR(U2_I2C_ADDR)
    ) s00_axi_inst (
        .adau_bclk(adau_bclk),
        .adau_lrclk(adau_lrclk),
        .adau_sdata(adau_sdata),
        .adau_pd_rst(adau_pd_rst),
        .adau_sda_i(adau_sda_i),
        .adau_scl_oe_n(adau_scl_oe_n),
        .adau_sda_oe_n(adau_sda_oe_n),
        .i2c_debug(i2c_debug),
        .m00_axis_tdata(m00_axis_tdata),
        .m00_axis_tkeep(m00_axis_tkeep),
        .m00_axis_tlast(m00_axis_tlast),
        .m00_axis_tready(m00_axis_tready),
        .m00_axis_tvalid(m00_axis_tvalid),
        .m00_axis_aresetn(m00_axis_aresetn),
        .m00_axis_aclk(m00_axis_aclk),
        .S_AXI_ACLK(s00_axi_aclk),
        .S_AXI_ARESETN(s00_axi_aresetn),
        .S_AXI_AWADDR(s00_axi_awaddr),
        .S_AXI_AWPROT(s00_axi_awprot),
        .S_AXI_AWVALID(s00_axi_awvalid),
        .S_AXI_AWREADY(s00_axi_awready),
        .S_AXI_WDATA(s00_axi_wdata),
        .S_AXI_WSTRB(s00_axi_wstrb),
        .S_AXI_WVALID(s00_axi_wvalid),
        .S_AXI_WREADY(s00_axi_wready),
        .S_AXI_BRESP(s00_axi_bresp),
        .S_AXI_BVALID(s00_axi_bvalid),
        .S_AXI_BREADY(s00_axi_bready),
        .S_AXI_ARADDR(s00_axi_araddr),
        .S_AXI_ARPROT(s00_axi_arprot),
        .S_AXI_ARVALID(s00_axi_arvalid),
        .S_AXI_ARREADY(s00_axi_arready),
        .S_AXI_RDATA(s00_axi_rdata),
        .S_AXI_RRESP(s00_axi_rresp),
        .S_AXI_RVALID(s00_axi_rvalid),
        .S_AXI_RREADY(s00_axi_rready)
    );

endmodule
