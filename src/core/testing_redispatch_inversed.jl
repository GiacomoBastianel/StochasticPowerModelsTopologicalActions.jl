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
n_hours = last_hour - first_hour + 1
one_scenario = 1

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

#########################################################################################
# Uploading time series
measured_wind = JSON.parsefile(joinpath(input_folder,"case30","measured_wind_$(first_hour)_$(last_hour)_modified.json"))
average_wind = JSON.parsefile(joinpath(input_folder,"case30","average_wind_$(first_hour)_$(last_hour)_modified.json"))
forecasted_wind = JSON.parsefile(joinpath(input_folder,"case30","forecasted_wind_hours_$(first_hour)_$(last_hour)_modified.json"))
scenario_wind_4 = JSON.parsefile(joinpath(input_folder,"case30","scenario_wind_4_$(first_hour)_$(last_hour)_modified.json"))
scenario_wind_4_adjusted = JSON.parsefile(joinpath(input_folder,"case30","scenario_wind_4_$(first_hour)_$(last_hour)_adjusted.json"))
scenario_wind_8 = JSON.parsefile(joinpath(input_folder,"case30","scenario_wind_8_$(first_hour)_$(last_hour)_modified.json"))

plot(forecasted_wind,label = "Measured",xticks = 1:1:24, grid = :none, color = :lightblue,ylims = (0,1.2), xlabel = "Hour", ylabel = "Offshore wind capacity factor [-]",legend = :topleft)
plot!(average_wind, label = "Average Measured-Forecasted", color = :green)
plot!(measured_wind, label = "Forecasted", color = :orange)

case_figures = "case_30"
savefig(joinpath(results_folder_figures,case_figures,"Time_series_$(first_hour)_$(last_hour)_meas_avg_for_inversed.svg"))
savefig(joinpath(results_folder_figures,case_figures,"Time_series_$(first_hour)_$(last_hour)_meas_avg_for_inversed.pdf"))


# Uploading results

hourly_opf_forecasted           = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Hourly_opf_forecasted_$(first_hour)_$(last_hour).json"))
hourly_opf_measured             = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Hourly_opf_measured_$(first_hour)_$(last_hour).json"))
hourly_opf_average              = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Hourly_opf_average_$(first_hour)_$(last_hour).json"))
hourly_opf_scenarios_4          = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Hourly_opf_stochastic_4_scenarios_$(first_hour)_$(last_hour).json"))
hourly_opf_scenarios_4_adjusted = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Hourly_opf_stochastic_4_scenarios_adjusted_$(first_hour)_$(last_hour).json"))

hourly_bs_forecasted           = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Hourly_bs_forecasted_$(first_hour)_$(last_hour).json"))
hourly_bs_measured             = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Hourly_bs_measured_$(first_hour)_$(last_hour).json"))
hourly_bs_average              = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Hourly_bs_average_$(first_hour)_$(last_hour).json"))
hourly_bs_scenarios_4          = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Hourly_bs_stochastic_4_scenarios_$(first_hour)_$(last_hour).json"))
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

# Uploading results fc
fc_one_sw_forecasted       = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","fc_one_sw_forecasted_$(first_hour)_$(last_hour).json"))
fc_one_sw_average          = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","fc_one_sw_average_$(first_hour)_$(last_hour).json"))
fc_one_sw_stochastic       = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","fc_one_sw_stochastic_$(first_hour)_$(last_hour).json"))
fc_one_sw_adjusted         = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","fc_one_sw_adjusted_$(first_hour)_$(last_hour).json"))
fc_one_sw_measured         = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","fc_one_sw_measured_$(first_hour)_$(last_hour).json"))
fc_two_sw_forecasted       = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","fc_two_sw_forecasted_$(first_hour)_$(last_hour).json"))
fc_two_sw_average          = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","fc_two_sw_average_$(first_hour)_$(last_hour).json"))
fc_two_sw_stochastic       = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","fc_two_sw_stochastic_$(first_hour)_$(last_hour).json"))
fc_two_sw_adjusted         = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","fc_two_sw_adjusted_$(first_hour)_$(last_hour).json"))
fc_two_sw_measured         = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","fc_two_sw_measured_$(first_hour)_$(last_hour).json"))
fc_one_topology_forecasted = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","fc_one_topology_forecasted_$(first_hour)_$(last_hour).json"))
fc_one_topology_average    = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","fc_one_topology_average_$(first_hour)_$(last_hour).json"))
fc_one_topology_stochastic = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","fc_one_topology_stochastic_$(first_hour)_$(last_hour).json"))
fc_one_topology_adjusted   = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","fc_one_topology_adjusted_$(first_hour)_$(last_hour).json"))
fc_one_topology_measured   = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","fc_one_topology_measured_$(first_hour)_$(last_hour).json"))
hourly_fc_forecasted       = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","hourly_fc_forecasted_$(first_hour)_$(last_hour).json"))
hourly_fc_average          = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","hourly_fc_average_$(first_hour)_$(last_hour).json"))
hourly_fc_stochastic       = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","hourly_fc_stochastic_$(first_hour)_$(last_hour).json"))
hourly_fc_adjusted         = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","hourly_fc_adjusted_$(first_hour)_$(last_hour).json"))
hourly_fc_measured         = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","hourly_fc_measured_$(first_hour)_$(last_hour).json"))


#######################

test_case_opf_replicate_one_scenario = _PM.replicate(test_case_opf, n_hours*one_scenario)
test_case_opf_mn_measured = deepcopy(test_case_opf_replicate_one_scenario)
_SPMTA.adding_multinetwork_scenarios(test_case_opf_mn_measured,n_hours,one_scenario,scenario_wind_4)

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

test_case_opf_replicate_one_scenario = _PM.replicate(test_case_opf, n_hours*one_scenario)
test_case_opf_mn_measured = deepcopy(test_case_opf_replicate_one_scenario)
test_case_opf_mn_forecasted = deepcopy(test_case_opf_replicate_one_scenario)
_SPMTA.adding_multinetwork_scenarios(test_case_opf_mn_measured,n_hours,one_scenario,scenario_wind_4)
_SPMTA.adding_multinetwork_scenarios(test_case_opf_mn_forecasted,n_hours,one_scenario,scenario_wind_4)


for i in 1:(n_hours*one_scenario)
    test_case_bs_mn_measured["nw"]["$i"]["gen"]["1"]["pmax"]   = deepcopy(test_case_bs_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*measured_wind[i])
    test_case_opf_mn_measured["nw"]["$i"]["gen"]["1"]["pmax"]   = deepcopy(test_case_bs_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*measured_wind[i])
    test_case_bs_mn_forecasted["nw"]["$i"]["gen"]["1"]["pmax"] = deepcopy(test_case_bs_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*forecasted_wind[i])
    test_case_bs_mn_average["nw"]["$i"]["gen"]["1"]["pmax"] = deepcopy(test_case_bs_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*average_wind[i])
    test_case_opf_mn_forecasted["nw"]["$i"]["gen"]["1"]["pmax"]   = deepcopy(test_case_bs_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*forecasted_wind[i])
end
for i in 1:(n_hours*n_scenarios)
    test_case_bs_mn_expected["nw"]["$i"]["gen"]["1"]["pmax"]   = deepcopy(test_case_bs_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*scenario_wind_4["$i"]["samples_pu"])
    test_case_bs_mn_adjusted["nw"]["$i"]["gen"]["1"]["pmax"]   = deepcopy(test_case_bs_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*scenario_wind_4_adjusted["$i"]["samples_pu"])
end

[test_case_bs_mn_forecasted["nw"]["$i"]["gen"]["1"]["pmax"] for i in 1:n_hours]
[test_case_opf_mn_forecasted["nw"]["$i"]["gen"]["1"]["pmax"] for i in 1:n_hours]

hourly_redispatch_measured = _SPMTA.run_hourly_redispatch_fc(test_case_bs_mn_forecasted,hourly_bs_measured,hourly_fc_measured,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
redispatch_one_topology_measured = _SPMTA.run_hourly_redispatch_one_topology_fc(test_case_bs_mn_forecasted,one_topology_measured,fc_one_topology_measured,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
redispatch_one_sw_measured = _SPMTA.run_hourly_redispatch_one_topology_fc(test_case_bs_mn_forecasted,one_switching_action_measured,fc_one_sw_measured,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
redispatch_two_sw_measured = _SPMTA.run_hourly_redispatch_one_topology_fc(test_case_bs_mn_forecasted,two_switching_action_measured,fc_two_sw_measured,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)

hourly_redispatch_forecasted = _SPMTA.run_hourly_redispatch_fc(test_case_bs_mn_forecasted,hourly_bs_forecasted,hourly_fc_forecasted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
redispatch_one_topology_forecasted = _SPMTA.run_hourly_redispatch_one_topology_fc(test_case_bs_mn_forecasted,one_topology_forecasted,fc_one_topology_forecasted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
redispatch_one_sw_forecasted = _SPMTA.run_hourly_redispatch_one_topology_fc(test_case_bs_mn_forecasted,one_switching_action_forecasted,fc_one_sw_forecasted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
redispatch_two_sw_forecasted = _SPMTA.run_hourly_redispatch_one_topology_fc(test_case_bs_mn_forecasted,two_switching_action_forecasted,fc_two_sw_forecasted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)

hourly_redispatch_average = _SPMTA.run_hourly_redispatch_fc(test_case_bs_mn_forecasted,hourly_bs_average,hourly_fc_average,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
redispatch_one_topology_average = _SPMTA.run_hourly_redispatch_one_topology_fc(test_case_bs_mn_forecasted,one_topology_average,fc_one_topology_average,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
redispatch_one_sw_average = _SPMTA.run_hourly_redispatch_one_topology_fc(test_case_bs_mn_forecasted,one_switching_action_average,fc_one_sw_average,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
redispatch_two_sw_average = _SPMTA.run_hourly_redispatch_one_topology_fc(test_case_bs_mn_forecasted,two_switching_action_average,fc_two_sw_average,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)

# -> Use the stochastic version now
hourly_redispatch_stochastic = _SPMTA.run_hourly_redispatch_stochastic_fc(test_case_bs_mn_forecasted,test_case_bs_mn_expected,hourly_bs_scenarios_4           ,hourly_fc_stochastic,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s,n_hours,n_scenarios)
redispatch_one_topology_stochastic = _SPMTA.run_hourly_redispatch_stochastic_fc(test_case_bs_mn_forecasted,test_case_bs_mn_expected,one_topology_scenarios_4  ,fc_one_topology_stochastic,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s,n_hours,n_scenarios)
redispatch_one_sw_stochastic = _SPMTA.run_hourly_redispatch_stochastic_fc(test_case_bs_mn_forecasted,test_case_bs_mn_expected,one_switching_action_scenarios_4,fc_one_sw_stochastic,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s,n_hours,n_scenarios)
redispatch_two_sw_stochastic = _SPMTA.run_hourly_redispatch_stochastic_fc(test_case_bs_mn_forecasted,test_case_bs_mn_expected,two_switching_action_scenarios_4,fc_two_sw_stochastic,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s,n_hours,n_scenarios)

hourly_redispatch_adjusted = _SPMTA.run_hourly_redispatch_stochastic_fc(test_case_bs_mn_forecasted,test_case_bs_mn_adjusted,hourly_bs_scenarios_4_adjusted,                    hourly_fc_adjusted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s,n_hours,n_scenarios)
redispatch_one_topology_adjusted = _SPMTA.run_hourly_redispatch_stochastic_fc(test_case_bs_mn_forecasted,test_case_bs_mn_adjusted,one_topology_scenarios_4_adjusted  ,fc_one_topology_adjusted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s,n_hours,n_scenarios)
redispatch_one_sw_adjusted = _SPMTA.run_hourly_redispatch_stochastic_fc(test_case_bs_mn_forecasted,test_case_bs_mn_adjusted,one_switching_action_scenarios_4_adjusted,fc_one_sw_adjusted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s,n_hours,n_scenarios)
redispatch_two_sw_adjusted = _SPMTA.run_hourly_redispatch_stochastic_fc(test_case_bs_mn_forecasted,test_case_bs_mn_adjusted,two_switching_action_scenarios_4_adjusted,fc_two_sw_adjusted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s,n_hours,n_scenarios)

####################
# -> OPF

function run_hourly_redispatch_opf(grid, result_opf, model, optimizer,settings)
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
            if length(g["cost"]) > 1
                g["redispatch_cost_up"] = g["cost"][1]
                g["redispatch_cost_down"] = g["cost"][1]
            elseif length(g["cost"]) <= 1
                g["redispatch_cost_up"] = 0.0
                g["redispatch_cost_down"] = 0.0
            end
            if g_id == "1"
                g["redispatch_cost_up"] = 10.0
                g["redispatch_cost_down"] = 10.0
                #println("Generator 1 has a cost up of $(g["redispatch_cost_up"])")
                #println("Generator 1 has a cost down of $(g["redispatch_cost_down"])")
            end
        end

        result_feasibility_checks["$hour"] = _SPMTA.solve_acdc_full_redispatch_opf(feasibility_check,model,optimizer)
    end
    return result_feasibility_checks
end

function run_hourly_redispatch_opf_stochastic(grid, stochastic_grid, result_opf, model, optimizer,settings)
    result_feasibility_checks = Dict{String,Any}()
    for hour in 1:n_hours
        for s in 1:n_scenarios
            # This has to include all the scenarios
            timestep = (hour - 1)*n_scenarios + s
            result_feasibility_checks["$timestep"] = Dict{String,Any}()
            feasibility_check = deepcopy(grid["nw"]["$hour"])
            feasibility_check_input = deepcopy(grid["nw"]["$hour"])
            # Adding set points
            for (g_id,g) in feasibility_check["gen"]
                g["pg_start"] = result_opf["$timestep"]["solution"]["gen"][g_id]["pg"]
                g["qg_start"] = result_opf["$timestep"]["solution"]["gen"][g_id]["qg"]
                if length(g["cost"]) > 1 
                    g["redispatch_cost_up"] = g["cost"][1]
                    g["redispatch_cost_down"] = g["cost"][1]
                elseif length(g["cost"]) < 1
                    g["redispatch_cost_up"] = 0.0
                    g["redispatch_cost_down"] = 0.0
                end
                if g_id == "1"
                    g["redispatch_cost_up"] = 10.0
                    g["redispatch_cost_down"] = 10.0
                    #println("Generator 1 has a cost up of $(g["redispatch_cost_up"])")
                    #println("Generator 1 has a cost down of $(g["redispatch_cost_down"])")
    
                end
            end
            result_feasibility_checks["$timestep"] = _SPMTA.solve_acdc_full_redispatch_opf(feasibility_check,model,optimizer)
            result_feasibility_checks["$timestep"]["probability"] = stochastic_grid["nw"]["$timestep"]["probability"]
        end
    end    
    return result_feasibility_checks
end

redispatch_opf_forecasted           = run_hourly_redispatch_opf(test_case_opf_mn_forecasted,hourly_opf_forecasted          ,ACPPowerModel,ipopt,s)
redispatch_opf_measured             = run_hourly_redispatch_opf(test_case_opf_mn_forecasted,hourly_opf_measured            ,ACPPowerModel,ipopt,s)
redispatch_opf_average              = run_hourly_redispatch_opf(test_case_opf_mn_forecasted,hourly_opf_average             ,ACPPowerModel,ipopt,s)
redispatch_opf_scenarios_4          = run_hourly_redispatch_opf_stochastic(test_case_opf_mn_forecasted,test_case_bs_mn_expected,hourly_opf_scenarios_4         ,ACPPowerModel,ipopt,s)
redispatch_opf_scenarios_4_adjusted = run_hourly_redispatch_opf_stochastic(test_case_opf_mn_forecasted,test_case_bs_mn_adjusted,hourly_opf_scenarios_4_adjusted,ACPPowerModel,ipopt,s)

[hourly_opf_measured["$h"]["solution"]["gen"]["1"]["pg"] for h in 1:12]
[hourly_opf_forecasted["$h"]["solution"]["gen"]["1"]["pg"] for h in 1:12]

[redispatch_opf_forecasted["$h"]["solution"]["gen"]["1"]["pg_up"] for h in 1:12]
[redispatch_opf_measured["$h"]["solution"]["gen"]["1"]["pg_up"] for h in 1:12]

[test_case_opf_mn_forecasted["nw"]["$h"]["gen"]["1"]["pmax"] for h in 1:n_hours]
[test_case_opf_mn_measured["nw"]["$h"]["gen"]["1"]["pmax"] for h in 1:n_hours]

test_case_bs_mn_forecasted["nw"]["1"]["gen"]["1"]["pmax"]

sum(redispatch_opf_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(redispatch_opf_measured["$hour"]["objective"] for hour in 1:n_hours)
sum(redispatch_opf_average["$hour"]["objective"] for hour in 1:n_hours)
sum(redispatch_opf_scenarios_4["$hour"]["objective"]*redispatch_one_sw_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(redispatch_opf_scenarios_4_adjusted["$hour"]["objective"]*redispatch_one_sw_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))

sum(redispatch_one_sw_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(redispatch_one_sw_average["$hour"]["objective"] for hour in 1:n_hours)
sum(redispatch_one_sw_stochastic["$hour"]["objective"]*redispatch_one_sw_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(redispatch_one_sw_adjusted["$hour"]["objective"]*redispatch_one_sw_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(redispatch_one_sw_measured["$hour"]["objective"] for hour in 1:n_hours)

sum(redispatch_two_sw_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(redispatch_two_sw_average["$hour"]["objective"] for hour in 1:n_hours)
sum(redispatch_two_sw_stochastic["$hour"]["objective"]*redispatch_two_sw_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(redispatch_two_sw_adjusted["$hour"]["objective"]*redispatch_two_sw_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(redispatch_two_sw_measured["$hour"]["objective"] for hour in 1:n_hours)

sum(redispatch_one_topology_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(redispatch_one_topology_average["$hour"]["objective"] for hour in 1:n_hours)
sum(redispatch_one_topology_stochastic["$hour"]["objective"]*redispatch_one_topology_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(redispatch_one_topology_adjusted["$hour"]["objective"]*redispatch_one_topology_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(redispatch_one_topology_measured["$hour"]["objective"] for hour in 1:n_hours)

sum(hourly_redispatch_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(hourly_redispatch_average["$hour"]["objective"] for hour in 1:n_hours)
sum(hourly_redispatch_stochastic["$hour"]["objective"]*hourly_redispatch_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(hourly_redispatch_adjusted["$hour"]["objective"]*hourly_redispatch_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(hourly_redispatch_measured["$hour"]["objective"] for hour in 1:n_hours)

#using StatsBase
#solutions = [redispatch_opf_scenarios_4_adjusted["$h"]["termination_status"] for h in 1:(n_hours*n_scenarios)]
#countmap(solutions)

################

sum(fc_one_sw_forecasted["$hour"]["objective"] for hour in 1:n_hours) + sum(redispatch_one_sw_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_one_sw_average["$hour"]["objective"] for hour in 1:n_hours) + sum(redispatch_one_sw_average["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_one_sw_stochastic["$hour"]["objective"]*fc_one_sw_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios)) + sum(redispatch_one_sw_stochastic["$hour"]["objective"]*redispatch_one_sw_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(fc_one_sw_adjusted["$hour"]["objective"]*fc_one_sw_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios)) + sum(redispatch_one_sw_adjusted["$hour"]["objective"]*redispatch_one_sw_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(fc_one_sw_measured["$hour"]["objective"] for hour in 1:n_hours) + sum(redispatch_one_sw_measured["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_two_sw_forecasted["$hour"]["objective"] for hour in 1:n_hours) + sum(redispatch_two_sw_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_two_sw_average["$hour"]["objective"] for hour in 1:n_hours) + sum(redispatch_two_sw_average["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_two_sw_stochastic["$hour"]["objective"]*fc_two_sw_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios)) + sum(redispatch_two_sw_stochastic["$hour"]["objective"]*redispatch_two_sw_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(fc_two_sw_adjusted["$hour"]["objective"]*fc_two_sw_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios)) + sum(redispatch_two_sw_adjusted["$hour"]["objective"]*redispatch_two_sw_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(fc_two_sw_measured["$hour"]["objective"] for hour in 1:n_hours) + sum(redispatch_two_sw_measured["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_one_topology_forecasted["$hour"]["objective"] for hour in 1:n_hours) + sum(redispatch_one_topology_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_one_topology_average["$hour"]["objective"] for hour in 1:n_hours) + sum(redispatch_one_topology_average["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_one_topology_stochastic["$hour"]["objective"]*fc_one_topology_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios)) + sum(redispatch_one_topology_stochastic["$hour"]["objective"]*redispatch_one_topology_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(fc_one_topology_adjusted["$hour"]["objective"]*fc_one_topology_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios)) + sum(redispatch_one_topology_adjusted["$hour"]["objective"]*redispatch_one_topology_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(fc_one_topology_measured["$hour"]["objective"] for hour in 1:n_hours) + sum(redispatch_one_topology_measured["$hour"]["objective"] for hour in 1:n_hours)
sum(hourly_fc_forecasted["$hour"]["objective"] for hour in 1:n_hours) + sum(hourly_redispatch_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(hourly_fc_average["$hour"]["objective"] for hour in 1:n_hours) + sum(hourly_redispatch_average["$hour"]["objective"] for hour in 1:n_hours)
sum(hourly_fc_stochastic["$hour"]["objective"]*hourly_fc_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios)) + sum(hourly_redispatch_stochastic["$hour"]["objective"]*hourly_redispatch_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(hourly_fc_adjusted["$hour"]["objective"]*hourly_fc_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios)) + sum(hourly_redispatch_adjusted["$hour"]["objective"]*hourly_redispatch_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(hourly_fc_measured["$hour"]["objective"] for hour in 1:n_hours) + sum(hourly_redispatch_measured["$hour"]["objective"] for hour in 1:n_hours)
sum(hourly_opf_forecasted["$hour"]["objective"] for hour in 1:n_hours) + sum(redispatch_opf_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(hourly_opf_measured["$hour"]["objective"] for hour in 1:n_hours) + sum(redispatch_opf_measured["$hour"]["objective"] for hour in 1:n_hours)
sum(hourly_opf_average["$hour"]["objective"] for hour in 1:n_hours) + sum(redispatch_opf_average["$hour"]["objective"] for hour in 1:n_hours)
sum(hourly_opf_scenarios_4["$hour"]["objective"]*hourly_redispatch_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios)) + sum(redispatch_opf_scenarios_4["$hour"]["objective"]*hourly_redispatch_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(hourly_opf_scenarios_4_adjusted["$hour"]["objective"] *hourly_redispatch_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios)) + sum(redispatch_opf_scenarios_4_adjusted["$hour"]["objective"]*hourly_redispatch_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))

###########################################


sum(hourly_opf_forecasted["$hour"]["objective"] for hour in 1:n_hours)      #+ sum(redispatch_opf_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_one_sw_forecasted["$hour"]["objective"] for hour in 1:n_hours)       #+ sum(redispatch_one_sw_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_two_sw_forecasted["$hour"]["objective"] for hour in 1:n_hours)       #+ sum(redispatch_two_sw_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_one_topology_forecasted["$hour"]["objective"] for hour in 1:n_hours) #+ sum(redispatch_one_topology_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(hourly_fc_forecasted["$hour"]["objective"] for hour in 1:n_hours)       #+ sum(hourly_redispatch_forecasted["$hour"]["objective"] for hour in 1:n_hours)

sum(hourly_opf_measured["$hour"]["objective"] for hour in 1:n_hours)      #+ sum(redispatch_opf_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_one_sw_measured["$hour"]["objective"] for hour in 1:n_hours)       #+ sum(redispatch_one_sw_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_two_sw_measured["$hour"]["objective"] for hour in 1:n_hours)       #+ sum(redispatch_two_sw_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_one_topology_measured["$hour"]["objective"] for hour in 1:n_hours) #+ sum(redispatch_one_topology_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(hourly_fc_measured["$hour"]["objective"] for hour in 1:n_hours)       #+ sum(hourly_redispatch_forecasted["$hour"]["objective"] for hour in 1:n_hours)


sum(hourly_opf_average["$hour"]["objective"] for hour in 1:n_hours)         #+ sum(redispatch_opf_average["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_one_sw_average["$hour"]["objective"] for hour in 1:n_hours)          #+ sum(redispatch_one_sw_average["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_two_sw_average["$hour"]["objective"] for hour in 1:n_hours)          #+ sum(redispatch_two_sw_average["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_one_topology_average["$hour"]["objective"] for hour in 1:n_hours)    #+ sum(redispatch_one_topology_average["$hour"]["objective"] for hour in 1:n_hours)
sum(hourly_fc_average["$hour"]["objective"] for hour in 1:n_hours)          #+ sum(hourly_redispatch_average["$hour"]["objective"] for hour in 1:n_hours)

sum(hourly_opf_scenarios_4["$hour"]["objective"]*hourly_redispatch_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))     #+ sum(redispatch_opf_scenarios_4["$hour"]["objective"]*hourly_redispatch_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(fc_one_sw_stochastic["$hour"]["objective"]*fc_one_sw_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))             #+ sum(redispatch_one_sw_stochastic["$hour"]["objective"]*redispatch_one_sw_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(fc_two_sw_stochastic["$hour"]["objective"]*fc_two_sw_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))             #+ sum(redispatch_two_sw_stochastic["$hour"]["objective"]*redispatch_two_sw_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(fc_one_topology_stochastic["$hour"]["objective"]*fc_one_topology_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios)) #+ sum(redispatch_one_topology_stochastic["$hour"]["objective"]*redispatch_one_topology_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(hourly_fc_stochastic["$hour"]["objective"]*hourly_fc_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))             #+ sum(hourly_redispatch_stochastic["$hour"]["objective"]*hourly_redispatch_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))

sum(hourly_opf_scenarios_4_adjusted["$hour"]["objective"] *hourly_redispatch_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios)) #+ sum(redispatch_opf_scenarios_4_adjusted["$hour"]["objective"]*hourly_redispatch_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(fc_one_sw_adjusted["$hour"]["objective"]*fc_one_sw_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))                         #+ sum(redispatch_one_sw_adjusted["$hour"]["objective"]*redispatch_one_sw_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(fc_two_sw_adjusted["$hour"]["objective"]*fc_two_sw_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))                         #+ sum(redispatch_two_sw_adjusted["$hour"]["objective"]*redispatch_two_sw_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(fc_one_topology_adjusted["$hour"]["objective"]*fc_one_topology_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))             #+ sum(redispatch_one_topology_adjusted["$hour"]["objective"]*redispatch_one_topology_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(hourly_fc_adjusted["$hour"]["objective"]*hourly_fc_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))                         #+ sum(hourly_redispatch_adjusted["$hour"]["objective"]*hourly_redispatch_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))


###########################################

sum(hourly_opf_forecasted["$hour"]["objective"] for hour in 1:n_hours) + sum(redispatch_opf_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_one_sw_forecasted["$hour"]["objective"] for hour in 1:n_hours) + sum(redispatch_one_sw_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_two_sw_forecasted["$hour"]["objective"] for hour in 1:n_hours) + sum(redispatch_two_sw_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_one_topology_forecasted["$hour"]["objective"] for hour in 1:n_hours) + sum(redispatch_one_topology_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(hourly_fc_forecasted["$hour"]["objective"] for hour in 1:n_hours) + sum(hourly_redispatch_forecasted["$hour"]["objective"] for hour in 1:n_hours)

sum(hourly_opf_measured["$hour"]["objective"] for hour in 1:n_hours) + sum(redispatch_opf_measured["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_one_sw_measured["$hour"]["objective"] for hour in 1:n_hours) + sum(redispatch_one_sw_measured["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_two_sw_measured["$hour"]["objective"] for hour in 1:n_hours) + sum(redispatch_two_sw_measured["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_one_topology_measured["$hour"]["objective"] for hour in 1:n_hours) + sum(redispatch_one_topology_measured["$hour"]["objective"] for hour in 1:n_hours)
sum(hourly_fc_measured["$hour"]["objective"] for hour in 1:n_hours) + sum(hourly_redispatch_measured["$hour"]["objective"] for hour in 1:n_hours)

sum(hourly_opf_average["$hour"]["objective"] for hour in 1:n_hours) + sum(redispatch_opf_average["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_one_sw_average["$hour"]["objective"] for hour in 1:n_hours) + sum(redispatch_one_sw_average["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_two_sw_average["$hour"]["objective"] for hour in 1:n_hours) + sum(redispatch_two_sw_average["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_one_topology_average["$hour"]["objective"] for hour in 1:n_hours) + sum(redispatch_one_topology_average["$hour"]["objective"] for hour in 1:n_hours)
sum(hourly_fc_average["$hour"]["objective"] for hour in 1:n_hours) + sum(hourly_redispatch_average["$hour"]["objective"] for hour in 1:n_hours)

sum(hourly_opf_scenarios_4["$hour"]["objective"]*hourly_redispatch_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios)) + sum(redispatch_opf_scenarios_4["$hour"]["objective"]*hourly_redispatch_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(fc_one_sw_stochastic["$hour"]["objective"]*fc_one_sw_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios)) + sum(redispatch_one_sw_stochastic["$hour"]["objective"]*redispatch_one_sw_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(fc_two_sw_stochastic["$hour"]["objective"]*fc_two_sw_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios)) + sum(redispatch_two_sw_stochastic["$hour"]["objective"]*redispatch_two_sw_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(fc_one_topology_stochastic["$hour"]["objective"]*fc_one_topology_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios)) + sum(redispatch_one_topology_stochastic["$hour"]["objective"]*redispatch_one_topology_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(hourly_fc_stochastic["$hour"]["objective"]*hourly_fc_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios)) + sum(hourly_redispatch_stochastic["$hour"]["objective"]*hourly_redispatch_stochastic["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))

sum(hourly_opf_scenarios_4_adjusted["$hour"]["objective"]*hourly_redispatch_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios)) + sum(redispatch_opf_scenarios_4_adjusted["$hour"]["objective"]*hourly_redispatch_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(fc_one_sw_adjusted["$hour"]["objective"]*fc_one_sw_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios)) + sum(redispatch_one_sw_adjusted["$hour"]["objective"]*redispatch_one_sw_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(fc_two_sw_adjusted["$hour"]["objective"]*fc_two_sw_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios)) + sum(redispatch_two_sw_adjusted["$hour"]["objective"]*redispatch_two_sw_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(fc_one_topology_adjusted["$hour"]["objective"]*fc_one_topology_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios)) + sum(redispatch_one_topology_adjusted["$hour"]["objective"]*redispatch_one_topology_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))
sum(hourly_fc_adjusted["$hour"]["objective"]*hourly_fc_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios)) + sum(hourly_redispatch_adjusted["$hour"]["objective"]*hourly_redispatch_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))


sum(redispatch_opf_scenarios_4_adjusted["$hour"]["objective"] for hour in 1:(n_hours*n_scenarios))
sum(redispatch_opf_scenarios_4_adjusted["$hour"]["objective"]*hourly_redispatch_adjusted["$hour"]["probability"] for hour in 1:(n_hours*n_scenarios))

objs = [redispatch_opf_scenarios_4_adjusted["$hour"]["objective"] for hour in 1:(n_hours*n_scenarios)]


[redispatch_opf_forecasted["$h"]["solution"]["gen"]["1"]["pg_up"] for h in 1:(n_hours)]
[redispatch_opf_measured["$h"]["solution"]["gen"]["1"]["pg_up"] for h in 1:(n_hours)]
[redispatch_opf_average["$h"]["solution"]["gen"]["1"]["pg_up"] for h in 1:(n_hours)]
[redispatch_opf_scenarios_4["$h"]["solution"]["gen"]["1"]["pg_up"] for h in 1:(n_hours*n_scenarios)]
[redispatch_opf_scenarios_4_adjusted["$h"]["solution"]["gen"]["1"]["pg_up"] for h in 1:(n_hours*n_scenarios)]

[redispatch_opf_forecasted["$h"]["solution"]["gen"]["1"]["pg_down"] for h in 1:(n_hours)]
[redispatch_opf_measured["$h"]["solution"]["gen"]["1"]["pg_down"] for h in 1:(n_hours)]
[redispatch_opf_average["$h"]["solution"]["gen"]["1"]["pg_down"] for h in 1:(n_hours)]
[redispatch_opf_scenarios_4["$h"]["solution"]["gen"]["1"]["pg_down"] for h in 1:(n_hours*n_scenarios)]
[redispatch_opf_scenarios_4_adjusted["$h"]["solution"]["gen"]["1"]["pg_down"] for h in 1:(n_hours*n_scenarios)]

######################################################

function print_gen_redispatch(grid,results,n_hours)
    for hour in 1:n_hours
        println("------------------------")
        println("Hour: $hour")
        println("Objective: $(results["$hour"]["objective"])")
        println("------------------------")
        for (g_id,g) in grid["gen"]
            if results["$hour"]["solution"]["gen"][g_id]["pg_up"] > 10^(-4)
                println("Generator $g_id: pg_up = $(results["$hour"]["solution"]["gen"][g_id]["pg_up"])")
            end
            if results["$hour"]["solution"]["gen"][g_id]["pg_down"] > 10^(-4)
                println("Generator $g_id: pg_down = $(results["$hour"]["solution"]["gen"][g_id]["pg_down"])")
            end
        end
    end
end

print_gen_redispatch(test_case_opf,redispatch_opf_forecasted,1)
print_gen_redispatch(test_case_opf,redispatch_one_sw_forecasted,1)
print_gen_redispatch(test_case_opf,hourly_redispatch_forecasted,1)
print_gen_redispatch(test_case_opf,redispatch_one_topology_forecasted,1)


fc_one_sw_forecasted["1"]["solution"]["gen"]["1"]["pg"]
hourly_opf_forecasted["1"]["solution"]["gen"]["1"]["pg"]
forecasted_wind[1]*test_case_opf["gen"]["1"]["pmax"]

redispatch_opf_forecasted["1"]["solution"]["gen"]["1"]["pg_down"]
fc_one_sw_forecasted["1"]["solution"]["gen"]["1"]["pg"] - redispatch_one_sw_forecasted["1"]["solution"]["gen"]["1"]["pg_down"]