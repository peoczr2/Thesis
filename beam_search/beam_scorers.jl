using Random
using MIRPLib

const DEFAULT_BEAM_SCORER = :gra

abstract type AbstractNodeScorer end

mutable struct GRABeamScorer <: AbstractNodeScorer
    q::Int64
end

mutable struct PredictiveBeamScorer{Q<:AbstractQualityModel} <: AbstractNodeScorer
    q::Int64
    quality_model::Q    
    warmup_levels::Int64
    usage_ratio::Float64
    shortlist_multiplier::Int64
end

function PredictiveBeamScorer(
    quality_model::Q;
    q::Int64 = 3,
    warmup_levels::Int64 = 1,
    usage_ratio::Float64 = 0.8,
    shortlist_multiplier::Int64 = 2,
) where {Q<:AbstractQualityModel}
    warmup_levels < 0 && throw(ArgumentError("warmup_levels must be non-negative."))
    !(0.0 <= usage_ratio <= 1.0) && throw(ArgumentError("usage_ratio must be between 0.0 and 1.0."))
    shortlist_multiplier < 1 && throw(ArgumentError("shortlist_multiplier must be positive."))
    return PredictiveBeamScorer{Q}(q, quality_model, warmup_levels, usage_ratio, shortlist_multiplier)
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
    surrogate_usage_ratio::Float64 = 0.8,
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
            usage_ratio = surrogate_usage_ratio,
            shortlist_multiplier = surrogate_shortlist_multiplier,
        )
    end

    throw(ArgumentError("scorer must be either :gra or :predictive."))
end





function score_successors!(
    model::GRABeamScorer,
    mirp::MIRP,
    successors::Vector{Solution},
    w::Int64,
    level::Int64;
    rng::AbstractRNG = Random.default_rng(),
)
    completed_solutions = Solution[]
    for successor in successors
        append!(completed_solutions, evaluate(successor, mirp, model.q; rng = rng))
    end
    return keep_best_N_unique(successors, w), completed_solutions
end

function score_successors!(
    model::PredictiveBeamScorer,
    mirp::MIRP,
    successors::Vector{Solution},
    w::Int64,
    level::Int64;
    rng::AbstractRNG = Random.default_rng(),
)
    completed_solutions = Solution[]
    training_samples = Tuple{Vector{Float64}, Float64}[]

    use_warmup_gra = level < model.warmup_levels

    if use_warmup_gra || !model.quality_model.trained
        sizehint!(training_samples, length(successors))
        for successor in successors
            x = partial_solution_features(mirp, successor)
            append!(completed_solutions, evaluate(successor, mirp, model.q; rng = rng))
            push!(training_samples, (x, successor.score))
        end
        fit!(model.quality_model, training_samples)
        return keep_best_N_unique(successors, w), completed_solutions
    end

    gra_nodes = Solution[]
    sizehint!(gra_nodes, ceil(Int64, length(successors) * min(1.0, 1.0 - model.usage_ratio + 0.1)))
    predict_nodes = Solution[]
    sizehint!(predict_nodes, ceil(Int64, length(successors) * min(1.0, model.usage_ratio + 0.1)))

    for successor in successors
        if rand(rng) > model.usage_ratio
            push!(gra_nodes, successor)
        else
            push!(predict_nodes, successor)
        end
    end

    sizehint!(training_samples, length(gra_nodes))
    for successor in gra_nodes
        x = partial_solution_features(mirp, successor)
        append!(completed_solutions, evaluate(successor, mirp, model.q; rng = rng))
        push!(training_samples, (x, successor.score))
    end
    fit!(model.quality_model, training_samples)

    gra_node_ids = IdSet()
    for successor in gra_nodes
        push!(gra_node_ids, successor)
    end

    for successor in predict_nodes
        successor.score = predict_quality(model.quality_model, mirp, successor)
    end

    shortlist_size = min(length(successors), max(w, model.shortlist_multiplier * w))
    shortlist = keep_best_N_unique(successors, shortlist_size)

    empty!(training_samples)
    sizehint!(training_samples, length(shortlist))
    for successor in shortlist
        if !(successor in gra_node_ids)
            x = partial_solution_features(mirp, successor)
            append!(completed_solutions, evaluate(successor, mirp, model.q; rng = rng))
            push!(training_samples, (x, successor.score))
        end
    end
    fit!(model.quality_model, training_samples)

    return keep_best_N_unique(shortlist, w), completed_solutions
end
