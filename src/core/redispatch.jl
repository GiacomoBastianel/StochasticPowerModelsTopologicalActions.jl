export solve_acdc_redispatch_opf

""
function solve_acdc_redispatch_opf(data::Dict{String,Any}, model_type::Type, solver; kwargs...)
    return _PM.solve_model(data, model_type, solver, build_acdc_redispatch_opf; ref_extensions = [_PMACDC.add_ref_dcgrid!], kwargs...)
end

""

function build_acdc_redispatch_opf(pm::_PM.AbstractPowerModel)
    _PM.variable_bus_voltage(pm)
    _PM.variable_gen_power(pm)
    _PM.variable_branch_power(pm)
    _PM.variable_storage_power(pm)

    _PMACDC.variable_active_dcbranch_flow(pm)
    _PMACDC.variable_dcbranch_current(pm)
    _PMACDC.variable_dc_converter(pm)
    _PMACDC.variable_dcgrid_voltage_magnitude(pm)

    objective_stochastic_redispatch_opf(pm)

    _PM.constraint_model_voltage(pm)
    _PMACDC.constraint_voltage_dc(pm)

    for i in _PM.ids(pm, :ref_buses)
        _PM.constraint_theta_ref(pm, i)
    end

    for i in _PM.ids(pm, :bus)
        _PMACDC.constraint_power_balance_ac(pm, i)
    end

    for i in _PM.ids(pm, :branch)
        _PM.constraint_ohms_yt_from(pm, i)
        _PM.constraint_ohms_yt_to(pm, i)
        _PM.constraint_voltage_angle_difference(pm, i) #angle difference across transformer and reactor - useful for LPAC if available?
        _PM.constraint_thermal_limit_from(pm, i)
        _PM.constraint_thermal_limit_to(pm, i)
    end
    
    for i in _PM.ids(pm, :busdc)
        _PMACDC.constraint_power_balance_dc(pm, i)
    end
    for i in _PM.ids(pm, :branchdc)
        _PMACDC.constraint_ohms_dc_branch(pm, i)
    end
    for i in _PM.ids(pm, :convdc)
        _PMACDC.constraint_converter_losses(pm, i)
        _PMACDC.constraint_converter_current(pm, i)
        _PMACDC.constraint_conv_transformer(pm, i)
        _PMACDC.constraint_conv_reactor(pm, i)
        _PMACDC.constraint_conv_filter(pm, i)
        if pm.ref[:it][:pm][:nw][_PM.nw_id_default][:convdc][i]["islcc"] == 1
            _PMACDC.constraint_conv_firing_angle(pm, i)
        end
    end
end


function solve_acdc_full_redispatch_opf(data::Dict{String,Any}, model_type::Type, solver; kwargs...)
    return _PM.solve_model(data, model_type, solver, build_acdc_full_redispatch_opf; ref_extensions = [_PMACDC.add_ref_dcgrid!], kwargs...)
end

""
function build_acdc_full_redispatch_opf(pm::_PM.AbstractPowerModel)
    _PM.variable_bus_voltage(pm)
    variable_gen_redispatch_upward(pm)
    variable_gen_redispatch_downward(pm)
    _PM.variable_branch_power(pm)
    _PM.variable_storage_power(pm)

    _PMACDC.variable_active_dcbranch_flow(pm)
    _PMACDC.variable_dcbranch_current(pm)
    _PMACDC.variable_dc_converter(pm)
    _PMACDC.variable_dcgrid_voltage_magnitude(pm)

    objective_stochastic_redispatch_opf(pm)

    _PM.constraint_model_voltage(pm)
    _PMACDC.constraint_voltage_dc(pm)

    for i in _PM.ids(pm, :ref_buses)
        _PM.constraint_theta_ref(pm, i)
    end

    for i in _PM.ids(pm, :gen)
        constraint_gen_redispatch(pm, i)
    end

    for i in _PM.ids(pm, :bus)
        constraint_power_balance_ac_redispatch(pm, i)
    end

    for i in _PM.ids(pm, :branch)
        _PM.constraint_ohms_yt_from(pm, i)
        _PM.constraint_ohms_yt_to(pm, i)
        _PM.constraint_voltage_angle_difference(pm, i) #angle difference across transformer and reactor - useful for LPAC if available?
        _PM.constraint_thermal_limit_from(pm, i)
        _PM.constraint_thermal_limit_to(pm, i)
    end
    
    for i in _PM.ids(pm, :busdc)
        _PMACDC.constraint_power_balance_dc(pm, i)
    end
    for i in _PM.ids(pm, :branchdc)
        _PMACDC.constraint_ohms_dc_branch(pm, i)
    end
    for i in _PM.ids(pm, :convdc)
        _PMACDC.constraint_converter_losses(pm, i)
        _PMACDC.constraint_converter_current(pm, i)
        _PMACDC.constraint_conv_transformer(pm, i)
        _PMACDC.constraint_conv_reactor(pm, i)
        _PMACDC.constraint_conv_filter(pm, i)
        if pm.ref[:it][:pm][:nw][_PM.nw_id_default][:convdc][i]["islcc"] == 1
            _PMACDC.constraint_conv_firing_angle(pm, i)
        end
    end
end

function run_hourly_redispatch(grid, result_bs, model, optimizer,switches_couples_ac,extremes_ZILs_ac,test_case_opf,settings)
    result_feasibility_checks = Dict{String,Any}()
    for hour in 1:length(grid["nw"])
        result_feasibility_checks["$hour"] = Dict{String,Any}()
        feasibility_check = deepcopy(grid["nw"]["$hour"])
        feasibility_check_input = deepcopy(grid["nw"]["$hour"])
        _PMTP.prepare_AC_feasibility_check(result_bs["$hour"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)

        # Adding set points
        for (g_id,g) in feasibility_check["gen"]
            g["pg_start"] = result_bs["$hour"]["solution"]["gen"][g_id]["pg"]
            g["qg_start"] = result_bs["$hour"]["solution"]["gen"][g_id]["qg"]
            if length(g["cost"]) > 1
                g["redispatch_cost_up"] = g["cost"][1]
                g["redispatch_cost_down"] = g["cost"][1]
            else
                g["redispatch_cost_up"] = 0.0
                g["redispatch_cost_down"] = 0.0
            end
        end

        result_feasibility_checks["$hour"] = solve_acdc_full_redispatch_opf(feasibility_check,model,optimizer)
    end
    return result_feasibility_checks
end

function run_hourly_redispatch_fc(grid, result_bs, results_fc, model, optimizer,switches_couples_ac,extremes_ZILs_ac,test_case_opf,settings)
    result_feasibility_checks = Dict{String,Any}()
    for hour in 1:length(grid["nw"])
        result_feasibility_checks["$hour"] = Dict{String,Any}()
        feasibility_check = deepcopy(grid["nw"]["$hour"])
        feasibility_check_input = deepcopy(grid["nw"]["$hour"])
        _PMTP.prepare_AC_feasibility_check(result_bs["$hour"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)

        # Adding set points
        for (g_id,g) in feasibility_check["gen"]
            g["pg_start"] = results_fc["$hour"]["solution"]["gen"][g_id]["pg"]
            g["qg_start"] = results_fc["$hour"]["solution"]["gen"][g_id]["qg"]
            if length(g["cost"]) > 1
                g["redispatch_cost_up"] = g["cost"][1]
                g["redispatch_cost_down"] = g["cost"][1]
            else
                g["redispatch_cost_up"] = 0.0
                g["redispatch_cost_down"] = 0.0
            end
            #if g_id == "1"
            #    g["redispatch_cost_up"] = 10.0
            #    g["redispatch_cost_down"] = 10.0
            #    #println("Generator 1 has a cost up of $(g["redispatch_cost_up"])")
            #    #println("Generator 1 has a cost down of $(g["redispatch_cost_down"])")
            #end
        end

        result_feasibility_checks["$hour"] = solve_acdc_full_redispatch_opf(feasibility_check,model,optimizer)
    end
    return result_feasibility_checks
end

function run_hourly_redispatch_one_topology(grid, result_bs, model, optimizer,switches_couples_ac,extremes_ZILs_ac,test_case_opf,settings)
    result_feasibility_checks = Dict{String,Any}()
    for hour in 1:length(grid["nw"])
        result_feasibility_checks["$hour"] = Dict{String,Any}()
        feasibility_check = deepcopy(grid["nw"]["$hour"])
        feasibility_check_input = deepcopy(grid["nw"]["$hour"])
        prepare_AC_feasibility_check_stochastic(result_bs["solution"]["nw"]["$hour"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)

        # Adding set points
        for (g_id,g) in feasibility_check["gen"]
            g["pg_start"] = result_bs["solution"]["nw"]["$hour"]["gen"][g_id]["pg"]
            g["qg_start"] = result_bs["solution"]["nw"]["$hour"]["gen"][g_id]["qg"]
            if length(g["cost"]) > 1
                g["redispatch_cost_up"] = g["cost"][1]
                g["redispatch_cost_down"] = g["cost"][1]
            else
                g["redispatch_cost_up"] = 0.0
                g["redispatch_cost_down"] = 0.0
            end
        end

        result_feasibility_checks["$hour"] = solve_acdc_full_redispatch_opf(feasibility_check,model,optimizer)
    end
    return result_feasibility_checks
end

function run_hourly_redispatch_one_topology_fc(grid, result_bs, results_fc, model, optimizer,switches_couples_ac,extremes_ZILs_ac,test_case_opf,settings)
    result_feasibility_checks = Dict{String,Any}()
    for hour in 1:length(grid["nw"])
        result_feasibility_checks["$hour"] = Dict{String,Any}()
        feasibility_check = deepcopy(grid["nw"]["$hour"])
        feasibility_check_input = deepcopy(grid["nw"]["$hour"])
        prepare_AC_feasibility_check_stochastic(result_bs["solution"]["nw"]["$hour"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)

        # Adding set points
        for (g_id,g) in feasibility_check["gen"]
            g["pg_start"] = results_fc["$hour"]["solution"]["gen"][g_id]["pg"]
            g["qg_start"] = results_fc["$hour"]["solution"]["gen"][g_id]["qg"]
            if length(g["cost"]) > 1
                g["redispatch_cost_up"] = g["cost"][1]
                g["redispatch_cost_down"] = g["cost"][1]
            else
                g["redispatch_cost_up"] = 0.0
                g["redispatch_cost_down"] = 0.0
            end
            #if g_id == "1"
            #    g["redispatch_cost_up"] = 10.0
            #    g["redispatch_cost_down"] = 10.0
            #    #println("Generator 1 has a cost up of $(g["redispatch_cost_up"])")
            #    #println("Generator 1 has a cost down of $(g["redispatch_cost_down"])")
            #end
        end

        result_feasibility_checks["$hour"] = solve_acdc_full_redispatch_opf(feasibility_check,model,optimizer)
    end
    return result_feasibility_checks
end

function run_hourly_redispatch_scenarios(grid, result_bs, model, optimizer,switches_couples_ac,extremes_ZILs_ac,test_case_opf,settings,n_hours,n_scenarios)
    result_feasibility_checks = Dict{String,Any}()
    for hour in 1:n_hours
        for s in 1:n_scenarios
            # This has to incclude all the scenarios
            if s == 1
                timestep = (hour - 1)*n_scenarios + s
                if haskey(result_bs,"solution")
                    result_feasibility_checks["$hour"] = Dict{String,Any}()
                    feasibility_check = deepcopy(grid["nw"]["$hour"])
                    feasibility_check_input = deepcopy(grid["nw"]["$hour"])
                    prepare_AC_feasibility_check_stochastic(result_bs["solution"]["nw"]["$hour"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)

                    # Adding set points
                    for (g_id,g) in feasibility_check["gen"]
                        g["pg_start"] = result_bs["solution"]["nw"]["$hour"]["gen"][g_id]["pg"]
                        g["qg_start"] = result_bs["solution"]["nw"]["$hour"]["gen"][g_id]["qg"]
                        if length(g["cost"]) > 1
                            g["redispatch_cost_up"] = g["cost"][1]
                            g["redispatch_cost_down"] = g["cost"][1]
                        else
                            g["redispatch_cost_up"] = 0.0
                            g["redispatch_cost_down"] = 0.0
                        end
                    end
                
                    result_feasibility_checks["$hour"] = solve_acdc_full_redispatch_opf(feasibility_check,model,optimizer)
                elseif haskey(result_bs["$hour"]["solution"],"nw")
                    result_feasibility_checks["$hour"] = Dict{String,Any}()
                    feasibility_check = deepcopy(grid["nw"]["$hour"])
                    feasibility_check_input = deepcopy(grid["nw"]["$hour"])
                    prepare_AC_feasibility_check_stochastic(result_bs["$hour"]["solution"]["nw"]["$s"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)

                    # Adding set points
                    for (g_id,g) in feasibility_check["gen"]
                        g["pg_start"] = result_bs["$hour"]["solution"]["nw"]["$s"]["gen"][g_id]["pg"]
                        g["qg_start"] = result_bs["$hour"]["solution"]["nw"]["$s"]["gen"][g_id]["qg"]
                        if length(g["cost"]) > 1
                            g["redispatch_cost_up"] = g["cost"][1]
                            g["redispatch_cost_down"] = g["cost"][1]
                        else
                            g["redispatch_cost_up"] = 0.0
                            g["redispatch_cost_down"] = 0.0
                        end
                    end
                
                    result_feasibility_checks["$hour"] = solve_acdc_full_redispatch_opf(feasibility_check,model,optimizer)
                end
            end
        end
    end
    return result_feasibility_checks
end

function print_gen_redispatch(grid,results,n_hours)
    for hour in 1:n_hours
        println("------------------------")
        println("Hour: $hour")
        println("Objective: $(results["$hour"]["objective"])")
        println("------------------------")
        for (g_id,g) in grid["gen"]
            if abs(results["$hour"]["solution"]["gen"][g_id]["pg_up"]) > 10^(-4)
                println("Generator $g_id: pg_up = $(results["$hour"]["solution"]["gen"][g_id]["pg_up"])")
            elseif abs(results["$hour"]["solution"]["gen"][g_id]["pg_down"]) > 10^(-4)
                println("Generator $g_id: pg_down = $(results["$hour"]["solution"]["gen"][g_id]["pg_down"])")
            end
        end
    end
end

function run_hourly_redispatch_stochastic(grid, stochastic_grid, result_bs, model, optimizer,switches_couples_ac,extremes_ZILs_ac,test_case_opf,settings,n_hours,n_scenarios)
    result_feasibility_checks = Dict{String,Any}()
    for hour in 1:n_hours
        for s in 1:n_scenarios
            # This has to include all the scenarios
                timestep = (hour - 1)*n_scenarios + s
                if haskey(result_bs,"solution")
                    result_feasibility_checks["$timestep"] = Dict{String,Any}()
                    feasibility_check = deepcopy(grid["nw"]["$hour"])
                    feasibility_check_input = deepcopy(grid["nw"]["$hour"])
                    prepare_AC_feasibility_check_stochastic(result_bs["solution"]["nw"]["$timestep"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)

                    # Adding set points
                    for (g_id,g) in feasibility_check["gen"]
                        g["pg_start"] = result_bs["solution"]["nw"]["$timestep"]["gen"][g_id]["pg"]
                        g["qg_start"] = result_bs["solution"]["nw"]["$timestep"]["gen"][g_id]["qg"]
                        if length(g["cost"]) > 1
                            g["redispatch_cost_up"] = g["cost"][1]
                            g["redispatch_cost_down"] = g["cost"][1]
                        else
                            g["redispatch_cost_up"] = 0.0
                            g["redispatch_cost_down"] = 0.0
                        end
                    end
                
                    result_feasibility_checks["$timestep"] = solve_acdc_full_redispatch_opf(feasibility_check,model,optimizer)
                    result_feasibility_checks["$timestep"]["probability"] = stochastic_grid["nw"]["$timestep"]["probability"]
                
                elseif haskey(result_bs["$hour"]["solution"],"nw")
                    result_feasibility_checks["$timestep"] = Dict{String,Any}()
                    feasibility_check = deepcopy(grid["nw"]["$hour"])
                    feasibility_check_input = deepcopy(grid["nw"]["$hour"])
                    prepare_AC_feasibility_check_stochastic(result_bs["$hour"]["solution"]["nw"]["$s"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)

                    # Adding set points
                    for (g_id,g) in feasibility_check["gen"]
                        g["pg_start"] = result_bs["$hour"]["solution"]["nw"]["$s"]["gen"][g_id]["pg"]
                        g["qg_start"] = result_bs["$hour"]["solution"]["nw"]["$s"]["gen"][g_id]["qg"]
                        if length(g["cost"]) > 1
                            g["redispatch_cost_up"] = g["cost"][1]
                            g["redispatch_cost_down"] = g["cost"][1]
                        else
                            g["redispatch_cost_up"] = 0.0
                            g["redispatch_cost_down"] = 0.0
                        end
                    end
                
                    result_feasibility_checks["$timestep"] = solve_acdc_full_redispatch_opf(feasibility_check,model,optimizer)
                    result_feasibility_checks["$timestep"]["probability"] = stochastic_grid["nw"]["$timestep"]["probability"]
                end
        end
    end
    return result_feasibility_checks
end

function run_hourly_redispatch_stochastic_fc(grid, stochastic_grid, result_bs, results_fc, model, optimizer,switches_couples_ac,extremes_ZILs_ac,test_case_opf,settings,n_hours,n_scenarios)
    result_feasibility_checks = Dict{String,Any}()
    for hour in 1:n_hours
        for s in 1:n_scenarios
            # This has to include all the scenarios
                timestep = (hour - 1)*n_scenarios + s
                if haskey(result_bs,"solution")
                    result_feasibility_checks["$timestep"] = Dict{String,Any}()
                    feasibility_check = deepcopy(grid["nw"]["$hour"])
                    feasibility_check_input = deepcopy(grid["nw"]["$hour"])
                    prepare_AC_feasibility_check_stochastic(result_bs["solution"]["nw"]["$timestep"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)

                    # Adding set points
                    for (g_id,g) in feasibility_check["gen"]
                        g["pg_start"] = results_fc["$timestep"]["solution"]["gen"][g_id]["pg"]
                        g["qg_start"] = results_fc["$timestep"]["solution"]["gen"][g_id]["qg"]
                        if length(g["cost"]) > 1 && g_id != "1"
                            g["redispatch_cost_up"] = g["cost"][1]
                            g["redispatch_cost_down"] = g["cost"][1]
                        elseif length(g["cost"]) > 1 && g_id == "1"
                            g["redispatch_cost_up"] = 10.0
                            g["redispatch_cost_down"] = 10.0
                        elseif length(g["cost"]) < 1
                            g["redispatch_cost_up"] = 0.0
                            g["redispatch_cost_down"] = 0.0
                        end
                    end
                
                    result_feasibility_checks["$timestep"] = solve_acdc_full_redispatch_opf(feasibility_check,model,optimizer)
                    result_feasibility_checks["$timestep"]["probability"] = stochastic_grid["nw"]["$timestep"]["probability"]
                
                elseif haskey(result_bs["$hour"]["solution"],"nw")
                    result_feasibility_checks["$timestep"] = Dict{String,Any}()
                    feasibility_check = deepcopy(grid["nw"]["$hour"])
                    feasibility_check_input = deepcopy(grid["nw"]["$hour"])
                    prepare_AC_feasibility_check_stochastic(result_bs["$hour"]["solution"]["nw"]["$s"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)

                    # Adding set points
                    for (g_id,g) in feasibility_check["gen"]
                        g["pg_start"] = results_fc["$timestep"]["solution"]["gen"][g_id]["pg"]
                        g["qg_start"] = results_fc["$timestep"]["solution"]["gen"][g_id]["qg"]
                        if length(g["cost"]) > 1 && g_id != "1"
                            g["redispatch_cost_up"] = g["cost"][1]
                            g["redispatch_cost_down"] = g["cost"][1]
                        elseif length(g["cost"]) > 1 && g_id == "1"
                            g["redispatch_cost_up"] = 0.0
                            g["redispatch_cost_down"] = 0.0
                        elseif length(g["cost"]) < 1
                            g["redispatch_cost_up"] = 0.0
                            g["redispatch_cost_down"] = 0.0
                        end
                    end
                
                    result_feasibility_checks["$timestep"] = solve_acdc_full_redispatch_opf(feasibility_check,model,optimizer)
                    result_feasibility_checks["$timestep"]["probability"] = stochastic_grid["nw"]["$timestep"]["probability"]
                end
        end
    end
    return result_feasibility_checks
end

function run_hourly_redispatch_opf(grid, result_opf, model, optimizer,switches_couples_ac,extremes_ZILs_ac,test_case_opf,settings)
    result_feasibility_checks = Dict{String,Any}()
    for hour in 1:length(grid["nw"])
        result_feasibility_checks["$hour"] = Dict{String,Any}()
        feasibility_check = deepcopy(grid["nw"]["$hour"])
        feasibility_check_input = deepcopy(grid["nw"]["$hour"])
        #_PMTP.prepare_AC_feasibility_check(result_opf["$hour"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)

        # Adding set points
        for (g_id,g) in feasibility_check["gen"]
            g["pg_start"] = result_opf["$hour"]["solution"]["gen"][g_id]["pg"]
            g["qg_start"] = result_opf["$hour"]["solution"]["gen"][g_id]["qg"]
            if length(g["cost"]) > 1 && g_id != "1"
                g["redispatch_cost_up"] = g["cost"][1]
                g["redispatch_cost_down"] = g["cost"][1]
            elseif length(g["cost"]) > 1 && g_id == "1"
                g["redispatch_cost_up"] = 10.0
                g["redispatch_cost_down"] = 10.0
            elseif length(g["cost"]) < 1
                g["redispatch_cost_up"] = 0.0
                g["redispatch_cost_down"] = 0.0
            end    
        end
        result_feasibility_checks["$hour"] = solve_acdc_full_redispatch_opf(feasibility_check,model,optimizer)
    end
    return result_feasibility_checks
end