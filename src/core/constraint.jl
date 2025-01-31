using JuMP

function constraint_switching_binaries(pm::_PM.AbstractPowerModel, n::Int, i)
    if n != 1
        n_1 = n - 1
        sw_status_1 = _PM.var(pm, n_1, :z_switch, i)
        sw_status = _PM.var(pm, n, :z_switch, i)

        JuMP.@constraint(pm.model, sw_status_1 == sw_status)
    end 
end

function constraint_switching_binaries_hour(pm::_PM.AbstractPowerModel, n::Int, i)
    #hour = _PM.ref(pm, :hours)
    #scenario = _PM.ref(pm, :scenarios)
    hour_sw = _PM.ref(pm, n, :hour)
    scenario_sw = _PM.ref(pm, n, :scenario)
    if scenario_sw != 1
        n_1 = n - 1
        #scenario_sw_1 = _PM.ref(pm, n-1, :scenario)
        hour_sw_1 = _PM.ref(pm, n_1, :hour)
        if hour_sw == hour_sw_1
            sw_status_1 = _PM.var(pm, n_1, :z_switch, i)
            sw_status = _PM.var(pm, n, :z_switch, i)
            JuMP.@constraint(pm.model, sw_status_1 == sw_status)
        end
    end 
end

