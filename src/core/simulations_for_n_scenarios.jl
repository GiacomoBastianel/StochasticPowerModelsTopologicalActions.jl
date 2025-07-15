using PowerModels; const _PM = PowerModels
using PowerModelsACDC; const _PMACDC = PowerModelsACDC
import PowerModelsTopologicalActionsII; const _PMTP = PowerModelsTopologicalActionsII
using FlexPlan; const _FP = FlexPlan
using Gurobi, Ipopt, JSON, Plots
import StochasticPowerModelsTopologicalActions; const _SPMTA = StochasticPowerModelsTopologicalActions
using JuMP, Juniper, HSL_jll, MathOptInterface, HiGHS
using Statistics

mip_gap = 5e-4
max_hours_simulations = 6.5
gurobi_bs = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 3600*max_hours_simulations,"MIPGap" => mip_gap,"BarHomogeneous" => 1, "NumericFocus"=>2) 
gurobi = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 1200,"MIPGap" => mip_gap,"BarHomogeneous" => 1,"BarQCPConvTol"=>1e-6,"QCPDual" => 1, "ScaleFlag"=>2, "NumericFocus"=>2) 
gurobi_opf = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 600,"MIPGap" => mip_gap,"BarHomogeneous" => 1, "NumericFocus"=>2,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "ScaleFlag"=>2, "NumericFocus"=>3) 
gurobi_lpac = JuMP.optimizer_with_attributes(Gurobi.Optimizer)#,"time_limit" => 1200,"MIPGap" => mip_gap,"BarHomogeneous" => 1,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "ScaleFlag"=>2, "NumericFocus"=>2)
ipopt = JuMP.optimizer_with_attributes(Ipopt.Optimizer, "tol" => 1e-6, "print_level" => 0,"linear_solver" => "ma97")
juniper = JuMP.optimizer_with_attributes(Juniper.Optimizer, "nl_solver" => ipopt, "mip_solver" => gurobi, "time_limit" => 600)

#########################################################################################
## Processing input data
s = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true)
s_dual = Dict("output" => Dict("branch_flows" => true,"duals" => true), "conv_losses_mp" => true)

#########################################################################################
## Processing input data
input_folder = dirname(dirname(@__DIR__))
test_case_file = joinpath(input_folder,"data_sources/pglib_opf_case30_ieee.m")
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
# Busbar splitting
test_case_bs = deepcopy(test_case_opf)
splitted_bus_ac = 6
test_case_bs,  switches_couples_ac,  extremes_ZILs_ac  = _PMTP.AC_busbar_split_AC_grid(test_case,splitted_bus_ac)

# Adding costs to the busbar couplers
for sw_id in 1:length(extremes_ZILs_ac)
    test_case_bs["switch"]["$sw_id"]["cost"] = 10.0
end

result_bs_6 = _PMTP.run_acdcsw_AC_big_M_hour(test_case_bs, LPACCPowerModel, gurobi)
result_bs_6_no_cost = _PMTP.run_acdcsw_AC_big_M(test_case_bs, LPACCPowerModel, gurobi)


feasibility_check = deepcopy(test_case_bs)
feasibility_check_input = deepcopy(test_case_bs)
_PMTP.prepare_AC_feasibility_check(result_bs_6,feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
result_feasibility_check = _PMACDC.run_acdcopf(feasibility_check,ACPPowerModel,ipopt; setting = s)

#########################################################################################
# Upload scenarios
first_hour = 355 
last_hour = 378
#n_scenarios = 4

#first_hour = 8153
#last_hour  = 8486
n_scenarios = 8

n_hours = last_hour - first_hour + 1

_SPMTA.add_dimensions!(test_case_bs,n_scenarios,n_hours)

input_data_folder = joinpath(@__DIR__,"case30")

forecasted_wind = JSON.parsefile(joinpath(input_data_folder,"forecasted_wind_hours_$(first_hour)_$(last_hour).json"))
measured_wind = JSON.parsefile(joinpath(input_data_folder,"measured_wind_$(first_hour)_$(last_hour).json"))

#forecasted_wind = JSON.parsefile(joinpath(input_data_folder,"forecasted_two_weeks_$(first_hour)_$(last_hour).json"))
#measured_wind = JSON.parsefile(joinpath(input_data_folder,"measured_two_weeks_$(first_hour)_$(last_hour).json"))

# Adjust name of the file here
scenarios_wind_simulations = JSON.parsefile(joinpath(@__DIR__,"case30","Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour).json"))

#########################################################################################
## Running simulations
# Busbar splitting
test_case_opf_replicate = _PM.replicate(test_case_opf, n_hours*n_scenarios)
#test_case_opf_replicate_one_scenario = _PM.replicate(test_case_opf, n_hours*one_scenario)

test_case_opf_mn_expected = deepcopy(test_case_opf_replicate)
_SPMTA.adding_multinetwork_scenarios(test_case_opf_mn_expected,n_hours,n_scenarios,scenarios_wind_simulations)

for i in 1:(n_hours*n_scenarios)
    test_case_opf_mn_expected["nw"]["$i"]["gen"]["1"]["pmax"]   = deepcopy(test_case_opf_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*scenarios_wind_simulations["$i"]["samples_pu"])
end

################################################################################
# OPF scenarios
result_expected_24_ac = Dict{String,Any}()
result_expected_24_lpac = Dict{String,Any}()

for hour in 1:(n_hours*n_scenarios)
    result_expected_24_ac["$hour"] = _PM.solve_opf(test_case_opf_mn_expected["nw"]["$hour"],ACPPowerModel,ipopt; setting = s)
    result_expected_24_lpac["$hour"] = _PM.solve_opf(test_case_opf_mn_expected["nw"]["$hour"],LPACCPowerModel,ipopt; setting = s)
end

obj_expected_24_ac = []
obj_expected_24_lpac = []
for hour in 1:n_hours
    first_n = (hour - 1)*n_scenarios + 1
    last_n = n_scenarios*hour
    opf_hour_ac = sum(result_expected_24_ac["$h"]["objective"]*test_case_opf_mn_expected["nw"]["$h"]["probability"] for h in first_n:last_n)
    push!(obj_expected_24_ac,opf_hour_ac)
    opf_hour_lpac = sum(result_expected_24_lpac["$h"]["objective"]*test_case_opf_mn_expected["nw"]["$h"]["probability"] for h in first_n:last_n)
    push!(obj_expected_24_lpac,opf_hour_lpac)
end

json_hourly_expected_24 = JSON.json(result_expected_24_ac)
open(joinpath(results_folder,case,"Hourly_opf_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_hourly_expected_24) 
end 


###########################################################################
# -> Busbar splitting
test_case_bs_replicate = _PM.replicate(test_case_bs, n_hours*n_scenarios)

test_case_bs_mn_expected = deepcopy(test_case_bs_replicate)
_SPMTA.adding_multinetwork_scenarios(test_case_bs_mn_expected,n_hours,n_scenarios,scenarios_wind_simulations)

for i in 1:(n_hours*n_scenarios)
    test_case_bs_mn_expected["nw"]["$i"]["gen"]["1"]["pmax"]   = deepcopy(test_case_bs_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*scenarios_wind_simulations["$i"]["samples_pu"])
end

test_case_bs_mn_expected_sp = deepcopy(test_case_bs_mn_expected)
_SPMTA.prepare_starting_value_dict_lpac_nw_sp(test_case_bs_mn_expected_sp,n_hours,n_scenarios)

test_case_bs_mn_expected_hours_sp = Dict{String,Any}()

for hour in 1:n_hours
    first_n = (hour - 1)*n_scenarios + 1
    last_n = n_scenarios*hour
    test_case_bs_mn_expected_hours_sp["$hour"] = Dict{String,Any}()
    test_case_bs_mn_expected_hours_sp["$hour"]["nw"] = Dict{String,Any}()
    test_case_bs_mn_expected_hours_sp["$hour"]["multinetwork"] = true
    test_case_bs_mn_expected_hours_sp["$hour"]["per_unit"] = true
    for i in first_n:last_n
        test_case_bs_mn_expected_hours_sp["$hour"]["nw"]["$i"] = deepcopy(test_case_bs_mn_expected_sp["nw"]["$i"])
    end
end

 
json_hourly_expected_24 = JSON.json(result_bs_hourly_expected_24)
open(joinpath(results_folder,case,"Hourly_bs_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_hourly_expected_24) 
end 

#########################################################################
# I should set a starting point here
test_case_bs_mn_expected_sp = deepcopy(test_case_bs_mn_expected)
_SPMTA.prepare_starting_value_dict_lpac_nw_sp(test_case_bs_mn_expected_sp,n_hours,n_scenarios)

results_one_topology_sp_stochastic = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology_sp(test_case_bs_mn_expected_sp,LPACCPowerModel,gurobi_bs; setting = s)

json_results_one_topology_sp_stochastic = JSON.json(results_one_topology_sp_stochastic)
open(joinpath(results_folder,case,"24_hours_BS_one_topology_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_results_one_topology_sp_stochastic) 
end 

####################################################

test_case_bs_mn_expected_try_max_sw = deepcopy(test_case_bs_mn_expected_sp)
test_case_bs_mn_expected["total_switching_actions"] = 1

for (sw_id,sw) in test_case_bs_mn_expected["nw"]["1"]["switch"]
    sw["maximum_actions"] = 1
end

results_one_topology_sp_expected_one_max_sw = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches_stochastic(test_case_bs_mn_expected,LPACCPowerModel,gurobi_bs)

json_results_one_topology_sp_expected_one_max_sw = JSON.json(results_one_topology_sp_expected_one_max_sw)
open(joinpath(results_folder,case,"One_maximum_actions_24_hours_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_results_one_topology_sp_expected_one_max_sw) 
end 

#######

test_case_bs_mn_expected_two_max_sw = deepcopy(test_case_bs_mn_expected)
test_case_bs_mn_expected["total_switching_actions"] = 2
for (sw_id,sw) in test_case_bs_mn_expected["nw"]["1"]["switch"]
    sw["maximum_actions"] = 2
end
results_one_topology_sp_expected_max_sw_2 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches_stochastic(test_case_bs_mn_expected,LPACCPowerModel,gurobi_bs)

json_results_two_topology_expected = JSON.json(results_one_topology_sp_expected_max_sw_2)
open(joinpath(results_folder,case,"Two_maximum_actions_24_hours_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_results_two_topology_expected) 
end 

