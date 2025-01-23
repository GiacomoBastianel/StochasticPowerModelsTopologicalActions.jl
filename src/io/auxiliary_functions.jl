function make_multinetwork(
    sn_data::Dict{String,Any},
    time_series::Dict{String,Any};
    global_keys = ["dim","multinetwork","name","per_unit","source_type","source_version"],
    number_of_nws::Int = length(dim(sn_data)[:li]), # scenarions
    nw_id_offset::Int = dim(sn_data)[:offset],
    share_data::Bool = true,
    check_dim::Bool = true
    )

    if _IM.ismultinetwork(sn_data)
        Memento.error(_LOGGER, "`sn_data` argument must be a single network.")
    end
    if check_dim && !haskey(sn_data, "dim")
        Memento.error(_LOGGER, "Missing `dim` dict in `sn_data` argument. The function `add_dimension!` must be called before `make_multinetwork`.")
    end

    mn_data = Dict{String,Any}("nw"=>Dict{String,Any}())
    _add_mn_global_values!(mn_data, sn_data, global_keys)
    _add_time_series!(mn_data, sn_data, global_keys, time_series, number_of_nws, nw_id_offset; share_data)

return mn_data
end

# Copy global values from sn_data to mn_data handling special cases
function _add_mn_global_values!(mn_data, sn_data, global_keys)

    # Insert global values into mn_data by copying from sn_data
    for k in global_keys
        if haskey(sn_data, k)
            mn_data[k] = sn_data[k]
        end
    end

    # Special cases are handled below
    mn_data["multinetwork"] = true
    get!(mn_data, "name", "multinetwork")
end

# Make a copy of `data` and remove global keys
function _make_template_nw(sn_data, global_keys)
    template_nw = copy(sn_data)
    for k in global_keys
        delete!(template_nw, k)
    end
    return template_nw
end

# Build multinetwork data structure: for each network, replicate the template and replace with data from time_series
function _add_time_series!(mn_data, sn_data, global_keys, time_series, number_of_nws, offset; share_data)
    template_nw = _make_template_nw(sn_data, global_keys)
    for time_series_idx in 1:number_of_nws
        n = time_series_idx + offset
        mn_data["nw"]["$n"] = _build_nw(template_nw, time_series, time_series_idx; share_data)
    end
end

# Build the nw by copying the template and substituting data from time_series.
function _build_nw(template_nw, time_series, idx; share_data)
    copy_function = share_data ? copy : deepcopy
    nw = copy_function(template_nw)
    for (key, element) in time_series
        if haskey(nw, key)
            nw[key] = copy_function(template_nw[key])
            for (l, element) in time_series[key]
                if haskey(nw[key], l)
                    nw[key][l] = copy_function(template_nw[key][l])
                    for (m, property) in time_series[key][l]
                        nw[key][l][m] = property[idx]
                    end
                else
                    Memento.warn(_LOGGER, "Key $l not found, will be ignored.")
                end
            end
        else
            Memento.warn(_LOGGER, "Key $key not found, will be ignored.")
        end
    end
    return nw
end

"""
# Arguments
- `data`: a multinetwork data dictionary;
- `number_of_periods = dim_length(data)`;
- `loadprofile = ones(number_of_periods,length(data["load"]))`;
- `genprofile = ones(number_of_periods,length(data["gen"])))`.
"""
function make_time_series(data::Dict{String,Any}, number_of_periods::Int = dim_length(data); loadprofile = ones(number_of_periods,length(data["load"])), genprofile = ones(number_of_periods,length(data["gen"])))
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

function create_profile_data(number_of_periods, data, loadprofile = ones(length(data["load"]),number_of_periods), genprofile = ones(length(data["gen"]),number_of_periods))
    make_time_series(data, number_of_periods; loadprofile = permutedims(loadprofile), genprofile = permutedims(genprofile))
end

function create_stochastic_profile_data!(data)

    hours = _FP.dim_length(data, :hour)
    scenarios = _FP.dim_length(data, :scenario)

    genprofile = ones(length(data["gen"]),   hours*scenarios)
    loadprofile = ones(length(data["load"]), hours*scenarios)

    #=
    monte_carlo = get(_FP.dim_meta(data, :scenario), "mc", false)

    for (s, scnr) in _FP.dim_prop(data, :scenario)
        pv_sicily, pv_south_central, wind_sicily = read_res_data(s; mc = monte_carlo)
        demand_center_north_pu, demand_north_pu, demand_center_south_pu, demand_south_pu, demand_sardinia_pu = read_demand_data(s; mc = monte_carlo)

        start_idx = (s-1) * hours
        if monte_carlo == false
            for h in 1 : hours
                h_idx = scnr["start"] + ((h-1) * 3600000)
                genprofile[4, start_idx + h] = pv_south_central["data"]["$h_idx"]["electricity"]
                genprofile[5, start_idx + h] = pv_sicily["data"]["$h_idx"]["electricity"]
                genprofile[6, start_idx + h] = wind_sicily["data"]["$h_idx"]["electricity"]
            end
        else
            genprofile[4, start_idx + 1 : start_idx + hours] = pv_south_central[1: hours]
            genprofile[5, start_idx + 1 : start_idx + hours] = pv_sicily[1: hours]
            genprofile[6, start_idx + 1 : start_idx + hours] = wind_sicily[1: hours]
        end
        loadprofile[:, start_idx + 1 : start_idx + hours] = [demand_center_north_pu'; demand_north_pu'; demand_center_south_pu'; demand_south_pu'; demand_sardinia_pu'][:, 1: hours]
        # loadprofile[:, start_idx + 1 : start_idx + number_of_hours] = repeat([demand_center_north_pu'; demand_north_pu'; demand_center_south_pu'; demand_south_pu'; demand_sardinia_pu'][:, 1],1,number_of_hours)
    end
    # Add bus locations to data dictionary
    data["bus"]["1"]["lat"] = 43.4894; data["bus"]["1"]["lon"] = 11.7946; # Italy central north
    data["bus"]["2"]["lat"] = 45.3411; data["bus"]["2"]["lon"] =  9.9489; # Italy north
    data["bus"]["3"]["lat"] = 41.8218; data["bus"]["3"]["lon"] = 13.8302; # Italy central south
    data["bus"]["4"]["lat"] = 40.5228; data["bus"]["4"]["lon"] = 16.2155; # Italy south
    data["bus"]["5"]["lat"] = 40.1717; data["bus"]["5"]["lon"] =  9.0738; # Sardinia
    data["bus"]["6"]["lat"] = 37.4844; data["bus"]["6"]["lon"] = 14.1568; # Sicily
    =#
    # Return info
    return data, loadprofile, genprofile
end