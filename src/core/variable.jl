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