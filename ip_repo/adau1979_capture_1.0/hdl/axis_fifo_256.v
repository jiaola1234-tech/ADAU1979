`timescale 1 ns / 1 ps

module axis_fifo_256 #
(
    parameter integer ADDR_WIDTH = 10
)
(
    input  wire         clk,
    input  wire         rstn,
    input  wire         clear,

    input  wire         wr_en,
    input  wire [255:0] wr_data,
    output wire         full,
    output wire [31:0]  overflow_count,
    output wire [31:0]  level,

    output reg  [255:0] m_axis_tdata,
    output wire [31:0]  m_axis_tkeep,
    output reg          m_axis_tvalid,
    input  wire         m_axis_tready,
    output wire         m_axis_tlast,

    input  wire         packet_enable,
    input  wire [31:0]  packet_len,
    output reg          packet_done,
    output reg  [31:0]  packet_count
);

    localparam integer DEPTH = (1 << ADDR_WIDTH);
    localparam [ADDR_WIDTH:0] DEPTH_COUNT = (1 << ADDR_WIDTH);

    (* ram_style = "block" *) reg [255:0] mem [0:DEPTH-1];
    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;
    reg [ADDR_WIDTH:0] count;
    reg [31:0] overflow_count_r;

    wire do_write = wr_en && !full;
    wire do_handshake = m_axis_tvalid && m_axis_tready;
    wire can_advance = !m_axis_tvalid || (m_axis_tready && !m_axis_tlast);
    wire can_load = can_advance && (count != 0) && packet_enable && !packet_done;
    wire do_read = can_load;
    // Zero is not a valid finite DMA packet length.  Fall back to one FIFO
    // depth while still allowing longer packets to stream through the FIFO.
    wire [31:0] effective_len = (packet_len == 32'd0) ? DEPTH : packet_len;

    assign full = (count == DEPTH_COUNT);
    assign overflow_count = overflow_count_r;
    assign level = {{(31-ADDR_WIDTH){1'b0}}, count};
    assign m_axis_tkeep = 32'hFFFF_FFFF;
    assign m_axis_tlast = packet_enable && m_axis_tvalid &&
                          (packet_count == effective_len - 1'b1);

    always @(posedge clk) begin
        if (!rstn) begin
            wr_ptr <= {ADDR_WIDTH{1'b0}};
            rd_ptr <= {ADDR_WIDTH{1'b0}};
            count <= {(ADDR_WIDTH+1){1'b0}};
            m_axis_tdata <= 256'd0;
            m_axis_tvalid <= 1'b0;
            overflow_count_r <= 32'd0;
            packet_done <= 1'b0;
            packet_count <= 32'd0;
        end else if (clear) begin
            wr_ptr <= {ADDR_WIDTH{1'b0}};
            rd_ptr <= {ADDR_WIDTH{1'b0}};
            count <= {(ADDR_WIDTH+1){1'b0}};
            m_axis_tdata <= 256'd0;
            m_axis_tvalid <= 1'b0;
            packet_done <= 1'b0;
            packet_count <= 32'd0;
        end else begin
            packet_done <= packet_done;

            if (!packet_enable) begin
                packet_done <= 1'b0;
                packet_count <= 32'd0;
            end

            if (wr_en && full)
                overflow_count_r <= overflow_count_r + 1'b1;

            if (do_write) begin
                mem[wr_ptr] <= wr_data;
                wr_ptr <= wr_ptr + 1'b1;
            end

            if (do_handshake) begin
                if (m_axis_tlast) begin
                    packet_done <= 1'b1;
                    packet_count <= 32'd0;
                end else begin
                    packet_count <= packet_count + 1'b1;
                end
            end

            if (can_load) begin
                m_axis_tdata <= mem[rd_ptr];
                m_axis_tvalid <= 1'b1;
                rd_ptr <= rd_ptr + 1'b1;
            end else if (do_handshake && !can_load) begin
                m_axis_tvalid <= 1'b0;
            end

            case ({do_write, do_read})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

endmodule
