#!/bin/bash
# test_microprograms.sh - Script specifico per testare i microprogrammi HybridCore

# Colori per output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=======================================${NC}"
echo -e "${BLUE}  Test Microprogrammi per HybridCore   ${NC}"
echo -e "${BLUE}=======================================${NC}"

# Verifica che Icarus Verilog sia installato
if ! command -v iverilog &> /dev/null; then
    echo -e "${RED}Errore: Icarus Verilog non è installato.${NC}"
    echo "Installalo con: sudo apt-get install iverilog"
    exit 1
fi

# Crea directory per i test se non esiste
mkdir -p microprograms

# Funzione per generare ed eseguire un testbench per un microprogramma specifico
run_microprogram() {
    local name="$1"
    local description="$2"
    local instructions=("${@:3}")
    local num_instructions=${#instructions[@]}
    
    echo -e "${YELLOW}Esecuzione microprogramma: ${name}${NC}"
    echo -e "${BLUE}${description}${NC}"
    
    # Crea il file con le istruzioni
    echo -e "// Microprogramma: ${name}\n// ${description}" > microprograms/${name}_instructions.v
    
    for i in "${!instructions[@]}"; do
        echo "program_memory[$i] = 32'h${instructions[$i]};" >> microprograms/${name}_instructions.v
    done
    
    # Crea il file testbench
    cat > microprograms/${name}_testbench.v <<EOF
\`timescale 1ns / 1ps

module ${name}_testbench;
    reg clk;
    reg rst;
    reg [31:0] instruction;
    reg [63:0] mem_data_in;
    wire [63:0] mem_data_out;
    wire [31:0] mem_addr;
    wire mem_write_enable;
    wire mem_read_enable;
    
    // Array per memorizzare le istruzioni del microprogramma
    reg [31:0] program_memory [0:${num_instructions-1}];
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
        // Include the program instructions
        \`include "microprograms/${name}_instructions.v"
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
        for (pc = 0; pc < ${num_instructions}; pc = pc + 1) begin
            instruction = program_memory[pc];
            
            // Per istruzioni LOAD, prepara dati fittizi in memoria
            if ((instruction[31:28] == 4'hD)) begin
                mem_data_in = 64'hABCD1234_5678ABCD;
            end
            
            #10; // Wait for instruction to complete
        end
        
        // Display results
        \$display("============ Register Contents After Execution ============");
        for (i = 0; i < 16; i = i + 1) begin
            \$display("R%0d = %h", i, dut.registers.registers[i]);
        end
        \$display("==========================================================");
        
        // Finish simulation
        #10 \$finish;
    end
    
    // Generate VCD file for waveform viewing
    initial begin
        \$dumpfile("microprograms/${name}_waveform.vcd");
        \$dumpvars(0, ${name}_testbench);
    end
    
endmodule
EOF

    # Compila con Icarus Verilog
    iverilog -o microprograms/${name}_sim microprograms/${name}_testbench.v hybridcore.v 2> microprograms/${name}_compile_log.txt
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}[ERRORE] Compilazione fallita per ${name}${NC}"
        echo -e "Log di compilazione:"
        cat microprograms/${name}_compile_log.txt
        return 1
    fi
    
    # Esegui la simulazione
    vvp microprograms/${name}_sim > microprograms/${name}_results.txt
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}[ERRORE] Esecuzione fallita per ${name}${NC}"
        return 1
    fi
    
    echo -e "${GREEN}[SUCCESSO] Microprogramma ${name} eseguito correttamente${NC}"
    echo -e "Risultati disponibili in: microprograms/${name}_results.txt"
    echo -e "Waveform disponibile in: microprograms/${name}_waveform.vcd"
    
    # Mostra i primi risultati per comodità
    echo -e "${BLUE}Primi risultati:${NC}"
    head -n 20 microprograms/${name}_results.txt
    
    return 0
}

# Prima verifica che il file principale Verilog esista
if [ ! -f "hybridcore.v" ]; then
    echo -e "${RED}File hybridcore.v non trovato!${NC}"
    echo -e "${RED}Devi creare il file hybridcore.v prima di eseguire i test${NC}"
    exit 1
fi

# Esegui ogni microprogramma

echo -e "${BLUE}===== Esecuzione Microprogramma 1: Calcolo con Interi =====${NC}"
run_microprogram "int_calc" "Operazioni aritmetiche con interi di diversi formati" \
    "0241000A" "02420014" "0143001E" "00440028" \
    "02512000" "12634000" "02751000" "0084000F"

echo -e "${BLUE}===== Esecuzione Microprogramma 2: Calcolo in Virgola Mobile =====${NC}"
run_microprogram "float_calc" "Operazioni con numeri in virgola mobile in diverse precisioni" \
    "06410005" "06420003" "04430002" "05440004" \
    "06512000" "26612000" "24734000" "2E860000" "6E910000"

echo -e "${BLUE}===== Esecuzione Microprogramma 3: Operazioni di Memoria =====${NC}"
run_microprogram "memory_ops" "Operazioni di caricamento e salvataggio in memoria" \
    "02410064" "0242002A" "0643000A" \
    "E2210000" "E6310004" "D2410000" "D6510004"

echo -e "${BLUE}===== Esecuzione Microprogramma 4: Test Modalità Mista =====${NC}"
run_microprogram "mixed_mode" "Test cambio tra modalità GP e AMC" \
    "06410004" "06420009" "26312000" "06412000" \
    "2E520000" "0E631000" "6E710000"

echo -e "${BLUE}===== Fine esecuzione test =====${NC}"

# Riepilogo
echo -e "${BLUE}===== Riepilogo Microprogrammi =====${NC}"
echo "I risultati dettagliati sono disponibili nella directory microprograms/"
echo -e "${GREEN}Microprogrammi eseguiti correttamente!${NC}"

exit 0