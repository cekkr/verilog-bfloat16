# HybridCore Processor - Instruction Set Architecture (ISA)

## Principi di Design

L'architettura HybridCore è progettata per combinare efficacemente:
- Elaborazione generale (GP - General Purpose)
- Calcoli matematici complessi (AMC - Advanced Math Computation)

L'ISA implementa diverse innovazioni:
1. **Type Encoding** - Tipi di dati codificati direttamente nelle istruzioni
2. **Instruction Overloading** - Stesse istruzioni per diversi tipi di dati
3. **Dynamic Mode Switching** - Cambio fluido tra modalità GP e AMC
4. **Vector Processing** - Supporto nativo per operazioni vettoriali

## Formato delle Istruzioni

### Formato Base (32-bit)
```
[4-bit OpCode][3-bit Type][1-bit Mode][4-bit Dest][4-bit Src1][4-bit Src2][12-bit Immediate/Extended]
```

### Formato Esteso (64-bit)
```
[4-bit OpCode][3-bit Type][1-bit Mode][4-bit Dest][4-bit Src1][4-bit Src2][46-bit Extended Data]
```

## Codifica dei Tipi (Type Encoding)

Il campo da 3-bit "Type" permette 8 diversi tipi di dati:

| Codice | Tipo     | Descrizione                     |
|--------|----------|---------------------------------|
| 000    | INT8     | Intero 8-bit                    |
| 001    | INT16    | Intero 16-bit                   |
| 010    | INT32    | Intero 32-bit                   |
| 011    | INT64    | Intero 64-bit                   |
| 100    | FP16     | Float 16-bit (IEEE-754)         |
| 101    | BF16     | BFloat16 16-bit                 |
| 110    | FP32     | Float 32-bit (IEEE-754)         |
| 111    | FP64     | Float 64-bit (IEEE-754)         |

## Modalità (Mode)

Il bit "Mode" determina se l'istruzione viene eseguita in:
- `0`: Modalità GP (General Purpose)
- `1`: Modalità AMC (Advanced Math Computation)

## Istruzioni di Base

### Operazioni Aritmetiche

| OpCode | Mnemonica | Descrizione                      | Supporto Tipi             |
|--------|-----------|----------------------------------|---------------------------|
| 0x0    | ADD       | Addizione                        | Tutti                     |
| 0x1    | SUB       | Sottrazione                      | Tutti                     |
| 0x2    | MUL       | Moltiplicazione                  | Tutti                     |
| 0x3    | DIV       | Divisione                        | Tutti                     |
| 0x4    | MOD       | Modulo                           | Solo INT                  |
| 0x5    | NEG       | Negazione                        | Tutti                     |
| 0x6    | ABS       | Valore assoluto                  | Tutti                     |

### Operazioni Logiche e di Confronto

| OpCode | Mnemonica | Descrizione                      | Supporto Tipi             |
|--------|-----------|----------------------------------|---------------------------|
| 0x7    | AND       | AND logico                       | Solo INT                  |
| 0x8    | OR        | OR logico                        | Solo INT                  |
| 0x9    | XOR       | XOR logico                       | Solo INT                  |
| 0xA    | CMP       | Confronto                        | Tutti                     |
| 0xB    | SHL       | Shift a sinistra                 | Solo INT                  |
| 0xC    | SHR       | Shift a destra                   | Solo INT                  |

### Operazioni di Memoria

| OpCode | Mnemonica | Descrizione                      | Supporto Tipi             |
|--------|-----------|----------------------------------|---------------------------|
| 0xD    | LOAD      | Carica dalla memoria             | Tutti                     |
| 0xE    | STORE     | Salva in memoria                 | Tutti                     |
| 0xF    | MOV       | Muove tra registri               | Tutti                     |

## Funzionalità di Overloading

L'overloading delle istruzioni è implementato attraverso il campo Type. La stessa istruzione (OpCode) può operare su diversi tipi di dati. Ad esempio, `ADD.FP32` e `ADD.INT16` utilizzano lo stesso OpCode ma operano su tipi diversi.

### Esempio di codifica

```
ADD.FP32 R1, R2, R3
```

Codifica: `[0000][110][0][0001][0010][0011][000000000000]`
- OpCode: 0000 (ADD)
- Type: 110 (FP32)
- Mode: 0 (GP)
- Dest: 0001 (R1)
- Src1: 0010 (R2)
- Src2: 0011 (R3)

## Istruzioni Matematiche Avanzate (AMC Mode)

Quando il bit Mode = 1, gli stessi OpCode assumono funzionalità matematiche avanzate:

| OpCode | GP Mode (0)    | AMC Mode (1)                | Supporto Tipi            |
|--------|--------------  |-----------------------------|--------------------------| 
| 0x0    | ADD            | MADD (Multiply-Add)         | Tutti FP e BF16          |
| 0x1    | SUB            | MSUB (Multiply-Subtract)    | Tutti FP e BF16          |
| 0x2    | MUL            | SQRT (Square Root)          | Tutti FP e BF16          |
| 0x3    | DIV            | INV (Inverse)               | Tutti FP e BF16          |
| 0x4    | MOD            | EXP (Exponential)           | Tutti FP e BF16          |
| 0x5    | NEG            | LOG (Natural Logarithm)     | Tutti FP e BF16          |
| 0x6    | ABS            | SIN (Sine)                  | Tutti FP e BF16          |
| 0x7    | AND            | COS (Cosine)                | Tutti FP e BF16          |
| 0x8    | OR             | TAN (Tangent)               | Tutti FP e BF16          |
| 0x9    | XOR            | RSQRT (Recip. Square Root)  | Tutti FP e BF16          |

### Operazioni Vettoriali

In modalità AMC, è possibile eseguire operazioni su vettori utilizzando il formato esteso da 64-bit. Il campo Extended Data può contenere:
- Informazioni sulla lunghezza del vettore
- Stride (passo) per accesso non contiguo
- Maschere per operazioni condizionali

### Esempio di codifica vettoriale

```
MUL.FP32.V R1, R2, #16
```

Codifica estesa: `[0010][110][1][0001][0010][0000][00000000000000000000000000000000000000000010000]`
- OpCode: 0010 (MUL → SQRT in AMC)
- Type: 110 (FP32)
- Mode: 1 (AMC)
- Dest: 0001 (R1)
- Src1: 0010 (R2)
- Src2: 0000 (Non utilizzato)
- Extended: Configura un'operazione vettoriale di lunghezza 16

## Registri Specializzati

### Registri per Calcolo Generale (Modalità GP)
- 16 registri generici (R0-R15) che possono contenere qualsiasi tipo di dato
- R0 è sempre zero, R15 è il registro di stato

### Registri per Calcolo Matematico (Modalità AMC)
Gli stessi registri R0-R15 vengono reinterpretati:
- R0-R7: registri scalari
- R8-R11: registri vettoriali/matriciali
- R12-R14: registri per maschere e configurazione
- R15: registro di stato AMC

## Ottimizzazioni Architetturali

### Gestione della Precisione
- Auto-conversione tra tipi quando necessario
- Operazioni di troncamento e arrotondamento controllate via registro di stato
- Rilevamento automatico di sottoflussi/overflow

### Fusion Engine
Identificazione e fusione automatica di pattern ricorrenti, come:
- Fused Multiply-Add (FMA)
- Normalizzazioni
- Attivazioni (ReLU, Sigmoid, ecc.)

### Energia e Performance
- Supporto per calcoli a precisione ridotta (INT8/FP16) per risparmio energetico
- Pipeline dinamica che si adatta al tipo di carico di lavoro
- Predizione di branch ottimizzata per loop matematici

## Estensioni Future

1. **QNT Extension** - Supporto per quantizzazione dinamica
2. **TENS Extension** - Operazioni tensoriali di alto livello
3. **SIMD+ Extension** - Istruzioni SIMD avanzate per elaborazione parallela

## Sommario

L'architettura ISA HybridCore introduce un approccio innovativo combinando:
1. Efficienza di codifica attraverso l'overloading del tipo
2. Dualità GP/AMC mediante mode switching
3. Supporto nativo per vari tipi numerici
4. Ottimizzazione per algoritmi matematici complessi

Questa ISA è particolarmente adatta per applicazioni che richiedono sia elaborazione tradizionale che calcolo scientifico/IA, offrendo flessibilità senza sacrificare le prestazioni.