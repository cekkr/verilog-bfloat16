// hybridcore_testbench_example.v
// Esempio di testbench specifico per il Microprogramma 2 (Calcolo in Virgola Mobile)

`timescale 1ns / 1ps

module hybridcore_testbench_fp;
    reg clk;
    reg rst;
    reg [31:0] instruction;
    reg [63:0] mem_data_in;
    wire [63:0] mem_data_out;
    wire [31:0] mem_addr;
    wire mem_write_enable;
    wire mem_read_enable;
    
    // Array per memorizzare le istruzioni del microprogramma
    reg [31:0] program_memory [0:9];
    integer pc = 0;
    integer i;
    
    // Instantiate the processor
    hybridcore_processor dut(
        .clk(clk),
        .rst(rst),
        .instruction(instruction),
        .mem_data_in(mem_data_in),
        .mem_data_out(mem_data_out),
        .mem_addr(mem_addr),
        .mem_write_enable(mem_write_enable),
        .mem_read_enable(mem_read_enable)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // Load the microprogram
    initial begin
        // Microprogramma 2: Calcolo in Virgola Mobile
        program_memory[0] = 32'h06410005;  // ADD.FP32  R1, R0, #5
        program_memory[1] = 32'h06420003;  // ADD.FP32  R2, R0, #3
        program_memory[2] = 32'h04430002;  // ADD.FP16  R3, R0, #2
        program_memory[3] = 32'h05440004;  // ADD.BF16  R4, R0, #4
        program_memory[4] = 32'h06512000;  // ADD.FP32  R5, R1, R2
        program_memory[5] = 32'h26612000;  // MUL.FP32  R6, R1, R2
        program_memory[6] = 32'h24734000;  // MUL.FP16  R7, R3, R4
        program_memory[7] = 32'h2E860000;  // SQRT.FP32 R8, R6, R0 (MUL in AMC mode)
        program_memory[8] = 32'h6E910000;  // SIN.FP32  R9, R1, R0 (ABS in AMC mode)
    end
    
    // Test sequence
    initial begin
        // Initialize
        rst = 1;
        instruction = 32'h00000000;
        mem_data_in = 64'h0000000000000000;
        
        // Reset
        #10 rst = 0;
        
        // Execute the microprogram
        for (pc = 0; pc < 9; pc = pc + 1) begin
            instruction = program_memory[pc];
            #10; // Wait for instruction to complete
        end
        
        // Display results
        $display("============ Register Contents After Execution ============");
        for (i = 0; i < 10; i = i + 1) begin
            $display("R%0d = %h", i, dut.registers.registers[i]);
        end
        $display("==========================================================");
        
        // Verify expected results (for a controlled test)
        if (dut.registers.registers[5] == 64'h0000000000000008) 
            $display("SUCCESS: R5 contains expected value 8.0");
        else
            $display("ERROR: R5 contains %h, expected 0x0000000000000008", dut.registers.registers[5]);
            
        if (dut.registers.registers[6] == 64'h000000000000000F) 
            $display("SUCCESS: R6 contains expected value 15.0");
        else
            $display("ERROR: R6 contains %h, expected 0x000000000000000F", dut.registers.registers[6]);
        
        // Finish simulation
        #10 $finish;
    end
    
    // Optional waveform generation
    initial begin
        $dumpfile("hybridcore_fp_test.vcd");
        $dumpvars(0, hybridcore_testbench_fp);
    end
    
endmodule