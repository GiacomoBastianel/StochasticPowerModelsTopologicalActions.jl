function constraint_switching_binaries(pm::_PM.AbstractPowerModel, i::Int; nw::Int=_PM.nw_id_default)
    constraint_switching_binaries(pm, nw, i)
end

function constraint_switching_binaries_hour(pm::_PM.AbstractPowerModel, i::Int; nw::Int=_PM.nw_id_default)
    constraint_switching_binaries_hour(pm, nw, i)
end


function constraint_limit_switching_actions(pm::_PM.AbstractPowerModel)    
    hours = pm.ref[:it][_PM.pm_it_sym][:hours]
    scenarios = pm.ref[:it][_PM.pm_it_sym][:scenarios]
    constraint_limit_switching_actions(pm, hours, scenarios)
end

