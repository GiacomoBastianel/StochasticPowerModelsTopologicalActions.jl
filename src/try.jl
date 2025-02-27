using JuMP, Gurobi, Plots, MathOptInterface

const MOI = MathOptInterface  # Alias for MathOptInterface

# Create a Gurobi model
model = Model(Gurobi.Optimizer)
set_optimizer_attribute(model, "TimeLimit", 10)  # Set a time limit for testing

# Define variables (INTEGER to ensure MIP solving)
@variable(model, x >= 0, Int)
@variable(model, y >= 0, Int)

# Define objective function
@objective(model, Min, x + y)

# Define constraints
@constraint(model, x + 2y ≥ 4)
@constraint(model, 3x + y ≥ 3)

# Arrays to store optimization progress
runtimeP = Float64[]  # Best objective values
objbstP = Float64[]    # Best bound values
objbndP = Float64[]  # MIP gap percentage
#iterations = Int[]    # Iteration numbers

# Define the callback function
softlimit = 5
hardlimit = 100
function my_callback_function(cb_data, cb_where::Cint)
    if cb_where == GRB_CB_MIP
        #runtimeP = Ref{Cdouble}()
        #objbstP = Ref{Cdouble}()
        #objbndP = Ref{Cdouble}()
        GRBcbget(cb_data, cb_where, GRB_CB_RUNTIME, runtimeP)
        GRBcbget(cb_data, cb_where, GRB_CB_MIP_OBJBST, objbstP)
        GRBcbget(cb_data, cb_where, GRB_CB_MIP_OBJBND, objbndP)
        gap = abs((objbstP[] - objbndP[]) / objbstP[])
        if runtimeP[] > softlimit && gap < 0.5
            GRBterminate(backend(model))
        end
    end
    return
end
MOI.set(model, Gurobi.CallbackFunction(), my_callback_function)

# Attach the callback (CORRECT way in JuMP)

# Solve the model
optimize!(model)

# Ensure data is collected before plotting
if !isempty(obj_vals)
    # Plot objective value and best bound
    p1 = plot(iterations, obj_vals, label="Objective Value", linewidth=2, xlabel="Iteration", ylabel="Objective", title="Gurobi Optimization Progress")
    plot!(p1, iterations, bounds, label="Best Bound", linewidth=2, linestyle=:dash)

    # Plot MIP gap
    p2 = plot(iterations, mip_gaps, label="MIP Gap (%)", linewidth=2, linestyle=:dot, color=:red, xlabel="Iteration", ylabel="MIP Gap (%)", title="MIP Gap Over Time")

    # Show both plots
    plot(p1, p2, layout=(2,1), size=(800,600))
else
    println("No data was collected. Ensure the problem is a MIP.")
end