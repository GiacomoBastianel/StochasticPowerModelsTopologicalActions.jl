using PowerModels; const _PM = PowerModels
using PowerModelsACDC; const _PMACDC = PowerModelsACDC
import PowerModelsTopologicalActionsII; const _PMTP = PowerModelsTopologicalActionsII
using FlexPlan; const _FP = FlexPlan
using Gurobi, Ipopt, JSON, Plots
import StochasticPowerModelsTopologicalActions; const _SPMTA = StochasticPowerModelsTopologicalActions
using JuMP, Juniper, HSL_jll, MathOptInterface, HiGHS
using Statistics

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
average_wind = JSON.parsefile(joinpath(input_folder,"case30","average_wind_$(first_hour)_$(last_hour)_modified.json"))
forecasted_wind = JSON.parsefile(joinpath(input_folder,"case30","forecasted_wind_hours_$(first_hour)_$(last_hour)_modified.json"))
scenario_wind_4 = JSON.parsefile(joinpath(input_folder,"case30","scenario_wind_4_$(first_hour)_$(last_hour)_modified.json"))
scenario_wind_4_adjusted = JSON.parsefile(joinpath(input_folder,"case30","scenario_wind_4_$(first_hour)_$(last_hour)_adjusted.json"))
scenario_wind_8 = JSON.parsefile(joinpath(input_folder,"case30","scenario_wind_8_$(first_hour)_$(last_hour)_modified.json"))

plot(measured_wind,label = "Measured")
plot!(average_wind, label = "Average Measured-Forecasted")
plot!(forecasted_wind, label = "Forecasted")

measured_wind_gen_1 = measured_wind*test_case_opf["gen"]["1"]["pmax"]
average_wind_gen_1 = average_wind*test_case_opf["gen"]["1"]["pmax"]
forecasted_wind_gen_1 = forecasted_wind*test_case_opf["gen"]["1"]["pmax"]


# Uploading results
hourly_bs_forecasted  = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Hourly_bs_forecasted_$(first_hour)_$(last_hour).json"))
hourly_bs_measured    = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Hourly_bs_measured_$(first_hour)_$(last_hour).json"))
hourly_bs_average   = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Hourly_bs_average_$(first_hour)_$(last_hour).json"))
hourly_bs_scenarios_4 = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Hourly_bs_stochastic_4_scenarios_$(first_hour)_$(last_hour).json"))
hourly_bs_scenarios_4_adjusted = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Hourly_bs_stochastic_4_scenarios_adjusted_$(first_hour)_$(last_hour).json"))

one_topology_forecasted  = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","24_hours_BS_one_topology_forecasted_$(first_hour)_$(last_hour).json"))
one_topology_measured    = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","24_hours_BS_one_topology_measured_$(first_hour)_$(last_hour).json"))
one_topology_average     = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","24_hours_BS_one_topology_average_$(first_hour)_$(last_hour).json"))
one_topology_scenarios_4 = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","24_hours_BS_one_topology_stochastic_4_scenarios_$(first_hour)_$(last_hour).json"))
one_topology_scenarios_4_adjusted = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","24_hours_BS_one_topology_adjusted_4_scenarios_$(first_hour)_$(last_hour).json"))

one_switching_action_forecasted  = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","One_maximum_actions_24_hours_forecasted_$(first_hour)_$(last_hour).json"))
one_switching_action_measured    = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","One_maximum_actions_24_hours_measured_$(first_hour)_$(last_hour).json"))
one_switching_action_average     = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","One_maximum_actions_24_hours_average_$(first_hour)_$(last_hour).json"))
one_switching_action_scenarios_4 = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","One_maximum_actions_24_hours_stochastic_4_scenarios_$(first_hour)_$(last_hour).json"))
one_switching_action_scenarios_4_adjusted = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","One_maximum_actions_24_hours_adjusted_$(first_hour)_$(last_hour).json"))

two_switching_action_forecasted  = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Two_maximum_actions_24_hours_forecasted_$(first_hour)_$(last_hour).json"))
two_switching_action_measured    = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Two_maximum_actions_24_hours_measured_$(first_hour)_$(last_hour).json"))
two_switching_action_average     = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Two_maximum_actions_24_hours_average_$(first_hour)_$(last_hour).json"))
two_switching_action_scenarios_4 = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Two_maximum_actions_24_hours_stochastic_4_scenarios_$(first_hour)_$(last_hour).json"))
two_switching_action_scenarios_4_adjusted = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Two_maximum_actions_24_hours_adjusted_$(first_hour)_$(last_hour).json"))




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

switches_one_topology_forecasted = print_switch_results(one_topology_forecasted, test_case_bs, 1)
switches_one_topology_measured = print_switch_results(one_topology_measured, test_case_bs, 1)
switches_one_topology_average  = print_switch_results(one_topology_average , test_case_bs, 1)
switches_one_topology_scenarios_4 = print_switch_results(one_topology_scenarios_4, test_case_bs, 1)
switches_one_topology_scenarios_4_adjusted = print_switch_results(one_topology_scenarios_4_adjusted, test_case_bs, 1)

switches_one_topology_forecasted
switches_one_topology_measured
switches_one_topology_average
switches_one_topology_scenarios_4
switches_one_topology_scenarios_4_adjusted



#######################

test_case_bs = deepcopy(test_case_opf)
splitted_bus_ac = 6
test_case_bs,  switches_couples_ac,  extremes_ZILs_ac  = _PMTP.AC_busbar_split_AC_grid(test_case,splitted_bus_ac)

# Adding costs to the busbar couplers
for sw_id in 1:length(extremes_ZILs_ac)
    test_case_bs["switch"]["$sw_id"]["cost"] = 10.0
end

n_hours = 24
n_scenarios = 4
one_scenario = 1

#########################################################################################

test_case_bs_replicate = _PM.replicate(test_case_bs, n_hours*n_scenarios)
test_case_bs_replicate_one_scenario = _PM.replicate(test_case_bs, n_hours*one_scenario)

test_case_bs_mn_measured = deepcopy(test_case_bs_replicate_one_scenario)
test_case_bs_mn_forecasted = deepcopy(test_case_bs_replicate_one_scenario)
test_case_bs_mn_average  = deepcopy(test_case_bs_replicate_one_scenario)

test_case_bs_mn_expected = deepcopy(test_case_bs_replicate)
test_case_bs_mn_adjusted = deepcopy(test_case_bs_replicate)

_SPMTA.adding_multinetwork_scenarios(test_case_bs_mn_measured,n_hours,one_scenario,scenario_wind_4)
_SPMTA.adding_multinetwork_scenarios(test_case_bs_mn_forecasted,n_hours,one_scenario,scenario_wind_4)
_SPMTA.adding_multinetwork_scenarios(test_case_bs_mn_average,n_hours,one_scenario,scenario_wind_4)
_SPMTA.adding_multinetwork_scenarios(test_case_bs_mn_expected,n_hours,n_scenarios,scenario_wind_4)
_SPMTA.adding_multinetwork_scenarios(test_case_bs_mn_adjusted,n_hours,n_scenarios,scenario_wind_4_adjusted)

# SOMETHING FISHY IS HAPPENING HERE
# ALL THE SIMULATIONS HAVE THE SAME RESULTS

for i in 1:(n_hours*one_scenario)
    test_case_bs_mn_measured["nw"]["$i"]["gen"]["1"]["pmax"]   = deepcopy(test_case_bs_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*measured_wind[i])
    test_case_bs_mn_forecasted["nw"]["$i"]["gen"]["1"]["pmax"] = deepcopy(test_case_bs_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*forecasted_wind[i])
    test_case_bs_mn_average["nw"]["$i"]["gen"]["1"]["pmax"] = deepcopy(test_case_bs_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*average_wind[i])
end
for i in 1:(n_hours*n_scenarios)
    test_case_bs_mn_expected["nw"]["$i"]["gen"]["1"]["pmax"]   = deepcopy(test_case_bs_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*scenario_wind_4["$i"]["samples_pu"])
    test_case_bs_mn_adjusted["nw"]["$i"]["gen"]["1"]["pmax"]   = deepcopy(test_case_bs_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*scenario_wind_4_adjusted["$i"]["samples_pu"])
end

samples = [scenario_wind_4["$i"]["samples_pu"] for i in 1:(n_hours*n_scenarios)]

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

function run_feasibility_checks_per_hour_one_topology(grid, result_bs, model, optimizer,switches_couples_ac,extremes_ZILs_ac,test_case_opf,settings)
    result_feasibility_checks = Dict{String,Any}()
    for hour in 1:length(grid["nw"])
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

test_case_bs_mn_measured["nw"]["1"]["gen"]["1"]["pmax"]
test_case_bs_mn_forecasted["nw"]["1"]["gen"]["1"]["pmax"]



hourly_fc_measured = run_feasibility_checks_per_hour(test_case_bs_mn_measured,hourly_bs_measured,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
fc_one_topology_measured = run_feasibility_checks_per_hour_one_topology(test_case_bs_mn_measured,one_topology_measured,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
fc_one_sw_measured = run_feasibility_checks_per_hour_one_topology(test_case_bs_mn_measured,one_switching_action_measured,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
fc_two_sw_measured = run_feasibility_checks_per_hour_one_topology(test_case_bs_mn_measured,two_switching_action_measured,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)

hourly_fc_forecasted = run_feasibility_checks_per_hour(test_case_bs_mn_forecasted,hourly_bs_forecasted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
fc_one_topology_forecasted = run_feasibility_checks_per_hour_one_topology(test_case_bs_mn_forecasted,one_topology_forecasted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
fc_one_sw_forecasted = run_feasibility_checks_per_hour_one_topology(test_case_bs_mn_forecasted,one_switching_action_forecasted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
fc_two_sw_forecasted = run_feasibility_checks_per_hour_one_topology(test_case_bs_mn_forecasted,two_switching_action_forecasted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)

hourly_fc_average = run_feasibility_checks_per_hour(test_case_bs_mn_average,hourly_bs_average,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
fc_one_topology_average = run_feasibility_checks_per_hour_one_topology(test_case_bs_mn_average,one_topology_average,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
fc_one_sw_average = run_feasibility_checks_per_hour_one_topology(test_case_bs_mn_average,one_switching_action_average,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
fc_two_sw_average = run_feasibility_checks_per_hour_one_topology(test_case_bs_mn_average,two_switching_action_average,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)

# -> Use the stochastic version now
hourly_fc_stochastic = run_feasibility_checks_per_hour_stochastic(test_case_bs_mn_expected,hourly_bs_scenarios_4,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s,n_hours,n_scenarios)
fc_one_topology_stochastic = run_feasibility_checks_per_hour_stochastic(test_case_bs_mn_expected,one_topology_scenarios_4,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s,n_hours,n_scenarios)
fc_one_sw_stochastic = run_feasibility_checks_per_hour_stochastic(test_case_bs_mn_expected,one_switching_action_scenarios_4,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s,n_hours,n_scenarios)
fc_two_sw_stochastic = run_feasibility_checks_per_hour_stochastic(test_case_bs_mn_expected,two_switching_action_scenarios_4,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s,n_hours,n_scenarios)

hourly_fc_adjusted = run_feasibility_checks_per_hour_stochastic(test_case_bs_mn_adjusted,hourly_bs_scenarios_4_adjusted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s,n_hours,n_scenarios)
fc_one_topology_adjusted = run_feasibility_checks_per_hour_stochastic(test_case_bs_mn_adjusted,one_topology_scenarios_4_adjusted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s,n_hours,n_scenarios)
fc_one_sw_adjusted = run_feasibility_checks_per_hour_stochastic(test_case_bs_mn_adjusted,one_switching_action_scenarios_4_adjusted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s,n_hours,n_scenarios)
fc_two_sw_adjusted = run_feasibility_checks_per_hour_stochastic(test_case_bs_mn_adjusted,two_switching_action_scenarios_4_adjusted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s,n_hours,n_scenarios)

##################

opf_measured = run_hourly_opf(test_case_opf_mn_measured,ACPPowerModel,ipopt,n_hours)
sum(opf_measured["$hour"]["objective"] for hour in 1:n_hours)

opf_measured["1"]["solution"]["gen"]["1"]

######################

sum(fc_one_sw_stochastic["$hour"]["objective"] for hour in 1:(n_hours*n_scenarios)  )
sum(fc_one_sw_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))

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
fc_one_topology_forecasted_fc["1"]["solution"]["gen"]["1"]
fc_one_topology_forecasted["1"]["solution"]["gen"]["1"]