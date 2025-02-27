using PowerModels; const _PM = PowerModels
using PowerModelsACDC; const _PMACDC = PowerModelsACDC
import PowerModelsTopologicalActionsII; const _PMTP = PowerModelsTopologicalActionsII
using FlexPlan; const _FP = FlexPlan
using Gurobi
using Ipopt
using JSON
using Plots
import StochasticPowerModelsTopologicalActions; const _SPMTA = StochasticPowerModelsTopologicalActions
using JuMP
using Juniper
using HSL_jll
using MathOptInterface

gurobi = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "time_limit" => 600,"MIPGap" => 2e-2)#r, "ScaleFlag"=>2, "NumericFocus"=>2) 
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

n_hours = 24
start_hour_simulation = 6010
end_hour_simulation = 6033
hours = collect(start_hour_simulation:end_hour_simulation)
n_scenarios = 8

#########################################################################################
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
    h = start_hour_simulation + i - 1
    hw = hours_wind[i]   
    Wind_data["$h"] = Dict{String,Any}()
    Wind_data["$h"]["most_recent_forecast_pu"] = Elia_OFW[hw]["mostrecentforecast"]/Elia_OFW[hw]["monitoredcapacity"]
    Wind_data["$h"]["measured_pu"] = Elia_OFW[hw]["measured"]/Elia_OFW[hw]["monitoredcapacity"]
    Wind_data["$h"]["P50_11hforecast_pu"] = Elia_OFW[hw]["dayahead11hforecast"]/Elia_OFW[hw]["monitoredcapacity"]
    Wind_data["$h"]["samples_pu"] = Gaussian_samples["$hw"]["samples_pu"]
    Wind_data["$h"]["pdf_normalized"] = Gaussian_samples["$hw"]["pdf_normalized"]
    Wind_data["$h"]["Elia_timestep"] = hours_wind[i]
end

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
_SPMTA.add_dimensions!(BE_grid_6010_6033,n_scenarios,n_hours)
BE_grid_6010_6033["limit_actions"] = 24

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
#########################################################################################

function create_RES_time_series(grid,res_dict,scenario_samples_dict,n_scenarios,start_hour_simulation,end_hour_simulation)
    count_ = 0
    for (g_id,g) in grid["gen"]
        res_dict[g_id] = Dict{String,Any}()
        for i in start_hour_simulation:end_hour_simulation
            hour = i - start_hour_simulation + 1
            res_dict[g_id]["$i"] = Dict{String,Any}()
            if n_scenarios > 1
                if g["type"] == "Offshore Wind" && g["zone"] == "BE00"
                    res_dict[g_id]["$i"]["P50_11hforecast_pu"] = scenario_samples_dict["$i"]["P50_11hforecast_pu"]
                    res_dict[g_id]["$i"]["most_recent_forecast_pu"] = scenario_samples_dict["$i"]["most_recent_forecast_pu"]
                    res_dict[g_id]["$i"]["measured_pu"] = scenario_samples_dict["$i"]["measured_pu"]
                    res_dict[g_id]["$i"]["pdf"] = []
                    res_dict[g_id]["$i"]["samples_pu"] = []
                    for s in 1:n_scenarios
                       push!(res_dict[g_id]["$i"]["pdf"],scenario_samples_dict["$i"]["pdf_normalized"][s])
                       push!(res_dict[g_id]["$i"]["samples_pu"],scenario_samples_dict["$i"]["samples_pu"][s])
                    end
                elseif g["type"] == "Offshore Wind" && g["zone"] != "BE00"
                    res_dict[g_id]["$i"]["P50_11hforecast_pu"] = scenario_samples_dict["$i"]["P50_11hforecast_pu"]
                    res_dict[g_id]["$i"]["most_recent_forecast_pu"] = scenario_samples_dict["$i"]["most_recent_forecast_pu"]
                    res_dict[g_id]["$i"]["measured_pu"] = scenario_samples_dict["$i"]["measured_pu"]
                    res_dict[g_id]["$i"]["pdf"] = []
                    res_dict[g_id]["$i"]["samples_pu"] = []
                    for s in 1:n_scenarios
                        push!(res_dict[g_id]["$i"]["pdf"],scenario_samples_dict["$i"]["pdf_normalized"][s])
                        push!(res_dict[g_id]["$i"]["samples_pu"],1.0)
                    end
                else
                    res_dict[g_id]["$i"]["P50_11hforecast_pu"] = scenario_samples_dict["$i"]["P50_11hforecast_pu"]
                    res_dict[g_id]["$i"]["most_recent_forecast_pu"] = scenario_samples_dict["$i"]["most_recent_forecast_pu"]
                    res_dict[g_id]["$i"]["measured_pu"] = scenario_samples_dict["$i"]["measured_pu"]
                    res_dict[g_id]["$i"]["pdf"] = []
                    res_dict[g_id]["$i"]["samples_pu"] = []
                    for s in 1:n_scenarios
                        push!(res_dict[g_id]["$i"]["pdf"],scenario_samples_dict["$i"]["pdf_normalized"][s])
                        push!(res_dict[g_id]["$i"]["samples_pu"],1.0)
                    end
                end
            else
                if g["type"] == "Offshore Wind" && g["zone"] == "BE00"
                    res_dict[g_id]["$i"]["P50_11hforecast_pu"] = scenario_samples_dict["$i"]["P50_11hforecast_pu"]
                    res_dict[g_id]["$i"]["most_recent_forecast_pu"] = scenario_samples_dict["$i"]["most_recent_forecast_pu"]
                    res_dict[g_id]["$i"]["measured_pu"] = scenario_samples_dict["$i"]["measured_pu"]
                    res_dict[g_id]["$i"]["pdf"] = 1.0
                    res_dict[g_id]["$i"]["samples_pu"] = 1.0
                elseif g["type"] == "Offshore Wind" && g["zone"] != "BE00"
                    res_dict[g_id]["$i"]["P50_11hforecast_pu"] = scenario_samples_dict["$i"]["P50_11hforecast_pu"]
                    res_dict[g_id]["$i"]["most_recent_forecast_pu"] = scenario_samples_dict["$i"]["most_recent_forecast_pu"]
                    res_dict[g_id]["$i"]["measured_pu"] = scenario_samples_dict["$i"]["measured_pu"]
                    res_dict[g_id]["$i"]["pdf"] = 1.0
                    res_dict[g_id]["$i"]["samples_pu"] = 1.0
                else
                    res_dict[g_id]["$i"]["P50_11hforecast_pu"] = scenario_samples_dict["$i"]["P50_11hforecast_pu"]
                    res_dict[g_id]["$i"]["most_recent_forecast_pu"] = scenario_samples_dict["$i"]["most_recent_forecast_pu"]
                    res_dict[g_id]["$i"]["measured_pu"] = scenario_samples_dict["$i"]["measured_pu"]
                    res_dict[g_id]["$i"]["pdf"] = 1.0
                    res_dict[g_id]["$i"]["samples_pu"] = 1.0
                end
            end
        end
    end
end

function create_gen_time_series_tyndp_scenario(grid,res_dict,RES_time_series, start_hour_simulation, end_hour_simulation)
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

function create_gen_time_series_tyndp_scenarios(grid,res_dict, wind_data, RES_time_series, start_hour_simulation, end_hour_simulation, n_scenarios)
    for (g_id,g) in grid["gen"]
        res_dict[g_id] = Dict{String,Any}()
        for i in start_hour_simulation:end_hour_simulation
            res_dict[g_id]["$i"] = Dict{String,Any}()
            for scenario_idx in 1:n_scenarios
                res_dict[g_id]["$i"]["$scenario_idx"] = Dict{String,Any}()
                if g["type"] == "Offshore Wind" && g["zone"] == "BE00"
                    res_dict[g_id]["$i"]["$scenario_idx"]["capacity_factor"] = wind_data["$i"]["samples_pu"][scenario_idx]
                elseif g["type"] == "Offshore Wind" && g["zone"] != "UK00"
                    res_dict[g_id]["$i"]["$scenario_idx"]["capacity_factor"] = RES_time_series["UK00"]["Offshore_wind"][i]
                elseif g["type"] == "Offshore Wind" && g["zone"] != "FR00"
                    res_dict[g_id]["$i"]["$scenario_idx"]["capacity_factor"] = RES_time_series["FR00"]["Offshore_wind"][i]
                elseif g["type"] == "Onshore Wind" && g["zone"] == "BE00"
                    res_dict[g_id]["$i"]["$scenario_idx"]["capacity_factor"] = RES_time_series["BE00"]["Onshore_wind"][i]
                elseif g["type"] == "Onshore Wind" && g["zone"] != "UK00"
                    res_dict[g_id]["$i"]["$scenario_idx"]["capacity_factor"] = RES_time_series["UK00"]["Onshore_wind"][i]
                elseif g["type"] == "Onshore Wind" && g["zone"] != "FR00"
                    res_dict[g_id]["$i"]["$scenario_idx"]["capacity_factor"] = RES_time_series["FR00"]["Onshore_wind"][i]
                elseif g["type"] == "Solar PV" && g["zone"] == "BE00"
                    res_dict[g_id]["$i"]["$scenario_idx"]["capacity_factor"] = RES_time_series["BE00"]["Solar_PV"][i]
                elseif g["type"] == "Solar PV" && g["zone"] != "UK00"
                    res_dict[g_id]["$i"]["$scenario_idx"]["capacity_factor"] = RES_time_series["UK00"]["Solar_PV"][i]
                elseif g["type"] == "Solar PV" && g["zone"] != "FR00"
                    res_dict[g_id]["$i"]["$scenario_idx"]["capacity_factor"] = RES_time_series["FR00"]["Solar_PV"][i]
                else
                    res_dict[g_id]["$i"]["$scenario_idx"]["capacity_factor"] = 1.0
                end
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
res_time_series_hour = Dict{String,Any}()
create_RES_time_series(BE_grid_bs_6010_6033,res_time_series_hour,Wind_data,n_scenarios,start_hour_simulation,end_hour_simulation)

gen_time_series_hour = Dict{String,Any}()
create_gen_time_series_tyndp_scenarios(BE_grid_bs_6010_6033,gen_time_series_hour, Wind_data, RES_time_series,start_hour_simulation,end_hour_simulation,n_scenarios)

load_time_series_hour = Dict{String,Any}()
add_load_time_series_tyndp_scenario(BE_grid_bs_6010_6033, load_time_series_hour, Load_time_series, start_hour_simulation, end_hour_simulation, n_scenarios)


time_series_hour = Dict{String,Any}()

function generate_input_dict_stochastic_optimization(dict,gen_time_series,load_time_series,start_hour_simulation,end_hour_simulation,scenario_data)
    dict["gen"] = gen_time_series
    dict["load"] = load_time_series
    dict["scenario_probability"] = Dict{String,Any}()
    for i in start_hour_simulation:end_hour_simulation
        dict["scenario_probability"]["$i"] = deepcopy(scenario_data["$i"]["pdf_normalized"])
    end
    return dict
end

generate_input_dict_stochastic_optimization(time_series_hour,gen_time_series_hour,load_time_series_hour,start_hour_simulation,end_hour_simulation,Wind_data)
#########################################################################################

_SPMTA.add_hour_scenario_data(BE_grid_bs_6010_6033, n_hours, n_scenarios)
_SPMTA.add_hour_scenario_data(BE_grid_6010_6033, n_hours, n_scenarios)


function add_hour_scenario_probability_tyndp_scenario(data,hour,index,scenario_idx,time_series,start_hour_simulation)
    nw_hour = hour - start_hour_simulation + 1
    data["nw"]["$index"]["hour"] = nw_hour
    data["nw"]["$index"]["hour_original"] = hour
    data["nw"]["$index"]["scenario"] = scenario_idx
    data["nw"]["$index"]["hour_scenario_index"] = [nw_hour,scenario_idx]
    data["nw"]["$index"]["probability"] = time_series["scenario_probability"]["$hour"][scenario_idx]
end

function make_multinetwork_time_series_tyndp_scenarios(
    sn_data::Dict{String,Any},n_scenarios,start_hour_simulation,end_hour_simulation,time_series,zones;
    global_keys = ["hours","scenarios","name","per_unit","source_type","source_version"],
    check_dim::Bool = true,
    )

    mn_data = Dict{String,Any}("nw"=>Dict{String,Any}())
    _FP._add_mn_global_values!(mn_data, sn_data, global_keys)
    #template_nw = _make_template_nw(sn_data, global_keys)
    for hour in start_hour_simulation:end_hour_simulation
        nw_hour = hour - start_hour_simulation + 1
        for scenario_idx in 1:n_scenarios
            n = (nw_hour - 1)*n_scenarios + scenario_idx
            mn_data["nw"]["$n"] = deepcopy(sn_data)#_build_nw(template_nw, sn_data, time_series_idx; share_data = true)
            add_hour_scenario_probability_tyndp_scenario(mn_data,hour,n,scenario_idx,time_series,start_hour_simulation)
            fix_hourly_load_nw(mn_data["nw"]["$n"],hour,zones,time_series,scenario_idx) 
            fix_gen_time_series_nw(mn_data["nw"]["$n"],hour,zones,time_series,scenario_idx)
        end
    end
    mn_data["scenarios"] = n_scenarios
    mn_data["hours"] = n_hours
    return mn_data
end

function fix_hourly_load_nw(grid,hour,zones,load_time_series,scenario_idx) 
    for zone in zones
        for (l_id,l) in grid["load"]
            if l["zone"] == zone
                l["pd"] = deepcopy(load_time_series["load"][l_id]["$hour"]["$scenario_idx"]["pd"]) #pu
                l["qd"] = deepcopy(l["pd"]/20) #pu
            end
        end   
    end
end

function fix_gen_time_series_nw(grid,hour,zones,res_time_series,scenario_idx)
    for zone in zones
        for (g_id,g) in grid["gen"]
            g["pmax"] = g["installed_capacity"]*res_time_series["gen"][g_id]["$hour"]["$scenario_idx"]["capacity_factor"] #pu
        end
    end
end

function fix_res_time_series_measured(grid,hour,zones,res_time_series,P_value)
    for zone in zones
        for (g_id,g) in grid["gen"]
            if g["zone"] == zone
                if g["type"] == "Onshore Wind" 
                    g["pmax"] = g["installed_capacity"]*res_time_series[zone]["Onshore_wind"][hour] #pu
                elseif g["type"] == "Offshore Wind" 
                    if zone == "BE00"
                        g["pmax"] = g["installed_capacity"]*P_value #pu
                    else
                        g["pmax"] = g["installed_capacity"]*res_time_series[zone]["Offshore_wind"][hour] #pu
                    end
                elseif g["type"] == "Solar PV" 
                    g["pmax"] = g["installed_capacity"]*res_time_series[zone]["Solar_PV"][hour] #pu
                end
            end
        end
    end
end

BE_grid_bs_opf_mn_6010_6033 = make_multinetwork_time_series_tyndp_scenarios(BE_grid_bs_6010_6033,n_scenarios,start_hour_simulation,end_hour_simulation,time_series_hour,zones)
BE_grid_opf_mn_6010_6033 = make_multinetwork_time_series_tyndp_scenarios(BE_grid_lpac_6010_6033,n_scenarios,start_hour_simulation,end_hour_simulation,time_series_hour,zones)

#=
count_ = 0
for nw in start_hour_simulation:end_hour_simulation
    count_ += 1
    BE_grid_bs_opf_mn_6010_6033["nw"]["$count_"]["probability"] = 1
end
=#
result_opf = _SPMTA.run_stochastic_acdc_opf(BE_grid_bs_opf_mn_6010_6033,LPACCPowerModel,gurobi; setting = s)
result_ac_opf = _SPMTA.run_stochastic_acdc_opf(BE_grid_opf_mn_6010_6033,ACPPowerModel,ipopt; setting = s)

########################################################################################################

gurobi = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "time_limit" => 600,"MIPGap" => 1e-2)#r, "ScaleFlag"=>2, "NumericFocus"=>2) 

result_ZIL = _SPMTA.run_stochastic_acdcsw_AC_ZIL(BE_grid_bs_opf_mn_6010_6033,LPACCPowerModel,gurobi; setting = s)
BE_grid_bs_opf_mn_6010_6033["limit_actions"] = 24
result_ZIL_la = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limited_actions(BE_grid_bs_opf_mn_6010_6033,LPACCPowerModel,gurobi; setting = s)

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

function prepare_starting_value_dict_nw(result,grid,start_hour_simulation,end_hour_simulation,n_scenarios)
    count_ = 0
    for hour in start_hour_simulation:end_hour_simulation
        count_ += 1
        for scenario_idx in 1:n_scenarios
            n = (count_ - 1)*n_scenarios + scenario_idx
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
end

function prepare_AC_grid_feasibility_check_stochastic_multistep(result_dict, input_dict, input_ac_check, switch_couples, extremes_dict, input_base, n_hours, n_scenarios)    
    orig_buses = maximum(parse.(Int, keys(input_base["bus"]))) + length(extremes_dict)
    for t in 1:(n_hours*n_scenarios)
        println("t is $(t)")
        for (sw_id,sw) in input_dict["nw"]["$t"]["switch"]
            if haskey(sw,"auxiliary") # Make sure ZILs are not included 
                aux =  deepcopy(input_ac_check["nw"]["$t"]["switch"][sw_id]["auxiliary"])
                orig = deepcopy(input_ac_check["nw"]["$t"]["switch"][sw_id]["original"])  
                for zil in eachindex(extremes_dict)
                    if haskey(input_ac_check["nw"]["$t"]["switch_couples"],sw_id)
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
    end
    return input_ac_check
end
feas_check_grid = deepcopy(BE_grid_bs_opf_mn_6010_6033)
feas_check_grid_auxiliary = deepcopy(BE_grid_bs_opf_mn_6010_6033)

prepare_AC_grid_feasibility_check_stochastic_multistep(result_ZIL,feas_check_grid,feas_check_grid_auxiliary,switches_couples_ac_6010_6033, extremes_ZILs_ac_6010_6033,BE_grid_6010_6033,n_hours,n_scenarios)
result_opf_check = _SPMTA.run_stochastic_acdc_opf(feas_check_grid,ACPPowerModel,ipopt; setting = s)




BE_grid_bs_mn_6010_6033_sp = deepcopy(BE_grid_bs_opf_mn_6010_6033)
prepare_starting_value_dict_nw(result_ac_opf,BE_grid_bs_mn_6010_6033_sp,start_hour_simulation,end_hour_simulation,n_scenarios)
result_ZIL_sp = _SPMTA.run_stochastic_acdcsw_AC_ZIL_sp(BE_grid_bs_mn_6010_6033_sp,LPACCPowerModel,gurobi; setting = s)
result_ZIL_sp_la = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limited_actions_sp(BE_grid_bs_mn_6010_6033_sp,LPACCPowerModel,gurobi; setting = s)

sw_1 = [result_ZIL["solution"]["nw"]["$n"]["switch"]["1"]["status"] for n in 1:n_hours*n_scenarios]
sw_1_la = [result_ZIL_la["solution"]["nw"]["$n"]["switch"]["1"]["status"] for n in 1:n_hours*n_scenarios]
sw_2 = [result_ZIL["solution"]["nw"]["$n"]["switch"]["2"]["status"] for n in 1:n_hours*n_scenarios]
sw_2_la = [result_ZIL_la["solution"]["nw"]["$n"]["switch"]["2"]["status"] for n in 1:n_hours*n_scenarios]

plot(sw_1,grid = :none, yticks = (0:1:1), xticks = :none,  label = "Busbar splitting",legend = :outertopright, title = "Zero Impedance Line 1")
plot!(sw_1_la, label = "Limited actions")

plot(sw_2,grid = :none, yticks = (0:1:1), xticks = :none,  label = "Busbar splitting",legend = :outertopright, title = "Zero Impedance Line 2")
plot!(sw_2_la, label = "Limited actions")
