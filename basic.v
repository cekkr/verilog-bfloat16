module bfloat16_processor #(
  parameter DATA_WIDTH = 16, // bfloat16 width
  parameter LOCAL_RAM_ADDR_WIDTH = 10, // 1024 words by default
  parameter SDRAM_ADDR_WIDTH = 24,    // Example SDRAM address width
  parameter NUM_CORES = 4,            // Number of arithmetic cores
  parameter FIFO_DEPTH = 16          // Depth of operation FIFO
) (
  input  wire clk,
  input  wire rst,

  // --- Host Interface ---
  input  wire host_req,         // Request from host
  input  wire host_wr,          // Host write enable
  input  wire [2:0] host_opcode, // 0: noop, 1: add, 2: sub, 3: mul, 4: div, 5: read_ram, 6: write_ram, 7: read_sdram, 8: write_sdram
  input  wire [DATA_WIDTH-1:0] host_data_in_a, // Operand A (bfloat16)
  input  wire [DATA_WIDTH-1:0] host_data_in_b, // Operand B (bfloat16)
  input  wire [LOCAL_RAM_ADDR_WIDTH-1:0] host_local_ram_addr, // Local RAM address
  input  wire [SDRAM_ADDR_WIDTH-1:0] host_sdram_addr, // SDRAM address
  input  wire [DATA_WIDTH-1:0] host_sdram_data_in, // Data to write to SDRAM
  output wire host_ack,         // Acknowledge to host
  output wire host_busy,        // Processor busy
  output wire [DATA_WIDTH-1:0] host_data_out,  // Result (bfloat16) or data read from memory
  output wire host_op_status,    // 0: success, 1: error (e.g., divide by zero)

  // --- Local RAM Interface ---
  output wire [LOCAL_RAM_ADDR_WIDTH-1:0] local_ram_addr,
  output wire local_ram_we,
  output wire [DATA_WIDTH-1:0] local_ram_data_out,
  input  wire [DATA_WIDTH-1:0] local_ram_data_in,

  // --- SDRAM Interface --- (Simplified for brevity, actual SDRAM controller would be more complex)
  output wire sdram_req,
  output wire sdram_wr,
  output wire [SDRAM_ADDR_WIDTH-1:0] sdram_addr,
  output wire [DATA_WIDTH-1:0] sdram_data_out,
  input  wire sdram_ack,
  input  wire [DATA_WIDTH-1:0] sdram_data_in
);

  // --- Internal Signals and Registers ---
  localparam STATE_IDLE = 0;
  localparam STATE_HOST_REQ = 1;
  localparam STATE_LOCAL_RAM_READ = 2;
  localparam STATE_LOCAL_RAM_WRITE = 3;
  localparam STATE_SDRAM_READ = 4;
  localparam STATE_SDRAM_WRITE = 5;
  localparam STATE_EXECUTE = 6;
  localparam STATE_WAIT_CORE = 7;
  localparam STATE_WRITE_BACK = 8;


  reg [3:0] state;
  reg host_ack_reg;
  reg host_busy_reg;
  reg [DATA_WIDTH-1:0] host_data_out_reg;
  reg host_op_status_reg;

  // --- Operation Queue (FIFO) ---
  reg [FIFO_DEPTH-1:0] fifo_valid;
  reg [FIFO_DEPTH-1:0][2:0] fifo_opcode;
  reg [FIFO_DEPTH-1:0][DATA_WIDTH-1:0] fifo_op_a;
  reg [FIFO_DEPTH-1:0][DATA_WIDTH-1:0] fifo_op_b;
  reg [$clog2(FIFO_DEPTH)-1:0] fifo_wr_ptr;
  reg [$clog2(FIFO_DEPTH)-1:0] fifo_rd_ptr;


  // --- Core Assignment ---
  reg [NUM_CORES-1:0] core_busy;   // Indicates if a core is busy
  wire [NUM_CORES-1:0] core_ready;   // Indicates if a core is ready for a new operation
  wire [NUM_CORES-1:0][2:0] core_result_opcode;
  wire [NUM_CORES-1:0][DATA_WIDTH-1:0] core_result;
  wire [NUM_CORES-1:0] core_result_valid;
  wire [NUM_CORES-1:0] core_op_status; // Operation status from each core

  // ---  Local and SDRAM ---
  reg [LOCAL_RAM_ADDR_WIDTH-1:0] local_ram_addr_reg;
  reg local_ram_we_reg;
  reg [DATA_WIDTH-1:0] local_ram_data_out_reg;
  reg sdram_req_reg;
  reg sdram_wr_reg;
  reg [SDRAM_ADDR_WIDTH-1:0] sdram_addr_reg;
  reg [DATA_WIDTH-1:0] sdram_data_out_reg;
  reg sdram_read_done;

  // --- Internal Operation Data ---
  reg [2:0] current_opcode;
  reg [DATA_WIDTH-1:0] operand_a;
  reg [DATA_WIDTH-1:0] operand_b;
  reg core_assigned; // Flag to indicate if a core has been assigned
  reg [$clog2(NUM_CORES)-1:0] assigned_core_id;  // ID of the assigned core


  // --- Operation Queue Management ---
  always @(posedge clk) begin
    if (rst) begin
      fifo_wr_ptr <= 0;
      fifo_rd_ptr <= 0;
      fifo_valid <= 0;
    end else begin
      // Write to FIFO (if there is a host request and space available)
      if (host_req && !fifo_valid[fifo_wr_ptr] && (host_opcode inside {1,2,3,4})) begin
          fifo_opcode[fifo_wr_ptr] <= host_opcode;
          fifo_op_a[fifo_wr_ptr] <= host_data_in_a;
          fifo_op_b[fifo_wr_ptr] <= host_data_in_b;
          fifo_valid[fifo_wr_ptr] <= 1;
          fifo_wr_ptr <= (fifo_wr_ptr == FIFO_DEPTH - 1) ? 0 : fifo_wr_ptr + 1;
      end
      // Read from FIFO (if a core is ready)
      if (|core_ready && fifo_valid[fifo_rd_ptr]) begin
          fifo_valid[fifo_rd_ptr] <= 0;
          fifo_rd_ptr <= (fifo_rd_ptr == FIFO_DEPTH - 1) ? 0 : fifo_rd_ptr + 1;
      end
    end
  end

  // --- Core Instantiation ---
  genvar i;
  generate
    for (i = 0; i < NUM_CORES; i = i + 1) begin : core_gen
      bfloat16_core #(
        .DATA_WIDTH(DATA_WIDTH)
      ) core_inst (
        .clk(clk),
        .rst(rst),
        .core_enable(core_ready[i] && fifo_valid[fifo_rd_ptr] && !core_busy[i]),  // Enable core when ready, FIFO has data, and core is not busy
        .opcode(fifo_opcode[fifo_rd_ptr]),  // Opcode from FIFO
        .operand_a(fifo_op_a[fifo_rd_ptr]),  // Operand A from FIFO
        .operand_b(fifo_op_b[fifo_rd_ptr]),  // Operand B from FIFO
        .result(core_result[i]),          // Result output
        .result_valid(core_result_valid[i]),// Result valid signal
        .op_status(core_op_status[i]),       // Operation status output
        .core_busy(core_busy[i]),        // Core busy signal
        .core_result_opcode(core_result_opcode[i])
      );

      // Core Ready Logic (simple example - could be improved with pipelining)
      assign core_ready[i] = !core_busy[i]; // Core is ready when not busy

    end
  endgenerate


  // --- State Machine ---
  always @(posedge clk) begin
    if (rst) begin
      state <= STATE_IDLE;
      host_ack_reg <= 0;
      host_busy_reg <= 0;
      host_data_out_reg <= 0;
      host_op_status_reg <= 0;
      local_ram_we_reg <= 0;
      sdram_req_reg <= 0;
      sdram_wr_reg <= 0;
      sdram_read_done <= 0;
      core_assigned <= 0;
      assigned_core_id <= 0;
    end else begin
      case (state)
        STATE_IDLE: begin
          host_ack_reg <= 0;
          host_busy_reg <= 1; // Initially busy, waiting for a core or operation
          core_assigned <= 0;

          if (host_req) begin
            state <= STATE_HOST_REQ;
          end else if (|core_ready && fifo_valid[fifo_rd_ptr]) begin //check if there are pending ops and a core free.
             state <= STATE_EXECUTE;
          end
        end

        STATE_HOST_REQ: begin
          host_ack_reg <= 1;
          host_busy_reg <= 1; // Still busy processing the request
          case (host_opcode)
            1, 2, 3, 4: begin // Arithmetic operations
              state <= STATE_IDLE; //Enqued in the FIFO, go to IDLE
            end
            5: begin // Local RAM read
              state <= STATE_LOCAL_RAM_READ;
              local_ram_addr_reg <= host_local_ram_addr;
            end
            6: begin // Local RAM write
              state <= STATE_LOCAL_RAM_WRITE;
              local_ram_addr_reg <= host_local_ram_addr;
              local_ram_data_out_reg <= host_data_in_a;
              local_ram_we_reg <= 1;
            end
            7: begin // SDRAM read
              state <= STATE_SDRAM_READ;
              sdram_addr_reg <= host_sdram_addr;
              sdram_req_reg <= 1;
              sdram_wr_reg <= 0;
            end
            8: begin // SDRAM write
              state <= STATE_SDRAM_WRITE;
              sdram_addr_reg <= host_sdram_addr;
              sdram_data_out_reg <= host_sdram_data_in;
              sdram_req_reg <= 1;
              sdram_wr_reg <= 1;
            end
            default: begin
              state <= STATE_IDLE;
              host_op_status_reg <= 1; // Indicate an invalid opcode
            end
          endcase
        end

        STATE_LOCAL_RAM_READ: begin
          host_data_out_reg <= local_ram_data_in;
          host_op_status_reg <= 0;
          state <= STATE_IDLE;  // Done reading, back to IDLE
        end

        STATE_LOCAL_RAM_WRITE: begin
          local_ram_we_reg <= 0; // Deassert write enable
          host_op_status_reg <= 0;
          state <= STATE_IDLE; // Done writing
        end
        STATE_SDRAM_READ: begin
          if (sdram_ack) begin
              host_data_out_reg <= sdram_data_in;
              host_op_status_reg <= 0;
              sdram_req_reg <= 0;
              state <= STATE_IDLE;
          end
        end

        STATE_SDRAM_WRITE: begin
           if (sdram_ack) begin
             sdram_req_reg <= 0;
             sdram_wr_reg <= 0;
             host_op_status_reg <= 0;
             state <= STATE_IDLE;
           end
        end


        STATE_EXECUTE: begin //Dequeue and try to assign
          host_busy_reg <= 1; // Busy executing
          host_op_status_reg <= 0; // Assume success initially

          // Find a free core
          if (!core_assigned) begin
              for (int i = 0; i < NUM_CORES; i++) begin
                  if (core_ready[i]) begin
                      assigned_core_id <= i;
                      core_assigned <= 1;
                      state <= STATE_WAIT_CORE; //move to waiting state
                      $display("Assigned core: %d", i);
                      break; // Assign the first available core
                  end
              end
          end

        end
        STATE_WAIT_CORE: begin // Wait for the assigned core to finish
          if (core_result_valid[assigned_core_id]) begin
            host_data_out_reg <= core_result[assigned_core_id];
            host_op_status_reg <= core_op_status[assigned_core_id];
            state <= STATE_IDLE; //go back to idle after result
            $display("Core %d finished", assigned_core_id);
          end
        end


        default: begin
          state <= STATE_IDLE;
        end
      endcase
    end
  end

  // --- Output Assignments ---
  assign host_ack = host_ack_reg;
  assign host_busy = host_busy_reg;
  assign host_data_out = host_data_out_reg;
  assign host_op_status = host_op_status_reg;

  assign local_ram_addr = local_ram_addr_reg;
  assign local_ram_we = local_ram_we_reg;
  assign local_ram_data_out = local_ram_data_out_reg;

  assign sdram_req = sdram_req_reg;
  assign sdram_wr = sdram_wr_reg;
  assign sdram_addr = sdram_addr_reg;
  assign sdram_data_out = sdram_data_out_reg;


endmodule

module bfloat16_core #(
  parameter DATA_WIDTH = 16
) (
  input wire clk,
  input wire rst,
  input wire core_enable, // Core enable signal
  input wire [2:0] opcode,   // Operation code
  input wire [DATA_WIDTH-1:0] operand_a,
  input wire [DATA_WIDTH-1:0] operand_b,
  output reg [DATA_WIDTH-1:0] result,
  output reg result_valid,
  output reg op_status,      // 0: success, 1: error (e.g., divide by zero)
  output reg core_busy,    // Core busy signal
  output reg [2:0] core_result_opcode
);
  // --- Internal Registers ---

  reg [7:0] exp_a;
  reg [7:0] exp_b;
  reg [7:0] exp_result;
  reg [6:0] mant_a;
  reg [6:0] mant_b;
  reg [15:0] mant_result;  // Wider mantissa for intermediate calculations
  reg sign_a;
  reg sign_b;
  reg sign_result;
    reg [3:0] operation_cycles;  // Counter for multi-cycle operations

  // --- Decompose bfloat16 ---

  always @(*) begin
    sign_a = operand_a[15];
    exp_a = operand_a[14:7];
    mant_a = operand_a[6:0];

    sign_b = operand_b[15];
    exp_b = operand_b[14:7];
    mant_b = operand_b[6:0];

    // Add implicit leading '1' for normalized numbers
    if (exp_a != 0)
       mant_a = {1'b1, mant_a};
    else
       mant_a = {1'b0, mant_a}; // Denormalized number

    if (exp_b != 0)
       mant_b = {1'b1, mant_b};
    else
      mant_b = {1'b0, mant_b}; // Denormalized number
  end


  // --- Asynchronous Arithmetic Operations (Combinational + Sequential for Multi-cycle) ---
  // Note: These are simplified, non-pipelined implementations.  Real implementations would
  // use pipelining for higher throughput and would handle special cases (NaN, Inf, etc.) more thoroughly.

  always @(posedge clk) begin
    if(rst) begin
      core_busy <= 0;
      result_valid <= 0;
      result <= 0;
      op_status <= 0;
      operation_cycles <= 0;
      core_result_opcode <= 0;
    end else if (core_enable) begin //only start if enable signal is on
      core_busy <= 1;
      result_valid <= 0; // Initially not valid
      op_status <= 0;    // Assume success
      core_result_opcode <= opcode;

        case (opcode)
            1: begin // Addition
                // Sign and Exponent Handling (Simplified)
                if (exp_a < exp_b) begin
                    // Swap operands to ensure exp_a >= exp_b
                    {exp_a, exp_b} = {exp_b, exp_a};
                    {mant_a, mant_b} = {mant_b, mant_a};
                    {sign_a, sign_b} = {sign_b, sign_a};
                end
                // Align mantissas
                 mant_b = mant_b >> (exp_a - exp_b);


                // Perform addition or subtraction based on signs
                if (sign_a == sign_b) begin
                    mant_result = mant_a + mant_b;
                    sign_result = sign_a;
                end else begin
                    mant_result = mant_a - mant_b;
                    sign_result = sign_a;
                end
                exp_result = exp_a;

                  // Normalize (Simplified - assumes no overflow)
                  if (mant_result[15]) begin // Check for overflow
                    mant_result = mant_result >> 1;
                    exp_result = exp_result + 1;
                  end
                  while (mant_result[7] == 0 && exp_result >0 && mant_result[15:8] !=0) begin // Normalize left
                    mant_result = mant_result << 1;
                    exp_result = exp_result - 1;
                  end
                result <= {sign_result, exp_result[7:0], mant_result[7:1]};
                result_valid <= 1; // Result is now valid
                core_busy <= 0;
            end

            2: begin // Subtraction (Similar to addition, but change sign of operand B)
              // Sign and Exponent Handling (Simplified)

                if (exp_a < exp_b) begin
                    // Swap operands to ensure exp_a >= exp_b
                    {exp_a, exp_b} = {exp_b, exp_a};
                    {mant_a, mant_b} = {mant_b, mant_a};
                     sign_b = ~sign_b; //invert the sign of B
                    {sign_a, sign_b} = {sign_b, sign_a};

                end else begin
                  sign_b = ~sign_b; //invert sign of B
                end
                // Align mantissas
                mant_b = mant_b >> (exp_a - exp_b);

                // Perform addition or subtraction based on signs
                if (sign_a == sign_b) begin
                    mant_result = mant_a + mant_b;
                    sign_result = sign_a;
                end else begin
                    mant_result = mant_a - mant_b;
                    sign_result = sign_a;

                end
              exp_result = exp_a;

                // Normalize (Simplified - assumes no overflow)
                if (mant_result[15]) begin
                  mant_result = mant_result >> 1;
                  exp_result = exp_result + 1;
                end
                while (mant_result[7] == 0 && exp_result >0 && mant_result[15:8] !=0) begin // Normalize left
                    mant_result = mant_result << 1;
                    exp_result = exp_result - 1;
                end
                result <= {sign_result, exp_result[7:0], mant_result[7:1]};
                result_valid <= 1; // Result is now valid
                core_busy <= 0;
            end

            3: begin // Multiplication (Simplified)
              if(operation_cycles == 0) begin //First Cycle
                sign_result = sign_a ^ sign_b;
                exp_result = exp_a + exp_b - 127;      // Bias adjustment
                mant_result = mant_a * mant_b;  // 8x8 -> 16-bit result
                operation_cycles <= 1; // Move to next stage
              end else begin // Second Cycle, finish up
                // Normalize
                if (mant_result[15]) begin
                  mant_result = mant_result >> 1;
                  exp_result = exp_result + 1;
                end
                while (mant_result[7] == 0 && exp_result >0 && mant_result[15:8] !=0) begin // Normalize left
                    mant_result = mant_result << 1;
                    exp_result = exp_result - 1;
                end
                result <= {sign_result, exp_result[7:0], mant_result[7:1]};
                result_valid <= 1; // Result is now valid
                operation_cycles <= 0;
                core_busy <= 0;
              end

            end

            4: begin // Division (Simplified - Non-restoring division)
                if(operation_cycles == 0) begin //First Cycle
                  sign_result = sign_a ^ sign_b;
                  exp_result = exp_a - exp_b + 127; // Bias adjustment

                  // Handle divide by zero
                  if (mant_b == 0) begin
                      op_status <= 1;  // Set error flag
                      result <= 16'hFFFF; // Or some other error value (e.g., NaN)
                      result_valid <= 1;
                      core_busy<=0;
                  end else begin
                    mant_result = mant_a << 7; //left shift to prepare division
                    operation_cycles <= 1; //go to division stage
                  end

              end else if (operation_cycles inside {1,2,3,4,5,6,7,8}) begin
                // Non-restoring division steps
                if (mant_result[15] == 0) begin
                  mant_result = (mant_result << 1) - (mant_b << 8);
                end else begin
                  mant_result = (mant_result << 1) + (mant_b << 8);
                end
                mant_result[0] = ~mant_result[15]; // Quotient bit
                operation_cycles <= operation_cycles + 1;

              end else begin //Last stage
                // Remainder correction (if needed for non-restoring division)
                if(mant_result[15] == 1) begin
                  mant_result = mant_result + (mant_b << 8);
                end

                while (mant_result[7] == 0 && exp_result >0 && mant_result[15:8] !=0) begin // Normalize left
                    mant_result = mant_result << 1;
                    exp_result = exp_result - 1;
                end

                result <= {sign_result, exp_result[7:0], mant_result[7:1]};
                result_valid <= 1; // Result is now valid
                operation_cycles <= 0; //reset cycles
                core_busy <= 0;
              end

            end
            default: begin //noop
               result <= 0;
               result_valid <= 1;
               core_busy <=0;
            end
        endcase
    end else begin //if core_enable is low, reduce busy time
      if(core_busy)
        core_busy <= 0;
    end
  end

endmodule