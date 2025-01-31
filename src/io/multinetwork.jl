"""
    make_multinetwork(sn_data, time_series; <keyword arguments>)

Generate a multinetwork data structure from a single network and a time series.

# Arguments
- `sn_data`: single-network data structure to be replicated.
- `time_series`: data structure containing the time series.
- `global_keys`: keys that are stored once per multinetwork (they are not repeated in each
  `nw`).
- `number_of_nws`: number of networks to be created from `sn_data` and `time_series`;
  default: read from `dim`.
- `nw_id_offset`: optional value to be added to `time_series` ids to shift `nw` ids in
  multinetwork data structure; default: read from `dim`.
- `share_data`: whether constant data is shared across networks (default, faster) or
  duplicated (uses more memory, but ensures networks are independent; useful if further
  transformations will be applied).
- `check_dim`: whether to check for `dim` in `sn_data`; default: `true`.
"""
function make_multinetwork(
    sn_data::Dict{String,Any},
    time_series::Dict{String,Any};
    global_keys = ["dim","multinetwork","name","per_unit","source_type","source_version"],
    number_of_nws::Int = length(_FP.dim(sn_data)[:li]),
    nw_id_offset::Int = _FP.dim(sn_data)[:offset],
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
add_hour_scenario(mn_data)

return mn_data
end

"""
    make_multinetwork(sn_data; global_keys)

Generate a multinetwork data structure - having only one `nw` - from a single network.

# Arguments
- `sn_data`: single-network data structure to be replicated.
- `global_keys`: keys that are stored once per multinetwork (they are not repeated in each
  `nw`).
- `check_dim`: whether to check for `dim` in `sn_data`; default: `true`.
"""
function make_multinetwork_first(
        sn_data::Dict{String,Any},n_scenarios,n_hours;
        global_keys = ["dim","name","per_unit","source_type","source_version"],
        check_dim::Bool = true,
    )

    #if _IM.ismultinetwork(sn_data)
    #    Memento.error(_LOGGER, "`sn_data` argument must be a single network.")
    #end
    #if check_dim && !haskey(sn_data, "dim")
    #    Memento.error(_LOGGER, "Missing `dim` dict in `sn_data` argument. The function `add_dimension!` must be called before `make_multinetwork`.")
    #end

    mn_data = Dict{String,Any}("nw"=>Dict{String,Any}())
    _add_mn_global_values!(mn_data, sn_data, global_keys)
    #template_nw = _make_template_nw(sn_data, global_keys)
    for hour in 1:n_hours
        for scenario_idx in 1:n_scenarios
            n = (hour - 1) + scenario_idx
            mn_data["nw"]["$n"] = deepcopy(sn_data)#_build_nw(template_nw, sn_data, time_series_idx; share_data = true)
        end
    end
    return mn_data
end

# Build multinetwork data structure: for each network, replicate the template and replace with data from time_series
function _add_time_series!(mn_data, sn_data, global_keys, time_series, number_of_nws, offset; share_data)
    template_nw = _make_template_nw(sn_data, global_keys)
    for time_series_idx in 1:number_of_nws
        n = time_series_idx + offset
        mn_data["nw"]["$n"] = _build_nw(template_nw, time_series, time_series_idx; share_data)
        #add_hour_scenario(mn_data["nw"]["$n"])
    end
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

function _make_template_nw(sn_data, global_keys)
    template_nw = copy(sn_data)
    for k in global_keys
        delete!(template_nw, k)
    end
    return template_nw
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



function make_multinetwork_time_series(
    sn_data::Dict{String,Any},n_scenarios,n_hours,time_series::Dict{String,Any};
    global_keys = ["dim","name","per_unit","source_type","source_version"],
    check_dim::Bool = true,
    )

    #if _IM.ismultinetwork(sn_data)
    #    Memento.error(_LOGGER, "`sn_data` argument must be a single network.")
    #end
    #if check_dim && !haskey(sn_data, "dim")
    #    Memento.error(_LOGGER, "Missing `dim` dict in `sn_data` argument. The function `add_dimension!` must be called before `make_multinetwork`.")
    #end

    mn_data = Dict{String,Any}("nw"=>Dict{String,Any}())
    _FP._add_mn_global_values!(mn_data, sn_data, global_keys)
    #template_nw = _make_template_nw(sn_data, global_keys)
    for hour in 1:n_hours
        for scenario_idx in 1:n_scenarios
            n = (hour - 1)*n_scenarios + scenario_idx
            mn_data["nw"]["$n"] = deepcopy(sn_data)#_build_nw(template_nw, sn_data, time_series_idx; share_data = true)
            delete!(mn_data["nw"]["$n"],"dim")
            add_hour_scenario_probability(mn_data,hour,scenario_idx,n,time_series)
            for (g_id,g) in mn_data["nw"]["$n"]["gen"]
                mn_data["nw"]["$n"]["gen"][g_id]["pmax"] = time_series["gen"][g_id]["$hour"]["$scenario_idx"]["pmax_hourly"]
            end
            for (l_id,l) in mn_data["nw"]["$n"]["load"]
                mn_data["nw"]["$n"]["load"][l_id]["pd"] = time_series["load"][l_id]["$hour"]["$scenario_idx"]["pd"]
            end
        end
    end
    return mn_data
end

function add_hour_scenario_probability(data,hour,scenario,index,time_series)
    data["nw"]["$index"]["hour"] = hour
    data["nw"]["$index"]["scenario"] = scenario
    data["nw"]["$index"]["hour_scenario_index"] = [hour,scenario,index]
    data["nw"]["$index"]["probability"] = time_series["scenario_probability"]["$index"]
end

function add_hour_scenario_data(data,hour,scenario)
    data["hours"] = hour
    data["scenarios"] = scenario
end
