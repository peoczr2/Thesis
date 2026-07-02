# Beam Search + ILS replication report

Generated: 2026-07-02 13:52

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
| LR1_DR02_VC01_V6a | 33809.00 | 33808.95 | 33808.97 | 33808.95 | 33808.95 | -0.00% | 102.22 |
| LR1_DR02_VC02_V6a | 74982.00 | 74981.65 | 78052.08 | 78052.08 | 78052.08 | 4.09% | 141.37 |
| LR1_DR02_VC03_V7a | 40446.00 | 40340.01 | 40992.20 | 40589.73 | 40589.73 | 0.36% | 162.98 |
| LR1_DR02_VC03_V8a | 43721.00 | 43721.43 | 43772.61 | 43772.61 | 43772.61 | 0.12% | 125.36 |

![Gap comparison](bs_ils_replication_gap_paper_120_20260702_134336.svg)
