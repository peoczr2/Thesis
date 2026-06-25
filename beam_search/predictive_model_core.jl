abstract type AbstractQualityModel end

function training_sample_count(model::Union{Nothing, AbstractQualityModel})
    return model === nothing ? 0 : length(model.ys)
end

function model_is_trained(model::Union{Nothing, AbstractQualityModel})
    return model !== nothing && model.trained
end

function add_training_example!(model::AbstractQualityModel, x::Vector{Float64}, y::Float64)
    if isfinite(y) && all(isfinite, x)
        push!(model.xs, copy(x))
        push!(model.ys, y)
    end
    return model
end

function training_matrix(model::AbstractQualityModel)
    n = length(model.ys)
    p = length(model.xs[1])
    X = Matrix{Float64}(undef, n, p)
    for i in 1:n
        X[i, :] = model.xs[i]
    end
    return X, collect(model.ys)
end
