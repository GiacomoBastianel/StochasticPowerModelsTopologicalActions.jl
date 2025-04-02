using PowerModels; const _PM = PowerModels
using PowerModelsACDC; const _PMACDC = PowerModelsACDC
import PowerModelsTopologicalActionsII; const _PMTP = PowerModelsTopologicalActionsII
using FlexPlan; const _FP = FlexPlan
using Gurobi, Ipopt, JSON, Plots
import StochasticPowerModelsTopologicalActions; const _SPMTA = StochasticPowerModelsTopologicalActions
using JuMP, Juniper, HSL_jll, MathOptInterface

mip_gap = 1e-2
gurobi = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 600,"MIPGap" => mip_gap,"BarHomogeneous" => 1)#,"BarQCPConvTol"=>1e-5,"QCPDual" => 1)#, "ScaleFlag"=>2, "NumericFocus"=>2) 
ipopt = JuMP.optimizer_with_attributes(Ipopt.Optimizer, "tol" => 1e-6, "print_level" => 0,"linear_solver" => "ma97")
juniper = JuMP.optimizer_with_attributes(Juniper.Optimizer, "nl_solver" => ipopt, "mip_solver" => gurobi, "time_limit" => 36000)

#########################################################################################
## Processing input data
input_folder = dirname(dirname(@__DIR__))
test_case_file = joinpath(input_folder,"data_sources/pglib_opf_case118_ieee.m")
test_case = _PM.parse_file(test_case_file)

#total_load = 0
#for (l_id,l) in test_case["load"]
#    total_load += l["pd"]
#end
#for (l_id,l) in test_case["load"]
#    l["power_portion"] = l["pd"]/total_load
#end

# -> Assigning the generators generating the most to offshore wind -> 30, 45
test_case["gen"]["30"]["type"] = "Offshore Wind"
test_case["gen"]["45"]["type"] = "Offshore Wind"
test_case["gen"]["30"]["cost"][1] = 600.0 
test_case["gen"]["45"]["cost"][1] = 600.0 
test_case["gen"]["30"]["gen_bus"]
test_case["gen"]["45"]["gen_bus"]

#########################################################################################
test_case_bs  = deepcopy(test_case)
test_case_opf = deepcopy(test_case)

opf_118 = _PM.solve_opf(test_case_opf, LPACCPowerModel, gurobi)
#########################################################################################
# Results from busbar splitting
result_bs_118 = JSON.parsefile("/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Busbar_splitting_metrics_results/case_118/split_one_bus_per_time.json")
obj_bs = [[result_bs_118["$i"]["objective"],i] for i in 1:length(result_bs_118) if result_bs_118["$i"]["objective"] != nothing]
findmin(obj_bs)
result_bs_118["69"]["objective"]/opf_118["objective"]

splitted_bus_ac = 69
test_case_bs,  switches_couples_ac,  extremes_ZILs_ac  = _PMTP.AC_busbar_split_AC_grid(test_case,splitted_bus_ac)
result_bs_69 = _PMTP.run_acdcsw_AC_grid_big_M(test_case_bs, LPACCPowerModel, gurobi)

#########################################################################################
# Uploading pdf samples for offshore wind and load data for Belgium
year_wind = "2024"
folder_data = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Elia_data"
folder_results = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Deliverable_1_2_DIRECTIONS/Results/case_118"
#start_hour_simulation = 1
#end_hour_simulation = 24

Gaussian_samples_file = joinpath(folder_data,"Gaussian_samples_8_Offshore_wind_$(year_wind)_Elia.json")
Gaussian_samples = JSON.parsefile(Gaussian_samples_file)
Gaussian_samples["1"]

Elia_OFW_file = joinpath(folder_data,"Offshore_wind_$(year_wind)_Elia_sorted.json")
Elia_OFW = JSON.parsefile(Elia_OFW_file)

# Only hours
differences_gen = [(Elia_OFW[i]["dayahead11hforecast"] - Elia_OFW[i]["measured"]) for i in 1:length(Elia_OFW) if Elia_OFW[i]["minute"] == "00"]
scatter(differences_gen[1:24],ylabel = "Difference for OFW in Belgium [MW]",xlabel = "Hour",title = "Offshore wind forecast vs measured (>0 -> forecast > measured)",ylabelfontsize = 9, xticks = 1:24, titlefontsize = 9, xlabelfontsize = 7, xtickfontsize = 7, legend = false, grid = :none)
capacity_factors_ofw = [Elia_OFW[i]["measured"]/Elia_OFW[i]["monitoredcapacity"] for i in 1:length(Elia_OFW) if Elia_OFW[i]["minute"] == "00"]
is = [i for i in 1:length(Elia_OFW) if Elia_OFW[i]["minute"] == "00"]
capacity_factors_118 = capacity_factors_ofw[start_hour_simulation:end_hour_simulation]

Load_2024_file = joinpath(folder_data,"Elia_load_$(year_wind).json")
Load_2024 = JSON.parsefile(Load_2024_file)
total_loads = [Load_2024[i]["totalload"] for i in 1:length(Load_2024)]
max_load = maximum(total_loads)

#########################################################################################
n_hours = 24
start_hour_simulation = 1
end_hour_simulation = 24
hours = collect(start_hour_simulation:end_hour_simulation)
n_scenarios = 1
#########################################################################################
## Processing input data
s = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true)
s_dual = Dict("output" => Dict("branch_flows" => true,"duals" => true), "conv_losses_mp" => true)

#########################################################################################
# Add dimensions for stochastic part
_SPMTA.add_dimensions!(test_case_bs,n_scenarios,n_hours)
_SPMTA.add_dimensions!(test_case_opf,n_scenarios,n_hours)

#########################################################################################
# Time series
Wind_data = Dict{String,Any}()
for i in 1:length(hours)
    h = start_hour_simulation + i - 1
    hw = is[i]   
    Wind_data["$h"] = Dict{String,Any}()
    Wind_data["$h"]["most_recent_forecast_pu"] = Elia_OFW[hw]["mostrecentforecast"]/Elia_OFW[hw]["monitoredcapacity"]
    Wind_data["$h"]["measured_pu"] = Elia_OFW[hw]["measured"]/Elia_OFW[hw]["monitoredcapacity"]
    Wind_data["$h"]["P50_11hforecast_pu"] = Elia_OFW[hw]["dayahead11hforecast"]/Elia_OFW[hw]["monitoredcapacity"]
    Wind_data["$h"]["samples_pu"] = Gaussian_samples["$hw"]["samples_pu"]
    Wind_data["$h"]["pdf_normalized"] = Gaussian_samples["$hw"]["pdf_normalized"]
    Wind_data["$h"]["Elia_timestep"] = is[i]
end

Load_data = Dict{String,Any}()
for i in 1:length(hours)
    h = start_hour_simulation + i - 1
    hw = is[i]   
    Load_data["$h"] = Dict{String,Any}()
    Load_data["$h"]["total_load"] = Load_2024[hw]["totalload"]
    Load_data["$h"]["total_load_pu"] = Load_2024[hw]["totalload"]/max_load
    Load_data["$h"]["Elia_timestep"] = is[i]
end

#########################################################################################
# OFW at gen 30 and 45
res_time_series_hour = Dict{String,Any}()
function create_RES_time_series_base(grid,res_dict,scenario_samples_dict,n_scenarios,start_hour_simulation,end_hour_simulation)
    count_ = 0
    for (g_id,g) in grid["gen"]
        res_dict[g_id] = Dict{String,Any}()
        for i in start_hour_simulation:end_hour_simulation
            hour = i - start_hour_simulation + 1
            res_dict[g_id]["$i"] = Dict{String,Any}()
            if n_scenarios > 1
                if haskey(g,"type") && g["type"] == "Offshore Wind" 
                    res_dict[g_id]["$i"]["P50_11hforecast_pu"] = scenario_samples_dict["$i"]["P50_11hforecast_pu"]
                    res_dict[g_id]["$i"]["most_recent_forecast_pu"] = scenario_samples_dict["$i"]["most_recent_forecast_pu"]
                    res_dict[g_id]["$i"]["measured_pu"] = scenario_samples_dict["$i"]["measured_pu"]
                    res_dict[g_id]["$i"]["pdf"] = []
                    res_dict[g_id]["$i"]["samples_pu"] = []
                    for s in 1:n_scenarios
                       push!(res_dict[g_id]["$i"]["pdf"],scenario_samples_dict["$i"]["pdf_normalized"][s])
                       push!(res_dict[g_id]["$i"]["samples_pu"],scenario_samples_dict["$i"]["samples_pu"][s])
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
                if haskey(g,"type")
                    if g["type"] == "Offshore Wind" 
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
end
create_RES_time_series_base(test_case_bs,res_time_series_hour,Wind_data,n_scenarios,start_hour_simulation,end_hour_simulation)

gen_time_series_hour = Dict{String,Any}()
function create_gen_time_series_base_scenarios(grid,res_dict, wind_data, RES_time_series, start_hour_simulation, end_hour_simulation, n_scenarios)
    for (g_id,g) in grid["gen"]
        res_dict[g_id] = Dict{String,Any}()
        for i in start_hour_simulation:end_hour_simulation
            res_dict[g_id]["$i"] = Dict{String,Any}()
            for scenario_idx in 1:n_scenarios
                res_dict[g_id]["$i"]["$scenario_idx"] = Dict{String,Any}()
                if haskey(g,"type")
                    if g["type"] == "Offshore Wind" 
                        res_dict[g_id]["$i"]["$scenario_idx"]["capacity_factor"] = wind_data["$i"]["samples_pu"][scenario_idx]
                    end
                else
                    res_dict[g_id]["$i"]["$scenario_idx"]["capacity_factor"] = 1.0
                end
            end
        end
    end
end
create_gen_time_series_base_scenarios(test_case_bs,gen_time_series_hour,Wind_data,n_scenarios,start_hour_simulation,end_hour_simulation,n_scenarios)

load_time_series_hour = Dict{String,Any}()
function add_load_time_series_base_scenario(grid, load_dict, grid_load, start_hour_simulation, end_hour_simulation, n_scenarios)
    for (l_id,l) in grid["load"]
        load_dict[l_id] = Dict{String,Any}()
        for h in start_hour_simulation:end_hour_simulation
            load_dict[l_id]["$h"] = Dict{String,Any}()
            for scenario in 1:n_scenarios 
                load_dict[l_id]["$h"]["$scenario"] = Dict{String,Any}()
                load_dict[l_id]["$h"]["$scenario"]["pd"] = grid_load["load"][l_id]["pd"]
            end 
        end
    end
end
add_load_time_series_base_scenario(test_case_bs, load_time_series_hour, test_case, start_hour_simulation, end_hour_simulation, n_scenarios)

time_series_hour = Dict{String,Any}()
_SPMTA.generate_input_dict_stochastic_optimization(time_series_hour,gen_time_series_hour,load_time_series_hour,start_hour_simulation,end_hour_simulation,Wind_data)

#########################################################################################
_SPMTA.add_hour_scenario_data(test_case_bs, n_hours, n_scenarios)
_SPMTA.add_hour_scenario_data(test_case_opf, n_hours, n_scenarios)


function add_hour_scenario_probability_scenario_base(data,hour,index,scenario_idx,time_series,start_hour_simulation)
    nw_hour = hour - start_hour_simulation + 1
    data["nw"]["$index"]["hour"] = nw_hour
    data["nw"]["$index"]["hour_original"] = hour
    data["nw"]["$index"]["scenario"] = scenario_idx
    data["nw"]["$index"]["hour_scenario_index"] = [nw_hour,scenario_idx]
    data["nw"]["$index"]["probability"] = time_series["scenario_probability"]["$hour"][scenario_idx]
end

function make_multinetwork_time_series_base_scenarios(
    sn_data::Dict{String,Any},n_hours,n_scenarios,start_hour_simulation,end_hour_simulation,time_series;
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
            add_hour_scenario_probability_scenario_base(mn_data,hour,n,scenario_idx,time_series,start_hour_simulation)
            fix_hourly_load_nw_base(mn_data["nw"]["$n"],hour,time_series,scenario_idx) 
            fix_gen_time_series_nw_base(mn_data["nw"]["$n"],hour,time_series,scenario_idx)
        end
    end
    mn_data["scenarios"] = n_scenarios
    mn_data["hours"] = n_hours
    return mn_data
end

function fix_hourly_load_nw_base(grid,hour,load_time_series,scenario_idx) 
    for (l_id,l) in grid["load"]
            l["pd"] = deepcopy(load_time_series["load"][l_id]["$hour"]["$scenario_idx"]["pd"]) #pu
            l["qd"] = deepcopy(l["pd"]/20) #pu
    end   
end

function fix_gen_time_series_nw_base(grid,hour,res_time_series,scenario_idx)
    for (g_id,g) in grid["gen"]
        g["pmax"] = g["pmax"]*res_time_series["gen"][g_id]["$hour"]["$scenario_idx"]["capacity_factor"] #pu
    end
end

test_case_bs_mn = make_multinetwork_time_series_base_scenarios(test_case_bs,n_hours,n_scenarios,start_hour_simulation,end_hour_simulation,time_series_hour)
test_case_opf_mn = make_multinetwork_time_series_base_scenarios(test_case_opf,n_hours,n_scenarios,start_hour_simulation,end_hour_simulation,time_series_hour)

test_case_opf_mn["nw"]["1"]["load"]["1"]
[test_case_opf_mn["nw"]["$i"]["load"]["1"]["pd"] for i in 1:2*n_scenarios]
[test_case_opf_mn["nw"]["$i"]["gen"]["30"]["pmax"] for i in 1:2*n_scenarios]


function run_hourly_opf(grid, model, optimizer; settings = s)
    result = Dict{String,Any}()
    for nw in 1:grid["hours"]
        result["$nw"] = _PM.solve_opf(grid["nw"]["$nw"],model,optimizer; setting = settings)
    end
    return result
end
result_opf_hourly = run_hourly_opf(test_case_opf_mn,LPACCPowerModel,gurobi,result_opf_hourly)

result_opf = _SPMTA.run_stochastic_acdc_opf(test_case_opf_mn,LPACCPowerModel,gurobi; setting = s)
result_bs = _SPMTA.run_stochastic_acdcsw_AC_ZIL_sp(test_case_bs_mn,LPACCPowerModel,gurobi; setting = s)
result_bs_hourly = _SPMTA.run_stochastic_acdcsw_AC_ZIL_hourly(test_case_bs_mn,LPACCPowerModel,gurobi; setting = s)




[test_case_opf_mn["nw"]["$i"]["gen"]["30"]["pmax"] for i in 1:2*n_scenarios]

















load_time_series_hour = Dict{String,Any}()
_SPMTA.add_load_time_series_tyndp_scenario(test_case_bs, load_time_series_hour, Load_time_series, start_hour_simulation, end_hour_simulation, n_scenarios)

time_series_hour = Dict{String,Any}()
_SPMTA.generate_input_dict_stochastic_optimization(time_series_hour,gen_time_series_hour,load_time_series_hour,start_hour_simulation,end_hour_simulation,Wind_data)

#########################################################################################
_SPMTA.add_hour_scenario_data(test_case_bs, n_hours, n_scenarios)
_SPMTA.add_hour_scenario_data(test_case_opf, n_hours, n_scenarios)

BE_grid_bs_mn_6010_6033 = _SPMTA.make_multinetwork_time_series_tyndp_scenarios(test_case_bs,n_hours,n_scenarios,start_hour_simulation,end_hour_simulation,time_series_hour,zones)
BE_grid_opf_mn_6010_6033 = _SPMTA.make_multinetwork_time_series_tyndp_scenarios(test_case_opf,n_hours,n_scenarios,start_hour_simulation,end_hour_simulation,time_series_hour,zones)

result_opf = _SPMTA.run_stochastic_acdc_opf(BE_grid_opf_mn_6010_6033,LPACCPowerModel,gurobi; setting = s)
#result_ac_opf = _SPMTA.run_stochastic_acdc_opf(BE_grid_opf_mn_6010_6033,ACPPowerModel,ipopt; setting = s)
