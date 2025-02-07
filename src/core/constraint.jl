
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

#=
function constraint_limit_switching_actions(pm::_PM.AbstractPowerModel, n::Int, i, ac_ZIL)
    if !haskey(switch, "auxiliary")           
        ZIL = _PM.var(pm, n, :z_switch, i)
    end
    JuMP.@constraint(pm.model,sum(ZIL_ac[i] for (i,n) in ac_ZIL) <= 1)ˆ
end

nw_list = collect(keys(pm.ref[:nw]))  # List of network indices
=#


function constraint_limit_switching_actions(pm::_PM.AbstractPowerModel, hours, scenarios)     
    
    scenario_idx = 1 # calling the first scenario
    first_hours = []
    for hour in 1:hours
        push!(first_hours,(hour - 1)*scenarios + scenario_idx)
    end
    ac_ZIL = []
    for hour in first_hours
        if haskey(_PM.ref(pm,hour),:switch)
            for (sw_id,sw) in _PM.ref(pm,hour,:switch)
                if !haskey(sw, "auxiliary")
                    push!(ac_ZIL,(sw_id,hour))
                end
            end
        end
    end
    for (i,n) in ac_ZIL
        println(i," ",n)
    end

    JuMP.@constraint(pm.model, 
    2 <= 
    sum(_PM.var(pm, n, :z_switch, sw_id) 
    for (sw_id, n) in ac_ZIL)
    )
end

#=
sum(
            sum( branch["construction_cost"]*var(pm, n, :branch_ne, i) for (i,branch) in nw_ref[:ne_branch] )
        for (n, nw_ref) in nws(pm))
            =#