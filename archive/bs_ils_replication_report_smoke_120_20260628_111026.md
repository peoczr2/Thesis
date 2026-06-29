# Beam Search + ILS replication report

Generated: 2026-06-28 11:10

## Paper settings used

- Beam nodes per level `N = 5`
- Maximum children per node `w = 2`
- Greedy randomized completions per successor `q = 3`
- Beam node scorer: `predictive`
- Predictive surrogate model: `linear`
- Predictive warmup levels: `1`
- Predictive minimum samples: `16`
- Predictive ridge lambda: `1.0`
- Predictive shortlist multiplier: `2`
- ILS parameters from Table 4: initial SA probability `0.79`, final SA probability `0.01`, `2` iterations, restore after `4` non-improving accepted moves, `2` perturbations
- Horizon run in this batch: `120`

## Implementation notes

This variant replaces exhaustive GRA-based beam-node scoring with an online `linear` predictive model. The model is trained from GRA-completed partial nodes, ranks all successors cheaply, and only the top predictive shortlist is GRA-completed before choosing children and saving incumbent candidates for RVND and ILS.

## Results

| Instance | Obj | Paper best | Rep BS | Rep LS | Rep ILS | Rep gap | Time (s) |
|---|---:|---:|---:|---:|---:|---:|---:|
| LR1_DR02_VC01_V6a | 33809.00 | 33808.95 | 37009.04 | 35468.23 | 35468.23 | 4.91% | 0.49 |
| LR1_DR02_VC02_V6a | 74982.00 | 74981.65 | 84882.34 | 84882.34 | 84882.34 | 13.20% | 0.55 |
| LR1_DR02_VC03_V7a | 40446.00 | 40340.01 | 45553.44 | 45553.41 | 45553.41 | 12.63% | 0.44 |
| LR1_DR02_VC03_V8a | 43721.00 | 43721.43 | 50732.57 | 48232.55 | 48232.55 | 10.32% | 0.48 |
| LR1_DR02_VC04_V8a | 41657.00 | 41708.65 | 42143.17 | 42143.14 | 42143.14 | 1.17% | 0.73 |
| LR1_DR02_VC05_V8a | 36659.00 | 36536.62 | 37209.69 | 37174.81 | 37174.81 | 1.41% | 0.67 |

![Gap comparison](bs_ils_replication_gap_smoke_120_20260628_111026.svg)
