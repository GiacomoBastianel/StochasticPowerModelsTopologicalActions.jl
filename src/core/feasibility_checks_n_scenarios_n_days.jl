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
scenario_wind_6 = JSON.parsefile(joinpath(input_folder,"case30","Laplace_6_scenarios_$(first_hour)_$(last_hour).json"))
scenario_wind_8 = JSON.parsefile(joinpath(input_folder,"case30","Laplace_8_scenarios_$(first_hour)_$(last_hour).json"))

# Uploading results
hourly_opf = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Hourly_opf_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour).json"))
hourly_opf_measured = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Hourly_opf_measured_$(first_hour)_$(last_hour).json"))
hourly_opf_average = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Hourly_opf_average_$(first_hour)_$(last_hour).json"))
hourly_opf_forecasted = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Hourly_opf_forecasted_$(first_hour)_$(last_hour).json"))

hourly_bs_measured = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep",  "Hourly_bs_measured_$(first_hour)_$(last_hour)_all_days.json"))
hourly_bs_average = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep",   "Hourly_bs_average_$(first_hour)_$(last_hour)_all_days.json"))
hourly_bs_forecasted = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Hourly_bs_forecasted_$(first_hour)_$(last_hour)_all_days.json"))

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

forecasted_wind = JSON.parsefile(joinpath(input_folder,"case30","forecasted_two_weeks_$(first_hour)_$(last_hour).json"))
measured_wind = JSON.parsefile(joinpath(input_folder,"case30","measured_two_weeks_$(first_hour)_$(last_hour).json"))
average_wind = [mean([forecasted_wind[i],measured_wind[i]]) for i in 1:length(forecasted_wind)]

# Adjust name of the file here
scenarios_wind_simulations = JSON.parsefile(joinpath(input_folder,"case30","Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour).json"))

#########################################################################################
# Upload results
function create_dict_results(n_days,results_folder,case,first_hour,last_hour,file_name)
    results_dict = Dict{String,Any}()
    for day in 1:n_days
        results_dict["$day"] = Dict{String,Any}()
        results_dict_day = JSON.parsefile(joinpath(results_folder,case,"$(file_name)_$(first_hour)_$(last_hour)_day_$(day).json"))
        results_dict["$day"] = results_dict_day["$day"]
    end
    json_result_check = JSON.json(results_dict)
    open(joinpath(results_folder,case,"$(file_name)_$(first_hour)_$(last_hour)_all_days.json"),"w") do f 
        write(f, json_result_check) 
    end  
    return results_dict
end
types = ["forecasted","average","measured"]
for type in types
    create_dict_results(n_days,results_folder,case,first_hour,last_hour,"One_topology_$(type)")    
end


function create_dict_results_scenarios(n_days,results_folder,case,first_hour,last_hour,hours_per_day,n_scenarios,file_name)
    results_dict = Dict{String,Any}()
    for day in 1:n_days
        results_dict["$day"] = Dict{String,Any}()
        results_dict_day = JSON.parsefile(joinpath(results_folder,case,"$(file_name)_$(first_hour)_$(last_hour)_day_$(day).json"))
        for hour in 1:n_hours_per_day
            if haskey(results_dict_day,"$hour")
                println("Day $day, Hour $hour")
                results_dict["$day"]["$hour"] = Dict{String,Any}()
                results_dict["$day"]["$hour"] = deepcopy(results_dict_day["$hour"])
            elseif haskey(results_dict_day,"solution")
                results_dict["$day"]["$hour"] = Dict{String,Any}()
                for n in 1:n_scenarios
                    println("Day $day, Hour $hour, Scenario $n")
                    this_scenario = (hour - 1)*n_scenarios + n
                    results_dict["$day"]["$hour"]["$n"] = Dict{String,Any}()
                    results_dict["$day"]["$hour"]["$n"] = deepcopy(results_dict_day["solution"]["nw"]["$this_scenario"])
                    results_dict["$day"]["$hour"]["$n"]["day"]  = deepcopy(day)
                    results_dict["$day"]["$hour"]["$n"]["hour"] = deepcopy(hour)
                    results_dict["$day"]["$hour"]["$n"]["scenario"] = deepcopy(n)
                end 
            end
        end
    end
    json_result_check = JSON.json(results_dict)
    open(joinpath(results_folder,case,"$(file_name)_$(first_hour)_$(last_hour)_all_days.json"),"w") do f 
        write(f, json_result_check) 
    end  
    return results_dict
end


create_dict_results_scenarios(n_days,results_folder,case,first_hour,last_hour,n_hours_per_day,"Hourly_bs_stochastic_Laplace_6_scenarios")
create_dict_results_scenarios(n_days,results_folder,case,first_hour,last_hour,n_hours_per_day,"Hourly_bs_stochastic_Laplace_8_scenarios")

create_dict_results_scenarios(n_days,results_folder,case,first_hour,last_hour,n_hours_per_day,6,"24_hours_BS_one_topology_stochastic_Laplace_6_scenarios")
create_dict_results_scenarios(n_days,results_folder,case,first_hour,last_hour,n_hours_per_day,8,"24_hours_BS_one_topology_stochastic_Laplace_8_scenarios")

create_dict_results_scenarios(n_days,results_folder,case,first_hour,last_hour,n_hours_per_day,6,"24_hours_BS_one_sw_stochastic_Laplace_6_scenarios")
create_dict_results_scenarios(n_days,results_folder,case,first_hour,last_hour,n_hours_per_day,8,"24_hours_BS_one_sw_stochastic_Laplace_8_scenarios")

create_dict_results_scenarios(n_days,results_folder,case,first_hour,last_hour,n_hours_per_day,6,"24_hours_BS_two_sw_stochastic_Laplace_6_scenarios")
create_dict_results_scenarios(n_days,results_folder,case,first_hour,last_hour,n_hours_per_day,8,"24_hours_BS_two_sw_stochastic_Laplace_8_scenarios")


function create_dict_results_hourly(n_days,results_folder,case,first_hour,last_hour,file_name,type)
    results_dict = Dict{String,Any}()
    result_hourly = JSON.parsefile(joinpath(results_folder,case,"$(file_name)_$(type)_$(first_hour)_$(last_hour).json"))
    for day in 1:n_days
        results_dict["$day"] = Dict{String,Any}()
        for hour in 1:n_hours_per_day
            this_hour = (day - 1)*n_hours_per_day + hour
            results_dict["$day"]["$hour"] = result_hourly["$this_hour"]
        end
    end
    json_result_check = JSON.json(results_dict)
    open(joinpath(results_folder,case,"$(file_name)_$(first_hour)_$(last_hour)_all_days.json"),"w") do f 
        write(f, json_result_check) 
    end  
end
types = ["forecasted","average","measured"]
for type in types
    create_dict_results_hourly(n_days,results_folder,case,first_hour,last_hour,"hourly_bs",type)    
end



function upload_results(n_days,results_folder,case,first_hour,last_hour,file_name)
    results_dict = Dict{String,Any}()
    for day in 1:n_days
        results_dict["$day"] = Dict{String,Any}()
        results_dict_day = JSON.parsefile(joinpath(results_folder,case,"$(file_name)_$(first_hour)_$(last_hour)_day_$(day).json"))
        results_dict["$day"] = results_dict_day["$day"]
    end
    return results_dict
end

function upload_results_all_days(results_folder,case,first_hour,last_hour,file_name)
    results_dict = JSON.parsefile(joinpath(results_folder,case,"$(file_name)_$(first_hour)_$(last_hour)_all_days.json"))
end

type = "forecasted"
one_topology_all_days = upload_results(n_days,results_folder,case,first_hour,last_hour,"One_topology_$(type)")


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


function feasibility_check_days(result_bs,scenario_wind,time_series,n_scenarios,simulation,type,first_hour,last_hour)
    result_dict = Dict{String,Any}()
    data_dict = Dict{String,Any}()
    test_case_bs_replicate = _PM.replicate(test_case_bs, n_hours*n_scenarios)
    test_case_bs_scenarios = deepcopy(test_case_bs_replicate)
    if n_scenarios > 1
        for day in 1:n_days
            data_dict["$day"] = Dict{String,Any}()
            result_dict["$day"] = Dict{String,Any}()
            for h in 1:n_hours_per_day
                data_dict["$day"]["$h"] = Dict{String,Any}()
                result_dict["$day"]["$h"] = Dict{String,Any}()
                #if haskey(result_bs[["$day"]["$h"],"solution"])
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
                #else
                #    for s in 1:n_scenarios
                #        println("Day: $day, Hour: $h, Scenario: $s")
                #        data_dict["$day"]["$h"]["$s"] = Dict{String,Any}()
                #        result_dict["$day"]["$h"]["$s"] = Dict{String,Any}()
                #        index = (day - 1)*n_hours_per_day*n_scenarios + (h - 1)*n_scenarios + s
                #        test_case_bs_scenarios["nw"]["$index"]["gen"]["1"]["pmax"]   = deepcopy(test_case_bs_scenarios["nw"]["$index"]["gen"]["1"]["pmax"]*scenario_wind["$index"]["samples_pu"])
                #        adding_multinetwork_scenario_days(test_case_bs_scenarios,n_hours,s,n_scenarios,scenario_wind,index,h)
                #        #result_dict["$index"] = Dict{String,Any}()
                #        run_feasibility_checks_per_hour_days(test_case_bs_scenarios,result_bs,result_dict,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,sc,day,h,n_hours,n_scenarios,index,s,data_dict)            
                #    end
                #end
            end
        end
        json_feasibility_check = JSON.json(result_dict)
        json_data_check = JSON.json(data_dict)
        open(joinpath(results_folder,case,"fc_$(simulation)_$(first_hour)_$(last_hour)_all_days.json"),"w") do f 
            write(f, json_feasibility_check) 
        end 
        open(joinpath(results_folder,case,"fc_data_$(simulation)_$(first_hour)_$(last_hour)_all_days.json"),"w") do f 
            write(f, json_data_check) 
        end 
    else
        for day in 1:n_days
            data_dict["$day"] = Dict{String,Any}()
            result_dict["$day"] = Dict{String,Any}()
            for h in 1:n_hours_per_day
                data_dict["$day"]["$h"] = Dict{String,Any}()
                result_dict["$day"]["$h"] = Dict{String,Any}()
                println("Day: $day, Hour: $h, One Scenario")
                index = (day - 1)*n_hours_per_day + h
                test_case_bs_scenarios["nw"]["$index"]["gen"]["1"]["pmax"]   = deepcopy(test_case_bs_scenarios["nw"]["$index"]["gen"]["1"]["pmax"]*time_series[index])
                adding_multinetwork_scenario_days(test_case_bs_scenarios,n_hours,s,n_scenarios,time_series,index,h)
                #result_dict["$index"] = Dict{String,Any}()
                run_feasibility_checks_per_hour_days(test_case_bs_scenarios,result_bs,result_dict,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,sc,day,h,n_hours,n_scenarios,index,s,data_dict)            
            end
        end
        json_feasibility_check = JSON.json(result_dict)
        json_data_check = JSON.json(data_dict)
        open(joinpath(results_folder,case,"fc_$(simulation)_$(type)_$(first_hour)_$(last_hour)_all_days.json"),"w") do f 
            write(f, json_feasibility_check) 
        end 
        open(joinpath(results_folder,case,"fc_data_$(simulation)_$(type)_$(first_hour)_$(last_hour)_all_days.json"),"w") do f 
            write(f, json_data_check) 
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
    if n_scenarios > 1
        if haskey(result_bs["$day"],"$hour")
            if haskey(result_bs["$day"]["$hour"],"$scenario")
                feasibility_check = deepcopy(grid["nw"]["$index"])
                feasibility_check_input = deepcopy(grid["nw"]["$index"])
                _SPMTA.prepare_AC_feasibility_check_stochastic(result_bs["$day"]["$hour"]["$scenario"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
                println("Feasibility check for day $day, hour $hour, scenario $scenario, index $index")
                data_dict["$day"]["$hour"]["$scenario"] = feasibility_check
                result_feasibility_checks["$day"]["$hour"]["$scenario"] = _PMACDC.run_acdcopf(feasibility_check,model,optimizer; setting = settings)
                result_feasibility_checks["$day"]["$hour"]["$scenario"]["probability"] = grid["nw"]["$index"]["probability"]    
            else
                #result_feasibility_checks["$day"] = Dict{String,Any}()
                feasibility_check = deepcopy(grid["nw"]["$index"])
                feasibility_check_input = deepcopy(grid["nw"]["$index"])
                _SPMTA.prepare_AC_feasibility_check_stochastic(result_bs["$day"]["$hour"]["solution"]["nw"]["$scenario"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
                println("Feasibility check for day $day, hour $hour, scenario $scenario, index $index")
                data_dict["$day"]["$hour"]["$scenario"] = feasibility_check
                result_feasibility_checks["$day"]["$hour"]["$scenario"] = _PMACDC.run_acdcopf(feasibility_check,model,optimizer; setting = settings)
                result_feasibility_checks["$day"]["$hour"]["$scenario"]["probability"] = grid["nw"]["$index"]["probability"]    
            end
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
    else
        # fix this here, you do not get feasibility checks because of this
        if haskey(result_bs["$day"],"$hour")
            feasibility_check = deepcopy(grid["nw"]["$index"])
            feasibility_check_input = deepcopy(grid["nw"]["$index"])
            _SPMTA.prepare_AC_feasibility_check_stochastic(result_bs["$day"]["$hour"]["solution"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
            println("Feasibility check for day $day, hour $hour, no scenario, index $index")
            data_dict["$day"]["$hour"] = feasibility_check
            result_feasibility_checks["$day"]["$hour"] = _PMACDC.run_acdcopf(feasibility_check,model,optimizer; setting = settings)
            result_feasibility_checks["$day"]["$hour"]["probability"] = grid["nw"]["$index"]["probability"]    
        elseif haskey(result_bs["$day"],"solution")
            feasibility_check = deepcopy(grid["nw"]["$index"])
            feasibility_check_input = deepcopy(grid["nw"]["$index"])
            _SPMTA.prepare_AC_feasibility_check_stochastic(result_bs["$day"]["solution"]["nw"]["$hour"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
            println("Feasibility check for day $day, hour $hour, no scenarios, index $index")
            data_dict["$day"]["$hour"] = feasibility_check
            result_feasibility_checks["$day"]["$hour"] = _PMACDC.run_acdcopf(feasibility_check,model,optimizer; setting = settings)
            result_feasibility_checks["$day"]["$hour"]["probability"] = grid["nw"]["$index"]["probability"]    
        end
    end
end




types = ["forecasted","average","measured"]
for type in types
    if type == "forecasted"
        one_topology_all_days_forecasted = upload_results(n_days,results_folder,case,first_hour,last_hour,"one_topology_$(type)")    
        fc_forecasted = feasibility_check_days(one_topology_all_days_forecasted,scenario_wind,forecasted_wind,one_scenario,"one_topology",type,first_hour,last_hour)
    elseif type == "average"
        one_topology_all_days_average = upload_results(n_days,results_folder,case,first_hour,last_hour,"one_topology_$(type)")    
        fc_average = feasibility_check_days(one_topology_all_days_average,scenario_wind,average_wind,one_scenario,"one_topology",type,first_hour,last_hour)
    elseif type == "measured"
        one_topology_all_days_measured = upload_results(n_days,results_folder,case,first_hour,last_hour,"one_topology_$(type)")    
        fc_measured = feasibility_check_days(one_topology_all_days_measured,scenario_wind,measured_wind,one_scenario,"one_topology",type,first_hour,last_hour)
    end
end

for type in types
    if type == "forecasted"
        one_sw_action_all_days_forecasted = upload_results(n_days,results_folder,case,first_hour,last_hour,"one_maximum_actions_$(type)")    
        fc_forecasted = feasibility_check_days(one_sw_action_all_days_forecasted,scenario_wind,forecasted_wind,one_scenario,"one_maximum_actions",type,first_hour,last_hour)
    elseif type == "average"
        one_sw_action_all_days_average = upload_results(n_days,results_folder,case,first_hour,last_hour,"one_maximum_actions_$(type)")    
        fc_average = feasibility_check_days(one_sw_action_all_days_average,scenario_wind,average_wind,one_scenario,"one_maximum_actions",type,first_hour,last_hour)
    elseif type == "measured"
        one_sw_action_all_days_measured = upload_results(n_days,results_folder,case,first_hour,last_hour,"one_maximum_actions_$(type)")    
        fc_measured = feasibility_check_days(one_sw_measured,scenario_wind,measured_wind,one_scenario,"one_maximum_actions_",type,first_hour,last_hour)
    end
end

for type in types
    if type == "forecasted"
    #    two_sw_action_all_days_forecasted = upload_results(n_days,results_folder,case,first_hour,last_hour,"two_maximum_actions_$(type)")    
    #    fc_forecasted = feasibility_check_days(two_sw_action_all_days_forecasted,scenario_wind,forecasted_wind,one_scenario,"two_maximum_actions",type,first_hour,last_hour)
    #elseif type == "average"
    #    two_sw_action_all_days_average = upload_results(n_days,results_folder,case,first_hour,last_hour,"two_maximum_actions_$(type)")    
    #    fc_average = feasibility_check_days(two_sw_action_all_days_average,scenario_wind,average_wind,two_scenario,"two_maximum_actions",type,first_hour,last_hour)
    elseif type == "measured"
        two_sw_action_all_days_measured = upload_results(n_days,results_folder,case,first_hour,last_hour,"two_maximum_actions_$(type)")    
        fc_measured = feasibility_check_days(two_sw_action_all_days_measured,scenario_wind,measured_wind,one_scenario,"two_maximum_actions_",type,first_hour,last_hour)
    end
end

for type in types
    if type == "forecasted"
        #hourly_bs_all_days_forecasted = upload_results_all_days(results_folder,case,first_hour,last_hour,"hourly_bs_$(type)")    
        fc_forecasted = feasibility_check_days(hourly_bs_forecasted,scenario_wind,forecasted_wind,one_scenario,"hourly_bs",type,first_hour,last_hour)
    elseif type == "average"
        #hourly_bs_all_days_average = upload_results_all_days(results_folder,case,first_hour,last_hour,"hourly_bs_$(type)")    
        fc_average = feasibility_check_days(hourly_bs_average,scenario_wind,average_wind,one_scenario,"hourly_bs",type,first_hour,last_hour)
    elseif type == "measured"
        #hourly_bs_all_days_measured = upload_results_all_days(results_folder,case,first_hour,last_hour,"hourly_bs_$(type)")    
        fc_measured = feasibility_check_days(hourly_bs_measured,scenario_wind,measured_wind,one_scenario,"hourly_bs",type,first_hour,last_hour)
    end
end


fc_forecasted = upload_results_all_days(results_folder,case,first_hour,last_hour,"fc_One_topology_forecasted")
fc_average    = upload_results_all_days(results_folder,case,first_hour,last_hour,"fc_One_topology_average")
fc_measured   = upload_results_all_days(results_folder,case,first_hour,last_hour,"fc_One_topology_measured")

fc_hourly_forecasted = JSON.parsefile(joinpath(results_folder,case,"fc_hourly_bs_forecasted_$(first_hour)_$(last_hour)_all_days.json"))
fc_hourly_average    = JSON.parsefile(joinpath(results_folder,case,"fc_hourly_bs_average_$(first_hour)_$(last_hour)_all_days.json"))
fc_hourly_measured   = JSON.parsefile(joinpath(results_folder,case,"fc_hourly_bs_measured_$(first_hour)_$(last_hour)_all_days.json"))


######################### Scenarios ############################
type = "ciao"

hourly_bs_scenarios_6 = upload_results_all_days(results_folder,case,first_hour,last_hour,"Hourly_bs_stochastic_Laplace_6_scenarios")
hourly_bs_scenarios_8 = upload_results_all_days(results_folder,case,first_hour,last_hour,"Hourly_bs_stochastic_Laplace_8_scenarios")

fc_hourly_bs_scenarios_6 = feasibility_check_days(hourly_bs_scenarios_6,scenario_wind_6,forecasted_wind,6,"Hourly_bs_stochastic_Laplace_6_scenarios",type,first_hour,last_hour)
fc_hourly_bs_scenarios_8 = feasibility_check_days(hourly_bs_scenarios_8,scenario_wind_8,forecasted_wind,8,"Hourly_bs_stochastic_Laplace_8_scenarios",type,first_hour,last_hour)

###############

one_topology_scenarios_6 = upload_results_all_days(results_folder,case,first_hour,last_hour,"24_hours_BS_one_topology_stochastic_Laplace_6_scenarios")
one_topology_scenarios_8 = upload_results_all_days(results_folder,case,first_hour,last_hour,"24_hours_BS_one_topology_stochastic_Laplace_8_scenarios")

fc_one_topology_scenarios_6 = feasibility_check_days(one_topology_scenarios_6,scenario_wind_6,forecasted_wind,6,"24_hours_BS_one_topology_stochastic_Laplace_6_scenarios",type,first_hour,last_hour)
fc_one_topology_scenarios_8 = feasibility_check_days(one_topology_scenarios_8,scenario_wind_8,forecasted_wind,8,"24_hours_BS_one_topology_stochastic_Laplace_8_scenarios",type,first_hour,last_hour)

###############

one_sw_scenarios_6 = upload_results_all_days(results_folder,case,first_hour,last_hour,"24_hours_BS_one_sw_stochastic_Laplace_6_scenarios")
one_sw_scenarios_8 = upload_results_all_days(results_folder,case,first_hour,last_hour,"24_hours_BS_one_sw_stochastic_Laplace_8_scenarios")

fc_one_sw_scenarios_6 = feasibility_check_days(one_sw_scenarios_6,scenario_wind_6,forecasted_wind,6,"24_hours_BS_one_sw_stochastic_Laplace_6_scenarios",type,first_hour,last_hour)
fc_one_sw_scenarios_8 = feasibility_check_days(one_sw_scenarios_8,scenario_wind_8,forecasted_wind,8,"24_hours_BS_one_sw_stochastic_Laplace_8_scenarios",type,first_hour,last_hour)

###############

two_sw_scenarios_6 = upload_results_all_days(results_folder,case,first_hour,last_hour,"24_hours_BS_two_sw_stochastic_Laplace_6_scenarios")
two_sw_scenarios_8 = upload_results_all_days(results_folder,case,first_hour,last_hour,"24_hours_BS_two_sw_stochastic_Laplace_8_scenarios")

fc_two_sw_scenarios_6 = feasibility_check_days(two_sw_scenarios_6,scenario_wind_6,forecasted_wind,6,"24_hours_BS_two_sw_stochastic_Laplace_6_scenarios",type,first_hour,last_hour)
fc_two_sw_scenarios_8 = feasibility_check_days(two_sw_scenarios_8,scenario_wind_8,forecasted_wind,8,"24_hours_BS_two_sw_stochastic_Laplace_8_scenarios",type,first_hour,last_hour)
