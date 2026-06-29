# Beam Search + ILS replication report

Generated: 2026-06-17 12:03

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
| LR1_DR02_VC01_V6a | 33809.00 | 33808.95 | 33809.37 | 33809.37 | 33809.37 | 0.00% | 863.46 |
| LR1_DR02_VC02_V6a | 74982.00 | 74981.65 | 78052.47 | 78052.47 | 78052.47 | 4.09% | 1562.04 |
| LR1_DR02_VC03_V7a | 40446.00 | 40340.01 | 44535.11 | 44535.11 | 44535.11 | 10.11% | 1884.05 |
| LR1_DR02_VC03_V8a | 43721.00 | 43721.43 | 45549.25 | 45549.25 | 45549.25 | 4.18% | 1449.92 |
| LR1_DR02_VC04_V8a | 41657.00 | 41708.65 | 41708.19 | 41708.19 | 41708.19 | 0.12% | 4072.20 |
| LR1_DR02_VC05_V8a | 36659.00 | 36536.62 | 36715.17 | 36715.17 | 36715.17 | 0.15% | 3008.19 |

![Gap comparison](bs_ils_replication_gap_paper_120_20260617_082925.svg)
