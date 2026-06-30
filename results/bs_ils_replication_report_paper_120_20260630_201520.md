# Beam Search + ILS replication report

Generated: 2026-06-30 20:31

## Paper settings used

- Beam nodes per level `N = 1000`
- Maximum children per node `w = 2`
- Greedy randomized completions per successor `q = 3`
- Beam node scorer: `gra`
- ILS parameters from Table 4: initial SA probability `0.79`, final SA probability `0.01`, `640` iterations, restore after `4` non-improving accepted moves, `2` perturbations
- Horizon run in this batch: `120`

## Implementation notes

The paper does not specify every tie-break, random sampling, and simulated annealing temperature detail. This replication follows the described structure: BS evaluates partial solutions with one deterministic and `q - 1` randomized greedy completions, keeps the best `N` complete GRA solutions found across the beam, applies RVND to that saved pool, then passes the best locally improved solution to ILS.

## Results

| Instance | Obj | Paper best | Rep BS | Rep LS | Rep ILS | Rep gap | Time (s) |
|---|---:|---:|---:|---:|---:|---:|---:|
| LR1_DR02_VC01_V6a | 33809.00 | 33808.95 | 33808.97 | 33808.96 | 33808.96 | -0.00% | 93.28 |
| LR1_DR02_VC02_V6a | 74982.00 | 74981.65 | 78052.08 | 78052.08 | 78052.08 | 4.09% | 132.97 |
| LR1_DR02_VC03_V7a | 40446.00 | 40340.01 | 40992.20 | 40992.20 | 40992.20 | 1.35% | 152.43 |
| LR1_DR02_VC03_V8a | 43721.00 | 43721.43 | 43772.61 | 43772.61 | 43772.61 | 0.12% | 117.27 |
| LR1_DR02_VC04_V8a | 41657.00 | 41708.65 | 41948.52 | 41708.69 | 41708.69 | 0.12% | 257.91 |
| LR1_DR02_VC05_V8a | 36659.00 | 36536.62 | 36623.99 | 36603.23 | 36603.23 | -0.15% | 212.21 |

![Gap comparison](bs_ils_replication_gap_paper_120_20260630_201520.svg)
