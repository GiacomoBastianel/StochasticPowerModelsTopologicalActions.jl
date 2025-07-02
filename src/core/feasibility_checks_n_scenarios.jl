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

for i in scenarios
    scenario_wind["$i"] = JSON.parsefile(joinpath(input_folder,"case30","Laplace_$(i)_scenarios_$(first_hour)_$(last_hour).json"))
end

# Uploading results
hourly_opf = Dict{String,Any}()
for i in full_scenarios
    hourly_opf["$i"] = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Hourly_opf_stochastic_Laplace_$(i)_scenarios_$(first_hour)_$(last_hour).json"))
end

hourly_optimization = Dict{String,Any}()
for i in full_scenarios
    hourly_optimization["$i"] = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Hourly_bs_stochastic_Laplace_$(i)_scenarios_$(first_hour)_$(last_hour).json"))
end

one_topology = Dict{String,Any}()
for i in scenarios
    one_topology["$i"] = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","24_hours_BS_one_topology_stochastic_Laplace_$(i)_scenarios_$(first_hour)_$(last_hour).json"))
end

one_switching_action = Dict{String,Any}()
for i in scenarios
    one_switching_action["$i"] = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","One_maximum_actions_24_hours_stochastic_Laplace_$(i)_scenarios_$(first_hour)_$(last_hour).json"))
end

two_switching_action = Dict{String,Any}()
for i in scenarios
    two_switching_action["$i"] = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Two_maximum_actions_24_hours_stochastic_Laplace_$(i)_scenarios_$(first_hour)_$(last_hour).json"))
end

#########################################################################################
#=
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

feasibility_check_hourly = Dict{String,Any}()
for i in scenarios
    test_case_bs_replicate = _PM.replicate(test_case_bs, n_hours*i)
    test_case_bs_scenarios = deepcopy(test_case_bs_replicate)
    _SPMTA.adding_multinetwork_scenarios(test_case_bs_scenarios,n_hours,i,scenario_wind["$i"])
    for h in 1:(n_hours*i)
        test_case_bs_scenarios["nw"]["$h"]["gen"]["1"]["pmax"]   = deepcopy(test_case_bs_scenarios["nw"]["$h"]["gen"]["1"]["pmax"]*scenario_wind["$i"]["$h"]["samples_pu"])
    end
    feasibility_check_hourly["$i"] = Dict{String,Any}()
    feasibility_check_hourly["$i"] = run_feasibility_checks_per_hour_stochastic(test_case_bs_scenarios,hourly_optimization["$i"],ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s,n_hours,i)
end

run_feasibility_checks_per_hour_one_topology = Dict{String,Any}()
for i in scenarios
    test_case_bs_replicate = _PM.replicate(test_case_bs, n_hours*i)
    test_case_bs_scenarios = deepcopy(test_case_bs_replicate)
    _SPMTA.adding_multinetwork_scenarios(test_case_bs_scenarios,n_hours,i,scenario_wind["$i"])
    for h in 1:(n_hours*i)
        test_case_bs_scenarios["nw"]["$h"]["gen"]["1"]["pmax"]   = deepcopy(test_case_bs_scenarios["nw"]["$h"]["gen"]["1"]["pmax"]*scenario_wind["$i"]["$h"]["samples_pu"])
    end
    run_feasibility_checks_per_hour_one_topology["$i"] = Dict{String,Any}()
    run_feasibility_checks_per_hour_one_topology["$i"] = run_feasibility_checks_per_hour_stochastic(test_case_bs_scenarios,one_topology["$i"],ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s,n_hours,i)
end
=#

# Running feasibility checks
feasibility_check_hourly        = Dict{String,Any}()
feasibility_checks_one_topology = Dict{String,Any}()
feasibility_checks_one_sw       = Dict{String,Any}()
feasibility_checks_two_sw       = Dict{String,Any}()

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

feasibility_check_scenarios(feasibility_check_hourly       ,hourly_optimization )
feasibility_check_scenarios(feasibility_checks_one_topology,one_topology        )
feasibility_check_scenarios(feasibility_checks_one_sw      ,one_switching_action)
feasibility_check_scenarios(feasibility_checks_two_sw      ,two_switching_action)


for i in scenarios
    println("Scenario $i")
    println("AC-OPF: ", sum(hourly_opf["$i"]["$hour"]["objective"]*feasibility_check_hourly["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)))
    println("Feasibility check hourly: ", sum(feasibility_check_hourly["$i"]["$hour"]["objective"]*feasibility_check_hourly["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)))
    println("Feasibility check one topology: ", sum(feasibility_checks_one_topology["$i"]["$hour"]["objective"]*feasibility_checks_one_topology["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)))
    println("Feasibility check one switching action: ", sum(feasibility_checks_one_sw["$i"]["$hour"]["objective"]*feasibility_checks_one_sw["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)))
    println("Feasibility check two switching actions: ", sum(feasibility_checks_two_sw["$i"]["$hour"]["objective"]*feasibility_checks_two_sw["$i"]["$hour"]["probability"] for hour in 1:(n_hours*i)))
    println("--------------")
end


##########################
# Saving results
json_feasibility_check_hourly        = JSON.json(feasibility_check_hourly       )
json_feasibility_checks_one_topology = JSON.json(feasibility_checks_one_topology)
json_feasibility_checks_one_sw       = JSON.json(feasibility_checks_one_sw      )
json_feasibility_checks_two_sw       = JSON.json(feasibility_checks_two_sw      )

json_hourly_opf           = JSON.json(hourly_opf)
json_hourly_optimization  = JSON.json(hourly_optimization )
json_one_topology         = JSON.json(one_topology        )
json_one_switching_action = JSON.json(one_switching_action)
json_two_switching_action = JSON.json(two_switching_action)

open(joinpath(results_folder,case,"fc_hourly_bs_Laplace_scenarios_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_feasibility_check_hourly) 
end 

open(joinpath(results_folder,case,"fc_one_topology_Laplace_scenarios_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_feasibility_checks_one_topology) 
end 

open(joinpath(results_folder,case,"fc_one_sw_Laplace_scenarios_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_feasibility_checks_one_sw) 
end 

open(joinpath(results_folder,case,"fc_two_sw_Laplace_scenarios_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_feasibility_checks_two_sw) 
end 

###########

open(joinpath(results_folder,case,"Hourly_OPF_Laplace_scenarios_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_hourly_opf) 
end 

open(joinpath(results_folder,case,"Hourly_bs_Laplace_scenarios_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_hourly_optimization) 
end 

open(joinpath(results_folder,case,"One_topology_Laplace_scenarios_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_one_topology) 
end 

open(joinpath(results_folder,case,"One_sw_Laplace_scenarios_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_one_switching_action) 
end 

open(joinpath(results_folder,case,"Two_sw_Laplace_scenarios_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_two_switching_action) 
end 

#########################################

function print_switch_results(result, grid, nw)
    switches = []
    for i in 1:length(grid["switch"])
        if !haskey(grid["switch"]["$i"],"auxiliary")
            push!(switches,result["solution"]["nw"]["$nw"]["switch"]["$i"]["status"])
            println(i," f_bus ",grid["switch"]["$i"]["f_bus"]," t_bus ",grid["switch"]["$i"]["t_bus"]," status ", result["solution"]["nw"]["$nw"]["switch"]["$i"]["status"])
        else
            push!(switches,result["solution"]["nw"]["$nw"]["switch"]["$i"]["status"])
            println(i," t_bus ",grid["switch"]["$i"]["t_bus"]," status ", result["solution"]["nw"]["$nw"]["switch"]["$i"]["status"]," auxiliary ", grid["switch"]["$i"]["auxiliary"], " original ", grid["switch"]["$i"]["original"])
        end
    end
    return switches
end
print_switch_results(one_topology["8"],test_case_bs,1)






