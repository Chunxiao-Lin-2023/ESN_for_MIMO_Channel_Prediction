
`timescale 1 ns / 1 ps

	module esn_axi_slv_v1_1_S00_AXI #
	(
		// Users to add parameters here
        parameter NUM_NEUR      = 8,
        parameter NUM_IN        = 64,
        parameter NUM_OUT       = 64,     // output nodes, =D_MATRIX_X
        parameter D_MATRIX      = NUM_NEUR + NUM_IN,
        
        parameter WIDTH_STATE   = 20,
        parameter WIDTH_WEIGHT  = 16,
        parameter WIDTH_INPUT   = 20, 
        parameter WIDTH_OUTPUT  = 32,
		// User parameters ends
		// Do not modify the parameters beyond this line

		// Width of S_AXI data bus
		parameter integer C_S_AXI_DATA_WIDTH	= 32,
		// Width of S_AXI address bus
		parameter integer C_S_AXI_ADDR_WIDTH	= 15
	)
	(
		// Users to add ports here
        //output wire done,
		// User ports ends
		// Do not modify the ports beyond this line

		// Global Clock Signal
		input wire  S_AXI_ACLK,
		// Global Reset Signal. This Signal is Active LOW
		input wire  S_AXI_ARESETN,
		// Write address (issued by master, acceped by Slave)
		input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_AWADDR,
		// Write channel Protection type. This signal indicates the
    		// privilege and security level of the transaction, and whether
    		// the transaction is a data access or an instruction access.
		input wire [2 : 0] S_AXI_AWPROT,
		// Write address valid. This signal indicates that the master signaling
    		// valid write address and control information.
		input wire  S_AXI_AWVALID,
		// Write address ready. This signal indicates that the slave is ready
    		// to accept an address and associated control signals.
		output wire  S_AXI_AWREADY,
		// Write data (issued by master, acceped by Slave) 
		input wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_WDATA,
		// Write strobes. This signal indicates which byte lanes hold
    		// valid data. There is one write strobe bit for each eight
    		// bits of the write data bus.    
		input wire [(C_S_AXI_DATA_WIDTH/8)-1 : 0] S_AXI_WSTRB,
		// Write valid. This signal indicates that valid write
    		// data and strobes are available.
		input wire  S_AXI_WVALID,
		// Write ready. This signal indicates that the slave
    		// can accept the write data.
		output wire  S_AXI_WREADY,
		// Write response. This signal indicates the status
    		// of the write transaction.
		output wire [1 : 0] S_AXI_BRESP,
		// Write response valid. This signal indicates that the channel
    		// is signaling a valid write response.
		output wire  S_AXI_BVALID,
		// Response ready. This signal indicates that the master
    		// can accept a write response.
		input wire  S_AXI_BREADY,
		// Read address (issued by master, acceped by Slave)
		input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_ARADDR,
		// Protection type. This signal indicates the privilege
    		// and security level of the transaction, and whether the
    		// transaction is a data access or an instruction access.
		input wire [2 : 0] S_AXI_ARPROT,
		// Read address valid. This signal indicates that the channel
    		// is signaling valid read address and control information.
		input wire  S_AXI_ARVALID,
		// Read address ready. This signal indicates that the slave is
    		// ready to accept an address and associated control signals.
		output wire  S_AXI_ARREADY,
		// Read data (issued by slave)
		output wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_RDATA,
		// Read response. This signal indicates the status of the
    		// read transfer.
		output wire [1 : 0] S_AXI_RRESP,
		// Read valid. This signal indicates that the channel is
    		// signaling the required read data.
		output wire  S_AXI_RVALID,
		// Read ready. This signal indicates that the master can
    		// accept the read data and response information.
		input wire  S_AXI_RREADY
	);

	// AXI4LITE signals
	reg [C_S_AXI_ADDR_WIDTH-1 : 0] 	axi_awaddr;
	reg  	axi_awready;
	reg  	axi_wready;
	reg [1 : 0] 	axi_bresp;
	reg  	axi_bvalid;
	reg [C_S_AXI_ADDR_WIDTH-1 : 0] 	axi_araddr;
	reg  	axi_arready;
	reg [C_S_AXI_DATA_WIDTH-1 : 0] 	axi_rdata;
	reg [1 : 0] 	axi_rresp;
	reg  	axi_rvalid;

    // ---------- Local sizes (for range checks) ----------
    localparam W_X_SIZE   = NUM_NEUR * NUM_NEUR;            //256
    localparam W_IN_SIZE  = NUM_NEUR * NUM_IN;              //64
    localparam W_OUT_SIZE = NUM_OUT  * D_MATRIX;            //40
    
	// Example-specific design signals
	// local parameter for addressing 32 bit / 64 bit C_S_AXI_DATA_WIDTH
	// ADDR_LSB is used for addressing 32/64 bit registers/memories
	// ADDR_LSB = 2 for 32 bits (n downto 2)
	// ADDR_LSB = 3 for 64 bits (n downto 3)
	localparam integer ADDR_LSB = (C_S_AXI_DATA_WIDTH/32) + 1;
    // TODO: NUM_SLV_REG_I = # of w_s + w_in + w_out + input data + start = 365	
	localparam integer NUM_SLV_REG = W_X_SIZE + W_IN_SIZE + W_OUT_SIZE + NUM_IN + 1; //8;           
	// TODO: NUM_SLV_REG_O = # of state + output + done = 19
	localparam integer NUM_SLV_REG_OUT = NUM_NEUR + NUM_OUT + 1; //8;
	
	localparam integer OPT_MEM_ADDR_BITS = $clog2(NUM_SLV_REG) - 1;
    localparam integer OPT_MEM_ADDR_BITS_R = $clog2(NUM_SLV_REG + NUM_SLV_REG_OUT) - 1;
    
    // TODO: PS-PL reg storage
	reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg       [0:NUM_SLV_REG-1]; 
    //TODO: PL-PS reg storage
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg_out    [0:NUM_SLV_REG_OUT-1]; 
    
	wire	 slv_reg_rden;
	wire	 slv_reg_wren;
	reg [C_S_AXI_DATA_WIDTH-1:0]	 reg_data_out;
	integer	 byte_index;
	reg	 aw_en;

	// I/O Connections assignments

	assign S_AXI_AWREADY	= axi_awready;
	assign S_AXI_WREADY	= axi_wready;
	assign S_AXI_BRESP	= axi_bresp;
	assign S_AXI_BVALID	= axi_bvalid;
	assign S_AXI_ARREADY	= axi_arready;
	assign S_AXI_RDATA	= axi_rdata;
	assign S_AXI_RRESP	= axi_rresp;
	assign S_AXI_RVALID	= axi_rvalid;
	// Implement axi_awready generation
	// axi_awready is asserted for one S_AXI_ACLK clock cycle when both
	// S_AXI_AWVALID and S_AXI_WVALID are asserted. axi_awready is
	// de-asserted when reset is low.

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_awready <= 1'b0;
	      aw_en <= 1'b1;
	    end 
	  else
	    begin    
	      if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en)
	        begin
	          // slave is ready to accept write address when 
	          // there is a valid write address and write data
	          // on the write address and data bus. This design 
	          // expects no outstanding transactions. 
	          axi_awready <= 1'b1;
	          aw_en <= 1'b0;
	        end
	        else if (S_AXI_BREADY && axi_bvalid)
	            begin
	              aw_en <= 1'b1;
	              axi_awready <= 1'b0;
	            end
	      else           
	        begin
	          axi_awready <= 1'b0;
	        end
	    end 
	end       

	// Implement axi_awaddr latching
	// This process is used to latch the address when both 
	// S_AXI_AWVALID and S_AXI_WVALID are valid. 

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_awaddr <= 0;
	    end 
	  else
	    begin    
	      if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en)
	        begin
	          // Write Address latching 
	          axi_awaddr <= S_AXI_AWADDR;
	        end
	    end 
	end       

	// Implement axi_wready generation
	// axi_wready is asserted for one S_AXI_ACLK clock cycle when both
	// S_AXI_AWVALID and S_AXI_WVALID are asserted. axi_wready is 
	// de-asserted when reset is low. 

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_wready <= 1'b0;
	    end 
	  else
	    begin    
	      if (~axi_wready && S_AXI_WVALID && S_AXI_AWVALID && aw_en )
	        begin
	          // slave is ready to accept write data when 
	          // there is a valid write address and write data
	          // on the write address and data bus. This design 
	          // expects no outstanding transactions. 
	          axi_wready <= 1'b1;
	        end
	      else
	        begin
	          axi_wready <= 1'b0;
	        end
	    end 
	end       

	// Implement memory mapped register select and write logic generation
	// The write data is accepted and written to memory mapped registers when
	// axi_awready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted. Write strobes are used to
	// select byte enables of slave registers while writing.
	// These registers are cleared when reset (active low) is applied.
	// Slave register write enable is asserted when valid address and data are available
	// and the slave is ready to accept the write address and write data.
	assign slv_reg_wren = axi_wready && S_AXI_WVALID && axi_awready && S_AXI_AWVALID;
    wire [OPT_MEM_ADDR_BITS:0] widx = axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB];

    integer i;
	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
            for (i = 0; i < NUM_SLV_REG; i = i + 1)
              slv_reg[i] <= {C_S_AXI_DATA_WIDTH{1'b0}};
	    end 
	  else begin
	    if (slv_reg_wren)
	      begin
	           for (byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1)
                    if (S_AXI_WSTRB[byte_index]) begin
                      slv_reg[widx][(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    end
	      end
	  end
	end    

	// Implement write response logic generation
	// The write response and response valid signals are asserted by the slave 
	// when axi_wready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted.  
	// This marks the acceptance of address and indicates the status of 
	// write transaction.

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_bvalid  <= 0;
	      axi_bresp   <= 2'b0;
	    end 
	  else
	    begin    
	      if (axi_awready && S_AXI_AWVALID && ~axi_bvalid && axi_wready && S_AXI_WVALID)
	        begin
	          // indicates a valid write response is available
	          axi_bvalid <= 1'b1;
	          axi_bresp  <= 2'b0; // 'OKAY' response 
	        end                   // work error responses in future
	      else
	        begin
	          if (S_AXI_BREADY && axi_bvalid) 
	            //check if bready is asserted while bvalid is high) 
	            //(there is a possibility that bready is always asserted high)   
	            begin
	              axi_bvalid <= 1'b0; 
	            end  
	        end
	    end
	end   

	// Implement axi_arready generation
	// axi_arready is asserted for one S_AXI_ACLK clock cycle when
	// S_AXI_ARVALID is asserted. axi_awready is 
	// de-asserted when reset (active low) is asserted. 
	// The read address is also latched when S_AXI_ARVALID is 
	// asserted. axi_araddr is reset to zero on reset assertion.

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_arready <= 1'b0;
	      axi_araddr  <= 32'b0;
	    end 
	  else
	    begin    
	      if (~axi_arready && S_AXI_ARVALID)
	        begin
	          // indicates that the slave has acceped the valid read address
	          axi_arready <= 1'b1;
	          // Read address latching
	          axi_araddr  <= S_AXI_ARADDR;
	        end
	      else
	        begin
	          axi_arready <= 1'b0;
	        end
	    end 
	end       

	// Implement axi_arvalid generation
	// axi_rvalid is asserted for one S_AXI_ACLK clock cycle when both 
	// S_AXI_ARVALID and axi_arready are asserted. The slave registers 
	// data are available on the axi_rdata bus at this instance. The 
	// assertion of axi_rvalid marks the validity of read data on the 
	// bus and axi_rresp indicates the status of read transaction.axi_rvalid 
	// is deasserted on reset (active low). axi_rresp and axi_rdata are 
	// cleared to zero on reset (active low).  
	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_rvalid <= 0;
	      axi_rresp  <= 0;
	    end 
	  else
	    begin    
	      if (axi_arready && S_AXI_ARVALID && ~axi_rvalid)
	        begin
	          // Valid read data is available at the read data bus
	          axi_rvalid <= 1'b1;
	          axi_rresp  <= 2'b0; // 'OKAY' response
	        end   
	      else if (axi_rvalid && S_AXI_RREADY)
	        begin
	          // Read data is accepted by the master
	          axi_rvalid <= 1'b0;
	        end                
	    end
	end    

	// Implement memory mapped register select and read logic generation
	// Slave register read enable is asserted when valid address is available
	// and the slave is ready to accept the read address.
	assign slv_reg_rden = axi_arready & S_AXI_ARVALID & ~axi_rvalid;
	wire [OPT_MEM_ADDR_BITS_R:0] ridx = axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS_R:ADDR_LSB];
	
	always @(*)
	begin
	      // Low addresses: read the PS->PL regs
          if (ridx < NUM_SLV_REG) begin
            reg_data_out = slv_reg[ridx];
          end
          // Next addresses: read the PL->PS regs
          else if (ridx < (NUM_SLV_REG + NUM_SLV_REG_OUT)) begin
            reg_data_out = slv_reg_out[ridx - NUM_SLV_REG];
          end
          // Out of range (shouldn't happen if address map is sized correctly)
          else begin
            reg_data_out = {C_S_AXI_DATA_WIDTH{1'b0}};
          end  
	end

	// Output register or memory read data
	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_rdata  <= 0;
	    end 
	  else
	    begin    
	      // When there is a valid read address (S_AXI_ARVALID) with 
	      // acceptance of read address by the slave (axi_arready), 
	      // output the read dada 
	      if (slv_reg_rden)
	        begin
	          axi_rdata <= reg_data_out;     // register read data
	        end   
	    end
	end    

 
//==========================================================================
//=== ESN data processing start here, 4-16-2=====================================
//=== PS to PL
//=== Start signal                          slv_reg0 [0]
//=== Weights state         16*16 = 256,    slv_reg1-256
//=== Weights input data    16*4 = 64,      slv_reg257-320
//=== Weights output data   20*2 = 40,      slv_reg321-360
//=== Input data            4               slv_reg361-364
//=== PL to PS
//=== Done signal                           slv_reg_out[0]
//=== New reservior state   16              slv_reg_out[1-16]
//=== Output                2               slv_reg_out17-18
//==============================================================
//=== ESN data processing start here, 64-8-64=====================================
//=== PS to PL
//=== Start signal                          slv_reg0 [0]
//=== Weights state         8*8 = 64,       slv_reg1-64
//=== Weights input data    8*64 = 512,     slv_reg65-576
//=== Weights output data   64*72 = 4608,   slv_reg577-5184
//=== Input data            64              slv_reg5185-5248  // 
//=== PL to PS
//=== Done signal                           slv_reg_out0[0]
//=== New reservior state   8               slv_reg_out1-8
//=== Output                64              slv_reg_out9-72   // 2^13 = 8192 registers are needed for AXI
//==============================================================
    reg  [WIDTH_STATE-1:0] rstate_reg [0:NUM_NEUR-1];       // reservoir states: #N of reservoir
    wire [WIDTH_STATE-1:0] rstate_new [0:NUM_NEUR-1];      // Updated reservoir neuron states
    wire [24:0]            rstate_ex [0:D_MATRIX-1];       // state vector concatination = 4 inputs + 16 reserviors , 25-bit for DSP input
    
    wire [WIDTH_WEIGHT-1:0] w_ex [0:NUM_NEUR-1][0:D_MATRIX-1];      // extended weights 16b x 16 x (16 + 4), <16,15>
    wire [(NUM_NEUR/2-1):0] echoready;               // 1 cycle pulse: rstate_new is ready
    
    wire  [WIDTH_WEIGHT-1:0] w_x       [0:NUM_NEUR-1][0:NUM_NEUR-1];
    wire  [WIDTH_WEIGHT-1:0] w_in      [0:NUM_NEUR-1][0:NUM_IN-1];
    wire  [WIDTH_WEIGHT-1:0] w_out     [0:NUM_OUT-1][0:D_MATRIX-1];
    
    // ---------- local bases (contiguous map) ----------
    localparam integer REG_CTRL_BASE = 0;
    wire start_bit = slv_reg[REG_CTRL_BASE][0];
    
    localparam W_X_BASE     = REG_CTRL_BASE + 1;  // slv_reg0 is for start signal 
    localparam W_IN_BASE    = W_X_BASE + W_X_SIZE;
    localparam W_OUT_BASE   = W_IN_BASE + W_IN_SIZE;
    localparam DATAIN_BASE   = W_OUT_BASE + W_OUT_SIZE;     

    // ------------------------------------------------------------------
    // Reshape PS->PL register bank into matrices/vectors
    // ------------------------------------------------------------------
    genvar j, k;
    
    // W_X: NUM_NEUR x NUM_NEUR  (each weight assumed to occupy low WIDTH_WEIGHT bits)
    generate
      for (j = 0; j < NUM_NEUR; j = j + 1) begin : G_WX_ROW
        for (k = 0; k < NUM_NEUR; k = k + 1) begin : G_WX_COL
          // index = base + row*NUM_NEUR + col
          localparam integer WX_IDX = W_X_BASE + (j*NUM_NEUR) + k;
          assign w_x[j][k] = slv_reg[WX_IDX][WIDTH_WEIGHT-1:0];
        end
      end
    endgenerate
    
    // W_IN: NUM_NEUR x NUM_IN
    generate
      for (j = 0; j < NUM_NEUR; j = j + 1) begin : G_WIN_ROW
        for (k = 0; k < NUM_IN; k = k + 1) begin : G_WIN_COL
          localparam integer WIN_IDX = W_IN_BASE + (j*NUM_IN) + k;
          assign w_in[j][k] = slv_reg[WIN_IDX][WIDTH_WEIGHT-1:0];
        end
      end
    endgenerate
    
    // W_OUT: NUM_OUT x D_MATRIX
    generate
      for (j = 0; j < NUM_OUT; j = j + 1) begin : G_WOUT_ROW
        for (k = 0; k < D_MATRIX; k = k + 1) begin : G_WOUT_COL
          localparam integer WOUT_IDX = W_OUT_BASE + (j*D_MATRIX) + k;
          assign w_out[j][k] = slv_reg[WOUT_IDX][WIDTH_WEIGHT-1:0];
        end
      end
    endgenerate
    
    // data_in[NUM_IN]
    wire [WIDTH_INPUT-1:0] data_in [0:NUM_IN-1];
    generate
      for (j = 0; j < NUM_IN; j = j + 1) begin : G_DATAIN
        localparam integer DIN_IDX = DATAIN_BASE + j;
        assign data_in[j] = slv_reg[DIN_IDX][WIDTH_INPUT-1:0];
      end
    endgenerate
    
    
    
   // ---------------------------------- Need to redesign ----------------------------- 
   // FIXME control signal to reset states
   // ---------------------------------------------------------------------------------
   reg update;
    integer a;
    always @(posedge S_AXI_ACLK) begin
      if (S_AXI_ARESETN == 1'b0) begin
        for (a = 0; a < NUM_NEUR; a = a + 1) rstate_reg[a] <= {WIDTH_STATE{1'b0}};  
        update <= 1'b0;
        end
      else if (&echoready) begin
        for (a = 0; a < NUM_NEUR; a = a + 1) rstate_reg[a] <= rstate_new[a];  
        update <= 1'b1;
        end
      else begin
        for (a = 0; a < NUM_NEUR; a = a + 1) rstate_reg[a] <= rstate_reg[a];  
        update <= 1'b0;
        end
      // else hold value
    end
    // -------------------------------------------------------- end ----------------------
    
    // ---------- Extended state vector: first states, then inputs<<4 --------------------
    genvar x;
    generate
      for (x = 0; x < D_MATRIX; x = x + 1) begin : G_RSTATE_EX
        if (x < NUM_NEUR) begin
          assign rstate_ex[x] = {{5{rstate_reg[x][WIDTH_STATE-1]}}, rstate_reg[x]};      end      // extended to 25-bit
        else begin
          //assign rstate_ex[x] = {rstate_reg[x][WIDTH_INPUT-1], data_in[x - NUM_NEUR], 4'b0 };           // input << 4 and then extended to 25-bit
            assign rstate_ex[x] = {data_in[x-NUM_NEUR][WIDTH_INPUT-1], data_in[x - NUM_NEUR], 4'b0 }; 
        end
      end
    endgenerate
    
    // ---------- Extended weight matrix: [w_x | w_in] ----------
    genvar r, c;
    generate
      for (r = 0; r < NUM_NEUR; r = r + 1) begin : G_WEX_ROW
        for (c = 0; c < D_MATRIX; c = c + 1) begin : G_WEX_COL
            if (c < NUM_NEUR) begin
                assign w_ex[r][c] = w_x[r][c];
            end else begin
                assign w_ex[r][c] = w_in[r][c-NUM_NEUR];
            end
        end
      end
    endgenerate
    
    
    // -------------------------------------------------------------------------------------
    // ESN Reservoir neurons
    // -------------------------------------------------------------------------------------
    logic reservoir_start;
    
    genvar g;
    for (g = 0; g < (NUM_NEUR/2); g = g + 1) begin : rn        //TODO parametize g
    New_dual_RN #(
    .WIDTH_STATE_EX(25),  // the DSP portA bitwidth
    .WIDTH_WEIGTH(WIDTH_WEIGHT), 
    .D_MATRIX(D_MATRIX)
        ) dut (
            .clk(S_AXI_ACLK),
            .rst(!S_AXI_ARESETN),
            .run(reservoir_start),
            .state_ex(rstate_ex),
            .w_ex_a(w_ex[g * 2]),
            .w_ex_b(w_ex[g * 2 + 1]),
            .echostate_a(rstate_new[g * 2]),
            .echostate_b(rstate_new[g * 2 + 1]),
            .echoready(echoready[g])
        );
    end
    
    // -------------------------------------------------------------------------------------
    // ESN Output layer based on systolic array
    // -------------------------------------------------------------------------------------
    /*logic [24:0] z_reg [0:D_MATRIX-1];  // save the rstate_ex with old state for output neuron
    generate
      for (j = 0; j < D_MATRIX; j++) begin
        always_ff@(posedge S_AXI_ACLK) begin
          if (!S_AXI_ARESETN)
             z_reg[j] <= 'd0;
          else if (update)
             z_reg[j] <= rstate_ex[j];
          else
             z_reg[j] <= z_reg[j];
          end
        end
    endgenerate
    */
    logic output_ready;
    logic [WIDTH_OUTPUT-1:0] y_out [0:NUM_OUT-1];
    scaled_reg_SA_MAC #( 
        .N_ROW(8),
        .D_MATRIX(D_MATRIX),
        .N_OUT(NUM_OUT),
        .WIDTH_WEIGHT(WIDTH_WEIGHT),
        .WIDTH_STATE_EX(25),
        .WIDTH_OUTPUT(WIDTH_OUTPUT)
    ) dut (
        .clk(S_AXI_ACLK),
        .rst(!S_AXI_ARESETN),
        .start(update),    //FIXME
        .rstate_ex(rstate_ex),
        .w_out(w_out),
        .out_vec(y_out),
        .out_valid(output_ready)
    );
    
    
    //--------------------------------------------------------------
    // control logic for reservoir and readout
    //--------------------------------------------------------------
    
    // Detect a 0-1 sequence of start_bit and set the reservoir_start for 1 clk
    logic start_d1;
    always_ff @(posedge S_AXI_ACLK) begin
      if (!S_AXI_ARESETN) begin
        start_d1        <= 1'b0;
        reservoir_start <= 1'b0;
      end else begin
        start_d1        <= start_bit;
        reservoir_start <= start_bit & ~start_d1; // rising edge
      end
    end
    
    // Done signal at slv_reg_out0, reset it at the next start signal
    always_ff @(posedge S_AXI_ACLK) begin
      if (!S_AXI_ARESETN)              slv_reg_out[0] <= '0;
      else if (reservoir_start)        slv_reg_out[0] <= '0;      
      else if (output_ready)     slv_reg_out[0][0] <= 1'b1;
      else                       slv_reg_out[0] <= slv_reg_out[0];
    end
    
    // Send the state_ex_new and y_out back to PS through slv_reg_out
    integer b;
    always_ff @(posedge S_AXI_ACLK) begin
      if (!S_AXI_ARESETN) begin
        for (b = 1; b < NUM_SLV_REG_OUT; b++) slv_reg_out[b] <= '0;
      end else if (output_ready) begin
        // write the new state
        for (b = 0; b < NUM_NEUR; b++) begin
          slv_reg_out[1 + b] <= rstate_new[b];
        end
        // write the y_out
        for (b = 0; b < NUM_OUT; b++) begin
          slv_reg_out[1 + NUM_NEUR + b] <= y_out[b];
        end
      end
end
    
    
endmodule
