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
using Statistics
using MathOptInterface

gurobi_e_3 = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "time_limit" => 600,"MIPGap" => 2e-2)#r, "ScaleFlag"=>2, "NumericFocus"=>2) 
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
## Processing input data
input_folder = "/Users/giacomobastianel/.julia/dev/DIRECTIONS_WP4.jl/src/Step_1"

# Belgium grid without energy island
BE_grid_2024_file = joinpath(dirname(dirname(input_folder)),"test_cases/DIRECTIONS_test_case_Step_1_no_OWF_UK_corrected.json")
BE_grid_6010_6033 = _PM.parse_file(BE_grid_2024_file)

BE_grid_2024_lpac_file = joinpath(dirname(dirname(input_folder)),"test_cases/DIRECTIONS_test_case_Step_1_no_OWF_UK_corrected_LPAC.json")
BE_grid_lpac_6010_6033 = _PM.parse_file(BE_grid_2024_lpac_file)
BE_grid_bs_6010_6033 = deepcopy(BE_grid_lpac_6010_6033)

splitted_bus_ac = [26,261]
name_splitted_buses = "26_261"

BE_grid_bs_6010_6033,  switches_couples_ac_6010_6033,  extremes_ZILs_ac_6010_6033  = _PMTP.AC_busbar_split_more_buses(BE_grid_bs_6010_6033,splitted_bus_ac)
BE_grid_bs_6010_6033["switch"]["1"]["maximum_actions"] = 12
BE_grid_bs_6010_6033["switch"]["2"]["maximum_actions"] = 12

s = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true)
s_dual = Dict("output" => Dict("branch_flows" => true,"duals" => true), "conv_losses_mp" => true)

_PMACDC.run_acdcopf(BE_grid_bs_6010_6033,ACPPowerModel,ipopt; setting = s)

#########################################################################################
# Add dimensions for stochastic part
n_hours = 2
start_hour_simulation = 6010
end_hour_simulation = 6033
hours = collect(start_hour_simulation:end_hour_simulation)
n_scenarios = 8

_FP._initialize_dim()
_FP.add_dimension!(BE_grid_bs_6010_6033, :scenario, n_scenarios)
_FP.add_dimension!(BE_grid_bs_6010_6033, :hour, n_hours)

_FP.add_dimension!(BE_grid_lpac_6010_6033, :scenario, n_scenarios)
_FP.add_dimension!(BE_grid_lpac_6010_6033, :hour, n_hours)

_FP.add_dimension!(BE_grid_6010_6033, :scenario, n_scenarios)
_FP.add_dimension!(BE_grid_6010_6033, :hour, n_hours)


#########################################################################################
# Calling scenario and climate year
results_folder = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Deliverable_4_1_DIRECTIONS/Results/Collab_Line"
scenario = "DE"
year = "2050"
climate_year = "1995"
zones = unique([g["zone"] for (g_id,g) in BE_grid_bs_6010_6033["gen"]])

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

function create_gen_time_series_tyndp_scenario(grid,res_dict,RES_time_series, start_hour_simulation, end_hour_simulation)
    count_ = 0
    zones = unique([g["zone"] for (g_id,g) in grid["gen"]])
    for (g_id,g) in grid["gen"]
        res_dict[g_id] = Dict{String,Any}()
        for i in start_hour_simulation:end_hour_simulation
            res_dict[g_id]["$i"] = Dict{String,Any}()
            if g["type"] == "Offshore Wind" && g["zone"] == "BE00"
                res_dict[g_id]["$i"]["capacity_factor"] = RES_time_series["BE00"]["Offshore_wind"][i]
            elseif g["type"] == "Offshore Wind" && g["zone"] != "UK00"
                res_dict[g_id]["$i"]["capacity_factor"] = RES_time_series["UK00"]["Offshore_wind"][i]
            elseif g["type"] == "Offshore Wind" && g["zone"] != "FR00"
                res_dict[g_id]["$i"]["capacity_factor"] = RES_time_series["FR00"]["Offshore_wind"][i]
            elseif g["type"] == "Onshore Wind" && g["zone"] == "BE00"
                res_dict[g_id]["$i"]["capacity_factor"] = RES_time_series["BE00"]["Onshore_wind"][i]
            elseif g["type"] == "Onshore Wind" && g["zone"] != "UK00"
                res_dict[g_id]["$i"]["capacity_factor"] = RES_time_series["UK00"]["Onshore_wind"][i]
            elseif g["type"] == "Onshore Wind" && g["zone"] != "FR00"
                res_dict[g_id]["$i"]["capacity_factor"] = RES_time_series["FR00"]["Onshore_wind"][i]
            elseif g["type"] == "Solar PV" && g["zone"] == "BE00"
                res_dict[g_id]["$i"]["capacity_factor"] = RES_time_series["BE00"]["Solar_PV"][i]
            elseif g["type"] == "Solar PV" && g["zone"] != "UK00"
                res_dict[g_id]["$i"]["capacity_factor"] = RES_time_series["UK00"]["Solar_PV"][i]
            elseif g["type"] == "Solar PV" && g["zone"] != "FR00"
                res_dict[g_id]["$i"]["capacity_factor"] = RES_time_series["FR00"]["Solar_PV"][i]
            else
                res_dict[g_id]["$i"]["capacity_factor"] = 1.0
            end
        end
    end
end

function add_load_time_series_tyndp_scenario(grid, load_dict, load_input_dict, start_hour_simulation, end_hour_simulation, n_scenarios)
    for (l_id,l) in grid["load"]
        load_dict[l_id] = Dict{String,Any}("$h" => Dict{String,Any}("$scenario" => Dict{String,Any}(
            "pd" => load_input_dict[l["zone"]]["pu"][h]) for scenario in 1:n_scenarios) for h in start_hour_simulation:end_hour_simulation)
    end
end

# Time series
gen_time_series_hour = Dict{String,Any}()
#create_RES_time_series(BE_grid_bs_6010_6033,RES_time_series_hour,Wind_data,n_scenarios,hours)
create_gen_time_series_tyndp_scenario(BE_grid_bs_6010_6033,gen_time_series_hour,RES_time_series,start_hour_simulation,end_hour_simulation)
create_gen_time_series_tyndp_scenario(BE_grid_6010_6033,gen_time_series_hour,RES_time_series,start_hour_simulation,end_hour_simulation)

load_time_series_hour = Dict{String,Any}()
add_load_time_series_tyndp_scenario(BE_grid_bs_6010_6033, load_time_series_hour, Load_time_series, start_hour_simulation, end_hour_simulation, n_scenarios)
add_load_time_series_tyndp_scenario(BE_grid_6010_6033, load_time_series_hour, Load_time_series, start_hour_simulation, end_hour_simulation, n_scenarios)

time_series_hour = Dict{String,Any}()

function generate_input_dict_stochastic_optimization(dict,gen_time_series,load_time_series,scenarios_probabilities)
    dict["gen"] = gen_time_series
    dict["load"] = load_time_series
    dict["scenario_probability"] = scenarios_probabilities
    return dict
end

scenarios_probabilities = Dict{String,Any}()
generate_input_dict_stochastic_optimization(time_series_hour,gen_time_series_hour,load_time_series_hour,scenarios_probabilities)

#########################################################################################
_SPMTA.add_hour_scenario_data(BE_grid_bs_6010_6033, n_hours, n_scenarios)
_SPMTA.add_hour_scenario_data(BE_grid_6010_6033, n_hours, n_scenarios)


function add_hour_scenario_probability_tyndp_scenario(data,hour,index)
    data["nw"]["$index"]["hour"] = index
    data["nw"]["$index"]["scenario"] = 1
    data["nw"]["$index"]["hour_scenario_index"] = [hour,scenario]
    data["nw"]["$index"]["probability"] = 1.0
end

function make_multinetwork_time_series_tyndp_scenario(
    sn_data::Dict{String,Any},n_scenarios,start_hour_simulation,end_hour_simulation,res_time_series,load_time_series,zones;
    global_keys = ["dim","name","per_unit","source_type","source_version"],
    check_dim::Bool = true,
    )

    mn_data = Dict{String,Any}("nw"=>Dict{String,Any}())
    _FP._add_mn_global_values!(mn_data, sn_data, global_keys)
    count_ = 1
    #template_nw = _make_template_nw(sn_data, global_keys)
    for hour in start_hour_simulation:end_hour_simulation
        count_ += 1
        n = (count_ - 1)*n_scenarios 
        mn_data["nw"]["$n"] = deepcopy(sn_data)#_build_nw(template_nw, sn_data, time_series_idx; share_data = true)
        add_hour_scenario_probability_tyndp_scenario(mn_data,hour,n)
        _SPMTA.fix_hourly_load(mn_data["nw"]["$n"],hour,zones,load_time_series) 
        _SPMTA.fix_res_time_series(mn_data["nw"]["$n"],hour,zones,res_time_series)
    end
    mn_data["scenarios"] = n_scenarios
    mn_data["hours"] = n_hours
    return mn_data
end

BE_grid_bs_opf_mn_6010_6033 = make_multinetwork_time_series_tyndp_scenario(BE_grid_lpac_6010_6033,n_scenarios,start_hour_simulation,end_hour_simulation,RES_time_series,Load_time_series,zones)
BE_grid_opf_mn_6010_6033 = make_multinetwork_time_series_tyndp_scenario(BE_grid_6010_6033,n_scenarios,start_hour_simulation,end_hour_simulation,RES_time_series,Load_time_series,zones)

count_ = 0
for nw in start_hour_simulation:end_hour_simulation
    count_ += 1
    BE_grid_bs_opf_mn_6010_6033["nw"]["$count_"]["probability"] = 1
end
result_opf = _SPMTA.run_stochastic_acdc_opf(BE_grid_bs_opf_mn_6010_6033,LPACCPowerModel,gurobi; setting = s)
result_ac_opf = _SPMTA.run_stochastic_acdc_opf(BE_grid_opf_mn_6010_6033,ACPPowerModel,ipopt; setting = s)


@time result_single_opf = _SPMTA.hourly_opf(BE_grid_lpac_6010_6033,start_hour_simulation,end_hour_simulation,zones,Load_time_series,RES_time_series,s_dual,gurobi,LPACCPowerModel)
obj = sum(result_single_opf["$i"]["objective"] for i in start_hour_simulation:end_hour_simulation)
@time result_single_ac_opf = _SPMTA.hourly_opf(BE_grid_6010_6033,start_hour_simulation,end_hour_simulation,zones,Load_time_series,RES_time_series,s_dual,ipopt,ACPPowerModel)
obj_ac_opf = sum(result_single_ac_opf["$i"]["objective"] for i in start_hour_simulation:end_hour_simulation)

gurobi_e_3 = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "MIPGap" => 5e-3)# "time_limit" => 600)#r, "ScaleFlag"=>2, "NumericFocus"=>2) 
optimizer = gurobi_e_3

BE_grid_bs_mn = make_multinetwork_time_series_tyndp_scenario(BE_grid_bs_6010_6033,n_scenarios,start_hour_simulation,end_hour_simulation,RES_time_series,Load_time_series,zones)
BE_grid_bs_mn["hours"] = n_hours
BE_grid_bs_mn["scenarios"] = n_scenarios
BE_grid_bs_mn["limit_actions"] = 24
#BE_grid_bs_mn["opf_result"] = result_opf["objective"]

result_ZIL = _SPMTA.run_stochastic_acdcsw_AC_ZIL(BE_grid_bs_mn,LPACCPowerModel,gurobi_e_3; setting = s)

function prepare_starting_value_dict_nw(result,grid,start_hour_simulation,end_hour_simulation,n_scenarios)
    count_ = 1
    for hour in start_hour_simulation:end_hour_simulation
        count_ += 1
        n = (count_ - 1)*n_scenarios 
        for (b_id,b) in grid["nw"]["$n"]["bus"]
            if haskey(result["solution"]["nw"]["$n"]["bus"],b_id)
                if abs(result["solution"]["nw"]["$n"]["bus"]["$b_id"]["va"]) < 10^(-4)
                    b["va_starting_value"] = 0.0
                else
                    b["va_starting_value"] = result["solution"]["nw"]["$n"]["bus"]["$b_id"]["va"]
                end
                if abs(result["solution"]["nw"]["$n"]["bus"]["$b_id"]["vm"]) < 10^(-4)
                    b["vm_starting_value"] = 0.0
                else
                    b["vm_starting_value"] = result["solution"]["nw"]["$n"]["bus"]["$b_id"]["vm"]
                end
            else
                b["va_starting_value"] = 0.0
                b["vm_starting_value"] = 1.0
            end
        end
        for (b_id,b) in grid["nw"]["$n"]["gen"]
            if abs(result["solution"]["nw"]["$n"]["gen"]["$b_id"]["pg"]) < 10^(-5)
                b["pg_starting_value"] = 0.0
            else
                b["pg_starting_value"] = result["solution"]["nw"]["$n"]["gen"]["$b_id"]["pg"]
            end
            if abs(result["solution"]["nw"]["$n"]["gen"]["$b_id"]["qg"]) < 10^(-5)
                b["qg_starting_value"] = 0.0
            else
                b["qg_starting_value"] = result["solution"]["nw"]["$n"]["gen"]["$b_id"]["qg"]
            end
        end
        for (sw_id,sw) in grid["nw"]["$n"]["switch"]
            if !haskey(sw,"auxiliary") # calling ZILs
                sw["starting_value"] = 1.0
            else
                if haskey(grid["nw"]["$n"]["switch_couples"],sw_id)
                    grid["nw"]["$n"]["switch"]["$(grid["nw"]["$n"]["switch_couples"][sw_id]["f_sw"])"]["starting_value"] = 0.0
                    grid["nw"]["$n"]["switch"]["$(grid["nw"]["$n"]["switch_couples"][sw_id]["t_sw"])"]["starting_value"] = 1.0
                end
                #sw["starting_value"] = 0.0
            end
        end
    end
end
BE_grid_bs_mn_6010_6033_sp = deepcopy(BE_grid_bs_mn)
prepare_starting_value_dict_nw(result_ac_opf,BE_grid_bs_mn_6010_6033_sp,start_hour_simulation,end_hour_simulation,n_scenarios)
result_ZIL_sp = _SPMTA.run_stochastic_acdcsw_AC_ZIL_sp(BE_grid_bs_mn_6010_6033_sp,LPACCPowerModel,gurobi_e_3; setting = s)



#result_ZIL_no_OTS = _SPMTA.run_stochastic_acdcsw_AC_ZIL_no_OTS(BE_grid_bs_mn,LPACCPowerModel,gurobi_e_3; setting = s)


function hourly_bs_nw(grid,optimizer,formulation)
    results = Dict()
    for hour in 1:(n_hours*n_scenarios)
        hourly_grid = deepcopy(grid["nw"]["$hour"])
        hourly_results = _PMTP.run_acdcsw_AC_big_M_ZIL(hourly_grid,formulation,optimizer)
        results["$hour"] = deepcopy(hourly_results)
    end
    return results
end
function hourly_bs_nw_sp(grid,optimizer,formulation)
    results = Dict()
    for hour in 1:(n_hours*n_scenarios)
        hourly_grid = deepcopy(grid["nw"]["$hour"])
        hourly_results = _PMTP.run_acdcsw_AC_big_M_ZIL_sp(hourly_grid,formulation,optimizer)
        results["$hour"] = deepcopy(hourly_results)
    end
    return results
end
@time results_bs_hourly = hourly_bs_nw(BE_grid_bs_mn,gurobi_e_3,LPACCPowerModel)
@time results_bs_hourly_sp = hourly_bs_nw_sp(BE_grid_bs_mn_6010_6033_sp,gurobi_e_3,LPACCPowerModel)
obj_bs = [results_bs_hourly["$i"]["objective"] for i in 1:(n_hours*n_scenarios)]
obj_bs_sp = [results_bs_hourly_sp["$i"]["objective"] for i in 1:(n_hours*n_scenarios)]

sum(obj_bs)
sum(obj_bs_sp)


result_la = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limited_actions(BE_grid_bs_mn,LPACCPowerModel,gurobi_e_3; setting = s)




switches_results = Dict{String,Any}()
for i in 1:(n_hours*n_scenarios)
    switches_results["$(i)"] = Dict{String,Any}()
    for (sw_id,sw) in BE_grid_bs_mn["nw"]["$(i)"]["switch"]
        switches_results["$(i)"]["$sw_id"] = Dict{String,Any}()
        switches_results["$(i)"]["$sw_id"]["status"] = result_ZIL["solution"]["nw"]["$(i)"]["switch"]["$sw_id"]["status"]
    end
end
for i in 1:(n_hours*n_scenarios)
    println("Nw is $(i)")
    println("1 is $(switches_results["$i"]["1"])")
    println("2 is $(switches_results["$i"]["2"])")
    println("")
end

switch_couples_feas_check = _PMTP.compute_couples_of_switches_feas_check(BE_grid_bs_6010_6033)
feas_check = deepcopy(BE_grid_bs_6010_6033)
feas_check_auxiliary = deepcopy(BE_grid_bs_6010_6033)
feas_check["switch_couples"] = deepcopy(switch_couples_feas_check)
feas_check_auxiliary["switch_couples"] = deepcopy(switch_couples_feas_check)

feas_check_mn = make_multinetwork_time_series_tyndp_scenario(feas_check,n_scenarios,start_hour_simulation,end_hour_simulation,RES_time_series,Load_time_series,zones)
feas_check_auxiliary_mn = make_multinetwork_time_series_tyndp_scenario(feas_check_auxiliary,n_scenarios,start_hour_simulation,end_hour_simulation,RES_time_series,Load_time_series,zones)

feas_check_mn["hours"] = n_hours
feas_check_mn["scenarios"] = n_scenarios
feas_check_mn["limit_actions"] = 24
feas_check_auxiliary_mn["hours"] = n_hours
feas_check_auxiliary_mn["scenarios"] = n_scenarios
feas_check_auxiliary_mn["limit_actions"] = 24


function prepare_AC_grid_feasibility_check_stochastic_multistep(result_dict, input_dict, input_ac_check, switch_couples, extremes_dict, input_base, n_hours, n_scenarios)    
    orig_buses = maximum(parse.(Int, keys(input_base["bus"]))) + length(extremes_dict)
    for t in 1:(n_hours*n_scenarios)
        println("t is $(t)")
        for (sw_id,sw) in input_dict["nw"]["$t"]["switch"]
            if haskey(sw,"auxiliary") # Make sure ZILs are not included 
                aux =  deepcopy(input_ac_check["nw"]["$t"]["switch"][sw_id]["auxiliary"])
                orig = deepcopy(input_ac_check["nw"]["$t"]["switch"][sw_id]["original"])  
                for zil in eachindex(extremes_dict)
                    if sw["bus_split"] == extremes_dict[zil][1] && result_dict["solution"]["nw"]["$t"]["switch"]["$(switch_couples[sw_id]["switch_split"])"]["status"] == 1.0  # Making sure to reconnect everything to the original if the ZIL is connected
                        if result_dict["solution"]["nw"]["$t"]["switch"][sw_id]["status"] >= 0.9
                            if aux == "gen"
                                input_ac_check["nw"]["$t"]["gen"]["$(orig)"]["gen_bus"] = deepcopy(extremes_dict[zil][1])
                            elseif aux == "load"
                                input_ac_check["nw"]["$t"]["load"]["$(orig)"]["load_bus"] = deepcopy(extremes_dict[zil][1])
                            elseif aux == "branch"  
                                if input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] > orig_buses && switch_couples[sw_id]["bus_split"] == parse(Int64,zil)
                                    input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] = deepcopy(switch_couples[sw_id]["bus_split"])
                                elseif input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] > orig_buses && switch_couples[sw_id]["bus_split"] == parse(Int64,zil)
                                    input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] = deepcopy(switch_couples[sw_id]["bus_split"])
                                end
                            end
                            delete!(input_ac_check["nw"]["$t"]["switch"],sw_id)
                        else
                            delete!(input_ac_check["nw"]["$t"]["switch"],sw_id)
                        end
                    elseif sw["bus_split"] == extremes_dict[zil][1] && result_dict["solution"]["nw"]["$t"]["switch"]["$(switch_couples[sw_id]["switch_split"])"]["status"] == 0.0 # Reconnect everything to the split busbar
                        if result_dict["solution"]["nw"]["$t"]["switch"][sw_id]["status"] >= 0.9
                            if aux == "gen"
                                input_ac_check["nw"]["$t"]["gen"]["$(orig)"]["gen_bus"] = deepcopy(sw["t_bus"])
                            elseif aux == "load"
                                input_ac_check["nw"]["$t"]["load"]["$(orig)"]["load_bus"] = deepcopy(sw["t_bus"])
                            elseif aux == "branch" 
                                if input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] > orig_buses && switch_couples[sw_id]["bus_split"] == parse(Int64,zil) 
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] = deepcopy(sw["t_bus"])
                                elseif input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] > orig_buses && switch_couples[sw_id]["bus_split"] == parse(Int64,zil)
                                    if !haskey(input_ac_check["nw"]["$t"]["branch"]["$(orig)"],"checked")
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] = deepcopy(sw["t_bus"])
                                    end
                                end
                            end
                            delete!(input_ac_check["nw"]["$t"]["switch"],sw_id)
                        else
                            delete!(input_ac_check["nw"]["$t"]["switch"],sw_id)
                        end
                    end
                end
            end
        end
    end
    return input_ac_check
end
prepare_AC_grid_feasibility_check_stochastic_multistep(result_ZIL,feas_check_auxiliary_mn,feas_check_mn,switch_couples_feas_check,extremes_ZILs_ac_6010_6033,BE_grid_bs_6010_6033,n_hours,n_scenarios)
result_opf_check = _SPMTA.run_stochastic_acdc_opf(feas_check_mn,ACPPowerModel,ipopt; setting = s)

function hourly_opf_feas_check(grid,optimizer,formulation,s)
    results = Dict()
    for hour in 1:(n_hours*n_scenarios)
        hourly_grid = deepcopy(grid["nw"]["$hour"])
        hourly_results = _PMACDC.run_acdcopf(hourly_grid,formulation, optimizer; setting = s)
        results["$hour"] = deepcopy(hourly_results)
    end
    return results
end

results = Dict{String,Any}()
for hour in 1:(n_hours*n_scenarios)
    hourly_grid = deepcopy(feas_check_mn["nw"]["$hour"])
    hourly_results = _PMACDC.run_acdcopf(hourly_grid,ACPPowerModel, ipopt; setting = s)
    results["$hour"] = deepcopy(hourly_results)
end
obj = sum(results["$i"]["objective"] for i in 1:(n_hours*n_scenarios))
obj_fc = [results["$i"]["objective"] for i in 1:(n_hours*n_scenarios)]
obj_opf = [result_single_ac_opf["$i"]["objective"] for i in start_hour_simulation:end_hour_simulation]
obj_opf_lpac = [result_single_opf["$i"]["objective"] for i in start_hour_simulation:end_hour_simulation]

result_opf_check = hourly_opf_feas_check(feas_check_mn,ACPPowerModel,ipopt,s)


gurobi_e_3 = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "MIPGap" => 8e-3)# "time_limit" => 600)#r, "ScaleFlag"=>2, "NumericFocus"=>2) 
results_bs_single_hour = Dict{String,Any}()
results_bs_single_hour_sp = Dict{String,Any}()
for i in 1:(n_hours*n_scenarios)
    println("Hour $(i)")
    results_bs_single_hour["$(i)"] = _PMTP.run_acdcsw_AC_big_M_ZIL(BE_grid_bs_mn["nw"]["$(i)"],LPACCPowerModel,gurobi_e_3)
    results_bs_single_hour_sp["$(i)"] = _PMTP.run_acdcsw_AC_big_M_ZIL_sp(BE_grid_bs_mn_6010_6033_sp["nw"]["$(i)"],LPACCPowerModel,gurobi_e_3)
end
obj_bs_hour = [results_bs_single_hour["$i"]["objective"] for i in 1:(n_hours*n_scenarios)]
obj_bs_hour_sp = [results_bs_single_hour_sp["$i"]["objective"] for i in 1:(n_hours*n_scenarios)]

sum(obj_bs_hour)








#=
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
=#
result_la_sw = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limited_actions_single_switch(BE_grid_bs_mn,LPACCPowerModel,gurobi_e_3; setting = s)
#=
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


result_opf["objective"]*10^5
result_ZIL["objective"]*10^5
result_ZIL_no_OTS["objective"]*10^5 
result_la["objective"]*10^5
result_la_no_OTS["objective"]*10^5
result_la_sw["objective"]*10^5
result_la_no_OTS_sw["objective"]*10^5
result_la_sw_all["objective"]*10^5
result_la_no_OTS_sw_all["objective"]*10^5


result_opf
result_ZIL
result_ZIL_no_OTS
result_la
result_la_no_OTS
result_la_sw
result_la_no_OTS_sw
result_la_sw_all
result_la_no_OTS_sw_all

result_opf["objective"]*10^5 - result_ZIL["objective"]*10^5
result_opf["objective"]*10^5 - result_ZIL_no_OTS["objective"]*10^5
result_opf["objective"]*10^5 - result_la["objective"]*10^5
result_opf["objective"]*10^5 - result_la_no_OTS["objective"]*10^5
result_opf["objective"]*10^5 - result_la_sw["objective"]*10^5
result_opf["objective"]*10^5 - result_la_no_OTS_sw["objective"]*10^5
result_opf["objective"]*10^5 - result_la_sw_all["objective"]*10^5
result_opf["objective"]*10^5 - result_la_no_OTS_sw_all["objective"]*10^5




json_string = JSON.json(result_opf)
open(joinpath(results_folder,"Results_OPF_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year)_$(n_hours)_hours_$(n_scenarios)_scenarios.json"),"w") do f 
    write(f, json_string) 
end

json_string = JSON.json(result_ZIL)
open(joinpath(results_folder,"Results_ZIL_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year)_$(n_hours)_hours_$(n_scenarios)_scenarios.json"),"w") do f 
    write(f, json_string) 
end

json_string = JSON.json(result_ZIL_no_OTS)
open(joinpath(results_folder,"Results_ZIL_no_OTS_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year)_$(n_hours)_hours_$(n_scenarios)_scenarios.json"),"w") do f 
    write(f, json_string) 
end

json_string = JSON.json(result_la)
open(joinpath(results_folder,"Results_la_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year)_$(n_hours)_hours_$(n_scenarios)_scenarios.json"),"w") do f 
    write(f, json_string) 
end

json_string = JSON.json(result_la_no_OTS)
open(joinpath(results_folder,"Results_la_no_OTS_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year)_$(n_hours)_hours_$(n_scenarios)_scenarios.json"),"w") do f 
    write(f, json_string) 
end

json_string = JSON.json(result_la_sw)
open(joinpath(results_folder,"Results_la_sw_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year)_$(n_hours)_hours_$(n_scenarios)_scenarios.json"),"w") do f 
    write(f, json_string) 
end


json_string = JSON.json(result_la_no_OTS_sw)
open(joinpath(results_folder,"Results_la_no_OTS_sw_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year)_$(n_hours)_hours_$(n_scenarios)_scenarios.json"),"w") do f 
    write(f, json_string) 
end

json_string = JSON.json(result_la_sw_all)
open(joinpath(results_folder,"Results_la_sw_all_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year)_$(n_hours)_hours_$(n_scenarios)_scenarios.json"),"w") do f 
    write(f, json_string) 
end

json_string = JSON.json(result_la_no_OTS_sw_all)
open(joinpath(results_folder,"Results_la_no_OTS_sw_all_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year)_$(n_hours)_hours_$(n_scenarios)_scenarios.json"),"w") do f 
    write(f, json_string) 
end
=#