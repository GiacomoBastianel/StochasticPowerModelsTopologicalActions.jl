
"""
# Arguments
- `data`: a multinetwork data dictionary;
- `number_of_periods = dim_length(data)`;
- `loadprofile = ones(number_of_periods,length(data["load"]))`;
- `genprofile = ones(number_of_periods,length(data["gen"])))`.
"""
# This to be adaptep probably
function make_time_series(data::Dict{String,Any}, number_of_periods::Int = dim_length(data); loadprofile = 0.5*ones(number_of_periods,length(data["load"])), genprofile = ones(number_of_periods,length(data["gen"])))
    if size(loadprofile) ≠ (number_of_periods, length(data["load"]))
        right_size = (number_of_periods, length(data["load"]))
        Memento.error(_LOGGER, "Size of loadprofile matrix must be $right_size, found $(size(loadprofile)) instead.")
    end
    if size(genprofile) ≠ (number_of_periods, length(data["gen"]))
        right_size = (number_of_periods, length(data["gen"]))
        Memento.error(_LOGGER, "Size of genprofile matrix must be $right_size, found $(size(genprofile)) instead.")
    end
    return Dict{String,Any}(
        "load" => Dict{String,Any}(l => Dict("pd" => load["pd"] .* loadprofile[:, parse(Int, l)]) for (l,load) in data["load"]),
        "gen" => Dict{String,Any}(g => Dict("pmax" => gen["pmax"] .* genprofile[:, parse(Int, g)]) for (g,gen) in data["gen"]),
    )
end

function create_profile_data(number_of_periods, data, loadprofile = 0.5*ones(length(data["load"]),number_of_periods), genprofile = ones(length(data["gen"]),number_of_periods))
    make_time_series(data, number_of_periods; loadprofile = permutedims(loadprofile), genprofile = permutedims(genprofile))
end

function create_stochastic_profile_data!(data)

    hours = _FP.dim_length(data, :hour)
    scenarios = _FP.dim_length(data, :scenario)

    genprofile = ones(length(data["gen"]),   hours*scenarios)
    loadprofile = ones(length(data["load"]), hours*scenarios)

    return data, loadprofile, genprofile
end