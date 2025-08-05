using PowerModels; const _PM = PowerModels
using PowerModelsACDC; const _PMACDC = PowerModelsACDC
import PowerModelsTopologicalActionsII; const _PMTP = PowerModelsTopologicalActionsII
using FlexPlan; const _FP = FlexPlan
using Gurobi, Ipopt, JSON, Plots
import StochasticPowerModelsTopologicalActions; const _SPMTA = StochasticPowerModelsTopologicalActions
using JuMP, Juniper, HSL_jll, MathOptInterface, HiGHS
using Statistics
using PowerPlots
using StatsBase

mip_gap = 1e-4
gurobi_bs = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 5400,"MIPGap" => mip_gap,"BarHomogeneous" => 1, "NumericFocus"=>2) 
gurobi_opf = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 1200,"MIPGap" => mip_gap,"BarHomogeneous" => 1, "NumericFocus"=>2,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "ScaleFlag"=>2, "NumericFocus"=>3) 
ipopt = JuMP.optimizer_with_attributes(Ipopt.Optimizer, "tol" => 1e-6, "print_level" => 0,"linear_solver" => "ma97")

sc = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true)



first_hour = 8153
last_hour  = 8488

#first_hour = 355
#last_hour  = 378



n_hours = last_hour - first_hour + 1
n_scenarios = 6
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
case = "case_24/stochastic_multistep"

test_case = _PM.parse_file(test_case_file)
test_case_opf = deepcopy(test_case)

# THIS IS APPARENTLY FUNDAMENTAL TO GUARANTEE FEASIBILITY
_SPMTA.add_VOLL_generators(test_case_opf)
_SPMTA.add_VOLL_generators(test_case)

opf_30 = _PM.solve_opf(test_case_opf, LPACCPowerModel, ipopt)

test_case_bs = deepcopy(test_case_opf)
splitted_bus_ac = 6
test_case_bs,  switches_couples_ac,  extremes_ZILs_ac  = _PMTP.AC_busbar_split_AC_grid(test_case,splitted_bus_ac)

function compute_computational_time(result_dict,n_days,n_hours,n_hours_per_day,n_scenarios)
    solve_time_vector = []
    for day in 1:n_days
        if length(result_dict["$day"]) == n_hours_per_day
            for hour in 1:n_hours_per_day
                if n_scenarios > 1
                    for scenario in 1:n_scenarios
                        timestep = (day - 1)*n_hours_per_day*n_scenarios + (hour - 1)*n_scenarios + scenario
                        #if haskey(result_dict,"$timestep")
                        #    push!(solve_time_vector,result_dict["$timestep"]["solution"]["solve_time"])
                        #if haskey(result_dict,"$day") && haskey(result_dict["$day"],"$hour") && haskey(result_dict["$day"]["$hour"],"$scenario")
                            push!(solve_time_vector,result_dict["$day"]["$hour"]["solve_time"])
                        #end
                    end
                else
                    timestep = (day - 1)*n_hours_per_day + (hour - 1)
                    push!(solve_time_vector,result_dict["$day"]["$hour"]["solve_time"])
                end
            end
        elseif length(result_dict["$day"]) == 8
            for hour in 1:n_hours_per_day
                if n_scenarios > 1
                    for scenario in 1:n_scenarios
                        timestep = (day - 1)*n_hours_per_day*n_scenarios + (hour - 1)*n_scenarios + scenario
                        #if haskey(result_dict,"$timestep")
                        #    push!(solve_time_vector,result_dict["$timestep"]["solution"]["solve_time"])
                        #if haskey(result_dict,"$day") && haskey(result_dict["$day"],"$hour") && haskey(result_dict["$day"]["$hour"],"$scenario")
                            push!(solve_time_vector,result_dict["$day"]["solve_time"])
                        #end
                    end
                else
                    timestep = (day - 1)*n_hours_per_day + (hour - 1)
                    push!(solve_time_vector,result_dict["$day"]["solve_time"])
                end
            end
        end
    end
    avg_time = mean(solve_time_vector)
    max_time = maximum(solve_time_vector)
    min_time = minimum(solve_time_vector)
    return avg_time, max_time, min_time
end


#########################################################################################
## Processing input data
scenario_wind = JSON.parsefile(joinpath(input_folder,"case30","Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour).json"))
measured_wind = JSON.parsefile(joinpath(input_folder,"case30","measured_two_weeks_$(first_hour)_$(last_hour).json"))
forecasted_wind = JSON.parsefile(joinpath(input_folder,"case30","forecasted_two_weeks_$(first_hour)_$(last_hour).json"))

hourly_opf = JSON.parsefile(joinpath(results_folder,case,"Hourly_opf_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour).json"))
hourly_opf_measured = JSON.parsefile(joinpath(results_folder,case,"Hourly_opf_measured_$(first_hour)_$(last_hour).json"))
hourly_opf_forecasted = JSON.parsefile(joinpath(results_folder,case,"Hourly_opf_forecasted_$(first_hour)_$(last_hour).json"))
hourly_opf_average = JSON.parsefile(joinpath(results_folder,case,"Hourly_opf_average_$(first_hour)_$(last_hour).json"))

################### Hourly optimization ########################
bs_hourly_forecasted = JSON.parsefile(joinpath(results_folder,case,"hourly_bs_forecasted_$(first_hour)_$(last_hour)_all_days.json"))
feasibility_check_bs_hourly_forecasted  = JSON.parsefile(joinpath(results_folder,case,"fc_hourly_bs_forecasted_$(first_hour)_$(last_hour)_all_days.json")) 

bs_hourly_measured = JSON.parsefile(joinpath(results_folder,case,"hourly_bs_measured_$(first_hour)_$(last_hour)_all_days.json"))
feasibility_check_bs_hourly_measured  = JSON.parsefile(joinpath(results_folder,case,"fc_hourly_bs_measured_$(first_hour)_$(last_hour)_all_days.json")) 


compute_computational_time(bs_hourly_forecasted,n_days,n_hours,n_hours_per_day,one_scenario)
compute_computational_time(bs_hourly_measured,n_days,n_hours,n_hours_per_day,one_scenario)


################### One topology ########################
bs_one_topology_forecasted = JSON.parsefile(joinpath(results_folder,case,"One_topology_forecasted_$(first_hour)_$(last_hour)_all_days.json"))
feasibility_check_one_topology_forecasted  = JSON.parsefile(joinpath(results_folder,case,"fc_one_topology_forecasted_$(first_hour)_$(last_hour)_all_days.json")) 

bs_one_topology_measured = JSON.parsefile(joinpath(results_folder,case,"One_topology_measured_$(first_hour)_$(last_hour)_all_days.json"))
feasibility_check_one_topology_measured  = JSON.parsefile(joinpath(results_folder,case,"fc_one_topology_measured_$(first_hour)_$(last_hour)_all_days.json")) 

compute_computational_time(bs_one_topology_forecasted,n_days,n_hours,n_hours_per_day,one_scenario)
compute_computational_time(bs_one_topology_measured,n_days,n_hours,n_hours_per_day,one_scenario)


################### One switching action ########################
bs_one_maximum_actions_forecasted = JSON.parsefile(joinpath(results_folder,case,"One_maximum_actions_forecasted_$(first_hour)_$(last_hour)_all_days.json"))
feasibility_check_one_maximum_actions_forecasted  = JSON.parsefile(joinpath(results_folder,case,"fc_one_maximum_actions_forecasted_$(first_hour)_$(last_hour)_all_days.json")) 

bs_one_maximum_actions_measured = JSON.parsefile(joinpath(results_folder,case,"one_maximum_actions_measured_$(first_hour)_$(last_hour)_all_days.json"))
feasibility_check_one_maximum_actions_measured  = JSON.parsefile(joinpath(results_folder,case,"fc_one_maximum_actions_measured_$(first_hour)_$(last_hour)_all_days.json")) 

compute_computational_time(bs_one_maximum_actions_forecasted,n_days,n_hours,n_hours_per_day,one_scenario)
compute_computational_time(bs_one_maximum_actions_measured,n_days,n_hours,n_hours_per_day,one_scenario)


################### Two switching actions ########################
bs_two_maximum_actions_forecasted = JSON.parsefile(joinpath(results_folder,case,"Two_maximum_actions_forecasted_$(first_hour)_$(last_hour)_all_days.json"))
feasibility_check_two_maximum_actions_forecasted  = JSON.parsefile(joinpath(results_folder,case,"fc_two_maximum_actions_forecasted_$(first_hour)_$(last_hour)_all_days.json")) 

bs_two_maximum_actions_measured = JSON.parsefile(joinpath(results_folder,case,"two_maximum_actions_measured_$(first_hour)_$(last_hour)_all_days.json"))
feasibility_check_two_maximum_actions_measured  = JSON.parsefile(joinpath(results_folder,case,"fc_two_maximum_actions_measured_$(first_hour)_$(last_hour)_all_days.json")) 

#bs_two_maximum_actions_average = JSON.parsefile(joinpath(results_folder,case,"two_maximum_actions_average_$(first_hour)_$(last_hour)_all_days.json"))
#feasibility_check_two_maximum_actions_average  = JSON.parsefile(joinpath(results_folder,case,"fc_two_maximum_actions_average_$(first_hour)_$(last_hour)_all_days.json")) 

compute_computational_time(bs_two_maximum_actions_forecasted,n_days,n_hours,n_hours_per_day,one_scenario)
compute_computational_time(bs_two_maximum_actions_measured,n_days,n_hours,n_hours_per_day,one_scenario)

####################################################################### Scenarios ###############
################### Hourly optimization ########################
bs_hourly_6_scenarios = JSON.parsefile(joinpath(results_folder,case,"Hourly_bs_stochastic_Laplace_6_scenarios_$(first_hour)_$(last_hour)_all_days.json"))
bs_hourly_8_scenarios = JSON.parsefile(joinpath(results_folder,case,"Hourly_bs_stochastic_Laplace_8_scenarios_$(first_hour)_$(last_hour)_all_days.json"))

compute_computational_time(bs_hourly_6_scenarios,n_days,n_hours,n_hours_per_day,one_scenario)
compute_computational_time(bs_hourly_8_scenarios,n_days,n_hours,n_hours_per_day,one_scenario)

################### One topology ########################
one_topology_6_scenarios = JSON.parsefile(joinpath(results_folder,case,"One_topology_stochastic_Laplace_6_scenarios_$(first_hour)_$(last_hour)_all_days.json"))
one_topology_8_scenarios = JSON.parsefile(joinpath(results_folder,case,"One_topology_stochastic_Laplace_8_scenarios_$(first_hour)_$(last_hour)_all_days.json"))

dict_try = Dict{String,Any}()
time = []
for day in 1:n_days
    dict_try["$day"] = deepcopy(JSON.parsefile(joinpath(results_folder,case,"24_hours_BS_one_topology_stochastic_Laplace_6_scenarios_$(first_hour)_$(last_hour)_day_$(day).json"))) 
    push!(time,dict_try["$day"]["solve_time"])
end
[mean(time),maximum(time),minimum(time)]

dict_try = Dict{String,Any}()
time = []
for day in 1:n_days
    dict_try["$day"] = deepcopy(JSON.parsefile(joinpath(results_folder,case,"One_topology_stochastic_Laplace_8_scenarios_$(first_hour)_$(last_hour)_day_$(day).json"))) 
    push!(time,dict_try["$day"]["solve_time"])
end
[mean(time),maximum(time),minimum(time)]

################### One switching action ########################
bs_one_maximum_actions_forecasted = JSON.parsefile(joinpath(results_folder,case,"One_maximum_actions_forecasted_$(first_hour)_$(last_hour)_all_days.json"))
bs_one_maximum_actions_measured = JSON.parsefile(joinpath(results_folder,case,"one_maximum_actions_measured_$(first_hour)_$(last_hour)_all_days.json"))

dict_try = Dict{String,Any}()
time = []
for day in 1:n_days
    dict_try["$day"] = deepcopy(JSON.parsefile(joinpath(results_folder,case,"One_maximum_actions_stochastic_Laplace_6_scenarios_$(first_hour)_$(last_hour)_day_$(day).json"))) 
    push!(time,dict_try["$day"]["solve_time"])
end
[mean(time),maximum(time),minimum(time)]

dict_try = Dict{String,Any}()
time = []
for day in 1:n_days
    dict_try["$day"] = deepcopy(JSON.parsefile(joinpath(results_folder,case,"One_maximum_actions_stochastic_Laplace_8_scenarios_$(first_hour)_$(last_hour)_day_$(day).json"))) 
    push!(time,dict_try["$day"]["solve_time"])
end
[mean(time),maximum(time),minimum(time)]


################### Two switching actions ########################
bs_two_maximum_actions_forecasted = JSON.parsefile(joinpath(results_folder,case,"Two_maximum_actions_forecasted_$(first_hour)_$(last_hour)_all_days.json"))
feasibility_check_two_maximum_actions_forecasted  = JSON.parsefile(joinpath(results_folder,case,"fc_two_maximum_actions_forecasted_$(first_hour)_$(last_hour)_all_days.json")) 

bs_two_maximum_actions_measured = JSON.parsefile(joinpath(results_folder,case,"two_maximum_actions_measured_$(first_hour)_$(last_hour)_all_days.json"))
feasibility_check_two_maximum_actions_measured  = JSON.parsefile(joinpath(results_folder,case,"fc_two_maximum_actions_measured_$(first_hour)_$(last_hour)_all_days.json")) 

#bs_two_maximum_actions_average = JSON.parsefile(joinpath(results_folder,case,"two_maximum_actions_average_$(first_hour)_$(last_hour)_all_days.json"))
#feasibility_check_two_maximum_actions_average  = JSON.parsefile(joinpath(results_folder,case,"fc_two_maximum_actions_average_$(first_hour)_$(last_hour)_all_days.json")) 

dict_try = Dict{String,Any}()
time = []
for day in 1:n_days
    dict_try["$day"] = deepcopy(JSON.parsefile(joinpath(results_folder,case,"Two_maximum_actions_stochastic_Laplace_6_scenarios_$(first_hour)_$(last_hour)_day_$(day).json"))) 
    push!(time,dict_try["$day"]["solve_time"])
end
[mean(time),maximum(time),minimum(time)]

dict_try = Dict{String,Any}()
time = []
for day in 1:n_days
    dict_try["$day"] = deepcopy(JSON.parsefile(joinpath(results_folder,case,"24_hours_BS_two_sw_stochastic_Laplace_8_scenarios_$(first_hour)_$(last_hour)_day_$(day).json"))) 
    push!(time,dict_try["$day"]["solve_time"])
end
[mean(time),maximum(time),minimum(time)]



#########################################################################################
test_case_bs_replicate = _PM.replicate(test_case_bs, n_hours_per_day*one_scenario)

function redispatch_scenarios(result_dict,result_bs,result_fc,realized_time_series)
    for i in scenarios
        test_case_bs_replicate = _PM.replicate(test_case_bs, n_hours*i)
        test_case_bs_scenarios = deepcopy(test_case_bs_replicate)
        test_case_bs_realized = deepcopy(test_case_bs_replicate)

        _SPMTA.adding_multinetwork_scenarios(test_case_bs_scenarios,n_hours,i,scenario_wind["$i"])
        _SPMTA.adding_multinetwork_scenarios(test_case_bs_realized,n_hours,i,scenario_wind["$i"])

        for hour in 1:n_hours
            for s in 1:i
                timestep = (hour - 1)*i + s
                test_case_bs_scenarios["nw"]["$timestep"]["gen"]["1"]["pmax"]   = deepcopy(test_case_bs_scenarios["nw"]["$timestep"]["gen"]["1"]["pmax"]*scenario_wind["$i"]["$timestep"]["samples_pu"])
                test_case_bs_realized["nw"]["$timestep"]["gen"]["1"]["pmax"]   = deepcopy(test_case_bs_scenarios["nw"]["$timestep"]["gen"]["1"]["pmax"]*realized_time_series[hour])
            end
        end
        result_dict["$i"] = Dict{String,Any}()
        result_dict["$i"] = _SPMTA.run_hourly_redispatch_stochastic_fc(test_case_bs_realized,test_case_bs_scenarios,result_bs["$i"],result_fc["$i"],ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s,n_hours,i)
    end
end

function adding_multinetwork_scenarios(test_case, n_hours, n_scenarios,uncertainty)
    for hour in 1:n_hours
        for scenario_idx in 1:n_scenarios
            n = (hour - 1)*n_scenarios + scenario_idx
            add_hour_scenario_probability(test_case,hour,scenario_idx,n_scenarios,n,uncertainty)
        end
    end
    test_case["scenarios"] = n_scenarios
    test_case["hours"] = n_hours
    return test_case
end

function add_hour_scenario_probability(data,hour,scenario_idx,n_scenarios,index,uncertainty)
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

function redispatch_scenarios_opf(result_dict,result_opf,scenario_wind,number_scenarios,n_hours,result_opf_measured)
    test_case_opf_replicate = _PM.replicate(test_case_opf, n_hours*number_scenarios)
    test_case_opf_mn_scenarios = deepcopy(test_case_opf_replicate)    
    test_case_opf_mn_realized = deepcopy(test_case_opf_replicate)  
    
    adding_multinetwork_scenarios(test_case_opf_mn_scenarios,n_hours,number_scenarios,scenario_wind)
    adding_multinetwork_scenarios(test_case_opf_mn_realized,n_hours,number_scenarios,scenario_wind)

    if number_scenarios > 1    
        for hour in 1:n_hours
            for scenario in 1:number_scenarios
                println("OPF redispatch for hour $hour, scenario $scenario")
                timestep = (hour - 1)*number_scenarios + scenario
                result_dict["$timestep"] = Dict{String,Any}()
            
                test_case_opf_mn_scenarios["nw"]["$timestep"]["gen"]["1"]["pmax"]  =  deepcopy(result_opf_measured["$hour"]["solution"]["gen"]["1"]["pg"])
                test_case_opf_mn_realized["nw"]["$timestep"]["gen"]["1"]["pmax"]   =  deepcopy(result_opf_measured["$hour"]["solution"]["gen"]["1"]["pg"])
                println("Pmax for generator 1 in test_case_opf_mn_scenarios is $(test_case_opf_mn_scenarios["nw"]["$timestep"]["gen"]["1"]["pmax"])")
                println("Pmax for generator 1 in test_case_opf_mn_realized is $(test_case_opf_mn_realized["nw"]["$timestep"]["gen"]["1"]["pmax"])")
     

            # Adding set points
                for (g_id,g) in test_case_opf_mn_scenarios["nw"]["$timestep"]["gen"]
                g["pg_start"] = result_opf["$timestep"]["solution"]["gen"][g_id]["pg"]
                g["qg_start"] = result_opf["$timestep"]["solution"]["gen"][g_id]["qg"]
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
                println("The pg start for gen 1 in test_case_opf_mn_scenarios is $(test_case_opf_mn_scenarios["nw"]["$timestep"]["gen"]["1"]["pg_start"])")
                println("The pmax for gen 1 in test_case_opf_mn_scenarios is $(test_case_opf_mn_scenarios["nw"]["$timestep"]["gen"]["1"]["pmax"])")

                test_case_opf_mn_scenarios["nw"]["$timestep"]["per_unit"] = true
                println("Running redispatch for hour $hour, scenario $scenario")
                result_dict["$timestep"] = _SPMTA.solve_acdc_full_redispatch_opf(test_case_opf_mn_scenarios["nw"]["$timestep"],ACPPowerModel,ipopt)
                result_dict["$timestep"]["probability"] = scenario_wind["$timestep"]["probability"]
            end
        end
    else
        for hour in 1:n_hours
                println("OPF redispatch for hour $hour")
                result_dict["$hour"] = Dict{String,Any}()
            
                test_case_opf_mn_scenarios["nw"]["$hour"]["gen"]["1"]["pmax"]  =  deepcopy(result_opf_measured["$hour"]["solution"]["gen"]["1"]["pg"])
                test_case_opf_mn_realized["nw"]["$hour"]["gen"]["1"]["pmax"]   =  deepcopy(result_opf_measured["$hour"]["solution"]["gen"]["1"]["pg"])
                println("Pmax for generator 1 in test_case_opf_mn_scenarios is $(test_case_opf_mn_scenarios["nw"]["$hour"]["gen"]["1"]["pmax"])")
                println("Pmax for generator 1 in test_case_opf_mn_realized is $(test_case_opf_mn_realized["nw"]["$hour"]["gen"]["1"]["pmax"])")
     

            # Adding set points
                for (g_id,g) in test_case_opf_mn_scenarios["nw"]["$hour"]["gen"]
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
                println("The pg start for gen 1 in test_case_opf_mn_scenarios is $(test_case_opf_mn_scenarios["nw"]["$hour"]["gen"]["1"]["pg_start"])")
                println("The pmax for gen 1 in test_case_opf_mn_scenarios is $(test_case_opf_mn_scenarios["nw"]["$hour"]["gen"]["1"]["pmax"])")

                test_case_opf_mn_scenarios["nw"]["$hour"]["per_unit"] = true
                println("Running redispatch for hour $hour")
                result_dict["$hour"] = _SPMTA.solve_acdc_full_redispatch_opf(test_case_opf_mn_scenarios["nw"]["$hour"],ACPPowerModel,ipopt)
        end  
    end  
end

function redispatch_scenarios_days(test_case_bs,result_dict,result_bs,result_fc,scenario_wind,realized_time_series,number_scenarios,day,n_hours_per_day,result_bs_measured,result_fc_measured)
    test_case_bs_replicate = _PM.replicate(test_case_bs, n_hours*number_scenarios)
    test_case_bs_scenarios = deepcopy(test_case_bs_replicate)
    test_case_bs_realized = deepcopy(test_case_bs_replicate)
    result_dict["$day"] = Dict{String,Any}()
    count_scenarios = 0
    if number_scenarios > 1
        for hour in 1:n_hours_per_day
            this_hour = (day - 1)*n_hours_per_day + hour
            result_dict["$day"]["$hour"] = Dict{String,Any}()
            for s in 1:number_scenarios
                count_scenarios += 1
                timestep = (day - 1)*n_hours_per_day*number_scenarios + (hour - 1)*number_scenarios + s
                println("Feasibility check and redispatch for day $day, hour $hour, scenario $s, timestep $timestep")

                adding_multinetwork_scenarios_days(test_case_bs_scenarios,n_hours_per_day,s,number_scenarios,scenario_wind,count_scenarios,hour)
                adding_multinetwork_scenarios_days(test_case_bs_realized,n_hours_per_day,s,number_scenarios,scenario_wind,count_scenarios,hour)        
                test_case_bs_scenarios["nw"]["$timestep"]["gen"]["1"]["pmax"]   = deepcopy(result_fc_measured["$day"]["$hour"]["solution"]["gen"]["1"]["pg"])
                test_case_bs_realized["nw"]["$timestep"]["gen"]["1"]["pmax"]   = deepcopy(result_fc_measured["$day"]["$hour"]["solution"]["gen"]["1"]["pg"])    
                feasibility_check = deepcopy(test_case_bs_realized["nw"]["$timestep"])
                feasibility_check_input = deepcopy(test_case_bs_realized["nw"]["$timestep"])
                feasibility_check["per_unit"] = true
                feasibility_check_input["per_unit"] = true
                if length(result_bs["$day"]) == n_hours_per_day
                    println("PDD Feasibility check & OPF and redispatch for day $day, hour $hour, scenario $s, timestep $timestep")
                    _SPMTA.prepare_AC_feasibility_check_stochastic(result_bs["$day"]["$hour"]["solution"]["nw"]["$s"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
                    result_dict["$day"]["$hour"]["$s"] = Dict{String,Any}()
                    result_dict["$day"]["$hour"]["$s"] = run_hourly_redispatch_stochastic_fc_days(feasibility_check,test_case_bs_scenarios,result_fc,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,sc,n_hours,number_scenarios,count_scenarios,day,hour,s)            
                elseif length(result_bs["$day"]["solution"]["nw"]) == n_hours_per_day*number_scenarios
                    println("DC Feasibility check & OPF and redispatch for day $day, hour $hour, scenario $s, timestep $timestep")
                    _SPMTA.prepare_AC_feasibility_check_stochastic(result_bs["$day"]["solution"]["nw"]["$count_scenarios"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
                    result_dict["$day"]["$hour"]["$s"] = Dict{String,Any}()
                    result_dict["$day"]["$hour"]["$s"] = run_hourly_redispatch_stochastic_fc_days(feasibility_check,test_case_bs_scenarios,result_fc,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,sc,n_hours,number_scenarios,count_scenarios,day,hour,s)            
                end
            end
        end
    else
        for hour in 1:n_hours_per_day
            this_hour = (day - 1)*n_hours_per_day + hour
            #result_dict["$day"]["$hour"] = Dict{String,Any}()
            println("Feasibility check and redispatch for day $day, hour $hour, one scenario")
            adding_multinetwork_scenarios_days(test_case_bs_scenarios,n_hours_per_day,number_scenarios,number_scenarios,scenario_wind,this_hour,hour) # not influencing anything
            adding_multinetwork_scenarios_days(test_case_bs_realized,n_hours_per_day ,number_scenarios,number_scenarios,scenario_wind,this_hour,hour) # not influencing anything        
            
            #test_case_bs_scenarios["nw"]["$this_hour"]["gen"]["1"]["pmax"]   = deepcopy(result_bs["$day"]["solution"]["nw"]["$hour"]["gen"]["1"]["pg"])
            #test_case_bs_realized["nw"]["$this_hour"]["gen"]["1"]["pmax"]   = deepcopy(result_bs_measured["$day"]["solution"]["nw"]["$hour"]["gen"]["1"]["pg"])#deepcopy(test_case_bs_realized["nw"]["$this_hour"]["gen"]["1"]["pmax"]*realized_time_series[this_hour])    
            
            test_case_bs_scenarios["nw"]["$this_hour"]["gen"]["1"]["pmax"]   = deepcopy(result_fc_measured["$day"]["$hour"]["solution"]["gen"]["1"]["pg"])
            test_case_bs_realized["nw"]["$this_hour"]["gen"]["1"]["pmax"]   = deepcopy(result_fc_measured["$day"]["$hour"]["solution"]["gen"]["1"]["pg"])#deepcopy(test_case_bs_realized["nw"]["$this_hour"]["gen"]["1"]["pmax"]*realized_time_series[this_hour])    
            

            feasibility_check = deepcopy(test_case_bs_scenarios["nw"]["$this_hour"])
            feasibility_check_input = deepcopy(test_case_bs_scenarios["nw"]["$this_hour"])
            feasibility_check["per_unit"] = true
            feasibility_check_input["per_unit"] = true
            if haskey(result_bs["$day"],"solution")
                if length(result_bs["$day"]["solution"]["nw"]) == n_hours_per_day
                    println("PDD Feasibility check & OPF and redispatch for day $day, hour $hour")
                    _SPMTA.prepare_AC_feasibility_check_stochastic(result_bs["$day"]["solution"]["nw"]["$hour"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
                    result_dict["$day"]["$hour"] = run_hourly_redispatch_stochastic_fc_days(feasibility_check,test_case_bs_scenarios,result_fc,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,sc,n_hours,number_scenarios,hour,day,hour,s)            
                elseif length(result_bs["$day"]["solution"]["nw"]) == n_hours_per_day*number_scenarios
                    println("DC Feasibility check & OPF and redispatch for day $day, hour $hour")
                    _SPMTA.prepare_AC_feasibility_check_stochastic(result_bs["$day"]["solution"]["nw"]["$hour"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
                    result_dict["$day"]["$hour"] = run_hourly_redispatch_stochastic_fc_days(feasibility_check,test_case_bs_scenarios,result_fc,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,sc,n_hours,number_scenarios,hour,day,hour,s)            
                end
            else
                if length(result_bs["$day"]) == n_hours_per_day
                    println("PDD Feasibility check & OPF and redispatch for day $day, hour $hour")
                    _SPMTA.prepare_AC_feasibility_check_stochastic(result_bs["$day"]["$hour"]["solution"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
                    result_dict["$day"]["$hour"] = run_hourly_redispatch_stochastic_fc_days(feasibility_check,test_case_bs_scenarios,result_fc,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,sc,n_hours,number_scenarios,hour,day,hour,s)            
                end
            end
        end
    end
end

function run_hourly_redispatch_stochastic_fc_days(grid, stochastic_grid, results_fc, model, optimizer,switches_couples_ac,extremes_ZILs_ac,test_case_opf,settings,n_hours,n_scenarios,timestep,day,hour,scenario)
    result_feasibility_checks = Dict{String,Any}()
    result_feasibility_checks["$hour"] = Dict{String,Any}()
        if n_scenarios > 1 
                    result_feasibility_checks["$hour"]["$scenario"] = Dict{String,Any}()
                    feasibility_check = deepcopy(grid)
                    feasibility_check_input = deepcopy(grid)
                    #_SPMTA.prepare_AC_feasibility_check_stochastic(result_bs["solution"]["nw"]["$timestep"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)

                    # Adding set points
                    for (g_id,g) in feasibility_check["gen"]
                        g["pg_start"] = results_fc["$day"]["$hour"]["$scenario"]["solution"]["gen"][g_id]["pg"]
                        g["qg_start"] = results_fc["$day"]["$hour"]["$scenario"]["solution"]["gen"][g_id]["qg"]
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
                    
                    result_feasibility_checks = _SPMTA.solve_acdc_full_redispatch_opf(feasibility_check,model,optimizer)
                    result_feasibility_checks["probability"] = stochastic_grid["nw"]["$timestep"]["probability"]
        else
                    result_feasibility_checks["$hour"] = Dict{String,Any}()
                    feasibility_check = deepcopy(grid)
                    feasibility_check_input = deepcopy(grid)
                    #feasibility_check["gen"]["1"]["pmax"] = test_case_opf["gen"]["1"]["pmax"]*measured_wind[hour]
                    #_SPMTA.prepare_AC_feasibility_check_stochastic(result_bs["$hour"]["solution"]["nw"]["$s"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)

                    # Adding set points
                    for (g_id,g) in feasibility_check["gen"]
                        g["pg_start"] = results_fc["$day"]["$hour"]["solution"]["gen"][g_id]["pg"]
                        g["qg_start"] = results_fc["$day"]["$hour"]["solution"]["gen"][g_id]["qg"]
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
                
                    result_feasibility_checks = _SPMTA.solve_acdc_full_redispatch_opf(feasibility_check,model,optimizer)
                    result_feasibility_checks["probability"] = 1.0
        end
    return result_feasibility_checks
end

function add_hour_scenario_probability_days(data,hour,scenario_idx,n_scenarios,uncertainty,index)
    data["nw"]["$index"]["hour"] = hour
    data["nw"]["$index"]["hour_scenario_index"] = [hour,scenario_idx,index]
    if n_scenarios == 1
        data["nw"]["$index"]["probability"] = 1.0
        data["nw"]["$index"]["per_unit"] = true
    elseif n_scenarios > 1
        data["nw"]["$index"]["scenario"] = scenario_idx
        data["nw"]["$index"]["probability"] = uncertainty["$index"]["probability"]
        data["nw"]["$index"]["per_unit"] = true
    end
end

function adding_multinetwork_scenarios_days(test_case, n_hours,scenario_idx, n_scenarios,uncertainty,index,hour)
    add_hour_scenario_probability_days(test_case,hour,scenario_idx,n_scenarios,uncertainty,index)
    test_case["scenarios"] = n_scenarios
    test_case["hours"] = n_hours
end

function save_redispatch_days(test_case_bs,results_bs,results_fc,realized_time_series,scenario_wind,n_scenarios,n_days,file_name,result_bs_measured,results_fc_measured)
    redispatch_results       = Dict{String,Any}()
    for day in 1:n_days
        redispatch_scenarios_days(test_case_bs,redispatch_results,results_bs,results_fc,scenario_wind,realized_time_series,n_scenarios,day,n_hours_per_day,result_bs_measured,results_fc_measured)
    end
    json_redispatch_results = JSON.json(redispatch_results)
    if n_scenarios > 1
        open(joinpath(results_folder,case,"redispatch_results_$(file_name)_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_all_days.json"),"w") do f 
            write(f, json_redispatch_results) 
        end 
    else
        open(joinpath(results_folder,case,"redispatch_results_$(file_name)_$(first_hour)_$(last_hour)_all_days.json"),"w") do f 
            write(f, json_redispatch_results) 
        end 
    end
end   


#########################################################################################

redispatch_results = Dict{String,Any}()
redispatch_results_forecasted = Dict{String,Any}()
for day in 1:14
    redispatch_scenarios_days(test_case_bs,redispatch_results,bs_one_topology_measured,feasibility_check_one_topology_measured,scenario_wind,measured_wind,one_scenario,day,n_hours_per_day,bs_one_topology_measured,feasibility_check_one_topology_measured)
end
for day in 1:14
    redispatch_scenarios_days(test_case_bs,redispatch_results_forecasted,bs_one_topology_forecasted,feasibility_check_one_topology_forecasted,scenario_wind,measured_wind,one_scenario,day,n_hours_per_day,bs_one_topology_measured,feasibility_check_one_topology_measured)
end


################### Hourly bs ########################
save_redispatch_days(test_case_bs,bs_hourly_measured  ,feasibility_check_bs_hourly_measured,measured_wind  ,scenario_wind,one_scenario,n_days,"bs_hourly_measured"  ,bs_hourly_measured,feasibility_check_bs_hourly_measured)
save_redispatch_days(test_case_bs,bs_hourly_forecasted,feasibility_check_bs_hourly_forecasted,measured_wind,scenario_wind,one_scenario,n_days,"bs_hourly_forecasted",bs_hourly_measured,feasibility_check_bs_hourly_measured)
save_redispatch_days(test_case_bs,bs_hourly_average   ,feasibility_check_bs_hourly_average,measured_wind   ,scenario_wind,one_scenario,n_days,"bs_hourly_average"   ,bs_hourly_measured,feasibility_check_bs_hourly_measured)


result_redispatch_bs_hourly_measured_check   = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_bs_hourly_measured_$(first_hour)_$(last_hour)_all_days.json"))
result_redispatch_bs_hourly_forecasted_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_bs_hourly_forecasted_$(first_hour)_$(last_hour)_all_days.json"))
result_redispatch_bs_hourly_average_check    = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_bs_hourly_average_$(first_hour)_$(last_hour)_all_days.json"))


pg_down_1 = []
termination_statuses = []
termination_statuses_1_0 = []
sum_redispatch_costs = 0.0
sum_redispatch_costs_with_infeasibilities = 0.0
count_infeasibilities = 0
for day in 1:n_days
    for hour in 1:n_hours_per_day
        push!(pg_down_1,result_redispatch_average_check["$day"]["$hour"]["solution"]["gen"]["1"]["pg_down"])
        push!(termination_statuses,result_redispatch_average_check["$day"]["$hour"]["termination_status"])
        sum_redispatch_costs_with_infeasibilities += result_redispatch_average_check["$day"]["$hour"]["objective"]
        if result_redispatch_average_check["$day"]["$hour"]["termination_status"] == "LOCALLY_SOLVED"
            push!(termination_statuses_1_0,0.0)
            sum_redispatch_costs += result_redispatch_average_check["$day"]["$hour"]["objective"]
        else
            count_infeasibilities += 1
            push!(termination_statuses_1_0,1.0)
        end
    end
end 
plot(pg_down_1)#,ylims = (0.01,1.1))
scatter!(termination_statuses_1_0)



################### One topology ########################
save_redispatch_days(test_case_bs,bs_one_topology_measured,feasibility_check_one_topology_measured,measured_wind,scenario_wind,one_scenario,n_days,"one_topology_measured",bs_one_topology_measured,feasibility_check_one_topology_measured)
save_redispatch_days(test_case_bs,bs_one_topology_forecasted,feasibility_check_one_topology_forecasted,measured_wind,scenario_wind,one_scenario,n_days,"one_topology_forecasted",bs_one_topology_measured,feasibility_check_one_topology_measured)
save_redispatch_days(test_case_bs,bs_one_topology_average,feasibility_check_one_topology_average,measured_wind,scenario_wind,one_scenario,n_days,"one_topology_average",bs_one_topology_measured,feasibility_check_one_topology_measured)


result_redispatch_one_topology_measured_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_one_topology_measured_$(first_hour)_$(last_hour)_all_days.json"))
result_redispatch_one_topology_forecasted_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_one_topology_forecasted_$(first_hour)_$(last_hour)_all_days.json"))
result_redispatch_one_topology_average_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_one_topology_average_$(first_hour)_$(last_hour)_all_days.json"))


pg_down_1 = []
termination_statuses = []
termination_statuses_1_0 = []
sum_redispatch_costs = 0.0
sum_redispatch_costs_with_infeasibilities = 0.0
count_infeasibilities = 0
for day in 1:n_days
    for hour in 1:n_hours_per_day
        push!(pg_down_1,result_redispatch_average_check["$day"]["$hour"]["solution"]["gen"]["1"]["pg_down"])
        push!(termination_statuses,result_redispatch_average_check["$day"]["$hour"]["termination_status"])
        sum_redispatch_costs_with_infeasibilities += result_redispatch_average_check["$day"]["$hour"]["objective"]
        if result_redispatch_average_check["$day"]["$hour"]["termination_status"] == "LOCALLY_SOLVED"
            push!(termination_statuses_1_0,0.0)
            sum_redispatch_costs += result_redispatch_average_check["$day"]["$hour"]["objective"]
        else
            count_infeasibilities += 1
            push!(termination_statuses_1_0,1.0)
        end
    end
end 
plot(pg_down_1)#,ylims = (0.01,1.1))
scatter!(termination_statuses_1_0)


################### One switching action ########################
save_redispatch_days(test_case_bs,bs_one_maximum_actions_measured,feasibility_check_one_maximum_actions_measured,measured_wind,scenario_wind,one_scenario,n_days,"one_maximum_actions_measured",bs_one_maximum_actions_measured,feasibility_check_one_maximum_actions_measured)
save_redispatch_days(test_case_bs,bs_one_maximum_actions_forecasted,feasibility_check_one_maximum_actions_forecasted,measured_wind,scenario_wind,one_scenario,n_days,"one_maximum_actions_forecasted",bs_one_maximum_actions_measured,feasibility_check_one_maximum_actions_measured)
save_redispatch_days(test_case_bs,bs_one_maximum_actions_average,feasibility_check_one_maximum_actions_average,measured_wind,scenario_wind,one_scenario,n_days,"one_maximum_actions_average",bs_one_maximum_actions_measured,feasibility_check_one_maximum_actions_measured)


result_redispatch_one_max_action_measured_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_one_maximum_actions_measured_$(first_hour)_$(last_hour)_all_days.json"))
result_redispatch_one_max_action_forecasted_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_one_maximum_actions_forecasted_$(first_hour)_$(last_hour)_all_days.json"))
result_redispatch_one_max_action_average_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_one_maximum_actions_average_$(first_hour)_$(last_hour)_all_days.json"))


pg_down_1 = []
termination_statuses = []
termination_statuses_1_0 = []
sum_redispatch_costs = 0.0
sum_redispatch_costs_with_infeasibilities = 0.0
count_infeasibilities = 0
for day in 1:n_days
    for hour in 1:n_hours_per_day
        push!(pg_down_1,result_redispatch_one_max_action_average_check["$day"]["$hour"]["solution"]["gen"]["1"]["pg_down"])
        push!(termination_statuses,result_redispatch_one_max_action_average_check["$day"]["$hour"]["termination_status"])
        sum_redispatch_costs_with_infeasibilities += result_redispatch_one_max_action_average_check["$day"]["$hour"]["objective"]
        if result_redispatch_one_max_action_average_check["$day"]["$hour"]["termination_status"] == "LOCALLY_SOLVED"
            push!(termination_statuses_1_0,0.0)
            sum_redispatch_costs += result_redispatch_one_max_action_average_check["$day"]["$hour"]["objective"]
        else
            count_infeasibilities += 1
            push!(termination_statuses_1_0,1.0)
        end
    end
end 
plot(pg_down_1)#,ylims = (0.01,1.1))
scatter!(termination_statuses_1_0)


cost_measured_one_action = 0
cost_forecasted_one_action = 0
cost_average_one_action = 0

for day in 1:n_days
    for hour in 1:n_hours_per_day
        cost_measured_one_action += (feasibility_check_one_maximum_actions_measured["$day"]["$hour"]["objective"] + result_redispatch_one_max_action_measured_check["$day"]["$hour"]["objective"])
        cost_forecasted_one_action += (feasibility_check_one_maximum_actions_forecasted["$day"]["$hour"]["objective"] + result_redispatch_one_max_action_forecasted_check["$day"]["$hour"]["objective"])
        cost_average_one_action += (feasibility_check_one_maximum_actions_average["$day"]["$hour"]["objective"] + result_redispatch_one_max_action_average_check["$day"]["$hour"]["objective"])
    end
end


cost_measured_hourly_bs = 0
cost_forecasted_hourly_bs = 0
cost_average_hourly_bs = 0

for day in 1:n_days
    for hour in 1:n_hours_per_day
        cost_measured_hourly_bs   += (feasibility_check_bs_hourly_measured["$day"]["$hour"]["objective"]   + result_redispatch_bs_hourly_measured_check["$day"]["$hour"]["objective"])
        cost_forecasted_hourly_bs += (feasibility_check_bs_hourly_forecasted["$day"]["$hour"]["objective"] + result_redispatch_bs_hourly_forecasted_check["$day"]["$hour"]["objective"])
        cost_average_hourly_bs    += (feasibility_check_bs_hourly_average["$day"]["$hour"]["objective"]    + result_redispatch_bs_hourly_average_check["$day"]["$hour"]["objective"])
    end
end


opf_measured = JSON.parsefile(joinpath(results_folder,case,"Hourly_opf_measured_$(first_hour)_$(last_hour).json"))
cost_opf_measured = sum(opf_measured["$hour"]["objective"] for hour in 1:n_hours)

################### Two switching actisn ########################
save_redispatch_days(test_case_bs,bs_two_maximum_actions_measured,feasibility_check_two_maximum_actions_measured,measured_wind,scenario_wind,one_scenario,n_days,"two_maximum_actions_measured",bs_two_maximum_actions_measured,feasibility_check_two_maximum_actions_measured)
save_redispatch_days(test_case_bs,bs_two_maximum_actions_forecasted,feasibility_check_one_maximum_actions_forecasted,measured_wind,scenario_wind,one_scenario,n_days,"two_maximum_actions_forecasted",bs_two_maximum_actions_measured,feasibility_check_two_maximum_actions_measured)
#save_redispatch_days(test_case_bs,bs_two_maximum_actions_average,feasibility_check_one_maximum_actions_average,measured_wind,scenario_wind,one_scenario,n_days,"one_maximum_actions_average",bs_one_maximum_actions_measured,feasibility_check_one_maximum_actions_measured)


result_redispatch_two_max_action_measured_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_two_maximum_actions_measured_$(first_hour)_$(last_hour)_all_days.json"))
result_redispatch_two_max_action_forecasted_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_two_maximum_actions_forecasted_$(first_hour)_$(last_hour)_all_days.json"))
#result_redispatch_one_max_action_average_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_one_maximum_actions_average_$(first_hour)_$(last_hour)_all_days.json"))


###########################################################
######### Scenarios
n_scenarios = 6
################### Hourly optimization ########################
bs_hourly_scenarios = JSON.parsefile(joinpath(results_folder,case,"Hourly_bs_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_all_days.json"))
feasibility_check_bs_hourly_scenarios  = JSON.parsefile(joinpath(results_folder,case,"fc_Hourly_bs_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_all_days.json")) 
save_redispatch_days(test_case_bs,bs_hourly_scenarios  ,feasibility_check_bs_hourly_scenarios,measured_wind  ,scenario_wind,n_scenarios,n_days,"Hourly_bs_stochastic_Laplace_$(n_scenarios)_scenarios"  ,bs_hourly_measured,feasibility_check_bs_hourly_measured)

compute_computational_time(bs_hourly_scenarios,n_days,n_hours,n_hours_per_day,n_scenarios)

################### One topology ########################
bs_one_topology_scenarios = JSON.parsefile(joinpath(results_folder,case,"24_hours_BS_one_topology_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_all_days.json"))

bs_one_topology_scenarios_fixed = Dict{String,Any}()
for day in 1:n_days
    bs_one_topology_scenarios_fixed["$day"] = Dict{String,Any}()
    for hour in 1:n_hours_per_day
        bs_one_topology_scenarios_fixed["$day"]["$hour"] = Dict{String,Any}()
        bs_one_topology_scenarios_fixed["$day"]["$hour"]["solution"] = Dict{String,Any}()
        bs_one_topology_scenarios_fixed["$day"]["$hour"]["solution"]["nw"] = Dict{String,Any}()
        bs_one_topology_scenarios_fixed["$day"]["$hour"]["solution"]["multiinfrastructure"] = false
        bs_one_topology_scenarios_fixed["$day"]["$hour"]["solution"]["multinetwork"] = true
        bs_one_topology_scenarios_fixed["$day"]["$hour"]["solution"]["per_unit"] = true
        for s in 1:n_scenarios
            bs_one_topology_scenarios_fixed["$day"]["$hour"]["solution"]["nw"]["$s"] = Dict{String,Any}()
            bs_one_topology_scenarios_fixed["$day"]["$hour"]["solution"]["nw"]["$s"] = bs_one_topology_scenarios["$day"]["$hour"]["$s"]
        end
    end
end

feasibility_check_one_topology_scenarios  = JSON.parsefile(joinpath(results_folder,case,"fc_24_hours_BS_one_topology_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_all_days.json")) 
save_redispatch_days(test_case_bs,bs_one_topology_scenarios_fixed,feasibility_check_one_topology_scenarios,measured_wind,scenario_wind,n_scenarios,n_days,"24_hours_BS_one_topology_stochastic",bs_one_topology_measured,feasibility_check_one_topology_measured)



################### One switching action ########################
bs_one_sw_scenarios = JSON.parsefile(joinpath(results_folder,case,"24_hours_BS_one_sw_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_all_days.json"))
bs_one_sw_scenarios_fixed = Dict{String,Any}()
for day in 1:n_days
    bs_one_sw_scenarios_fixed["$day"] = Dict{String,Any}()
    for hour in 1:n_hours_per_day
        bs_one_sw_scenarios_fixed["$day"]["$hour"] = Dict{String,Any}()
        bs_one_sw_scenarios_fixed["$day"]["$hour"]["solution"] = Dict{String,Any}()
        bs_one_sw_scenarios_fixed["$day"]["$hour"]["solution"]["nw"] = Dict{String,Any}()
        bs_one_sw_scenarios_fixed["$day"]["$hour"]["solution"]["multiinfrastructure"] = false
        bs_one_sw_scenarios_fixed["$day"]["$hour"]["solution"]["multinetwork"] = true
        bs_one_sw_scenarios_fixed["$day"]["$hour"]["solution"]["per_unit"] = true
        for s in 1:n_scenarios
            bs_one_sw_scenarios_fixed["$day"]["$hour"]["solution"]["nw"]["$s"] = Dict{String,Any}()
            bs_one_sw_scenarios_fixed["$day"]["$hour"]["solution"]["nw"]["$s"] = bs_one_sw_scenarios["$day"]["$hour"]["$s"]
        end
    end
end

feasibility_check_one_sw_scenarios  = JSON.parsefile(joinpath(results_folder,case,"fc_24_hours_BS_one_sw_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_all_days.json")) 
save_redispatch_days(test_case_bs,bs_one_sw_scenarios_fixed,feasibility_check_one_sw_scenarios,measured_wind,scenario_wind,n_scenarios,n_days,"fc_24_hours_BS_one_sw_stochastic",bs_one_maximum_actions_measured,feasibility_check_one_maximum_actions_measured)

compute_computational_time(bs_one_sw_scenarios_fixed,n_days,n_hours,n_hours_per_day,n_scenarios)


################### Two switching actions ########################
bs_two_sw_scenarios = JSON.parsefile(joinpath(results_folder,case,"24_hours_BS_two_sw_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_all_days.json"))
bs_two_sw_scenarios_fixed = Dict{String,Any}()
for day in 1:n_days
    bs_two_sw_scenarios_fixed["$day"] = Dict{String,Any}()
    for hour in 1:n_hours_per_day
        bs_two_sw_scenarios_fixed["$day"]["$hour"] = Dict{String,Any}()
        bs_two_sw_scenarios_fixed["$day"]["$hour"]["solution"] = Dict{String,Any}()
        bs_two_sw_scenarios_fixed["$day"]["$hour"]["solution"]["nw"] = Dict{String,Any}()
        bs_two_sw_scenarios_fixed["$day"]["$hour"]["solution"]["multiinfrastructure"] = false
        bs_two_sw_scenarios_fixed["$day"]["$hour"]["solution"]["multinetwork"] = true
        bs_two_sw_scenarios_fixed["$day"]["$hour"]["solution"]["per_unit"] = true
        for s in 1:n_scenarios
            bs_two_sw_scenarios_fixed["$day"]["$hour"]["solution"]["nw"]["$s"] = Dict{String,Any}()
            bs_two_sw_scenarios_fixed["$day"]["$hour"]["solution"]["nw"]["$s"] = bs_two_sw_scenarios["$day"]["$hour"]["$s"]
        end
    end
end

feasibility_check_two_sw_scenarios  = JSON.parsefile(joinpath(results_folder,case,"fc_24_hours_BS_two_sw_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_all_days.json")) 
save_redispatch_days(test_case_bs,bs_two_sw_scenarios_fixed,feasibility_check_two_sw_scenarios,measured_wind,scenario_wind,n_scenarios,n_days,"fc_24_hours_BS_two_sw_stochastic",bs_two_maximum_actions_measured,feasibility_check_two_maximum_actions_measured)

compute_computational_time(bs_hourly_scenarios,n_days,n_hours,n_hours_per_day,n_scenarios)


#####################################################
result_redispatch_hourly_bs_scnearios_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_Hourly_bs_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_all_days.json"))


pg_down_1 = []
termination_statuses = []
termination_statuses_1_0 = []
sum_redispatch_costs = 0.0
sum_redispatch_costs_with_infeasibilities = 0.0
count_infeasibilities = 0
for day in 1:n_days
    for hour in 1:n_hours_per_day
        sum_down_1 = 0
        for s in 1:n_scenarios
            timestep = (day - 1)*n_hours_per_day*n_scenarios + (hour - 1)*n_scenarios + s
            sum_down_1 += result_redispatch_hourly_bs_scnearios_check["$day"]["$hour"]["$s"]["solution"]["gen"]["1"]["pg_down"]*scenario_wind["$timestep"]["probability"]
            push!(termination_statuses,result_redispatch_hourly_bs_scnearios_check["$day"]["$hour"]["$s"]["termination_status"])
            sum_redispatch_costs_with_infeasibilities += result_redispatch_hourly_bs_scnearios_check["$day"]["$hour"]["$s"]["objective"]*scenario_wind["$timestep"]["probability"]
            if result_redispatch_hourly_bs_scnearios_check["$day"]["$hour"]["$s"]["termination_status"] == "LOCALLY_SOLVED"
                push!(termination_statuses_1_0,0.0)
                sum_redispatch_costs += result_redispatch_hourly_bs_scnearios_check["$day"]["$hour"]["$s"]["objective"]*scenario_wind["$timestep"]["probability"]
            else
                count_infeasibilities += 1
                push!(termination_statuses_1_0,1.0)
            end    
        end
        push!(pg_down_1,sum_down_1)
    end
end 
plot(pg_down_1)#,ylims = (0.01,1.1))
scatter!(termination_statuses_1_0)

####################
n_scenarios = 8
scenario_wind = JSON.parsefile(joinpath(input_folder,"case30","Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour).json"))


result_redispatch_one_topology_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_24_hours_BS_one_topology_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_all_days.json"))


pg_down_1 = []
termination_statuses = []
termination_statuses_1_0 = []
sum_redispatch_costs = 0.0
sum_redispatch_costs_with_infeasibilities = 0.0
count_infeasibilities = 0
for day in 1:n_days
    for hour in 1:n_hours_per_day
        sum_down_1 = 0
        for s in 1:n_scenarios
            timestep = (day - 1)*n_hours_per_day*n_scenarios + (hour - 1)*n_scenarios + s
            sum_down_1 += result_redispatch_one_topology_scenarios_check["$day"]["$hour"]["$s"]["solution"]["gen"]["1"]["pg_down"]*scenario_wind["$timestep"]["probability"]
            push!(termination_statuses,result_redispatch_one_topology_scenarios_check["$day"]["$hour"]["$s"]["termination_status"])
            sum_redispatch_costs_with_infeasibilities += result_redispatch_one_topology_scenarios_check["$day"]["$hour"]["$s"]["objective"]*scenario_wind["$timestep"]["probability"]
            if result_redispatch_one_topology_scenarios_check["$day"]["$hour"]["$s"]["termination_status"] == "LOCALLY_SOLVED"
                push!(termination_statuses_1_0,0.0)
                sum_redispatch_costs += result_redispatch_one_topology_scenarios_check["$day"]["$hour"]["$s"]["objective"]*scenario_wind["$timestep"]["probability"]
            else
                count_infeasibilities += 1
                push!(termination_statuses_1_0,1.0)
            end    
        end
        push!(pg_down_1,sum_down_1)
    end
end 
plot(pg_down_1)#,ylims = (0.01,1.1))
scatter!(termination_statuses_1_0)


####################
result_redispatch_one_sw_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_fc_24_hours_BS_one_sw_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_all_days.json"))


pg_down_1 = []
termination_statuses = []
termination_statuses_1_0 = []
sum_redispatch_costs = 0.0
sum_redispatch_costs_with_infeasibilities = 0.0
count_infeasibilities = 0
for day in 1:n_days
    for hour in 1:n_hours_per_day
        sum_down_1 = 0
        for s in 1:n_scenarios
            timestep = (day - 1)*n_hours_per_day*n_scenarios + (hour - 1)*n_scenarios + s
            sum_down_1 += result_redispatch_one_sw_scenarios_check["$day"]["$hour"]["$s"]["solution"]["gen"]["1"]["pg_down"]*scenario_wind["$timestep"]["probability"]
            push!(termination_statuses,result_redispatch_one_sw_scenarios_check["$day"]["$hour"]["$s"]["termination_status"])
            sum_redispatch_costs_with_infeasibilities += result_redispatch_one_sw_scenarios_check["$day"]["$hour"]["$s"]["objective"]*scenario_wind["$timestep"]["probability"]
            if result_redispatch_one_sw_scenarios_check["$day"]["$hour"]["$s"]["termination_status"] == "LOCALLY_SOLVED"
                push!(termination_statuses_1_0,0.0)
                sum_redispatch_costs += result_redispatch_one_sw_scenarios_check["$day"]["$hour"]["$s"]["objective"]*scenario_wind["$timestep"]["probability"]
            else
                count_infeasibilities += 1
                push!(termination_statuses_1_0,1.0)
            end    
        end
        push!(pg_down_1,sum_down_1)
    end
end 
plot(pg_down_1)#,ylims = (0.01,1.1))
scatter!(termination_statuses_1_0)

##########################################################################################
### Uploading results
## Feasibility checks
scenario_wind_6 = JSON.parsefile(joinpath(input_folder,"case30","Laplace_6_scenarios_$(first_hour)_$(last_hour).json"))
scenario_wind_8 = JSON.parsefile(joinpath(input_folder,"case30","Laplace_8_scenarios_$(first_hour)_$(last_hour).json"))

opf_6_scenarios = JSON.parsefile(joinpath(results_folder,case,"Hourly_opf_stochastic_Laplace_6_scenarios_$(first_hour)_$(last_hour).json"))
opf_8_scenarios = JSON.parsefile(joinpath(results_folder,case,"Hourly_opf_stochastic_Laplace_8_scenarios_$(first_hour)_$(last_hour).json"))

result_fc_hourly_bs_6_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"fc_Hourly_bs_stochastic_Laplace_6_scenarios_$(first_hour)_$(last_hour)_all_days.json"))
result_fc_hourly_bs_8_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"fc_Hourly_bs_stochastic_Laplace_8_scenarios_$(first_hour)_$(last_hour)_all_days.json"))

result_fc_one_topology_6_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"fc_24_hours_BS_one_topology_stochastic_Laplace_6_scenarios_$(first_hour)_$(last_hour)_all_days.json"))
result_fc_one_topology_8_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"fc_24_hours_BS_one_topology_stochastic_Laplace_8_scenarios_$(first_hour)_$(last_hour)_all_days.json"))

result_fc_one_sw_6_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"fc_24_hours_BS_one_sw_stochastic_Laplace_6_scenarios_$(first_hour)_$(last_hour)_all_days.json"))
result_fc_one_sw_8_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"fc_24_hours_BS_one_sw_stochastic_Laplace_8_scenarios_$(first_hour)_$(last_hour)_all_days.json"))

result_fc_two_sw_6_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"fc_24_hours_BS_two_sw_stochastic_Laplace_6_scenarios_$(first_hour)_$(last_hour)_all_days.json"))
result_fc_two_sw_8_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"fc_24_hours_BS_two_sw_stochastic_Laplace_8_scenarios_$(first_hour)_$(last_hour)_all_days.json"))


## Redispatch
result_redispatch_hourly_bs_6_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_Hourly_bs_stochastic_Laplace_6_scenarios_$(first_hour)_$(last_hour)_all_days.json"))
result_redispatch_hourly_bs_8_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_Hourly_bs_stochastic_Laplace_8_scenarios_$(first_hour)_$(last_hour)_all_days.json"))

result_redispatch_one_topology_6_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_24_hours_BS_one_topology_stochastic_Laplace_6_scenarios_$(first_hour)_$(last_hour)_all_days.json"))
result_redispatch_one_topology_8_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_24_hours_BS_one_topology_stochastic_Laplace_8_scenarios_$(first_hour)_$(last_hour)_all_days.json"))

result_redispatch_one_sw_6_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_24_hours_BS_one_sw_stochastic_Laplace_6_scenarios_$(first_hour)_$(last_hour)_all_days.json"))
result_redispatch_one_sw_8_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_24_hours_BS_one_sw_stochastic_Laplace_8_scenarios_$(first_hour)_$(last_hour)_all_days.json"))

result_redispatch_two_sw_6_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_24_hours_BS_two_sw_stochastic_Laplace_6_scenarios_$(first_hour)_$(last_hour)_all_days.json"))
result_redispatch_two_sw_8_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_24_hours_BS_two_sw_stochastic_Laplace_8_scenarios_$(first_hour)_$(last_hour)_all_days.json"))


##### OPF
result_redispatch_opf_6 = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_OPF_Laplace_6_scenarios_$(first_hour)_$(last_hour).json"))
result_redispatch_opf_8 = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_OPF_Laplace_8_scenarios_$(first_hour)_$(last_hour).json"))


pg_1_opf_measured = []
pg_1_opf_forecasted = []
pg_1_hourly_bs_measured = []
pg_1_hourly_bs_forecasted = []
pg_1_one_topology_measured = []

pg_1_opf_6_scenarios = []
pg_1_6_scenarios_hourly_bs = []
pg_1_6_scenarios_one_topology = []
pg_1_6_scenarios_one_sw = []
pg_1_opf_8_scenarios = []
pg_1_8_scenarios_hourly_bs = []
pg_1_8_scenarios_one_topology = []
pg_1_8_scenarios_one_sw = []
for day in 1:n_days
    for hour in 1:n_hours_per_day
        this_hour = hour + (day - 1)*n_hours_per_day
        gen_hourly_6 = 0
        gen_hourly_bs_6 = 0
        gen_hourly_one_topology_6 = 0
        gen_hourly_one_sw_6 = 0
        push!(pg_1_opf_measured,hourly_opf_measured["$this_hour"]["solution"]["gen"]["1"]["pg"])
        push!(pg_1_opf_forecasted,hourly_opf_forecasted["$this_hour"]["solution"]["gen"]["1"]["pg"])

        push!(pg_1_hourly_bs_measured,bs_hourly_measured["$day"]["$hour"]["solution"]["gen"]["1"]["pg"])
        push!(pg_1_hourly_bs_forecasted,bs_hourly_forecasted["$day"]["$hour"]["solution"]["gen"]["1"]["pg"])

        push!(pg_1_one_topology_measured,bs_one_topology_measured["$day"]["solution"]["nw"]["$hour"]["gen"]["1"]["pg"])

        for scenario in 1:6
            timestep = (day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario
            gen_hourly_6 += opf_6_scenarios["$timestep"]["solution"]["gen"]["1"]["pg"]*scenario_wind_6["$timestep"]["probability"]
            gen_hourly_bs_6 += result_fc_hourly_bs_6_scenarios_check["$day"]["$hour"]["$scenario"]["solution"]["gen"]["1"]["pg"]*scenario_wind_6["$timestep"]["probability"]
            gen_hourly_one_topology_6 += result_fc_one_topology_6_scenarios_check["$day"]["$hour"]["$scenario"]["solution"]["gen"]["1"]["pg"]*scenario_wind_6["$timestep"]["probability"]
            gen_hourly_one_sw_6 += result_fc_one_sw_6_scenarios_check["$day"]["$hour"]["$scenario"]["solution"]["gen"]["1"]["pg"]*scenario_wind_6["$timestep"]["probability"]
        end
        push!(pg_1_opf_6_scenarios,gen_hourly_6)
        push!(pg_1_6_scenarios_hourly_bs,gen_hourly_bs_6)
        push!(pg_1_6_scenarios_one_topology,gen_hourly_one_topology_6)
        push!(pg_1_6_scenarios_one_sw,gen_hourly_one_sw_6)
        gen_hourly_8 = 0
        gen_hourly_bs_8 = 0
        gen_hourly_one_topology_8 = 0
        gen_hourly_one_sw_8 = 0
        for scenario_8 in 1:8
            timestep = (day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario_8
            gen_hourly_8 += opf_8_scenarios["$timestep"]["solution"]["gen"]["1"]["pg"]*scenario_wind_8["$timestep"]["probability"]
            gen_hourly_bs_8 += result_fc_hourly_bs_8_scenarios_check["$day"]["$hour"]["$scenario_8"]["solution"]["gen"]["1"]["pg"]*scenario_wind_8["$timestep"]["probability"]
            gen_hourly_one_topology_8 += result_fc_one_topology_8_scenarios_check["$day"]["$hour"]["$scenario_8"]["solution"]["gen"]["1"]["pg"]*scenario_wind_8["$timestep"]["probability"]
            gen_hourly_one_sw_8 += result_fc_one_sw_8_scenarios_check["$day"]["$hour"]["$scenario_8"]["solution"]["gen"]["1"]["pg"]*scenario_wind_8["$timestep"]["probability"]
        end
        push!(pg_1_opf_8_scenarios,gen_hourly_8)
        push!(pg_1_8_scenarios_hourly_bs,gen_hourly_bs_8)
        push!(pg_1_8_scenarios_one_topology,gen_hourly_one_topology_8)
        push!(pg_1_8_scenarios_one_sw,gen_hourly_one_sw_8)
    end
end


obj_opf_measured = [hourly_opf_measured["$hour"]["objective"] for hour in 1:n_hours]

gen_1_pmax = test_case_opf["gen"]["1"]["pmax"]

plot(pg_1_opf_measured/gen_1_pmax, label = "OPF measured",xlabel = "Hours", ylabel = "Offshore wind generaion [pu]",ylims = (0,1.0),yticks = 0:0.2:1,grid = :none,legendfontsize = 7)
#plot!(pg_1_opf_forecasted/gen_1_pmax, label = "OPF forecasted")
plot!(pg_1_opf_6_scenarios/gen_1_pmax, label = "OPF 6 scenarios")

#plot!(pg_1_hourly_bs_measured/gen_1_pmax, label = "Hourly BS measured")
##plot!(pg_1_hourly_bs_forecasted/gen_1_pmax, label = "Hourly BS forecasted")
#plot!(pg_1_6_scenarios_hourly_bs/gen_1_pmax, label = "Hourly BS 6 scenarios")

plot!(pg_1_one_topology_measured/gen_1_pmax, label = "One topology measured")
##plot!(pg_1_hourly_bs_forecasted/gen_1_pmax, label = "Hourly BS forecasted")
plot!(pg_1_6_scenarios_one_topology/gen_1_pmax, label = "One topology 6 scenarios")


figures_folder = joinpath(dirname(results_folder),"Figures","case_30")

savefig(joinpath(figures_folder,"OFW_generation_OPF_one_topology_6_scenarios_$(first_hour)_$(last_hour).png"))
savefig(joinpath(figures_folder,"OFW_generation_OPF_one_topology_6_scenarios_$(first_hour)_$(last_hour).svg"))
savefig(joinpath(figures_folder,"OFW_generation_OPF_one_topology_6_scenarios_$(first_hour)_$(last_hour).pdf"))

plot(pg_1_opf_measured/gen_1_pmax, label = "OPF measured",xlabel = "Hours", ylabel = "Offshore wind generaion [pu]",ylims = (0,1.0),yticks = 0:0.2:1)
plot!(pg_1_opf_6_scenarios/gen_1_pmax, label = "OPF 6 scenarios")
plot!(pg_1_hourly_bs_measured/gen_1_pmax, label = "Hourly BS measured")

#plot!(pg_1_opf_8_scenarios/gen_1_pmax, label = "OPF 8 scenarios")

plot!(pg_1_6_scenarios_hourly_bs/gen_1_pmax, label = "Hourly BS 6 scenarios")
#plot!(pg_1_scenarios_one_topology_6, label = "One topology 6 scenarios")
#plot!(pg_1_scenarios_one_sw_6, label = "One switching action 6 scenarios")
#plot!(pg_1_8_scenarios_hourly_bs/gen_1_pmax, label = "Hourly BS 8 scenarios")
plot!(pg_1_hourly_bs_measured/gen_1_pmax, label = "Hourly BS measured")


###################

redispatch_opf_8 = Dict{String,Any}()
redispatch_scenarios_opf(redispatch_opf_8,opf_8_scenarios,scenario_wind_8,8,n_hours,hourly_opf_measured)


json_redispatch_opf_results = JSON.json(redispatch_opf_8)
 open(joinpath(results_folder,case,"redispatch_results_OPF_Laplace_8_scenarios_$(first_hour)_$(last_hour).json"),"w") do f 
     write(f, json_redispatch_opf_results) 
end 

obj_opf_8 = []
for day in 1:n_days
    for hour in 1:n_hours_per_day
        for scenario in 1:6
            timestep = (day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario
            push!(obj_opf_8,redispatch_opf_8["$(timestep)"]["objective"]) 
        end
    end
end
plot(obj_opf_8)


redispatch_opf_forecasted = Dict{String,Any}()
redispatch_scenarios_opf(redispatch_opf_forecasted,hourly_opf_forecasted,scenario_wind_8,one_scenario,n_hours,hourly_opf_measured)

redispatch_opf_average = Dict{String,Any}()
redispatch_scenarios_opf(redispatch_opf_average,hourly_opf_average,scenario_wind_8,one_scenario,n_hours,hourly_opf_measured)

json_redispatch_opf_results = JSON.json(redispatch_opf_forecasted)
 open(joinpath(results_folder,case,"redispatch_results_OPF_forecasted_$(first_hour)_$(last_hour).json"),"w") do f 
     write(f, json_redispatch_opf_results) 
end 

json_redispatch_opf_results = JSON.json(redispatch_opf_average)
 open(joinpath(results_folder,case,"redispatch_results_OPF_average_$(first_hour)_$(last_hour).json"),"w") do f 
     write(f, json_redispatch_opf_results) 
end 

#redispatch_opf_average = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_OPF_forecasted_$(first_hour)_$(last_hour).json"))
redispatch_opf_forecasted = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_OPF_forecasted_$(first_hour)_$(last_hour).json"))


#########################################################################################
### Computing the full sum
total_costs_opf_measured = sum(hourly_opf_measured["$hour"]["objective"] for hour in 1:n_hours)
total_costs_hourly_bs_measured = sum(feasibility_check_bs_hourly_measured["$day"]["$hour"]["objective"] for day in 1:n_days, hour in 1:n_hours_per_day)
total_costs_one_topology_measured = sum((feasibility_check_one_topology_measured["$day"]["$hour"]["objective"]) for day in 1:n_days, hour in 1:n_hours_per_day)
total_costs_one_sw_measured = sum((feasibility_check_one_maximum_actions_measured["$day"]["$hour"]["objective"]) for day in 1:n_days, hour in 1:n_hours_per_day)
total_costs_two_sw_measured = sum((feasibility_check_two_maximum_actions_measured["$day"]["$hour"]["objective"]) for day in 1:n_days, hour in 1:n_hours_per_day)


total_costs_opf_forecasted = sum(hourly_opf_forecasted["$hour"]["objective"] for hour in 1:n_hours)             + sum(redispatch_opf_forecasted["$hour"]["objective"] for hour in 1:n_hours)
total_costs_hourly_bs_forecasted = sum((feasibility_check_bs_hourly_forecasted["$day"]["$hour"]["objective"]        + result_redispatch_bs_hourly_forecasted_check["$day"]["$hour"]["objective"]) for day in 1:n_days, hour in 1:n_hours_per_day)
total_costs_one_topology_forecasted = sum((feasibility_check_one_topology_forecasted["$day"]["$hour"]["objective"]  + result_redispatch_one_topology_forecasted_check["$day"]["$hour"]["objective"]) for day in 1:n_days, hour in 1:n_hours_per_day)
total_costs_one_sw_forecasted = sum((feasibility_check_one_maximum_actions_forecasted["$day"]["$hour"]["objective"] + result_redispatch_one_max_action_forecasted_check["$day"]["$hour"]["objective"]) for day in 1:n_days, hour in 1:n_hours_per_day)
total_costs_two_sw_forecasted = sum((feasibility_check_two_maximum_actions_forecasted["$day"]["$hour"]["objective"] + result_redispatch_two_max_action_forecasted_check["$day"]["$hour"]["objective"]) for day in 1:n_days, hour in 1:n_hours_per_day)


#total_costs_opf_average = sum(hourly_opf_average["$hour"]["objective"] for hour in 1:n_hours)  + sum(redispatch_opf_average["$hour"]["objective"] for hour in 1:n_hours)
#total_costs_hourly_bs_average = sum((feasibility_check_bs_hourly_average["$day"]["$hour"]["objective"] + result_redispatch_bs_hourly_average_check["$day"]["$hour"]["objective"]) for day in 1:n_days, hour in 1:n_hours_per_day)
#total_costs_one_topology_average = sum((feasibility_check_one_topology_average["$day"]["$hour"]["objective"] + result_redispatch_one_topology_average_check["$day"]["$hour"]["objective"]) for day in 1:n_days, hour in 1:n_hours_per_day)
#total_costs_one_sw_average = sum((feasibility_check_one_maximum_actions_average["$day"]["$hour"]["objective"] + result_redispatch_one_max_action_average_check["$day"]["$hour"]["objective"]) for day in 1:n_days, hour in 1:n_hours_per_day)


total_costs_opf_6_scenarios = sum(((opf_6_scenarios["$((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)"]["objective"]    + result_redispatch_opf_6["$((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)"]["objective"])*scenario_wind_6["$((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)"]["probability"]) for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:6) 
total_costs_hourly_bs_6_scenarios = sum((result_fc_hourly_bs_6_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]       + result_redispatch_hourly_bs_6_scenarios_check["$day"]["$hour"]["$scenario"]["objective"])*scenario_wind_6["$((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:6)
total_costs_one_topology_6_scenarios = sum((result_fc_one_topology_6_scenarios_check["$day"]["$hour"]["$scenario"]["objective"] + result_redispatch_one_topology_6_scenarios_check["$day"]["$hour"]["$scenario"]["objective"])*scenario_wind_6["$((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:6)
total_costs_one_sw_6_scenarios       = sum((result_fc_one_sw_6_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]       + result_redispatch_one_sw_6_scenarios_check["$day"]["$hour"]["$scenario"]["objective"])*scenario_wind_6["$((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:6)
total_costs_two_sw_6_scenarios       = sum((result_fc_two_sw_6_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]       + result_redispatch_two_sw_6_scenarios_check["$day"]["$hour"]["$scenario"]["objective"])*scenario_wind_6["$((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:6)


total_costs_opf_8_scenarios = sum(((opf_8_scenarios["$((day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario)"]["objective"]    + result_redispatch_opf_8["$((day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario)"]["objective"])*scenario_wind_8["$((day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario)"]["probability"]) for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:8)
total_costs_hourly_bs_8_scenarios = sum((result_fc_hourly_bs_8_scenarios_check["$day"]["$hour"]["$scenario"]["objective"] + result_redispatch_hourly_bs_8_scenarios_check["$day"]["$hour"]["$scenario"]["objective"])*scenario_wind_8["$((day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:8)
total_costs_one_topology_8_scenarios = sum((result_fc_one_topology_8_scenarios_check["$day"]["$hour"]["$scenario"]["objective"] + result_redispatch_one_topology_8_scenarios_check["$day"]["$hour"]["$scenario"]["objective"])*scenario_wind_8["$((day - 1)*n_hours_per_day*8 + (hour - 1)*8+ scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:8)
total_costs_one_sw_8_scenarios       = sum((result_fc_one_sw_8_scenarios_check["$day"]["$hour"]["$scenario"]["objective"] + result_redispatch_one_sw_8_scenarios_check["$day"]["$hour"]["$scenario"]["objective"])*scenario_wind_8["$((day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:8)
total_costs_two_sw_8_scenarios       = sum((result_fc_two_sw_8_scenarios_check["$day"]["$hour"]["$scenario"]["objective"] + result_redispatch_two_sw_8_scenarios_check["$day"]["$hour"]["$scenario"]["objective"])*scenario_wind_8["$((day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:8)

################


generation_costs_opf_measured = sum(hourly_opf_measured["$hour"]["objective"] for hour in 1:n_hours)
generation_costs_hourly_bs_measured = sum(feasibility_check_bs_hourly_measured["$day"]["$hour"]["objective"] for day in 1:n_days, hour in 1:n_hours_per_day)
generation_costs_one_topology_measured = sum((feasibility_check_one_topology_measured["$day"]["$hour"]["objective"]) for day in 1:n_days, hour in 1:n_hours_per_day)
generation_costs_one_sw_measured = sum((feasibility_check_one_maximum_actions_measured["$day"]["$hour"]["objective"]) for day in 1:n_days, hour in 1:n_hours_per_day)
generation_costs_two_sw_measured = sum((feasibility_check_two_maximum_actions_measured["$day"]["$hour"]["objective"]) for day in 1:n_days, hour in 1:n_hours_per_day)


generation_costs_opf_forecasted = sum(hourly_opf_forecasted["$hour"]["objective"] for hour in 1:n_hours) 
generation_costs_hourly_bs_forecasted = sum(feasibility_check_bs_hourly_forecasted["$day"]["$hour"]["objective"]        for day in 1:n_days, hour in 1:n_hours_per_day)
generation_costs_one_topology_forecasted = sum(feasibility_check_one_topology_forecasted["$day"]["$hour"]["objective"]  for day in 1:n_days, hour in 1:n_hours_per_day)
generation_costs_one_sw_forecasted = sum(feasibility_check_one_maximum_actions_forecasted["$day"]["$hour"]["objective"]  for day in 1:n_days, hour in 1:n_hours_per_day)
generation_costs_two_sw_forecasted = sum(feasibility_check_two_maximum_actions_forecasted["$day"]["$hour"]["objective"]  for day in 1:n_days, hour in 1:n_hours_per_day)


generation_costs_opf_6_scenarios = sum(((opf_6_scenarios["$((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)"]["objective"]   )*scenario_wind_6["$((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)"]["probability"]) for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:6) 
generation_costs_hourly_bs_6_scenarios = sum((result_fc_hourly_bs_6_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]      )*scenario_wind_6["$((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:6)
generation_costs_one_topology_6_scenarios = sum((result_fc_one_topology_6_scenarios_check["$day"]["$hour"]["$scenario"]["objective"])*scenario_wind_6["$((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:6)
generation_costs_one_sw_6_scenarios       = sum((result_fc_one_sw_6_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]      )*scenario_wind_6["$((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:6)
generation_costs_two_sw_6_scenarios       = sum((result_fc_two_sw_6_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]      )*scenario_wind_6["$((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:6)


generation_costs_opf_8_scenarios = sum(((opf_8_scenarios["$((day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario)"]["objective"]    )*scenario_wind_8["$((day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario)"]["probability"]) for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:8)
generation_costs_hourly_bs_8_scenarios = sum((result_fc_hourly_bs_8_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]       )*scenario_wind_8["$((day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:8)
generation_costs_one_topology_8_scenarios = sum((result_fc_one_topology_8_scenarios_check["$day"]["$hour"]["$scenario"]["objective"] )*scenario_wind_8["$((day - 1)*n_hours_per_day*8 + (hour - 1)*8+ scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:8)
generation_costs_one_sw_8_scenarios       = sum((result_fc_one_sw_8_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]       )*scenario_wind_8["$((day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:8)
generation_costs_two_sw_8_scenarios       = sum((result_fc_two_sw_8_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]       )*scenario_wind_8["$((day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:8)



redispatch_costs_opf_measured = 0
redispatch_costs_hourly_bs_measured = 0
redispatch_costs_one_topology_measured = 0
redispatch_costs_one_sw_measured = 0
redispatch_costs_two_sw_measured = 0


redispatch_costs_opf_forecasted          = sum(redispatch_opf_forecasted["$hour"]["objective"] for hour in 1:n_hours)
redispatch_costs_hourly_bs_forecasted    = sum(result_redispatch_bs_hourly_forecasted_check["$day"]["$hour"]["objective"] for day in 1:n_days, hour in 1:n_hours_per_day)
redispatch_costs_one_topology_forecasted = sum(result_redispatch_one_topology_forecasted_check["$day"]["$hour"]["objective"] for day in 1:n_days, hour in 1:n_hours_per_day)
redispatch_costs_one_sw_forecasted       = sum(result_redispatch_one_max_action_forecasted_check["$day"]["$hour"]["objective"] for day in 1:n_days, hour in 1:n_hours_per_day)
redispatch_costs_two_sw_forecasted       = sum(result_redispatch_two_max_action_forecasted_check["$day"]["$hour"]["objective"] for day in 1:n_days, hour in 1:n_hours_per_day)



redispatch_costs_opf_6_scenarios          = sum(result_redispatch_opf_6["$((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)"]["objective"]*scenario_wind_6["$((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:6) 
redispatch_costs_hourly_bs_6_scenarios    = sum(result_redispatch_hourly_bs_6_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]*scenario_wind_6["$((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:6)
redispatch_costs_one_topology_6_scenarios = sum(result_redispatch_one_topology_6_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]*scenario_wind_6["$((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:6)
redispatch_costs_one_sw_6_scenarios       = sum(result_redispatch_one_sw_6_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]*scenario_wind_6["$((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:6)
redispatch_costs_two_sw_6_scenarios       = sum(result_redispatch_two_sw_6_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]*scenario_wind_6["$((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:6)


redispatch_costs_opf_8_scenarios =          sum(result_redispatch_opf_8["$((day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario)"]["objective"]*scenario_wind_8["$((day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:8)
redispatch_costs_hourly_bs_8_scenarios =    sum(result_redispatch_hourly_bs_8_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]*scenario_wind_8["$((day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:8)
redispatch_costs_one_topology_8_scenarios = sum(result_redispatch_one_topology_8_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]*scenario_wind_8["$((day - 1)*n_hours_per_day*8 + (hour - 1)*8+ scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:8)
redispatch_costs_one_sw_8_scenarios       = sum(result_redispatch_one_sw_8_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]*scenario_wind_8["$((day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:8)
redispatch_costs_two_sw_8_scenarios       = sum(result_redispatch_two_sw_8_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]*scenario_wind_8["$((day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:8)

################

generation_costs_opf_measured = sum(hourly_opf_measured["$hour"]["objective"] for hour in 1:n_hours)
generation_costs_hourly_bs_measured = sum(feasibility_check_bs_hourly_measured["$day"]["$hour"]["objective"] for day in 1:n_days, hour in 1:n_hours_per_day)
generation_costs_one_topology_measured = sum((feasibility_check_one_topology_measured["$day"]["$hour"]["objective"]) for day in 1:n_days, hour in 1:n_hours_per_day)
generation_costs_one_sw_measured = sum((feasibility_check_one_maximum_actions_measured["$day"]["$hour"]["objective"]) for day in 1:n_days, hour in 1:n_hours_per_day)
generation_costs_two_sw_measured = sum((feasibility_check_two_maximum_actions_measured["$day"]["$hour"]["objective"]) for day in 1:n_days, hour in 1:n_hours_per_day)

generation_costs_opf_forecasted = sum(hourly_opf_forecasted["$hour"]["objective"] for hour in 1:n_hours) 
generation_costs_hourly_bs_forecasted = sum(feasibility_check_bs_hourly_forecasted["$day"]["$hour"]["objective"]        for day in 1:n_days, hour in 1:n_hours_per_day)
generation_costs_one_topology_forecasted = sum(feasibility_check_one_topology_forecasted["$day"]["$hour"]["objective"]  for day in 1:n_days, hour in 1:n_hours_per_day)
generation_costs_one_sw_forecasted = sum(feasibility_check_one_maximum_actions_forecasted["$day"]["$hour"]["objective"]  for day in 1:n_days, hour in 1:n_hours_per_day)
generation_costs_two_sw_forecasted = sum(feasibility_check_two_maximum_actions_forecasted["$day"]["$hour"]["objective"]  for day in 1:n_days, hour in 1:n_hours_per_day)

generation_costs_opf_6_scenarios = sum(((opf_6_scenarios["$((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)"]["objective"]   )*scenario_wind_6["$((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)"]["probability"]) for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:6) 
generation_costs_hourly_bs_6_scenarios = sum((result_fc_hourly_bs_6_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]      )*scenario_wind_6["$((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:6)
generation_costs_one_topology_6_scenarios = sum((result_fc_one_topology_6_scenarios_check["$day"]["$hour"]["$scenario"]["objective"])*scenario_wind_6["$((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:6)
generation_costs_one_sw_6_scenarios       = sum((result_fc_one_sw_6_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]      )*scenario_wind_6["$((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:6)
generation_costs_two_sw_6_scenarios       = sum((result_fc_two_sw_6_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]      )*scenario_wind_6["$((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:6)

generation_costs_opf_8_scenarios = sum(((opf_8_scenarios["$((day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario)"]["objective"]    )*scenario_wind_8["$((day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario)"]["probability"]) for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:8)
generation_costs_hourly_bs_8_scenarios = sum((result_fc_hourly_bs_8_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]       )*scenario_wind_8["$((day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:8)
generation_costs_one_topology_8_scenarios = sum((result_fc_one_topology_8_scenarios_check["$day"]["$hour"]["$scenario"]["objective"] )*scenario_wind_8["$((day - 1)*n_hours_per_day*8 + (hour - 1)*8+ scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:8)
generation_costs_one_sw_8_scenarios       = sum((result_fc_one_sw_8_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]       )*scenario_wind_8["$((day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:8)
generation_costs_two_sw_8_scenarios       = sum((result_fc_two_sw_8_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]       )*scenario_wind_8["$((day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:8)



generation_costs_opf_measured_days = []
generation_costs_hourly_bs_measured_days = []
generation_costs_one_topology_measured_days = []
generation_costs_one_sw_measured_days = []
generation_costs_two_sw_measured_days = []

generation_costs_opf_forecasted_days = []
generation_costs_hourly_bs_forecasted_days = []
generation_costs_one_topology_forecasted_days = []
generation_costs_one_sw_forecasted_days = []
generation_costs_two_sw_forecasted_days = []

generation_costs_opf_6_scenarios_days = []
generation_costs_hourly_bs_6_scenarios_days = []
generation_costs_one_topology_6_scenarios_days = []
generation_costs_one_sw_6_scenarios_days = []
generation_costs_two_sw_6_scenarios_days = []

generation_costs_opf_8_scenarios_days = []
generation_costs_hourly_bs_8_scenarios_days = []
generation_costs_one_topology_8_scenarios_days = []
generation_costs_one_sw_8_scenarios_days = []
generation_costs_two_sw_8_scenarios_days = []


function compute_costs_per_day(result,days,hours,total_hours,scenarios,vector_results,scenario_wind)
    if length(result) == days
        for day in 1:days
            daily_costs = 0
            if scenarios > 1
                for hour in 1:hours
                    for scenario in 1:scenarios
                        timestep = (day - 1)*hours*scenarios + (hour - 1)*scenarios + scenario
                        daily_costs += result["$day"]["$hour"]["$scenario"]["objective"]*scenario_wind["$timestep"]["probability"]
                    end
                end
            else
                for hour in 1:hours
                    timestep = (day - 1)*hours + (hour - 1)
                    daily_costs += result["$day"]["$hour"]["objective"]
                end
            end
            push!(vector_results,daily_costs)
        end
    elseif length(result) == total_hours
        for day in 1:days
            daily_costs = 0
            for hour in 1:hours
                this_hour = (day-1)*hours + hour
                daily_costs += result["$this_hour"]["objective"]
            end
            push!(vector_results,daily_costs)
        end
    elseif length(result) == total_hours*scenarios
        println("Starting here yay")
        for day in 1:n_days
            daily_costs = 0
            for hour in 1:hours
                for scenario in 1:scenarios
                    timestep = (day-1)*hours*scenarios + (hour-1)*scenarios + scenario
                    daily_costs += result["$timestep"]["objective"]*scenario_wind["$timestep"]["probability"]
                end
            end
            push!(vector_results,daily_costs)
        end
    end

    return vector_results
end

compute_costs_per_day(hourly_opf_measured,n_days,n_hours_per_day,n_hours,one_scenario,generation_costs_opf_measured_days,scenario_wind_6)
compute_costs_per_day(feasibility_check_bs_hourly_measured,n_days,n_hours_per_day,n_hours,one_scenario,generation_costs_hourly_bs_measured_days,scenario_wind_6)
compute_costs_per_day(feasibility_check_one_topology_measured,n_days,n_hours_per_day,n_hours,one_scenario,generation_costs_one_topology_measured_days,scenario_wind_6)
compute_costs_per_day(feasibility_check_one_maximum_actions_measured,n_days,n_hours_per_day,n_hours,one_scenario,generation_costs_one_sw_measured_days,scenario_wind_6)
compute_costs_per_day(feasibility_check_two_maximum_actions_measured,n_days,n_hours_per_day,n_hours,one_scenario,generation_costs_two_sw_measured_days,scenario_wind_6)

compute_costs_per_day(hourly_opf_forecasted,n_days,n_hours_per_day,n_hours,one_scenario,generation_costs_opf_forecasted_days,scenario_wind_6)
compute_costs_per_day(feasibility_check_bs_hourly_forecasted,n_days,n_hours_per_day,n_hours,one_scenario,generation_costs_hourly_bs_forecasted_days,scenario_wind_6)
compute_costs_per_day(feasibility_check_one_topology_forecasted,n_days,n_hours_per_day,n_hours,one_scenario,generation_costs_one_topology_forecasted_days,scenario_wind_6)
compute_costs_per_day(feasibility_check_one_maximum_actions_forecasted,n_days,n_hours_per_day,n_hours,one_scenario,generation_costs_one_sw_forecasted_days,scenario_wind_6)
compute_costs_per_day(feasibility_check_two_maximum_actions_forecasted,n_days,n_hours_per_day,n_hours,one_scenario,generation_costs_two_sw_forecasted_days,scenario_wind_6)

compute_costs_per_day(opf_6_scenarios,n_days,n_hours_per_day,n_hours,6,generation_costs_opf_6_scenarios_days,scenario_wind_6)
compute_costs_per_day(result_fc_hourly_bs_6_scenarios_check,n_days,n_hours_per_day,n_hours,6,generation_costs_hourly_bs_6_scenarios_days,scenario_wind_6)
compute_costs_per_day(result_fc_one_topology_6_scenarios_check,n_days,n_hours_per_day,n_hours,6,generation_costs_one_topology_6_scenarios_days,scenario_wind_6)
compute_costs_per_day(result_fc_one_sw_6_scenarios_check,n_days,n_hours_per_day,n_hours,6,generation_costs_one_sw_forecasted_days,scenario_wind_6)
compute_costs_per_day(result_fc_two_sw_6_scenarios_check,n_days,n_hours_per_day,n_hours,6,generation_costs_two_sw_forecasted_days,scenario_wind_6)

compute_costs_per_day(opf_8_scenarios,n_days,n_hours_per_day,n_hours,8,generation_costs_opf_8_scenarios_days,scenario_wind_8)
compute_costs_per_day(result_fc_hourly_bs_8_scenarios_check,n_days,n_hours_per_day,n_hours,8,generation_costs_hourly_bs_8_scenarios_days,scenario_wind_8)
compute_costs_per_day(result_fc_one_topology_8_scenarios_check,n_days,n_hours_per_day,n_hours,8,generation_costs_one_topology_8_scenarios_days,scenario_wind_8)
compute_costs_per_day(result_fc_one_sw_8_scenarios_check,n_days,n_hours_per_day,n_hours,8,generation_costs_one_sw_8_scenarios_days,scenario_wind_8)
compute_costs_per_day(result_fc_two_sw_8_scenarios_check,n_days,n_hours_per_day,n_hours,8,generation_costs_two_sw_8_scenarios_days,scenario_wind_8)


#################


redispatch_costs_opf_measured_days = zeros(n_days)
redispatch_costs_hourly_bs_measured_days = zeros(n_days)
redispatch_costs_one_topology_measured_days = zeros(n_days)
redispatch_costs_one_sw_measured_days = zeros(n_days)
redispatch_costs_two_sw_measured_days = zeros(n_days)

redispatch_costs_opf_forecasted_days = []
redispatch_costs_hourly_bs_forecasted_days = []
redispatch_costs_one_topology_forecasted_days = []
redispatch_costs_one_sw_forecasted_days = []
redispatch_costs_two_sw_forecasted_days = []

redispatch_costs_opf_6_scenarios_days = []
redispatch_costs_hourly_bs_6_scenarios_days = []
redispatch_costs_one_topology_6_scenarios_days = []
redispatch_costs_one_sw_6_scenarios_days = []
redispatch_costs_two_sw_6_scenarios_days = []

redispatch_costs_opf_8_scenarios_days = []
redispatch_costs_hourly_bs_8_scenarios_days = []
redispatch_costs_one_topology_8_scenarios_days = []
redispatch_costs_one_sw_8_scenarios_days = []
redispatch_costs_two_sw_8_scenarios_days = []


compute_costs_per_day(redispatch_opf_forecasted,n_days,n_hours_per_day,n_hours,one_scenario,redispatch_costs_opf_forecasted_days,scenario_wind_6)
compute_costs_per_day(result_redispatch_bs_hourly_forecasted_check,n_days,n_hours_per_day,n_hours,one_scenario,redispatch_costs_hourly_bs_forecasted_days,scenario_wind_6)
compute_costs_per_day(result_redispatch_one_topology_forecasted_check,n_days,n_hours_per_day,n_hours,one_scenario,redispatch_costs_one_topology_forecasted_days,scenario_wind_6)
compute_costs_per_day(result_redispatch_one_max_action_forecasted_check,n_days,n_hours_per_day,n_hours,one_scenario,redispatch_costs_one_sw_forecasted_days,scenario_wind_6)
compute_costs_per_day(result_redispatch_two_max_action_forecasted_check,n_days,n_hours_per_day,n_hours,one_scenario,redispatch_costs_two_sw_forecasted_days,scenario_wind_6)

compute_costs_per_day(result_redispatch_opf_6,n_days,n_hours_per_day,n_hours,6,redispatch_costs_opf_6_scenarios_days,scenario_wind_6)
compute_costs_per_day(result_redispatch_hourly_bs_6_scenarios_check,n_days,n_hours_per_day,n_hours,6,redispatch_costs_hourly_bs_6_scenarios_days,scenario_wind_6)
compute_costs_per_day(result_redispatch_one_topology_6_scenarios_check,n_days,n_hours_per_day,n_hours,6,redispatch_costs_one_topology_6_scenarios_days,scenario_wind_6)
compute_costs_per_day(result_redispatch_one_sw_6_scenarios_check,n_days,n_hours_per_day,n_hours,6,redispatch_costs_one_sw_forecasted_days,scenario_wind_6)
compute_costs_per_day(result_redispatch_two_sw_6_scenarios_check,n_days,n_hours_per_day,n_hours,6,redispatch_costs_two_sw_forecasted_days,scenario_wind_6)

compute_costs_per_day(result_redispatch_opf_8,n_days,n_hours_per_day,n_hours,8,redispatch_costs_opf_8_scenarios_days,scenario_wind_8)
compute_costs_per_day(result_redispatch_hourly_bs_8_scenarios_check,n_days,n_hours_per_day,n_hours,8,redispatch_costs_hourly_bs_8_scenarios_days,scenario_wind_8)
compute_costs_per_day(result_redispatch_one_topology_8_scenarios_check,n_days,n_hours_per_day,n_hours,8,redispatch_costs_one_topology_8_scenarios_days,scenario_wind_8)
compute_costs_per_day(result_redispatch_one_sw_8_scenarios_check,n_days,n_hours_per_day,n_hours,8,redispatch_costs_one_sw_8_scenarios_days,scenario_wind_8)
compute_costs_per_day(result_redispatch_two_sw_8_scenarios_check,n_days,n_hours_per_day,n_hours,8,redispatch_costs_two_sw_8_scenarios_days,scenario_wind_8)


#######################



# Grouped bar plot
gen_opf = Float64[]
gen_one_topology  = Float64[]

for i in 1:n_days
    push!(gen_opf ,generation_costs_opf_measured_days[i] )
end
for i in 1:n_days
    push!(gen_opf ,generation_costs_opf_forecasted_days[i] )
end
for i in 1:n_days
    push!(gen_opf,generation_costs_opf_6_scenarios_days[i])
end
for i in 1:n_days
    push!(gen_opf,generation_costs_opf_8_scenarios_days[i])
end

for i in 1:n_days
    push!(gen_one_topology ,generation_costs_one_topology_measured_days[i] )
end
for i in 1:n_days
    push!(gen_one_topology ,generation_costs_one_topology_forecasted_days[i] )
end
for i in 1:n_days
    push!(gen_one_topology,generation_costs_one_topology_6_scenarios_days[i])
end
for i in 1:n_days
    push!(gen_one_topology,generation_costs_one_topology_8_scenarios_days[i])
end





redispatch_costs_opf = Float64[]
redispatch_costs_one_topology = Float64[]


for i in 1:n_days
    push!(redispatch_costs_opf ,redispatch_costs_opf_measured_days[i] )
end
for i in 1:n_days
    push!(redispatch_costs_opf ,redispatch_costs_opf_forecasted_days[i] )
end
for i in 1:n_days
    push!(redispatch_costs_opf,redispatch_costs_opf_6_scenarios_days[i])
end
for i in 1:n_days
    push!(redispatch_costs_opf,redispatch_costs_opf_8_scenarios_days[i])
end

for i in 1:n_days
    push!(redispatch_costs_one_topology ,redispatch_costs_one_topology_measured_days[i] )
end
for i in 1:n_days
    push!(redispatch_costs_one_topology ,redispatch_costs_one_topology_forecasted_days[i] )
end
for i in 1:n_days
    push!(redispatch_costs_one_topology,redispatch_costs_one_topology_6_scenarios_days[i])
end
for i in 1:n_days
    push!(redispatch_costs_one_topology,redispatch_costs_one_topology_8_scenarios_days[i])
end


#bar(1:n_days,[gen_costs redispatch_costs], bar_position = :stack, label = ["Generation" "Redispatch"])

sx_gen = repeat(["Generation costs Measured","Generation costs Forecasted", "Generation costs 6 scenarios", "Generation costs 8 scenarios"], inner = n_days)
sx_redispatch = repeat(["Redispatch costs Measured","Redispatch costs Forecasted", "Redispatch costs 6 scenarios", "Redispatch costs 8 scenarios"], inner = n_days)
using StatsPlots

p1_opf = groupedbar((gen_opf.+redispatch_costs_opf)/10^3, 
group = sx_redispatch, legend = :topright,color = [:lightblue :peachpuff :lightgreen :indianred], xlabelfontsize = 10, ylabelfontsize = 10,
ylims = (0,800))

groupedbar!((gen_opf/10^3), 
group = sx_gen, ylabel = "Costs [k\$]",xticks = 1:1:n_days, legend = :topright, color = [:blue :orange :green :red], legendfontsize = 7,
ylims = (0,800),grid = :none,xlabel = "Day")


savefig(p1_opf,joinpath(figures_folder,"Daily_opf_generation_and_redispatch_costs_$(first_hour)_$(last_hour).png"))
savefig(p1_opf,joinpath(figures_folder,"Daily_opf_generation_and_redispatch_costs_$(first_hour)_$(last_hour).svg"))
savefig(p1_opf,joinpath(figures_folder,"Daily_opf_generation_and_redispatch_costs_$(first_hour)_$(last_hour).pdf"))



p1_one_topology = groupedbar(gen_one_topology/10^3, 
group = sx, ylabel = "Generation costs [k\$]",xticks = 1:1:n_days, legend = :topright,color = [:blue :orange :green :red],
ylims = (0,600),grid = :none,xlabel = "Day")

savefig(p1_one_topology,joinpath(figures_folder,"Daily_one_topology_generation_costs_$(first_hour)_$(last_hour).png"))
savefig(p1_one_topology,joinpath(figures_folder,"Daily_one_topology_generation_costs_$(first_hour)_$(last_hour).svg"))
savefig(p1_one_topology,joinpath(figures_folder,"Daily_one_topology_generation_costs_$(first_hour)_$(last_hour).pdf"))



p1_one_topology = groupedbar((gen_one_topology.+redispatch_costs_one_topology)/10^3, 
group = sx_redispatch, legend = :topright,color = [:lightblue :peachpuff :lightgreen :indianred], xlabelfontsize = 10, ylabelfontsize = 10,
ylims = (0,800))

groupedbar!((gen_one_topology/10^3), 
group = sx_gen, ylabel = "Costs [k\$]",xticks = 1:1:n_days, legend = :topright, color = [:blue :orange :green :red], legendfontsize = 7,
ylims = (0,800),grid = :none,xlabel = "Day")


savefig(p1_one_topology,joinpath(figures_folder,"Daily_one_topology_generation_and_redispatch_costs_$(first_hour)_$(last_hour).png"))
savefig(p1_one_topology,joinpath(figures_folder,"Daily_one_topology_generation_and_redispatch_costs_$(first_hour)_$(last_hour).svg"))
savefig(p1_one_topology,joinpath(figures_folder,"Daily_one_topology_generation_and_redispatch_costs_$(first_hour)_$(last_hour).pdf"))












mean_redispatch_costs_opf_forecasted_days  = mean(redispatch_costs_opf_forecasted_days)
mean_redispatch_costs_opf_6_scenarios_days = mean(redispatch_costs_opf_6_scenarios_days)
mean_redispatch_costs_opf_8_scenarios_days = mean(redispatch_costs_opf_8_scenarios_days)

mean_redispatch_costs_one_topology_forecasted_days  = mean(redispatch_costs_one_topology_forecasted_days)
mean_redispatch_costs_one_topology_6_scenarios_days = mean(redispatch_costs_one_topology_6_scenarios_days)
mean_redispatch_costs_one_topology_8_scenarios_days = mean(redispatch_costs_one_topology_8_scenarios_days)

p2_opf = groupedbar(redispatch_costs_opf/10^3, 
group = sx, ylabel = "Redispatch costs [k\$]",xticks = 1:1:n_days, legend = :topright,color = [:blue :orange :green :red],
ylims = (0,600),grid = :none,xlabel = "Day")
hline!(p2_opf,1:n_days,[mean_redispatch_costs_opf_6_scenarios_days/10^3],label = "Average 6 scenarios", color = :blue, linewidth = 1)
hline!(p2_opf,1:n_days,[mean_redispatch_costs_opf_8_scenarios_days/10^3],label = "Average 8 scenarios", color = :orange, linewidth = 1)
hline!(p2_opf,1:n_days,[mean_redispatch_costs_opf_forecasted_days/10^3],label = "Average forecasted", color = :green, linewidth = 1)

savefig(p2_opf,joinpath(figures_folder,"Daily_opf_redispatch_costs_$(first_hour)_$(last_hour).png"))
savefig(p2_opf,joinpath(figures_folder,"Daily_opf_redispatch_costs_$(first_hour)_$(last_hour).svg"))
savefig(p2_opf,joinpath(figures_folder,"Daily_opf_redispatch_costs_$(first_hour)_$(last_hour).pdf"))


p2_one_topology = groupedbar(redispatch_costs_one_topology/10^3,color = [:blue :orange :green :red], 
group = sx, ylabel = "Redispatch costs [k\$]",xticks = 1:1:n_days, legend = :topright,
ylims = (0,600),grid = :none,xlabel = "Day")
hline!(p2_one_topology,1:n_days,[mean_redispatch_costs_one_topology_6_scenarios_days/10^3],label = "Average 6 scenarios", color = :blue, linewidth = 1)
hline!(p2_one_topology,1:n_days,[mean_redispatch_costs_one_topology_8_scenarios_days/10^3],label = "Average 8 scenarios", color = :orange, linewidth = 1)
hline!(p2_one_topology,1:n_days,[mean_redispatch_costs_one_topology_forecasted_days/10^3],label = "Average forecasted", color = :green, linewidth = 1)

savefig(p2_one_topology,joinpath(figures_folder,"Daily_one_topology_redispatch_costs_$(first_hour)_$(last_hour).png"))
savefig(p2_one_topology,joinpath(figures_folder,"Daily_one_topology_redispatch_costs_$(first_hour)_$(last_hour).svg"))
savefig(p2_one_topology,joinpath(figures_folder,"Daily_one_topology_redispatch_costs_$(first_hour)_$(last_hour).pdf"))

diff = measured_wind - forecasted_wind 
diff_100 = diff .+ 100
plot(diff,xticks = 1:24:336)

#############################
combined_result = Float64[]
for i in 1:n_days
    push!(combined_result,gen_and_redispatch_costs_forecasted[i])
    push!(combined_result,gen_and_redispatch_costs_6_scenarios[i])
    push!(combined_result,gen_and_redispatch_costs_8_scenarios[i])
end

combined_result_redispatch = Float64[]
for i in 1:n_days
    push!(combined_result_redispatch,redispatch_costs_forecasted[i])
    push!(combined_result_redispatch,redispatch_costs_6_scenarios[i])
    push!(combined_result_redispatch,redispatch_costs_8_scenarios[i])
end

combined_result_generation = Float64[]
for i in 1:n_days
    push!(combined_result_generation,generation_costs_opf_forecasted_days[i])
    push!(combined_result_generation,generation_costs_opf_6_scenarios_days[i])
    push!(combined_result_generation,generation_costs_opf_8_scenarios_days[i])
end

############################## 
sum(redispatch_costs_one_topology_6_scenarios_days)
sum(redispatch_costs_one_topology_8_scenarios_days)
sum(redispatch_costs_one_topology_forecasted_days)

sum(generation_costs_one_topology_6_scenarios_days)
sum(generation_costs_one_topology_8_scenarios_days)
sum(generation_costs_one_topology_forecasted_days)


sum(redispatch_costs_opf_6_scenarios_days)
sum(redispatch_costs_opf_8_scenarios_days)
sum(redispatch_costs_opf_forecasted_days)

sum(generation_costs_opf_6_scenarios_days)
sum(generation_costs_opf_8_scenarios_days)
sum(generation_costs_opf_forecasted_days)
