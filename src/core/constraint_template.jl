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

function constraint_equalling_all_binaries(pm::_PM.AbstractPowerModel, i::Int; nw::Int=_PM.nw_id_default)
    constraint_equalling_all_binaries(pm, nw, i)
end

function constraint_sum_of_switching_actions(pm::_PM.AbstractPowerModel)     
    hours = pm.ref[:it][_PM.pm_it_sym][:hours]
    scenarios = pm.ref[:it][_PM.pm_it_sym][:scenarios]
    total_switching_actions = pm.ref[:it][_PM.pm_it_sym][:total_switching_actions]
    constraint_sum_of_switching_actions(pm, hours, scenarios, total_switching_actions)
end