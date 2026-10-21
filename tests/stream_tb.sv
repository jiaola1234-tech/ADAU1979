`timescale 1ns/1ps
module stream_tb;
 reg clk=0; always #5 clk=~clk;
 reg rstn=0, enable=0, bclk=0, lr=1; reg [3:0] sdata=0;
 wire [255:0] data; wire [31:0] keep,frames,syncerr,ovf,level,index;
 wire valid,last,full,packet;
 reg ready=0; integer cycles=0,received=0,packets=0,produced=0,f,j,lane;
 reg stalled=0, held_last; reg [255:0] held;
 parameter DUAL=1, SWAP=0, INVERT_LR=0;
 function [23:0] sample;
  input integer frame_no,line_no,right_slot;
  begin
   case(line_no*2+right_slot)
    0: sample=24'h800000+frame_no;
    1: sample=24'h7fffff-frame_no;
    2: sample=24'hffffff-frame_no;
    3: sample=24'h000001+frame_no;
    default: sample=24'h102030+line_no*4096+right_slot*256+frame_no;
   endcase
  end
 endfunction
 function [31:0] expected;
  input integer frame_no,word_no;
  integer line_no; reg [23:0] v;
  begin
   line_no=(word_no/2+2)%4;
   if(SWAP) line_no=word_no/2;
   v=sample(frame_no,line_no,word_no%2);
   expected=(!DUAL && word_no>=4) ? 0 : {{8{v[23]}},v};
  end
 endfunction
 adau1979_capture_core #(.FIFO_ADDR_WIDTH(10),.DUAL_ENABLE(DUAL),
   .LR_POLARITY(INVERT_LR ? 0:1),
   .A_SDATA0(SWAP ? 0:2),.A_SDATA1(SWAP ? 1:3),.B_SDATA0(SWAP ? 2:0),.B_SDATA1(SWAP ? 3:1)) dut(
  .clk(clk),.rstn(rstn),.capture_enable(enable),.init_done(1'b1),.sample_len(32'd1024),
  .bclk(bclk),.lrclk(lr),.sdata(sdata),.m_axis_tdata(data),.m_axis_tkeep(keep),
  .m_axis_tlast(last),.m_axis_tready(ready),.m_axis_tvalid(valid),.i2s_frame_count(frames),
  .i2s_sync_error_count(syncerr),.fifo_overflow_count(ovf),.fifo_level(level),.fifo_full(full),
  .packet_done(packet),.packet_count(index));
 task slot;
  input integer frame_no,right_slot;
  reg [23:0] v;
  integer bit_no,k;
  begin
   bclk=0; lr=right_slot ^ INVERT_LR; sdata=0; #80;
   // One full I2S delay, then 24 significant bits, 7 remaining slot clocks.
   for(bit_no=0;bit_no<32;bit_no=bit_no+1) begin
    bclk=0;
    for(k=0;k<4;k=k+1) begin
     v=sample(frame_no,k,right_slot);
     sdata[k]=(bit_no>=1 && bit_no<=24) ? v[24-bit_no] : 0;
    end
    #80; bclk=1; #80;
   end
   bclk=0;
  end
 endtask
 always @(negedge clk) begin
  cycles=cycles+1;
  // Initial buffering plus periodic DMA rearm gaps, including TLAST stalls.
  ready=(cycles>6000 && cycles%5000>250 && cycles%17!=0);
 end
 always @(posedge clk) if(rstn) begin
  if(stalled && (!valid || data!==held || last!==held_last)) $fatal(1,"backpressure unstable");
  stalled=valid && !ready; held=data; held_last=last;
  if(valid && ready) begin
   for(lane=0;lane<8;lane=lane+1)
    if(data[lane*32+:32]!==expected(received,lane))
     $fatal(1,"frame %0d word %0d got=%h expected=%h",received,lane,data[lane*32+:32],expected(received,lane));
   if(keep!==32'hffffffff || last!==(received%1024==1023)) $fatal(1,"TLAST/TKEEP frame=%d",received);
   if(last) packets=packets+1;
   received=received+1;
  end
 end
 initial begin
  lr=1 ^ INVERT_LR;
  #100 rstn=1; enable=1; #200;
  // Start on a complete LRCLK pair; the first captured frame must be zero.
  for(f=0;f<3072;f=f+1) begin slot(f,0); slot(f,1); end
  wait(received==3072); #100;
  if(ovf || syncerr || frames!=3072 || packets!=3) $fatal(1,"counts frames=%d packets=%d sync=%d ovf=%d",frames,packets,syncerr,ovf);
  $display("PASS stream DUAL=%0d SWAP=%0d INVERT_LR=%0d 3072 distinct frames, 3 TLAST, stable backpressure",DUAL,SWAP,INVERT_LR);
  $finish;
 end
 initial begin #100000000; $fatal(1,"stream timeout received=%d frames=%d",received,frames); end
endmodule

module stream_swap_tb; stream_tb #(.SWAP(1)) tb(); endmodule
module stream_single_tb; stream_tb #(.DUAL(0)) tb(); endmodule

// 0x04=0xBF sets LR_POL=1: high carries CH1/3, low carries CH2/4.
// Keep per-frame data distinct to detect incorrect pairing across frames.
module stream_inverted_lr_tb; stream_tb #(.SWAP(1),.INVERT_LR(1)) tb(); endmodule
