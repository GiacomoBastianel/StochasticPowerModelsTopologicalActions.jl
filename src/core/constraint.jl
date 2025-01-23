using JuMP

function constraint_switching_binaries(pm::_PM.AbstractPowerModel, n::Int, i)
    if n != 1
        n_1 = n - 1
        sw_status_1 = _PM.var(pm, n_1, :z_switch, i)
        sw_status = _PM.var(pm, n, :z_switch, i)

        JuMP.@constraint(pm.model, sw_status_1 == sw_status)
    end 
end

