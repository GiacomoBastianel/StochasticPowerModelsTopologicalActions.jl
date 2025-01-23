using PowerModels; const _PM = PowerModels
using PowerModelsACDC; const _PMACDC = PowerModelsACDC
using PowerModelsTopologicalActionsII; const _PMTP = PowerModelsTopologicalActionsII
using FlexPlan; const _FP = FlexPlan
using Gurobi
using StochasticPowerModelsTopologicalActions; const _SPMTA = StochasticPowerModelsTopologicalActions

gurobi = Gurobi.Optimizer
##### Testing FlexPlan.jl functions to build multinetwork model with scenarios
test_case_5_acdc = "case5_acdc.m"
data_file_5_acdc = joinpath(dirname(@__DIR__),"data_sources",test_case_5_acdc)

data_5_acdc = _PM.parse_file(data_file_5_acdc)
_PMACDC.process_additional_data!(data_5_acdc)


_FP._initialize_dim()

#loads = Dict(1 => Dict{String,Any}("load"=>1.0))
n_hours = 2
n_scenarios = 2
scenarios = Dict(1 => Dict{String,Any}("probability"=>0.8,"value"=>1.0),2 => Dict{String,Any}("probability"=>0.2,"value"=>1.0))

_FP.add_dimension!(data_5_acdc, :hour, n_hours)
_FP.add_dimension!(data_5_acdc, :scenario, scenarios)

#data_5_acdc["dim"][:prop][:hour]
#data_5_acdc["dim"][:prop][:scenario]

# Selecting which busbars are split
splitted_bus_ac = 2

split_elements = _PMTP.elements_AC_busbar_split(data_5_acdc)
data_busbars_ac_split_5_acdc,  switches_couples_ac_5,  extremes_ZILs_5_ac  = _PMTP.AC_busbar_split_more_buses(data_5_acdc,splitted_bus_ac)



data_busbars_ac_split_5_acdc, loadprofile, genprofile = _SPMTA.create_stochastic_profile_data!(data_busbars_ac_split_5_acdc)


# These need to be modified
time_series = _SPMTA.create_profile_data(n_hours*n_scenarios, data_busbars_ac_split_5_acdc, loadprofile, genprofile) # Your time series should have the same format as this `time_series` dict

mn_data = _FP.make_multinetwork(data_busbars_ac_split_5_acdc, time_series)

result = _SPMTA.run_stochastic_acdcsw_AC(mn_data, LPACCPowerModel, gurobi)

result_switches = Dict{String,Any}()
for i in eachindex(result["solution"]["nw"])
    result_switches["$i"] = []
    for (sw_id,sw) in data_busbars_ac_split_5_acdc["switch"]
        push!(result_switches["$i"],result["solution"]["nw"]["$i"]["switch"][sw_id]["status"])
    end
end 
println(result_switches["1"])
println(result_switches["2"])