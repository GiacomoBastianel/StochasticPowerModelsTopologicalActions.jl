using PowerModels; const _PM = PowerModels
using PowerModelsACDC; const _PMACDC = PowerModelsACDC
import PowerModelsTopologicalActionsII; const _PMTP = PowerModelsTopologicalActionsII
using FlexPlan; const _FP = FlexPlan
using Gurobi
using Ipopt
using JSON
import StochasticPowerModelsTopologicalActions; const _SPMTA = StochasticPowerModelsTopologicalActions
using JuMP
using Juniper
using HSL_jll

gurobi_e_3 = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "time_limit" => 7200,"MIPGap" => 2e-3)#r, "ScaleFlag"=>2, "NumericFocus"=>2) 

gurobi = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "time_limit" => 7200)#r, "ScaleFlag"=>2, "NumericFocus"=>2) 
ipopt = JuMP.optimizer_with_attributes(Ipopt.Optimizer, "tol" => 1e-6, "print_level" => 0,"linear_solver" => "ma97")
juniper = JuMP.optimizer_with_attributes(Juniper.Optimizer, "nl_solver" => ipopt, "mip_solver" => gurobi, "time_limit" => 36000)

#########################################################################################
## Processing input data
input_folder = "/Users/giacomobastianel/.julia/dev/DIRECTIONS_WP4.jl/src/Step_1"

#########################################################################################
# Uploading pdf samples for offshore wind
year_wind = "2023"
folder_data = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Elia_data"

Gaussian_samples_file = joinpath(folder_data,"Gaussian_samples_8_Offshore_wind_$(year_wind)_Elia.json")
Gaussian_samples = JSON.parsefile(Gaussian_samples_file)

Elia_OFW_file = joinpath(folder_data,"Offshore_wind_$(year_wind)_Elia.json")
Elia_OFW = JSON.parsefile(Elia_OFW_file)

results_folder = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Deliverable_4_1_DIRECTIONS/Results/Collab_Line"
wind_CF_Line = "Wind_capacity_factors_DE2050_1995"

file_cf_Line_name = joinpath(results_folder,"$wind_CF_Line.json")
cf_Line = JSON.parsefile(file_cf_Line_name)

#########################################################################################
# Selecting the hours
hours_wind = []
for l in cf_Line
    values_l = []
    for i in eachindex(Elia_OFW)
        if Elia_OFW[i]["minute"] == "00" && (Elia_OFW[i]["dayahead11hforecast"]/Elia_OFW[i]["monitoredcapacity"] < (l + 0.001) && Elia_OFW[i]["dayahead11hforecast"]/Elia_OFW[i]["monitoredcapacity"] >  (l - 0.001))
            push!(values_l,i)
        end
    end
    push!(hours_wind,values_l[1])
end

Wind_data = Dict{String,Any}()
for i in 1:length(hours_wind)
    Wind_data["$i"] = Dict{String,Any}()
    Wind_data["$i"]["most_recent_forecast_pu"] = Elia_OFW[i]["mostrecentforecast"]/Elia_OFW[i]["monitoredcapacity"]
    Wind_data["$i"]["measured_pu"] = Elia_OFW[i]["measured"]/Elia_OFW[i]["monitoredcapacity"]
    Wind_data["$i"]["P50_11hforecast_pu"] = Elia_OFW[i]["dayahead11hforecast"]/Elia_OFW[i]["monitoredcapacity"]
    Wind_data["$i"]["samples_pu"] = Gaussian_samples["$i"]["samples_pu"]
    Wind_data["$i"]["pdf_normalized"] = Gaussian_samples["$i"]["pdf_normalized"]
    Wind_data["$i"]["Elia_timestep"] = hours_wind[i]
end

#########################################################################################
## Processing input data
input_folder = "/Users/giacomobastianel/.julia/dev/DIRECTIONS_WP4.jl/src/Step_1"

# Belgium grid without energy island
BE_grid_2024_file = joinpath(dirname(dirname(input_folder)),"test_cases/DIRECTIONS_test_case_Step_1_no_OWF_UK_corrected.json")
BE_grid = _PM.parse_file(BE_grid_2024_file)

BE_grid_2024_lpac_file = joinpath(dirname(dirname(input_folder)),"test_cases/DIRECTIONS_test_case_Step_1_no_OWF_UK_corrected_LPAC.json")
BE_grid_lpac = _PM.parse_file(BE_grid_2024_lpac_file)
for (g_id,g) in BE_grid_lpac["gen"]
    g["cost"][1] = g["cost"][1]/100
end
BE_grid_bs = deepcopy(BE_grid_lpac)


splitted_bus_ac = [26,261]
name_splitted_buses = "26_261"

BE_grid_bs,  switches_couples_ac,  extremes_ZILs_ac  = _PMTP.AC_busbar_split_more_buses(BE_grid_bs,splitted_bus_ac)
BE_grid_bs["switch"]["1"]["maximum_actions"] = 1
BE_grid_bs["switch"]["2"]["maximum_actions"] = 1


s = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true)
s_dual = Dict("output" => Dict("branch_flows" => true,"duals" => true), "conv_losses_mp" => true)

#########################################################################################
# Add dimensions for stochastic part
n_hours = 24
start_hour_simulation = 6010
end_hour_simulation = 6033
hours = collect(start_hour_simulation:end_hour_simulation)
n_scenarios = 1

_FP._initialize_dim()
_FP.add_dimension!(BE_grid_bs, :scenario, n_scenarios)
_FP.add_dimension!(BE_grid_bs, :hour, n_hours)

_FP.add_dimension!(BE_grid_lpac, :scenario, n_scenarios)
_FP.add_dimension!(BE_grid_lpac, :hour, n_hours)



function create_RES_time_series(grid,res_dict,scenario_samples_dict,n_scenarios,hours)
    count_ = 0
    for (g_id,g) in grid["gen"]
        res_dict[g_id] = Dict{String,Any}()
        for i in 1:length(hours)
            res_dict[g_id]["$(hours[i])"] = Dict{String,Any}()
            if n_scenarios > 1
                if g["type"] == "Offshore Wind" && g["zone"] == "BE00"
                    res_dict[g_id]["$(hours[i])"]["P50_11hforecast_pu"] = scenario_samples_dict["$i"]["P50_11hforecast_pu"]
                    res_dict[g_id]["$(hours[i])"]["most_recent_forecast_pu"] = scenario_samples_dict["$i"]["most_recent_forecast_pu"]
                    res_dict[g_id]["$(hours[i])"]["measured_pu"] = scenario_samples_dict["$i"]["measured_pu"]
                     for s in 1:n_scenarios
                        res_dict[g_id]["$(hours[i])"]["$s"] = Dict{String,Any}()
                        res_dict[g_id]["$(hours[i])"]["$s"]["pdf"] = scenario_samples_dict["$i"]["pdf_normalized"][s]
                        res_dict[g_id]["$(hours[i])"]["$s"]["samples_pu"] = scenario_samples_dict["$i"]["samples_pu"][s]
                     end
                elseif g["type"] == "Offshore Wind" && g["zone"] != "BE00"
                    res_dict[g_id]["$(hours[i])"]["P50_11hforecast_pu"] = scenario_samples_dict["$i"]["P50_11hforecast_pu"]
                    res_dict[g_id]["$(hours[i])"]["most_recent_forecast_pu"] = scenario_samples_dict["$i"]["most_recent_forecast_pu"]
                    res_dict[g_id]["$(hours[i])"]["measured_pu"] = scenario_samples_dict["$i"]["measured_pu"]
                    for s in 1:n_scenarios
                        res_dict[g_id]["$(hours[i])"]["$s"] = Dict{String,Any}()
                        res_dict[g_id]["$(hours[i])"]["$s"]["pdf"] = scenario_samples_dict["$i"]["pdf_normalized"][s]
                        res_dict[g_id]["$(hours[i])"]["$s"]["samples_pu"] = 1.0
                    end
                else
                    res_dict[g_id]["$(hours[i])"]["P50_11hforecast_pu"] = scenario_samples_dict["$i"]["P50_11hforecast_pu"]
                    res_dict[g_id]["$(hours[i])"]["most_recent_forecast_pu"] = scenario_samples_dict["$i"]["most_recent_forecast_pu"]
                    res_dict[g_id]["$(hours[i])"]["measured_pu"] = scenario_samples_dict["$i"]["measured_pu"]
                    for s in 1:n_scenarios
                        res_dict[g_id]["$(hours[i])"]["$s"] = Dict{String,Any}()
                        res_dict[g_id]["$(hours[i])"]["$s"]["pdf"] = scenario_samples_dict["$i"]["pdf_normalized"][s]
                        res_dict[g_id]["$(hours[i])"]["$s"]["samples_pu"] = 1.0
                    end
                end
            else
                if g["type"] == "Offshore Wind" && g["zone"] == "BE00"
                    res_dict[g_id]["$(hours[i])"]["P50_11hforecast_pu"] = scenario_samples_dict["$i"]["P50_11hforecast_pu"]
                    res_dict[g_id]["$(hours[i])"]["most_recent_forecast_pu"] = scenario_samples_dict["$i"]["most_recent_forecast_pu"]
                    res_dict[g_id]["$(hours[i])"]["measured_pu"] = scenario_samples_dict["$i"]["measured_pu"]
                     for s in 1:n_scenarios
                        res_dict[g_id]["$(hours[i])"]["$s"] = Dict{String,Any}()
                        res_dict[g_id]["$(hours[i])"]["$s"]["pdf"] = 1.0
                        res_dict[g_id]["$(hours[i])"]["$s"]["samples_pu"] = 1.0
                     end
                elseif g["type"] == "Offshore Wind" && g["zone"] != "BE00"
                    res_dict[g_id]["$(hours[i])"]["P50_11hforecast_pu"] = scenario_samples_dict["$i"]["P50_11hforecast_pu"]
                    res_dict[g_id]["$(hours[i])"]["most_recent_forecast_pu"] = scenario_samples_dict["$i"]["most_recent_forecast_pu"]
                    res_dict[g_id]["$(hours[i])"]["measured_pu"] = scenario_samples_dict["$i"]["measured_pu"]
                    for s in 1:n_scenarios
                        res_dict[g_id]["$(hours[i])"]["$s"] = Dict{String,Any}()
                        res_dict[g_id]["$(hours[i])"]["$s"]["pdf"] = 1.0
                        res_dict[g_id]["$(hours[i])"]["$s"]["samples_pu"] = 1.0
                    end
                else
                    res_dict[g_id]["$(hours[i])"]["P50_11hforecast_pu"] = scenario_samples_dict["$i"]["P50_11hforecast_pu"]
                    res_dict[g_id]["$(hours[i])"]["most_recent_forecast_pu"] = scenario_samples_dict["$i"]["most_recent_forecast_pu"]
                    res_dict[g_id]["$(hours[i])"]["measured_pu"] = scenario_samples_dict["$i"]["measured_pu"]
                    for s in 1:n_scenarios
                        res_dict[g_id]["$(hours[i])"]["$s"] = Dict{String,Any}()
                        res_dict[g_id]["$(hours[i])"]["$s"]["pdf"] = 1.0
                        res_dict[g_id]["$(hours[i])"]["$s"]["samples_pu"] = 1.0
                    end
                end
            end
        end
    end
end

#########################################################################################
# Calling scenario and climate year
results_folder = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Deliverable_4_1_DIRECTIONS/Results/Collab_Line"
scenario = "DE"
year = "2050"
climate_year = "1995"

simulated_hour = 761
#########################################################################################
# Uploading files
RES_time_series_file = joinpath(results_folder,"RES_time_series_$(scenario)$(year)_$(climate_year).json")
open(RES_time_series_file, "r") do f
    global RES_time_series = JSON.parse(read(f, String))
end

Load_time_series_file = joinpath(results_folder,"Load_time_series_$(scenario)$(year)_$(climate_year).json")
open(Load_time_series_file, "r") do f
    global Load_time_series = JSON.parse(read(f, String))
end

# Time series
RES_time_series_hour = Dict{String,Any}()
create_RES_time_series(BE_grid_bs,RES_time_series_hour,Wind_data,n_scenarios,hours)
#_SPMTA.create_RES_time_series_scenarios(BE_grid_bs,RES_time_series_hour,Gaussian_samples,n_scenarios,simulated_hour,hour_wind)

scenarios_probabilities = Dict{String,Any}()
#_SPMTA.add_scenarios_probabilities(scenarios_probabilities,hour_wind,n_hours,n_scenarios,Gaussian_samples)


function add_scenarios_probabilities(scenarios_probabilities_dict,start_hour,n_hours,n_scenarios,scenario_samples_dict)
    for i in 1:n_hours
        if n_scenarios > 1
            for j in 1:n_scenarios
                n = (i - 1)*n_scenarios + j
                scenarios_probabilities_dict["$n"] = scenario_samples_dict["$(i)"]["pdf_normalized"][j]
            end
        else
            for j in 1:n_scenarios
                n = (i - 1)*n_scenarios + j
                scenarios_probabilities_dict["$n"] = 1.0
            end
        end
    end
end
add_scenarios_probabilities(scenarios_probabilities,start_hour_simulation,n_hours,n_scenarios,Wind_data)

gen_time_series_hour = Dict{String,Any}()
_SPMTA.add_gen_time_series(BE_grid_bs, gen_time_series_hour, RES_time_series_hour, hours, n_scenarios)

load_time_series_hour = Dict{String,Any}()
_SPMTA.add_load_time_series(BE_grid_bs, load_time_series_hour, Load_time_series, hours, n_scenarios)

time_series_hour = Dict{String,Any}()
_SPMTA.generate_input_dict_stochastic_optimization(time_series_hour,gen_time_series_hour,load_time_series_hour,scenarios_probabilities)

#########################################################################################
_SPMTA.add_hour_scenario_data(BE_grid_bs, n_hours, n_scenarios)
_SPMTA.add_hour_scenario_data(BE_grid_lpac, n_hours, n_scenarios)


function make_multinetwork_time_series_scenarios(
    sn_data::Dict{String,Any},n_scenarios,n_hours,hours,start_hour,time_series::Dict{String,Any};
    global_keys = ["dim","name","per_unit","source_type","source_version"],
    check_dim::Bool = true,
    )

    mn_data = Dict{String,Any}("nw"=>Dict{String,Any}())
    _FP._add_mn_global_values!(mn_data, sn_data, global_keys)
    #template_nw = _make_template_nw(sn_data, global_keys)
    for hour in 1:length(hours)
        for scenario_idx in 1:n_scenarios
            n = (hour - 1)*n_scenarios + scenario_idx
            mn_data["nw"]["$n"] = deepcopy(sn_data)#_build_nw(template_nw, sn_data, time_series_idx; share_data = true)
            delete!(mn_data["nw"]["$n"],"dim")
            add_hour_scenario_probability(mn_data,hour,scenario_idx,n,time_series)
            for (g_id,g) in mn_data["nw"]["$n"]["gen"]
                mn_data["nw"]["$n"]["gen"][g_id]["pmax"] = time_series["gen"][g_id]["$(start_hour+hour)"]["$scenario_idx"]["pmax_hourly"]
            end
            for (l_id,l) in mn_data["nw"]["$n"]["load"]
                mn_data["nw"]["$n"]["load"][l_id]["pd"] = time_series["load"][l_id]["$(start_hour+hour)"]["$scenario_idx"]["pd"]
            end
        end
    end
    mn_data["scenarios"] = n_scenarios
    mn_data["hours"] = n_hours
    return mn_data
end

function add_hour_scenario_probability(data,hour,scenario,index,time_series)
    data["nw"]["$index"]["hour"] = hour
    data["nw"]["$index"]["scenario"] = scenario
    data["nw"]["$index"]["hour_scenario_index"] = [hour,scenario,index]
    data["nw"]["$index"]["probability"] = time_series["scenario_probability"]["$index"]
end

BE_grid_bs_mn = make_multinetwork_time_series_scenarios(BE_grid_bs,n_scenarios,n_hours,hours,start_hour_simulation-1,time_series_hour)
BE_grid_bs_opf_mn = make_multinetwork_time_series_scenarios(BE_grid_lpac,n_scenarios,n_hours,hours,start_hour_simulation-1,time_series_hour)

BE_grid_bs_mn["hours"] = n_hours
BE_grid_bs_mn["scenarios"] = n_scenarios
BE_grid_bs_mn["limit_actions"] = 26


optimizer = gurobi_e_3
result_opf = _SPMTA.run_stochastic_acdc_opf(BE_grid_bs_opf_mn,LPACCPowerModel,optimizer; setting = s)

#result_opf["objective"]*10^4

gurobi_e_3 = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "time_limit" => 7200,"MIPGap" => 1.6e-3)#r, "ScaleFlag"=>2, "NumericFocus"=>2) 
optimizer = gurobi_e_3

#=
result_ZIL = _SPMTA.run_stochastic_acdcsw_AC_ZIL(BE_grid_bs_mn,LPACCPowerModel,optimizer; setting = s)
result_ZIL_no_OTS = _SPMTA.run_stochastic_acdcsw_AC_ZIL_no_OTS(BE_grid_bs_mn,LPACCPowerModel,optimizer; setting = s)

result_ZIL["objective"]*10^4

(result_opf["objective"]*10^4 - result_ZIL["objective"]*10^4)/(result_opf["objective"]*10^4)

result_la = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limited_actions(BE_grid_bs_mn,LPACCPowerModel,optimizer; setting = s)
result_la_no_OTS = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limited_actions_no_OTS(BE_grid_bs_mn,LPACCPowerModel,optimizer; setting = s)

count_ = 0
for i in eachindex(result_la["solution"]["nw"]) 
    println("Nw $i")
    println("Switch 1 $(result_la["solution"]["nw"]["$i"]["switch"]["1"]["status"])")
    count_ += result_la["solution"]["nw"]["$i"]["switch"]["1"]["status"]
    println("Switch 2 $(result_la["solution"]["nw"]["$i"]["switch"]["2"]["status"])")
    count_ += result_la["solution"]["nw"]["$i"]["switch"]["2"]["status"]
    println(" ")
end
count_

results_folder = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Deliverable_4_1_DIRECTIONS/Results/Collab_Line"

json_string = JSON.json(result_opf)
open(joinpath(results_folder,"Results_OPF_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year)_$(n_hours)_hours_$(n_scenarios)_scenarios_OTS.json"),"w") do f 
    write(f, json_string) 
end

json_string = JSON.json(result_ZIL)
open(joinpath(results_folder,"Results_BS_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year)_$(n_hours)_hours_$(n_scenarios)_scenarios_OTS.json"),"w") do f 
    write(f, json_string) 
end

json_string = JSON.json(result_ZIL_no_OTS)
open(joinpath(results_folder,"Results_BS_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year)_$(n_hours)_hours_$(n_scenarios)_scenarios_no_OTS.json"),"w") do f 
    write(f, json_string) 
end

json_string = JSON.json(result_la)
open(joinpath(results_folder,"Results_BS_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year)_$(n_hours)_hours_$(n_scenarios)_scenarios_OTS_limited_actions.json"),"w") do f 
    write(f, json_string) 
end

json_string = JSON.json(result_la_no_OTS)
open(joinpath(results_folder,"Results_BS_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year)_$(n_hours)_hours_$(n_scenarios)_scenarios_no_OTS_limited_actions.json"),"w") do f 
    write(f, json_string) 
end


function print_switch_results(result, grid, nw)
    for i in 1:length(grid["switch"])
        if !haskey(grid["switch"]["$i"],"auxiliary")
            println(i," f_bus ",grid["switch"]["$i"]["f_bus"]," t_bus ",grid["switch"]["$i"]["t_bus"]," status ", result["solution"]["nw"]["$nw"]["switch"]["$i"]["status"])
        else
            println(i," t_bus ",grid["switch"]["$i"]["t_bus"]," status ", result["solution"]["nw"]["$nw"]["switch"]["$i"]["status"]," auxiliary ", grid["switch"]["$i"]["auxiliary"], " original ", grid["switch"]["$i"]["original"])
        end
    end
end

for i in 1:(n_hours*n_scenarios)
    println("Nw $i")
    print_switch_results(result_ZIL,BE_grid_bs,i)
end
=#


result_la = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limited_actions(BE_grid_bs_mn,LPACCPowerModel,gurobi_e_3; setting = s)
count_ = 0
for i in eachindex(result_la["solution"]["nw"]) 
    println("Nw $i")
    println("Switch 1 $(result_la["solution"]["nw"]["$i"]["switch"]["1"]["status"])")
    count_ += result_la["solution"]["nw"]["$i"]["switch"]["1"]["status"]
    println("Switch 2 $(result_la["solution"]["nw"]["$i"]["switch"]["2"]["status"])")
    count_ += result_la["solution"]["nw"]["$i"]["switch"]["2"]["status"]
    println(" ")
end
count_

result_la_no_OTS = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limited_actions_no_OTS(BE_grid_bs_mn,LPACCPowerModel,gurobi_e_3; setting = s)
for i in 1:(n_hours*n_scenarios)
    println("Nw $i")
    print_switch_results(result_ZIL,BE_grid_bs,i)
end
count__ = 0
for i in eachindex(result_la_no_OTS["solution"]["nw"]) 
    println("Nw $i")
    println("Switch 1 $(result_la_no_OTS["solution"]["nw"]["$i"]["switch"]["1"]["status"])")
    count__ += result_la_no_OTS["solution"]["nw"]["$i"]["switch"]["1"]["status"]
    println("Switch 2 $(result_la_no_OTS["solution"]["nw"]["$i"]["switch"]["2"]["status"])")
    count__ += result_la_no_OTS["solution"]["nw"]["$i"]["switch"]["2"]["status"]
    println(" ")
end
count__

result_la_sw = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limited_actions_single_switch(BE_grid_bs_mn,LPACCPowerModel,gurobi_e_3; setting = s)
count___ = 0
for i in eachindex(result_la_sw["solution"]["nw"]) 
    println("Nw $i")
    println("Switch 1 $(result_la_sw["solution"]["nw"]["$i"]["switch"]["1"]["status"])")
    count___ += result_la_sw["solution"]["nw"]["$i"]["switch"]["1"]["status"]
    println("Switch 2 $(result_la_sw["solution"]["nw"]["$i"]["switch"]["2"]["status"])")
    count___ += result_la_sw["solution"]["nw"]["$i"]["switch"]["2"]["status"]
    println(" ")
end
count___

result_la_no_OTS_sw = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limited_actions_single_switch_no_OTS(BE_grid_bs_mn,LPACCPowerModel,gurobi_e_3; setting = s)
count____ = 0
for i in eachindex(result_la_no_OTS_sw["solution"]["nw"]) 
    println("Nw $i")
    println("Switch 1 $(result_la_no_OTS_sw["solution"]["nw"]["$i"]["switch"]["1"]["status"])")
    count____ += result_la_no_OTS_sw["solution"]["nw"]["$i"]["switch"]["1"]["status"]
    println("Switch 2 $(result_la_no_OTS_sw["solution"]["nw"]["$i"]["switch"]["2"]["status"])")
    count____ += result_la_no_OTS_sw["solution"]["nw"]["$i"]["switch"]["2"]["status"]
    println(" ")
end
count____

result_la_sw_all = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limited_actions_limited_single_switch(BE_grid_bs_mn,LPACCPowerModel,gurobi_e_3; setting = s)
count_sw_1 = 0
count_sw_2 = 0
for i in eachindex(result_la_no_OTS["solution"]["nw"]) 
    println("Nw $i")
    println("Switch 1 $(result_la_no_OTS["solution"]["nw"]["$i"]["switch"]["1"]["status"])")
    count_sw_1 += result_la_no_OTS["solution"]["nw"]["$i"]["switch"]["1"]["status"]
    println("Switch 2 $(result_la_no_OTS["solution"]["nw"]["$i"]["switch"]["2"]["status"])")
    count_sw_2 += result_la_no_OTS["solution"]["nw"]["$i"]["switch"]["2"]["status"]
    println(" ")
end
count_sw_1
count_sw_2

result_la_no_OTS_sw_all = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limited_actions_limited_single_switch_no_OTS(BE_grid_bs_mn,LPACCPowerModel,gurobi_e_3; setting = s)
count_sw_1_ = 0
count_sw_2_ = 0

for i in eachindex(result_la_no_OTS_sw_all["solution"]["nw"]) 
    println("Nw $i")
    println("Switch 1 $(result_la_no_OTS_sw_all["solution"]["nw"]["$i"]["switch"]["1"]["status"])")
    count_sw_1_ += result_la_no_OTS_sw_all["solution"]["nw"]["$i"]["switch"]["1"]["status"]
    println("Switch 2 $(result_la_no_OTS_sw_all["solution"]["nw"]["$i"]["switch"]["2"]["status"])")
    count_sw_2_ += result_la_no_OTS_sw_all["solution"]["nw"]["$i"]["switch"]["2"]["status"]
    println(" ")
end
count_sw_1_
count_sw_2_