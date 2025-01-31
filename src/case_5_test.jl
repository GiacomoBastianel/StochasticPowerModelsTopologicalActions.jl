using PowerModels; const _PM = PowerModels
using PowerModelsACDC; const _PMACDC = PowerModelsACDC
import PowerModelsTopologicalActionsII; const _PMTP = PowerModelsTopologicalActionsII
using FlexPlan; const _FP = FlexPlan
using Gurobi
using Ipopt
using JSON
import StochasticPowerModelsTopologicalActions; const _SPMTA = StochasticPowerModelsTopologicalActions

gurobi = Gurobi.Optimizer
ipopt = Ipopt.Optimizer
#########################################################################################
##### Testing FlexPlan.jl functions to build multinetwork model with scenarios
test_case_5_acdc = "case5_acdc.m"
data_file_5_acdc = joinpath(dirname(@__DIR__),"data_sources",test_case_5_acdc)

data_5_acdc = _PM.parse_file(data_file_5_acdc)
_PMACDC.process_additional_data!(data_5_acdc)
data_5_acdc["gen"]["1"]["type"] = "Offshore Wind"
data_5_acdc["gen"]["1"]["pmax"] = data_5_acdc["gen"]["1"]["pmax"]/2
data_5_acdc["gen"]["2"]["type"] = "Other RES"

data_5_acdc_opf = _PM.parse_file(data_file_5_acdc)
_PMACDC.process_additional_data!(data_5_acdc_opf)
data_5_acdc_opf["gen"]["1"]["type"] = "Offshore Wind"
data_5_acdc_opf["gen"]["1"]["pmax"] = data_5_acdc_opf["gen"]["1"]["pmax"]/2
data_5_acdc_opf["gen"]["2"]["type"] = "Other RES"


n_hours = 4
n_scenarios = 8

#########################################################################################
# Uploading pdf samples for offshore wind
folder_data = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Elia_data"
#folder_data = joinpath(dirname(@__DIR__),"Elia_data")

# Belgium grid without energy island
Gaussian_samples_file = joinpath(folder_data,"Gaussian_samples_8_Offshore_wind_2023_Elia.json")
Gaussian_samples = JSON.parsefile(Gaussian_samples_file)

_FP._initialize_dim()
_FP.add_dimension!(data_5_acdc, :scenario, n_scenarios)
_FP.add_dimension!(data_5_acdc, :hour, n_hours)

_FP.add_dimension!(data_5_acdc_opf, :scenario, n_scenarios)
_FP.add_dimension!(data_5_acdc_opf, :hour, n_hours)

###############################

RES_time_series = Dict{String,Any}()
for (g_id,g) in data_5_acdc["gen"]
    RES_time_series[g_id] = Dict{String,Any}()
    for hour in 1:n_hours
        RES_time_series[g_id]["$hour"] = Dict{String,Any}()
        if g["type"] == "Offshore Wind"
            for i in 1:n_scenarios
                RES_time_series[g_id]["$hour"]["$i"] = Dict{String,Any}(
                    "pdf" => Gaussian_samples["$hour"]["pdf_normalized"][i], 
                    "sample" => Gaussian_samples["$hour"]["samples_pu"][i])
            end
        else
            for i in 1:n_scenarios
                RES_time_series[g_id]["$hour"]["$i"] = Dict{String,Any}(
                    "pdf" => Gaussian_samples["$hour"]["pdf_normalized"][i], 
                    "sample" => 1.0)
            end
        end
    end
end

scenarios_probabilities = Dict{String,Any}()
for i in 1:n_hours
    for j in 1:n_scenarios
        n = (i - 1)*n_scenarios + j
        scenarios_probabilities["$n"] = Gaussian_samples["$i"]["pdf_normalized"][j]
    end
end

gen_time_series = Dict{String,Any}()
for (g_id,g) in data_5_acdc["gen"]
    gen_time_series[g_id] = Dict{String,Any}("$hour" => Dict{String,Any}("$scenario" => Dict{String,Any}(
        "Capacity_factor" => RES_time_series[g_id]["$hour"]["$scenario"]["sample"], 
        "pmax_hourly" => g["pmax"]*RES_time_series[g_id]["$hour"]["$scenario"]["sample"],
        "pmax" => g["pmax"]) for scenario in 1:n_scenarios) for hour in 1:n_hours)
end

load_time_series = Dict{String,Any}()
for (l_id,l) in data_5_acdc["load"]
    load_time_series[l_id] = Dict{String,Any}("$hour" => Dict{String,Any}("$scenario" => Dict{String,Any}(
        "pd" => l["pd"]) for scenario in 1:n_scenarios) for hour in 1:n_hours)
end

time_series = Dict{String,Any}()
time_series["gen"] = gen_time_series
time_series["load"] = load_time_series
time_series["scenario_probability"] = scenarios_probabilities

_SPMTA.add_hour_scenario_data(data_5_acdc, n_hours, n_scenarios)
_SPMTA.add_hour_scenario_data(data_5_acdc_opf, n_hours, n_scenarios)

#########################################################################################
# Selecting which busbars are split
splitted_bus_ac = 2
split_elements = _PMTP.elements_AC_busbar_split(data_5_acdc)
data_busbars_ac_split_5_acdc,  switches_couples_ac_5,  extremes_ZILs_5_ac  = _PMTP.AC_busbar_split_more_buses(data_5_acdc,splitted_bus_ac)

#########################################################################################
# Creating multinetwork data
data_5_acdc_mn = _SPMTA.make_multinetwork_time_series(data_5_acdc,n_scenarios,n_hours,time_series)
data_5_acdc_opf_mn = _SPMTA.make_multinetwork_time_series(data_5_acdc_opf,n_scenarios,n_hours,time_series)

#######################################

result = _SPMTA.run_stochastic_acdcsw_AC_ZIL(data_5_acdc_mn, LPACCPowerModel, gurobi)
result_opf = _SPMTA.run_stochastic_acdc_opf(data_5_acdc_opf_mn, LPACCPowerModel, gurobi)


switch_result = Dict()
for i in 1:n_hours*n_scenarios 
    switch_result[i] = []
    for l in 1:length(data_5_acdc_mn["nw"]["$i"]["switch"])
        push!(switch_result[i],result["solution"]["nw"]["$i"]["switch"]["$l"]["status"])
    end
end


for i in 1:(n_hours*n_scenarios)
   println(switch_result[i][1])
end

for i in 1:n_scenarios
    println(result["solution"]["nw"]["$i"]["gen"]["1"]["pg"])
    println(data_5_acdc_mn["nw"]["$i"]["probability"])
    print("\n")
end
for i in 9:16
    println(result["solution"]["nw"]["$i"]["gen"]["1"]["pg"])
end
for i in 17:24
    println(result["solution"]["nw"]["$i"]["gen"]["1"]["pg"])
end
for i in 25:32
    println(result["solution"]["nw"]["$i"]["gen"]["1"]["pg"])
end

cost = []
for hour in 1:n_hours
    cost_hour = 0
    for i in 1:n_scenarios
        n = (hour - 1)*n_scenarios + i
        for (g_id,g) in data_5_acdc_mn["nw"]["$n"]["gen"]
            cost_hour += g["cost"][end-1]*result["solution"]["nw"]["$n"]["gen"]["$g_id"]["pg"]*data_5_acdc_mn["nw"]["$n"]["probability"]
        end
    end
    push!(cost,cost_hour)
end
sum(cost)























