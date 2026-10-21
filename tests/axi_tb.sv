`timescale 1ns/1ps
module axi_tb;
 reg clk=0; always #5 clk=~clk;
 reg rstn=0;
 reg [7:0] awaddr=0,araddr=0; reg [31:0] wdata=0;
 reg awvalid=0,wvalid=0,arvalid=0; wire awready,wready,bvalid,arready,rvalid;
 wire [31:0] rdata; wire [1:0] bresp,rresp;
 wire scl,sda_release,pd; tri1 sda;
 assign sda=sda_release ? 1'bz:1'b0;
 wire [255:0] data; wire [31:0] keep; wire valid,last; integer received=0,packets=0,scenario=0;
 reg bclk=0,lr=1; reg [3:0] audio=0; reg [31:0] value;
 wire [7:0] ra,rb;
 adau_model #(.ADDRESS(7'h11)) a(scl,pd,sda,1'b0,1'b0,1'b0,ra);
 adau_model #(.ADDRESS(7'h31)) b(scl,pd,sda,(scenario==1),1'b0,1'b0,rb);
 adau1979_capture_v1_0_S00_AXI #(.CLK_HZ(100000),.I2C_HZ(1000)) dut(
  .adau_bclk(bclk),.adau_lrclk(lr),.adau_sdata(audio),.adau_pd_rst(pd),.adau_sda_i(sda),
  .adau_scl_oe_n(scl),.adau_sda_oe_n(sda_release),.m00_axis_aclk(clk),.m00_axis_aresetn(rstn),
  .m00_axis_tdata(data),.m00_axis_tkeep(keep),.m00_axis_tlast(last),.m00_axis_tvalid(valid),.m00_axis_tready(1'b1),
  .S_AXI_ACLK(clk),.S_AXI_ARESETN(rstn),.S_AXI_AWADDR(awaddr),.S_AXI_AWPROT(3'd0),
  .S_AXI_AWVALID(awvalid),.S_AXI_AWREADY(awready),.S_AXI_WDATA(wdata),.S_AXI_WSTRB(4'hf),
  .S_AXI_WVALID(wvalid),.S_AXI_WREADY(wready),.S_AXI_BRESP(bresp),.S_AXI_BVALID(bvalid),.S_AXI_BREADY(1'b1),
  .S_AXI_ARADDR(araddr),.S_AXI_ARPROT(3'd0),.S_AXI_ARVALID(arvalid),.S_AXI_ARREADY(arready),
  .S_AXI_RDATA(rdata),.S_AXI_RRESP(rresp),.S_AXI_RVALID(rvalid),.S_AXI_RREADY(1'b1));
 task write_reg;
  input [7:0] addr; input [31:0] v;
  begin
   @(negedge clk); awaddr=addr; wdata=v; awvalid=1; wvalid=1;
   @(posedge clk); while(!(awready && wready)) @(posedge clk); @(negedge clk); awvalid=0; wvalid=0;
   wait(bvalid); @(negedge clk);
  end
 endtask
 task read_reg;
  input [7:0] addr;
  begin
   @(negedge clk); araddr=addr; arvalid=1;
   @(posedge clk); while(!arready) @(posedge clk); @(negedge clk); arvalid=0;
   wait(rvalid); #1 value=rdata; @(negedge clk);
  end
 endtask
 task expect_reg;
  input [7:0] addr; input [31:0] v;
  begin read_reg(addr); if(value!==v) $fatal(1,"AXI addr=%h actual=%h expected=%h",addr,value,v); end
 endtask
 integer n,k;
 initial begin
  wait(rstn);
  forever begin
   lr=0; bclk=0; #80;
   for(k=0;k<32;k=k+1) begin bclk=0; audio=4'b0101; #80; bclk=1; #80; end
   lr=1; bclk=0; #80;
   for(k=0;k<32;k=k+1) begin bclk=0; audio=4'b1010; #80; bclk=1; #80; end
  end
 end
 always @(posedge clk) if(valid) begin
  if(!dut.init_done) $fatal(1,"unverified capture escaped gate");
  received=received+1; if(last) packets=packets+1;
 end
 initial begin
  if($test$plusargs("scenario1")) scenario=1;
  if($test$plusargs("scenario2")) scenario=2;
  if($test$plusargs("scenario3")) scenario=3;
  #100 rstn=1; #100;
  expect_reg(8'h60,32'hAD790208); expect_reg(8'h64,32'h2701);
  write_reg(8'h04,1024); write_reg(8'h00,1);
  // RO high-bank writes must not alias legacy control/sample length.
  write_reg(8'h80,0); write_reg(8'h84,123);
  expect_reg(8'h00,1); expect_reg(8'h04,1024);
  wait(!dut.init_busy); #100;
  if(scenario==1) begin
   if(!dut.init_error) $fatal(1,"NACK must fail");
   expect_reg(8'hB8,32'h1B100);
   #100000; if(received!=0) $fatal(1,"NACK capture enabled");
  end else begin
   expect_reg(8'h80,32'h0023F07E); expect_reg(8'hA0,32'h0062F07E);
   expect_reg(8'h84,1); expect_reg(8'h88,8'hc3); expect_reg(8'h8c,8'hbf);
   expect_reg(8'h90,2); expect_reg(8'h94,1);
   expect_reg(8'ha4,1); expect_reg(8'ha8,8'hc3); expect_reg(8'hac,8'hbf);
   expect_reg(8'hb0,2); expect_reg(8'hb4,0);
   expect_reg(8'h40,32'h7e); expect_reg(8'h44,1); expect_reg(8'h54,1);
   expect_reg(8'hB8,0);
   wait(received>=2048); #100;
   expect_reg(8'h00,1); // Packet notification never disarms continuous capture.
   read_reg(8'hBC); if(value<2048 || packets!=2) $fatal(1,"continuous packet count");
  end
  $display("PASS AXI scenario=%0d banks>=0x80 no alias, init gate, continuous START",scenario); $finish;
 end
 initial begin #50000000; $fatal(1,"AXI timeout received=%d",received); end
endmodule
