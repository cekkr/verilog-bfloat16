# Microprogrammi per HybridCore

Questo documento descrive una serie di microprogrammi di esempio per testare le diverse funzionalità del processore HybridCore.

## Microprogramma 1: Calcolo con Interi

Questo microprogramma esegue semplici operazioni aritmetiche con interi di diversi formati.

```assembly
// Inizializzazione
ADD.INT32 R1, R0, #10        // R1 = 10
ADD.INT32 R2, R0, #20        // R2 = 20
ADD.INT16 R3, R0, #30        // R3 = 30
ADD.INT8  R4, R0, #40        // R4 = 40

// Operazioni aritmetiche
ADD.INT32 R5, R1, R2         // R5 = R1 + R2 = 30
MUL.INT16 R6, R3, R4         // R6 = R3 * R4 = 1200
SUB.INT32 R7, R5, R1         // R7 = R5 - R1 = 20
AND.INT8  R8, R4, #15        // R8 = R4 & 15 = 8
```

### Bytecode (formato hex)
```
0241000A  // ADD.INT32 R1, R0, #10
02420014  // ADD.INT32 R2, R0, #20
0143001E  // ADD.INT16 R3, R0, #30
00440028  // ADD.INT8  R4, R0, #40
02512000  // ADD.INT32 R5, R1, R2
12634000  // MUL.INT16 R6, R3, R4
02751000  // SUB.INT32 R7, R5, R1
0084000F  // AND.INT8  R8, R4, #15
```

## Microprogramma 2: Calcolo in Virgola Mobile

Questo microprogramma testa le operazioni con numeri in virgola mobile in diverse precisioni.

```assembly
// Inizializzazione valori FP
ADD.FP32  R1, R0, #5         // R1 = 5.0
ADD.FP32  R2, R0, #3         // R2 = 3.0
ADD.FP16  R3, R0, #2         // R3 = 2.0
ADD.BF16  R4, R0, #4         // R4 = 4.0

// Operazioni matematiche
ADD.FP32  R5, R1, R2         // R5 = R1 + R2 = 8.0
MUL.FP32  R6, R1, R2         // R6 = R1 * R2 = 15.0
MUL.FP16  R7, R3, R4         // R7 = R3 * R4 = 8.0

// Modalità AMC - operazioni matematiche avanzate
SQRT.FP32 R8, R6, R0         // R8 = sqrt(R6) = sqrt(15.0)
SIN.FP32  R9, R1, R0         // R9 = sin(R1) = sin(5.0)
```

### Bytecode (formato hex)
```
06410005  // ADD.FP32  R1, R0, #5
06420003  // ADD.FP32  R2, R0, #3
04430002  // ADD.FP16  R3, R0, #2
05440004  // ADD.BF16  R4, R0, #4
06512000  // ADD.FP32  R5, R1, R2
26612000  // MUL.FP32  R6, R1, R2
24734000  // MUL.FP16  R7, R3, R4
2E860000  // SQRT.FP32 R8, R6, R0 (MUL in AMC mode)
6E910000  // SIN.FP32  R9, R1, R0 (ABS in AMC mode)
```

## Microprogramma 3: Operazioni di Memoria

Questo microprogramma testa le operazioni di caricamento e salvataggio in memoria con diverse codifiche di dati.

```assembly
// Inizializza valori
ADD.INT32 R1, R0, #100       // R1 = 100 (usato come indirizzo base)
ADD.INT32 R2, R0, #42        // R2 = 42 (dato da salvare)
ADD.FP32  R3, R0, #3.14      // R3 = 3.14 (dato da salvare)

// Operazioni di memoria
STORE.INT32 R2, R1, #0       // Salva R2 all'indirizzo R1+0
STORE.FP32  R3, R1, #4       // Salva R3 all'indirizzo R1+4
LOAD.INT32  R4, R1, #0       // Carica R4 dall'indirizzo R1+0 (dovrebbe essere 42)
LOAD.FP32   R5, R1, #4       // Carica R5 dall'indirizzo R1+4 (dovrebbe essere 3.14)
```

### Bytecode (formato hex)
```
02410064  // ADD.INT32 R1, R0, #100
0242002A  // ADD.INT32 R2, R0, #42
0643000A  // ADD.FP32  R3, R0, #10 (usiamo 10 come approssimazione per 3.14 in questo esempio)
E2210000  // STORE.INT32 R2, R1, #0
E6310004  // STORE.FP32  R3, R1, #4
D2410000  // LOAD.INT32  R4, R1, #0
D6510004  // LOAD.FP32   R5, R1, #4
```

## Microprogramma 4: Test Modalità Mista

Questo microprogramma dimostra come passare tra modalità GP e AMC per sfruttare entrambe le capacità del processore.

```assembly
// Inizializza valori
ADD.FP32  R1, R0, #4         // R1 = 4.0
ADD.FP32  R2, R0, #9         // R2 = 9.0

// Calcolo GP standard
MUL.FP32  R3, R1, R2         // R3 = R1 * R2 = 36.0
ADD.FP32  R4, R1, R2         // R4 = R1 + R2 = 13.0

// Calcolo AMC avanzato
SQRT.FP32 R5, R2, R0         // R5 = sqrt(R2) = 3.0 (sqrt di 9)
MADD.FP32 R6, R3, R1         // R6 = (R3 * 1) + R1 = 36.0 + 4.0 = 40.0
SIN.FP32  R7, R1, R0         // R7 = sin(R1) = sin(4.0)
```

### Bytecode (formato hex)
```
06410004  // ADD.FP32  R1, R0, #4
06420009  // ADD.FP32  R2, R0, #9
26312000  // MUL.FP32  R3, R1, R2
06412000  // ADD.FP32  R4, R1, R2
2E520000  // SQRT.FP32 R5, R2, R0 (MUL in AMC mode)
0E631000  // MADD.FP32 R6, R3, R1 (ADD in AMC mode)
6E710000  // SIN.FP32  R7, R1, R0 (ABS in AMC mode)
```

## Microprogramma 5: Implementazione di un Algoritmo

Questo microprogramma implementa un semplice algoritmo per calcolare il valore medio di un array di numeri e determinare quanti elementi sono sopra la media.

```assembly
// Inizializzazione
ADD.INT32 R1, R0, #0        // R1 = 0 (indice)
ADD.INT32 R2, R0, #5        // R2 = 5 (lunghezza array)
ADD.INT32 R3, R0, #100      // R3 = 100 (indirizzo base dell'array)
ADD.INT32 R4, R0, #0        // R4 = 0 (somma)

// Caricamento dati di esempio in memoria (in un'applicazione reale verrebbero da input)
ADD.INT32 R10, R0, #10       // Valore 1: 10
STORE.INT32 R10, R3, #0      // Salva all'indirizzo base
ADD.INT32 R10, R0, #20       // Valore 2: 20
STORE.INT32 R10, R3, #4      // Salva all'indirizzo base + 4
ADD.INT32 R10, R0, #15       // Valore 3: 15
STORE.INT32 R10, R3, #8      // Salva all'indirizzo base + 8
ADD.INT32 R10, R0, #30       // Valore 4: 30
STORE.INT32 R10, R3, #12     // Salva all'indirizzo base + 12
ADD.INT32 R10, R0, #25       // Valore 5: 25
STORE.INT32 R10, R3, #16     // Salva all'indirizzo base + 16

// Calcolo media (mettiamo solo parte del loop per brevità)
LOAD.INT32 R10, R3, #0       // Carica primo elemento
ADD.INT32 R4, R4, R10        // Aggiunge alla somma
LOAD.INT32 R10, R3, #4       // Carica secondo elemento
ADD.INT32 R4, R4, R10        // Aggiunge alla somma
// ... (continua per tutti gli elementi)

// Calcola la media
DIV.FP32 R5, R4, R2         // R5 = R4 / R2 (somma / numero elementi)
```

### Bytecode (formato hex)
```
02410000  // ADD.INT32 R1, R0, #0
02420005  // ADD.INT32 R2, R0, #5
02430064  // ADD.INT32 R3, R0, #100
02440000  // ADD.INT32 R4, R0, #0
024A000A  // ADD.INT32 R10, R0, #10
E2A30000  // STORE.INT32 R10, R3, #0
024A0014  // ADD.INT32 R10, R0, #20
E2A30004  // STORE.INT32 R10, R3, #4
024A000F  // ADD.INT32 R10, R0, #15
E2A30008  // STORE.INT32 R10, R3, #8
024A001E  // ADD.INT32 R10, R0, #30
E2A3000C  // STORE.INT32 R10, R3, #12
024A0019  // ADD.INT32 R10, R0, #25
E2A30010  // STORE.INT32 R10, R3, #16
D2A30000  // LOAD.INT32 R10, R3, #0
0244A000  // ADD.INT32 R4, R4, R10
D2A30004  // LOAD.INT32 R10, R3, #4
0244A000  // ADD.INT32 R4, R4, R10
36542000  // DIV.FP32 R5, R4, R2
```

---

## Note per l'Esecuzione

Questi microprogrammi sono progettati per testare diverse funzionalità del processore HybridCore. In un'implementazione reale, sarebbero necessari elementi aggiuntivi come gestione dei salti condizionali e supporto per loop, che sono stati omessi per semplicità in questi esempi.

Per un test completo, è consigliabile:

1. Eseguire ogni microprogramma separatamente
2. Verificare i valori dei registri dopo l'esecuzione
3. Per gli ultimi due microprogrammi, potrebbe essere necessario estendere l'implementazione del processore per supportare completamente tutte le operazioni