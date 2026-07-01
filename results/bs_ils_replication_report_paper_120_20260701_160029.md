# Beam Search + ILS replication report

Generated: 2026-07-01 16:12

## Paper settings used

- Beam nodes per level `N = 1000`
- Maximum children per node `w = 2`
- Greedy randomized completions per successor `q = 5`
- Beam node scorer: `gra`
- ILS parameters from Table 4: initial SA probability `0.79`, final SA probability `0.01`, `640` iterations, restore after `4` non-improving accepted moves, `2` perturbations
- Horizon run in this batch: `120`

## Implementation notes

The paper does not specify every tie-break, random sampling, and simulated annealing temperature detail. This replication follows the described structure: BS evaluates partial solutions with one deterministic and `q - 1` randomized greedy completions, keeps the best `N` complete GRA solutions found across the beam, applies RVND to that saved pool, then passes the best locally improved solution to ILS.

## Results

| Instance | Obj | Paper best | Rep BS | Rep LS | Rep ILS | Rep gap | Time (s) |
|---|---:|---:|---:|---:|---:|---:|---:|
| LR1_DR02_VC01_V6a | 33809.00 | 33808.95 | 33808.97 | 33808.95 | 33808.95 | -0.00% | 140.16 |
| LR1_DR02_VC02_V6a | 74982.00 | 74981.65 | 78052.08 | 78052.08 | 78052.08 | 4.09% | 193.41 |
| LR1_DR02_VC03_V7a | 40446.00 | 40340.01 | 40566.92 | 40566.92 | 40566.92 | 0.30% | 231.43 |
| LR1_DR02_VC03_V8a | 43721.00 | 43721.43 | 43772.62 | 43772.62 | 43772.61 | 0.12% | 178.04 |

![Gap comparison](bs_ils_replication_gap_paper_120_20260701_160029.svg)
