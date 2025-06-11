function objective_stochastic_switch(pm::_PM.LPACCPowerModel)
    cost = JuMP.AffExpr(0.0)

    # Operation cost
    #if multi_period
        # multiperiod formulation to be added
    #else
        for (s, scenario) in _FP.dim_prop(pm, :scenario)
            println("s: ", s)
            println("scenario: ", scenario)
            scenario_probability = scenario["probability"]
            for n in _FP.nw_ids(pm; scenario=s)
                JuMP.add_to_expression!(cost, scenario_probability, calc_gen_cost(pm,n))
            end
        end
    #end
    JuMP.@objective(pm.model, Min, cost)
end

function objective_stochastic_opf(pm::_PM.AbstractPowerModel)
    cost = JuMP.AffExpr(0.0)

    for n in 1:length(pm.ref[:it][_PM.pm_it_sym][:nw])
        scenario_probability = _PM.ref(pm, n, :probability)
        JuMP.add_to_expression!(cost, scenario_probability, calc_gen_cost(pm,n))
    end
    JuMP.@objective(pm.model, Min, cost)
end

function objective_stochastic_opf_hourly(pm::_PM.AbstractPowerModel)
    cost = JuMP.AffExpr(0.0)

    for (n,network) in pm.ref[:it][_PM.pm_it_sym][:nw]
        scenario_probability = _PM.ref(pm, n, :probability)
        JuMP.add_to_expression!(cost, scenario_probability, calc_gen_cost(pm,n))
    end
    JuMP.@objective(pm.model, Min, cost)
end

function objective_stochastic_opf_opf(pm::_PM.AbstractPowerModel)
    cost = JuMP.AffExpr(0.0)

    for n in _FP.nw_ids(pm)
        scenario_probability = _PM.ref(pm, n, :probability)
        JuMP.add_to_expression!(cost, scenario_probability, -calc_gen_cost(pm,n))
    end
    opf_result = pm.ref[:it][_PM.pm_it_sym][:opf_result]
    JuMP.add_to_expression!(cost, 1.0, opf_result)
    JuMP.@objective(pm.model, Min, cost)
    #return JuMP.@objective(pm.model, Min,
    #sum(
    #    sum( _PM.var(pm, n, :pg_cost, i) for (i,gen) in nw_ref[:gen])
    #for (n,nw_ref) in _FP.nw_ids(pm)
    #)
    #)
end

function objective_multistep_ac_switch(pm::_PM.AbstractPowerModel)
    cost = JuMP.AffExpr(0.0)

    # Operation cost
    #if multi_period
        # multiperiod formulation to be added
    #else
        for nw_id in 1:length(pm.ref[:it][:pm][:nw])
            println("s: ", "$nw_id")
            nw = pm.ref[:it][:pm][:nw][nw_id]
            scenario_probability = nw[:probability]
            println("scenario_probability: ", scenario_probability)
            println(typeof(nw_id), " ")
            JuMP.add_to_expression!(cost, scenario_probability, calc_gen_cost(pm,nw_id))
            JuMP.add_to_expression!(cost, scenario_probability, calc_ac_switch_cost(pm,nw_id))
        end
    #end
    JuMP.@objective(pm.model, Min, cost)
end

function calc_gen_cost(pm::_PM.AbstractPowerModel, n::Int)
    println("n: ", n)
    cost = JuMP.AffExpr(0.0)
    for (i,g) in pm.ref[:it][:pm][:nw][n][:gen]
        if length(g["cost"]) ≥ 2
            JuMP.add_to_expression!(cost, g["cost"][end-1], _PM.var(pm,n,:pg,i))
        end
    end
    return cost
end

function calc_gen_redispatch_cost(pm::_PM.AbstractPowerModel, n::Int)
    println("n: ", n)
    cost = JuMP.AffExpr(0.0)
    for (i,g) in pm.ref[:it][:pm][n][:gen]
        if length(g["cost"]) ≥ 2
            JuMP.add_to_expression!(cost, g["redispatch_cost_up"], _PM.var(pm,n,:pg_up,i) - pm.ref[:it][:pm][:nw][n][:gen][i]["pg_start"])
            JuMP.add_to_expression!(cost, g["redispatch_cost_down"], pm.ref[:it][:pm][:nw][n][:gen][i]["pg_start"] - _PM.var(pm,n,:pg_down,i))
        end
    end
    return cost
end

function calc_ac_switch_cost(pm::_PM.AbstractPowerModel,n::Int)
    cost = JuMP.AffExpr(0.0)
    for (sw_id,sw) in pm.ref[:it][:pm][:nw][n][:switch]
        if !haskey(sw,"auxiliary")
            JuMP.add_to_expression!(cost, sw["cost"], (1 - _PM.var(pm,n,:z_switch,sw_id)))
        end
    end
    return cost
end

function calc_dc_switch_cost(pm::_PM.AbstractPowerModel, n::Int)
    cost = JuMP.AffExpr(0.0)
    for (sw_id,sw) in _PM.ref(pm, n, :dcswitch)
        JuMP.add_to_expression!(cost, sw["cost"], (1 - _PM.var(pm,n,:z_switch,sw_id)))
    end
    return cost
end

function objective_stochastic_redispatch_opf(pm::_PM.AbstractPowerModel)
    cost = JuMP.AffExpr(0.0)

    #for n in 1:length(pm.ref[:it][_PM.pm_it_sym][:nw])
        JuMP.add_to_expression!(cost, calc_gen_redispatch_cost(pm))
    #end
    JuMP.@objective(pm.model, Min, cost)
end


function calc_gen_redispatch_cost(pm::_PM.AbstractPowerModel)
    cost = JuMP.AffExpr(0.0)
    for (i,g) in pm.ref[:it][:pm][:nw][_PM.nw_id_default][:gen]
        JuMP.add_to_expression!(cost, g["redispatch_cost_up"], _PM.var(pm,:pg_up,i))# - pm.ref[:it][:pm][:nw][_PM.nw_id_default][:gen][i]["pg_start"]))
        JuMP.add_to_expression!(cost, g["redispatch_cost_down"], _PM.var(pm,:pg_down,i))#-(pm.ref[:it][:pm][:nw][_PM.nw_id_default][:gen][i]["pg_start"]))
        #JuMP.add_to_expression!(cost, g["redispatch_cost_up"], _PM.var(pm,:qg_up,i))# - pm.ref[:it][:pm][:nw][_PM.nw_id_default][:gen][i]["qg_start"]))
        #JuMP.add_to_expression!(cost, g["redispatch_cost_down"], _PM.var(pm,:qg_down,i))# -(pm.ref[:it][:pm][:nw][_PM.nw_id_default][:gen][i]["qg_start"] - _PM.var(pm,:qg_down,i)))
    end
    return cost
end

