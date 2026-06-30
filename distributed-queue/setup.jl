import Pkg

const MANIFEST_PATH = joinpath(@__DIR__, "Manifest.toml")
const JULIA_VERSION_PATTERN = r"(?m)^julia_version\s*=\s*\"([^\"]+)\""

function manifest_julia_version()
    manifest = read(MANIFEST_PATH, String)
    match_result = match(JULIA_VERSION_PATTERN, manifest)
    match_result === nothing && error("Could not find julia_version in $(MANIFEST_PATH).")
    return VersionNumber(match_result.captures[1])
end

required_julia = manifest_julia_version()
if VERSION != required_julia
    error(
        "distributed-queue requires Julia $(required_julia), matching Manifest.toml; " *
        "current Julia is $(VERSION). Install Julia $(required_julia) or regenerate Manifest.toml with this Julia version."
    )
end

Pkg.activate(@__DIR__)
Pkg.instantiate()

println("Julia worker environment is ready with Julia $(VERSION). Package versions are pinned by Manifest.toml.")
