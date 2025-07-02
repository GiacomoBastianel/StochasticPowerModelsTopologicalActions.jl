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


first_hour = 355
last_hour  = 378
n_hours = 24

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
scenario_wind = Dict{String,Any}()
scenarios = collect(4:2:8)
full_scenarios = collect(4:2:12)

#########################################################################################
## Processing input data
for i in scenarios
    scenario_wind["$i"] = JSON.parsefile(joinpath(input_folder,"case30","Laplace_$(i)_scenarios_$(first_hour)_$(last_hour).json"))
end

for i in full_scenarios
    scenario_wind["$i"] = JSON.parsefile(joinpath(input_folder,"case30","Laplace_$(i)_scenarios_$(first_hour)_$(last_hour).json"))
end

hourly_optimization  = JSON.parsefile(joinpath(results_folder,case,"Hourly_bs_Laplace_scenarios_$(first_hour)_$(last_hour).json"))  
one_topology         = JSON.parsefile(joinpath(results_folder,case,"One_topology_Laplace_scenarios_$(first_hour)_$(last_hour).json")) 
one_switching_action = JSON.parsefile(joinpath(results_folder,case,"One_sw_Laplace_scenarios_$(first_hour)_$(last_hour).json"))  
two_switching_action = JSON.parsefile(joinpath(results_folder,case,"Two_sw_Laplace_scenarios_$(first_hour)_$(last_hour).json"))  

hourly_opf                     = JSON.parsefile(joinpath(results_folder,case,"Hourly_OPF_Laplace_scenarios_$(first_hour)_$(last_hour).json")) 
feasibility_check_hourly       = JSON.parsefile(joinpath(results_folder,case,"fc_hourly_bs_Laplace_scenarios_$(first_hour)_$(last_hour).json")) 
feasibility_check_one_topology = JSON.parsefile(joinpath(results_folder,case,"fc_one_topology_Laplace_scenarios_$(first_hour)_$(last_hour).json")) 
feasibility_check_one_sw       = JSON.parsefile(joinpath(results_folder,case,"fc_one_sw_Laplace_scenarios_$(first_hour)_$(last_hour).json")) 
feasibility_check_two_sw       = JSON.parsefile(joinpath(results_folder,case,"fc_two_sw_Laplace_scenarios_$(first_hour)_$(last_hour).json"))



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

function redispatch_scenarios_opf(result_dict,result_opf,realized_time_series)
    for i in scenarios
        result_dict["$i"] = Dict{String,Any}()
        test_case_opf_replicate = _PM.replicate(test_case_opf, n_hours*i)
        test_case_opf_mn_scenarios = deepcopy(test_case_opf_replicate)    
        test_case_opf_mn_realized = deepcopy(test_case_opf_replicate)    
    
        _SPMTA.adding_multinetwork_scenarios(test_case_opf_mn_scenarios,n_hours,i,scenario_wind["$i"])
        _SPMTA.adding_multinetwork_scenarios(test_case_opf_mn_realized,n_hours,i,scenario_wind["$i"])
    
        for hour in 1:n_hours
            for s in 1:i
                timestep = (hour - 1)*i + s
                test_case_opf_mn_scenarios["nw"]["$timestep"]["gen"]["1"]["pmax"]   = deepcopy(test_case_opf_mn_scenarios["nw"]["$timestep"]["gen"]["1"]["pmax"]*scenario_wind["$i"]["$timestep"]["samples_pu"])
                test_case_opf_mn_realized["nw"]["$timestep"]["gen"]["1"]["pmax"]   = deepcopy(test_case_opf_mn_realized["nw"]["$timestep"]["gen"]["1"]["pmax"]*realized_time_series[hour])
            end
        end
    
        run_hourly_redispatch_opf_stochastic_scenarios(result_dict["$i"],test_case_opf_mn_realized,test_case_opf_mn_scenarios,result_opf["$i"],ACPPowerModel,ipopt,s,i)
    end
end


redispatch_opf          = Dict{String,Any}()
redispatch_hourly       = Dict{String,Any}()
redispatch_one_topology = Dict{String,Any}()
redispatch_one_sw       = Dict{String,Any}()
redispatch_two_sw       = Dict{String,Any}()

redispatch_scenarios_opf(redispatch_opf,hourly_opf,measured_wind)
redispatch_scenarios(redispatch_hourly,hourly_optimization,feasibility_check_hourly,measured_wind)
redispatch_scenarios(redispatch_one_topology,one_topology,feasibility_check_one_topology,measured_wind)
redispatch_scenarios(redispatch_one_sw,one_switching_action,feasibility_check_one_sw,measured_wind)
redispatch_scenarios(redispatch_two_sw,two_switching_action,feasibility_check_two_sw,measured_wind)

function run_hourly_redispatch_opf_stochastic_scenarios(result_dict, grid, stochastic_grid, result_opf, model, optimizer,settings,i)
    for hour in 1:n_hours
        for s in 1:i
            # This has to include all the scenarios
            timestep = (hour - 1)*i + s
            result_dict["$timestep"] = Dict{String,Any}()
            feasibility_check = deepcopy(grid["nw"]["$timestep"])
            feasibility_check_input = deepcopy(grid["nw"]["$timestep"])
            # Adding set points
            for (g_id,g) in feasibility_check["gen"]
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
            result_dict["$timestep"] = _SPMTA.solve_acdc_full_redispatch_opf(feasibility_check,model,optimizer)
            result_dict["$timestep"]["probability"] = stochastic_grid["nw"]["$timestep"]["probability"]
        end
    end    
end


for i in scenarios
    println("Scenario $i")
    println("AC-OPF: ", sum(redispatch_opf["$i"]["$hour"]["objective"]*feasibility_check_hourly["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)))
    println("Feasibility check hourly: ",                sum(redispatch_hourly["$i"]["$hour"]["objective"]*feasibility_check_hourly["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)))             
    println("Feasibility check one topology: ",          sum(redispatch_one_topology["$i"]["$hour"]["objective"]*feasibility_checks_one_topology["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)))
    println("Feasibility check one switching action: ",  sum(redispatch_one_sw["$i"]["$hour"]["objective"]*feasibility_checks_one_sw["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)))            
    println("Feasibility check two switching actions: ", sum(redispatch_two_sw["$i"]["$hour"]["objective"]*feasibility_checks_two_sw["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)))            
    println("--------------")
end

for i in scenarios
    println("Scenario $i")
    println("AC-OPF: ", sum(hourly_opf["$i"]["$hour"]["objective"]*feasibility_check_hourly["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)) + sum(redispatch_opf["$i"]["$hour"]["objective"]*feasibility_check_hourly["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)))
    println("Feasibility check hourly: ", sum(feasibility_check_hourly["$i"]["$hour"]["objective"]*feasibility_check_hourly["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i))                     .+ sum(redispatch_hourly["$i"]["$hour"]["objective"]*feasibility_check_hourly["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)))            
    println("Feasibility check one topology: ", sum(feasibility_checks_one_topology["$i"]["$hour"]["objective"]*feasibility_checks_one_topology["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)) .+ sum(redispatch_one_topology["$i"]["$hour"]["objective"]*feasibility_checks_one_topology["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)))
    println("Feasibility check one switching action: ", sum(feasibility_checks_one_sw["$i"]["$hour"]["objective"]*feasibility_checks_one_sw["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i))     .+ sum(redispatch_one_sw["$i"]["$hour"]["objective"]*feasibility_checks_one_sw["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)))            
    println("Feasibility check two switching actions: ", sum(feasibility_checks_two_sw["$i"]["$hour"]["objective"]*feasibility_checks_two_sw["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i))    .+ sum(redispatch_two_sw["$i"]["$hour"]["objective"]*feasibility_checks_two_sw["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)))           
    println("--------------")
end

n_scenarios = 6
for hour in 1:(n_hours*n_scenarios)
    println("$hour , $(feasibility_check_hourly["$n_scenarios"]["$hour"]["probability"])")
end

for i in full_scenarios
    println(" $(sum(scenario_wind["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)))")
end


for hour in 1:(n_hours*n_scenarios)
#sum(redispatch_opf["$i"]["$hour"]["objective"]*feasibility_check_hourly["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i))
    println("hour $hour ")
    println("obj $(redispatch_opf["$n_scenarios"]["$hour"]["objective"])")
    println("prob, $(feasibility_check_hourly["$n_scenarios"]["$hour"]["probability"])")
    println("--------")
end


#########################

forecasted_redispatch_opf          = Dict{String,Any}()
forecasted_redispatch_hourly       = Dict{String,Any}()
forecasted_redispatch_one_topology = Dict{String,Any}()
forecasted_redispatch_one_sw       = Dict{String,Any}()
forecasted_redispatch_two_sw       = Dict{String,Any}()

redispatch_scenarios_opf(forecasted_redispatch_opf,hourly_opf,forecasted_wind)
redispatch_scenarios(forecasted_redispatch_hourly,hourly_optimization,feasibility_check_hourly,forecasted_wind)
redispatch_scenarios(forecasted_redispatch_one_topology,one_topology,feasibility_check_one_topology,forecasted_wind)
redispatch_scenarios(forecasted_redispatch_one_sw,one_switching_action,feasibility_check_one_sw,forecasted_wind)
redispatch_scenarios(forecasted_redispatch_two_sw,two_switching_action,feasibility_check_two_sw,forecasted_wind)

for i in scenarios
    println("Scenario $i")
    println("AC-OPF: ", sum(hourly_opf["$i"]["$hour"]["objective"]*feasibility_check_hourly["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i))                                                     .+ sum(forecasted_redispatch_opf["$i"]["$hour"]["objective"]*feasibility_check_hourly["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)))
    println("Feasibility check hourly: ", sum(feasibility_check_hourly["$i"]["$hour"]["objective"]*feasibility_check_hourly["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i))                     .+ sum(forecasted_redispatch_hourly["$i"]["$hour"]["objective"]*feasibility_check_hourly["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)))            
    println("Feasibility check one topology: ", sum(feasibility_checks_one_topology["$i"]["$hour"]["objective"]*feasibility_checks_one_topology["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)) .+ sum(forecasted_redispatch_one_topology["$i"]["$hour"]["objective"]*feasibility_checks_one_topology["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)))
    println("Feasibility check one switching action: ", sum(feasibility_checks_one_sw["$i"]["$hour"]["objective"]*feasibility_checks_one_sw["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i))     .+ sum(forecasted_redispatch_one_sw["$i"]["$hour"]["objective"]*feasibility_checks_one_sw["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)))            
    println("Feasibility check two switching actions: ", sum(feasibility_checks_two_sw["$i"]["$hour"]["objective"]*feasibility_checks_two_sw["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i))    .+ sum(forecasted_redispatch_two_sw["$i"]["$hour"]["objective"]*feasibility_checks_two_sw["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)))           
    println("--------------")
end

json_redispatch_opf          = JSON.json(redispatch_opf         )
json_redispatch_hourly       = JSON.json(redispatch_hourly      )
json_redispatch_one_topology = JSON.json(redispatch_one_topology)
json_redispatch_one_sw       = JSON.json(redispatch_one_sw      )
json_redispatch_two_sw       = JSON.json(redispatch_two_sw      )

open(joinpath(results_folder,case,"redispatch_OPF_Laplace_scenarios_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_redispatch_opf) 
end 

open(joinpath(results_folder,case,"redispatch_hourly_bs_Laplace_scenarios_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_redispatch_hourly) 
end 

open(joinpath(results_folder,case,"redispatch_one_topology_Laplace_scenarios_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_redispatch_one_topology) 
end 

open(joinpath(results_folder,case,"redispatch_one_sw_Laplace_scenarios_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_redispatch_one_sw) 
end 

open(joinpath(results_folder,case,"redispatch_two_sw_Laplace_scenarios_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_redispatch_two_sw) 
end 

###############################################################

json_forecasted_redispatch_opf          = JSON.json(forecasted_redispatch_opf         )
json_forecasted_redispatch_hourly       = JSON.json(forecasted_redispatch_hourly      )
json_forecasted_redispatch_one_topology = JSON.json(forecasted_redispatch_one_topology)
json_forecasted_redispatch_one_sw       = JSON.json(forecasted_redispatch_one_sw      )
json_forecasted_redispatch_two_sw       = JSON.json(forecasted_redispatch_two_sw      )

open(joinpath(results_folder,case,"redispatch_forecasted_OPF_Laplace_scenarios_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_forecasted_redispatch_opf) 
end 

open(joinpath(results_folder,case,"redispatch_forecasted_hourly_bs_Laplace_scenarios_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_forecasted_redispatch_hourly) 
end 

open(joinpath(results_folder,case,"redispatch_forecasted_one_topology_Laplace_scenarios_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_forecasted_redispatch_one_topology) 
end 

open(joinpath(results_folder,case,"redispatch_forecasted_one_sw_Laplace_scenarios_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_forecasted_redispatch_one_sw) 
end 

open(joinpath(results_folder,case,"redispatch_forecasted_two_sw_Laplace_scenarios_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_forecasted_redispatch_two_sw) 
end 

###################

for i in scenarios
    println("Scenario $i")
    println(sum(hourly_opf["$i"]["$hour"]["objective"]*feasibility_check_hourly["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i))                                                     .+ sum(redispatch_opf["$i"]["$hour"]["objective"]*feasibility_check_hourly["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)))
    println(sum(feasibility_check_hourly["$i"]["$hour"]["objective"]*feasibility_check_hourly["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i))                     .+ sum(redispatch_hourly["$i"]["$hour"]["objective"]*feasibility_check_hourly["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)))            
    println(sum(feasibility_checks_one_topology["$i"]["$hour"]["objective"]*feasibility_checks_one_topology["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)) .+ sum(redispatch_one_topology["$i"]["$hour"]["objective"]*feasibility_checks_one_topology["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)))
    println(sum(feasibility_checks_one_sw["$i"]["$hour"]["objective"]*feasibility_checks_one_sw["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i))     .+ sum(redispatch_one_sw["$i"]["$hour"]["objective"]*feasibility_checks_one_sw["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)))            
    println(sum(feasibility_checks_two_sw["$i"]["$hour"]["objective"]*feasibility_checks_two_sw["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i))    .+ sum(redispatch_two_sw["$i"]["$hour"]["objective"]*feasibility_checks_two_sw["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)))           
    println("--------------")
end



for i in scenarios
    println("Scenario $i")
    println(sum(hourly_opf["$i"]["$hour"]["objective"]*feasibility_check_hourly["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i))                                                     .+ sum(forecasted_redispatch_opf["$i"]["$hour"]["objective"]*feasibility_check_hourly["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)))
    println(sum(feasibility_check_hourly["$i"]["$hour"]["objective"]*feasibility_check_hourly["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i))                     .+ sum(forecasted_redispatch_hourly["$i"]["$hour"]["objective"]*feasibility_check_hourly["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)))            
    println(sum(feasibility_checks_one_topology["$i"]["$hour"]["objective"]*feasibility_checks_one_topology["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)) .+ sum(forecasted_redispatch_one_topology["$i"]["$hour"]["objective"]*feasibility_checks_one_topology["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)))
    println(sum(feasibility_checks_one_sw["$i"]["$hour"]["objective"]*feasibility_checks_one_sw["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i))     .+ sum(forecasted_redispatch_one_sw["$i"]["$hour"]["objective"]*feasibility_checks_one_sw["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)))            
    println(sum(feasibility_checks_two_sw["$i"]["$hour"]["objective"]*feasibility_checks_two_sw["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i))    .+ sum(forecasted_redispatch_two_sw["$i"]["$hour"]["objective"]*feasibility_checks_two_sw["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)))           
    println("--------------")
end