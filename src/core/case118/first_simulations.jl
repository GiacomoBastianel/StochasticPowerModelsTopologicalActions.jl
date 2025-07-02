using PowerModels; const _PM = PowerModels
using PowerModelsACDC; const _PMACDC = PowerModelsACDC
import PowerModelsTopologicalActionsII; const _PMTP = PowerModelsTopologicalActionsII
using FlexPlan; const _FP = FlexPlan
using Gurobi, Ipopt, JSON, Plots
import StochasticPowerModelsTopologicalActions; const _SPMTA = StochasticPowerModelsTopologicalActions
using JuMP, Juniper, HSL_jll, MathOptInterface, HiGHS
using Statistics

mip_gap = 1e-5
gurobi_bs = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 600,"MIPGap" => mip_gap,"BarHomogeneous" => 1, "NumericFocus"=>2) 
gurobi = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 3600,"MIPGap" => mip_gap,"BarHomogeneous" => 1,"BarQCPConvTol"=>1e-6,"QCPDual" => 1, "ScaleFlag"=>2, "NumericFocus"=>2) 
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
input_folder = dirname(dirname(dirname(@__DIR__)))
test_case_file = joinpath(input_folder,"data_sources/pglib_opf_case118_ieee.m")
original_grid = _PM.parse_file(test_case_file)

results_folder = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/IJEPES_paper/Results"
results_folder_figures = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/IJEPES_paper/Figures"
case = "case_118"

test_case = _PM.parse_file(test_case_file)
push!(test_case["gen"]["1"]["cost"],10000.0)
push!(test_case["gen"]["1"]["cost"],0.0)


test_case_opf = deepcopy(test_case)

# THIS IS APPARENTLY FUNDAMENTAL TO GUARANTEE FEASIBILITY (to be checked for this case)
_SPMTA.add_VOLL_generators(test_case_opf)

opf_test_result_lpac = _PM.solve_opf(test_case_opf, LPACCPowerModel, ipopt)
opf_test_result_ac = _PM.solve_opf(test_case_opf, ACPPowerModel, ipopt)

for (g_id,g) in test_case_opf["gen"]
    #if opf_test_result_ac["solution"]["gen"][g_id]["pg"] >= 0.001
    if length(g["cost"]) > 0
        println("Generator $g_id has a power output of $(opf_test_result_ac["solution"]["gen"][g_id]["pg"]), pmax $(g["pmax"]) utilized $(opf_test_result_ac["solution"]["gen"][g_id]["pg"]/g["pmax"]), cost $(g["cost"][1]), gen bus $(g["gen_bus"])")
    end
end


#########################################################################################
# Busbar splitting
test_case_bs = deepcopy(test_case_opf)
splitted_bus_ac = 69
test_case_bs,  switches_couples_ac,  extremes_ZILs_ac  = _PMTP.AC_busbar_split_AC_grid(test_case,splitted_bus_ac)

# Adding costs to the busbar couplers
for sw_id in 1:length(extremes_ZILs_ac)
    test_case_bs["switch"]["$sw_id"]["cost"] = 10.0
end

result_bs_6 = _PMTP.run_acdcsw_AC_big_M_hour(test_case_bs, LPACCPowerModel, gurobi_bs)
result_bs_6_no_cost = _PMTP.run_acdcsw_AC_big_M(test_case_bs, LPACCPowerModel, gurobi_bs)


feasibility_check = deepcopy(test_case_bs)
feasibility_check_input = deepcopy(test_case_bs)
_PMTP.prepare_AC_feasibility_check(result_bs_6,feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
result_feasibility_check = _PM.solve_opf(feasibility_check,ACPPowerModel,ipopt; setting = s)


1 - result_feasibility_check["objective"]/opf_test_result_ac["objective"]
#########################################################################################
# Add dimensions for stochastic part
n_scenarios = 4
n_hours = 24
one_scenario = 1
N_4 = 4
N_8 = 8
hours = collect(1:n_hours)
_SPMTA.add_dimensions!(test_case_bs,n_scenarios,n_hours)

start_hour_simulation = 1
end_hour_simulation = 8760

#########################################################################################
# Uploading pdf samples for offshore wind and load data for Belgium
year_wind = "2024"
folder_data = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Elia_data"
#folder_results = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Deliverable_1_2_DIRECTIONS/Results/case_30"

input_data_folder = joinpath(@__DIR__)
first_hour = 355 
last_hour = 378

forecasted_wind = JSON.parsefile(joinpath(input_data_folder,"forecasted_wind_hours_$(first_hour)_$(last_hour).json"))
measured_wind = JSON.parsefile(joinpath(input_data_folder,"measured_wind_$(first_hour)_$(last_hour).json"))
average_forecasted_measured_wind = [mean([forecasted_wind[i],measured_wind[i]]) for i in 1:length(forecasted_wind)]

plot(forecasted_wind,label = "Forecasted wind",grid = :none,ylims = (0,1.2),legend = :topleft,xticks = 1:1:24,xlabel = "Hour",ylabel = "Capacity factor [-]",)
plot!(measured_wind,label = "Average forecasted-measured wind")
plot!(average_forecasted_measured_wind,label = "Measured wind")

#scenarios_wind_4 = JSON.parsefile(joinpath(results_folder,case,"scenario_wind_4_$(first_hour)_$(last_hour)_modified.json"))
scenarios_wind_8 = JSON.parsefile(joinpath(input_data_folder,"scenario_wind_8_$(first_hour)_$(last_hour)_modified.json"))
#scenarios_wind_4_adjusted = JSON.parsefile(joinpath(results_folder,case,"scenario_wind_4_$(first_hour)_$(last_hour)_adjusted.json"))

#########################################################################################
## Running simulations
# Busbar splitting
test_case_opf_replicate = _PM.replicate(test_case_opf, n_hours*n_scenarios)
test_case_opf_replicate_one_scenario = _PM.replicate(test_case_opf, n_hours*one_scenario)

test_case_opf_mn_measured = deepcopy(test_case_opf_replicate_one_scenario)
test_case_opf_mn_forecasted = deepcopy(test_case_opf_replicate_one_scenario)
test_case_opf_mn_average = deepcopy(test_case_opf_replicate_one_scenario)
test_case_opf_mn_expected = deepcopy(test_case_opf_replicate)
test_case_opf_mn_adjusted = deepcopy(test_case_opf_replicate)

n_hours = 24

_SPMTA.adding_multinetwork_scenarios(test_case_opf_mn_measured,n_hours,one_scenario,scenarios_wind_8)
_SPMTA.adding_multinetwork_scenarios(test_case_opf_mn_forecasted,n_hours,one_scenario,scenarios_wind_8)
#_SPMTA.adding_multinetwork_scenarios(test_case_opf_mn_expected,n_hours,N_8,scenarios_wind_8)
#_SPMTA.adding_multinetwork_scenarios(test_case_opf_mn_adjusted,n_hours,N_8,scenarios_wind_8_adjusted)
#_SPMTA.adding_multinetwork_scenarios(test_case_opf_mn_average,n_hours,one_scenario,scenarios_wind_8)

# generators 21 & 45 (cheapest ones)
for (g_id,g) in test_case_opf["gen"]
    if length(g["cost"]) > 0 && g["cost"][1] <= 2600.0
        push!(ofw_gen, parse(Int64, g_id))
    end
end

for i in 1:(n_hours*one_scenario)
    for gen in ofw_gen
        test_case_opf_mn_measured["nw"]["$i"]["gen"]["$gen"]["pmax"]   = deepcopy(test_case_opf_replicate["nw"]["$i"]["gen"]["$gen"]["pmax"]*measured_wind[i])
        test_case_opf_mn_forecasted["nw"]["$i"]["gen"]["$gen"]["pmax"] = deepcopy(test_case_opf_replicate["nw"]["$i"]["gen"]["$gen"]["pmax"]*forecasted_wind[i])
        test_case_opf_mn_average["nw"]["$i"]["gen"]["$gen"]["pmax"]   = deepcopy(test_case_opf_replicate["nw"]["$i"]["gen"]["$gen"]["pmax"]*average_forecasted_measured_wind[i])
    end
end

[test_case_opf_mn_forecasted["nw"]["$i"]["gen"]["45"]["pmax"] for i in 1:n_hours]


for i in 1:(n_hours*n_scenarios)
    #test_case_opf_mn_expected["nw"]["$i"]["gen"]["1"]["pmax"]   = deepcopy(test_case_opf_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*scenarios_wind_8["$i"]["samples_pu"])
    #test_case_opf_mn_adjusted["nw"]["$i"]["gen"]["1"]["pmax"]   = deepcopy(test_case_opf_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*scenarios_wind_8_adjusted["$i"]["samples_pu"])
end

################################################################################

result_forecasted_24_ac = Dict{String,Any}()
result_forecasted_24_lpac = Dict{String,Any}()

result_measured_24_ac = Dict{String,Any}()
result_measured_24_lpac = Dict{String,Any}()

for hour in 1:(n_hours*one_scenario)
    result_forecasted_24_ac["$hour"] = _PM.solve_opf(test_case_opf_mn_forecasted["nw"]["$hour"],ACPPowerModel,ipopt; setting = s)
    result_forecasted_24_lpac["$hour"] = _PM.solve_opf(test_case_opf_mn_forecasted["nw"]["$hour"],LPACCPowerModel,ipopt; setting = s)

    result_measured_24_ac["$hour"] = _PM.solve_opf(test_case_opf_mn_measured["nw"]["$hour"],ACPPowerModel,ipopt; setting = s)
    result_measured_24_lpac["$hour"] = _PM.solve_opf(test_case_opf_mn_measured["nw"]["$hour"],LPACCPowerModel,ipopt; setting = s)
end

obj_forecasted_24_ac = [result_forecasted_24_ac["$i"]["objective"] for i in 1:(n_hours*one_scenario)]
obj_forecasted_24_lpac = [result_forecasted_24_lpac["$i"]["objective"] for i in 1:(n_hours*one_scenario)]
obj_measured_24_lpac = [result_measured_24_lpac["$i"]["objective"] for i in 1:(n_hours*one_scenario)]
obj_measured_24_ac = [result_measured_24_ac["$i"]["objective"] for i in 1:(n_hours*one_scenario)]

#plot(obj_forecasted_24_ac)
#plot!(obj_average_24_ac)
#plot!(obj_measured_24_ac)

meas_ = sum(obj_measured_24_ac)
for_ = sum(obj_forecasted_24_ac)

#=
plot(obj_expected_24_ac./10^3,label = "Stochastic",grid = :none,ylims = (5,25),xticks = 1:n_hours,xlims = (0.8,24.5),xlabel = "Hour",ylabel = "Generation costs [k€]",
legend = :topleft,xlabelfontsize = 10,ylabelfontsize = 10,xtickfont = font(8),ytickfont = font(8))
plot!(obj_measured_24_ac./10^3,label = "Measured")
plot!(obj_forecasted_24_ac./10^3,label = "Forecasted")
plot!(obj_adjusted_24_ac./10^3,label = "Adjusted")
plot!(obj_average_24_ac./10^3,label = "Average")
savefig(joinpath(results_folder_figures,"case_118","OPF_results_$(first_hour)_$(last_hour)_modified.svg"))


json_hourly_forecasted_24 = JSON.json(result_forecasted_24_ac)
open(joinpath(results_folder,case,"Hourly_opf_forecasted_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_hourly_forecasted_24) 
end 

json_hourly_measured_24 = JSON.json(result_measured_24_ac)
open(joinpath(results_folder,case,"Hourly_opf_measured_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_hourly_measured_24) 
end 

json_hourly_average_24 = JSON.json(result_average_24_ac)
open(joinpath(results_folder,case,"Hourly_opf_average_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_hourly_average_24) 
end 

json_hourly_expected_24 = JSON.json(result_expected_24_ac)
open(joinpath(results_folder,case,"Hourly_opf_stochastic_4_scenarios_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_hourly_expected_24) 
end 

json_hourly_adjusted_24 = JSON.json(result_adjusted_24_ac)
open(joinpath(results_folder,case,"Hourly_opf_stochastic_4_scenarios_adjusted_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_hourly_adjusted_24) 
end 
=#


###########################################################################
# -> OPFs are comparable now, data set built, need to tweak the functions to have a multistep-stochastic formulation
n_hours = 24
test_case_bs_replicate = _PM.replicate(test_case_bs, n_hours*n_scenarios)
test_case_bs_replicate_one_scenario = _PM.replicate(test_case_bs, n_hours*one_scenario)

test_case_bs_mn_measured = deepcopy(test_case_bs_replicate_one_scenario)
test_case_bs_mn_forecasted = deepcopy(test_case_bs_replicate_one_scenario)
test_case_bs_mn_average = deepcopy(test_case_bs_replicate_one_scenario)
test_case_bs_mn_expected = deepcopy(test_case_bs_replicate)
test_case_bs_mn_adjusted = deepcopy(test_case_bs_replicate)

_SPMTA.adding_multinetwork_scenarios(test_case_bs_mn_measured,n_hours,one_scenario,scenarios_wind_8)
_SPMTA.adding_multinetwork_scenarios(test_case_bs_mn_forecasted,n_hours,one_scenario,scenarios_wind_8)

for i in 1:(n_hours*one_scenario)
    for gen in ofw_gen
        test_case_bs_mn_measured["nw"]["$i"]["gen"]["$gen"]["pmax"]   = deepcopy(test_case_opf_replicate["nw"]["$i"]["gen"]["$gen"]["pmax"]*measured_wind[i])
        test_case_bs_mn_forecasted["nw"]["$i"]["gen"]["$gen"]["pmax"] = deepcopy(test_case_opf_replicate["nw"]["$i"]["gen"]["$gen"]["pmax"]*forecasted_wind[i])
        test_case_bs_mn_average["nw"]["$i"]["gen"]["$gen"]["pmax"]   = deepcopy(test_case_opf_replicate["nw"]["$i"]["gen"]["$gen"]["pmax"]*average_forecasted_measured_wind[i])
    end
end

result_bs_hourly_forecasted_24 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_per_hour(test_case_bs_mn_forecasted,LPACCPowerModel,gurobi,n_hours,one_scenario;setting = s)
result_bs_hourly_measured_24 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_per_hour(test_case_bs_mn_measured,LPACCPowerModel,gurobi_bs,n_hours,one_scenario;setting = s)

sum(result_bs_hourly_forecasted_24["$h"]["objective"] for h in 1:n_hours)
[result_bs_hourly_forecasted_24["$h"]["termination_status"] for h in 1:n_hours]

[result_bs_hourly_forecasted_24["$h"]["solution"]["switch"]["1"]["status"] for h in 1:n_hours]
[result_bs_hourly_measured_24["$h"]["solution"]["switch"]["1"]["status"] for h in 1:n_hours]



json_hourly_forecasted_24 = JSON.json(result_bs_hourly_forecasted_24)
open(joinpath(results_folder,case,"Hourly_bs_forecasted_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_hourly_forecasted_24) 
end 

json_hourly_measured_24 = JSON.json(result_bs_hourly_measured_24)
open(joinpath(results_folder,case,"Hourly_bs_measured_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_hourly_measured_24) 
end 
#=
json_hourly_average_24 = JSON.json(result_bs_hourly_average_24)
open(joinpath(results_folder,case,"Hourly_bs_average_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_hourly_average_24) 
end 

json_hourly_expected_24 = JSON.json(result_bs_hourly_expected_24)
open(joinpath(results_folder,case,"Hourly_bs_stochastic_4_scenarios_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_hourly_expected_24) 
end 

json_hourly_adjusted_24 = JSON.json(result_bs_hourly_adjusted_24)
open(joinpath(results_folder,case,"Hourly_bs_stochastic_4_scenarios_adjusted_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_hourly_adjusted_24) 
end 
=#

####

results_one_topology_sp_forecasted = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology_sp(test_case_bs_mn_forecasted,LPACCPowerModel,gurobi; setting = s)
results_one_topology_sp_measured = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology(test_case_bs_mn_measured,LPACCPowerModel,gurobi; setting = s)
#results_one_topology_sp_average = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology(test_case_bs_mn_average,LPACCPowerModel,gurobi_bs; setting = s)
#results_one_topology_sp_stochastic = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology(test_case_bs_mn_expected,LPACCPowerModel,gurobi_bs; setting = s)
#results_one_topology_sp_adjusted = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology(test_case_bs_mn_adjusted,LPACCPowerModel,gurobi_bs; setting = s)

json_results_one_topology_sp_forecasted = JSON.json(results_one_topology_sp_forecasted)
open(joinpath(results_folder,case,"24_hours_BS_one_topology_forecasted_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_results_one_topology_sp_forecasted) 
end 



test_case_bs_mn_forecasted_try_max_sw = deepcopy(test_case_bs_mn_forecasted)
test_case_bs_mn_measured_try_max_sw = deepcopy(test_case_bs_mn_measured)

test_case_bs_mn_forecasted["total_switching_actions"] = 1
test_case_bs_mn_measured["total_switching_actions"] = 1

for (sw_id,sw) in test_case_bs_mn_forecasted["nw"]["1"]["switch"]
    sw["maximum_actions"] = 1
end
for (sw_id,sw) in test_case_bs_mn_measured["nw"]["1"]["switch"]
    sw["maximum_actions"] = 1
end

results_one_topology_sp_forecasted_one_max_sw = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches(test_case_bs_mn_forecasted,LPACCPowerModel,gurobi_bs)

