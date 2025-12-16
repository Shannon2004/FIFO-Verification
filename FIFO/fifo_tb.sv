
// -----------------------------------------------------------------------
// 3. TESTBENCH CLASSES
// -----------------------------------------------------------------------

class transaction;
  rand bit oper;          
  bit rd, wr;             
  bit [7:0] data_in;      
  bit full, empty;        
  bit [7:0] data_out;     
  
  constraint oper_ctrl {  
    oper dist {1 :/ 50 , 0 :/ 50}; 
  }
endclass
 
///////////////////////////////////////////////////
 
class generator;
  transaction tr;           
  mailbox #(transaction) mbx;  
  int count = 0;            
  int i = 0;                
  
  event next;               
  event done;               
   
  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
    tr = new();
  endfunction; 
 
  task run(); 
    repeat (count) begin
      assert (tr.randomize) else $error("Randomization failed");
      i++;
      // Usually we put a copy but here we are verifying in-order, one after another
      mbx.put(tr);
      $display("[GEN] : Oper : %0d iteration : %0d", tr.oper, i);
      @(next);
    end -> done;
  endtask
endclass

////////////////////////////////////////////
 
class driver;
  virtual fifo_if fif;     
  mailbox #(transaction) mbx;  
  transaction datac;       
 
  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
  endfunction; 
 
  task reset();
    fif.rst <= 1'b1;
    fif.rd <= 1'b0;
    fif.wr <= 1'b0;
    fif.data_in <= 0;
    repeat (5) @(posedge fif.clock);
    fif.rst <= 1'b0;
    $display("[DRV] : DUT Reset Done");
    $display("------------------------------------------");
  endtask
   
  task write();
    @(posedge fif.clock);
    fif.rst <= 1'b0;
    fif.rd <= 1'b0;
    fif.wr <= 1'b1;
    fif.data_in <= $urandom_range(1, 10);
    @(posedge fif.clock);
    fif.wr <= 1'b0;
    $display("[DRV] : DATA WRITE  data : %0d", fif.data_in);  
    @(posedge fif.clock);
  endtask
  
  task read();  
    @(posedge fif.clock);
    fif.rst <= 1'b0;
    fif.rd <= 1'b1;
    fif.wr <= 1'b0;
    @(posedge fif.clock);
    fif.rd <= 1'b0;      
    $display("[DRV] : DATA READ");  
    @(posedge fif.clock);
  endtask
  
  task run();
    forever begin
      mbx.get(datac);  
      if (datac.oper == 1'b1)
        write();
      else
        read();
    end
  endtask
endclass
 
///////////////////////////////////////////////////////
 
class monitor;
  virtual fifo_if fif;     
  mailbox #(transaction) mbx;      // To Scoreboard
  mailbox #(transaction) mbx_sub;  // To Subscriber (New)
  transaction tr;          
  
  // Updated new() to accept 2 mailboxes
  function new(mailbox #(transaction) mbx, mailbox #(transaction) mbx_sub);
    this.mbx = mbx;     
    this.mbx_sub = mbx_sub;
  endfunction;
 
  task run();
    forever begin
      tr = new(); // FIX: Create new object every loop to avoid overwriting data
      
      repeat (2) @(posedge fif.clock);
      tr.wr = fif.wr;
      tr.rd = fif.rd;
      tr.data_in = fif.data_in;
      tr.full = fif.full;
      tr.empty = fif.empty; 
      @(posedge fif.clock);
      tr.data_out = fif.data_out;
    
      mbx.put(tr);
      mbx_sub.put(tr); // Send copy to Subscriber
      
      $display("[MON] : Wr:%0d rd:%0d din:%0d dout:%0d full:%0d empty:%0d", tr.wr, tr.rd, tr.data_in, tr.data_out, tr.full, tr.empty);
    end
  endtask
endclass
 
/////////////////////////////////////////////////////
 
class scoreboard;
  mailbox #(transaction) mbx;  
  transaction tr;          
  event next;
  bit [7:0] din[$];       
  bit [7:0] temp;         
  int err = 0;            
  
  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;     
  endfunction;
 
  task run();
    forever begin
      mbx.get(tr);
      $display("[SCO] : Wr:%0d rd:%0d din:%0d dout:%0d full:%0d empty:%0d", tr.wr, tr.rd, tr.data_in, tr.data_out, tr.full, tr.empty);
      
      if (tr.wr == 1'b1) begin
        if (tr.full == 1'b0) begin
          din.push_front(tr.data_in);
          $display("[SCO] : DATA STORED IN QUEUE :%0d", tr.data_in);
        end
        else begin
          $display("[SCO] : FIFO is full");
        end
        $display("--------------------------------------"); 
      end
    
      if (tr.rd == 1'b1) begin
        if (tr.empty == 1'b0) begin  
          temp = din.pop_back();
          
          if (tr.data_out == temp)
            $display("[SCO] : DATA MATCH");
          else begin
            $error("[SCO] : DATA MISMATCH");
            err++;
          end
        end
        else begin
          $display("[SCO] : FIFO IS EMPTY");
        end
        
        $display("--------------------------------------"); 
      end
      
      -> next;
    end
  endtask
endclass

///////////////////////////////////////////////////////

// NEW CLASS: Subscriber for Coverage
class subscriber;
  mailbox #(transaction) mbx;
  transaction tr;
  
  // Covergroup definition
  covergroup fifo_cg;
    // Cover Write Enable
    cp_wr: coverpoint tr.wr {
      bins active = {1};
      bins idle   = {0};
    }
    // Cover Read Enable
    cp_rd: coverpoint tr.rd {
      bins active = {1};
      bins idle   = {0};
    }
    // Cover Full Flag
    cp_full: coverpoint tr.full {
      bins is_full     = {1};
      bins not_full    = {0};
    }
    // Cover Empty Flag
    cp_empty: coverpoint tr.empty {
      bins is_empty    = {1};
      bins not_empty   = {0};
    }
    // Cross: Write vs Full (Checks overflow protection)
    cross_wr_full: cross cp_wr, cp_full;
    
    // Cross: Read vs Empty (Checks underflow protection)
    cross_rd_empty: cross cp_rd, cp_empty;
  endgroup
  
  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
    fifo_cg = new(); // Instantiate the covergroup
  endfunction
  
  task run();
    forever begin
      mbx.get(tr);
      fifo_cg.sample(); // Sample coverage on every transaction
      // Optional: Display current coverage percentage
      // $display("[SUB] : Coverage = %.2f%%", fifo_cg.get_coverage());
    end
  endtask
endclass
 
///////////////////////////////////////////////////////
 
class environment;
  generator gen;
  driver drv;
  monitor mon;
  scoreboard sco;
  subscriber sub;                // NEW
  
  mailbox #(transaction) gdmbx;  
  mailbox #(transaction) msmbx;  
  mailbox #(transaction) csmbx;  // NEW Coverage Mailbox
  
  event nextgs;
  virtual fifo_if fif;
  
  function new(virtual fifo_if fif);
    gdmbx = new();
    msmbx = new();
    csmbx = new();               // Init new mailbox
    
    gen = new(gdmbx);
    drv = new(gdmbx);
    
    mon = new(msmbx, csmbx);     // Pass both mailboxes
    sco = new(msmbx);
    sub = new(csmbx);            // Init subscriber
    
    this.fif = fif;
    drv.fif = this.fif;
    mon.fif = this.fif;
    gen.next = nextgs;
    sco.next = nextgs;
  endfunction
  
  task pre_test();
    drv.reset();
  endtask
  
  task test();
    fork
      gen.run();
      drv.run();
      mon.run();
      sco.run();
      sub.run(); // Run subscriber
    join_any
  endtask
  
  task post_test();
    wait(gen.done.triggered);  
    $display("---------------------------------------------");
    $display("Error Count :%0d", sco.err);
    $display("Final Functional Coverage : %.2f%%", sub.fifo_cg.get_coverage()); // Report coverage
    $display("---------------------------------------------");
    $finish();
  endtask
  
  task run();
    pre_test();
    test();
    post_test();
  endtask
endclass
 
///////////////////////////////////////////////////////
// 4. TESTBENCH TOP
///////////////////////////////////////////////////////
 
module tb;
    
  fifo_if fif();
  FIFO dut (fif.clock, fif.rst, fif.wr, fif.rd, fif.data_in, fif.data_out, fif.empty, fif.full);
    
  initial begin
    fif.clock <= 0;
  end
    
  always #10 fif.clock <= ~fif.clock;
    
  environment env;
    
  initial begin
    env = new(fif);
    // INCREASED COUNT to 40 to ensure we fill FIFO (Depth 16) and hit full/empty flags
    env.gen.count = 250; 
    env.run();
  end
    
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars;
  end
   
endmodule