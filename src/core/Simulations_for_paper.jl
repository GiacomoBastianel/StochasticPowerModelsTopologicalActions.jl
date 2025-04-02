using PowerModels; const _PM = PowerModels
using PowerModelsACDC; const _PMACDC = PowerModelsACDC
import PowerModelsTopologicalActionsII; const _PMTP = PowerModelsTopologicalActionsII
using FlexPlan; const _FP = FlexPlan
using Gurobi, Ipopt, JSON, Plots
import StochasticPowerModelsTopologicalActions; const _SPMTA = StochasticPowerModelsTopologicalActions
using JuMP, Juniper, HSL_jll, MathOptInterface

mip_gap = 1e-4
gurobi = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 120,"MIPGap" => mip_gap)#,"BarQCPConvTol"=>1e-4,"QCPDual" => 1)#r, "ScaleFlag"=>2, "NumericFocus"=>2) 
ipopt = JuMP.optimizer_with_attributes(Ipopt.Optimizer, "tol" => 1e-6, "print_level" => 0,"linear_solver" => "ma97")
juniper = JuMP.optimizer_with_attributes(Juniper.Optimizer, "nl_solver" => ipopt, "mip_solver" => gurobi, "time_limit" => 36000)

#########################################################################################
## Processing input data
input_folder = "/Users/giacomobastianel/.julia/dev/DIRECTIONS_WP4.jl/src/Step_1"

#########################################################################################
# Uploading pdf samples for offshore wind
year_wind = "2023"
folder_data = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Elia_data"
folder_results = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Deliverable_1_2_DIRECTIONS/Results/Synthetic_Belgian_grid"

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
# Belgium grid without energy island
BE_grid_2024_file = joinpath(dirname(dirname(input_folder)),"test_cases/DIRECTIONS_test_case_Step_1_no_OWF_UK_corrected_LPAC.json")
BE_grid_6010_6033 = _PM.parse_file(BE_grid_2024_file)

BE_grid_bs_6010_6033  = deepcopy(BE_grid_6010_6033)
BE_grid_opf_6010_6033 = deepcopy(BE_grid_6010_6033)

splitted_bus_ac = [26,261]
name_splitted_buses = "26_261"

BE_grid_bs_6010_6033,  switches_couples_ac_6010_6033,  extremes_ZILs_ac_6010_6033  = _PMTP.AC_busbar_split_more_buses(BE_grid_bs_6010_6033,splitted_bus_ac)
BE_grid_bs_6010_6033["switch"]["1"]["maximum_actions"] = 12
BE_grid_bs_6010_6033["switch"]["2"]["maximum_actions"] = 12

s = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true)
s_dual = Dict("output" => Dict("branch_flows" => true,"duals" => true), "conv_losses_mp" => true)

#########################################################################################
# Add dimensions for stochastic part
_SPMTA.add_dimensions!(BE_grid_bs_6010_6033,n_scenarios,n_hours)
_SPMTA.add_dimensions!(BE_grid_opf_6010_6033,n_scenarios,n_hours)

_SPMTA.add_hour_scenario_data(BE_grid_bs_6010_6033, n_hours, n_scenarios)
_SPMTA.add_hour_scenario_data(BE_grid_opf_6010_6033, n_hours, n_scenarios)

BE_grid_bs_mn_6010_6033 = _SPMTA.make_multinetwork_time_series_tyndp_scenarios(BE_grid_bs_6010_6033,n_hours,n_scenarios,start_hour_simulation,end_hour_simulation,time_series_hour,zones)
BE_grid_opf_mn_6010_6033 = _SPMTA.make_multinetwork_time_series_tyndp_scenarios(BE_grid_opf_6010_6033,n_hours,n_scenarios,start_hour_simulation,end_hour_simulation,time_series_hour,zones)

result_opf = _SPMTA.run_stochastic_acdc_opf(BE_grid_opf_mn_6010_6033,LPACCPowerModel,gurobi; setting = s)
result_ac_opf = _SPMTA.run_stochastic_acdc_opf(BE_grid_opf_mn_6010_6033,ACPPowerModel,ipopt; setting = s)

#########################################################################################
function make_multinetwork_time_series_opf_check(
    sn_data::Dict{String,Any},n_hours,n_scenarios,start_hour_simulation,end_hour_simulation,time_series,zones,wind_values;
    global_keys = ["hours","scenarios","name","per_unit","source_type","source_version"],
    check_dim::Bool = true,
    )

    mn_data = Dict{String,Any}("nw"=>Dict{String,Any}())
    _FP._add_mn_global_values!(mn_data, sn_data, global_keys)
    #template_nw = _make_template_nw(sn_data, global_keys)
    for hour in start_hour_simulation:end_hour_simulation
        scenario_idx = 1
        nw_hour = hour - start_hour_simulation + 1
        mn_data["nw"]["$nw_hour"] = deepcopy(sn_data)
        add_hour_opf_check(mn_data,hour,nw_hour,scenario_idx,time_series,start_hour_simulation)
        fix_hourly_load_nw(mn_data["nw"]["$nw_hour"],hour,zones,time_series,scenario_idx) 
        fix_gen_time_series_nw(mn_data["nw"]["$nw_hour"],hour,zones,time_series,scenario_idx)
        add_OFW_time_series(mn_data["nw"]["$nw_hour"],nw_hour,zones,wind_values) # this is just to check if it works, to be modified
    end
    mn_data["scenarios"] = n_scenarios
    mn_data["hours"] = n_hours
    return mn_data
end

function add_hour_opf_check(data,hour,index,scenario_idx,time_series,start_hour_simulation)
    nw_hour = hour - start_hour_simulation + 1
    data["nw"]["$index"]["hour"] = nw_hour
    data["nw"]["$index"]["hour_original"] = hour
    data["nw"]["$index"]["scenario"] = scenario_idx
    data["nw"]["$index"]["hour_scenario_index"] = [nw_hour,scenario_idx]
    data["nw"]["$index"]["probability"] = 1.0
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

function add_OFW_time_series(grid,hour,zones,wind_values)
    for zone in zones
        for (g_id,g) in grid["gen"]
            if g["type"] == "Offshore Wind" && g["zone"] == "BE00"
                g["pmax"] = g["installed_capacity"]*wind_values[hour] #pu
            end
        end
    end
end

BE_grid_bs_6010_6033_measured = deepcopy(BE_grid_bs_6010_6033)
BE_grid_opf_6010_6033_measured = deepcopy(BE_grid_opf_6010_6033)
BE_grid_bs_6010_6033_forecasted = deepcopy(BE_grid_bs_6010_6033)
BE_grid_opf_6010_6033_forecasted = deepcopy(BE_grid_opf_6010_6033)

BE_grid_bs_mn_6010_6033_measured    = make_multinetwork_time_series_opf_check(BE_grid_bs_6010_6033_measured,n_hours,n_scenarios,start_hour_simulation,end_hour_simulation,time_series_hour,zones,measured)
BE_grid_opf_mn_6010_6033_measured   = make_multinetwork_time_series_opf_check(BE_grid_opf_6010_6033_measured,n_hours,n_scenarios,start_hour_simulation,end_hour_simulation,time_series_hour,zones,measured)
BE_grid_bs_mn_6010_6033_forecasted  = make_multinetwork_time_series_opf_check(BE_grid_bs_6010_6033_measured,n_hours,n_scenarios,start_hour_simulation,end_hour_simulation,time_series_hour,zones,p_50_forecast)
BE_grid_opf_mn_6010_6033_forecasted = make_multinetwork_time_series_opf_check(BE_grid_opf_6010_6033_measured,n_hours,n_scenarios,start_hour_simulation,end_hour_simulation,time_series_hour,zones,p_50_forecast)

#########################################################################################
# Calling scenario and climate year
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
# Time series
res_time_series_hour = Dict{String,Any}()
_SPMTA.create_RES_time_series(BE_grid_bs_6010_6033,res_time_series_hour,Wind_data,n_scenarios,start_hour_simulation,end_hour_simulation)

gen_time_series_hour = Dict{String,Any}()
_SPMTA.create_gen_time_series_tyndp_scenarios(BE_grid_bs_6010_6033,gen_time_series_hour, Wind_data, RES_time_series,start_hour_simulation,end_hour_simulation,n_scenarios)

load_time_series_hour = Dict{String,Any}()
_SPMTA.add_load_time_series_tyndp_scenario(BE_grid_bs_6010_6033, load_time_series_hour, Load_time_series, start_hour_simulation, end_hour_simulation, n_scenarios)

time_series_hour = Dict{String,Any}()
_SPMTA.generate_input_dict_stochastic_optimization(time_series_hour,gen_time_series_hour,load_time_series_hour,start_hour_simulation,end_hour_simulation,Wind_data)

#########################################################################################
_SPMTA.add_hour_scenario_data(BE_grid_bs_6010_6033, n_hours, n_scenarios)
_SPMTA.add_hour_scenario_data(BE_grid_opf_6010_6033, n_hours, n_scenarios)

BE_grid_bs_mn_6010_6033 = _SPMTA.make_multinetwork_time_series_tyndp_scenarios(BE_grid_bs_6010_6033,n_hours,n_scenarios,start_hour_simulation,end_hour_simulation,time_series_hour,zones)
BE_grid_opf_mn_6010_6033 = _SPMTA.make_multinetwork_time_series_tyndp_scenarios(BE_grid_opf_6010_6033,n_hours,n_scenarios,start_hour_simulation,end_hour_simulation,time_series_hour,zones)

result_opf = _SPMTA.run_stochastic_acdc_opf(BE_grid_opf_mn_6010_6033,LPACCPowerModel,gurobi; setting = s)
#result_ac_opf = _SPMTA.run_stochastic_acdc_opf(BE_grid_opf_mn_6010_6033,ACPPowerModel,ipopt; setting = s)

result_ZIL = JSON.parsefile(joinpath(folder_results,"Results_ZIL_$(n_hours)_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year).json"))
result_ZIL_sp = JSON.parsefile(joinpath(folder_results,"Results_ZIL_sp_$(n_hours)_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year).json"))

bs_measured   = JSON.parsefile(joinpath(folder_results,"Results_BS_measured_$(n_hours)_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year).json"))
bs_forecasted = JSON.parsefile(joinpath(folder_results,"Results_BS_forecasted_$(n_hours)_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year).json"))
opf_forecasted   = JSON.parsefile(joinpath(folder_results,"Results_OPF_measured_$(n_hours)_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year).json"))
opf_measured = JSON.parsefile(joinpath(folder_results,"Results_OPF_forecasted_$(n_hours)_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year).json"))
result_opf_check_measured_with_forecasted_topology = JSON.parsefile(joinpath(folder_results,"Results_OPF_measured_with_forecasted_topology_$(n_hours)_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year).json"))

#########################################################################################
# Plotting wind time series
Wind_data["6010"]
p_50_forecast = [Wind_data["$hour"]["P50_11hforecast_pu"] for hour in start_hour_simulation:end_hour_simulation]
measured = [Wind_data["$hour"]["measured_pu"] for hour in start_hour_simulation:end_hour_simulation]
expected = [sum(Wind_data["$hour"]["pdf_normalized"][s]*Wind_data["$hour"]["samples_pu"][s] for s in 1:n_scenarios) for hour in start_hour_simulation:end_hour_simulation]
plot(measured, label = "measured", grid = :none, xlims = (1,24), xticks = (1:1:24), 
title = "Wind time series, hours $(start_hour_simulation)-$(end_hour_simulation), scenario $(scenario)$(year), cy $(climate_year)", xlabel = "hour", 
titlefontsize = 10, ylabel = "Capacity factor [-]", legend = :bottomright,ylims = (0,1))
plot!(expected, label = "expected", grid = :none)
plot!(p_50_forecast, label = "D-1 (11h) forecast", grid = :none)

result_figures_folder = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Deliverable_1_2_DIRECTIONS/Figures"
savefig(joinpath(result_figures_folder,"Wind_time_series_$(n_hours)_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year).svg")) 
savefig(joinpath(result_figures_folder,"Wind_time_series_$(n_hours)_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year).pdf")) 

#########################################################################################
# Running OPF
function prepare_AC_feasibility_check_stochastic_multistep(result_dict, input_dict, input_ac_check, switch_couples, extremes_dict, input_base, n_hours, n_scenarios)
    orig_buses = maximum(parse.(Int, keys(input_base["bus"])))
    println("Number of original buses is $orig_buses")
    for t in 1:(n_hours*n_scenarios)
        println("t is $(t)")
        for (sw_id,sw) in input_dict["nw"]["$t"]["switch"]
            if !haskey(sw,"auxiliary")
                println("SWITCH $sw_id, BUS $(sw["t_bus"])")
                if result_dict["solution"]["nw"]["$t"]["switch"][sw_id]["status"] >= 0.9
                    println("Switch $sw_id is closed, Connecting everything back, no busbar splitting on bus $(sw["bus_split"])")
                    #delete!(input_ac_check["bus"],"$(input_ac_check["switch"][sw_id]["t_bus"])")
                    for l in keys(switch_couples)
                        if switch_couples[l]["bus_split"] == sw["bus_split"]
                            println("SWITCH COUPLE IS $l")
                            #println("Starting from switch $(switch_couples[l]["f_sw"]), with t_bus $(input_ac_check["nw"]["$t"]["switch"]["$(switch_couples[l]["f_sw"])"]["t_bus"])")
                            #println("Then switch $(switch_couples[l]["t_sw"]), with t_bus $(input_ac_check["nw"]["$t"]["switch"]["$(switch_couples[l]["t_sw"])"]["t_bus"])")
                            if input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["f_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                println("WE GO WITH SWITCH $(switch_couples[l]["f_sw"])")
                                aux =  deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["f_sw"])"]["auxiliary"])
                                orig = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["f_sw"])"]["original"])
                                if aux == "gen"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["gen"]["$(orig)"]["gen_bus"])
                                    input_ac_check["nw"]["$t"]["gen"]["$(orig)"]["gen_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "load"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["load"]["$(orig)"]["load_bus"])
                                    input_ac_check["nw"]["$t"]["load"]["$(orig)"]["load_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "convdc"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["convdc"]["$(orig)"]["busac_i"])
                                    input_ac_check["nw"]["$t"]["convdc"]["$(orig)"]["busac_i"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "branch"                
                                    if input_dict["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"])
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                    elseif input_dict["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"])
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                    end
                                end
                            elseif input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["t_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                println("WE GO WITH SWITCH $(switch_couples[l]["t_sw"])")
                                println("----------------------------")
                                aux =  deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["t_sw"])"]["auxiliary"])
                                orig = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["t_sw"])"]["original"])
                                if aux == "gen"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["gen"]["$(orig)"]["gen_bus"])
                                    input_ac_check["nw"]["$t"]["gen"]["$(orig)"]["gen_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "load"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["load"]["$(orig)"]["load_bus"])
                                    input_ac_check["nw"]["$t"]["load"]["$(orig)"]["load_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "convdc"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["convdc"]["$(orig)"]["busac_i"])
                                    input_ac_check["nw"]["$t"]["convdc"]["$(orig)"]["busac_i"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "branch"                
                                    if input_dict["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"])
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                    elseif input_dict["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"])
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                    end
                                end
                            end
                        end
                    end
                elseif result_dict["solution"]["nw"]["$t"]["switch"][sw_id]["status"] <= 0.1
                    println("Switch $sw_id is open, busbar splitting on bus $(sw["bus_split"])")
                    delete!(input_ac_check["nw"]["$t"]["switch"],sw_id)
                    for l in keys(switch_couples)
                        if switch_couples[l]["bus_split"] == sw["bus_split"]
                            println("SWITCH COUPLE IS $l")
                            #println("Starting from switch $(switch_couples[l]["f_sw"]), with t_bus $(input_ac_check["nw"]["$t"]["switch"]["$(switch_couples[l]["f_sw"])"]["t_bus"])")
                            #println("Then switch $(switch_couples[l]["t_sw"]), with t_bus $(input_ac_check["nw"]["$t"]["switch"]["$(switch_couples[l]["t_sw"])"]["t_bus"])")
                            if result_dict["solution"]["nw"]["$t"]["switch"]["$(switch_couples["$l"]["switch_split"])"]["status"] >= 0.9
                                aux =  deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["auxiliary"])
                                orig = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["original"])
                                if aux == "gen"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["gen"]["$(orig)"]["gen_bus"])
                                    input_ac_check["nw"]["$t"]["gen"]["$(orig)"]["gen_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "load"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["load"]["$(orig)"]["load_bus"])
                                    input_ac_check["nw"]["$t"]["load"]["$(orig)"]["load_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "convdc"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["convdc"]["$(orig)"]["busac_i"])
                                    input_ac_check["nw"]["$t"]["convdc"]["$(orig)"]["busac_i"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "branch"                
                                    if input_dict["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"])
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                    elseif input_dict["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"])
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                    end
                                end
                            elseif result_dict["solution"]["nw"]["$t"]["switch"]["$(switch_couples["$l"]["switch_split"])"]["status"] <= 0.1
                                switch_t = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]) 
                                aux_t = switch_t["auxiliary"]
                                orig_t = switch_t["original"]
                                print([l,aux_t,orig_t],"\n")
                                if result_dict["solution"]["nw"]["$t"]["switch"]["$(switch_t["index"])"]["status"] <= 0.1
                                    delete!(input_ac_check["nw"]["$t"]["switch"],"$(switch_t["index"])")
                                elseif result_dict["solution"]["nw"]["$t"]["switch"]["$(switch_t["index"])"]["status"] >= 0.9
                                    if aux_t == "gen"
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["gen"]["$(orig_t)"]["gen_bus"])
                                        input_ac_check["nw"]["$t"]["gen"]["$(orig_t)"]["gen_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["gen"]["$(orig_t)"]["gen_bus"]],"\n")
                                    elseif aux_t == "load"
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["load"]["$(orig_t)"]["load_bus"])
                                        input_ac_check["nw"]["$t"]["load"]["$(orig_t)"]["load_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["load"]["$(orig_t)"]["load_bus"]],"\n")
                                    elseif aux_t == "convdc"
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["convdc"]["$(orig_t)"]["busac_i"])
                                        input_ac_check["nw"]["$t"]["convdc"]["$(orig_t)"]["busac_i"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["convdc"]["$(orig_t)"]["busac_i"]],"\n")
                                    elseif aux_t == "branch" 
                                        if input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                            delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"])
                                            input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                            print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"]],"\n")
                                        elseif input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                            delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"])
                                            input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                            print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"]],"\n")
                                        end
                                    end
                                end
                            
                                switch_f = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]) 
                                aux_f = switch_f["auxiliary"]
                                orig_f = switch_f["original"]
                                print([l,aux_f,orig_f],"\n")
                                if result_dict["solution"]["nw"]["$t"]["switch"]["$(switch_f["index"])"]["status"] <= 0.1
                                    delete!(input_ac_check["nw"]["$t"]["switch"],"$(switch_t["index"])")
                                else
                                    if aux_f == "gen"
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["gen"]["$(orig_f)"]["gen_bus"])
                                        input_ac_check["nw"]["$t"]["gen"]["$(orig_f)"]["gen_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["gen"]["$(orig_f)"]["gen_bus"]],"\n")
                                    elseif aux_f == "load"
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["load"]["$(orig_f)"]["load_bus"])
                                        input_ac_check["nw"]["$t"]["load"]["$(orig_f)"]["load_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["load"]["$(orig_f)"]["load_bus"]],"\n")
                                    elseif aux_f == "convdc"
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["convdc"]["$(orig_f)"]["busac_i"])
                                        input_ac_check["nw"]["$t"]["convdc"]["$(orig_f)"]["busac_i"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["convdc"]["$(orig_f)"]["busac_i"]],"\n")
                                    elseif aux_f == "branch"
                                        if input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                            delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["f_bus"])
                                            input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["f_bus"] = deepcopy(input_ac_check["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                            print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"]],"\n")
                                        elseif input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                            delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"])
                                            input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"] = deepcopy(input_ac_check["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                            print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"]],"\n")
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        input_ac_check["nw"]["$t"]["switch"] = Dict{String,Any}()
        input_ac_check["nw"]["$t"]["switch_couples"] = Dict{String,Any}()
    end
end

function run_stochastic_acdcsw_AC_ZIL_hourly_measured(grid, model, optimizer, n_hours,result; setting = s)
    for hour in 1:n_hours
        grid_hour = deepcopy(grid)
        grid_hour["hours"] = 1
        grid_hour["nw"]= Dict{String,Any}()
        grid_hour["nw"]["$hour"] = deepcopy(grid["nw"]["$hour"])  
        result["$hour"] = _SPMTA.run_stochastic_acdcsw_AC_ZIL_hourly(grid_hour,model,optimizer; setting = setting)
    end
    return result
end

bs_measured_hourly = Dict{String,Any}()
run_stochastic_acdcsw_AC_ZIL_hourly_measured(BE_grid_bs_mn_6010_6033_measured,LPACCPowerModel,gurobi,n_hours,bs_measured_hourly; setting = s)
sum(bs_measured_hourly["$i"]["objective"] for i in 1:n_hours)

bs_forecasted_hourly = Dict{String,Any}()
run_stochastic_acdcsw_AC_ZIL_hourly_measured(BE_grid_bs_mn_6010_6033_forecasted,LPACCPowerModel,gurobi,n_hours,bs_measured_hourly; setting = s)
sum(bs_forecasted_hourly["$i"]["objective"] for i in 1:n_hours)

folder_results = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Deliverable_1_2_DIRECTIONS/Results/Synthetic_Belgian_grid"
ZIL_la_sp = JSON.json(result_ZIL_sp_la)

bs_measured_hourly_json = JSON.json(bs_measured_hourly)
open(joinpath(folder_results,"Results_bs_measured_hourly_$(n_hours)_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year).json"),"w" ) do f
    write(f,bs_measured_hourly_json)
end

bs_ZIL_hourly = Dict{String,Any}()
run_stochastic_acdcsw_AC_ZIL_hourly(BE_grid_bs_mn_6010_6033,LPACCPowerModel,gurobi,n_hours,bs_measured_hourly; setting = s)
sum(bs_ZIL_hourly["$i"]["objective"] for i in 1:n_hours)



result_opf_measured = _SPMTA.run_stochastic_acdc_opf(BE_grid_opf_mn_6010_6033_measured,LPACCPowerModel,gurobi; setting = s)
result_opf_forecasted = _SPMTA.run_stochastic_acdc_opf(BE_grid_opf_mn_6010_6033_forecasted,LPACCPowerModel,gurobi; setting = s)

CHECK_result_ZIL   = deepcopy(BE_grid_bs_mn_6010_6033_measured)
CHECK_result_ZIL_auxiliary   = deepcopy(BE_grid_bs_mn_6010_6033_measured)

CHECK_result_ZIL_sp = deepcopy(BE_grid_bs_mn_6010_6033_measured)
CHECK_result_ZIL_sp_auxiliary = deepcopy(BE_grid_bs_mn_6010_6033_measured)

CHECK_result_bs_measured = deepcopy(BE_grid_bs_mn_6010_6033_measured)
CHECK_result_bs_measured_auxiliary = deepcopy(BE_grid_bs_mn_6010_6033_measured)

CHECK_result_bs_measured_hourly = deepcopy(BE_grid_bs_mn_6010_6033_measured)
CHECK_result_bs_measured_auxiliary_hourly = deepcopy(BE_grid_bs_mn_6010_6033_measured)

CHECK_result_bs_forecast = deepcopy(BE_grid_bs_mn_6010_6033_measured)
CHECK_result_bs_forecast_auxiliary = deepcopy(BE_grid_bs_mn_6010_6033_measured)


prepare_AC_feasibility_check_stochastic_multistep(result_ZIL,CHECK_result_ZIL,CHECK_result_ZIL_auxiliary,switches_couples_ac_6010_6033, extremes_ZILs_ac_6010_6033,BE_grid_6010_6033,n_hours,1)
OPF_CHECK_result_ZIL = _SPMTA.run_stochastic_acdc_opf(CHECK_result_ZIL_auxiliary,LPACCPowerModel,gurobi; setting = s)

prepare_AC_feasibility_check_stochastic_multistep(result_ZIL_sp,CHECK_result_ZIL_sp,CHECK_result_ZIL_sp_auxiliary,switches_couples_ac_6010_6033, extremes_ZILs_ac_6010_6033,BE_grid_6010_6033,n_hours,1)
OPF_CHECK_result_ZIL_sp = _SPMTA.run_stochastic_acdc_opf(CHECK_result_ZIL_sp_auxiliary,LPACCPowerModel,gurobi; setting = s)

prepare_AC_feasibility_check_stochastic_multistep(bs_forecasted,CHECK_result_bs_forecast,CHECK_result_bs_forecast_auxiliary,switches_couples_ac_6010_6033, extremes_ZILs_ac_6010_6033,BE_grid_6010_6033,n_hours,1)
OPF_CHECK_result_forecast = _SPMTA.run_stochastic_acdc_opf(CHECK_result_bs_forecast_auxiliary,LPACCPowerModel,gurobi; setting = s)

function prepare_AC_feasibility_check_stochastic_multistep_hourly(result_dict, input_dict, input_ac_check, switch_couples, extremes_dict, input_base, n_hours)
    orig_buses = maximum(parse.(Int, keys(input_base["bus"])))
    println("Number of original buses is $orig_buses")
    for t in 1:n_hours
        println("t is $(t)")
        for (sw_id,sw) in input_dict["nw"]["$t"]["switch"]
            if !haskey(sw,"auxiliary")
                println("SWITCH $sw_id, BUS $(sw["t_bus"])")
                if result_dict["$t"]["solution"]["nw"]["$t"]["switch"][sw_id]["status"] >= 0.9
                    println("Switch $sw_id is closed, Connecting everything back, no busbar splitting on bus $(sw["bus_split"])")
                    #delete!(input_ac_check["bus"],"$(input_ac_check["switch"][sw_id]["t_bus"])")
                    for l in keys(switch_couples)
                        if switch_couples[l]["bus_split"] == sw["bus_split"]
                            println("SWITCH COUPLE IS $l")
                            #println("Starting from switch $(switch_couples[l]["f_sw"]), with t_bus $(input_ac_check["nw"]["$t"]["switch"]["$(switch_couples[l]["f_sw"])"]["t_bus"])")
                            #println("Then switch $(switch_couples[l]["t_sw"]), with t_bus $(input_ac_check["nw"]["$t"]["switch"]["$(switch_couples[l]["t_sw"])"]["t_bus"])")
                            if input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["f_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                println("WE GO WITH SWITCH $(switch_couples[l]["f_sw"])")
                                aux =  deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["f_sw"])"]["auxiliary"])
                                orig = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["f_sw"])"]["original"])
                                if aux == "gen"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["gen"]["$(orig)"]["gen_bus"])
                                    input_ac_check["nw"]["$t"]["gen"]["$(orig)"]["gen_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "load"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["load"]["$(orig)"]["load_bus"])
                                    input_ac_check["nw"]["$t"]["load"]["$(orig)"]["load_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "convdc"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["convdc"]["$(orig)"]["busac_i"])
                                    input_ac_check["nw"]["$t"]["convdc"]["$(orig)"]["busac_i"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "branch"                
                                    if input_dict["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"])
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                    elseif input_dict["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"])
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                    end
                                end
                            elseif input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["t_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                println("WE GO WITH SWITCH $(switch_couples[l]["t_sw"])")
                                println("----------------------------")
                                aux =  deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["t_sw"])"]["auxiliary"])
                                orig = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["t_sw"])"]["original"])
                                if aux == "gen"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["gen"]["$(orig)"]["gen_bus"])
                                    input_ac_check["nw"]["$t"]["gen"]["$(orig)"]["gen_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "load"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["load"]["$(orig)"]["load_bus"])
                                    input_ac_check["nw"]["$t"]["load"]["$(orig)"]["load_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "convdc"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["convdc"]["$(orig)"]["busac_i"])
                                    input_ac_check["nw"]["$t"]["convdc"]["$(orig)"]["busac_i"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "branch"                
                                    if input_dict["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"])
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                    elseif input_dict["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"])
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                    end
                                end
                            end
                        end
                    end
                elseif result_dict["$t"]["solution"]["nw"]["$t"]["switch"][sw_id]["status"] <= 0.1
                    println("Switch $sw_id is open, busbar splitting on bus $(sw["bus_split"])")
                    delete!(input_ac_check["nw"]["$t"]["switch"],sw_id)
                    for l in keys(switch_couples)
                        if switch_couples[l]["bus_split"] == sw["bus_split"]
                            println("SWITCH COUPLE IS $l")
                            #println("Starting from switch $(switch_couples[l]["f_sw"]), with t_bus $(input_ac_check["nw"]["$t"]["switch"]["$(switch_couples[l]["f_sw"])"]["t_bus"])")
                            #println("Then switch $(switch_couples[l]["t_sw"]), with t_bus $(input_ac_check["nw"]["$t"]["switch"]["$(switch_couples[l]["t_sw"])"]["t_bus"])")
                            if result_dict["$t"]["solution"]["nw"]["$t"]["switch"]["$(switch_couples["$l"]["switch_split"])"]["status"] >= 0.9
                                aux =  deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["auxiliary"])
                                orig = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["original"])
                                if aux == "gen"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["gen"]["$(orig)"]["gen_bus"])
                                    input_ac_check["nw"]["$t"]["gen"]["$(orig)"]["gen_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "load"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["load"]["$(orig)"]["load_bus"])
                                    input_ac_check["nw"]["$t"]["load"]["$(orig)"]["load_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "convdc"
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["convdc"]["$(orig)"]["busac_i"])
                                    input_ac_check["nw"]["$t"]["convdc"]["$(orig)"]["busac_i"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "branch"                
                                    if input_dict["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"])
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                    elseif input_dict["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"])
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                    end
                                end
                            elseif result_dict["$t"]["solution"]["nw"]["$t"]["switch"]["$(switch_couples["$l"]["switch_split"])"]["status"] <= 0.1
                                switch_t = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]) 
                                aux_t = switch_t["auxiliary"]
                                orig_t = switch_t["original"]
                                print([l,aux_t,orig_t],"\n")
                                if result_dict["$t"]["solution"]["nw"]["$t"]["switch"]["$(switch_t["index"])"]["status"] <= 0.1
                                    delete!(input_ac_check["nw"]["$t"]["switch"],"$(switch_t["index"])")
                                elseif result_dict["$t"]["solution"]["nw"]["$t"]["switch"]["$(switch_t["index"])"]["status"] >= 0.9
                                    if aux_t == "gen"
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["gen"]["$(orig_t)"]["gen_bus"])
                                        input_ac_check["nw"]["$t"]["gen"]["$(orig_t)"]["gen_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["gen"]["$(orig_t)"]["gen_bus"]],"\n")
                                    elseif aux_t == "load"
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["load"]["$(orig_t)"]["load_bus"])
                                        input_ac_check["nw"]["$t"]["load"]["$(orig_t)"]["load_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["load"]["$(orig_t)"]["load_bus"]],"\n")
                                    elseif aux_t == "convdc"
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["convdc"]["$(orig_t)"]["busac_i"])
                                        input_ac_check["nw"]["$t"]["convdc"]["$(orig_t)"]["busac_i"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["convdc"]["$(orig_t)"]["busac_i"]],"\n")
                                    elseif aux_t == "branch" 
                                        if input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                            delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"])
                                            input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                            print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"]],"\n")
                                        elseif input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                            delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"])
                                            input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                            print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"]],"\n")
                                        end
                                    end
                                end
                            
                                switch_f = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]) 
                                aux_f = switch_f["auxiliary"]
                                orig_f = switch_f["original"]
                                print([l,aux_f,orig_f],"\n")
                                if result_dict["$t"]["solution"]["nw"]["$t"]["switch"]["$(switch_f["index"])"]["status"] <= 0.1
                                    delete!(input_ac_check["nw"]["$t"]["switch"],"$(switch_t["index"])")
                                else
                                    if aux_f == "gen"
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["gen"]["$(orig_f)"]["gen_bus"])
                                        input_ac_check["nw"]["$t"]["gen"]["$(orig_f)"]["gen_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["gen"]["$(orig_f)"]["gen_bus"]],"\n")
                                    elseif aux_f == "load"
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["load"]["$(orig_f)"]["load_bus"])
                                        input_ac_check["nw"]["$t"]["load"]["$(orig_f)"]["load_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["load"]["$(orig_f)"]["load_bus"]],"\n")
                                    elseif aux_f == "convdc"
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["convdc"]["$(orig_f)"]["busac_i"])
                                        input_ac_check["nw"]["$t"]["convdc"]["$(orig_f)"]["busac_i"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["convdc"]["$(orig_f)"]["busac_i"]],"\n")
                                    elseif aux_f == "branch"
                                        if input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                            delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["f_bus"])
                                            input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["f_bus"] = deepcopy(input_ac_check["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                            print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"]],"\n")
                                        elseif input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                            delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"])
                                            input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"] = deepcopy(input_ac_check["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                            print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"]],"\n")
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        input_ac_check["nw"]["$t"]["switch"] = Dict{String,Any}()
        input_ac_check["nw"]["$t"]["switch_couples"] = Dict{String,Any}()
    end
end

prepare_AC_feasibility_check_stochastic_multistep_hourly(bs_measured_hourly,CHECK_result_bs_measured_hourly,CHECK_result_bs_measured_auxiliary_hourly,switches_couples_ac_6010_6033, extremes_ZILs_ac_6010_6033,BE_grid_6010_6033,n_hours)
OPF_CHECK_result_measured_hourly = _SPMTA.run_stochastic_acdc_opf(CHECK_result_bs_measured_hourly,LPACCPowerModel,gurobi; setting = s)


function compute_hourly_costs_stochastic_multistep_simulations_check(grid,result,start_hour_simulation,end_hour_simulation,vector)
    for hour in start_hour_simulation:end_hour_simulation
        hourly_cost_hour = 0
        nw = hour - start_hour_simulation + 1
        for (g_id,g) in grid["gen"]
            hourly_cost_hour += result["solution"]["nw"]["$nw"]["gen"][g_id]["pg"]*g["cost"][1]*100
        end
        push!(vector,hourly_cost_hour)
    end
end

function compute_hourly_costs_stochastic_multistep_simulations_check_hourly(grid,result,start_hour_simulation,end_hour_simulation,vector)
    for hour in start_hour_simulation:end_hour_simulation
        hourly_cost_hour = 0
        nw = hour - start_hour_simulation + 1
        for (g_id,g) in grid["gen"]
            hourly_cost_hour += result["$nw"]["solution"]["nw"]["$nw"]["gen"][g_id]["pg"]*g["cost"][1]*100
        end
        push!(vector,hourly_cost_hour)
    end
end


hourly_ZIL = []
hourly_ZIL_measured = []
hourly_ZIL_forecasted = []
hourly_ZIL_opf_measured = []

compute_hourly_costs_stochastic_multistep_simulations_check(BE_grid_6010_6033,       OPF_CHECK_result_ZIL,     start_hour_simulation,end_hour_simulation,hourly_ZIL)
compute_hourly_costs_stochastic_multistep_simulations_check_hourly(BE_grid_6010_6033,bs_measured_hourly,       start_hour_simulation,end_hour_simulation,hourly_ZIL_measured)
compute_hourly_costs_stochastic_multistep_simulations_check(BE_grid_6010_6033,       OPF_CHECK_result_forecast,start_hour_simulation,end_hour_simulation,hourly_ZIL_forecasted)
compute_hourly_costs_stochastic_multistep_simulations_check(BE_grid_6010_6033,       result_opf_measured,      start_hour_simulation,end_hour_simulation,hourly_ZIL_opf_measured)


rel_hourly_ZIL = (hourly_ZIL./hourly_ZIL_measured)
for i in 1:length(rel_hourly_ZIL)
    if rel_hourly_ZIL[i] < 1
        rel_hourly_ZIL[i] = 1
    end
end
rel_hourly_ZIL_measured = (hourly_ZIL_measured./hourly_ZIL_measured)
for i in 1:length(rel_hourly_ZIL_measured)
    if rel_hourly_ZIL_measured[i] < 1
        rel_hourly_ZIL_measured[i] = 1
    end
end
rel_hourly_ZIL_forecasted = (hourly_ZIL_forecasted./hourly_ZIL_measured)
for i in 1:length(rel_hourly_ZIL_forecasted)
    if rel_hourly_ZIL_forecasted[i] < 1
        rel_hourly_ZIL_forecasted[i] = 1
    end
end
rel_hourly_ZIL_opf_measured = (hourly_ZIL_opf_measured./hourly_ZIL_measured)
for i in 1:length(rel_hourly_ZIL_opf_measured)
    if rel_hourly_ZIL_opf_measured[i] < 1
        rel_hourly_ZIL_opf_measured[i] = 1
    end
end
rel_hourly_ZIL_percentage              = rel_hourly_ZIL              .- 1
rel_hourly_ZIL_measured_percentage     = rel_hourly_ZIL_measured     .- 1
rel_hourly_ZIL_forecasted_percentage   = rel_hourly_ZIL_forecasted   .- 1
rel_hourly_ZIL_opf_measured_percentage = rel_hourly_ZIL_opf_measured .- 1

sum(rel_hourly_ZIL_percentage             )
sum(rel_hourly_ZIL_measured_percentage    )
sum(rel_hourly_ZIL_forecasted_percentage  )
sum(rel_hourly_ZIL_opf_measured_percentage)

abs_diff_ZIL_percentage              = rel_hourly_ZIL.*hourly_ZIL_measured*100
abs_diff_ZIL_measured_percentage     = rel_hourly_ZIL_measured.*hourly_ZIL_measured*100
abs_diff_ZIL_forecasted_percentage   = rel_hourly_ZIL_forecasted.*hourly_ZIL_measured*100
abs_diff_ZIL_opf_measured_percentage = rel_hourly_ZIL_opf_measured.*hourly_ZIL_measured*100

sum(abs_diff_ZIL_percentage             )/sum(abs_diff_ZIL_measured_percentage    )
sum(abs_diff_ZIL_measured_percentage    )/sum(abs_diff_ZIL_measured_percentage    )
sum(abs_diff_ZIL_forecasted_percentage  )/sum(abs_diff_ZIL_measured_percentage    )
sum(abs_diff_ZIL_opf_measured_percentage)/sum(abs_diff_ZIL_measured_percentage    )

plot(rel_hourly_ZIL_measured_percentage,label = "Perfect foresight, busbar splitting",
    ylims = (-0.1,1),xticks = 1:24, xtickfontsize = 7, ylabel = "Hourly cost increase wrt perfect foresight busbar splitting [%]", 
    ylabelfontsize = 8,xlabel = "Hour", xlabelfontsize = 8, yticks = 0:0.2:1.0, #title = "Hourly cost increase wrt perfect foresight busbar splitting",
    legend = :topright, grid = :none)
plot!(rel_hourly_ZIL_percentage*100,label = "Scenario-based approach")
plot!(rel_hourly_ZIL_forecasted_percentage*100,label = "Day-ahead topology")
plot!(rel_hourly_ZIL_opf_measured_percentage*100,label = "Perfect foresight, OPF")

result_figures_folder = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Deliverable_1_2_DIRECTIONS/Figures"
savefig(joinpath(result_figures_folder,"Cost_increase_percentage_$(n_hours)_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year).svg")) 

###############################################################
# Analysis of the results
OPF_CHECK_result_ZIL    
bs_measured_hourly      
OPF_CHECK_result_forecast
result_opf_measured 

function compute_gen_capacity(data,results,start_hour,end_hour,dict)
    gen_type = []
    for (g_id,g) in data["gen"]
        push!(gen_type,g["type"])
    end
    types = unique(gen_type)

    for t in types
        dict["$t"] = 0
    end
    for hour in start_hour:end_hour
        if haskey(results,"$hour")
            for t in types
                for (g_id,g) in data["gen"]
                    if g["type"] == t
                        dict["$t"] += results["$hour"]["solution"]["gen"][g_id]["pg"]
                    end
                end
            end
        end
    end
end

function compute_gen_capacity_OPF(data,results,start_hour,end_hour,dict)
    gen_type = []
    for (g_id,g) in data["gen"]
        push!(gen_type,g["type"])
    end
    types = unique(gen_type)

    for hour in start_hour:end_hour
        if haskey(results["solution"]["nw"],"$hour")
            dict["$hour"] = Dict{String,Any}()
            for t in types
                dict["$hour"]["$t"] = 0
            end
            for t in types
                for (g_id,g) in data["gen"]
                    if g["type"] == t
                        dict["$hour"]["$t"] += results["solution"]["nw"]["$hour"]["gen"][g_id]["pg"]
                    end
                end
            end
        end
    end
end

function compute_gen_capacity_hourly(data,results,start_hour,end_hour,dict)
    gen_type = []
    for (g_id,g) in data["gen"]
        push!(gen_type,g["type"])
    end
    types = unique(gen_type)


    for hour in start_hour:end_hour
        if haskey(results,"$hour")
            dict["$hour"] = Dict{String,Any}()
            for t in types
                dict["$hour"]["$t"] = 0
            end
            for t in types
                for (g_id,g) in data["gen"]
                    if g["type"] == t
                        dict["$hour"]["$t"] += results["$hour"]["solution"]["nw"]["$hour"]["gen"][g_id]["pg"]
                    end
                end
            end
        end
    end
end


gen_opf_measured = Dict{String,Any}()
gen_bs_measured = Dict{String,Any}()
gen_opf_ZIL      = Dict{String,Any}()
gen_opf_forecast = Dict{String,Any}()

compute_gen_capacity_OPF(BE_grid_6010_6033,result_opf_measured,1,24,gen_opf_measured)
compute_gen_capacity_OPF(BE_grid_6010_6033,OPF_CHECK_result_ZIL,1,24,gen_opf_ZIL)
compute_gen_capacity_OPF(BE_grid_6010_6033,OPF_CHECK_result_forecast,1,24,gen_opf_forecast)
compute_gen_capacity_hourly(BE_grid_6010_6033,bs_measured_hourly,1,24,gen_bs_measured)


opf_ofw_measured = [gen_opf_measured["$i"]["Offshore Wind"]*100/10^3 for i in 1:24]
ofw_ZIL      = [gen_opf_ZIL["$i"]["Offshore Wind"]*100/10^3 for i in 1:24]
ofw_forecast = [gen_opf_forecast["$i"]["Offshore Wind"]*100/10^3 for i in 1:24]
bs_ofw_measured = [gen_bs_measured["$i"]["Offshore Wind"]*100/10^3 for i in 1:24]

plot(bs_ofw_measured,label = "Perfect foresight, busbar splitting",grid = :none,xticks = 1:24, xtickfontsize = 7, ylabel = "Offshore wind generation [GW]", 
    ylabelfontsize = 8,xlabel = "Hour", xlabelfontsize = 8, yticks = 0:1:6, #title = "Hourly cost increase wrt perfect foresight busbar splitting",
    legend = :topleft)
plot!(ofw_ZIL,label = "Scenario-based approach")
plot!(ofw_forecast,label = "D-1 (11h) forecast")
plot!(opf_ofw_measured,label = "Perfect foresight, OPF")
result_figures_folder = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Deliverable_1_2_DIRECTIONS/Figures"
savefig(joinpath(result_figures_folder,"Diff_wind_generation_$(n_hours)_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year).svg")) 

#####

function compute_gen_capacity_OPF_zone(data,results,start_hour,end_hour,zones,dict)
    for zone in zones
        dict["$zone"] = Dict{String,Any}()
        gen_type = []
        for (g_id,g) in data["gen"]
            push!(gen_type,g["type"])
        end
        types = unique(gen_type)

        for hour in start_hour:end_hour
            dict["$zone"]["$hour"] = Dict{String,Any}()
            if haskey(results["solution"]["nw"],"$hour")
                for t in types
                    dict["$zone"]["$hour"]["$t"] = 0
                    for (g_id,g) in data["gen"]
                        if g["zone"] == zone && g["type"] == t
                            dict["$zone"]["$hour"]["$t"] += results["solution"]["nw"]["$hour"]["gen"][g_id]["pg"]
                        end
                    end
                end
            end
        end
    end
end

function compute_gen_capacity_hourly_zone(data,results,start_hour,end_hour,zones,dict)
    for zone in zones
        dict["$zone"] = Dict{String,Any}()
        gen_type = []
        for (g_id,g) in data["gen"]
            push!(gen_type,g["type"])
        end
        types = unique(gen_type)

        for hour in start_hour:end_hour
            dict["$zone"]["$hour"] = Dict{String,Any}()
            if haskey(results,"$hour")
                dict["$zone"]["$hour"] = Dict{String,Any}()
                for t in types
                    dict["$zone"]["$hour"]["$t"] = 0
                    for (g_id,g) in data["gen"]
                        if g["zone"] == zone && g["type"] == t
                            dict["$zone"]["$hour"]["$t"] += results["$hour"]["solution"]["nw"]["$hour"]["gen"][g_id]["pg"]
                        end
                    end
                end
            end
        end
    end
end

gen_opf_measured_zone = Dict{String,Any}()
gen_bs_measured_zone = Dict{String,Any}()
gen_opf_ZIL_zone      = Dict{String,Any}()
gen_opf_forecast_zone = Dict{String,Any}()

compute_gen_capacity_OPF_zone(BE_grid_6010_6033,result_opf_measured,1,24,      zones,gen_opf_measured_zone)
compute_gen_capacity_OPF_zone(BE_grid_6010_6033,OPF_CHECK_result_ZIL,1,24,     zones,gen_opf_ZIL_zone)
compute_gen_capacity_OPF_zone(BE_grid_6010_6033,OPF_CHECK_result_forecast,1,24,zones,gen_opf_forecast_zone)
compute_gen_capacity_hourly_zone(BE_grid_6010_6033,bs_measured_hourly,1,24,    zones,gen_bs_measured_zone)

opf_ofw_measured_zone = [gen_opf_measured_zone["BE00"]["$i"]["Offshore Wind"]*100/10^3 for i in 1:24]
ofw_ZIL_zone      = [gen_opf_ZIL_zone["BE00"]["$i"]["Offshore Wind"]*100/10^3 for i in 1:24]
ofw_forecast_zone = [gen_opf_forecast_zone["BE00"]["$i"]["Offshore Wind"]*100/10^3 for i in 1:24]
bs_ofw_measured_zone = [gen_bs_measured_zone["BE00"]["$i"]["Offshore Wind"]*100/10^3 for i in 1:24]

plot(bs_ofw_measured_zone,label = "Perfect foresight, busbar splitting",grid = :none,xticks = 1:24, xtickfontsize = 7, ylabel = "Offshore wind generation Belgium [GW]", 
    ylabelfontsize = 8,xlabel = "Hour", xlabelfontsize = 8, yticks = 0:1:6, #title = "Hourly cost increase wrt perfect foresight busbar splitting",
    legend = :topright)
plot!(ofw_ZIL_zone,label = "Scenario-based approach")
plot!(ofw_forecast_zone,label = "D-1 (11h) forecast")
plot!(opf_ofw_measured_zone,label = "Perfect foresight, OPF")
result_figures_folder = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Deliverable_1_2_DIRECTIONS/Figures"
savefig(joinpath(result_figures_folder,"Diff_wind_generation_BE_$(n_hours)_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year).svg")) 
