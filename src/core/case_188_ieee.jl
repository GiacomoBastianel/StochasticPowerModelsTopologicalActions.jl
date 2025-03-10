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
input_folder = dirname(dirname(@__DIR__))
test_case_file = joinpath(input_folder,"data_sources/pglib_opf_case118_ieee.m")
test_case = _PM.parse_file(test_case_file)

total_load = 0
for (l_id,l) in test_case["load"]
    total_load += l["pd"]
end
for (l_id,l) in test_case["load"]
    l["power_portion"] = l["pd"]/total_load
end

for (g_id,g) in test_case["gen"]
    println("Gen $g_id, cost is $(g["cost"]), generation is $(result_bs_69["solution"]["gen"][g_id]["pg"])")
end

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

Gaussian_samples_file = joinpath(folder_data,"Gaussian_samples_8_Offshore_wind_$(year_wind)_Elia.json")
Gaussian_samples = JSON.parsefile(Gaussian_samples_file)
Gaussian_samples["1"]

Elia_OFW_file = joinpath(folder_data,"Offshore_wind_$(year_wind)_Elia_sorted.json")
Elia_OFW = JSON.parsefile(Elia_OFW_file)

differences_gen = [(Elia_OFW[i]["dayahead11hforecast"] - Elia_OFW[i]["measured"]) for i in 1:length(Elia_OFW) if Elia_OFW[i]["minute"] == "00"]
scatter(differences_gen[1:24],ylabel = "Difference for OFW in Belgium [MW]",xlabel = "Hour",title = "Offshore wind forecast vs measured (>0 -> forecast > measured)",ylabelfontsize = 9, xticks = 1:24, titlefontsize = 9, xlabelfontsize = 7, xtickfontsize = 7, legend = false, grid = :none)

Load_2024_file = joinpath(folder_data,"Elia_load_$(year_wind).json")
Load_2024 = JSON.parsefile(Load_2024_file)

#########################################################################################
n_hours = 24
start_hour_simulation = 1
end_hour_simulation = 24
hours = collect(start_hour_simulation:end_hour_simulation)
n_scenarios = 8
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
res_time_series_hour = Dict{String,Any}()
_SPMTA.create_RES_time_series(test_case_bs,res_time_series_hour,Wind_data,n_scenarios,start_hour_simulation,end_hour_simulation)

gen_time_series_hour = Dict{String,Any}()
_SPMTA.create_gen_time_series_tyndp_scenarios(test_case_bs,gen_time_series_hour, Wind_data, RES_time_series,start_hour_simulation,end_hour_simulation,n_scenarios)

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
