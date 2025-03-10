using JuMP, Gurobi, Test

model = direct_model(Gurobi.Optimizer())
@variable(model, 0 <= x <= 2.5, Int)
@variable(model, 0 <= y <= 2.5, Int)
@objective(model, Max, y)
cb_calls = Cint[]
function my_callback_function(cb_data, cb_where::Cint)
    # You can reference variables outside the function as normal
    push!(cb_calls, cb_where)
    # You can select where the callback is run
    if cb_where != GRB_CB_MIPSOL && cb_where != GRB_CB_MIPNODE
        return
    end
    println("DIO PORCOOOOO")
    println(" GRB_CB_MIP_OBJBND is $(GRB_CB_MIP_OBJBND)")
    println(" GRB_CB_MIP_OBJBST is $(GRB_CB_MIP_OBJBST)")
    # You can query a callback attribute using GRBcbget
    if cb_where == GRB_CB_MIPNODE
        resultP = Ref{Cint}()
        GRBcbget(cb_data, cb_where, GRB_CB_MIPNODE_STATUS, resultP)
        if resultP[] != GRB_OPTIMAL
            return  # Solution is something other than optimal.
        end
    end
    # Before querying `callback_value`, you must call:
    Gurobi.load_callback_variable_primal(cb_data, cb_where)
    x_val = callback_value(cb_data, x)
    y_val = callback_value(cb_data, y)
    # You can submit solver-independent MathOptInterface attributes such as
    # lazy constraints, user-cuts, and heuristic solutions.
    #println(GRB_CB_MIP_OBJBND)
    
    if y_val - x_val > 1 + 1e-6
        con = @build_constraint(y - x <= 1)
        MOI.submit(model, MOI.LazyConstraint(cb_data), con)
    elseif y_val + x_val > 3 + 1e-6
        con = @build_constraint(y + x <= 3)
        MOI.submit(model, MOI.LazyConstraint(cb_data), con)
    end
    if rand() < 0.1
        # You can terminate the callback as follows:
        GRBterminate(backend(model))
    end
    return
end
# You _must_ set this parameter if using lazy constraints.
MOI.set(model, MOI.RawOptimizerAttribute("LazyConstraints"), 1)
MOI.set(model, Gurobi.CallbackFunction(), my_callback_function)
optimize!(model)
@test termination_status(model) == MOI.OPTIMAL
@test primal_status(model) == MOI.FEASIBLE_POINT
@test value(x) == 1
@test value(y) == 2