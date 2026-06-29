using Random

include("predictive_model_core.jl")
include("predictive_features.jl")
include("linear_quality_model.jl")

function create_quality_model(
    surrogate_model::Symbol;
    min_samples::Int64 = 16,
    lambda::Float64 = 1.0,
    forest_trees::Int64 = 8,
    rng::AbstractRNG = Random.default_rng(),
)
    if surrogate_model == :linear
        return LinearQualityModel(min_samples = min_samples, lambda = lambda)
    end

    throw(ArgumentError("surrogate_model must be :linear."))
end
