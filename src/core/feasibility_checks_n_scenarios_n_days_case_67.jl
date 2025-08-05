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
ipopt = JuMP.optimizer_with_attributes(Ipopt.Optimizer, "tol" => 1e-6, "print_level" => 0,"linear_solver" => "ma57")

sc = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true)


#first_hour = 355
#last_hour  = 378
#n_hours = 24

first_hour = 8153
last_hour  = 8488
n_scenarios = 6
n_days = 14
one_scenario = 1
n_hours_per_day = 24
n_hours = last_hour - first_hour + 1

#########################################################################################
## Processing input data
s = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true)
s_dual = Dict("output" => Dict("branch_flows" => true,"duals" => true), "conv_losses_mp" => true)

#########################################################################################
## Processing input data
input_folder = "$(dirname(dirname(@__DIR__)))"
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
# Uploading time series
scenario_wind = JSON.parsefile(joinpath(input_folder,"src","core","case30","Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour).json"))
scenario_wind_6 = JSON.parsefile(joinpath(input_folder,"src","core","case30","Laplace_6_scenarios_$(first_hour)_$(last_hour).json"))
scenario_wind_8 = JSON.parsefile(joinpath(input_folder,"src","core","case30","Laplace_8_scenarios_$(first_hour)_$(last_hour).json"))

# Uploading results
#hourly_opf = JSON.parsefile(joinpath(results_folder,"case_24","stochastic_multistep","Hourly_opf_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour).json"))
hourly_opf_measured = JSON.parsefile(joinpath(results_folder,"case_24","stochastic_multistep","Hourly_opf_ac_measured_$(first_hour)_$(last_hour).json"))
hourly_opf_forecasted = JSON.parsefile(joinpath(results_folder,"case_24","stochastic_multistep","Hourly_opf_ac_forecasted_$(first_hour)_$(last_hour).json"))

hourly_bs_measured = JSON.parsefile(joinpath(results_folder,"case_24","stochastic_multistep",  "Hourly_bs_measured_$(first_hour)_$(last_hour).json"))
#hourly_bs_average = JSON.parsefile(joinpath(results_folder,"case_24","stochastic_multistep",   "Hourly_bs_average_$(first_hour)_$(last_hour).json"))
hourly_bs_forecasted = JSON.parsefile(joinpath(results_folder,"case_24","stochastic_multistep","Hourly_bs_forecasted_$(first_hour)_$(last_hour).json"))

one_sw_measured = JSON.parsefile(joinpath(results_folder,"case_24","stochastic_multistep",  "One_maximum_actions_24_hours_measured_$(first_hour)_$(last_hour).json"))
#one_sw_average = JSON.parsefile(joinpath(results_folder,"case_24","stochastic_multistep",   "One_maximum_actions_24_hours_average_$(first_hour)_$(last_hour).json"))
one_sw_forecasted = JSON.parsefile(joinpath(results_folder,"case_24","stochastic_multistep","One_maximum_actions_24_hours_forecasted_$(first_hour)_$(last_hour).json"))

one_topology_measured = JSON.parsefile(joinpath(results_folder,"case_24","stochastic_multistep",  "24_hours_BS_one_topology_measured_$(first_hour)_$(last_hour).json"))
one_topology_forecasted = JSON.parsefile(joinpath(results_folder,"case_24","stochastic_multistep","24_hours_BS_one_topology_forecasted_$(first_hour)_$(last_hour).json"))

two_sw_measured = JSON.parsefile(joinpath(results_folder,"case_24","stochastic_multistep",  "24_hours_BS_one_topology_measured_$(first_hour)_$(last_hour).json"))
two_sw_forecasted = JSON.parsefile(joinpath(results_folder,"case_24","stochastic_multistep","Two_maximum_actions_forecasted_$(first_hour)_$(last_hour)_all_days.json"))


n_hours = last_hour - first_hour + 1

_SPMTA.add_dimensions!(test_case_bs,n_scenarios,n_hours)

forecasted_wind = JSON.parsefile(joinpath(input_folder,"src","core","case30","forecasted_two_weeks_$(first_hour)_$(last_hour).json"))
measured_wind = JSON.parsefile(joinpath(input_folder,"src","core","case30","measured_two_weeks_$(first_hour)_$(last_hour).json"))
#average_wind = [mean([forecasted_wind[i],measured_wind[i]]) for i in 1:length(forecasted_wind)]

# Adjust name of the file here
scenarios_wind_simulations = JSON.parsefile(joinpath(input_folder,"src","core","case30","Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour).json"))

#########################################################################################
# Upload results
function create_dict_results(n_days,results_folder,case,first_hour,last_hour,file_name)
    results_dict = Dict{String,Any}()
    for day in 1:n_days
        results_dict["$day"] = Dict{String,Any}()
        results_dict_day = JSON.parsefile(joinpath(results_folder,case,"$(file_name)_$(first_hour)_$(last_hour)_day_$(day).json"))
        results_dict["$day"] = results_dict_day
    end
    json_result_check = JSON.json(results_dict)
    open(joinpath(results_folder,case,"$(file_name)_$(first_hour)_$(last_hour)_all_days.json"),"w") do f 
        write(f, json_result_check) 
    end  
    return results_dict
end
types = ["forecasted","measured"]
types = ["measured"]
for type in types
    create_dict_results(n_days,results_folder,case,first_hour,last_hour,"One_topology_$(type)")    
end


for type in types
    create_dict_results(n_days,results_folder,case,first_hour,last_hour,"One_maximum_actions_$(type)")    
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

function create_dict_results_scenarios_with_back_up(n_days,results_folder,case,first_hour,last_hour,hours_per_day,n_scenarios,file_name,file_name_backup)
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
                    this_timestep = (day - 1)*hours_per_day*n_scenarios + (hour - 1)*n_scenarios + n
                    results_dict["$day"]["$hour"]["$n"] = Dict{String,Any}()
                    if length(results_dict_day["solution"]) > 0
                        results_dict["$day"]["$hour"]["$n"] = deepcopy(results_dict_day["solution"]["nw"]["$this_scenario"])
                    else
                        println("I'm here, read in the file with backup")
                        println("Timestep: $this_timestep")
                        results_dict_day_backup = JSON.parsefile(joinpath(results_folder,case,"$(file_name_backup)_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour).json"))
                        results_dict["$day"]["$hour"]["$n"] = deepcopy(results_dict_day_backup["$this_scenario"]["solution"])
                        #results_dict["$day"]["$hour"]["$n"] = deepcopy(results_dict_day_backup["solution"]["nw"]["$this_scenario"])
                    end
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

one_topology_bs_6_day_2 = JSON.parsefile("/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/IJEPES_paper/Results/case_24/stochastic_multistep/24_hours_BS_one_topology_stochastic_Laplace_6_scenarios_8153_8488_day_2.json")
one_sw_bs_6_day_2 = JSON.parsefile("/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/IJEPES_paper/Results/case_24/stochastic_multistep/One_maximum_actions_stochastic_Laplace_6_scenarios_8153_8488_day_2.json")
opf = JSON.parsefile("/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/IJEPES_paper/Results/case_24/stochastic_multistep/Hourly_opf_stochastic_Laplace_6_scenarios_8153_8488.json")

create_dict_results_scenarios_with_back_up(n_days,results_folder,case,first_hour,last_hour,n_hours_per_day,6,"Hourly_bs_stochastic_Laplace_6_scenarios","Hourly_opf_stochastic_Laplace")
create_dict_results_scenarios_with_back_up(n_days,results_folder,case,first_hour,last_hour,n_hours_per_day,8,"Hourly_bs_stochastic_Laplace_8_scenarios","Hourly_opf_stochastic_Laplace")

create_dict_results_scenarios_with_back_up(n_days,results_folder,case,first_hour,last_hour,n_hours_per_day,6,"24_hours_BS_one_topology_stochastic_Laplace_6_scenarios","Hourly_opf_stochastic_Laplace")
create_dict_results_scenarios_with_back_up(n_days,results_folder,case,first_hour,last_hour,n_hours_per_day,8,"One_topology_stochastic_Laplace_8_scenarios","Hourly_opf_stochastic_Laplace")

create_dict_results_scenarios_with_back_up(n_days,results_folder,case,first_hour,last_hour,n_hours_per_day,6,"One_maximum_actions_stochastic_Laplace_6_scenarios","Hourly_opf_stochastic_Laplace")
create_dict_results_scenarios_with_back_up(n_days,results_folder,case,first_hour,last_hour,n_hours_per_day,8,"One_maximum_actions_stochastic_Laplace_8_scenarios","Hourly_opf_stochastic_Laplace")

create_dict_results_scenarios_with_back_up(n_days,results_folder,case,first_hour,last_hour,n_hours_per_day,6,"Two_maximum_actions_stochastic_Laplace_6_scenarios","Hourly_opf_stochastic_Laplace")
create_dict_results_scenarios_with_back_up(n_days,results_folder,case,first_hour,last_hour,n_hours_per_day,8,"24_hours_BS_two_sw_stochastic_Laplace_8_scenarios","Hourly_opf_stochastic_Laplace")


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
    open(joinpath(results_folder,case,"$(file_name)_$(type)_$(first_hour)_$(last_hour)_all_days.json"),"w") do f 
        write(f, json_result_check) 
    end  
end
types = ["forecasted","measured"]
for type in types
    create_dict_results_hourly(n_days,results_folder,case,first_hour,last_hour,"hourly_bs",type)    
end



function upload_results(n_days,results_folder,case,first_hour,last_hour,file_name)
    results_dict = Dict{String,Any}()
    for day in 1:n_days
        results_dict["$day"] = Dict{String,Any}()
        println("Uploading results for day $day")
        results_dict_day = JSON.parsefile(joinpath(results_folder,case,"$(file_name)_$(first_hour)_$(last_hour)_day_$(day).json"))
        results_dict["$day"] = results_dict_day
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


function feasibility_check_days(result_bs,scenario_wind,time_series,n_scenarios,simulation,type,first_hour,last_hour,n_days)
    result_dict = Dict{String,Any}()
    data_dict = Dict{String,Any}()
    n_hours = last_hour - first_hour + 1
    println("Number of hours is $n_hours")
    test_case_bs_replicate = _PM.replicate(test_case_bs, n_hours*n_scenarios)
    test_case_bs_scenarios = deepcopy(test_case_bs_replicate)
    if n_scenarios > 1
        for day in 1:n_days
            data_dict["$day"] = Dict{String,Any}()
            result_dict["$day"] = Dict{String,Any}()
            for h in 1:n_hours_per_day
                data_dict["$day"]["$h"] = Dict{String,Any}()
                result_dict["$day"]["$h"] = Dict{String,Any}()
                if length(result_bs) == n_days
                    for s in 1:n_scenarios
                        println("Day: $day, Hour: $h, Scenario: $s")
                        data_dict["$day"]["$h"]["$s"] = Dict{String,Any}()
                        result_dict["$day"]["$h"]["$s"] = Dict{String,Any}()
                        index = (day - 1)*n_hours_per_day*n_scenarios + (h - 1)*n_scenarios + s
                        println("Index: $index")
                        for (g_id,g) in test_case_bs_scenarios["nw"]["$index"]["gen"]
                            if length(g["cost"]) > 0 && g["cost"][1] <= 0.14 #&& test_case["gen"][g_id]["cost"][1] <= 750.0
                                test_case_bs_scenarios["nw"]["$index"]["gen"][g_id]["pmax"]   = deepcopy(test_case_bs_scenarios["nw"]["$index"]["gen"][g_id]["pmax"]*scenario_wind["$index"]["samples_pu"])
                                println("Gen $g_id, Pmax: $(test_case_bs_scenarios["nw"]["$index"]["gen"][g_id]["pmax"])")
                            end
                        end
                        adding_multinetwork_scenario_days(test_case_bs_scenarios,n_hours,s,n_scenarios,scenario_wind,index,h)
                        result_dict["$day"]["$h"]["$s"] = Dict{String,Any}()
                        run_feasibility_checks_per_hour_days(test_case_bs_scenarios,result_bs,result_dict,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,sc,day,h,n_hours,n_scenarios,index,s,data_dict)            
                    end
                elseif length(result_bs) == n_hours_per_day
                    for s in 1:n_scenarios
                        println("Day: $day, Hour: $h, Scenario: $s")
                        data_dict["$day"]["$h"]["$s"] = Dict{String,Any}()
                        result_dict["$day"]["$h"]["$s"] = Dict{String,Any}()
                        index = (day - 1)*n_hours_per_day*n_scenarios + (h - 1)*n_scenarios + s
                        for (g_id,g) in test_case_bs_scenarios["nw"]["$index"]["gen"]
                            if length(g["cost"]) > 0 && g["cost"][1] <= 0.14 #&& test_case["gen"][g_id]["cost"][1] <= 750.0
                                test_case_bs_scenarios["nw"]["$index"]["gen"][g_id]["pmax"]   = deepcopy(test_case_bs_scenarios["nw"]["$index"]["gen"][g_id]["pmax"]*scenario_wind["$index"]["samples_pu"])
                            end
                        end
                        adding_multinetwork_scenario_days(test_case_bs_scenarios,n_hours,s,n_scenarios,scenario_wind,index,h)
                        #result_dict["$index"] = Dict{String,Any}()
                        run_feasibility_checks_per_hour_days(test_case_bs_scenarios,result_bs,result_dict,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,sc,day,h,n_hours,n_scenarios,index,s,data_dict)            
                    end
                end
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

                for (g_id,g) in test_case_bs_scenarios["nw"]["$index"]["gen"]
                    if length(g["cost"]) > 0 && g["cost"][1] <= 0.14 #&& test_case["gen"][g_id]["cost"][1] <= 750.0
                        test_case_bs_scenarios["nw"]["$index"]["gen"][g_id]["pmax"]   = deepcopy(test_case_bs_scenarios["nw"]["$index"]["gen"][g_id]["pmax"]*time_series[index])
                    end
                end
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
                println("Creating feasibility checks for index $index")
                feasibility_check = deepcopy(grid["nw"]["$index"])
                feasibility_check_input = deepcopy(grid["nw"]["$index"])
                if haskey(result_bs["$day"]["$hour"]["$scenario"],"solution") && length(result_bs["$day"]["$hour"]["$scenario"]["solution"]) > 0
                    _SPMTA.prepare_AC_feasibility_check_stochastic(result_bs["$day"]["$hour"]["$scenario"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
                end
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
            timestep = (day-1)*n_hours_per_day + (hour - 1)*n_scenarios + scenario
            _SPMTA.prepare_AC_feasibility_check_stochastic(result_bs["$day"]["solution"]["nw"]["$hour"]["$scenario"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
            println("Feasibility check for day $day, hour $hour, scenario $scenario, index $index")
            data_dict["$day"]["$hour"]["$scenario"] = feasibility_check
            result_feasibility_checks["$day"]["$hour"]["$scenario"] = _PMACDC.run_acdcopf(feasibility_check,model,optimizer; setting = settings)
            result_feasibility_checks["$day"]["$hour"]["$scenario"]["probability"] = grid["nw"]["$index"]["probability"]    
        end
    else
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


types = ["measured"]
for type in types
    if type == "forecasted"
        hourly_bs_forecasted_days = Dict{String,Any}()
        for day in 1:n_days
            hourly_bs_forecasted_days["$day"] = Dict{String,Any}()
            for hour in 1:n_hours_per_day
                this_hour = (day - 1)*n_hours_per_day + hour
                hourly_bs_forecasted_days["$day"]["$hour"] = Dict{String,Any}()
                println("Uploading results for day $day, hour $hour")
                hourly_bs_forecasted_days["$day"]["$hour"] = deepcopy(hourly_bs_forecasted["$this_hour"])
            end
        end
        json_data_check = JSON.json(hourly_bs_forecasted_days)
        open(joinpath(results_folder,case,"Hourly_bs_forecasted_$(first_hour)_$(last_hour)_all_days.json"),"w") do f 
            write(f, json_data_check) 
        end         

        fc_forecasted = feasibility_check_days(hourly_bs_forecasted_days,scenario_wind,forecasted_wind,one_scenario,"hourly_bs",type,first_hour,last_hour,n_days)
    elseif type == "measured"
        hourly_bs_measured_days = Dict{String,Any}()
        for day in 1:n_days
            hourly_bs_measured_days["$day"] = Dict{String,Any}()
            for hour in 1:n_hours_per_day
                this_hour = (day - 1)*n_hours_per_day + hour
                hourly_bs_measured_days["$day"]["$hour"] = Dict{String,Any}()
                println("Uploading results for day $day, hour $hour")
                hourly_bs_measured_days["$day"]["$hour"] = deepcopy(hourly_bs_measured["$this_hour"])
            end
        end
        json_data_check = JSON.json(hourly_bs_measured_days)
        open(joinpath(results_folder,case,"Hourly_bs_measured_$(first_hour)_$(last_hour)_all_days.json"),"w") do f 
            write(f, json_data_check) 
        end 

        fc_measured = feasibility_check_days(hourly_bs_measured_days,scenario_wind,measured_wind,one_scenario,"hourly_bs",type,first_hour,last_hour,n_days)
    end
end






types = ["measured"]
for type in types
    if type == "forecasted"
        hourly_bs_forecasted_days = Dict{String,Any}()
        for day in 1:n_days
            hourly_bs_forecasted_days["$day"] = Dict{String,Any}()
            for hour in 1:n_hours_per_day
                this_hour = (day - 1)*n_hours_per_day + hour
                hourly_bs_forecasted_days["$day"]["$hour"] = Dict{String,Any}()
                println("Uploading results for day $day, hour $hour")
                hourly_bs_forecasted_days["$day"]["$hour"] = deepcopy(hourly_bs_forecasted["$this_hour"])
            end
        end
        json_data_check = JSON.json(hourly_bs_forecasted_days)
        open(joinpath(results_folder,case,"Hourly_bs_forecasted_$(first_hour)_$(last_hour)_all_days.json"),"w") do f 
            write(f, json_data_check) 
        end         

        fc_forecasted = feasibility_check_days(hourly_bs_forecasted_days,scenario_wind,forecasted_wind,one_scenario,"hourly_bs",type,first_hour,last_hour,n_days)
    elseif type == "measured"
        hourly_bs_measured_days = Dict{String,Any}()
        for day in 1:n_days
            hourly_bs_measured_days["$day"] = Dict{String,Any}()
            for hour in 1:n_hours_per_day
                this_hour = (day - 1)*n_hours_per_day + hour
                hourly_bs_measured_days["$day"]["$hour"] = Dict{String,Any}()
                println("Uploading results for day $day, hour $hour")
                hourly_bs_measured_days["$day"]["$hour"] = deepcopy(hourly_bs_measured["$this_hour"])
            end
        end
        json_data_check = JSON.json(hourly_bs_measured_days)
        open(joinpath(results_folder,case,"Hourly_bs_measured_$(first_hour)_$(last_hour)_all_days.json"),"w") do f 
            write(f, json_data_check) 
        end 

        fc_measured = feasibility_check_days(hourly_bs_measured_days,scenario_wind,measured_wind,one_scenario,"hourly_bs",type,first_hour,last_hour,n_days)
    end
end



















types = ["forecasted"]
for type in types
    if type == "forecasted"
        one_topology_all_days_forecasted = upload_results(n_days,results_folder,case,first_hour,last_hour,"one_topology_$(type)")    
        fc_forecasted = feasibility_check_days(one_topology_all_days_forecasted,scenario_wind,forecasted_wind,one_scenario,"one_topology",type,first_hour,last_hour,n_days)
    #elseif type == "average"
    #    one_topology_all_days_average = upload_results(n_days,results_folder,case,first_hour,last_hour,"one_topology_$(type)")    
    #    fc_average = feasibility_check_days(one_topology_all_days_average,scenario_wind,average_wind,one_scenario,"one_topology",type,first_hour,last_hour)
    elseif type == "measured"
        one_topology_all_days_measured = upload_results_all_days(results_folder,case,first_hour,last_hour,"One_topology_$(type)")    
        fc_measured = feasibility_check_days(one_topology_all_days_measured,scenario_wind,measured_wind,one_scenario,"one_topology",type,first_hour,last_hour,n_days)
    end
end


for type in types
    if type == "forecasted"
        #one_sw_action_all_days_forecasted = upload_results(n_days,results_folder,case,first_hour,last_hour,"one_maximum_actions_$(type)")    
        #fc_forecasted = feasibility_check_days(one_sw_action_all_days_forecasted,scenario_wind,forecasted_wind,1,"one_maximum_actions",type,first_hour,last_hour,n_days)
    elseif type == "measured"
        one_sw_action_all_days_measured = upload_results(n_days,results_folder,case,first_hour,last_hour,"one_maximum_actions_$(type)")    
        fc_measured = feasibility_check_days(one_sw_action_all_days_measured,scenario_wind,measured_wind,1,"one_maximum_actions_",type,first_hour,last_hour,n_days)
    end
end


for type in types
    if type == "forecasted"
        two_sw_action_all_days_forecasted = upload_results(n_days,results_folder,case,first_hour,last_hour,"two_maximum_actions_$(type)")    
        fc_forecasted = feasibility_check_days(two_sw_forecasted,scenario_wind,forecasted_wind,one_scenario,"two_maximum_actions",type,first_hour,last_hour,n_days)
    #elseif type == "average"
    #    two_sw_action_all_days_average = upload_results(n_days,results_folder,case,first_hour,last_hour,"two_maximum_actions_$(type)")    
    #    fc_average = feasibility_check_days(two_sw_action_all_days_average,scenario_wind,average_wind,two_scenario,"two_maximum_actions",type,first_hour,last_hour)
    #elseif type == "measured"
    #    two_sw_action_all_days_measured = upload_results(n_days,results_folder,case,first_hour,last_hour,"two_maximum_actions_$(type)")    
    #    fc_measured = feasibility_check_days(two_sw_action_all_days_measured,scenario_wind,measured_wind,one_scenario,"two_maximum_actions_",type,first_hour,last_hour)
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

hourly_bs_6_all_days = upload_results(n_days,results_folder,case,first_hour,last_hour,"Hourly_bs_stochastic_Laplace_6_scenarios")
hourly_bs_8_all_days = upload_results(n_days,results_folder,case,first_hour,last_hour,"Hourly_bs_stochastic_Laplace_8_scenarios")


json_data_check = JSON.json(hourly_bs_6_all_days)
open(joinpath(results_folder,case,"Hourly_bs_stochastic_Laplace_6_scenarios_$(first_hour)_$(last_hour)_all_days.json"),"w") do f 
    write(f, json_data_check) 
end 

json_data_check = JSON.json(hourly_bs_8_all_days)
open(joinpath(results_folder,case,"Hourly_bs_stochastic_Laplace_8_scenarios_$(first_hour)_$(last_hour)_all_days.json"),"w") do f 
    write(f, json_data_check) 
end 


try_ = JSON.parsefile(joinpath(results_folder,case,"Hourly_bs_stochastic_Laplace_6_scenarios_$(first_hour)_$(last_hour)_day_1.json"))

hourly_bs_scenarios_6 = upload_results_all_days(results_folder,case,first_hour,last_hour,"One_maximum_actions_stochastic_Laplace_6_scenarios")
hourly_bs_scenarios_8 = upload_results_all_days(results_folder,case,first_hour,last_hour,"Hourly_bs_stochastic_Laplace_8_scenarios")

fc_hourly_bs_scenarios_6 = feasibility_check_days(hourly_bs_scenarios_6,scenario_wind_6,forecasted_wind,6,"One_maximum_actions_stochastic_Laplace_6_scenarios_8153_8488_all_days","stochastic",first_hour,last_hour,n_days)
fc_hourly_bs_scenarios_8 = feasibility_check_days(hourly_bs_scenarios_8,scenario_wind_8,forecasted_wind,8,"Hourly_bs_stochastic_Laplace_8_scenarios","stochastic",first_hour,last_hour,n_days)

###############

function upload_results(n_days,results_folder,case,first_hour,last_hour,file_name)
    results_dict = Dict{String,Any}()
    for day in 1:n_days
        results_dict["$day"] = Dict{String,Any}()
        println("Uploading results for day $day")
        results_dict_day = JSON.parsefile(joinpath(results_folder,case,"$(file_name)_$(first_hour)_$(last_hour)_day_$(day).json"))
        results_dict["$day"] = results_dict_day
    end
    return results_dict
end

one_topology_scenarios_6 = upload_results(n_days,results_folder,case,first_hour,last_hour,"24_hours_BS_one_topology_stochastic_Laplace_6_scenarios")
one_topology_scenarios_8 = upload_results(n_days,results_folder,case,first_hour,last_hour,"24_hours_BS_one_topology_stochastic_Laplace_8_scenarios")

one_topology_scenarios_6 = upload_results_all_days(results_folder,case,first_hour,last_hour,"24_hours_BS_one_topology_stochastic_Laplace_6_scenarios")
one_topology_scenarios_8 = upload_results_all_days(results_folder,case,first_hour,last_hour,"One_topology_stochastic_Laplace_8_scenarios")

fc_one_topology_scenarios_6 = feasibility_check_days(one_topology_scenarios_6,scenario_wind_6,forecasted_wind,6,"One_topology_stochastic_Laplace_6_scenarios",type,first_hour,last_hour,n_days)
fc_one_topology_scenarios_8 = feasibility_check_days(one_topology_scenarios_8,scenario_wind_8,forecasted_wind,8,"One_topology_stochastic_Laplace_8_scenarios",type,first_hour,last_hour,n_days)

###############

one_sw_scenarios_6 = upload_results_all_days(results_folder,case,first_hour,last_hour,"One_maximum_actions_stochastic_Laplace_6_scenarios")
#one_sw_scenarios_8 = upload_results_all_days(results_folder,case,first_hour,last_hour,"24_hours_BS_one_sw_stochastic_Laplace_8_scenarios")

fc_one_sw_scenarios_6 = feasibility_check_days(one_sw_scenarios_6,scenario_wind_6,forecasted_wind,6,"One_maximum_actions_stochastic_Laplace_6_scenarios",type,first_hour,last_hour,n_days)
#fc_one_sw_scenarios_8 = feasibility_check_days(one_sw_scenarios_8,scenario_wind_8,forecasted_wind,8,"24_hours_BS_one_sw_stochastic_Laplace_8_scenarios",type,first_hour,last_hour,n_days)

###############

two_sw_scenarios_6 = upload_results_all_days(results_folder,case,first_hour,last_hour,"Two_maximum_actions_stochastic_Laplace_6_scenarios")
two_sw_scenarios_8 = upload_results_all_days(results_folder,case,first_hour,last_hour,"Two_maximum_actions_stochastic_Laplace_8_scenarios")

fc_two_sw_scenarios_6 = feasibility_check_days(two_sw_scenarios_6,scenario_wind_6,forecasted_wind,6,"Two_maximum_actions_stochastic_Laplace_6_scenarios",type,first_hour,last_hour,n_days)
fc_two_sw_scenarios_8 = feasibility_check_days(two_sw_scenarios_8,scenario_wind_8,forecasted_wind,8,"Two_maximum_actions_stochastic_Laplace_8_scenarios",type,first_hour,last_hour,n_days)


############################ 
### 24 hours
# one scenario
hourly_bs_measured = JSON.parsefile(joinpath(results_folder,case,"Hourly_bs_measured_$(first_hour)_$(last_hour).json"))
hourly_bs_forecasted = JSON.parsefile(joinpath(results_folder,case,"Hourly_bs_forecasted_$(first_hour)_$(last_hour).json"))

one_topology_measured = JSON.parsefile(joinpath(results_folder,case,"24_hours_BS_one_topology_measured_$(first_hour)_$(last_hour).json"))
one_topology_forecasted = JSON.parsefile(joinpath(results_folder,case,"24_hours_BS_one_topology_forecasted_$(first_hour)_$(last_hour).json"))

one_sw_measured = JSON.parsefile(joinpath(results_folder,case,"One_maximum_actions_24_hours_measured_$(first_hour)_$(last_hour).json"))
one_sw_forecasted = JSON.parsefile(joinpath(results_folder,case,"One_maximum_actions_24_hours_forecasted_$(first_hour)_$(last_hour).json"))

two_sw_measured = JSON.parsefile(joinpath(results_folder,case,"Two_maximum_actions_24_hours_measured_$(first_hour)_$(last_hour).json"))
two_sw_forecasted = JSON.parsefile(joinpath(results_folder,case,"Two_maximum_actions_24_hours_forecasted_$(first_hour)_$(last_hour).json"))

# 6 scenarios
hourly_bs_scenarios_6 = JSON.parsefile(joinpath(results_folder,case,"Hourly_bs_stochastic_Laplace_6_scenarios_$(first_hour)_$(last_hour)_day_1.json"))

one_topology_scenarios_6 = JSON.parsefile(joinpath(results_folder,case,"24_hours_BS_one_topology_stochastic_Laplace_6_scenarios_$(first_hour)_$(last_hour).json"))
one_sw_scenarios_6 = JSON.parsefile(joinpath(results_folder,case,"One_maximum_actions_24_hours_stochastic_Laplace_6_scenarios_$(first_hour)_$(last_hour).json"))
two_sw_scenarios_6 = JSON.parsefile(joinpath(results_folder,case,"Two_maximum_actions_24_hours_stochastic_Laplace_6_scenarios_$(first_hour)_$(last_hour).json"))

# 8 scenarios
hourly_bs_scenarios_8 = JSON.parsefile(joinpath(results_folder,case,"Hourly_bs_stochastic_Laplace_8_scenarios_$(first_hour)_$(last_hour)_day_1.json"))

one_topology_scenarios_8 = JSON.parsefile(joinpath(results_folder,case,"24_hours_BS_one_topology_stochastic_Laplace_8_scenarios_$(first_hour)_$(last_hour).json"))
one_sw_scenarios_8 = JSON.parsefile(joinpath(results_folder,case,"One_maximum_actions_24_hours_stochastic_Laplace_8_scenarios_$(first_hour)_$(last_hour).json"))
two_sw_scenarios_8 = JSON.parsefile(joinpath(results_folder,case,"Two_maximum_actions_24_hours_stochastic_Laplace_8_scenarios_$(first_hour)_$(last_hour).json"))


################# Feasibility checks 24 hours ###############
hourly_bs_forecasted_fixed = Dict{String,Any}()
hourly_bs_forecasted_fixed["1"] = Dict{String,Any}()

for i in 1:n_hours_per_day
    hourly_bs_forecasted_fixed["1"]["$i"] = Dict{String,Any}()
    hourly_bs_forecasted_fixed["1"]["$i"] = deepcopy(hourly_bs_forecasted["$i"])
end

hourly_bs_measured_fixed = Dict{String,Any}()
hourly_bs_measured_fixed["1"] = Dict{String,Any}()

for i in 1:n_hours_per_day
    hourly_bs_measured_fixed["1"]["$i"] = Dict{String,Any}()
    hourly_bs_measured_fixed["1"]["$i"] = deepcopy(hourly_bs_measured["$i"])
end


two_sw_forecasted_fixed = Dict{String,Any}()
two_sw_forecasted_fixed["1"] = Dict{String,Any}()
two_sw_forecasted_fixed["1"] = deepcopy(two_sw_forecasted)

two_sw_measured_fixed = Dict{String,Any}()
two_sw_measured_fixed["1"] = Dict{String,Any}()
two_sw_measured_fixed["1"] = deepcopy(two_sw_measured)


types = ["forecasted","measured"]
for type in types
    if type == "forecasted"
        fc_hourly_bs_forecasted = feasibility_check_days(hourly_bs_forecasted_fixed,scenario_wind,forecasted_wind,one_scenario,"hourly_bs",type,first_hour,last_hour,1)
        fc_one_topology_forecasted = feasibility_check_days(one_topology_forecasted,scenario_wind,forecasted_wind,one_scenario,"one_topology",type,first_hour,last_hour,1)
        fc_one_sw_forecasted = feasibility_check_days(one_sw_forecasted,scenario_wind,forecasted_wind,one_scenario,"one_maximum_actions",type,first_hour,last_hour,1)
        fc_two_sw_forecasted = feasibility_check_days(two_sw_forecasted_fixed,scenario_wind,forecasted_wind,one_scenario,"two_maximum_actions",type,first_hour,last_hour,1)
    elseif type == "measured"
        fc_hourly_bs_measured = feasibility_check_days(hourly_bs_measured_fixed,scenario_wind,measured_wind,one_scenario,"hourly_bs",type,first_hour,last_hour,1)
        fc_one_topology_measured = feasibility_check_days(one_topology_measured,scenario_wind,measured_wind,one_scenario,"one_topology",type,first_hour,last_hour,1)
        fc_one_sw_measured = feasibility_check_days(one_sw_measured,scenario_wind,measured_wind,one_scenario,"one_maximum_actions",type,first_hour,last_hour,1)
        fc_two_sw_measured = feasibility_check_days(two_sw_measured_fixed,scenario_wind,measured_wind,one_scenario,"two_maximum_actions",type,first_hour,last_hour,1)
    end
end

################## Feasibility checks 24 hours scenarios ###############

function feasibility_check_one_day(result_bs,scenario_wind,time_series,n_scenarios,simulation,type,first_hour,last_hour,n_days)
    result_dict = Dict{String,Any}()
    data_dict = Dict{String,Any}()
    test_case_bs_replicate = _PM.replicate(test_case_bs, n_hours*n_scenarios)
    test_case_bs_scenarios = deepcopy(test_case_bs_replicate)
    if n_scenarios > 1
        if length(result_bs) == n_days
            println("WE HERE LET'S GO")
            for day in 1:n_days
                data_dict["$day"] = Dict{String,Any}()
                result_dict["$day"] = Dict{String,Any}()
                for h in 1:n_hours_per_day
                    data_dict["$day"]["$h"] = Dict{String,Any}()
                    result_dict["$day"]["$h"] = Dict{String,Any}()
                    if length(result_bs) == n_days
                        for s in 1:n_scenarios
                            println("Day: $day, Hour: $h, Scenario: $s")
                            data_dict["$day"]["$h"]["$s"] = Dict{String,Any}()
                            result_dict["$day"]["$h"]["$s"] = Dict{String,Any}()
                            index = (day - 1)*n_hours_per_day*n_scenarios + (h - 1)*n_scenarios + s


                            for (g_id,g) in test_case_bs_scenarios["nw"]["$index"]["gen"]
                                if length(g["cost"]) > 0 && g["cost"][1] <= 0.14 #&& test_case["gen"][g_id]["cost"][1] <= 750.0
                                    test_case_bs_scenarios["nw"]["$index"]["gen"][g_id]["pmax"]   = deepcopy(test_case_bs_scenarios["nw"]["$index"]["gen"][g_id]["pmax"]*scenario_wind["$index"]["samples_pu"])
                                end
                            end
                            adding_multinetwork_scenario_days(test_case_bs_scenarios,n_hours,s,n_scenarios,scenario_wind,index,h)
                            #result_dict["$index"] = Dict{String,Any}()
                            run_feasibility_checks_per_hour_days(test_case_bs_scenarios,result_bs,result_dict,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,sc,day,h,n_hours,n_scenarios,index,s,data_dict)            
                        end
                    elseif length(result_bs) == n_hours_per_day
                        for s in 1:n_scenarios
                            println("Day: $day, Hour: $h, Scenario: $s")
                            data_dict["$day"]["$h"]["$s"] = Dict{String,Any}()
                            result_dict["$day"]["$h"]["$s"] = Dict{String,Any}()
                            index = (day - 1)*n_hours_per_day*n_scenarios + (h - 1)*n_scenarios + s
                            for (g_id,g) in test_case_bs_scenarios["nw"]["$index"]["gen"]
                                if length(g["cost"]) > 0 && g["cost"][1] <= 0.14 #&& test_case["gen"][g_id]["cost"][1] <= 750.0
                                    test_case_bs_scenarios["nw"]["$index"]["gen"][g_id]["pmax"]   = deepcopy(test_case_bs_scenarios["nw"]["$index"]["gen"][g_id]["pmax"]*scenario_wind["$index"]["samples_pu"])
                                end
                            end
                            adding_multinetwork_scenario_days(test_case_bs_scenarios,n_hours,s,n_scenarios,scenario_wind,index,h)
                            #result_dict["$index"] = Dict{String,Any}()
                            run_feasibility_checks_per_hour_one_day(test_case_bs_scenarios,result_bs,result_dict,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,sc,day,h,n_hours,n_scenarios,index,s,data_dict)            
                        end
                    end
                end
            end
        elseif length(result_bs) == n_hours_per_day
            
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

                for (g_id,g) in test_case_bs_scenarios["nw"]["$index"]["gen"]
                    if length(g["cost"]) > 0 && g["cost"][1] <= 0.14 #&& test_case["gen"][g_id]["cost"][1] <= 750.0
                        test_case_bs_scenarios["nw"]["$index"]["gen"][g_id]["pmax"]   = deepcopy(test_case_bs_scenarios["nw"]["$index"]["gen"][g_id]["pmax"]*time_series[index])
                    end
                end
                adding_multinetwork_scenario_days(test_case_bs_scenarios,n_hours,s,n_scenarios,time_series,index,h)
                #result_dict["$index"] = Dict{String,Any}()
                run_feasibility_checks_per_hour_one_day(test_case_bs_scenarios,result_bs,result_dict,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,sc,day,h,n_hours,n_scenarios,index,s,data_dict)            
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


function run_feasibility_checks_per_hour_one_day(grid, result_bs,result_feasibility_checks, model, optimizer,switches_couples_ac,extremes_ZILs_ac,test_case_opf,settings,day,hour,n_hours,n_scenarios,index,scenario,data_dict)
    #result_feasibility_checks = Dict{String,Any}()
    if n_scenarios > 1
        if length(result_bs) == n_days
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
        elseif length(result_bs) == n_hours_per_day
            feasibility_check = deepcopy(grid["nw"]["$index"])
            feasibility_check_input = deepcopy(grid["nw"]["$index"])
            timestep = (hour - 1)*n_scenarios + scenario
            _SPMTA.prepare_AC_feasibility_check_stochastic(result_bs["$hour"]["solution"]["nw"]["$scenario"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
            println("Feasibility check for day $day, hour $hour, scenario $scenario, index $index")
            data_dict["$day"]["$hour"]["$scenario"] = feasibility_check
            result_feasibility_checks["$day"]["$hour"]["$scenario"] = _PMACDC.run_acdcopf(feasibility_check,model,optimizer; setting = settings)
            result_feasibility_checks["$day"]["$hour"]["$scenario"]["probability"] = grid["nw"]["$index"]["probability"]    
        elseif length(result_bs) == 8
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
        end
    else
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



type = "forecasted"
hourly_bs_scenario_8_corrected = Dict{String,Any}()
hourly_bs_scenario_8_corrected["1"] = Dict{String,Any}()
for hour in 1:n_hours_per_day
    hourly_bs_scenario_8_corrected["1"]["$hour"] = Dict{String,Any}()
    hourly_bs_scenario_8_corrected["1"]["$hour"] = deepcopy(hourly_bs_scenarios_8["$hour"])
end

fc_hourly_bs_scenarios_6 = feasibility_check_one_day(hourly_bs_scenarios_6,scenario_wind_6,forecasted_wind,6,"Hourly_bs_stochastic_Laplace_6_scenarios",type,first_hour,last_hour,1)
fc_hourly_bs_scenarios_8 = feasibility_check_one_day(hourly_bs_scenario_8_corrected,scenario_wind_8,forecasted_wind,8,"Hourly_bs_stochastic_Laplace_8_scenarios",type,first_hour,last_hour,1)

###############
one_topology_scenarios_6_fixed = Dict{String,Any}()
one_topology_scenarios_6_fixed["1"] = Dict{String,Any}()

for i in 1:n_hours_per_day
    one_topology_scenarios_6_fixed["1"]["$i"] = Dict{String,Any}()
    one_topology_scenarios_6_fixed["1"]["$i"] = deepcopy(one_topology_scenarios_6)
end


fc_one_topology_scenarios_6 = feasibility_check_one_day(one_topology_scenarios_6_fixed,scenario_wind_6,forecasted_wind,6,"24_hours_BS_one_topology_stochastic_Laplace_6_scenarios",type,first_hour,last_hour,1)
fc_one_topology_scenarios_8 = feasibility_check_one_day(one_topology_scenarios_8_fixed,scenario_wind_8,forecasted_wind,8,"24_hours_BS_one_topology_stochastic_Laplace_8_scenarios",type,first_hour,last_hour,1)

###############
one_sw_scenarios_6_fixed = Dict{String,Any}()
one_sw_scenarios_6_fixed["1"] = Dict{String,Any}()
one_sw_scenarios_6_fixed["1"] = deepcopy(one_sw_scenarios_6)


fc_one_sw_scenarios_6 = feasibility_check_one_day(one_sw_scenarios_6_fixed,scenario_wind_6,forecasted_wind,6,"24_hours_BS_one_sw_stochastic_Laplace_6_scenarios",type,first_hour,last_hour,1)
fc_one_sw_scenarios_8 = feasibility_check_one_day(one_sw_scenarios_8_fixed,scenario_wind_8,forecasted_wind,8,"24_hours_BS_one_sw_stochastic_Laplace_8_scenarios",type,first_hour,last_hour,1)

###############
two_sw_scenarios_6_fixed = Dict{String,Any}()
two_sw_scenarios_6_fixed["1"] = Dict{String,Any}()
two_sw_scenarios_6_fixed["1"] = deepcopy(two_sw_scenarios_6)


fc_two_sw_scenarios_6 = feasibility_check_one_day(two_sw_scenarios_6_fixed,scenario_wind_6,forecasted_wind,6,"24_hours_BS_two_sw_stochastic_Laplace_6_scenarios",type,first_hour,last_hour,1)
fc_two_sw_scenarios_8 = feasibility_check_one_day(one_sw_scenarios_8_fixed,scenario_wind_8,forecasted_wind,8,"24_hours_BS_two_sw_stochastic_Laplace_8_scenarios",type,first_hour,last_hour,1)


