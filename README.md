

TODO: check if the following is handled and how. it might be better to have a vessel wait, so that the ports inventory hints a certain level. Does the heuristic handles this, if not maybe wise to have it handled
TODO: Also it is not handled to choose alpha in a certain way, like maybe inventory in the next port would be fucked, but in the current one its fine with alpha = 0, but why not have alpha non-zero now if in the next port P costs are high, maybe greedily choosen based on which port has low P (inventory) costs
TODO: consider carefully when to use copy() or deepcopy()
TODO: vessel discount_empty() is not handled, so it might happen that vessel goes empty somewhere adn that gets a discount
TODO: How does the starting ports handled? Routing costs, or there is an initial port? 
TODO: It would be wise to precalculate C_{a}^vc and P_{j,t}
TODO: Handle efficiency and speed with highly nested variables
TODO: What is last_service_time_vessel for?
TODO: Pay extra attention how to handle nothing variables for last_occ_...
TODO: There might be initial inventory levels at ports and even in vessels
TODO: in the mrplib there is this mindurationinregiontable, what is that?

## Beam node scoring experiments

The beam search now supports two node scorers:

- `:gra`: the original deterministic/randomized greedy-completion scorer.
- `:predictive`: an online surrogate model. It warms up on GRA-labelled partial nodes, ranks all successors from partial-solution features, then GRA-completes only the top predictive shortlist before keeping children.

Predictive model choices:

- `--surrogate-model=linear`: ridge regression.
- `--surrogate-model=tree`: CART-style regression tree.
- `--surrogate-model=forest`: bootstrap random forest. Use `--surrogate-forest-trees=8` to adjust the forest size.

Example:

```bash
julia --project=. replication_runner.jl --horizon=120 --N=1000 --w=2 --q=3 --scorer=predictive --surrogate-model=forest --surrogate-forest-trees=8 --surrogate-shortlist-multiplier=2
```

## Linear surrogate thesis analysis

Generate the stage-time and objective-cascade tables from an existing GRA run and linear run:

```bash
julia --project=. analyze_linear_surrogate_results.jl \
  --gra=results/bs_ils_replication_mlcmp_gra_120_20260623_091648.csv \
  --linear=results/bs_ils_replication_mlcmp_linear_120_20260623_093113.csv
```

This writes:

- `results/linear_surrogate_analysis_plan_report.md`
- `results/linear_surrogate_stage_time_table.csv`
- `results/linear_surrogate_objective_cascade_table.csv`


### Full replication runner defaults

The normal replication runners keep their default experiment settings at the top of `replication_runner.jl` and `replication_runner_parallel.jl`. Override them with CLI flags when needed:

```bash
julia --project=. replication_runner_parallel.jl --horizon=120 --N=1000 --w=2 --q=3 --seeds=1:10 --jobs=6 --scorer=gra --label=gra_main
julia --project=. replication_runner_parallel.jl --horizon=120 --N=1000 --w=2 --q=3 --seeds=1:10 --jobs=6 --scorer=predictive --surrogate-model=linear --surrogate-min-samples=16 --surrogate-lambda=1.0 --surrogate-shortlist-multiplier=2 --label=linear_main
```

The Windows/Python pull-queue prototype is in `distributed-queue/`.
