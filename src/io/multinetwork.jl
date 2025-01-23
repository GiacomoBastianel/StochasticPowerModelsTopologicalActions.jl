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
    number_of_nws::Int = length(dim(sn_data)[:li]),
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

"""
    make_multinetwork(sn_data; global_keys)

Generate a multinetwork data structure - having only one `nw` - from a single network.

# Arguments
- `sn_data`: single-network data structure to be replicated.
- `global_keys`: keys that are stored once per multinetwork (they are not repeated in each
  `nw`).
- `check_dim`: whether to check for `dim` in `sn_data`; default: `true`.
"""
function make_multinetwork(
        sn_data::Dict{String,Any};
        global_keys = ["dim","name","per_unit","source_type","source_version"],
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
    template_nw = _make_template_nw(sn_data, global_keys)
    mn_data["nw"]["1"] = copy(template_nw)

    return mn_data
end

# Build multinetwork data structure: for each network, replicate the template and replace with data from time_series
function _add_time_series!(mn_data, sn_data, global_keys, time_series, number_of_nws, offset; share_data)
    template_nw = _make_template_nw(sn_data, global_keys)
    for time_series_idx in 1:number_of_nws
        n = time_series_idx + offset
        mn_data["nw"]["$n"] = _build_nw(template_nw, time_series, time_series_idx; share_data)
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