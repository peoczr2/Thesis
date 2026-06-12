# Beam Search + ILS replication report

Generated: 2026-06-01 22:53

## Paper settings used

- Beam nodes per level `N = 5`
- Maximum children per node `w = 2`
- Greedy randomized completions per successor `q = 3`
- ILS parameters from Table 4: initial SA probability `0.79`, final SA probability `0.01`, `2` iterations, restore after `4` non-improving accepted moves, `2` perturbations
- Horizon run in this batch: `120`

## Implementation notes

The paper does not specify every tie-break, random sampling, and simulated annealing temperature detail. This replication follows the described structure: BS evaluates partial solutions with one deterministic and `q - 1` randomized greedy completions, keeps unique scored nodes, applies RVND neighborhoods, then runs ILS. The local-search phase is applied to the BS incumbent before ILS; applying RVND to every generated complete solution was left as a documented deviation because the paper's implementation details and pruning rules are not fully specified.

## Results

| Instance | Obj | Paper best | Rep BS | Rep LS | Rep ILS | Rep gap | Time (s) |
|---|---:|---:|---:|---:|---:|---:|---:|
| LR1_DR02_VC01_V6a | 33809.00 | 33808.95 | 33440.17 | 33440.17 | 33440.17 | -1.09% | 5.49 |
| LR1_DR02_VC02_V6a | 74982.00 | 74981.65 | 83270.95 | 83270.95 | 83270.95 | 11.05% | 8.34 |
| LR1_DR02_VC03_V7a | 40446.00 | 40340.01 | 45562.03 | 45562.03 | 45562.03 | 12.65% | 9.05 |
| LR1_DR02_VC03_V8a | 43721.00 | 43721.43 | 49394.87 | 49394.87 | 49394.87 | 12.98% | 5.93 |
| LR1_DR02_VC04_V8a | 41657.00 | 41708.65 | 41304.29 | 41304.29 | 41062.98 | -1.43% | 15.30 |
| LR1_DR02_VC05_V8a | 36659.00 | 36536.62 | 37069.06 | 37069.06 | 37069.06 | 1.12% | 14.22 |

![Gap comparison](bs_ils_replication_gap_smoke_120_20260601_225235.svg)
