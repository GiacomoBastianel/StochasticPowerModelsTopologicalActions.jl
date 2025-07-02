using PowerModels; const _PM = PowerModels
using PowerModelsACDC; const _PMACDC = PowerModelsACDC
import PowerModelsTopologicalActionsII; const _PMTP = PowerModelsTopologicalActionsII
using FlexPlan; const _FP = FlexPlan
using Gurobi, Ipopt, JSON, Plots
import StochasticPowerModelsTopologicalActions; const _SPMTA = StochasticPowerModelsTopologicalActions
using JuMP, Juniper, HSL_jll, MathOptInterface, HiGHS
using Statistics
using PowerPlots

mip_gap = 1e-3
gurobi_bs = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 5400,"MIPGap" => mip_gap,"BarHomogeneous" => 1, "NumericFocus"=>2) 
gurobi = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 1800,"MIPGap" => mip_gap,"BarHomogeneous" => 1,"BarQCPConvTol"=>1e-6,"QCPDual" => 1, "ScaleFlag"=>2, "NumericFocus"=>2) 
gurobi_opf = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 1200,"MIPGap" => mip_gap,"BarHomogeneous" => 1, "NumericFocus"=>2,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "ScaleFlag"=>2, "NumericFocus"=>3) 
gurobi_lpac = JuMP.optimizer_with_attributes(Gurobi.Optimizer)#,"time_limit" => 1200,"MIPGap" => mip_gap,"BarHomogeneous" => 1,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "ScaleFlag"=>2, "NumericFocus"=>2)
ipopt = JuMP.optimizer_with_attributes(Ipopt.Optimizer, "tol" => 1e-6, "print_level" => 0,"linear_solver" => "ma97")
juniper = JuMP.optimizer_with_attributes(Juniper.Optimizer, "nl_solver" => ipopt, "mip_solver" => gurobi, "time_limit" => 36000)

first_hour = 355
last_hour  = 378

#########################################################################################
## Processing input data
s = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true)
s_dual = Dict("output" => Dict("branch_flows" => true,"duals" => true), "conv_losses_mp" => true)

#########################################################################################
## Processing input data
input_folder = @__DIR__
test_case_file = joinpath(dirname(dirname(input_folder)),"data_sources/pglib_opf_case30_ieee.m")
original_grid = _PM.parse_file(test_case_file)

results_folder = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/IJEPES_paper/Results"
results_folder_figures = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/IJEPES_paper/Figures"
case = "case_30/stochastic_multistep"

test_case = _PM.parse_file(test_case_file)
test_case_opf = deepcopy(test_case)

# THIS IS APPARENTLY FUNDAMENTAL TO GUARANTEE FEASIBILITY
_SPMTA.add_VOLL_generators(test_case_opf)
_SPMTA.add_VOLL_generators(test_case)

opf_30 = _PM.solve_opf(test_case_opf, LPACCPowerModel, ipopt)

test_case_bs = deepcopy(test_case_opf)
splitted_bus_ac = 6
test_case_bs,  switches_couples_ac,  extremes_ZILs_ac  = _PMTP.AC_busbar_split_AC_grid(test_case,splitted_bus_ac)

#########################################################################################
# Uploading time series
measured_wind = JSON.parsefile(joinpath(input_folder,"case30","measured_wind_$(first_hour)_$(last_hour)_modified.json"))
forecasted_wind = JSON.parsefile(joinpath(input_folder,"case30","forecasted_wind_hours_$(first_hour)_$(last_hour)_modified.json"))

# Uploading results
hourly_bs_forecasted  = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Hourly_bs_forecasted_$(first_hour)_$(last_hour).json"))
hourly_bs_measured    = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Hourly_bs_measured_$(first_hour)_$(last_hour).json"))

one_topology_forecasted  = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","24_hours_BS_one_topology_forecasted_$(first_hour)_$(last_hour).json"))
one_topology_measured    = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","24_hours_BS_one_topology_measured_$(first_hour)_$(last_hour).json"))

one_switching_action_forecasted  = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","One_maximum_actions_24_hours_forecasted_$(first_hour)_$(last_hour).json"))
one_switching_action_measured    = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","One_maximum_actions_24_hours_measured_$(first_hour)_$(last_hour).json"))

two_switching_action_forecasted  = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Two_maximum_actions_24_hours_forecasted_$(first_hour)_$(last_hour).json"))
two_switching_action_measured    = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Two_maximum_actions_24_hours_measured_$(first_hour)_$(last_hour).json"))

#######################
# Adding costs to the busbar couplers
for sw_id in 1:length(extremes_ZILs_ac)
    test_case_bs["switch"]["$sw_id"]["cost"] = 10.0
end

n_hours = 24
n_scenarios = 4
one_scenario = 1

#########################################################################################

test_case_opf_replicate_one_scenario_measured = deepcopy(_PM.replicate(test_case_opf, n_hours*one_scenario))
test_case_opf_replicate_one_scenario_forecasted = deepcopy(_PM.replicate(test_case_opf, n_hours*one_scenario))

test_case_bs_replicate = deepcopy(_PM.replicate(test_case_bs, n_hours*n_scenarios))
test_case_bs_replicate_one_scenario = deepcopy(_PM.replicate(test_case_bs, n_hours*one_scenario))

test_case_bs_replicate = deepcopy(_PM.replicate(test_case_bs, n_hours*n_scenarios))
test_case_bs_replicate_one_scenario_forecasted = deepcopy(_PM.replicate(test_case_bs, n_hours*one_scenario))

test_case_bs_mn_measured = deepcopy(test_case_bs_replicate_one_scenario)
test_case_bs_mn_forecasted = deepcopy(test_case_bs_replicate_one_scenario_forecasted)

test_case_opf_mn_measured = deepcopy(test_case_opf_replicate_one_scenario)
test_case_opf_mn_forecasted = deepcopy(test_case_opf_replicate_one_scenario)

_SPMTA.adding_multinetwork_scenarios(test_case_bs_mn_measured,n_hours,one_scenario,scenario_wind_4)
_SPMTA.adding_multinetwork_scenarios(test_case_bs_mn_forecasted,n_hours,one_scenario,scenario_wind_4)

_SPMTA.adding_multinetwork_scenarios(test_case_opf_mn_forecasted,n_hours,one_scenario,scenario_wind_4)
_SPMTA.adding_multinetwork_scenarios(test_case_opf_mn_measured,n_hours,one_scenario,scenario_wind_4)

# SOMETHING FISHY IS HAPPENING HERE
# ALL THE SIMULATIONS HAVE THE SAME RESULTS

for i in 1:(n_hours*one_scenario)
    test_case_bs_mn_measured["nw"]["$i"]["gen"]["1"]["pmax"]   = deepcopy(test_case_bs_mn_measured["nw"]["$i"]["gen"]["1"]["pmax"]*measured_wind[i])
    test_case_bs_mn_forecasted["nw"]["$i"]["gen"]["1"]["pmax"] = deepcopy(test_case_bs_mn_forecasted["nw"]["$i"]["gen"]["1"]["pmax"]*forecasted_wind[i])
    test_case_opf_mn_forecasted["nw"]["$i"]["gen"]["1"]["pmax"]   = deepcopy(test_case_opf_mn_forecasted["nw"]["$i"]["gen"]["1"]["pmax"]*forecasted_wind[i])
    test_case_opf_mn_measured["nw"]["$i"]["gen"]["1"]["pmax"]     = deepcopy(test_case_opf_mn_measured["nw"]["$i"]["gen"]["1"]["pmax"]*measured_wind[i])
end

# Running feasibility checks
function run_feasibility_checks_per_hour(grid, result_bs, model, optimizer,switches_couples_ac,extremes_ZILs_ac,test_case_opf,settings)
    result_feasibility_checks = Dict{String,Any}()
    for hour in 1:length(grid["nw"])
        result_feasibility_checks["$hour"] = Dict{String,Any}()
        feasibility_check = deepcopy(grid["nw"]["$hour"])
        feasibility_check_input = deepcopy(grid["nw"]["$hour"])
        _PMTP.prepare_AC_feasibility_check(result_bs["$hour"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
        result_feasibility_checks["$hour"] = _PM.solve_opf(feasibility_check,model,optimizer; setting = settings)
    end
    return result_feasibility_checks
end

function run_feasibility_checks_per_hour_one_topology_fixing(grid, result_bs, model, optimizer,switches_couples_ac,extremes_ZILs_ac,test_case_opf,settings)
    result_feasibility_checks = Dict{String,Any}()
    grid_hour = Dict{String,Any}()
    for hour in 1:grid["hours"]
        result_feasibility_checks["$hour"] = Dict{String,Any}()
        feasibility_check = deepcopy(grid["nw"]["$hour"])
        feasibility_check_input = deepcopy(grid["nw"]["$hour"])
        _SPMTA.prepare_AC_feasibility_check_stochastic(result_bs["solution"]["nw"]["$hour"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
        result_feasibility_checks["$hour"] = _PM.solve_opf(feasibility_check,model,optimizer; setting = settings)
        grid_hour["$hour"] = deepcopy(feasibility_check)
    end
    return result_feasibility_checks, grid_hour
end

function run_feasibility_checks_per_hour_one_topology(grid, result_bs, model, optimizer,switches_couples_ac,extremes_ZILs_ac,test_case_opf,settings)
    result_feasibility_checks = Dict{String,Any}()
    for hour in 1:grid["hours"]
        result_feasibility_checks["$hour"] = Dict{String,Any}()
        feasibility_check = deepcopy(grid["nw"]["$hour"])
        feasibility_check_input = deepcopy(grid["nw"]["$hour"])
        _SPMTA.prepare_AC_feasibility_check_stochastic(result_bs["solution"]["nw"]["$hour"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
        result_feasibility_checks["$hour"] = _PM.solve_opf(feasibility_check,model,optimizer; setting = settings)
    end
    return result_feasibility_checks
end

function run_feasibility_checks_per_hour_stochastic(grid, result_bs, model, optimizer,switches_couples_ac,extremes_ZILs_ac,test_case_opf,settings,n_hours,n_scenarios)
    result_feasibility_checks = Dict{String,Any}()
    for hour in 1:n_hours
        for s in 1:n_scenarios
            timestep = (hour - 1)*n_scenarios + s
            if haskey(result_bs,"solution")
                result_feasibility_checks["$timestep"] = Dict{String,Any}()
                feasibility_check = deepcopy(grid["nw"]["$timestep"])
                feasibility_check_input = deepcopy(grid["nw"]["$timestep"])
                _SPMTA.prepare_AC_feasibility_check_stochastic(result_bs["solution"]["nw"]["$timestep"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)

                result_feasibility_checks["$timestep"] = _PMACDC.run_acdcopf(feasibility_check,model,optimizer; setting = settings)
                result_feasibility_checks["$timestep"]["probability"] = grid["nw"]["$timestep"]["probability"]
            
            elseif haskey(result_bs["$hour"]["solution"],"nw")
                result_feasibility_checks["$timestep"] = Dict{String,Any}()
                feasibility_check = deepcopy(grid["nw"]["$timestep"])
                feasibility_check_input = deepcopy(grid["nw"]["$timestep"])
                _SPMTA.prepare_AC_feasibility_check_stochastic(result_bs["$hour"]["solution"]["nw"]["$s"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)

                result_feasibility_checks["$timestep"] = _PMACDC.run_acdcopf(feasibility_check,model,optimizer; setting = settings)
                result_feasibility_checks["$timestep"]["probability"] = grid["nw"]["$timestep"]["probability"]
            end
        end
    end
    return result_feasibility_checks
end

function run_hourly_opf(grid, model, optimizer,n_hours; settings = s)
    result = Dict{String,Any}()
    for nw in 1:n_hours
        result["$nw"] = _PM.solve_opf(grid["nw"]["$nw"],model,optimizer; setting = settings)
    end
    return result
end


hourly_fc_test_case_bs_mn_measured = deepcopy(test_case_bs_mn_measured)
fc_one_topology_test_case_bs_mn_measured = deepcopy(test_case_bs_mn_measured)
fc_one_sw_test_case_bs_mn_measured = deepcopy(test_case_bs_mn_measured)
fc_two_sw_test_case_bs_mn_measured = deepcopy(test_case_bs_mn_measured)

hourly_fc_test_case_bs_mn_forecasted = deepcopy(test_case_bs_mn_forecasted)
fc_one_topology_test_case_bs_mn_forecasted = deepcopy(test_case_bs_mn_forecasted)
fc_one_sw_test_case_bs_mn_forecasted = deepcopy(test_case_bs_mn_forecasted)
fc_two_sw_test_case_bs_mn_forecasted = deepcopy(test_case_bs_mn_forecasted)


hourly_fc_measured = run_feasibility_checks_per_hour(hourly_fc_test_case_bs_mn_measured,hourly_bs_measured,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
fc_one_topology_measured = run_feasibility_checks_per_hour_one_topology(fc_one_topology_test_case_bs_mn_measured,one_topology_measured,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
fc_one_sw_measured = run_feasibility_checks_per_hour_one_topology(fc_one_sw_test_case_bs_mn_measured,one_switching_action_measured,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
fc_two_sw_measured = run_feasibility_checks_per_hour_one_topology(fc_two_sw_test_case_bs_mn_measured,two_switching_action_measured,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)

hourly_fc_forecasted = run_feasibility_checks_per_hour(hourly_fc_test_case_bs_mn_forecasted,hourly_bs_forecasted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
fc_one_topology_forecasted, grid_one_topology = run_feasibility_checks_per_hour_one_topology_fixing(fc_one_topology_test_case_bs_mn_forecasted,one_topology_forecasted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
fc_one_sw_forecasted = run_feasibility_checks_per_hour_one_topology(fc_one_sw_test_case_bs_mn_forecasted,one_switching_action_forecasted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
fc_two_sw_forecasted = run_feasibility_checks_per_hour_one_topology(fc_two_sw_test_case_bs_mn_forecasted,two_switching_action_forecasted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)


sum(fc_one_sw_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(hourly_fc_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_one_topology_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_two_sw_forecasted["$hour"]["objective"] for hour in 1:n_hours)


function compute_total_pg_cost(grid,results,n_hours)
    cost_vector = []
    for hour in 1:n_hours
        cost = 0.0
        for (g_id,g) in grid["gen"]
            if haskey(results,"$hour")
                if haskey(results["$hour"]["solution"]["gen"],"$g_id") && length(g["cost"]) > 1
                    cost += results["$hour"]["solution"]["gen"]["$g_id"]["pg"]*g["cost"][end-1]
                end
            else
                if haskey(results["solution"]["nw"]["$hour"]["gen"],"$g_id") && length(g["cost"]) > 1
                    cost += results["solution"]["nw"]["$hour"]["gen"]["$g_id"]["pg"]*g["cost"][end-1]
                end
            end
        end
        push!(cost_vector,cost)
    end 
    return cost_vector       
end

cost_vector_hourly_bs_forecasted = compute_total_pg_cost(test_case_opf,hourly_bs_forecasted,n_hours)
cost_vector_one_topology_forecasted = compute_total_pg_cost(test_case_opf,one_topology_forecasted,n_hours)
cost_vector_one_sw_forecasted       = compute_total_pg_cost(test_case_opf,one_switching_action_forecasted,n_hours)
cost_vector_two_sw_forecasted       = compute_total_pg_cost(test_case_opf,two_switching_action_forecasted,n_hours)

fc_cost_vector_hourly_bs_forecasted    = compute_total_pg_cost(test_case_opf,hourly_fc_forecasted,n_hours)
fc_cost_vector_one_topology_forecasted = compute_total_pg_cost(test_case_opf,fc_one_topology_forecasted,n_hours)
fc_cost_vector_one_sw_forecasted       = compute_total_pg_cost(test_case_opf,fc_one_sw_forecasted,n_hours)
fc_cost_vector_two_sw_forecasted       = compute_total_pg_cost(test_case_opf,fc_two_sw_forecasted,n_hours)

##################

opf_measured   = run_hourly_opf(test_case_opf_mn_measured,ACPPowerModel,ipopt,n_hours)
opf_forecasted = run_hourly_opf(test_case_opf_mn_forecasted,ACPPowerModel,ipopt,n_hours)

fc_cost_vector_opf_measured   = compute_total_pg_cost(test_case_opf,hourly_fc_forecasted,n_hours)
fc_cost_vector_opf_forecasted = compute_total_pg_cost(test_case_opf,hourly_fc_forecasted,n_hours)


sum(opf_measured["$hour"]["objective"] for hour in 1:n_hours)
sum(opf_forecasted["$hour"]["objective"] for hour in 1:n_hours)

######################
function run_feasibility_checks_per_hour_one_topology_fixing(grid_hour,grid, result_bs, model, optimizer,switches_couples_ac,extremes_ZILs_ac,test_case_opf,settings)
    result_feasibility_checks = Dict{String,Any}()
    for hour in 1:grid["hours"]
        result_feasibility_checks["$hour"] = Dict{String,Any}()
        feasibility_check = deepcopy(grid["nw"]["$hour"])
        feasibility_check_input = deepcopy(grid["nw"]["$hour"])
        prepare_AC_feasibility_check_stochastic(result_bs["solution"]["nw"]["$hour"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
        result_feasibility_checks["$hour"] = _PM.solve_opf(feasibility_check,model,optimizer; setting = settings)
        grid_hour["$hour"] = deepcopy(feasibility_check)
    end
    return result_feasibility_checks
end

function prepare_AC_feasibility_check_stochastic(result_dict, input_dict, input_ac_check, switch_couples, extremes_dict,input_base)
    orig_buses = maximum(parse.(Int, keys(input_base["bus"]))) # maximum value before splitting (in case the buses are not in numerical order)
    println("DIOBOIAAAAA")
    for (sw_id,sw) in input_dict["switch"]
        if !haskey(sw,"auxiliary")
            println("SWITCH $sw_id, BUS from $(sw["f_bus"]), BUS to $(sw["t_bus"])")
            if result_dict["switch"][sw_id]["status"] >= 0.9 # Just reconnecting stuff
                println("Switch $sw_id is closed, Connecting everything back, no busbar splitting on bus $(sw["bus_split"])")
                for l in keys(switch_couples)
                    #if haskey(switch_couples,sw_id) && switch_couples[l]["bus_split"] == sw["bus_split"] -> wrong, you are checking the ZIL sw here
                    if switch_couples[l]["bus_split"] == sw["bus_split"] # coupling the switch couple to their split bus, if it closed, just connect everything back to the original switch
                        println("SWITCH COUPLE IS $l")

                        switch_t = deepcopy(input_dict["switch"]["$(switch_couples["$l"]["t_sw"])"])
                        switch_f = deepcopy(input_dict["switch"]["$(switch_couples["$l"]["f_sw"])"])
                        
                        if switch_t["t_bus"] == switch_couples[l]["bus_split"]
                            aux_t = switch_t["auxiliary"]
                            orig_t = switch_t["original"]
                            println("Element $aux_t $orig_t")
                            if aux_t == "gen"
                                input_ac_check["gen"]["$(orig_t)"]["gen_bus"] = deepcopy(input_dict["switch"]["$(switch_t["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                                delete!(input_ac_check["bus"],input_ac_check["gen"]["$(orig_t)"]["gen_bus"])
                                println("Element $aux_t $orig_t connected to $(input_ac_check["gen"]["$(orig_t)"]["gen_bus"])")
                            elseif aux_t == "load"
                                input_ac_check["load"]["$(orig_t)"]["load_bus"] = deepcopy(input_dict["switch"]["$(switch_t["index"])"]["t_bus"])
                                delete!(input_ac_check["bus"],input_ac_check["load"]["$(orig_t)"]["load_bus"])
                                println("Element $aux_t $orig_t connected to $(input_ac_check["load"]["$(orig_t)"]["load_bus"])")
                            elseif aux_t == "convdc"
                                input_ac_check["convdc"]["$(orig_t)"]["busac_i"] = deepcopy(input_dict["switch"]["$(switch_t["index"])"]["t_bus"])
                                delete!(input_ac_check["bus"],input_ac_check["convdc"]["$(orig_t)"]["busac_i"])
                                println("Element $aux_t $orig_t connected to $(input_ac_check["convdc"]["$(orig_t)"]["busac_i"])")
                            elseif aux_t == "branch" 
                                if input_ac_check["branch"]["$(orig_t)"]["f_bus"] > orig_buses && input_dict["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"] # useful if both ends of a branch are busbars being split
                                    input_ac_check["branch"]["$(orig_t)"]["f_bus"] = deepcopy(input_dict["switch"]["$(switch_t["index"])"]["t_bus"])
                                    delete!(input_ac_check["bus"],input_ac_check["branch"]["$(orig_t)"]["f_bus"])
                                    println("Element $aux_t $orig_t connected to $(input_ac_check["branch"]["$(orig_t)"]["f_bus"])")
                                elseif input_ac_check["branch"]["$(orig_t)"]["t_bus"] > orig_buses && input_dict["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                    input_ac_check["branch"]["$(orig_t)"]["t_bus"] = deepcopy(input_dict["switch"]["$(switch_t["index"])"]["t_bus"])
                                    delete!(input_ac_check["bus"],input_ac_check["branch"]["$(orig_t)"]["t_bus"])
                                    println("Element $aux_t $orig_t connected to $(input_ac_check["branch"]["$(orig_t)"]["t_bus"])")
                                end
                            end
                        elseif switch_f["t_bus"] == switch_couples[l]["bus_split"]
                            aux_f = switch_f["auxiliary"]
                            orig_f = switch_f["original"]
                            println("Element $aux_f $orig_f")
                            if aux_f == "gen"
                                input_ac_check["gen"]["$(orig_f)"]["gen_bus"] = deepcopy(input_dict["switch"]["$(switch_f["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                                delete!(input_ac_check["bus"],input_ac_check["gen"]["$(orig_f)"]["gen_bus"])
                                println("Element $aux_f $orig_f connected to $(input_ac_check["gen"]["$(orig_f)"]["gen_bus"])")
                            elseif aux_f == "load"
                                input_ac_check["load"]["$(orig_f)"]["load_bus"] = deepcopy(input_dict["switch"]["$(switch_f["index"])"]["t_bus"])
                                delete!(input_ac_check["bus"],input_ac_check["load"]["$(orig_f)"]["load_bus"])
                                println("Element $aux_f $orig_f connected to $(input_ac_check["load"]["$(orig_f)"]["load_bus"])")
                            elseif aux_f == "convdc"
                                input_ac_check["convdc"]["$(orig_f)"]["busac_i"] = deepcopy(input_dict["switch"]["$(switch_f["index"])"]["t_bus"])
                                delete!(input_ac_check["bus"],input_ac_check["convdc"]["$(orig_f)"]["busac_i"])
                                println("Element $aux_f $orig_f connected to $(input_ac_check["convdc"]["$(orig_f)"]["busac_i"])")
                            elseif aux_f == "branch" 
                                if input_ac_check["branch"]["$(orig_f)"]["f_bus"] > orig_buses && input_dict["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"] # useful if both ends of a branch are busbars being split
                                    input_ac_check["branch"]["$(orig_f)"]["f_bus"] = deepcopy(input_dict["switch"]["$(switch_f["index"])"]["t_bus"])
                                    delete!(input_ac_check["bus"],input_ac_check["branch"]["$(orig_f)"]["f_bus"])
                                    println("Element $aux_f $orig_f connected to $(input_ac_check["branch"]["$(orig_f)"]["f_bus"])")
                                elseif input_ac_check["branch"]["$(orig_f)"]["t_bus"] > orig_buses && input_dict["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                    input_ac_check["branch"]["$(orig_f)"]["t_bus"] = deepcopy(input_dict["switch"]["$(switch_f["index"])"]["t_bus"])
                                    delete!(input_ac_check["bus"],input_ac_check["branch"]["$(orig_f)"]["t_bus"])
                                    println("Element $aux_f $orig_f connected to $(input_ac_check["branch"]["$(orig_f)"]["t_bus"])")
                                end
                            end
                        end
                    end
                end
            elseif result_dict["switch"][sw_id]["status"] <= 0.1 # Connect elements to the right bus
                println("Switch $sw_id is open, busbar splitting on bus $(sw["bus_split"])")
                delete!(input_ac_check["switch"],sw_id)
                for l in keys(switch_couples)
                    if switch_couples[l]["bus_split"] == sw["bus_split"] # coupling the switch couple to their split bus
                        println("SWITCH COUPLE IS $l")
                            switch_t = deepcopy(input_dict["switch"]["$(switch_couples["$l"]["t_sw"])"]) 
                            aux_t = switch_t["auxiliary"]
                            orig_t = switch_t["original"]
                            println("Element $aux_t $orig_t")
                            if result_dict["switch"]["$(switch_t["index"])"]["status"] <= 0.1
                                println("Deleting switch $(switch_t["index"])")
                                delete!(input_ac_check["switch"],"$(switch_t["index"])")
                            elseif result_dict["switch"]["$(switch_t["index"])"]["status"] >= 0.9
                                if aux_t == "gen"
                                    input_ac_check["gen"]["$(orig_t)"]["gen_bus"] = deepcopy(input_dict["switch"]["$(switch_t["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                                    delete!(input_ac_check["bus"],input_ac_check["gen"]["$(orig_t)"]["gen_bus"])
                                    println("Element $aux_t $orig_t connected to $(input_ac_check["gen"]["$(orig_t)"]["gen_bus"])")
                                elseif aux_t == "load"
                                    input_ac_check["load"]["$(orig_t)"]["load_bus"] = deepcopy(input_dict["switch"]["$(switch_t["index"])"]["t_bus"])
                                    delete!(input_ac_check["bus"],input_ac_check["load"]["$(orig_t)"]["load_bus"])
                                    println("Element $aux_t $orig_t connected to $(input_ac_check["load"]["$(orig_t)"]["load_bus"])")
                                elseif aux_t == "convdc"
                                    input_ac_check["convdc"]["$(orig_t)"]["busac_i"] = deepcopy(input_dict["switch"]["$(switch_t["index"])"]["t_bus"])
                                    delete!(input_ac_check["bus"],input_ac_check["convdc"]["$(orig_t)"]["busac_i"])
                                    println("Element $aux_t $orig_t connected to $(input_ac_check["convdc"]["$(orig_t)"]["busac_i"])")
                                elseif aux_t == "branch" 
                                    if input_ac_check["branch"]["$(orig_t)"]["f_bus"] > orig_buses && input_dict["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"] # useful if both ends of a branch are busbars being split
                                        input_ac_check["branch"]["$(orig_t)"]["f_bus"] = deepcopy(input_dict["switch"]["$(switch_t["index"])"]["t_bus"])
                                        delete!(input_ac_check["bus"],input_ac_check["branch"]["$(orig_t)"]["f_bus"])
                                        println("Element $aux_t $orig_t connected to $(input_ac_check["branch"]["$(orig_t)"]["f_bus"])")
                                    elseif input_ac_check["branch"]["$(orig_t)"]["t_bus"] > orig_buses && input_dict["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                        input_ac_check["branch"]["$(orig_t)"]["t_bus"] = deepcopy(input_dict["switch"]["$(switch_t["index"])"]["t_bus"])
                                        delete!(input_ac_check["bus"],input_ac_check["branch"]["$(orig_t)"]["t_bus"])
                                        println("Element $aux_t $orig_t connected to $(input_ac_check["branch"]["$(orig_t)"]["t_bus"])")
                                    end
                                end
                            end
                        

                            switch_f = deepcopy(input_dict["switch"]["$(switch_couples["$l"]["f_sw"])"]) 
                            aux_f = switch_f["auxiliary"]
                            orig_f = switch_f["original"]
                            println("Element $aux_f $orig_f")
                            if result_dict["switch"]["$(switch_f["index"])"]["status"] <= 0.1
                                println("Deleting switch $(switch_f["index"])")
                                delete!(input_ac_check["switch"],"$(switch_f["index"])")
                            elseif result_dict["switch"]["$(switch_f["index"])"]["status"] >= 0.9
                                if aux_f == "gen"
                                    input_ac_check["gen"]["$(orig_f)"]["gen_bus"] = deepcopy(input_dict["switch"]["$(switch_f["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                                    delete!(input_ac_check["bus"],input_ac_check["gen"]["$(orig_f)"]["gen_bus"])
                                    println("Element $aux_f $orig_f connected to $(input_ac_check["gen"]["$(orig_f)"]["gen_bus"])")
                                elseif aux_f == "load"
                                    input_ac_check["load"]["$(orig_f)"]["load_bus"] = deepcopy(input_dict["switch"]["$(switch_f["index"])"]["t_bus"])
                                    delete!(input_ac_check["bus"],input_ac_check["load"]["$(orig_f)"]["load_bus"])
                                    println("Element $aux_f $orig_f connected to $(input_ac_check["load"]["$(orig_f)"]["load_bus"])")
                                elseif aux_f == "convdc"
                                    input_ac_check["convdc"]["$(orig_f)"]["busac_i"] = deepcopy(input_dict["switch"]["$(switch_f["index"])"]["t_bus"])
                                    delete!(input_ac_check["bus"],input_ac_check["convdc"]["$(orig_f)"]["busac_i"])
                                    println("Element $aux_f $orig_f connected to $(input_ac_check["convdc"]["$(orig_f)"]["busac_i"])")
                                elseif aux_f == "branch" 
                                    if input_ac_check["branch"]["$(orig_f)"]["f_bus"] > orig_buses && input_dict["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"] # useful if both ends of a branch are busbars being split
                                        input_ac_check["branch"]["$(orig_f)"]["f_bus"] = deepcopy(input_dict["switch"]["$(switch_f["index"])"]["t_bus"])
                                        delete!(input_ac_check["bus"],input_ac_check["branch"]["$(orig_f)"]["f_bus"])
                                        println("Element $aux_f $orig_f connected to $(input_ac_check["branch"]["$(orig_f)"]["f_bus"])")
                                    elseif input_ac_check["branch"]["$(orig_f)"]["t_bus"] > orig_buses && input_dict["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                        input_ac_check["branch"]["$(orig_f)"]["t_bus"] = deepcopy(input_dict["switch"]["$(switch_f["index"])"]["t_bus"])
                                        delete!(input_ac_check["bus"],input_ac_check["branch"]["$(orig_f)"]["t_bus"])
                                        println("Element $aux_f $orig_f connected to $(input_ac_check["branch"]["$(orig_f)"]["t_bus"])")
                                    end
                                end
                            end
                        #end
                    end
                end
            end
            input_ac_check["switch"] = Dict{String,Any}()
            input_ac_check["switch_couples"] = Dict{String,Any}()
        end
    end
end

grid_one_topology = Dict{String,Any}()
fc_one_topology_forecasted = run_feasibility_checks_per_hour_one_topology_fixing(grid_one_topology,fc_one_topology_test_case_bs_mn_forecasted,one_topology_forecasted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)


fc_one_topology_forecasted["1"]

fc_one_topology_test_case_bs_mn_forecasted["nw"]["1"]

function print_switch_results(result, grid, nw)
    switches = []
    for i in 1:length(grid["switch"])
        if !haskey(grid["switch"]["$i"],"auxiliary")
            push!(switches,result["solution"]["nw"]["$nw"]["switch"]["$i"]["status"])
            println(i," f_bus ",grid["switch"]["$i"]["f_bus"]," t_bus ",grid["switch"]["$i"]["t_bus"]," status ", result["solution"]["nw"]["$nw"]["switch"]["$i"]["status"])
        else
            push!(switches,result["solution"]["nw"]["$nw"]["switch"]["$i"]["status"])
            println(i," t_bus ",grid["switch"]["$i"]["t_bus"]," status ", result["solution"]["nw"]["$nw"]["switch"]["$i"]["status"]," auxiliary ", grid["switch"]["$i"]["auxiliary"], " original ", grid["switch"]["$i"]["original"])
        end
    end
    return switches
end
print_switch_results(one_topology_forecasted,test_case_bs,1)


grid_one_topology["1"]["gen"]["14"]["gen_bus"]

grid_one_topology["1"]["branch"]["11"]["f_bus"]
grid_one_topology["1"]["branch"]["11"]["t_bus"]

grid_one_topology["1"]["branch"]["12"]["f_bus"]
grid_one_topology["1"]["branch"]["12"]["t_bus"]

grid_one_topology["1"]["branch"]["9"]["f_bus"]
grid_one_topology["1"]["branch"]["9"]["t_bus"]

grid_one_topology["1"]["branch"]["10"]["f_bus"]
grid_one_topology["1"]["branch"]["10"]["t_bus"]

grid_one_topology["1"]["branch"]["6"]["f_bus"]
grid_one_topology["1"]["branch"]["6"]["t_bus"]

grid_one_topology["1"]["branch"]["41"]["f_bus"]
grid_one_topology["1"]["branch"]["41"]["t_bus"]

grid_one_topology["1"]["branch"]["7"]["f_bus"]
grid_one_topology["1"]["branch"]["7"]["t_bus"]





###################

sum(fc_one_sw_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_one_sw_average["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_one_sw_stochastic["$hour"]["objective"]*fc_one_sw_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(fc_one_sw_adjusted["$hour"]["objective"]*fc_one_sw_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(fc_one_sw_measured["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_two_sw_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_two_sw_average["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_two_sw_stochastic["$hour"]["objective"]*fc_two_sw_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(fc_two_sw_adjusted["$hour"]["objective"]*fc_two_sw_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(fc_two_sw_measured["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_one_topology_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_one_topology_average["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_one_topology_stochastic["$hour"]["objective"]*fc_one_topology_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(fc_one_topology_adjusted["$hour"]["objective"]*fc_one_topology_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(fc_one_topology_measured["$hour"]["objective"] for hour in 1:n_hours)
sum(hourly_fc_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(hourly_fc_average["$hour"]["objective"] for hour in 1:n_hours)
sum(hourly_fc_stochastic["$hour"]["objective"]*hourly_fc_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(hourly_fc_adjusted["$hour"]["objective"]*hourly_fc_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(hourly_fc_measured["$hour"]["objective"] for hour in 1:n_hours)

######################

sum(opf_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_one_sw_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_two_sw_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_one_topology_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(hourly_fc_forecasted["$hour"]["objective"] for hour in 1:n_hours)

sum(fc_one_sw_stochastic["$hour"]["objective"]*fc_one_sw_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(fc_two_sw_stochastic["$hour"]["objective"]*fc_two_sw_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(fc_one_topology_stochastic["$hour"]["objective"]*fc_one_topology_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(hourly_fc_stochastic["$hour"]["objective"]*hourly_fc_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))

sum(fc_one_sw_adjusted["$hour"]["objective"]*fc_one_sw_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(fc_two_sw_adjusted["$hour"]["objective"]*fc_two_sw_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(fc_one_topology_adjusted["$hour"]["objective"]*fc_one_topology_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(hourly_fc_adjusted["$hour"]["objective"]*hourly_fc_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))

sum(opf_measured["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_one_sw_measured["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_two_sw_measured["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_one_topology_measured["$hour"]["objective"] for hour in 1:n_hours)
sum(hourly_fc_measured["$hour"]["objective"] for hour in 1:n_hours)

sum(opf_average["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_one_sw_average["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_two_sw_average["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_one_topology_average["$hour"]["objective"] for hour in 1:n_hours)
sum(hourly_fc_average["$hour"]["objective"] for hour in 1:n_hours)




fc_one_topology_forecasted["1"]["solution"]["gen"]["1"]
fc_one_topology_average["1"]["solution"]["gen"]["1"]
fc_one_topology_stochastic["1"]["solution"]["gen"]["1"]
fc_one_topology_adjusted["1"]["solution"]["gen"]["1"]
fc_one_topology_measured["1"]["solution"]["gen"]["1"]

hourly_fc_measured["1"]["solution"]["gen"]["1"]
hourly_fc_forecasted["1"]["solution"]["gen"]["1"]
hourly_fc_average["1"]["solution"]["gen"]["1"]

##########################
# Saving results
json_fc_one_sw_forecasted       = JSON.json(fc_one_sw_forecasted      )
json_fc_one_sw_average          = JSON.json(fc_one_sw_average         )
json_fc_one_sw_stochastic       = JSON.json(fc_one_sw_stochastic      )
json_fc_one_sw_adjusted         = JSON.json(fc_one_sw_adjusted        )
json_fc_one_sw_measured         = JSON.json(fc_one_sw_measured        )
json_fc_two_sw_forecasted       = JSON.json(fc_two_sw_forecasted      )
json_fc_two_sw_average          = JSON.json(fc_two_sw_average         )
json_fc_two_sw_stochastic       = JSON.json(fc_two_sw_stochastic      )
json_fc_two_sw_adjusted         = JSON.json(fc_two_sw_adjusted        )
json_fc_two_sw_measured         = JSON.json(fc_two_sw_measured        )
json_fc_one_topology_forecasted = JSON.json(fc_one_topology_forecasted)
json_fc_one_topology_average    = JSON.json(fc_one_topology_average   )
json_fc_one_topology_stochastic = JSON.json(fc_one_topology_stochastic)
json_fc_one_topology_adjusted   = JSON.json(fc_one_topology_adjusted  )
json_fc_one_topology_measured   = JSON.json(fc_one_topology_measured  )
json_hourly_fc_forecasted       = JSON.json(hourly_fc_forecasted      )
json_hourly_fc_average          = JSON.json(hourly_fc_average         )
json_hourly_fc_stochastic       = JSON.json(hourly_fc_stochastic      )
json_hourly_fc_adjusted         = JSON.json(hourly_fc_adjusted        )
json_hourly_fc_measured         = JSON.json(hourly_fc_measured        )


open(joinpath(results_folder,case,"fc_one_sw_forecasted_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_fc_one_sw_forecasted) 
end 

open(joinpath(results_folder,case,"fc_one_sw_average_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_fc_one_sw_average) 
end 

open(joinpath(results_folder,case,"fc_one_sw_stochastic_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_fc_one_sw_stochastic) 
end 

open(joinpath(results_folder,case,"fc_one_sw_adjusted_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_fc_one_sw_adjusted) 
end 

open(joinpath(results_folder,case,"fc_one_sw_measured_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_fc_one_sw_measured) 
end 

open(joinpath(results_folder,case,"fc_two_sw_forecasted_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_fc_two_sw_forecasted) 
end 

open(joinpath(results_folder,case,"fc_two_sw_average_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_fc_two_sw_average) 
end 

open(joinpath(results_folder,case,"fc_two_sw_stochastic_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_fc_two_sw_stochastic) 
end 

open(joinpath(results_folder,case,"fc_two_sw_adjusted_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_fc_two_sw_adjusted) 
end 

open(joinpath(results_folder,case,"fc_two_sw_measured_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_fc_two_sw_measured) 
end 

open(joinpath(results_folder,case,"fc_one_topology_forecasted_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_fc_one_topology_forecasted) 
end 

open(joinpath(results_folder,case,"fc_one_topology_average_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_fc_one_topology_average) 
end 

open(joinpath(results_folder,case,"fc_one_topology_stochastic_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_fc_one_topology_stochastic) 
end 

open(joinpath(results_folder,case,"fc_one_topology_adjusted_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_fc_one_topology_adjusted) 
end 

open(joinpath(results_folder,case,"fc_one_topology_measured_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_fc_one_topology_measured) 
end 

open(joinpath(results_folder,case,"hourly_fc_forecasted_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_hourly_fc_forecasted) 
end 

open(joinpath(results_folder,case,"hourly_fc_average_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_hourly_fc_average) 
end 

open(joinpath(results_folder,case,"hourly_fc_stochastic_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_hourly_fc_stochastic) 
end 

open(joinpath(results_folder,case,"hourly_fc_adjusted_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_hourly_fc_adjusted) 
end 

open(joinpath(results_folder,case,"hourly_fc_measured_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_hourly_fc_measured) 
end 





fc_one_topology_forecasted_fc = run_feasibility_checks_per_hour_one_topology(test_case_bs_mn_forecasted,one_topology_forecasted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
fc_one_topology_forecasted["1"]["objective"]


for (g_id,g) in test_case_opf["gen"]
    if haskey(hourly_bs_average["2"]["solution"]["gen"],g_id)
        println("Gen $g_id: ", hourly_bs_average["2"]["solution"]["gen"]["$g_id"]["pg"])
    end
end 

for (g_id,g) in test_case_opf["gen"]
    if haskey(hourly_fc_average["2"]["solution"]["gen"],g_id) && hourly_fc_average["2"]["solution"]["gen"][g_id]["pg"] > 0.001 
        println("Gen $g_id: ", hourly_fc_average["2"]["solution"]["gen"]["$g_id"]["pg"])
    end
end 

[hourly_fc_forecasted["$hour"]["objective"] for hour in 1:n_hours]
[fc_one_topology_forecasted["$hour"]["objective"] for hour in 1:n_hours]
[fc_one_sw_forecasted["$hour"]["objective"] for hour in 1:n_hours]
[fc_two_sw_forecasted["$hour"]["objective"] for hour in 1:n_hours]


fc_one_topology_forecasted["1"]