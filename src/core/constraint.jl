
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

function constraint_equalling_all_binaries_stochastic(pm::_PM.AbstractPowerModel, n::Int, i)
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

function constraint_limit_number_of_switching_actions_all_switches(pm::_PM.AbstractPowerModel, hours, scenarios)     
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
                #if !haskey(sw,"auxiliary")            
                    sw_status_1 = _PM.var(pm, n_1, :z_switch, sw_id)
                    sw_status = _PM.var(pm, n, :z_switch, sw_id)
                    switch_action = _PM.var(pm, n, :switch_action, sw_id)
                
                    JuMP.@constraint(pm.model, sw_status_1 - sw_status <= switch_action)
                    JuMP.@constraint(pm.model, sw_status - sw_status_1 <= switch_action)
                #end
            end
        end
    end 
end

function constraint_limit_number_of_switching_actions_all_switches_stochastic(pm::_PM.AbstractPowerModel, hours, scenarios)     
    scenario_idx = 1 # calling the first scenario
    first_hours = []
    for hour in 1:hours
        push!(first_hours,(hour - 1)*scenarios + scenario_idx)
    end
    
    count_ = 0
    for hour in first_hours
        count_ += 1
        if count_ >= 2
            n = first_hours[count_]
            n_1 = first_hours[count_ - 1]
            for (sw_id,sw) in _PM.ref(pm,hour,:switch)
                #if !haskey(sw,"auxiliary")            
                    sw_status_1 = _PM.var(pm, n_1, :z_switch, sw_id)
                    sw_status = _PM.var(pm, n, :z_switch, sw_id)
                    switch_action = _PM.var(pm, n, :switch_action, sw_id)
                
                    JuMP.@constraint(pm.model, sw_status_1 - sw_status <= switch_action)
                    JuMP.@constraint(pm.model, sw_status - sw_status_1 <= switch_action)
                #end
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

function constraint_sum_of_switching_actions_all_switches(pm::_PM.AbstractPowerModel, hours, scenarios, total_switching_actions)     
    scenario_idx = 1 # calling the first scenario
    #first_hours = []
    #for hour in 1:hours
    #    push!(first_hours,(hour - 1)*scenarios + scenario_idx)
    #end
    
    ac_ZIL = []
    for hour in 1:(length(hours)*length(scenarios))
        if haskey(_PM.ref(pm,hour),:switch)
            for (sw_id,sw) in _PM.ref(pm,hour,:switch)
                #if !haskey(sw, "auxiliary")
                    push!(ac_ZIL,(sw_id,hour))
                #end
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

function constraint_limit_switching_actions_all_switches(pm::_PM.AbstractPowerModel, hours, scenarios)     
    scenario_idx = 1 # calling the first scenario
    first_hours = []
    for hour in 1:hours
        push!(first_hours,(hour - 1)*scenarios + scenario_idx)
    end

    for (sw_id,sw) in _PM.ref(pm,1,:switch)
        ac_ZIL = []
        #if !haskey(sw, "auxiliary")
            for hour in first_hours
                push!(ac_ZIL,(sw_id,hour))
            end
            JuMP.@constraint(pm.model, 
            sum(_PM.var(pm, n, :switch_action, sw_id) for (sw_id, n) in ac_ZIL) <= sw["maximum_actions"])    
        #end        
    end
end

function constraint_limit_switching_actions_all_switches_stochastic(pm::_PM.AbstractPowerModel, i, hours, scenarios)     
    scenario_idx = 1 # calling the first scenario
    first_hours = []
    for hour in 1:hours
        push!(first_hours,(hour - 1)*scenarios + scenario_idx)
    end

    JuMP.@constraint(pm.model, 
        sum(_PM.var(pm, n, :switch_action, i) for n in first_hours) <= _PM.ref(pm,1,:switch,1,"maximum_actions"))    
end


function constraint_equalling_all_switching_actions_in_one_hour(pm::_PM.AbstractPowerModel, n::Int)
    switches = []
    count_ = 0
    for (sw_id,sw) in _PM.ref(pm,1,:switch)
        count_ += 1
        push!(switches,sw_id)
        if count_ >= 2
            last_switch = _PM.var(pm, n, :switch_action, switches[count_])
            second_last_switch = _PM.var(pm, n, :switch_action, switches[count_ - 1])
            JuMP.@constraint(pm.model, last_switch == second_last_switch
            )    
        end        
    end
end

function constraint_equalling_all_switching_actions_in_one_hour_stochastic(pm::_PM.AbstractPowerModel, i, scenarios, hours)
    first_hours = []
    scenario_idx = 1
    for hour in 1:hours
        push!(first_hours,(hour - 1)*scenarios + scenario_idx)
    end

    for h in first_hours
        count_ = 0
        for s in 1:scenarios
            nw = h + s - 1
            count_ += 1
            if count_ >= 2
                sw_n = _PM.var(pm, nw, :switch_action, i)
                nw_1 = nw - 1
                sw_n_1 = _PM.var(pm, nw_1, :switch_action, i)
                JuMP.@constraint(pm.model, sw_n == sw_n_1
                )
            end
        end
    end
end

function constraint_power_balance_ac_redispatch(pm::_PM.AbstractPowerModel, n::Int,  i::Int, bus_arcs, bus_arcs_dc, bus_gens, bus_convs_ac, bus_loads, bus_shunts, pd, qd, gs, bs, pg_start, qg_start)
    vm = _PM.var(pm, n,  :vm, i)
    p = _PM.var(pm, n,  :p)
    q = _PM.var(pm, n,  :q)
    pg_up = _PM.var(pm, n,  :pg_up)
    qg_up = _PM.var(pm, n,  :qg_up)
    pg_down = _PM.var(pm, n,  :pg_down)
    qg_down = _PM.var(pm, n,  :qg_down)
    pconv_grid_ac = _PM.var(pm, n,  :pconv_tf_fr)
    qconv_grid_ac = _PM.var(pm, n,  :qconv_tf_fr)

    cstr_p = JuMP.@constraint(pm.model, sum(p[a] for a in bus_arcs) + sum(pconv_grid_ac[c] for c in bus_convs_ac)  == sum(pg_start[g] for g in bus_gens) + sum(pg_up[g] for g in bus_gens) - sum(pg_down[g] for g in bus_gens) - sum(pd[d] for d in bus_loads) - sum(gs[s] for s in bus_shunts)*vm^2)
    cstr_q = JuMP.@constraint(pm.model, sum(q[a] for a in bus_arcs) + sum(qconv_grid_ac[c] for c in bus_convs_ac)  == sum(qg_start[g] for g in bus_gens) + sum(qg_up[g] for g in bus_gens) - sum(qg_down[g] for g in bus_gens) - sum(qd[d] for d in bus_loads) + sum(bs[s] for s in bus_shunts)*vm^2)
end

function constraint_gen_redispatch(pm::_PM.AbstractPowerModel, n::Int,  i::Int, pg_start, qg_start,pmax,qmax)
    pg_up = _PM.var(pm, n,  :pg_up, i)
    qg_up = _PM.var(pm, n,  :qg_up, i)
    pg_down = _PM.var(pm, n,  :pg_down, i)
    qg_down = _PM.var(pm, n,  :qg_down, i)

    JuMP.@constraint(pm.model, 
        pg_start + pg_up - pg_down <= pmax)

    JuMP.@constraint(pm.model, 
        qg_start + qg_up - qg_down <= qmax)
end
