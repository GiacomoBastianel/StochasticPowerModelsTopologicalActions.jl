
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

function constraint_equalling_all_binaries(pm::_PM.AbstractPowerModel, n::Int, i)
    if n != 1
        n_1 = n - 1
        sw_status_1 = _PM.var(pm, n_1, :z_switch, i)
        sw_status = _PM.var(pm, n, :z_switch, i)
        JuMP.@constraint(pm.model, sw_status_1 == sw_status)
    end 
end


function constraint_limit_switching_actions(pm::_PM.AbstractPowerModel, hours, scenarios, limit_actions)     
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

    JuMP.@constraint(pm.model, 
    limit_actions <= sum(_PM.var(pm, n, :z_switch, sw_id) for (sw_id, n) in ac_ZIL)
    )
end

function constraint_limit_number_of_switching_actions(pm::_PM.AbstractPowerModel, hours, scenarios)     
    scenario_idx = 1 # calling the first scenario
    first_hours = []
    for hour in 1:hours
        push!(first_hours,(hour - 1)*scenarios + scenario_idx)
    end
    
    for hour in first_hours
        if hour != 1
            n = hour
            n_1 = n - 1
            for (sw_id,sw) in _PM.ref(pm,hour,:switch)
                if !haskey(sw,"auxiliary")            
                    sw_status_1 = _PM.var(pm, n_1, :z_switch, sw_id)
                    sw_status = _PM.var(pm, n, :z_switch, sw_id)
                    switch_action = _PM.var(pm, n, :switch_action, sw_id)
                
                    JuMP.@constraint(pm.model, sw_status_1 - sw_status <= switch_action)
                    JuMP.@constraint(pm.model, sw_status - sw_status_1 <= switch_action)
                end
            end
        end
    end 
end

function constraint_sum_of_switching_actions(pm::_PM.AbstractPowerModel, hours, scenarios, total_switching_actions)     
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

    JuMP.@constraint(pm.model, 
    sum(_PM.var(pm, n, :switch_action, sw_id) for (sw_id, n) in ac_ZIL) <= total_switching_actions
    )
end


#=
function constraint_maximum_switching_actions(pm::_PM.AbstractPowerModel, hours, scenarios, switching_actions) 
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

    JuMP.@constraint(pm.model, 
        sum(_PM.var(pm, n, :switch_action, sw_id) for (sw_id, n) in ac_ZIL) <= switching_actions
    )
end
=#



function constraint_limit_switching_actions_single_switches(pm::_PM.AbstractPowerModel, hours, scenarios)     
    scenario_idx = 1 # calling the first scenario
    first_hours = []
    for hour in 1:hours
        push!(first_hours,(hour - 1)*scenarios + scenario_idx)
    end

    for (sw_id,sw) in _PM.ref(pm,1,:switch)
        ac_ZIL = []
        if !haskey(sw, "auxiliary")
            for hour in first_hours
                push!(ac_ZIL,(sw_id,hour))
            end
            JuMP.@constraint(pm.model, 
            sw["maximum_actions"] <= sum(_PM.var(pm, n, :z_switch, sw_id) for (sw_id, n) in ac_ZIL))    
        end        
    end
end
