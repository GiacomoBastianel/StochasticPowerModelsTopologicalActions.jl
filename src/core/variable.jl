function variable_switch_action(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default, report::Bool=true)
    bus_couplers = []
    for hour in 1:1
        if haskey(_PM.ref(pm,hour),:switch)
            for (sw_id,sw) in _PM.ref(pm,hour,:switch)
                if !haskey(sw, "auxiliary")
                    push!(bus_couplers,sw_id)
                end
            end
        end
    end
    println(bus_couplers)

    switch_action = _PM.var(pm, nw)[:switch_action] = JuMP.@variable(pm.model,
    [i in bus_couplers], base_name="$(nw)_switch_action",
    lower_bound = 0.0,
    upper_bound = 1.0,
    start = _PM.comp_start_value(_PM.ref(pm, nw, :switch, i), "switch_action", 0.0)
    )
    report # && _PM.sol_component_value(pm, nw, :switch, :status, _PM.ids(pm, nw, :switch), z_switch)
end

function variable_switch_action_all_switches(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default, report::Bool=true)
    bus_couplers = []
    for hour in 1:1
        if haskey(_PM.ref(pm,hour),:switch)
            for (sw_id,sw) in _PM.ref(pm,hour,:switch)
                #if !haskey(sw, "auxiliary")
                    push!(bus_couplers,sw_id)
                #end
            end
        end
    end

    switch_action = _PM.var(pm, nw)[:switch_action] = JuMP.@variable(pm.model,
    [i in bus_couplers], base_name="$(nw)_switch_action",
    lower_bound = 0.0,
    upper_bound = 1.0,
    start = _PM.comp_start_value(_PM.ref(pm, nw, :switch, i), "switch_action", 0.0)
    )
    report # && _PM.sol_component_value(pm, nw, :switch, :status, _PM.ids(pm, nw, :switch), z_switch)
end

function variable_switch_action_old(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default, report::Bool=true)
    switch_action = _PM.var(pm, nw)[:switch_action] = JuMP.@variable(pm.model,
    [i in _PM.ids(pm, nw, :switch)], base_name="$(nw)_switch_action",
    lower_bound = 0.0,
    upper_bound = 1.0,
    start = _PM.comp_start_value(_PM.ref(pm, nw, :switch, i), "switch_action", 0.0)
    )
    report # && _PM.sol_component_value(pm, nw, :switch, :status, _PM.ids(pm, nw, :switch), z_switch)
end

#=

    switch_action = _PM.var(pm, nw)[:switch_action] = JuMP.@variable(pm.model,
        [i in _PM.ids(pm, nw, :switch)], base_name="$(nw)_switch_action",
        lower_bound = 0.0,
        upper_bound = 1.0,
        start = _PM.comp_start_value(_PM.ref(pm, nw, :switch, i), "switch_action", 0.0)
    )
end
report && _PM.sol_component_value(pm, nw, :switch, :status, _PM.ids(pm, nw, :switch), switch_action)
=#


"generates variables for both `active` and `reactive` generation"
function variable_gen_redispatch_upward(pm::_PM.AbstractPowerModel; kwargs...)
    variable_gen_redispatch_upward_real(pm; kwargs...)
    variable_gen_redispatch_upward_imaginary(pm; kwargs...)
end

function variable_gen_redispatch_downward(pm::_PM.AbstractPowerModel; kwargs...)
    variable_gen_redispatch_downward_real(pm; kwargs...)
    variable_gen_redispatch_downward_imaginary(pm; kwargs...)
end


"variable: `pg[j]` for `j` in `gen`"
function variable_gen_redispatch_upward_real(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default, bounded::Bool=true, report::Bool=true)
    pg_up = _PM.var(pm, nw)[:pg_up] = JuMP.@variable(pm.model,
        [i in _PM.ids(pm, nw, :gen)], base_name="$(nw)_pg_up",
        start = _PM.comp_start_value(_PM.ref(pm, nw, :gen, i), "pg_start")
    )

    if bounded
        for (i, gen) in _PM.ref(pm, nw, :gen)
            JuMP.set_lower_bound(pg_up[i], 0.0)
            JuMP.set_upper_bound(pg_up[i], gen["pmax"])
        end
    end

    report && _PM.sol_component_value(pm, nw, :gen, :pg_up, _PM.ids(pm, nw, :gen), pg_up)
end

"variable: `qq[j]` for `j` in `gen`"
function variable_gen_redispatch_upward_imaginary(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default, bounded::Bool=true, report::Bool=true)
    qg_up = _PM.var(pm, nw)[:qg_up] = JuMP.@variable(pm.model,
        [i in _PM.ids(pm, nw, :gen)], base_name="$(nw)_qg_up",
        start = _PM.comp_start_value(_PM.ref(pm, nw, :gen, i), "qg_start")
    )

    if bounded
        for (i, gen) in _PM.ref(pm, nw, :gen)
            JuMP.set_lower_bound(qg_up[i], gen["qmin"])
            JuMP.set_upper_bound(qg_up[i], gen["qmax"])
        end
    end

    report && _PM.sol_component_value(pm, nw, :gen, :qg_up, _PM.ids(pm, nw, :gen), qg_up)
end

function variable_gen_redispatch_downward_real(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default, bounded::Bool=true, report::Bool=true)
    pg_down = _PM.var(pm, nw)[:pg_down] = JuMP.@variable(pm.model,
        [i in _PM.ids(pm, nw, :gen)], base_name="$(nw)_pg_down",
        start = _PM.comp_start_value(_PM.ref(pm, nw, :gen, i), "pg_start")
    )

    if bounded
        for (i, gen) in _PM.ref(pm, nw, :gen)
            JuMP.set_lower_bound(pg_down[i], 0.0)
            JuMP.set_upper_bound(pg_down[i], gen["pmax"])
        end
    end

    report && _PM.sol_component_value(pm, nw, :gen, :pg_down, _PM.ids(pm, nw, :gen), pg_down)
end

"variable: `qq[j]` for `j` in `gen`"
function variable_gen_redispatch_downward_imaginary(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default, bounded::Bool=true, report::Bool=true)
    qg_down = _PM.var(pm, nw)[:qg_down] = JuMP.@variable(pm.model,
        [i in _PM.ids(pm, nw, :gen)], base_name="$(nw)_qg_down",
        start = _PM.comp_start_value(_PM.ref(pm, nw, :gen, i), "qg_start")
    )

    if bounded
        for (i, gen) in _PM.ref(pm, nw, :gen)
            JuMP.set_lower_bound(qg_down[i], gen["qmin"])
            JuMP.set_upper_bound(qg_down[i], gen["qmax"])
        end
    end

    report && _PM.sol_component_value(pm, nw, :gen, :qg_down, _PM.ids(pm, nw, :gen), qg_down)
end
