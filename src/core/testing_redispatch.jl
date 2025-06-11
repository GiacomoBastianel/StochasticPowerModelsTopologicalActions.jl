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

#########################################################################################
# Uploading time series
measured_wind = JSON.parsefile(joinpath(input_folder,"case30","measured_wind_$(first_hour)_$(last_hour)_modified.json"))
average_wind = JSON.parsefile(joinpath(input_folder,"case30","average_wind_$(first_hour)_$(last_hour)_modified.json"))
forecasted_wind = JSON.parsefile(joinpath(input_folder,"case30","forecasted_wind_hours_$(first_hour)_$(last_hour)_modified.json"))
scenario_wind_4 = JSON.parsefile(joinpath(input_folder,"case30","scenario_wind_4_$(first_hour)_$(last_hour)_modified.json"))
scenario_wind_4_adjusted = JSON.parsefile(joinpath(input_folder,"case30","scenario_wind_4_$(first_hour)_$(last_hour)_adjusted.json"))
scenario_wind_8 = JSON.parsefile(joinpath(input_folder,"case30","scenario_wind_8_$(first_hour)_$(last_hour)_modified.json"))

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


for i in 1:(n_hours*one_scenario)
    test_case_bs_mn_measured["nw"]["$i"]["gen"]["1"]["pmax"]   = deepcopy(test_case_bs_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*measured_wind[i])
    test_case_bs_mn_forecasted["nw"]["$i"]["gen"]["1"]["pmax"] = deepcopy(test_case_bs_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*forecasted_wind[i])
    test_case_bs_mn_average["nw"]["$i"]["gen"]["1"]["pmax"] = deepcopy(test_case_bs_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*average_wind[i])
end
for i in 1:(n_hours*n_scenarios)
    test_case_bs_mn_expected["nw"]["$i"]["gen"]["1"]["pmax"]   = deepcopy(test_case_bs_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*scenario_wind_4["$i"]["samples_pu"])
    test_case_bs_mn_adjusted["nw"]["$i"]["gen"]["1"]["pmax"]   = deepcopy(test_case_bs_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*scenario_wind_4_adjusted["$i"]["samples_pu"])
end

hourly_redispatch = _SPMTA.run_hourly_redispatch(test_case_bs_mn_measured,hourly_bs_forecasted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
redispatch_one_topology = _SPMTA.run_hourly_redispatch_one_topology(test_case_bs_mn_measured,one_topology_forecasted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
redispatch_one_sw = _SPMTA.run_hourly_redispatch_one_topology(test_case_bs_mn_measured,one_switching_action_forecasted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
redispatch_two_sw = _SPMTA.run_hourly_redispatch_one_topology(test_case_bs_mn_measured,two_switching_action_forecasted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)

hourly_redispatch_average = _SPMTA.run_hourly_redispatch(test_case_bs_mn_average,hourly_bs_average,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
redispatch_one_topology_average = _SPMTA.run_hourly_redispatch_one_topology(test_case_bs_mn_average,one_topology_average,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
redispatch_one_sw_average = _SPMTA.run_hourly_redispatch_one_topology(test_case_bs_mn_average,one_switching_action_average,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
redispatch_two_sw_average = _SPMTA.run_hourly_redispatch_one_topology(test_case_bs_mn_average,two_switching_action_average,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)

# -> Use the stochastic version now
hourly_redispatch_stochastic = _SPMTA.run_hourly_redispatch_scenarios(test_case_bs_mn_measured,hourly_bs_scenarios_4,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s,n_hours,n_scenarios)
redispatch_one_topology_stochastic = _SPMTA.run_hourly_redispatch_scenarios(test_case_bs_mn_measured,one_topology_scenarios_4,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s,n_hours,n_scenarios)
redispatch_one_sw_stochastic = _SPMTA.run_hourly_redispatch_scenarios(test_case_bs_mn_measured,one_switching_action_scenarios_4,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s,n_hours,n_scenarios)
redispatch_two_sw_stochastic = _SPMTA.run_hourly_redispatch_scenarios(test_case_bs_mn_measured,two_switching_action_scenarios_4,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s,n_hours,n_scenarios)

#hourly_redispatch_adjusted = _SPMTA.run_hourly_redispatch_scenarios(test_case_bs_mn_adjusted,hourly_bs_scenarios_4,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s,n_hours,n_scenarios)
redispatch_one_topology_adjusted = _SPMTA.run_hourly_redispatch_scenarios(test_case_bs_mn_adjusted,one_topology_scenarios_4_adjusted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s,n_hours,n_scenarios)
redispatch_one_sw_adjusted = _SPMTA.run_hourly_redispatch_scenarios(test_case_bs_mn_adjusted,one_switching_action_scenarios_4_adjusted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s,n_hours,n_scenarios)
redispatch_two_sw_adjusted = _SPMTA.run_hourly_redispatch_scenarios(test_case_bs_mn_adjusted,two_switching_action_scenarios_4_adjusted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s,n_hours,n_scenarios)


sum(redispatch_one_sw["$hour"]["objective"] for hour in 1:n_hours)
sum(redispatch_one_sw_average["$hour"]["objective"] for hour in 1:n_hours)
sum(redispatch_one_sw_stochastic["$hour"]["objective"] for hour in 1:n_hours)
sum(redispatch_one_sw_adjusted["$hour"]["objective"] for hour in 1:n_hours)

sum(redispatch_two_sw["$hour"]["objective"] for hour in 1:n_hours)
sum(redispatch_two_sw_average["$hour"]["objective"] for hour in 1:n_hours)
sum(redispatch_two_sw_stochastic["$hour"]["objective"] for hour in 1:n_hours)
sum(redispatch_two_sw_adjusted["$hour"]["objective"] for hour in 1:n_hours)

sum(redispatch_one_topology["$hour"]["objective"] for hour in 1:n_hours)
sum(redispatch_one_topology_average["$hour"]["objective"] for hour in 1:n_hours)
sum(redispatch_one_topology_stochastic["$hour"]["objective"] for hour in 1:n_hours)
sum(redispatch_one_topology_adjusted["$hour"]["objective"] for hour in 1:n_hours)

sum(hourly_redispatch["$hour"]["objective"] for hour in 1:n_hours)
sum(hourly_redispatch_average["$hour"]["objective"] for hour in 1:n_hours)
sum(hourly_redispatch_stochastic["$hour"]["objective"] for hour in 1:n_hours)
sum(hourly_redispatch_adjusted["$hour"]["objective"] for hour in 1:n_hours)


_SPMTA.print_gen_redispatch(test_case_opf,redispatch_one_topology,n_hours)
_SPMTA.print_gen_redispatch(test_case_opf,redispatch_one_sw,n_hours)
_SPMTA.print_gen_redispatch(test_case_opf,redispatch_two_sw,n_hours)

pmax_measured   = [test_case_bs_mn_measured["nw"]["$i"]["gen"]["1"]["pmax"] for i in 1:(n_hours*one_scenario)]
pmax_forecasted = [test_case_bs_mn_forecasted["nw"]["$i"]["gen"]["1"]["pmax"] for i in 1:(n_hours*one_scenario)]
pmax_average    = [test_case_bs_mn_average["nw"]["$i"]["gen"]["1"]["pmax"] for i in 1:(n_hours*one_scenario)]
pmax_stochastic = []
for i in 1:n_hours 
    pmax_stochastic_scenarios = []
    for s in 1:n_scenarios 
        n = (i-1)*n_scenarios + s
        push!(pmax_stochastic_scenarios,test_case_bs_mn_expected["nw"]["$n"]["gen"]["1"]["pmax"]*test_case_bs_mn_expected["nw"]["$n"]["probability"])
    end
    push!(pmax_stochastic,sum(pmax_stochastic_scenarios))
end
pmax_adjusted = []
for i in 1:n_hours 
    pmax_adjusted_scenarios = []
    for s in 1:n_scenarios 
        n = (i-1)*n_scenarios + s
        push!(pmax_adjusted_scenarios,test_case_bs_mn_expected["nw"]["$n"]["gen"]["1"]["pmax"]*test_case_bs_mn_expected["nw"]["$n"]["probability"])
    end
    push!(pmax_adjusted,sum(pmax_adjusted_scenarios))
end

x_values_4 = []
forecasted_values_4 = []
first_hour_show = 1
last_hour_show = 24
for i in first_hour_show:last_hour_show
    for s in 1:n_scenarios
        l = (i - 1)*n_scenarios + s
        push!(x_values_4,i)
        push!(forecasted_values_4,forecasted_wind[i])
    end
end
errors_4 = [scenario_wind_4["$i"]["error"] for i in 1:(n_scenarios*24)]
forecast_4 = [forecasted_values_4[i]+scenario_wind_4["$i"]["error"] for i in 1:(n_scenarios*24)]
probabilities_4 = [scenario_wind_4["$i"]["probability"] for i in 1:(n_scenarios*24)]
probabilities_4 = round.(probabilities_4, digits=2)


plot(pmax_measured   ,label = "Measured",ylims = (0.0,4.0), yticks = 0:0.5:3.0, xlabel = "Hour", ylabel = "Pmax (MW)", xticks = 1:24,color = :blue,grid = :none,legend = :topleft)
plot!(pmax_forecasted,label = "Forecasted",color = :green)
plot!(pmax_stochastic,label = "Stochastic",color = :orange)
plot!(pmax_adjusted,label = "Adjusted",color = :orange)
plot!(pmax_average,label = "Average Measured-Forecasted",color = :red)
scatter!(pmax_measured,color = :blue,label = :none)
scatter!(pmax_forecasted,color = :green,label = :none)
scatter!(pmax_average,color = :red,label = :none)
scatter!(x_values_4,forecast_4*test_case_opf["gen"]["1"]["pmax"],xticks = 1:1:24,label = :none,color = :orange)

odd_numbers = [i for i in 1:(n_scenarios*24) if isodd(i)]
even_numbers = [i for i in 1:(n_scenarios*24) if iseven(i)]

#for i in 1:n_scenarios*24
#    if i in odd_numbers
#        annotate!(x_values_4[i]+0.5, forecast_4[i]*test_case_opf["gen"]["1"]["pmax"]+0.05, (probabilities_4[i], 6, :orange))
#    elseif i in even_numbers
#        annotate!(x_values_4[i]-0.5, forecast_4[i]*test_case_opf["gen"]["1"]["pmax"]+0.05, (probabilities_4[i], 6, :orange))
#    end
#end
#display(current())