# Beam Search + ILS replication report

Generated: 2026-06-01 21:50

## Paper settings used

- Beam nodes per level `N = 1000`
- Maximum children per node `w = 2`
- Greedy randomized completions per successor `q = 3`
- ILS parameters from Table 4: initial SA probability `0.79`, final SA probability `0.01`, `640` iterations, restore after `4` non-improving accepted moves, `2` perturbations
- Horizon run in this batch: `120`

## Implementation notes

The paper does not specify every tie-break, random sampling, and simulated annealing temperature detail. This replication follows the described structure: BS evaluates partial solutions with one deterministic and `q - 1` randomized greedy completions, keeps unique scored nodes, applies RVND neighborhoods, then runs ILS. The local-search phase is applied to the BS incumbent before ILS; applying RVND to every generated complete solution was left as a documented deviation because the paper's implementation details and pruning rules are not fully specified.

## Results

| Instance | Obj | Paper best | Rep BS | Rep LS | Rep ILS | Rep gap | Time (s) |
|---|---:|---:|---:|---:|---:|---:|---:|
| LR1_DR02_VC01_V6a | 33809.00 | 33808.95 | 33440.17 | 33440.17 | 33440.17 | -1.09% | 347.20 |
| LR1_DR02_VC02_V6a | 74982.00 | 74981.65 | 88411.03 | 88411.03 | 88411.03 | 17.91% | 734.67 |
| LR1_DR02_VC03_V7a | 40446.00 | 40340.01 | 47354.23 | 47354.23 | 47354.23 | 17.08% | 784.84 |
| LR1_DR02_VC03_V8a | 43721.00 | 43721.43 | 375880.67 | 375880.67 | 327658.42 | 649.43% | 129.93 |
| LR1_DR02_VC04_V8a | 41657.00 | 41708.65 | 43104.29 | 43104.29 | 43104.29 | 3.47% | 1787.71 |
| LR1_DR02_VC05_V8a | 36659.00 | 36536.62 | 41178.13 | 41178.13 | 41178.13 | 12.33% | 1267.46 |

![Gap comparison](bs_ils_replication_gap_120_20260601_215020.svg)
