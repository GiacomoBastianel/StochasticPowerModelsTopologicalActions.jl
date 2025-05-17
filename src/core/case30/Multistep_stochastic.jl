using PowerModels; const _PM = PowerModels
using PowerModelsACDC; const _PMACDC = PowerModelsACDC
import PowerModelsTopologicalActionsII; const _PMTP = PowerModelsTopologicalActionsII
using FlexPlan; const _FP = FlexPlan
using Gurobi, Ipopt, JSON, Plots
import StochasticPowerModelsTopologicalActions; const _SPMTA = StochasticPowerModelsTopologicalActions
using JuMP, Juniper, HSL_jll, MathOptInterface, HiGHS
using Statistics

mip_gap = 1e-3
gurobi_bs = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 5400,"MIPGap" => mip_gap,"BarHomogeneous" => 1, "NumericFocus"=>2) 
gurobi = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 1800,"MIPGap" => mip_gap,"BarHomogeneous" => 1,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "ScaleFlag"=>2, "NumericFocus"=>2) 
gurobi_opf = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 1200,"MIPGap" => mip_gap,"BarHomogeneous" => 1, "NumericFocus"=>2,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "ScaleFlag"=>2, "NumericFocus"=>3) 
gurobi_lpac = JuMP.optimizer_with_attributes(Gurobi.Optimizer)#,"time_limit" => 1200,"MIPGap" => mip_gap,"BarHomogeneous" => 1,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "ScaleFlag"=>2, "NumericFocus"=>2)
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

results_folder = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Deliverable_1_2_DIRECTIONS/Results"
case = "case_30/stochastic_multistep"

test_case = _PM.parse_file(test_case_file)

test_case_opf = deepcopy(test_case)
opf_30 = _PM.solve_opf(test_case_opf, LPACCPowerModel, ipopt)

#########################################################################################
# Busbar splitting
test_case_bs = deepcopy(test_case_opf)
splitted_bus_ac = 6
test_case_bs,  switches_couples_ac,  extremes_ZILs_ac  = _PMTP.AC_busbar_split_AC_grid(test_case,splitted_bus_ac)

# Adding costs to the busbar couplers
for sw_id in 1:length(extremes_ZILs_ac)
    test_case_bs["switch"]["$sw_id"]["cost"] = 10.0
end

result_bs_6 = _PMTP.run_acdcsw_AC_big_M_hour(test_case_bs, LPACCPowerModel, gurobi)
result_bs_6_no_cost = _PMTP.run_acdcsw_AC_big_M(test_case_bs, LPACCPowerModel, gurobi)


feasibility_check = deepcopy(test_case_bs)
feasibility_check_input = deepcopy(test_case_bs)
_PMTP.prepare_AC_feasibility_check(result_bs_6,feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
result_feasibility_check = _PMACDC.run_acdcopf(feasibility_check,LPACCPowerModel,gurobi_opf; setting = s)


#########################################################################################
# Hours
n_hours = 1
start_hour_simulation = 1
end_hour_simulation = 1
hours = collect(start_hour_simulation:end_hour_simulation)
n_scenarios = 8
one_scenario = 1

#########################################################################################
# Add dimensions for stochastic part
_SPMTA.add_dimensions!(test_case_bs,n_scenarios,n_hours)

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
for i in hours
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
for i in hours
    h = start_hour_simulation + i - 1
    hw = is[i]   
    Load_data["$h"] = Dict{String,Any}()
    Load_data["$h"]["total_load"] = Load_2024[hw]["totalload"]
    Load_data["$h"]["total_load_pu"] = Load_2024[hw]["totalload"]/max_load
    Load_data["$h"]["Elia_timestep"] = is[i]
end


measured_wind   = [Wind_data["$i"]["measured_pu"]   for i in 1:length(hours)]
forecasted_wind = [Wind_data["$i"]["P50_11hforecast_pu"] for i in 1:length(hours)]
load_pu = [Load_data["$i"]["total_load_pu"] for i in 1:length(hours)]
Wind_data["1"]["samples_pu"] 


P50_11h = []
for i in 1:length(Elia_OFW)
    if Elia_OFW[i]["minute"] == "00"
        push!(P50_11h,Elia_OFW[i]["dayahead11hforecast"]/Elia_OFW[i]["monitoredcapacity"])
    end
end

measured_11h = []
for i in 1:length(Elia_OFW)
    if Elia_OFW[i]["minute"] == "00"
        push!(measured_11h,Elia_OFW[i]["measured"]/Elia_OFW[i]["monitoredcapacity"])
    end
end

expected_h = Dict{String,Any}()
count_hour = 0
for i in 1:length(Elia_OFW)
    if Elia_OFW[i]["minute"] == "00"
        count_hour += 1
        expected_h["$count_hour"] = Dict{String,Any}()
        expected_h["$count_hour"]["samples_pu"] = deepcopy(Gaussian_samples["$i"]["samples_pu"])
        expected_h["$count_hour"]["pdf_normalized"] = deepcopy(Gaussian_samples["$i"]["pdf_normalized"])
    end
end

first_hour = 355
last_hour = 378

forecasted_wind = P50_11h[first_hour:last_hour]
measured_wind = measured_11h[first_hour:last_hour]
hours_simulation_Elia = collect(first_hour:last_hour)


n_hours = last_hour - first_hour + 1
start_hour_simulation = 1
end_hour_simulation = last_hour - first_hour + 1
hours = collect(start_hour_simulation:end_hour_simulation)
n_scenarios = 8
one_scenario = 1



expected_value_wind = []
scenarios_wind = Dict{String,Any}()
count_hour = 0
for i in hours_simulation_Elia
    count_hour += 1
    expected_value_wind_hourly = 0.0  
    for s in 1:n_scenarios
        n = (count_hour - 1)*n_scenarios + s
        scenarios_wind["$n"] = Dict{String,Any}()
        scenarios_wind["$n"]["probability"] = deepcopy(expected_h["$i"]["pdf_normalized"][s])
        scenarios_wind["$n"]["samples_pu"] = deepcopy(expected_h["$i"]["samples_pu"][s])
        scenarios_wind["$n"]["hour"] = i
        scenarios_wind["$n"]["scenario"] = s
        expected_value_wind_hourly += expected_h["$i"]["samples_pu"][s]*expected_h["$i"]["pdf_normalized"][s]
    end
    push!(expected_value_wind, expected_value_wind_hourly)
end

forecasted_wind[20] = forecasted_wind[1]
forecasted_wind[21] = forecasted_wind[2]
forecasted_wind[22] = forecasted_wind[3]
forecasted_wind[23] = forecasted_wind[4]
forecasted_wind[24] = forecasted_wind[5]

measured_wind[20] = measured_wind[1]
measured_wind[21] = measured_wind[2]
measured_wind[22] = measured_wind[3]
measured_wind[23] = measured_wind[4]
measured_wind[24] = measured_wind[5]

expected_value_wind[20] = expected_value_wind[1]
expected_value_wind[21] = expected_value_wind[2]
expected_value_wind[22] = expected_value_wind[3]
expected_value_wind[23] = expected_value_wind[4]
expected_value_wind[24] = expected_value_wind[5]

for h in 20:24
    for s in 1:n_scenarios
        l = (h - 1)*n_scenarios + s
        n = (h - 19)*n_scenarios + s
        #if scenarios_wind["$l"]["hour"] == h && scenarios_wind["$l"]["scenario"] == s
        scenarios_wind["$l"]["samples_pu"] = scenarios_wind["$(n)"]["samples_pu"]
        scenarios_wind["$l"]["probability"] = scenarios_wind["$(n)"]["probability"]
        #end
    end
end

plot(forecasted_wind)
plot!(measured_wind)
plot!(expected_value_wind)


#=
forecasted_wind_all = P50_11h
measured_wind_all = measured_11h
hours_simulation_Elia_all = collect(1:8784)

expected_value_wind_all = []
for i in hours_simulation_Elia_all
    expected_value_wind_hourly_all = 0.0  
    for s in 1:n_scenarios
        expected_value_wind_hourly_all += expected_h["$i"]["samples_pu"][s]*expected_h["$i"]["pdf_normalized"][s]
    end
    push!(expected_value_wind_all, expected_value_wind_hourly_all)
end

diff_exp_meas_all = measured_wind_all .- expected_value_wind_all
diff_exp_forecast_all = measured_wind_all .- forecasted_wind_all

diff_exp_forecast_all = expected_value_wind_all .- forecasted_wind_all

scatter(diff_exp_forecast_all)
findmax(diff_exp_meas_all)
findmin(diff_exp_meas_all)
=#
#########################################################################################
## Running simulations
# Busbar splitting
test_case_opf_replicate = _PM.replicate(test_case_opf, n_hours*n_scenarios)
test_case_opf_replicate_one_scenario = _PM.replicate(test_case_opf, n_hours*one_scenario)

test_case_opf_mn_measured = deepcopy(test_case_opf_replicate_one_scenario)
test_case_opf_mn_forecasted = deepcopy(test_case_opf_replicate_one_scenario)
test_case_opf_mn_expected = deepcopy(test_case_opf_replicate)

function adding_multinetwork_scenarios(test_case, n_hours, n_scenarios,uncertainty)
    for hour in 1:n_hours
        for scenario_idx in 1:n_scenarios
            n = (hour - 1)*n_scenarios + scenario_idx
            add_hour_scenario_probability(test_case,hour,scenario_idx,n_scenarios,n,uncertainty)
        end
    end
    test_case["scenarios"] = n_scenarios
    test_case["hours"] = n_hours
    return test_case
end

function add_hour_scenario_probability(data,hour,scenario_idx,n_scenarios,index,uncertainty)
    data["nw"]["$index"]["hour"] = hour
    data["nw"]["$index"]["scenario"] = scenario_idx
    data["nw"]["$index"]["hour_scenario_index"] = [hour,scenario_idx,index]
    if n_scenarios == 1
        data["nw"]["$index"]["probability"] = 1.0
        data["nw"]["$index"]["per_unit"] = true
    elseif n_scenarios > 1
        data["nw"]["$index"]["probability"] = uncertainty["$index"]["probability"]
        data["nw"]["$index"]["per_unit"] = true
    end
end

adding_multinetwork_scenarios(test_case_opf_mn_measured,n_hours,one_scenario,scenarios_wind)
adding_multinetwork_scenarios(test_case_opf_mn_forecasted,n_hours,one_scenario,scenarios_wind)
adding_multinetwork_scenarios(test_case_opf_mn_expected,n_hours,n_scenarios,scenarios_wind)


for i in 1:(n_hours*one_scenario)
    test_case_opf_mn_measured["nw"]["$i"]["gen"]["1"]["pmax"]   = deepcopy(test_case_opf_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*measured_wind[i])
    test_case_opf_mn_forecasted["nw"]["$i"]["gen"]["1"]["pmax"] = deepcopy(test_case_opf_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*forecasted_wind[i])
end
for i in 1:(n_hours*n_scenarios)
    test_case_opf_mn_expected["nw"]["$i"]["gen"]["1"]["pmax"]   = deepcopy(test_case_opf_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*scenarios_wind["$i"]["samples_pu"])
end


################################################################################

result_forecasted_24_ac = Dict{String,Any}()
result_forecasted_24_lpac = Dict{String,Any}()

result_measured_24_ac = Dict{String,Any}()
result_measured_24_lpac = Dict{String,Any}()

result_expected_24_ac = Dict{String,Any}()
result_expected_24_lpac = Dict{String,Any}()

#=
json_opf_results_opf_forecasted_ac = JSON.json(result_forecasted_24_ac)
open(joinpath(results_folder,case,"24_hours_OPF_ac_forecasted.json"),"w") do f 
    write(f, json_opf_results_opf_forecasted_ac) 
end 

json_opf_results_opf_forecasted_lpac = JSON.json(result_forecasted_24_lpac)
open(joinpath(results_folder,case,"24_hours_OPF_lpac_forecasted.json"),"w") do f 
    write(f, json_opf_results_opf_forecasted_lpac) 
end 

json_opf_results_opf_measured_ac = JSON.json(result_measured_24_ac)
open(joinpath(results_folder,case,"24_hours_OPF_ac_measured.json"),"w") do f 
    write(f, json_opf_results_opf_measured_ac) 
end 

json_opf_results_opf_measured_lpac = JSON.json(result_measured_24_lpac)
open(joinpath(results_folder,case,"24_hours_OPF_lpac_measured.json"),"w") do f 
    write(f, json_opf_results_opf_measured_lpac) 
end 
=#

for hour in 1:(n_hours*one_scenario)
    result_forecasted_24_ac["$hour"] = _PM.solve_opf(test_case_opf_mn_forecasted["nw"]["$hour"],ACPPowerModel,ipopt; setting = s)
    result_forecasted_24_lpac["$hour"] = _PM.solve_opf(test_case_opf_mn_forecasted["nw"]["$hour"],LPACCPowerModel,ipopt; setting = s)

    result_measured_24_ac["$hour"] = _PM.solve_opf(test_case_opf_mn_measured["nw"]["$hour"],ACPPowerModel,ipopt; setting = s)
    result_measured_24_lpac["$hour"] = _PM.solve_opf(test_case_opf_mn_measured["nw"]["$hour"],LPACCPowerModel,ipopt; setting = s)
end

obj_forecasted_24_lpac = [result_forecasted_24_lpac["$i"]["objective"] for i in 1:(n_hours*one_scenario)]
obj_measured_24_lpac = [result_measured_24_lpac["$i"]["objective"] for i in 1:(n_hours*one_scenario)]

for hour in 1:(n_hours*n_scenarios)
    result_expected_24_lpac["$hour"] = _PM.solve_opf(test_case_opf_mn_expected["nw"]["$hour"],LPACCPowerModel,ipopt; setting = s)
end

obj_expected = []
for hour in 1:n_hours
    first_n = (hour - 1)*n_scenarios + 1
    println("first_n: ", first_n)
    last_n = n_scenarios*hour
    println("last_n: ", last_n)
    opf_hour = sum(result_expected_24_lpac["$h"]["objective"]*test_case_opf_mn_expected["nw"]["$h"]["probability"] for h in first_n:last_n)
    push!(obj_expected,opf_hour)
end


exp_ = sum(obj_expected)
for_ = sum(obj_forecasted_24_lpac)
mea_ = sum(obj_measured_24_lpac)

plot(obj_expected)
plot!(obj_forecasted_24_lpac)
plot!(obj_measured_24_lpac)

###########################################################################
# -> OPFs are comparable now, data set built, need to tweak the functions to have a multistep-stochastic formulation

test_case_bs_replicate = _PM.replicate(test_case_bs, n_hours*n_scenarios)
test_case_bs_replicate_one_scenario = _PM.replicate(test_case_bs, n_hours*one_scenario)

test_case_bs_mn_measured = deepcopy(test_case_bs_replicate_one_scenario)
test_case_bs_mn_forecasted = deepcopy(test_case_bs_replicate_one_scenario)
test_case_bs_mn_expected = deepcopy(test_case_bs_replicate)

adding_multinetwork_scenarios(test_case_bs_mn_measured,n_hours,one_scenario,scenarios_wind)
adding_multinetwork_scenarios(test_case_bs_mn_forecasted,n_hours,one_scenario,scenarios_wind)
adding_multinetwork_scenarios(test_case_bs_mn_expected,n_hours,n_scenarios,scenarios_wind)


for i in 1:(n_hours*one_scenario)
    test_case_bs_mn_measured["nw"]["$i"]["gen"]["1"]["pmax"]   = deepcopy(test_case_bs_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*measured_wind[i])
    test_case_bs_mn_forecasted["nw"]["$i"]["gen"]["1"]["pmax"] = deepcopy(test_case_bs_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*forecasted_wind[i])
end
for i in 1:(n_hours*n_scenarios)
    test_case_bs_mn_expected["nw"]["$i"]["gen"]["1"]["pmax"]   = deepcopy(test_case_bs_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*scenarios_wind["$i"]["samples_pu"])
end



function prepare_starting_value_dict_lpac_nw_sp(grid,n_hours,n_scenarios)
    count_ = 0
    for hour in 1:n_hours
        count_ += 1
        for scenario_idx in 1:n_scenarios
            n = (count_ - 1)*n_scenarios + scenario_idx
            for (sw_id,sw) in grid["nw"]["$n"]["switch"]
                if !haskey(sw,"auxiliary") # calling ZILs
                    sw["starting_value"] = 1.0
                else
                    if haskey(grid["nw"]["$n"]["switch_couples"],sw_id)
                        grid["nw"]["$n"]["switch"]["$(grid["nw"]["$n"]["switch_couples"][sw_id]["f_sw"])"]["starting_value"] = 0.0
                        grid["nw"]["$n"]["switch"]["$(grid["nw"]["$n"]["switch_couples"][sw_id]["t_sw"])"]["starting_value"] = 1.0
                    end
                end
            end
        end
    end
end

test_case_bs_mn_expected_sp = deepcopy(test_case_bs_mn_expected)
prepare_starting_value_dict_lpac_nw_sp(test_case_bs_mn_expected_sp,n_hours,n_scenarios)

test_case_bs_mn_expected_hours_sp = Dict{String,Any}()
for hour in 1:n_hours
    first_n = (hour - 1)*n_scenarios + 1
    last_n = n_scenarios*hour
    test_case_bs_mn_expected_hours_sp["$hour"] = Dict{String,Any}()
    test_case_bs_mn_expected_hours_sp["$hour"]["nw"] = Dict{String,Any}()
    test_case_bs_mn_expected_hours_sp["$hour"]["multinetwork"] = true
    test_case_bs_mn_expected_hours_sp["$hour"]["per_unit"] = true
    for i in first_n:last_n
        test_case_bs_mn_expected_hours_sp["$hour"]["nw"]["$i"] = deepcopy(test_case_bs_mn_expected_sp["nw"]["$i"])
    end
end

#result = Dict{String,Any}()
#for hour in 1:n_hours
#    result["$hour"] = Dict{String,Any}()
#    result["$hour"] = _SPMTA.run_stochastic_acdcsw_AC_ZIL_hourly_sp(test_case_bs_mn_expected_hours_sp["$hour"],LPACCPowerModel,gurobi_opf; setting = s)
#end
hour_reduction = 6

test_case_bs_mn_expected_try = deepcopy(test_case_bs_mn_expected)
test_case_bs_mn_expected_try["hours"] = hour_reduction
for i in 1:(n_hours*n_scenarios)
    if i > hour_reduction*n_scenarios
        delete!(test_case_bs_mn_expected_try["nw"],"$i")
    end
end
test_case_bs_mn_expected_try["nw"]

test_case_bs_mn_forecasted_try = deepcopy(test_case_bs_mn_forecasted)
test_case_bs_mn_measured_try = deepcopy(test_case_bs_mn_measured)
test_case_bs_mn_forecasted_try["hours"] = hour_reduction
test_case_bs_mn_measured_try["hours"] = hour_reduction
for i in 1:(n_hours*n_scenarios)
    if i > hour_reduction
        delete!(test_case_bs_mn_forecasted_try["nw"],"$i")
        delete!(test_case_bs_mn_measured_try["nw"],"$i")
    end
end

#########################################################################
#results_one_topology_sp_expected = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology_sp(test_case_bs_mn_expected_try,LPACCPowerModel,gurobi; setting = s)
results_one_topology_sp_forecasted = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology_sp(test_case_bs_mn_forecasted_try,LPACCPowerModel,gurobi; setting = s)
results_one_topology_sp_measured = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology_sp(test_case_bs_mn_measured_try,LPACCPowerModel,gurobi; setting = s)


# -> 'gurobi' works for 1,2,4,6 hours

result = Dict{String,Any}()
for hour in 1:n_hours
    result["$hour"] = Dict{String,Any}()
    result["$hour"] = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology_sp(test_case_bs_mn_expected_hours_sp["$hour"],LPACCPowerModel,gurobi_opf; setting = s)
end

[results_one_topology_sp["solution"]["nw"]["$h"]["switch"]["1"]["status"] for h in 1:16]

####################################################

test_case_bs_mn_forecasted_try_max_sw = deepcopy(test_case_bs_mn_forecasted_try)
test_case_bs_mn_measured_try_max_sw = deepcopy(test_case_bs_mn_measured_try)
test_case_bs_mn_expected_try_max_sw = deepcopy(test_case_bs_mn_expected_try)

test_case_bs_mn_forecasted["total_switching_actions"] = 1
test_case_bs_mn_measured["total_switching_actions"] = 1
test_case_bs_mn_expected["total_switching_actions"] = 1

for (sw_id,sw) in test_case_bs_mn_forecasted["nw"]["1"]["switch"]
    sw["maximum_actions"] = 1
end
for (sw_id,sw) in test_case_bs_mn_measured["nw"]["1"]["switch"]
    sw["maximum_actions"] = 1
end
for (sw_id,sw) in test_case_bs_mn_expected["nw"]["1"]["switch"]
    sw["maximum_actions"] = 1
end

results_one_topology_sp_forecasted_max_sw = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches(test_case_bs_mn_forecasted,LPACCPowerModel,gurobi)
results_one_topology_sp_measured_max_sw = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches(test_case_bs_mn_measured,LPACCPowerModel,gurobi)
results_one_topology_sp_expected_max_sw = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches(test_case_bs_mn_expected,LPACCPowerModel,gurobi)

results_one_topology_sp_expected_max_sw = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches_stochastic(test_case_bs_mn_expected,LPACCPowerModel,gurobi)

first_hours = []
scenario_idx = 1
scenarios = 8
for hour in 1:24
    push!(first_hours,(hour - 1)*scenarios + scenario_idx)
end





[results_one_topology_sp_expected_max_sw["solution"]["nw"]["1"]["switch"][sw_id]["status"] for (sw_id,sw) in test_case_bs_mn_expected_try_max_sw["nw"]["1"]["switch"]]
[results_one_topology_sp_expected_max_sw["solution"]["nw"]["$h"]["switch"]["1"]["status"] for h in eachindex(test_case_bs_mn_expected_try_max_sw["nw"])]
[results_one_topology_sp_expected_max_sw["solution"]["nw"]["$h"]["switch"]["2"]["status"] for h in 1:32]
[results_one_topology_sp_expected_max_sw["solution"]["nw"]["$h"]["switch"]["3"]["status"] for h in 1:32]
[results_one_topology_sp_expected_max_sw["solution"]["nw"]["$h"]["switch"]["4"]["status"] for h in 1:32]
[results_one_topology_sp_expected_max_sw["solution"]["nw"]["$h"]["switch"]["5"]["status"] for h in 1:32]
[results_one_topology_sp_expected_max_sw["solution"]["nw"]["$h"]["switch"]["6"]["status"] for h in 1:32]
[results_one_topology_sp_expected_max_sw["solution"]["nw"]["$h"]["switch"]["7"]["status"] for h in 1:32]
[results_one_topology_sp_expected_max_sw["solution"]["nw"]["$h"]["switch"]["8"]["status"] for h in 1:32]
[results_one_topology_sp_expected_max_sw["solution"]["nw"]["$h"]["switch"]["9"]["status"] for h in 1:32]
[results_one_topology_sp_expected_max_sw["solution"]["nw"]["$h"]["switch"]["10"]["status"] for h in eachindex(test_case_bs_mn_expected_try_max_sw["nw"])]