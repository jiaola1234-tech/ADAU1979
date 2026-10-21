`timescale 1ns/1ps
// Pin-level, open-drain register model; no references to DUT internals.
module adau_model #(parameter [6:0] ADDRESS=7'h11)(
 input scl, input reset_n, inout sda, input nack, input unlock, input corrupt,
 output reg [7:0] role);
 reg drive=0;
 assign sda=drive ? 1'b0 : 1'bz;
 reg [7:0] regs[0:255];
 reg [7:0] shift=0, value=0, pointer=0, tx=0;
 integer mode=4, stage=0, count=0, bitpos=7, i;
 reg selected=0, reading=0, ack_clocked=0;
 initial begin role=0; for(i=0;i<256;i=i+1) regs[i]=0; end
 always @(negedge reset_n) begin
  drive=0; mode=4; role=0;
  for(i=0;i<256;i=i+1) regs[i]=0;
 end
 always @(negedge sda) if(scl && reset_n) begin
  mode=0; stage=0; count=0; shift=0; selected=0; reading=0; ack_clocked=0;
 end
 always @(posedge sda) if(scl) begin mode=4; drive=0; end
 always @(posedge scl) if(reset_n) begin
  if(mode==0) begin
   shift={shift[6:0],sda};
   if(count==7) begin
    value=shift; count=0; mode=1; ack_clocked=0;
    if(stage==0) begin selected=(value[7:1]==ADDRESS && !nack); reading=value[0]; end
    else if(selected && stage==1) pointer=value;
    else if(selected && stage==2) begin regs[pointer]=value; if(pointer==6) role=value; end
   end else count=count+1;
  end else if(mode==1) ack_clocked=1;
  else if(mode==2) begin
   if(bitpos==0) mode=3; else bitpos=bitpos-1;
  end else if(mode==3) mode=4;
 end
 always @(negedge scl) if(reset_n) begin
  if(mode==1) begin
   if(!ack_clocked) drive=selected;
   else begin
    drive=0;
    if(selected && stage==0 && reading) begin
     tx=regs[pointer];
     if(pointer==1) tx=unlock ? 8'h43 : 8'hC3;
     if(pointer==4 && corrupt) tx=8'hBE;
     bitpos=7; mode=2; drive=~tx[7];
    end else begin mode=0; stage=stage+1; end
   end
  end else if(mode==2) drive=~tx[bitpos];
  else drive=0;
 end
endmodule

module init_tb;
 reg clk=0; always #5 clk=~clk;
 reg rstn=0, start=0;
 tri1 sda; wire scl, sda_release, pd, busy, done, error;
 assign sda=sda_release ? 1'bz : 1'b0;
 wire [63:0] ds; wire [79:0] rb;
 wire [6:0] faildev; wire [7:0] failreg; wire [1:0] code;
 wire [31:0] errs;
 wire [7:0] role_a,role_b;
 integer scenario=0, reset_edges=0, writes=0, last_slave_write=0;
 reg previous_pd=0;
 parameter MASTER=0, DUAL=1;
 adau1979_i2c_init #(.CLK_HZ(100000),.I2C_HZ(1000),.AUDIO_MASTER(MASTER),.DUAL_ENABLE(DUAL)) dut(
  .clk(clk),.rstn(rstn),.init_start(start),.adau_sda_i(sda),.adau_scl_oe_n(scl),
  .adau_sda_oe_n(sda_release),.adau_pd_rst(pd),.init_busy(busy),.init_done(done),
  .init_error(error),.device_status(ds),.device_readback(rb),
  .verify_fail_dev_addr(faildev),.verify_fail_reg_addr(failreg),.verify_fail_code(code),.ack_error_count(errs));
 adau_model #(.ADDRESS(7'h11)) a(scl,pd,sda,1'b0,1'b0,1'b0,role_a);
 adau_model #(.ADDRESS(7'h31)) b(scl,pd,sda,(scenario==1),(scenario==2),(scenario==3),role_b);
 always @(posedge clk) begin
  previous_pd<=pd;
  if(pd && !previous_pd) reset_edges=reset_edges+1;
  if(role_a[0] && role_b[0]) $fatal(1,"two audio clock masters");
  if(dut.i2c_start) begin
   writes=writes+1;
   if(writes==1 && DUAL && dut.I2C_ADDR!=(MASTER==0 ? 7'h31 : 7'h11)) $fatal(1,"slave not first");
  end
  if(dut.i2c_busy && dut.pll_busy) $fatal(1,"I2C engines overlap");
 end
 initial begin
  if($test$plusargs("scenario1")) scenario=1;
  if($test$plusargs("scenario2")) scenario=2;
  if($test$plusargs("scenario3")) scenario=3;
  #100 rstn=1;
  wait(!busy); #100;
  if(reset_edges!=1) $fatal(1,"shared reset repeated: %d",reset_edges);
  if(scenario==0) begin
   if(!done || error || !ds[14] || (DUAL && !ds[46])) $fatal(1,"success missing ds=%h rb=%h code=%d",ds,rb,code);
   if(rb[39:32]!=(MASTER==0 ? 1:0) || (DUAL && rb[79:72]!=(MASTER==1 ? 1:0))) $fatal(1,"role readback");
   if(writes!=(DUAL ? 30:15)) $fatal(1,"write count %d",writes);
  end else begin
   if(done || !error || faildev!=7'h31) $fatal(1,"failed device not blocked %h",faildev);
   if(scenario==1 && (code!=1 || failreg!=0 || errs!=1)) $fatal(1,"NACK details");
   if(scenario==2 && (code!=2 || failreg!=1 || errs!=0)) $fatal(1,"PLL details");
   if(scenario==3 && (code!=3 || failreg!=4 || !ds[36] || !ds[41])) $fatal(1,"readback mismatch details ds=%h",ds);
  end
  $display("PASS init scenario=%0d MASTER=%0d DUAL=%0d ds=%h rb=%h",scenario,MASTER,DUAL,ds,rb);
  $finish;
 end
 initial begin #100000000; $fatal(1,"init timeout"); end
endmodule

module init_master1_tb; init_tb #(.MASTER(1)) tb(); endmodule
module init_single_tb; init_tb #(.DUAL(0)) tb(); endmodule
