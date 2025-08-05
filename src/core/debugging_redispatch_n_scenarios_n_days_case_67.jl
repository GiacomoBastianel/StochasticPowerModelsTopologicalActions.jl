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


#first_hour = 355
#last_hour  = 378


first_hour = 8153
last_hour  = 8488
n_hours = last_hour - first_hour + 1
n_scenarios = 6
n_days = 1
one_scenario = 1
n_hours_per_day = 24

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
## Processing input data
input_folder = "$(dirname(dirname(@__DIR__)))/src/core"

scenario_wind = JSON.parsefile(joinpath(input_folder,"case30","Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour).json"))
if first_hour == 355 && last_hour == 378
    measured_wind = JSON.parsefile(joinpath(input_folder,"case30","measured_wind_$(first_hour)_$(last_hour)_modified.json"))
    forecasted_wind = JSON.parsefile(joinpath(input_folder,"case30","forecasted_wind_hours_$(first_hour)_$(last_hour)_modified.json"))
elseif first_hour == 8153 && last_hour == 8488
    measured_wind = JSON.parsefile(joinpath(input_folder,"case30","measured_two_weeks_$(first_hour)_$(last_hour).json"))
    forecasted_wind = JSON.parsefile(joinpath(input_folder,"case30","forecasted_two_weeks_$(first_hour)_$(last_hour).json"))
end

hourly_opf_stochastic = JSON.parsefile(joinpath(results_folder,case,"Hourly_opf_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour).json"))
hourly_opf_measured = JSON.parsefile(joinpath(results_folder,case,"Hourly_opf_ac_measured_$(first_hour)_$(last_hour).json"))
hourly_opf_forecasted = JSON.parsefile(joinpath(results_folder,case,"Hourly_opf_ac_forecasted_$(first_hour)_$(last_hour).json"))

################### Hourly optimization ########################
bs_hourly_forecasted = JSON.parsefile(joinpath(results_folder,case,"hourly_bs_forecasted_$(first_hour)_$(last_hour)_all_days.json"))
feasibility_check_bs_hourly_forecasted  = JSON.parsefile(joinpath(results_folder,case,"fc_hourly_bs_forecasted_$(first_hour)_$(last_hour)_all_days.json")) 

bs_hourly_measured = JSON.parsefile(joinpath(results_folder,case,"hourly_bs_measured_$(first_hour)_$(last_hour)_all_days.json"))
feasibility_check_bs_hourly_measured  = JSON.parsefile(joinpath(results_folder,case,"fc_hourly_bs_measured_$(first_hour)_$(last_hour)_all_days.json")) 


################### One topology ########################
bs_one_topology_forecasted = JSON.parsefile(joinpath(results_folder,case,"One_topology_forecasted_$(first_hour)_$(last_hour)_all_days.json"))
feasibility_check_bs_one_topology_forecasted  = JSON.parsefile(joinpath(results_folder,case,"fc_one_topology_forecasted_$(first_hour)_$(last_hour)_all_days.json")) 

bs_one_topology_measured = JSON.parsefile(joinpath(results_folder,case,"One_topology_measured_$(first_hour)_$(last_hour)_all_days.json"))
feasibility_check_bs_one_topology_measured  = JSON.parsefile(joinpath(results_folder,case,"fc_one_topology_measured_$(first_hour)_$(last_hour)_all_days.json")) 


################### One switching action ########################

################### Two switching actions ########################


#########################################################################################

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
                for (g_id,g) in test_case_bs_scenarios["nw"]["$timestep"]["gen"]
                    if length(g["cost"]) > 0 && g["cost"][1] <= 0.14 
                        test_case_bs_scenarios["nw"]["$timestep"]["gen"][g_id]["pmax"]   = deepcopy(test_case_bs_scenarios["nw"]["$timestep"]["gen"][g_id]["pmax"]*scenario_wind["$timestep"]["samples_pu"])
                        test_case_bs_realized["nw"]["$timestep"]["gen"][g_id]["pmax"]   = deepcopy(test_case_bs_scenarios["nw"]["$timestep"]["gen"][g_id]["pmax"]*realized_time_series[hour])
                    end
                end
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

gen_wind = []
for (g_id,g) in test_case_opf["gen"]
    if length(g["cost"]) > 0 && g["cost"][1] <= 0.14 
        push!(gen_wind,g_id)
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
            
                for (g_id,g) in test_case_opf_mn_scenarios["nw"]["$timestep"]["gen"]
                    if length(g["cost"]) > 0 && g["cost"][1] <= 0.14 
                        test_case_opf_mn_scenarios["nw"]["$timestep"]["gen"][g_id]["pmax"]   = deepcopy(result_opf_measured["$hour"]["solution"]["gen"][g_id]["pg"])
                        test_case_opf_mn_realized["nw"]["$timestep"]["gen"][g_id]["pmax"]   = deepcopy(result_opf_measured["$hour"]["solution"]["gen"][g_id]["pg"])
                    end
                    println("Pmax for generator $g_id in test_case_opf_mn_scenarios is $(test_case_opf_mn_scenarios["nw"]["$timestep"]["gen"][g_id]["pmax"])")
                    println("Pmax for generator $g_id in test_case_opf_mn_realized is $(test_case_opf_mn_realized["nw"]["$timestep"]["gen"][g_id]["pmax"])")    
                end
     

            # Adding set points
                for (g_id,g) in test_case_opf_mn_scenarios["nw"]["$timestep"]["gen"]
                g["pg_start"] = result_opf["$timestep"]["solution"]["gen"][g_id]["pg"]
                g["qg_start"] = result_opf["$timestep"]["solution"]["gen"][g_id]["qg"]
                    if g_id in gen_wind
                        g["redispatch_cost_up"] = 0.14
                        g["redispatch_cost_down"] = 0.14
                    else
                        g["redispatch_cost_up"] = g["cost"][1]
                        g["redispatch_cost_down"] = g["cost"][1]
                    end
                end

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
            
                for (g_id,g) in test_case_opf_mn_scenarios["nw"]["$hour"]["gen"]
                    if length(g["cost"]) > 0 && g["cost"][1] <= 0.14 
                        test_case_opf_mn_scenarios["nw"]["$hour"]["gen"][g_id]["pmax"]   = deepcopy(result_opf_measured["$hour"]["solution"]["gen"][g_id]["pg"])
                        test_case_opf_mn_realized["nw"]["$hour"]["gen"][g_id]["pmax"]   = deepcopy(result_opf_measured["$hour"]["solution"]["gen"][g_id]["pg"])
                    end
                    println("Pmax for generator $g_id in test_case_opf_mn_scenarios is $(test_case_opf_mn_scenarios["nw"]["$hour"]["gen"][g_id]["pmax"])")
                    println("Pmax for generator $g_id in test_case_opf_mn_realized is $(test_case_opf_mn_realized["nw"]["$hour"]["gen"][g_id]["pmax"])")    
                end                     

            # Adding set points
                for (g_id,g) in test_case_opf_mn_scenarios["nw"]["$hour"]["gen"]
                g["pg_start"] = result_opf["$hour"]["solution"]["gen"][g_id]["pg"]
                g["qg_start"] = result_opf["$hour"]["solution"]["gen"][g_id]["qg"]
                    if g_id in gen_wind
                        g["redispatch_cost_up"] = 0.14
                        g["redispatch_cost_down"] = 0.14
                    else
                        g["redispatch_cost_up"] = g["cost"][1]
                        g["redispatch_cost_down"] = g["cost"][1]
                    end
                end

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
                
                for (g_id,g) in test_case_bs_scenarios["nw"]["$timestep"]["gen"]
                    if length(g["cost"]) > 0 && g["cost"][1] <= 0.14 
                        test_case_bs_scenarios["nw"]["$timestep"]["gen"][g_id]["pmax"]   = deepcopy(result_fc_measured["$day"]["$hour"]["solution"]["gen"][g_id]["pg"])
                        test_case_bs_realized["nw"]["$timestep"]["gen"][g_id]["pmax"]   = deepcopy(result_fc_measured["$day"]["$hour"]["solution"]["gen"][g_id]["pg"])
                    end
                end

                feasibility_check = deepcopy(test_case_bs_realized["nw"]["$timestep"])
                feasibility_check_input = deepcopy(test_case_bs_realized["nw"]["$timestep"])
                feasibility_check["per_unit"] = true
                feasibility_check_input["per_unit"] = true
                if length(result_bs["$day"]) == n_hours_per_day
                    println("PDD Feasibility check & OPF and redispatch for day $day, hour $hour, scenario $s, timestep $timestep")
                    if haskey(result_bs["$day"]["$hour"],"solution") 
                            _SPMTA.prepare_AC_feasibility_check_stochastic(result_bs["$day"]["$hour"]["solution"]["nw"]["$s"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
                            result_dict["$day"]["$hour"]["$s"] = Dict{String,Any}()
                            result_dict["$day"]["$hour"]["$s"] = run_hourly_redispatch_stochastic_fc_days(feasibility_check,test_case_bs_scenarios,result_fc,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,sc,n_hours,number_scenarios,count_scenarios,day,hour,s)                    
                    elseif haskey(result_bs["$day"]["$hour"],"$s")
                        if haskey(result_bs["$day"]["$hour"]["$s"],"switch") 
                            println("There are switches here")
                            _SPMTA.prepare_AC_feasibility_check_stochastic(result_bs["$day"]["$hour"]["$s"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
                        end
                        result_dict["$day"]["$hour"]["$s"] = Dict{String,Any}()
                        result_dict["$day"]["$hour"]["$s"] = run_hourly_redispatch_stochastic_fc_days(feasibility_check,test_case_bs_scenarios,result_fc,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,sc,n_hours,number_scenarios,count_scenarios,day,hour,s)                    
                    end
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
            if length(result_fc_measured["$day"]) == 8
                println("YAY ")
                for (g_id,g) in test_case_bs_scenarios["nw"]["$this_hour"]["gen"]
                    if length(g["cost"]) > 0 && g["cost"][1] <= 0.14 
                        test_case_bs_scenarios["nw"]["$this_hour"]["gen"][g_id]["pmax"]   = deepcopy(result_fc_measured["$day"]["solution"]["nw"]["$hour"]["gen"][g_id]["pg"])
                        test_case_bs_realized["nw"]["$this_hour"]["gen"][g_id]["pmax"]   = deepcopy(result_fc_measured["$day"]["solution"]["nw"]["$hour"]["gen"][g_id]["pg"])
                        println("Pmax for generator $g_id in test_case_bs_scenarios is $(test_case_bs_scenarios["nw"]["$this_hour"]["gen"][g_id]["pmax"])")
                        println("Pmax for generator $g_id in test_case_bs_realized is $(test_case_bs_realized["nw"]["$this_hour"]["gen"][g_id]["pmax"])")    
                    end
                end
            elseif length(result_fc_measured["$day"]) == n_hours_per_day       
                println("YOY ")
                for (g_id,g) in test_case_bs_scenarios["nw"]["$this_hour"]["gen"]
                    if length(g["cost"]) > 0 && g["cost"][1] <= 0.14 
                        test_case_bs_scenarios["nw"]["$this_hour"]["gen"][g_id]["pmax"]   = deepcopy(result_fc_measured["$day"]["$hour"]["solution"]["gen"][g_id]["pg"])
                        test_case_bs_realized["nw"]["$this_hour"]["gen"][g_id]["pmax"]   = deepcopy(result_fc_measured["$day"]["$hour"]["solution"]["gen"][g_id]["pg"])
                        println("Pmax for generator $g_id in test_case_bs_scenarios is $(test_case_bs_scenarios["nw"]["$this_hour"]["gen"][g_id]["pmax"])")
                        println("Pmax for generator $g_id in test_case_bs_realized is $(test_case_bs_realized["nw"]["$this_hour"]["gen"][g_id]["pmax"])")    
                    end
                end
            end
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
                    println("PDDD HEY HEY Feasibility check & OPF and redispatch for day $day, hour $hour")
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
                        if g_id in gen_wind
                            g["redispatch_cost_up"] = 0.14
                            g["redispatch_cost_down"] = 0.14
                        else
                            g["redispatch_cost_up"] = g["cost"][1]
                            g["redispatch_cost_down"] = g["cost"][1]
                        end
                    end
                    
                    result_feasibility_checks = _SPMTA.solve_acdc_full_redispatch_opf(feasibility_check,model,optimizer)
                    result_feasibility_checks["probability"] = stochastic_grid["nw"]["$timestep"]["probability"]
        else
                    result_feasibility_checks["$hour"] = Dict{String,Any}()
                    feasibility_check = deepcopy(grid)
                    feasibility_check_input = deepcopy(grid)

                    # Adding set points
                    for (g_id,g) in feasibility_check["gen"]
                        g["pg_start"] = results_fc["$day"]["$hour"]["solution"]["gen"][g_id]["pg"]
                        g["qg_start"] = results_fc["$day"]["$hour"]["solution"]["gen"][g_id]["qg"]
                        if g_id in gen_wind
                            g["redispatch_cost_up"] = 0.14
                            g["redispatch_cost_down"] = 0.14
                        else
                            g["redispatch_cost_up"] = g["cost"][1]
                            g["redispatch_cost_down"] = g["cost"][1]
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
################### Hourly bs ########################
save_redispatch_days(test_case_bs,bs_hourly_measured  ,feasibility_check_bs_hourly_measured,measured_wind  ,scenario_wind,one_scenario,14,"bs_hourly_measured"  ,bs_hourly_measured,feasibility_check_bs_hourly_measured)
save_redispatch_days(test_case_bs,bs_hourly_forecasted,feasibility_check_bs_hourly_forecasted,measured_wind,scenario_wind,one_scenario,14,"bs_hourly_forecasted",bs_hourly_measured,feasibility_check_bs_hourly_measured)
#save_redispatch_days(test_case_bs,bs_hourly_average   ,feasibility_check_bs_hourly_average,measured_wind   ,scenario_wind,one_scenario,n_days,"bs_hourly_average"   ,bs_hourly_measured,feasibility_check_bs_hourly_measured)


result_redispatch_bs_hourly_measured_check   = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_bs_hourly_measured_$(first_hour)_$(last_hour)_all_days.json"))
result_redispatch_bs_hourly_forecasted_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_bs_hourly_forecasted_$(first_hour)_$(last_hour)_all_days.json"))


################### One topology ########################
bs_one_topology_forecasted = JSON.parsefile(joinpath(results_folder,case,"One_topology_forecasted_$(first_hour)_$(last_hour)_all_days.json"))
feasibility_check_one_topology_forecasted  = JSON.parsefile(joinpath(results_folder,case,"fc_one_topology_forecasted_$(first_hour)_$(last_hour)_all_days.json")) 

bs_one_topology_measured = JSON.parsefile(joinpath(results_folder,case,"One_topology_measured_$(first_hour)_$(last_hour)_all_days.json"))
feasibility_check_one_topology_measured  = JSON.parsefile(joinpath(results_folder,case,"fc_one_topology_measured_$(first_hour)_$(last_hour)_all_days.json")) 


save_redispatch_days(test_case_bs,bs_one_topology_measured,feasibility_check_bs_one_topology_measured,measured_wind,scenario_wind,one_scenario,n_days,"One_topology_measured",bs_one_topology_measured,feasibility_check_bs_one_topology_measured)
save_redispatch_days(test_case_bs,bs_one_topology_forecasted,feasibility_check_bs_one_topology_forecasted,measured_wind,scenario_wind,one_scenario,n_days,"One_topology_forecasted",bs_one_topology_measured,feasibility_check_bs_one_topology_measured)

redispatch_results_one_topology_forecasted = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_one_topology_forecasted_$(first_hour)_$(last_hour)_all_days.json"))
redispatch_results_one_topology_measured = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_one_topology_measured_$(first_hour)_$(last_hour)_all_days.json"))


################### One switching action ########################
bs_one_maximum_actions_forecasted = JSON.parsefile(joinpath(results_folder,case,"One_maximum_actions_forecasted_$(first_hour)_$(last_hour)_all_days.json"))
feasibility_check_one_maximum_actions_forecasted  = JSON.parsefile(joinpath(results_folder,case,"fc_one_maximum_actions_forecasted_$(first_hour)_$(last_hour)_all_days.json")) 

bs_one_maximum_actions_measured = JSON.parsefile(joinpath(results_folder,case,"one_maximum_actions_measured_$(first_hour)_$(last_hour)_all_days.json"))
feasibility_check_one_maximum_actions_measured  = JSON.parsefile(joinpath(results_folder,case,"fc_one_maximum_actions_measured_$(first_hour)_$(last_hour)_all_days.json")) 

save_redispatch_days(test_case_bs,bs_one_maximum_actions_measured,feasibility_check_one_maximum_actions_measured,measured_wind,scenario_wind,one_scenario,n_days,"one_maximum_actions_measured",bs_one_maximum_actions_measured,feasibility_check_one_maximum_actions_measured)
save_redispatch_days(test_case_bs,bs_one_maximum_actions_forecasted,feasibility_check_one_maximum_actions_forecasted,measured_wind,scenario_wind,one_scenario,n_days,"one_maximum_actions_forecasted",bs_one_maximum_actions_measured,feasibility_check_one_maximum_actions_measured)

redispatch_results_one_maximum_actions_forecasted = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_one_maximum_actions_forecasted_$(first_hour)_$(last_hour)_all_days.json"))
redispatch_results_one_maximum_actions_measured = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_one_maximum_actions_measured_$(first_hour)_$(last_hour)_all_days.json"))

################### Two switching actisn ########################
bs_two_maximum_actions_forecasted = JSON.parsefile(joinpath(results_folder,case,"two_maximum_actions_forecasted_$(first_hour)_$(last_hour)_all_days.json"))
feasibility_check_two_maximum_actions_forecasted  = JSON.parsefile(joinpath(results_folder,case,"fc_two_maximum_actions_forecasted_$(first_hour)_$(last_hour)_all_days.json")) 

bs_two_maximum_actions_measured = deepcopy(bs_one_maximum_actions_measured)
feasibility_check_two_maximum_actions_measured  = deepcopy(feasibility_check_one_maximum_actions_measured)

save_redispatch_days(test_case_bs,bs_two_maximum_actions_measured,feasibility_check_two_maximum_actions_measured,measured_wind,scenario_wind,one_scenario,n_days,"two_maximum_actions_measured",bs_two_maximum_actions_measured,feasibility_check_two_maximum_actions_measured)
save_redispatch_days(test_case_bs,bs_two_maximum_actions_forecasted,feasibility_check_two_maximum_actions_forecasted,measured_wind,scenario_wind,one_scenario,n_days,"two_maximum_actions_forecasted",bs_two_maximum_actions_measured,feasibility_check_two_maximum_actions_measured)

redispatch_results_two_maximum_actions_forecasted = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_two_maximum_actions_forecasted_$(first_hour)_$(last_hour)_all_days.json"))
redispatch_results_two_maximum_actions_measured = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_two_maximum_actions_measured_$(first_hour)_$(last_hour)_all_days.json"))



###########################################################
######### Scenarios
n_scenarios = 8
################### Hourly optimization ########################
bs_hourly_scenarios = JSON.parsefile(joinpath(results_folder,case,"Hourly_bs_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_all_days.json"))
#bs_hourly_scenarios = Dict{String,Any}()
#bs_hourly_scenarios["1"] = Dict{String,Any}()
#bs_hourly_scenarios["1"] = deepcopy(bs_hourly_scenarios_beginning)

n_days = 14
feasibility_check_bs_hourly_scenarios  = JSON.parsefile(joinpath(results_folder,case,"fc_Hourly_bs_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_all_days.json")) 
save_redispatch_days(test_case_bs,bs_hourly_scenarios  ,feasibility_check_bs_hourly_scenarios,measured_wind  ,scenario_wind,n_scenarios,n_days,"Hourly_bs_stochastic",bs_hourly_measured,feasibility_check_bs_hourly_measured)

result_redispatch_hourly_bs_6_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_Hourly_bs_stochastic_Laplace_6_scenarios_$(first_hour)_$(last_hour)_all_days.json"))
result_redispatch_hourly_bs_8_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_Hourly_bs_stochastic_Laplace_8_scenarios_$(first_hour)_$(last_hour)_all_days.json"))


################### One topology ########################
one_topology_scenarios = JSON.parsefile(joinpath(results_folder,case,"One_topology_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_all_days.json"))

n_days = 14
feasibility_check_one_topology_scenarios  = JSON.parsefile(joinpath(results_folder,case,"fc_One_topology_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_all_days.json")) 
save_redispatch_days(test_case_bs,one_topology_scenarios  ,feasibility_check_one_topology_scenarios,measured_wind  ,scenario_wind,n_scenarios,n_days,"One_topology_stochastic",bs_hourly_measured,feasibility_check_bs_hourly_measured)

result_redispatch_one_topology_6_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_one_topology_stochastic_Laplace_6_scenarios_$(first_hour)_$(last_hour)_all_days.json"))
result_redispatch_one_topology_8_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_one_topology_stochastic_Laplace_8_scenarios_$(first_hour)_$(last_hour)_all_days.json"))


################### One switching action ########################
one_sw_scenarios = JSON.parsefile(joinpath(results_folder,case,"One_maximum_actions_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_all_days.json"))

n_days = 14
feasibility_check_one_switching_action_scenarios  = JSON.parsefile(joinpath(results_folder,case,"fc_One_maximum_actions_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_all_days.json")) 
save_redispatch_days(test_case_bs,one_sw_scenarios  ,feasibility_check_one_switching_action_scenarios,measured_wind  ,scenario_wind,n_scenarios,n_days,"One_maximum_action_stochastic",bs_hourly_measured,feasibility_check_bs_hourly_measured)

result_redispatch_one_switching_action_6_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_one_switching_action_stochastic_Laplace_6_scenarios_$(first_hour)_$(last_hour)_all_days.json"))
result_redispatch_one_switching_action_8_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_one_switching_action_stochastic_Laplace_8_scenarios_$(first_hour)_$(last_hour)_all_days.json"))

################### Two switching actions ########################
two_sw_scenarios = JSON.parsefile(joinpath(results_folder,case,"Two_maximum_actions_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_all_days.json"))

feasibility_check_two_switching_action_scenarios  = JSON.parsefile(joinpath(results_folder,case,"fc_Two_maximum_actions_stochastic_Laplace_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_all_days.json")) 
save_redispatch_days(test_case_bs,two_sw_scenarios  ,feasibility_check_two_switching_action_scenarios,measured_wind  ,scenario_wind,n_scenarios,n_days,"Two_maximum_actions_stochastic",bs_hourly_measured,feasibility_check_bs_hourly_measured)

result_redispatch_hourly_bs_6_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_two_switching_actions_stochastic_Laplace_6_scenarios_$(first_hour)_$(last_hour)_all_days.json"))
result_redispatch_hourly_bs_8_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_two_switching_actions_stochastic_Laplace_8_scenarios_$(first_hour)_$(last_hour)_all_days.json"))



#####################################################


##########################################################################################
### Uploading results
## Feasibility checks
scenario_wind_6 = JSON.parsefile(joinpath(input_folder,"case30","Laplace_6_scenarios_$(first_hour)_$(last_hour).json"))
scenario_wind_8 = JSON.parsefile(joinpath(input_folder,"case30","Laplace_8_scenarios_$(first_hour)_$(last_hour).json"))

opf_6_scenarios = JSON.parsefile(joinpath(results_folder,case,"Hourly_opf_stochastic_Laplace_6_scenarios_$(first_hour)_$(last_hour).json"))
opf_8_scenarios = JSON.parsefile(joinpath(results_folder,case,"Hourly_opf_stochastic_Laplace_8_scenarios_$(first_hour)_$(last_hour).json"))

result_fc_hourly_bs_6_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"fc_Hourly_bs_stochastic_Laplace_6_scenarios_$(first_hour)_$(last_hour)_all_days.json"))
result_fc_hourly_bs_8_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"fc_Hourly_bs_stochastic_Laplace_8_scenarios_$(first_hour)_$(last_hour)_all_days.json"))

result_fc_one_topology_6_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"fc_One_topology_stochastic_Laplace_6_scenarios_$(first_hour)_$(last_hour)_all_days.json"))
result_fc_one_topology_8_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"fc_One_topology_stochastic_Laplace_8_scenarios_$(first_hour)_$(last_hour)_all_days.json"))

result_fc_one_sw_6_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"fc_One_maximum_actions_stochastic_Laplace_6_scenarios_$(first_hour)_$(last_hour)_all_days.json"))
result_fc_one_sw_8_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"fc_One_maximum_actions_stochastic_Laplace_8_scenarios_$(first_hour)_$(last_hour)_all_days.json"))

result_fc_two_sw_6_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"fc_Two_maximum_actions_stochastic_Laplace_6_scenarios_$(first_hour)_$(last_hour)_all_days.json"))
result_fc_two_sw_8_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"fc_Two_maximum_actions_stochastic_Laplace_8_scenarios_$(first_hour)_$(last_hour)_all_days.json"))


## Redispatch
result_redispatch_hourly_bs_6_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_Hourly_bs_stochastic_Laplace_6_scenarios_$(first_hour)_$(last_hour)_all_days.json"))
result_redispatch_hourly_bs_8_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_Hourly_bs_stochastic_Laplace_8_scenarios_$(first_hour)_$(last_hour)_all_days.json"))

result_redispatch_one_topology_6_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_One_topology_stochastic_Laplace_6_scenarios_$(first_hour)_$(last_hour)_all_days.json"))
result_redispatch_one_topology_8_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_One_topology_stochastic_Laplace_8_scenarios_$(first_hour)_$(last_hour)_all_days.json"))

result_redispatch_one_sw_6_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_One_maximum_action_stochastic_Laplace_6_scenarios_$(first_hour)_$(last_hour)_all_days.json"))
result_redispatch_one_sw_8_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_One_maximum_action_stochastic_Laplace_8_scenarios_$(first_hour)_$(last_hour)_all_days.json"))

result_redispatch_two_sw_6_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_Two_maximum_actions_stochastic_Laplace_6_scenarios_$(first_hour)_$(last_hour)_all_days.json"))
result_redispatch_two_sw_8_scenarios_check = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_Two_maximum_actions_stochastic_Laplace_8_scenarios_$(first_hour)_$(last_hour)_all_days.json"))


##### OPF
result_redispatch_opf_6 = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_OPF_Laplace_6_scenarios_$(first_hour)_$(last_hour).json"))
#result_redispatch_opf_8 = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_OPF_Laplace_8_scenarios_$(first_hour)_$(last_hour).json"))



###################
#=
redispatch_opf_6 = Dict{String,Any}()
redispatch_scenarios_opf(redispatch_opf_6,opf_6_scenarios,scenario_wind,6,n_hours,hourly_opf_measured)


json_redispatch_opf_results = JSON.json(redispatch_opf_6)
 open(joinpath(results_folder,case,"redispatch_results_OPF_Laplace_6_scenarios_$(first_hour)_$(last_hour).json"),"w") do f 
     write(f, json_redispatch_opf_results) 
end 
=#


redispatch_opf_8 = Dict{String,Any}()
redispatch_scenarios_opf(redispatch_opf_8,opf_8_scenarios,scenario_wind_8,8,n_hours,hourly_opf_measured)


json_redispatch_opf_results = JSON.json(redispatch_opf_8)
 open(joinpath(results_folder,case,"redispatch_results_OPF_Laplace_8_scenarios_$(first_hour)_$(last_hour).json"),"w") do f 
     write(f, json_redispatch_opf_results) 
end 



#redispatch_opf_average = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_OPF_forecasted_$(first_hour)_$(last_hour).json"))
redispatch_opf_forecasted = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_OPF_forecasted_$(first_hour)_$(last_hour).json"))
result_redispatch_opf_6 = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_OPF_Laplace_6_scenarios_$(first_hour)_$(last_hour).json"))
result_redispatch_opf_8 = JSON.parsefile(joinpath(results_folder,case,"redispatch_results_OPF_Laplace_8_scenarios_$(first_hour)_$(last_hour).json"))

sum(result_redispatch_opf_6["$hour"]["objective"] for hour in 1:n_hours*6)

#########################################################################################
### Computing the full sum
total_costs_opf_measured = sum(hourly_opf_measured["$hour"]["objective"] for hour in 1:n_hours)
total_costs_hourly_bs_measured = sum(feasibility_check_bs_hourly_measured["$day"]["$hour"]["objective"] for day in 1:n_days, hour in 1:n_hours_per_day)
total_costs_one_topology_measured = sum((feasibility_check_one_topology_measured["$day"]["$hour"]["objective"]) for day in 1:n_days, hour in 1:n_hours_per_day)
total_costs_one_sw_measured = sum((feasibility_check_one_maximum_actions_measured["$day"]["$hour"]["objective"]) for day in 1:n_days, hour in 1:n_hours_per_day)
total_costs_two_sw_measured = sum((feasibility_check_one_maximum_actions_measured["$day"]["$hour"]["objective"]) for day in 1:n_days, hour in 1:n_hours_per_day)


total_costs_opf_forecasted = sum(hourly_opf_forecasted["$hour"]["objective"] for hour in 1:n_hours)             + sum(redispatch_opf_forecasted["$hour"]["objective"] for hour in 1:n_hours)
total_costs_hourly_bs_forecasted = sum((feasibility_check_bs_hourly_forecasted["$day"]["$hour"]["objective"]        + result_redispatch_bs_hourly_forecasted_check["$day"]["$hour"]["objective"]) for day in 1:n_days, hour in 1:n_hours_per_day)
total_costs_one_topology_forecasted = sum((feasibility_check_one_topology_forecasted["$day"]["$hour"]["objective"]  + redispatch_results_one_topology_forecasted["$day"]["$hour"]["objective"]) for day in 1:n_days, hour in 1:n_hours_per_day)
total_costs_one_sw_forecasted = sum((feasibility_check_one_maximum_actions_forecasted["$day"]["$hour"]["objective"] + redispatch_results_one_maximum_actions_forecasted["$day"]["$hour"]["objective"]) for day in 1:n_days, hour in 1:n_hours_per_day)
total_costs_two_sw_forecasted = sum((feasibility_check_two_maximum_actions_forecasted["$day"]["$hour"]["objective"] + redispatch_results_two_maximum_actions_forecasted["$day"]["$hour"]["objective"]) for day in 1:n_days, hour in 1:n_hours_per_day)


term_status = []
term_status_redispatch = []
opf_cost_timestep = []
opf_costs = 0
redispatch_costs = 0
for day in 1:14
    for hour in 1:n_hours_per_day
        for scenario in 1:6
            timestep = (day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario
            push!(term_status,opf_6_scenarios["$timestep"]["termination_status"])
            opf_costs += opf_6_scenarios["$timestep"]["objective"]*scenario_wind["$timestep"]["probability"]
            push!(opf_cost_timestep,opf_6_scenarios["$timestep"]["objective"]*scenario_wind["$timestep"]["probability"])
            if result_redispatch_opf_6["$timestep"]["termination_status"] == "LOCALLY_SOLVED"
                push!(term_status_redispatch,result_redispatch_opf_6["$timestep"]["termination_status"])
                redispatch_costs += result_redispatch_opf_6["$timestep"]["objective"]*scenario_wind["$timestep"]["probability"]
            end
        end
    end
end
obj_forecasted = [hourly_opf_forecasted["$hour"]["objective"] for hour in 1:n_hours]
obj_measured = [hourly_opf_measured["$hour"]["objective"] for hour in 1:n_hours]
opf_stochastic = []
for hour in 1:n_hours
    hourly_opf_stochastic = 0
    for s in 1:n_scenarios
        hourly_opf_stochastic += opf_6_scenarios["$((hour - 1)*6 + s)"]["objective"]*scenario_wind["$((hour - 1)*6 + s)"]["probability"]
    end
    push!(opf_stochastic,hourly_opf_stochastic)
end


scatter(obj_forecasted)
scatter!(obj_measured)
scatter!(opf_stochastic)


#################################### 6 scenarios #################################

function redispatch_costs_scenarios(result_dict,redispatch_opf_solved,redispatch_opf_infeasible,infeasible_scenarios,feasible_scenarios,feasible,infeasible,n_scenarios)
    if length(result_dict["1"]) == n_hours_per_day
        println("Redispatch results $(n_hours_per_day)")
        for day in 1:n_days 
            for hour in 1:n_hours_per_day
                for scenario in 1:n_scenarios
                    timestep = ((day - 1)*n_hours_per_day*n_scenarios + (hour - 1)*n_scenarios + scenario)
                    if result_dict["$day"]["$hour"]["$scenario"]["termination_status"] == "LOCALLY_SOLVED"
                        push!(redispatch_opf_solved, result_dict["$day"]["$hour"]["$scenario"]["objective"])
                        #push!(redispatch_opf_6_infeasible, 0.0)
                        feasible += 1
                        push!(feasible_scenarios,timestep)
                    else
                        #push!(redispatch_opf_6_solved, 0.0)
                        push!(redispatch_opf_infeasible, result_dict["$day"]["$hour"]["$scenario"]["objective"])
                        infeasible += 1
                        push!(infeasible_scenarios, timestep)
                    end
                end
            end
        end

    elseif length(result_dict) == n_hours_per_day*n_scenarios*n_days
        println("Redispatch results $(n_hours_per_day*n_scenarios*n_days)")
        for day in 1:n_days 
            for hour in 1:n_hours_per_day
                for scenario in 1:n_scenarios
                    timestep = ((day - 1)*n_hours_per_day*n_scenarios + (hour - 1)*n_scenarios + scenario)
                    if result_dict["$timestep"]["termination_status"] == "LOCALLY_SOLVED"
                        push!(redispatch_opf_solved, result_dict["$timestep"]["objective"])
                        #push!(redispatch_opf_6_infeasible, 0.0)
                        feasible += 1
                        push!(feasible_scenarios,timestep)
                    else
                        #push!(redispatch_opf_6_solved, 0.0)
                        push!(redispatch_opf_infeasible, result_dict["$timestep"]["objective"])
                        infeasible += 1
                        push!(infeasible_scenarios, timestep)
                    end
                end
            end
        end
    end
    return feasible, infeasible
end


###### OPF ######
all_redispatch_opf = sum(result_redispatch_opf_6["$timestep"]["objective"]*scenario_wind["$timestep"]["probability"] for timestep in 1:(n_days*n_hours_per_day*6))
total_costs_opf_6_scenarios = sum((opf_6_scenarios["$((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)"]["objective"]*scenario_wind["$((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)"]["probability"]) for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:6) + all_redispatch_opf


redispatch_opf_8_solved = []
redispatch_opf_8_infeasible = []
infeasible_scenarios = []
feasible_scenarios = []
feasible = 0
infeasible = 0

redispatch_costs_scenarios(result_redispatch_hourly_bs_8_scenarios_check,redispatch_opf_8_solved,redispatch_opf_8_infeasible,infeasible_scenarios,feasible_scenarios,feasible,infeasible,8)


feasible_redispatch_opf_8 = 0
fix_infeasibility_opf_8 = 0
for day in 1:n_days
    for hour in 1:n_hours_per_day
        for scenario in 1:8
            timestep = ((day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario)
            if timestep in feasible_scenarios
                feasible_redispatch_opf_8 += result_redispatch_hourly_bs_8_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]*scenario_wind_8["$timestep"]["probability"]
            end
            if timestep in infeasible_scenarios
                fix_infeasibility_opf_8 += mean(redispatch_opf_8_solved)*scenario_wind_8["$timestep"]["probability"]
            end
        end 
    end
end
total_costs_opf_8_scenarios = sum((opf_8_scenarios["$((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)"]["objective"]*scenario_wind_8["$((day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario)"]["probability"]) for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:8) + feasible_redispatch_opf_8 + fix_infeasibility_opf_8



##### Hourly BS ######
redispatch_hbs_solved = []
redispatch_hbs_infeasible = []
infeasible_scenarios = []
feasible_scenarios = []
feasible = 0
infeasible = 0

redispatch_costs_scenarios(result_redispatch_hourly_bs_6_scenarios_check,redispatch_hbs_solved,redispatch_hbs_infeasible,infeasible_scenarios,feasible_scenarios,feasible,infeasible,6)
sum(redispatch_hbs_solved)
sum(redispatch_hbs_infeasible)


feasible_redispatch_hbs = 0
fix_infeasibility_hbs = 0
for day in 1:n_days
    for hour in 1:n_hours_per_day
        for scenario in 1:6
            timestep = ((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)
            if timestep in feasible_scenarios
                feasible_redispatch_hbs += result_redispatch_hourly_bs_6_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]*scenario_wind["$timestep"]["probability"]
            end
            if timestep in infeasible_scenarios
                fix_infeasibility_hbs += mean(redispatch_hbs_solved)*scenario_wind["$timestep"]["probability"]
            end
        end 
    end
end

all_redispatch_hbs = 0
for day in 1:n_days
    for hour in 1:n_hours_per_day
        for scenario in 1:6
            timestep = ((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)
            all_redispatch_hbs += result_redispatch_hourly_bs_6_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]*scenario_wind["$timestep"]["probability"]
        end
    end
end

all_redispatch_hbs = feasible_redispatch_hbs + fix_infeasibility_hbs

total_costs_hourly_bs_6_scenarios = sum((result_fc_hourly_bs_6_scenarios_check["$day"]["$hour"]["$scenario"]["objective"])*scenario_wind_6["$((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:6) + all_redispatch_hbs
total_redispatch_hbs_6_scenarios = feasible_redispatch_hbs + fix_infeasibility_hbs



##### One topology ######
redispatch_one_topology_solved = []
redispatch_one_topology_infeasible = []
infeasible_scenarios = []
feasible_scenarios = []
feasible = 0
infeasible = 0

redispatch_costs_scenarios(result_redispatch_one_topology_6_scenarios_check,redispatch_one_topology_solved,redispatch_one_topology_infeasible,infeasible_scenarios,feasible_scenarios,feasible,infeasible,6)
sum(redispatch_one_topology_solved)
sum(redispatch_one_topology_infeasible)


feasible_redispatch_one_topology = 0
fix_infeasibility_one_topology = 0
for day in 1:n_days
    for hour in 1:n_hours_per_day
        for scenario in 1:6
            timestep = ((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)
            if timestep in feasible_scenarios
                feasible_redispatch_one_topology += result_redispatch_one_topology_6_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]*scenario_wind["$timestep"]["probability"]
            end
            if timestep in infeasible_scenarios
                fix_infeasibility_one_topology += mean(redispatch_one_topology_solved)*scenario_wind["$timestep"]["probability"]
            end
        end 
    end
end

all_redispatch_one_topology = 0
for day in 1:n_days
    for hour in 1:n_hours_per_day
        for scenario in 1:6
            timestep = ((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)
            all_redispatch_one_topology += result_redispatch_one_topology_6_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]*scenario_wind["$timestep"]["probability"]
        end
    end
end

all_redispatch_one_topology = feasible_redispatch_one_topology + fix_infeasibility_one_topology

total_costs_one_topology_6_scenarios = sum((result_fc_one_topology_6_scenarios_check["$day"]["$hour"]["$scenario"]["objective"])*scenario_wind_6["$((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:6) + all_redispatch_one_topology

total_redispatch_one_topology_6_scenarios = feasible_redispatch_one_topology + fix_infeasibility_one_topology


##### One maximum action ######
redispatch_one_maximum_action_solved = []
redispatch_one_maximum_action_infeasible = []
infeasible_scenarios = []
feasible_scenarios = []
feasible = 0
infeasible = 0

redispatch_costs_scenarios(result_redispatch_one_sw_6_scenarios_check,redispatch_one_maximum_action_solved,redispatch_one_maximum_action_infeasible,infeasible_scenarios,feasible_scenarios,feasible,infeasible,6)
sum(redispatch_one_maximum_action_solved)
sum(redispatch_one_maximum_action_infeasible)


feasible_redispatch_one_maximum_action = 0
fix_infeasibility_one_maximum_action = 0
for day in 1:n_days
    for hour in 1:n_hours_per_day
        for scenario in 1:6
            timestep = ((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)
            if timestep in feasible_scenarios
                feasible_redispatch_one_maximum_action += result_redispatch_one_sw_6_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]*scenario_wind["$timestep"]["probability"]
            end
            if timestep in infeasible_scenarios
                fix_infeasibility_one_maximum_action += mean(redispatch_one_maximum_action_solved)*scenario_wind["$timestep"]["probability"]
            end
        end 
    end
end

all_redispatch_one_maximum_action = 0
for day in 1:n_days
    for hour in 1:n_hours_per_day
        for scenario in 1:6
            timestep = ((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)
            all_redispatch_one_maximum_action += result_redispatch_one_sw_6_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]*scenario_wind["$timestep"]["probability"]
        end
    end
end

all_redispatch_one_maximum_action = feasible_redispatch_one_maximum_action + fix_infeasibility_one_maximum_action

total_costs_one_maximum_action_6_scenarios = sum((result_fc_one_sw_6_scenarios_check["$day"]["$hour"]["$scenario"]["objective"])*scenario_wind_6["$((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:6) + all_redispatch_one_maximum_action

total_redispatch_one_maximum_action_6_scenarios = feasible_redispatch_one_maximum_action + fix_infeasibility_one_maximum_action

##### Two maximum actions ######
redispatch_two_maximum_actions_solved = []
redispatch_two_maximum_actions_infeasible = []
infeasible_scenarios = []
feasible_scenarios = []
feasible = 0
infeasible = 0

redispatch_costs_scenarios(result_redispatch_two_sw_6_scenarios_check,redispatch_two_maximum_actions_solved,redispatch_two_maximum_actions_infeasible,infeasible_scenarios,feasible_scenarios,feasible,infeasible,6)
sum(redispatch_two_maximum_actions_solved)
sum(redispatch_two_maximum_actions_infeasible)


feasible_redispatch_two_maximum_actions = 0
fix_infeasibility_two_maximum_actions = 0
for day in 1:n_days
    for hour in 1:n_hours_per_day
        for scenario in 1:6
            timestep = ((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)
            if timestep in feasible_scenarios
                feasible_redispatch_two_maximum_actions += result_redispatch_two_sw_6_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]*scenario_wind["$timestep"]["probability"]
            end
            if timestep in infeasible_scenarios
                fix_infeasibility_two_maximum_actions += mean(redispatch_two_maximum_actions_solved)*scenario_wind["$timestep"]["probability"]
            end
        end 
    end
end

all_redispatch_two_maximum_actions = 0
for day in 1:n_days
    for hour in 1:n_hours_per_day
        for scenario in 1:6
            timestep = ((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)
            all_redispatch_two_maximum_actions += result_redispatch_two_sw_6_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]*scenario_wind["$timestep"]["probability"]
        end
    end
end

all_redispatch_two_maximum_actions = feasible_redispatch_two_maximum_actions + fix_infeasibility_two_maximum_actions

total_costs_two_maximum_actions_6_scenarios = sum((result_fc_one_sw_6_scenarios_check["$day"]["$hour"]["$scenario"]["objective"])*scenario_wind_6["$((day - 1)*n_hours_per_day*6 + (hour - 1)*6 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:6) + all_redispatch_two_maximum_actions

total_redispatch_two_maximum_actions_6_scenarios = feasible_redispatch_two_maximum_actions + fix_infeasibility_two_maximum_actions



#### 8 scenarios

redispatch_hbs_8_solved = []
redispatch_hbs_8_infeasible = []
infeasible_scenarios = []
feasible_scenarios = []
feasible = 0
infeasible = 0

redispatch_costs_scenarios(result_redispatch_hourly_bs_8_scenarios_check,redispatch_hbs_8_solved,redispatch_hbs_8_infeasible,infeasible_scenarios,feasible_scenarios,feasible,infeasible,8)
sum(redispatch_hbs_8_solved)
sum(redispatch_hbs_8_infeasible)


feasible_redispatch_hbs_8 = 0
fix_infeasibility_hbs_8 = 0
for day in 1:n_days
    for hour in 1:n_hours_per_day
        for scenario in 1:8
            timestep = ((day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario)
            if timestep in feasible_scenarios
                feasible_redispatch_hbs_8 += result_redispatch_hourly_bs_8_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]*scenario_wind_8["$timestep"]["probability"]
            end
            if timestep in infeasible_scenarios
                fix_infeasibility_hbs_8 += mean(redispatch_hbs_8_solved)*scenario_wind_8["$timestep"]["probability"]
            end
        end 
    end
end

all_redispatch_hbs_8 = 0
for day in 1:n_days
    for hour in 1:n_hours_per_day
        for scenario in 1:8
            timestep = ((day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario)
            all_redispatch_hbs_8 += result_redispatch_hourly_bs_8_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]*scenario_wind_8["$timestep"]["probability"]
        end
    end
end

all_redispatch_hbs_8 = feasible_redispatch_hbs_8 + fix_infeasibility_hbs_8

total_costs_hourly_bs_8_scenarios = sum((result_fc_hourly_bs_8_scenarios_check["$day"]["$hour"]["$scenario"]["objective"])*scenario_wind_8["$((day - 1)*n_hours_per_day*n_scenarios + (hour - 1)*n_scenarios + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:n_scenarios) + all_redispatch_hbs_8



##### One topology ######
redispatch_one_topology_solved = []
redispatch_one_topology_infeasible = []
infeasible_scenarios = []
feasible_scenarios = []
feasible = 0
infeasible = 0

redispatch_costs_scenarios(result_redispatch_one_topology_8_scenarios_check,redispatch_one_topology_solved,redispatch_one_topology_infeasible,infeasible_scenarios,feasible_scenarios,feasible,infeasible,8)
sum(redispatch_one_topology_solved)
sum(redispatch_one_topology_infeasible)


feasible_redispatch_one_topology = 0
fix_infeasibility_one_topology = 0
for day in 1:n_days
    for hour in 1:n_hours_per_day
        for scenario in 1:8
            timestep = ((day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario)
            if timestep in feasible_scenarios
                feasible_redispatch_one_topology += result_redispatch_one_topology_8_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]*scenario_wind_8["$timestep"]["probability"]
            end
            if timestep in infeasible_scenarios
                fix_infeasibility_one_topology += mean(redispatch_one_topology_solved)*scenario_wind_8["$timestep"]["probability"]
            end
        end 
    end
end

all_redispatch_one_topology = 0
for day in 1:n_days
    for hour in 1:n_hours_per_day
        for scenario in 1:8
            timestep = ((day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario)
            all_redispatch_one_topology += result_redispatch_one_topology_8_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]*scenario_wind_8["$timestep"]["probability"]
        end
    end
end

all_redispatch_one_topology = feasible_redispatch_one_topology + fix_infeasibility_one_topology

total_costs_one_topology_8_scenarios = sum((result_fc_one_topology_8_scenarios_check["$day"]["$hour"]["$scenario"]["objective"])*scenario_wind_8["$((day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:8) + all_redispatch_one_topology

total_redispatch_one_topology_8_scenarios = feasible_redispatch_one_topology + fix_infeasibility_one_topology


##### One maximum action ######
redispatch_one_maximum_action_solved = []
redispatch_one_maximum_action_infeasible = []
infeasible_scenarios = []
feasible_scenarios = []
feasible = 0
infeasible = 0

redispatch_costs_scenarios(result_redispatch_one_sw_8_scenarios_check,redispatch_one_maximum_action_solved,redispatch_one_maximum_action_infeasible,infeasible_scenarios,feasible_scenarios,feasible,infeasible,8)
sum(redispatch_one_maximum_action_solved)
sum(redispatch_one_maximum_action_infeasible)


feasible_redispatch_one_maximum_action = 0
fix_infeasibility_one_maximum_action = 0
for day in 1:n_days
    for hour in 1:n_hours_per_day
        for scenario in 1:8
            timestep = ((day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario)
            if timestep in feasible_scenarios
                feasible_redispatch_one_maximum_action += result_redispatch_one_sw_8_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]*scenario_wind_8["$timestep"]["probability"]
            end
            if timestep in infeasible_scenarios
                fix_infeasibility_one_maximum_action += mean(redispatch_one_maximum_action_solved)*scenario_wind_8["$timestep"]["probability"]
            end
        end 
    end
end

all_redispatch_one_maximum_action = 0
for day in 1:n_days
    for hour in 1:n_hours_per_day
        for scenario in 1:8
            timestep = ((day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario)
            all_redispatch_one_maximum_action += result_redispatch_one_sw_8_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]*scenario_wind_8["$timestep"]["probability"]
        end
    end
end

all_redispatch_one_maximum_action = feasible_redispatch_one_maximum_action + fix_infeasibility_one_maximum_action

total_costs_one_maximum_action_8_scenarios = sum((result_fc_one_sw_8_scenarios_check["$day"]["$hour"]["$scenario"]["objective"])*scenario_wind_8["$((day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:8) + all_redispatch_one_maximum_action

total_redispatch_one_maximum_action_8_scenarios = feasible_redispatch_one_maximum_action + fix_infeasibility_one_maximum_action

##### Two maximum actions ######
redispatch_two_maximum_actions_solved = []
redispatch_two_maximum_actions_infeasible = []
infeasible_scenarios = []
feasible_scenarios = []
feasible = 0
infeasible = 0

redispatch_costs_scenarios(result_redispatch_two_sw_8_scenarios_check,redispatch_two_maximum_actions_solved,redispatch_two_maximum_actions_infeasible,infeasible_scenarios,feasible_scenarios,feasible,infeasible,8)
sum(redispatch_two_maximum_actions_solved)
sum(redispatch_two_maximum_actions_infeasible)


feasible_redispatch_two_maximum_actions = 0
fix_infeasibility_two_maximum_actions = 0
for day in 1:n_days
    for hour in 1:n_hours_per_day
        for scenario in 1:8
            timestep = ((day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario)
            if timestep in feasible_scenarios
                feasible_redispatch_two_maximum_actions += result_redispatch_two_sw_8_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]*scenario_wind_8["$timestep"]["probability"]
            end
            if timestep in infeasible_scenarios
                fix_infeasibility_two_maximum_actions += mean(redispatch_two_maximum_actions_solved)*scenario_wind_8["$timestep"]["probability"]
            end
        end 
    end
end

all_redispatch_two_maximum_actions = 0
for day in 1:n_days
    for hour in 1:n_hours_per_day
        for scenario in 1:8
            timestep = ((day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario)
            all_redispatch_two_maximum_actions += result_redispatch_two_sw_8_scenarios_check["$day"]["$hour"]["$scenario"]["objective"]*scenario_wind["$timestep"]["probability"]
        end
    end
end

all_redispatch_two_maximum_actions = feasible_redispatch_two_maximum_actions + fix_infeasibility_two_maximum_actions

total_costs_two_maximum_actions_8_scenarios = sum((result_fc_one_sw_8_scenarios_check["$day"]["$hour"]["$scenario"]["objective"])*scenario_wind_8["$((day - 1)*n_hours_per_day*8 + (hour - 1)*8 + scenario)"]["probability"] for day in 1:n_days, hour in 1:n_hours_per_day, scenario in 1:8) + all_redispatch_two_maximum_actions

total_redispatch_two_maximum_actions_8_scenarios = feasible_redispatch_two_maximum_actions + fix_infeasibility_two_maximum_actions



