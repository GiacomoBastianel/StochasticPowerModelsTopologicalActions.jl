function constraint_switching_binaries(pm::_PM.AbstractPowerModel, i::Int; nw::Int=_PM.nw_id_default)
    constraint_switching_binaries(pm, nw, i)
end

function constraint_switching_binaries_hour(pm::_PM.AbstractPowerModel, i::Int; nw::Int=_PM.nw_id_default)
    constraint_switching_binaries_hour(pm, nw, i)
end


function constraint_limit_switching_actions(pm::_PM.AbstractPowerModel)    
    hours = pm.ref[:it][_PM.pm_it_sym][:hours]
    scenarios = pm.ref[:it][_PM.pm_it_sym][:scenarios]
    limit_actions = pm.ref[:it][_PM.pm_it_sym][:limit_actions]
    constraint_limit_switching_actions(pm, hours, scenarios, limit_actions)
end

function constraint_limit_switching_actions_single_switches(pm::_PM.AbstractPowerModel)    
    hours = pm.ref[:it][_PM.pm_it_sym][:hours]
    scenarios = pm.ref[:it][_PM.pm_it_sym][:scenarios]
    constraint_limit_switching_actions_single_switches(pm, hours, scenarios)
end

function constraint_maximum_switching_actions(pm::_PM.AbstractPowerModel)    
    hours = pm.ref[:it][_PM.pm_it_sym][:hours]
    scenarios = pm.ref[:it][_PM.pm_it_sym][:scenarios]
    switching_actions = pm.ref[:it][_PM.pm_it_sym][:switching_actions]
    constraint_maximum_switching_actions(pm, hours, scenarios, switching_actions)
end

function constraint_limit_number_of_switching_actions(pm::_PM.AbstractPowerModel)    
    hours = pm.ref[:it][_PM.pm_it_sym][:hours]
    scenarios = pm.ref[:it][_PM.pm_it_sym][:scenarios]
    constraint_limit_number_of_switching_actions(pm, hours, scenarios)
end

function constraint_limit_number_of_switching_actions_all_switches(pm::_PM.AbstractPowerModel)    
    hours = pm.ref[:it][_PM.pm_it_sym][:hours]
    scenarios = pm.ref[:it][_PM.pm_it_sym][:scenarios]
    constraint_limit_number_of_switching_actions_all_switches(pm, hours, scenarios)
end

function constraint_limit_number_of_switching_actions_all_switches_stochastic(pm::_PM.AbstractPowerModel)    
    hours = pm.ref[:it][_PM.pm_it_sym][:hours]
    scenarios = pm.ref[:it][_PM.pm_it_sym][:scenarios]
    constraint_limit_number_of_switching_actions_all_switches_stochastic(pm, hours, scenarios)
end

function constraint_equalling_all_binaries(pm::_PM.AbstractPowerModel, i::Int; nw::Int=_PM.nw_id_default)
    constraint_equalling_all_binaries(pm, nw, i)
end

function constraint_sum_of_switching_actions(pm::_PM.AbstractPowerModel)     
    hours = pm.ref[:it][_PM.pm_it_sym][:hours]
    scenarios = pm.ref[:it][_PM.pm_it_sym][:scenarios]
    total_switching_actions = pm.ref[:it][_PM.pm_it_sym][:total_switching_actions]
    constraint_sum_of_switching_actions(pm, hours, scenarios, total_switching_actions)
end

function constraint_sum_of_switching_actions_all_switches(pm::_PM.AbstractPowerModel)     
    hours = pm.ref[:it][_PM.pm_it_sym][:hours]
    scenarios = pm.ref[:it][_PM.pm_it_sym][:scenarios]
    total_switching_actions = pm.ref[:it][_PM.pm_it_sym][:total_switching_actions]
    constraint_sum_of_switching_actions_all_switches(pm, hours, scenarios, total_switching_actions)
end

function constraint_limit_switching_actions_all_switches(pm::_PM.AbstractPowerModel)    
    hours = pm.ref[:it][_PM.pm_it_sym][:hours]
    scenarios = pm.ref[:it][_PM.pm_it_sym][:scenarios]
    constraint_limit_switching_actions_all_switches(pm, hours, scenarios)
end

function constraint_limit_switching_actions_all_switches_stochastic(pm::_PM.AbstractPowerModel, i::Int)    
    hours = pm.ref[:it][_PM.pm_it_sym][:hours]
    scenarios = pm.ref[:it][_PM.pm_it_sym][:scenarios]
    constraint_limit_switching_actions_all_switches_stochastic(pm, i, hours, scenarios)
end


function constraint_equalling_all_switching_actions_in_one_hour(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default)
    constraint_equalling_all_switching_actions_in_one_hour(pm, nw)
end

function constraint_equalling_all_switching_actions_in_one_hour_stochastic(pm::_PM.AbstractPowerModel, i::Int)
    hours = pm.ref[:it][_PM.pm_it_sym][:hours]
    scenarios = pm.ref[:it][_PM.pm_it_sym][:scenarios]
    constraint_equalling_all_switching_actions_in_one_hour_stochastic(pm, i, scenarios,hours)
end

function constraint_power_balance_ac_redispatch(pm::_PM.AbstractPowerModel, i::Int; nw::Int=_PM.nw_id_default)
    bus = _PM.ref(pm, nw, :bus, i)
    bus_arcs = _PM.ref(pm, nw, :bus_arcs, i)
    bus_arcs_dc = _PM.ref(pm, nw, :bus_arcs_dc, i)
    bus_gens = _PM.ref(pm, nw, :bus_gens, i)
    bus_convs_ac = _PM.ref(pm, nw, :bus_convs_ac, i)
    bus_loads = _PM.ref(pm, nw, :bus_loads, i)
    bus_shunts = _PM.ref(pm, nw, :bus_shunts, i)

    pd = Dict(k => _PM.ref(pm, nw, :load, k, "pd") for k in bus_loads)
    qd = Dict(k => _PM.ref(pm, nw, :load, k, "qd") for k in bus_loads)

    gs = Dict(k => _PM.ref(pm, nw, :shunt, k, "gs") for k in bus_shunts)
    bs = Dict(k => _PM.ref(pm, nw, :shunt, k, "bs") for k in bus_shunts)

    pg_start = Dict(k => _PM.ref(pm, nw, :gen, k, "pg_start") for k in bus_gens)
    qg_start = Dict(k => _PM.ref(pm, nw, :gen, k, "qg_start") for k in bus_gens)

    constraint_power_balance_ac_redispatch(pm, nw, i, bus_arcs, bus_arcs_dc, bus_gens, bus_convs_ac, bus_loads, bus_shunts, pd, qd, gs, bs, pg_start, qg_start)
end

function constraint_gen_redispatch(pm::_PM.AbstractPowerModel, i::Int; nw::Int=_PM.nw_id_default)
    pg_start = _PM.ref(pm, nw, :gen, i, "pg_start")
    qg_start = _PM.ref(pm, nw, :gen, i, "qg_start")

    pmax = _PM.ref(pm, nw, :gen, i, "pmax")
    qmax = _PM.ref(pm, nw, :gen, i, "qmax")

    constraint_gen_redispatch(pm, nw, i, pg_start, qg_start,pmax,qmax)
end