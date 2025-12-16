// Code your design here
module FIFO(

  
  input clk, rst, wr, rd,
  input [7:0] data_in,
  output reg [7:0] data_out,
  output empty, full
  
   
);
  
  
  reg [3:0] wptr, rptr;
  reg [4:0] count;
  reg [7:0] mem[15:0];
  
  always @(posedge clk)
    begin
      
      if(rst == 1'b1)begin
        
        wptr <= 0;
        rptr <= 0;
        count <= 0;
        
      end
      
      else if(wr == 1'b1 && full == 1'b0)begin
        
        mem[wptr] <= data_in;
        wptr <= wptr + 1;
        count <= count + 1;
        
      end
      
      else if(rd == 1'b1 && empty == 1'b0)begin
        
        data_out <= mem[rptr];
        rptr <= rptr + 1;
        count <= count - 1;
        
      end
      
      
    end
  
 
  assign empty = (count == 0) ? 1'b1 : 1'b0;
  assign full = (count == 16) ? 1'b1 : 1'b0;
  
  
endmodule


// Define an interface for the FIFO
interface fifo_if;
  
  logic clock, rd, wr;         // Clock, read, and write signals
  logic full, empty;           // Flags indicating FIFO status
  logic [7:0] data_in;         // Data input
  logic [7:0] data_out;        // Data output
  logic rst;                   // Reset signal
 
endinterface