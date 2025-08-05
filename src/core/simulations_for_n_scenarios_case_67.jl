using PowerModels; const _PM = PowerModels
using PowerModelsACDC; const _PMACDC = PowerModelsACDC
import PowerModelsTopologicalActionsII; const _PMTP = PowerModelsTopologicalActionsII
using FlexPlan; const _FP = FlexPlan
using Gurobi, Ipopt, JSON, Plots
import StochasticPowerModelsTopologicalActions; const _SPMTA = StochasticPowerModelsTopologicalActions
using JuMP, Juniper, HSL_jll, MathOptInterface, HiGHS
using Statistics

mip_gap = 1e-4
max_hours_simulations = 4
gurobi_bs = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 3600*max_hours_simulations,"MIPGap" => mip_gap,"BarHomogeneous" => 1, "NumericFocus"=>2) 
gurobi = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 1200,"MIPGap" => mip_gap,"BarHomogeneous" => 1,"BarQCPConvTol"=>1e-6,"QCPDual" => 1, "ScaleFlag"=>2, "NumericFocus"=>2) 
gurobi_opf = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 600,"MIPGap" => mip_gap,"BarHomogeneous" => 1, "NumericFocus"=>2,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "ScaleFlag"=>2, "NumericFocus"=>3) 
gurobi_lpac = JuMP.optimizer_with_attributes(Gurobi.Optimizer)#,"time_limit" => 1200,"MIPGap" => mip_gap,"BarHomogeneous" => 1,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "ScaleFlag"=>2, "NumericFocus"=>2)
ipopt = JuMP.optimizer_with_attributes(Ipopt.Optimizer, "tol" => 1e-6, "print_level" => 0,"linear_solver" => "ma57")
juniper = JuMP.optimizer_with_attributes(Juniper.Optimizer, "nl_solver" => ipopt, "mip_solver" => gurobi, "time_limit" => 600)

#########################################################################################
## Processing input data
s = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true)
s_dual = Dict("output" => Dict("branch_flows" => true,"duals" => true), "conv_losses_mp" => true)

#########################################################################################
## Processing input data
input_folder = dirname(dirname(@__DIR__))
test_case_file = joinpath(input_folder,"data_sources/case24_3zones_acdc.m")
original_grid = _PM.parse_file(test_case_file)
_PMACDC.process_additional_data!(original_grid)
test_case = deepcopy(original_grid)

results_folder = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/IJEPES_paper/Results"
results_folder_figures = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/IJEPES_paper/Figures"
case = "case_24/stochastic_multistep"


function add_VOLL_generators(data,gen_to_be_duplicated)
    first_l = maximum(parse.(Int, keys(data["gen"])))
    count = 0
    for (b_id,b) in data["bus"]
        count += 1
        l = first_l + count
        data["gen"]["$l"] = deepcopy(data["gen"]["$gen_to_be_duplicated"])
        #data["gen"]["$l"]["installed_capacity"] = 99.99
        data["gen"]["$l"]["gen_bus"] = parse(Int64,b_id) 
        data["gen"]["$l"]["pmax"] = 99.99
        #data["gen"]["$l"]["mbase"] = 9999
        data["gen"]["$l"]["source_id"][2] = deepcopy(l)
        #data["gen"]["$l"]["gen_type"] = "VOLL"
        data["gen"]["$l"]["index"] = l 
        #data["gen"]["$l"]["type"] = "VOLL"
        data["gen"]["$l"]["cost"][1] = 4400
    end
end
add_VOLL_generators(test_case,1)



for (g_id,g) in test_case["gen"]
    g["pmin"] = 0
end
for (g_id,g) in test_case["gen"]
    if length(g["cost"]) > 2
        g["cost"] = deepcopy(g["cost"][1:2]) 
    elseif length(g["cost"]) == 0
        push!(g["cost"],183.846)
        push!(g["cost"],0.0)
    end
end

for (g_id,g) in test_case["gen"]
    g["ncost"] = 2
    g["cost"][2] = 0
    g["cost"][1] = g["cost"][1]*1.3
end

for (l_id,l) in test_case["load"]
    if l["pd"] > 2.0
        l["pd"] = l["pd"]*1.2
    end
end
test_case_opf = deepcopy(test_case)

#for (g_id,g) in test_case["gen"]
#    if length(g["cost"]) > 0 && g["cost"][1] == 10000.0
#        g["cost"][1] = 180.0 # Just to avoid problems with the cost function
#    end
#end

for (g_id,g) in test_case["gen"]
    println([g_id,g["cost"]])
end


opf_67 = _PMACDC.run_acdcopf(test_case, LPACCPowerModel, ipopt; setting = s)
opf_67_ac = _PMACDC.run_acdcopf(test_case, ACPPowerModel, ipopt; setting = s_dual)


#########################################################################################
# Busbar splitting
test_case_bs = deepcopy(test_case_opf)
splitted_bus_ac = 211
test_case_bs,  switches_couples_ac,  extremes_ZILs_ac  = _PMTP.AC_busbar_split_AC_grid(test_case,splitted_bus_ac)

# Adding costs to the busbar couplers
for sw_id in 1:length(extremes_ZILs_ac)
    test_case_bs["switch"]["$sw_id"]["cost"] = 1.0
end

result_bs_6 = _PMTP.run_acdcsw_AC_big_M_hour(test_case_bs, LPACCPowerModel, gurobi_bs)


feasibility_check = deepcopy(test_case_bs)
feasibility_check_input = deepcopy(test_case_bs)
_PMTP.prepare_AC_feasibility_check(result_bs_6,feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
result_feasibility_check = _PMACDC.run_acdcopf(feasibility_check,ACPPowerModel,ipopt; setting = s)

#########################################################################################
# Upload scenarios
#first_hour = 355 
#last_hour = 378
#n_scenarios = 4

first_hour = 8153
last_hour  = 8488
n_scenarios = 8

n_hours = last_hour - first_hour + 1

_SPMTA.add_dimensions!(test_case_bs,n_scenarios,n_hours)


#forecasted_wind = JSON.parsefile(joinpath(input_data_folder,"src","core","case30","forecasted_wi_$(first_hour)_$(last_hour)_modified.json"))
#measured_wind = JSON.parsefile(joinpath(input_data_folder,"measured_wind_$(first_hour)_$(last_hour)_modified.json"))

forecasted_wind = JSON.parsefile(joinpath(input_folder,"src","core","case30","forecasted_two_weeks_$(first_hour)_$(last_hour).json"))
measured_wind = JSON.parsefile(joinpath(input_folder,"src","core","case30","measured_two_weeks_$(first_hour)_$(last_hour).json"))

# Adjust name of the file here
scenarios_wind_simulations = JSON.parsefile(joinpath(@__DIR__,"case30","Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour).json"))

#########################################################################################
## Running simulations
# Busbar splitting
test_case_opf_replicate = _PM.replicate(test_case_opf, n_hours*n_scenarios)
#test_case_opf_replicate_one_scenario = _PM.replicate(test_case_opf, n_hours*one_scenario)

test_case_opf_mn_expected = deepcopy(test_case_opf_replicate)
_SPMTA.adding_multinetwork_scenarios(test_case_opf_mn_expected,n_hours,n_scenarios,scenarios_wind_simulations)


for (g_id,g) in test_case["gen"]
    if length(test_case["gen"][g_id]["cost"]) > 0 && test_case["gen"][g_id]["cost"][1] <= 0.14 #&& test_case["gen"][g_id]["cost"][1] <= 750.0 
        for i in 1:(n_hours*n_scenarios)
            println("Generator $g_id, cost $(test_case["gen"][g_id]["cost"]), pmax $(test_case["gen"][g_id]["pmax"]) MW")
            test_case_opf_mn_expected["nw"]["$i"]["gen"][g_id]["pmax"]   = deepcopy(test_case_opf_replicate["nw"]["$i"]["gen"][g_id]["pmax"]*scenarios_wind_simulations["$i"]["samples_pu"])
            println("Pmax gen $(g_id) is $(test_case_opf_mn_expected["nw"]["$i"]["gen"][g_id]["pmax"])") 
        end
    end
end


################################################################################
# OPF scenarios
result_expected_24_ac = Dict{String,Any}()
result_expected_24_lpac = Dict{String,Any}()

for hour in 1:(n_hours*n_scenarios)
    result_expected_24_ac["$hour"] = _PMACDC.run_acdcopf(test_case_opf_mn_expected["nw"]["$hour"],ACPPowerModel,ipopt; setting = s)
    result_expected_24_lpac["$hour"] = _PMACDC.run_acdcopf(test_case_opf_mn_expected["nw"]["$hour"],LPACCPowerModel,ipopt; setting = s)
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

for (g_id,g) in test_case["gen"]
    if length(test_case["gen"][g_id]["cost"]) > 0 && test_case["gen"][g_id]["cost"][1] <= 0.14 #&& test_case["gen"][g_id]["cost"][1] <= 750.0 
        for i in 1:(n_hours*n_scenarios)
            println("Generator $g_id, cost $(test_case["gen"][g_id]["cost"]), pmax $(test_case["gen"][g_id]["pmax"]) MW")
            test_case_bs_mn_expected["nw"]["$i"]["gen"][g_id]["pmax"]   = deepcopy(test_case_bs_replicate["nw"]["$i"]["gen"][g_id]["pmax"]*scenarios_wind_simulations["$i"]["samples_pu"])
            println("Pmax gen $(g_id) is $(test_case_bs_mn_expected["nw"]["$i"]["gen"][g_id]["pmax"])") 
        end
    end
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


n_days = 14
n_hours_per_day = 24
for day in 1:n_days
    result_bs_hourly_expected = Dict{String,Any}()
    for hour in 1:n_hours_per_day
        hourly_grid_stochastic = Dict{String,Any}()
        result_bs_hourly_expected["$hour"] = Dict{String,Any}()
        first_n = (hour-1)*n_scenarios + 1
        last_n = (hour-1)*n_scenarios + n_scenarios
        println("day $day, hour $hour, first_n $first_n, last_n $last_n")
        hourly_grid_stochastic = Dict{String,Any}()
        hourly_grid_stochastic["nw"]   = Dict{String,Any}()
        hourly_grid_stochastic["multinetwork"] = true
        hourly_grid_stochastic["per_unit"] = true
        count_scenarios = 0
        for i in first_n:last_n
            count_scenarios += 1
            hourly_grid_stochastic["nw"]["$count_scenarios"] = deepcopy(test_case_bs_mn_expected_hours_sp["$hour"]["nw"]["$i"])
        end
        result_bs_hourly_expected["$hour"] = Dict{String,Any}()
        result_bs_hourly_expected["$hour"] = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology(hourly_grid_stochastic,LPACCPowerModel,gurobi_bs; setting = s)
    end
    json_hourly_expected = JSON.json(result_bs_hourly_expected)
    open(joinpath(results_folder,case,"Hourly_bs_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_day_$day.json"),"w") do f 
        write(f, json_hourly_expected) 
    end 
end

result_try = JSON.parsefile(joinpath(results_folder,case,"Hourly_bs_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_day_1.json"))

obj_hourly = [result_try["$h"]["objective"] for h in 1:n_hours_per_day]
obj_expected_24_lpac

sum(result_expected_24_ac["$h"]["objective"]*test_case_opf_mn_expected["nw"]["$h"]["probability"] for h in 1:(n_hours*n_scenarios))
sum(obj_hourly)

1 - sum(obj_hourly)/sum(result_expected_24_ac["$h"]["objective"]*test_case_opf_mn_expected["nw"]["$h"]["probability"] for h in 1:(n_hours*n_scenarios))


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

