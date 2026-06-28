using Random
using MIRPLib

const DEFAULT_BEAM_SCORER = :predictive

abstract type AbstractNodeScorer end

mutable struct GRABeamScorer <: AbstractNodeScorer
    q::Int64
end

mutable struct PredictiveBeamScorer <: AbstractNodeScorer
    q::Int64
    quality_model::AbstractQualityModel
    warmup_levels::Int64
    shortlist_multiplier::Int64
    levels_seen::Int64
end

function PredictiveBeamScorer(
    quality_model::AbstractQualityModel;
    q::Int64 = 3,
    warmup_levels::Int64 = 1,
    shortlist_multiplier::Int64 = 2,
)
    return PredictiveBeamScorer(q, quality_model, warmup_levels, shortlist_multiplier, 0)
end

beam_scorer_name(::GRABeamScorer) = :gra
beam_scorer_name(::PredictiveBeamScorer) = :predictive

function create_beam_scorer(
    scorer::Symbol;
    q::Int64 = 3,
    surrogate_model::Symbol = :linear,
    surrogate_warmup_levels::Int64 = 1,
    surrogate_min_samples::Int64 = 16,
    surrogate_lambda::Float64 = 1.0,
    surrogate_shortlist_multiplier::Int64 = 2,
    surrogate_forest_trees::Int64 = 8,
    rng::AbstractRNG = Random.default_rng(),
)
    q < 1 && throw(ArgumentError("q must be a positive integer."))
    if scorer == :gra
        return GRABeamScorer(q)
    elseif scorer == :predictive
        quality_model = create_quality_model(
            surrogate_model;
            min_samples = surrogate_min_samples,
            lambda = surrogate_lambda,
            forest_trees = surrogate_forest_trees,
            rng = rng,
        )
        return PredictiveBeamScorer(
            quality_model;
            q = q,
            warmup_levels = surrogate_warmup_levels,
            shortlist_multiplier = surrogate_shortlist_multiplier,
        )
    end

    throw(ArgumentError("scorer must be either :gra or :predictive."))
end

function complete_and_train!(
    model::PredictiveBeamScorer,
    successor::Solution,
    mirp::MIRP;
    rng::AbstractRNG = Random.default_rng(),
)
    x = partial_solution_features(mirp, successor)
    full_solutions = evaluate(successor, mirp, model.q; rng = rng)
    add_training_example!(model.quality_model, x, successor.score)
    return full_solutions
end

function score_successors!(
    model::GRABeamScorer,
    mirp::MIRP,
    successors::Vector{Solution},
    w::Int64;
    rng::AbstractRNG = Random.default_rng(),
)
    completed_solutions = Solution[]
    for successor in successors
        append!(completed_solutions, evaluate(successor, mirp, model.q; rng = rng))
    end
    return keep_best_unique(successors, w), completed_solutions
end

function score_successors!(
    model::PredictiveBeamScorer,
    mirp::MIRP,
    successors::Vector{Solution},
    w::Int64;
    rng::AbstractRNG = Random.default_rng(),
)
    completed_solutions = Solution[]

    # Use GRA, not enough data to train a predictive model yet
    if model.levels_seen < model.warmup_levels || !model.quality_model.trained 
        for successor in successors
            append!(completed_solutions, complete_and_train!(model, successor, mirp; rng = rng))
        end
        return keep_best_unique(successors, w), completed_solutions
    end

    for successor in successors
        successor.score = predict_quality(model.quality_model, mirp, successor)
    end

    # TODO: this could be more efficient with better datastructure
    shortlist_size = min(length(successors), max(w, model.shortlist_multiplier * w))
    shortlist = keep_best_unique(successors, shortlist_size)

    for successor in shortlist
        append!(completed_solutions, complete_and_train!(model, successor, mirp; rng = rng))
    end

    return keep_best_unique(shortlist, w), completed_solutions
end

finish_level!(::GRABeamScorer) = nothing

function finish_level!(model::PredictiveBeamScorer)
    fit!(model.quality_model)
    model.levels_seen += 1
    return model
end
