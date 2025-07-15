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
gurobi_opf = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 1200,"MIPGap" => mip_gap,"BarHomogeneous" => 1, "NumericFocus"=>2,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "ScaleFlag"=>2, "NumericFocus"=>3) 
ipopt = JuMP.optimizer_with_attributes(Ipopt.Optimizer, "tol" => 1e-6, "print_level" => 0,"linear_solver" => "ma97")

sc = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true)


#first_hour = 355
#last_hour  = 378
n_hours = 24

first_hour = 8153
last_hour  = 8488
n_scenarios = 8
n_days = 14
one_scenario = 1
n_hours_per_day = 24

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
scenario_wind = JSON.parsefile(joinpath(input_folder,"case30","Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour).json"))

# Uploading results
hourly_opf = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Hourly_opf_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour).json"))
hourly_opf_measured = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Hourly_opf_measured_$(first_hour)_$(last_hour).json"))
hourly_opf_average = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Hourly_opf_average_$(first_hour)_$(last_hour).json"))
hourly_opf_forecasted = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Hourly_opf_forecasted_$(first_hour)_$(last_hour).json"))

hourly_bs_measured = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep",  "Hourly_bs_measured_$(first_hour)_$(last_hour).json"))
hourly_bs_average = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep",   "Hourly_bs_average_$(first_hour)_$(last_hour).json"))
hourly_bs_forecasted = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Hourly_bs_forecasted_$(first_hour)_$(last_hour).json"))

one_sw_measured = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep",  "One_maximum_actions_24_hours_measured_$(first_hour)_$(last_hour).json"))
one_sw_average = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep",   "One_maximum_actions_24_hours_average_$(first_hour)_$(last_hour).json"))
one_sw_forecasted = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","One_maximum_actions_24_hours_forecasted_$(first_hour)_$(last_hour).json"))

one_topology_measured = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep",  "24_hours_BS_one_topology_measured_$(first_hour)_$(last_hour).json"))
one_topology_forecasted = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","24_hours_BS_one_topology_forecasted_$(first_hour)_$(last_hour).json"))


n_hours = last_hour - first_hour + 1

_SPMTA.add_dimensions!(test_case_bs,n_scenarios,n_hours)

input_data_folder = joinpath(@__DIR__)

#forecasted_wind = JSON.parsefile(joinpath(input_data_folder,"case30","forecasted_wind_hours_$(first_hour)_$(last_hour).json"))
#measured_wind = JSON.parsefile(joinpath(input_data_folder,"case30","measured_wind_$(first_hour)_$(last_hour).json"))

forecasted_wind = JSON.parsefile(joinpath(input_data_folder,"case30","forecasted_two_weeks_$(first_hour)_$(last_hour).json"))
measured_wind = JSON.parsefile(joinpath(input_data_folder,"case30","measured_two_weeks_$(first_hour)_$(last_hour).json"))

# Adjust name of the file here
scenarios_wind_simulations = JSON.parsefile(joinpath(input_data_folder,"case30","Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour).json"))

#########################################################################################
# Upload results
hourly_bs_days = Dict{String,Any}()
for day in 1:n_days
    hourly_bs_days["$day"] = Dict{String,Any}()
    hourly_bs_days["$day"] = JSON.parsefile(joinpath(results_folder,case,"Hourly_bs_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_day_$(day).json"))
end

one_topology_bs_days = Dict{String,Any}()
for day in 1:n_days
    one_topology_bs_days["$day"] = Dict{String,Any}()
    one_topology_bs_days["$day"] = JSON.parsefile(joinpath(results_folder,case,"24_hours_BS_one_topology_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_day_$(day).json"))
end

one_sw_bs_days = Dict{String,Any}()
for day in 1:n_days
    one_sw_bs_days["$day"] = Dict{String,Any}()
    one_sw_bs_days["$day"] = JSON.parsefile(joinpath(results_folder,case,"24_hours_BS_one_sw_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_day_$(day).json"))
end

two_sw_bs_days = Dict{String,Any}()
for day in 1:n_days
    two_sw_bs_days["$day"] = Dict{String,Any}()
    two_sw_bs_days["$day"] = JSON.parsefile(joinpath(results_folder,case,"24_hours_BS_two_sw_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_day_$(day).json"))
end



#########################################################################################

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

#=
function feasibility_check_scenarios(result_dict,result_bs)
    for i in scenarios
        test_case_bs_replicate = _PM.replicate(test_case_bs, n_hours*i)
        test_case_bs_scenarios = deepcopy(test_case_bs_replicate)
        _SPMTA.adding_multinetwork_scenarios(test_case_bs_scenarios,n_hours,i,scenario_wind["$i"])
        for h in 1:(n_hours*i)
            test_case_bs_scenarios["nw"]["$h"]["gen"]["1"]["pmax"]   = deepcopy(test_case_bs_scenarios["nw"]["$h"]["gen"]["1"]["pmax"]*scenario_wind["$i"]["$h"]["samples_pu"])
        end
        result_dict["$i"] = Dict{String,Any}()
        result_dict["$i"] = run_feasibility_checks_per_hour_stochastic(test_case_bs_scenarios,result_bs["$i"],ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s,n_hours,i)
    end
end
=#
result_feasibility_checks = Dict{String,Any}()


function feasibility_check_days(result_dict,result_bs,data_dict)
    test_case_bs_replicate = _PM.replicate(test_case_bs, n_hours*n_scenarios)
    test_case_bs_scenarios = deepcopy(test_case_bs_replicate)
    for day in 1:n_days
        data_dict["$day"] = Dict{String,Any}()
        result_dict["$day"] = Dict{String,Any}()
        for h in 1:n_hours_per_day
            data_dict["$day"]["$h"] = Dict{String,Any}()
            result_dict["$day"]["$h"] = Dict{String,Any}()
            for s in 1:n_scenarios
                println("Day: $day, Hour: $h, Scenario: $s")
                data_dict["$day"]["$h"]["$s"] = Dict{String,Any}()
                result_dict["$day"]["$h"]["$s"] = Dict{String,Any}()
                index = (day - 1)*n_hours_per_day*n_scenarios + (h - 1)*n_scenarios + s
                test_case_bs_scenarios["nw"]["$index"]["gen"]["1"]["pmax"]   = deepcopy(test_case_bs_scenarios["nw"]["$index"]["gen"]["1"]["pmax"]*scenario_wind["$index"]["samples_pu"])
                adding_multinetwork_scenario_days(test_case_bs_scenarios,n_hours,s,n_scenarios,scenario_wind,index,h)
                #result_dict["$index"] = Dict{String,Any}()
                run_feasibility_checks_per_hour_days(test_case_bs_scenarios,result_bs,result_dict,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,sc,day,h,n_hours,n_scenarios,index,s,data_dict)            
            end
        end
    end
    return result_dict
end


function add_hour_scenario_probability_days(data,hour,scenario_idx,n_scenarios,uncertainty,index)
    data["nw"]["$index"]["hour"] = hour
    data["nw"]["$index"]["scenario"] = scenario_idx
    data["nw"]["$index"]["hour_scenario_index"] = [hour,scenario_idx,index]
    if n_scenarios == 1
        data["nw"]["$index"]["probability"] = 1.0
        data["nw"]["$index"]["per_unit"] = true
    elseif n_scenarios > 1
        data["nw"]["$index"]["probability"] = uncertainty["$index"]["probability"]
        data["nw"]["$index"]["per_unit"] = true
    end
end

function adding_multinetwork_scenario_days(test_case, n_hours,scenario_idx, n_scenarios,uncertainty,index,hour)
    add_hour_scenario_probability_days(test_case,hour,scenario_idx,n_scenarios,uncertainty,index)
    test_case["scenarios"] = n_scenarios
    test_case["hours"] = n_hours
end


function run_feasibility_checks_per_hour_days(grid, result_bs,result_feasibility_checks, model, optimizer,switches_couples_ac,extremes_ZILs_ac,test_case_opf,settings,day,hour,n_hours,n_scenarios,index,scenario,data_dict)
    #result_feasibility_checks = Dict{String,Any}()
    if haskey(result_bs["$day"],"$hour")
        #result_feasibility_checks["$day"] = Dict{String,Any}()
        feasibility_check = deepcopy(grid["nw"]["$index"])
        feasibility_check_input = deepcopy(grid["nw"]["$index"])
        _SPMTA.prepare_AC_feasibility_check_stochastic(result_bs["$day"]["$hour"]["solution"]["nw"]["$scenario"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
        println("Feasibility check for day $day, hour $hour, scenario $scenario, index $index")
        data_dict["$day"]["$hour"]["$scenario"] = feasibility_check
        result_feasibility_checks["$day"]["$hour"]["$scenario"] = _PMACDC.run_acdcopf(feasibility_check,model,optimizer; setting = settings)
        result_feasibility_checks["$day"]["$hour"]["$scenario"]["probability"] = grid["nw"]["$index"]["probability"]    
    elseif haskey(result_bs["$day"],"solution")
        feasibility_check = deepcopy(grid["nw"]["$index"])
        feasibility_check_input = deepcopy(grid["nw"]["$index"])
        timestep = (hour - 1)*n_scenarios + scenario
        _SPMTA.prepare_AC_feasibility_check_stochastic(result_bs["$day"]["solution"]["nw"]["$timestep"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
        println("Feasibility check for day $day, hour $hour, scenario $scenario, index $index")
        data_dict["$day"]["$hour"]["$scenario"] = feasibility_check
        result_feasibility_checks["$day"]["$hour"]["$scenario"] = _PMACDC.run_acdcopf(feasibility_check,model,optimizer; setting = settings)
        result_feasibility_checks["$day"]["$hour"]["$scenario"]["probability"] = grid["nw"]["$index"]["probability"]    
    end
end


test_case_bs_replicate = _PM.replicate(test_case_bs, n_hours*n_scenarios)
test_case_bs_scenarios = deepcopy(test_case_bs_replicate)


result_feasibility_checks = Dict{String,Any}()
data_check = Dict{String,Any}()
feasibility_check_days(result_feasibility_checks,hourly_bs_days,data_check)

result_feasibility_checks_one_topology = Dict{String,Any}()
data_check_one_topology = Dict{String,Any}()
feasibility_check_days(result_feasibility_checks_one_topology,one_topology_bs_days,data_check_one_topology)

result_feasibility_checks_one_topology = Dict{String,Any}()
data_check_one_topology = Dict{String,Any}()
feasibility_check_days(result_feasibility_checks_one_topology,one_topology_bs_days,data_check_one_topology)

result_feasibility_checks_one_sw = Dict{String,Any}()
data_check_one_sw = Dict{String,Any}()
feasibility_check_days(result_feasibility_checks_one_sw,one_sw_bs_days,data_check_one_sw)


result_feasibility_checks_two_sw = Dict{String,Any}()
data_check_two_sw = Dict{String,Any}()
feasibility_check_days(result_feasibility_checks_two_sw,two_sw_bs_days,data_check_two_sw)


obj_one_topology = []
obj_hourly_bs = []
obj_one_sw = []
obj_two_sw = []
for day in 1:n_days
    for hour in 1:n_hours_per_day
        for scenario in 1:n_scenarios
            if haskey(result_feasibility_checks["$day"]["$hour"],"$scenario")
                push!(obj_hourly_bs,result_feasibility_checks["$day"]["$hour"]["$scenario"]["objective"])
            end
            if haskey(result_feasibility_checks_one_sw["$day"]["$hour"],"$scenario")
                push!(obj_one_sw,result_feasibility_checks_one_sw["$day"]["$hour"]["$scenario"]["objective"])
            end
            if haskey(result_feasibility_checks_one_topology["$day"]["$hour"],"$scenario")
                push!(obj_one_topology,result_feasibility_checks_one_topology["$day"]["$hour"]["$scenario"]["objective"])
            end
            if haskey(result_feasibility_checks_two_sw["$day"]["$hour"],"$scenario")
                push!(obj_two_sw,result_feasibility_checks_two_sw["$day"]["$hour"]["$scenario"]["objective"])
            end
        end
    end
end

opf_total = sum(hourly_opf["$timestep"]["objective"]*scenario_wind["$timestep"]["probability"] for timestep in 1:(n_hours*n_scenarios))
one_topology_total = sum(obj_one_topology[timestep]*scenario_wind["$timestep"]["probability"] for timestep in 1:(n_hours*n_scenarios))
one_sw_total = sum(obj_one_sw[timestep]*scenario_wind["$timestep"]["probability"] for timestep in 1:(n_hours*n_scenarios))
two_sw_total = sum(obj_two_sw[timestep]*scenario_wind["$timestep"]["probability"] for timestep in 1:(n_hours*n_scenarios))
hourly_bs_total = sum(obj_hourly_bs[timestep]*scenario_wind["$timestep"]["probability"] for timestep in 1:(n_hours*n_scenarios))


(opf_total - hourly_bs_total)/opf_total*100
(opf_total - one_topology_total)/opf_total*100 
(opf_total - one_sw_total)/opf_total*100
(opf_total - two_sw_total)/opf_total*100

##########################################################################################

json_hourly_bs_n_scenarios = JSON.json(hourly_bs_days)
json_feasibility_check_hourly_bs = JSON.json(result_feasibility_checks)
json_data_check = JSON.json(data_check)

open(joinpath(results_folder,case,"hourly_bs_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_all_days.json"),"w") do f 
    write(f, json_hourly_bs_n_scenarios) 
end 

open(joinpath(results_folder,case,"fc_hourly_bs_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_all_days.json"),"w") do f 
    write(f, json_feasibility_check_hourly_bs) 
end 

open(joinpath(results_folder,case,"fc_data_hourly_bs_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_all_days.json"),"w") do f 
    write(f, json_data_check) 
end 



json_one_topology_n_scenarios = JSON.json(one_topology_bs_days)
json_feasibility_check_one_topology = JSON.json(result_feasibility_checks_one_topology)
json_data_check = JSON.json(data_check_one_topology)

open(joinpath(results_folder,case,"one_topology_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_all_days.json"),"w") do f 
    write(f, json_one_topology_n_scenarios) 
end 

open(joinpath(results_folder,case,"fc_one_topology_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_all_days.json"),"w") do f 
    write(f, json_feasibility_check_one_topology) 
end 

open(joinpath(results_folder,case,"fc_data_one_topology_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_all_days.json"),"w") do f 
    write(f, json_data_check) 
end 


json_one_sw_n_scenarios = JSON.json(one_sw_bs_days)
json_feasibility_check_one_sw = JSON.json(result_feasibility_checks_one_sw)
json_data_check = JSON.json(data_check_one_sw)

open(joinpath(results_folder,case,"one_sw_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_all_days.json"),"w") do f 
    write(f, json_one_sw_n_scenarios) 
end 

open(joinpath(results_folder,case,"fc_one_sw_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_all_days.json"),"w") do f 
    write(f, json_feasibility_check_one_sw) 
end 

open(joinpath(results_folder,case,"fc_data_one_sw_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_all_days.json"),"w") do f 
    write(f, json_data_check) 
end 


json_two_sw_n_scenarios = JSON.json(two_sw_bs_days)
json_feasibility_check_two_sw = JSON.json(result_feasibility_checks_two_sw)
json_data_check = JSON.json(data_check_two_sw)

open(joinpath(results_folder,case,"two_sw_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_all_days.json"),"w") do f 
    write(f, json_two_sw_n_scenarios) 
end 

open(joinpath(results_folder,case,"fc_two_sw_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_all_days.json"),"w") do f 
    write(f, json_feasibility_check_two_sw) 
end 

open(joinpath(results_folder,case,"fc_data_two_sw_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_all_days.json"),"w") do f 
    write(f, json_data_check) 
end 










