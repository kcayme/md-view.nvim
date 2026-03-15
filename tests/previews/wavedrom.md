# WaveDrom Digital Timing Diagrams

## Basic Clock Signal

```wavedrom
{ "signal": [{ "name": "clk", "wave": "p......" }] }
```

## Clock with Data

```wavedrom
{ "signal": [
  { "name": "clk",  "wave": "p......" },
  { "name": "data", "wave": "x.345x.", "data": ["a", "b", "c"] }
] }
```

## Bus Protocol

```wavedrom
{ "signal": [
  { "name": "clk",   "wave": "p..Pp..P" },
  { "name": "addr",  "wave": "x..3.x..", "data": ["A1"] },
  { "name": "wr",    "wave": "0..1..0." },
  { "name": "data",  "wave": "x..3..x.", "data": ["D1"] },
  { "name": "ack",   "wave": "0....10." }
] }
```

## Signal Groups

```wavedrom
{ "signal": [
  ["Master",
    { "name": "clk",  "wave": "p...." },
    { "name": "req",  "wave": "01..0" }
  ],
  ["Slave",
    { "name": "ack",  "wave": "0.1.0" },
    { "name": "data", "wave": "x.34x", "data": ["D0", "D1"] }
  ]
] }
```
