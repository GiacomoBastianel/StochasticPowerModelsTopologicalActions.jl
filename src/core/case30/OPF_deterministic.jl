using PowerModels; const _PM = PowerModels
using PowerModelsACDC; const _PMACDC = PowerModelsACDC
import PowerModelsTopologicalActionsII; const _PMTP = PowerModelsTopologicalActionsII
using FlexPlan; const _FP = FlexPlan
using Gurobi, Ipopt, JSON, Plots
import StochasticPowerModelsTopologicalActions; const _SPMTA = StochasticPowerModelsTopologicalActions
using JuMP, Juniper, HSL_jll, MathOptInterface, HiGHS

mip_gap = 1e-4
gurobi = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 300,"MIPGap" => mip_gap,"BarHomogeneous" => 1,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "ScaleFlag"=>2, "NumericFocus"=>2) 
gurobi_opf = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 600)#,"BarHomogeneous" => 1,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "ScaleFlag"=>2, "NumericFocus"=>2) 
ipopt = JuMP.optimizer_with_attributes(Ipopt.Optimizer, "tol" => 1e-6, "print_level" => 0,"linear_solver" => "ma97")
juniper = JuMP.optimizer_with_attributes(Juniper.Optimizer, "nl_solver" => ipopt, "mip_solver" => gurobi, "time_limit" => 36000)

#########################################################################################
## Processing input data
s = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true)
s_dual = Dict("output" => Dict("branch_flows" => true,"duals" => true), "conv_losses_mp" => true)

#########################################################################################
## Processing input data
input_folder = dirname(dirname(dirname(@__DIR__)))
test_case_file = joinpath(input_folder,"data_sources/pglib_opf_case30_ieee.m")
original_grid = _PM.parse_file(test_case_file)
#pm_original = _PM.instantiate_model(original_grid, LPACCPowerModel, _PM.build_opf)

test_case = _PM.parse_file(test_case_file)

function add_VOLL_generators(data)
    first_l = maximum(parse.(Int, keys(data["gen"])))
    count = 0
    for (b_id,b) in data["bus"]
        count += 1
        l = first_l + count
        data["gen"]["$l"] = deepcopy(data["gen"]["1"])
        #data["gen"]["$l"]["installed_capacity"] = 99.99
        data["gen"]["$l"]["gen_bus"] = parse(Int64,b_id) 
        data["gen"]["$l"]["pmax"] = 99.99
        #data["gen"]["$l"]["mbase"] = 9999
        data["gen"]["$l"]["source_id"][2] = deepcopy(l)
        #data["gen"]["$l"]["gen_type"] = "VOLL"
        data["gen"]["$l"]["index"] = l 
        #data["gen"]["$l"]["type"] = "VOLL"
        data["gen"]["$l"]["cost"][1] = 10000
    end
end
add_VOLL_generators(test_case)

test_case_opf = deepcopy(test_case)
opf_30 = _PM.solve_opf(test_case_opf, LPACCPowerModel, gurobi_opf)

#########################################################################################
# Hours
n_hours = 12
start_hour_simulation = 1
end_hour_simulation = 12
hours = collect(start_hour_simulation:end_hour_simulation)
one_scenario = 1

#########################################################################################
# Add dimensions for stochastic part
_SPMTA.add_dimensions!(test_case_opf,one_scenario,n_hours)

#########################################################################################
# Uploading pdf samples for offshore wind and load data for Belgium
year_wind = "2024"
folder_data = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Elia_data"
folder_results = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Deliverable_1_2_DIRECTIONS/Results/case_30"

Gaussian_samples = JSON.parsefile(joinpath(folder_data,"Gaussian_samples_8_Offshore_wind_$(year_wind)_Elia.json"))
Elia_OFW = JSON.parsefile(joinpath(folder_data,"Offshore_wind_$(year_wind)_Elia_sorted.json"))

# Only hours
differences_gen = [(Elia_OFW[i]["dayahead11hforecast"] - Elia_OFW[i]["measured"]) for i in 1:length(Elia_OFW) if Elia_OFW[i]["minute"] == "00"]
capacity_factors_ofw = [Elia_OFW[i]["measured"]/Elia_OFW[i]["monitoredcapacity"] for i in 1:length(Elia_OFW) if Elia_OFW[i]["minute"] == "00"]
is = [i for i in 1:length(Elia_OFW) if Elia_OFW[i]["minute"] == "00"]
capacity_factors_30 = capacity_factors_ofw[start_hour_simulation:end_hour_simulation]

Load_2024 = JSON.parsefile(joinpath(folder_data,"Elia_load_$(year_wind).json"))
total_loads = [Load_2024[i]["totalload"] for i in 1:length(Load_2024)]
max_load = maximum(total_loads)

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

measured_wind   = [Wind_data["$i"]["measured_pu"]  for i in 1:length(hours)]
forecasted_wind = [Wind_data["$i"]["P50_11hforecast_pu"] for i in 1:length(hours)]
load_pu = [Load_data["$i"]["total_load_pu"] for i in 1:length(hours)]

##############################################################
## Running simulations
# OPF
test_case_opf_replicate = _PM.replicate(test_case_opf, n_hours)
for (nw_id,nw) in test_case_opf_replicate["nw"]
    nw["probability"] = 1.0
    nw["per_unit"] = true
end
test_case_opf_mn_measured = deepcopy(test_case_opf_replicate)
test_case_opf_mn_forecasted = deepcopy(test_case_opf_replicate)
for i in 1:(n_hours*one_scenario)
    test_case_opf_mn_measured["nw"]["$i"]["gen"]["1"]["pmax"]   = deepcopy(test_case_opf_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*measured_wind[i])
    test_case_opf_mn_forecasted["nw"]["$i"]["gen"]["1"]["pmax"] = deepcopy(test_case_opf_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*forecasted_wind[i])
end

result = Dict{String,Any}()
result = _PM.solve_mn_opf(test_case_opf_replicate,LPACCPowerModel,gurobi_opf; setting = s)
result_measured = _PM.solve_mn_opf(test_case_opf_mn_measured,LPACCPowerModel,gurobi_opf; setting = s)
result_forecasted = _PM.solve_mn_opf(test_case_opf_mn_forecasted,LPACCPowerModel,gurobi_opf; setting = s)

# For results comparison
#for i in 1:(n_hours*one_scenario)
#    result["$i"] = _PM.solve_opf(test_case_opf_replicate["nw"]["$i"],LPACCPowerModel,gurobi_opf; setting = s)
#end
#result_opf = _SPMTA.run_stochastic_ac_opf(test_case_opf_replicate,LPACCPowerModel,gurobi_opf; setting = s)
#result_opf_measured   = _SPMTA.run_stochastic_ac_opf(test_case_opf_mn_measured  ,LPACCPowerModel,gurobi_opf; setting = s)
#result_opf_forecasted = _SPMTA.run_stochastic_ac_opf(test_case_opf_mn_forecasted,LPACCPowerModel,gurobi_opf; setting = s)
