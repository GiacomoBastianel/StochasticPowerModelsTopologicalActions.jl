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

function objective_stochastic_opf(pm::_PM.LPACCPowerModel)
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

function calc_gen_cost(pm::_PM.LPACCPowerModel, n::Int)
    cost = JuMP.AffExpr(0.0)
    for (i,g) in _PM.ref(pm, n, :gen)
        if length(g["cost"]) ≥ 2
            JuMP.add_to_expression!(cost, g["cost"][end-1], _PM.var(pm,n,:pg,i))
        end
    end
    return cost
end