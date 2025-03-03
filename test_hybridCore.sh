#!/bin/bash
# test_hybridcore.sh - Script di test per il processore HybridCore

# Colori per output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=======================================${NC}"
echo -e "${BLUE}  Test di simulazione per HybridCore   ${NC}"
echo -e "${BLUE}=======================================${NC}"

# Verifica che Icarus Verilog sia installato
if ! command -v iverilog &> /dev/null; then
    echo -e "${RED}Errore: Icarus Verilog non è installato.${NC}"
    echo "Installalo con: sudo apt-get install iverilog"
    exit 1
fi

# Crea directory per i test se non esiste
mkdir -p hybridcore_tests

# Funzione per eseguire un test
run_test() {
    local test_name="$1"
    local test_instruction_file="$2"
    local expected_output="$3"
    
    echo -e "${YELLOW}Esecuzione test: ${test_name}${NC}"
    
    # Crea il file di testbench per questo test specifico
    cat > hybridcore_tests/test_${test_name}.v <<EOF
\`include "hybridcore.v"

module test_${test_name};
    reg clk;
    reg rst;
    reg [31:0] instruction;
    reg [63:0] mem_data_in;
    wire [63:0] mem_data_out;
    wire [31:0] mem_addr;
    wire mem_write_enable;
    wire mem_read_enable;
    
    // Risultati salvati per verifica
    reg [63:0] test_results [0:15];
    
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
    
    // Test sequence
    initial begin
        // Initialize
        rst = 1;
        instruction = 32'h00000000;
        mem_data_in = 64'h0000000000000000;
        
        // Reset
        #10 rst = 0;
        
        // Istruzioni da leggere da file
        \$readmemh("${test_instruction_file}", test_instr_mem);
        
        // Esegui le istruzioni
        for (int i = 0; i < test_instr_count; i = i + 1) begin
            #10 instruction = test_instr_mem[i];
            // Se è un'istruzione LOAD, prepara i dati di memoria
            if ((instruction[31:28] == 4'hD)) begin
                mem_data_in = 64'hABCD_1234_5678_9ABC;
            end
        end
        
        // Salva i risultati dei registri per la verifica
        for (int i = 0; i < 16; i = i + 1) begin
            test_results[i] = dut.registers.registers[i];
        end
        
        // Stampa risultati in un formato facilmente processabile
        \$display("TEST_RESULT_START");
        for (int i = 0; i < 16; i = i + 1) begin
            \$display("R%0d: %h", i, test_results[i]);
        end
        \$display("TEST_RESULT_END");
        
        // Finish
        #10 \$finish;
    end
    
    // Array per le istruzioni
    reg [31:0] test_instr_mem [0:63];
    integer test_instr_count = 0;
    
    // Leggi numero di istruzioni
    initial begin
        \$readmemh("${test_instruction_file}.count", test_instr_count_arr);
        test_instr_count = test_instr_count_arr[0];
    end
    
    reg [31:0] test_instr_count_arr [0:0];
    
endmodule
EOF

    # Compila con Icarus Verilog
    iverilog -o hybridcore_tests/test_${test_name} hybridcore_tests/test_${test_name}.v 2> hybridcore_tests/compile_${test_name}.log
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}[ERRORE] Compilazione fallita per ${test_name}${NC}"
        echo -e "Log di compilazione:"
        cat hybridcore_tests/compile_${test_name}.log
        return 1
    fi
    
    # Esegui la simulazione
    vvp hybridcore_tests/test_${test_name} > hybridcore_tests/output_${test_name}.log
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}[ERRORE] Esecuzione fallita per ${test_name}${NC}"
        return 1
    fi
    
    # Estrai i risultati
    sed -n '/TEST_RESULT_START/,/TEST_RESULT_END/p' hybridcore_tests/output_${test_name}.log > hybridcore_tests/results_${test_name}.txt
    
    # Confronta con i risultati attesi
    if [ ! -z "$expected_output" ] && [ -f "$expected_output" ]; then
        if diff -B hybridcore_tests/results_${test_name}.txt "$expected_output" > /dev/null; then
            echo -e "${GREEN}[SUCCESSO] ${test_name} - Risultati corrispondono ai valori attesi${NC}"
        else
            echo -e "${RED}[FALLITO] ${test_name} - Risultati non corrispondono ai valori attesi${NC}"
            echo "Risultati ottenuti:"
            cat hybridcore_tests/results_${test_name}.txt
            echo "Risultati attesi:"
            cat "$expected_output"
            return 1
        fi
    else
        echo -e "${YELLOW}[INFO] ${test_name} - Nessun confronto con risultati attesi${NC}"
        echo "Risultati ottenuti:"
        cat hybridcore_tests/results_${test_name}.txt
    fi
    
    echo -e "${GREEN}[COMPLETATO] Test ${test_name}${NC}"
    return 0
}

# Prima verifica che il file principale Verilog esista
if [ ! -f "hybridcore.v" ]; then
    echo -e "${RED}File hybridcore.v non trovato!${NC}"
    echo "Creo il file dal codice fornito..."
    
    # Inserisci qui il codice Verilog completo se necessario
    # cat > hybridcore.v <<EOF
    # ... codice Verilog ...
    # EOF
    
    # Per ora, usiamo un messaggio di errore
    echo -e "${RED}Devi creare il file hybridcore.v prima di eseguire i test${NC}"
    exit 1
fi

# Crea i file di istruzioni per i diversi test

# Test 1: Operazioni aritmetiche di base (modalità GP)
echo -e "${BLUE}Preparazione Test 1: Operazioni aritmetiche base${NC}"
cat > hybridcore_tests/test1_instructions.hex <<EOF
00410300  // ADD.INT32 R1, R2, R3
02520400  // MUL.INT32 R2, R5, R4
01630500  // SUB.INT32 R3, R6, R5
07741000  // AND.INT8 R4, R7, R1
EOF

# File conta istruzioni
echo -e "4" > hybridcore_tests/test1_instructions.hex.count

# Test 2: Operazioni in virgola mobile (modalità GP)
echo -e "${BLUE}Preparazione Test 2: Operazioni in virgola mobile${NC}"
cat > hybridcore_tests/test2_instructions.hex <<EOF
0648000A  // ADD.FP32 R4, R1, #10
06590002  // ADD.FP32 R5, R9, #2
2669A000  // MUL.FP32 R6, R9, R10
EOF

# File conta istruzioni
echo -e "3" > hybridcore_tests/test2_instructions.hex.count

# Test 3: Operazioni di memoria
echo -e "${BLUE}Preparazione Test 3: Operazioni di memoria${NC}"
cat > hybridcore_tests/test3_instructions.hex <<EOF
06410005  // ADD.FP32 R1, R0, #5
D3200064  // LOAD.INT64 R2, R0, #100
E6300096  // STORE.FP32 R3, R0, #150
D6400032  // LOAD.FP32 R4, R0, #50
EOF

# File conta istruzioni
echo -e "4" > hybridcore_tests/test3_instructions.hex.count

# Test 4: Modalità AMC (operazioni matematiche avanzate)
echo -e "${BLUE}Preparazione Test 4: Modalità AMC${NC}"
cat > hybridcore_tests/test4_instructions.hex <<EOF
06510064  // ADD.FP32 R5, R1, #100
2E620000  // SQRT.FP32 R6, R2, R0 (MUL in AMC mode)
0E730000  // MADD.FP32 R7, R3, R0 (ADD in AMC mode)
6E840000  // SIN.FP32 R8, R4, R0 (ABS in AMC mode)
EOF

# File conta istruzioni
echo -e "4" > hybridcore_tests/test4_instructions.hex.count

# Test 5: Mix di istruzioni
echo -e "${BLUE}Preparazione Test 5: Mix di operazioni${NC}"
cat > hybridcore_tests/test5_instructions.hex <<EOF
00A10005  // ADD.INT8 R1, R10, #5
02C20064  // MUL.INT16 R2, R12, #100
0683000A  // ADD.FP32 R3, R8, #10
2EC40000  // SQRT.FP32 R4, R12, R0 (MUL in AMC mode)
06950020  // ADD.FP32 R5, R9, #32
F0960000  // MOV R6, R9, R0
EOF

# File conta istruzioni
echo -e "6" > hybridcore_tests/test5_instructions.hex.count

# Crea risultati attesi per i test (opzionale)
# cat > hybridcore_tests/expected_test1.txt <<EOF
# TEST_RESULT_START
# R0: 0000000000000000
# R1: 0000000000000005
# ...
# TEST_RESULT_END
# EOF

# Esegui i test
echo -e "${BLUE}===== Inizio esecuzione test =====${NC}"
run_test "test1_basic_arithmetic" "hybridcore_tests/test1_instructions.hex" ""
run_test "test2_floating_point" "hybridcore_tests/test2_instructions.hex" ""
run_test "test3_memory_operations" "hybridcore_tests/test3_instructions.hex" ""
run_test "test4_amc_mode" "hybridcore_tests/test4_instructions.hex" ""
run_test "test5_mixed" "hybridcore_tests/test5_instructions.hex" ""

echo -e "${BLUE}===== Fine esecuzione test =====${NC}"

# Riepilogo
echo -e "${BLUE}===== Riepilogo Test =====${NC}"
echo "I risultati dettagliati sono disponibili nella directory hybridcore_tests/"
echo "Verificare i file results_*.txt per i valori dei registri"

# Generazione facoltativa di waveform
echo -e "${YELLOW}Vuoi generare i grafici waveform per l'analisi dettagliata? (s/n)${NC}"
read -n 1 -r generate_waveform
echo

if [[ $generate_waveform =~ ^[Ss]$ ]]; then
    echo -e "${BLUE}Generazione waveform per test_mixed...${NC}"
    
    # Crea versione modificata del testbench con dump VCD
    sed '/initial begin/a\\n        // Dump waveform\n        $dumpfile("hybridcore_tests/waveform.vcd");\n        $dumpvars(0, test_test5_mixed);' hybridcore_tests/test_test5_mixed.v > hybridcore_tests/test_test5_mixed_wave.v
    
    # Compila ed esegui
    iverilog -o hybridcore_tests/wave_test hybridcore_tests/test_test5_mixed_wave.v
    vvp hybridcore_tests/wave_test
    
    echo -e "${GREEN}Waveform generato: hybridcore_tests/waveform.vcd${NC}"
    echo "Puoi visualizzarlo con GTKWave: gtkwave hybridcore_tests/waveform.vcd"
fi

echo -e "${BLUE}=======================================${NC}"
echo -e "${GREEN}Test completati!${NC}"