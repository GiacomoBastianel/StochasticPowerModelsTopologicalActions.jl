using PowerModels; const _PM = PowerModels
using PowerModelsACDC; const _PMACDC = PowerModelsACDC
import PowerModelsTopologicalActionsII; const _PMTP = PowerModelsTopologicalActionsII
using FlexPlan; const _FP = FlexPlan
using Gurobi, Ipopt, JSON, Plots
import StochasticPowerModelsTopologicalActions; const _SPMTA = StochasticPowerModelsTopologicalActions
using JuMP, Juniper, HSL_jll, MathOptInterface, HiGHS

mip_gap = 1e-4
gurobi_bs = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 5400,"MIPGap" => mip_gap,"BarHomogeneous" => 1, "NumericFocus"=>2) 
ipopt = JuMP.optimizer_with_attributes(Ipopt.Optimizer, "tol" => 1e-6, "print_level" => 0,"linear_solver" => "ma97")
juniper = JuMP.optimizer_with_attributes(Juniper.Optimizer, "nl_solver" => ipopt, "mip_solver" => gurobi, "time_limit" => 36000)

#########################################################################################
## Processing input data
s = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true)
s_dual = Dict("output" => Dict("branch_flows" => true,"duals" => true), "conv_losses_mp" => true)

#########################################################################################
## Processing input data
#=
input_folder = dirname(dirname(dirname(@__DIR__)))
test_case_file = joinpath(input_folder,"data_sources/case67.m")
original_grid = _PM.parse_file(test_case_file)
test_case = _PM.parse_file(test_case_file)
_PMACDC.process_additional_data!(test_case)

opf_67 = _PMACDC.run_acdcopf(test_case_json, LPACCPowerModel, gurobi; setting = s)
opf_67_ac = _PMACDC.run_acdcopf(test_case_json, ACPPowerModel, ipopt; setting = s_dual)

test_case["gen"]["2"]["cost"][1] = 59.0
test_case["gen"]["4"]["cost"][1] = 59.0
test_case["gen"]["20"]["cost"][1] = 59.0
test_case["gen"]["1"]["cost"][1]  = 120.0
test_case["gen"]["3"]["cost"][1]  = 120.0
test_case["gen"]["10"]["cost"][1] = 120.0
test_case["gen"]["16"]["cost"][1] = 120.0
test_case["gen"]["18"]["cost"][1] = 120.0
test_case["gen"]["7"]["cost"][1] = 120.0
test_case["gen"]["15"]["cost"][1]  = 89.0
test_case["gen"]["5"]["cost"][1]  = 89.0
test_case["gen"]["17"]["cost"][1] = 89.0
test_case["gen"]["9"]["cost"][1]  = 89.0
test_case["gen"]["8"]["cost"][1]  = 89.0
test_case["gen"]["12"]["cost"][1] = 89.0
test_case["gen"]["6"]["cost"][1]  = 110.0
test_case["gen"]["14"]["cost"][1] = 110.0
test_case["gen"]["11"]["cost"][1] = 110.0
test_case["gen"]["13"]["cost"][1] = 110.0
test_case["gen"]["19"]["cost"][1]  = 110.0

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
=#


input_folder = dirname(dirname(dirname(@__DIR__)))
test_case_file = joinpath(input_folder,"data_sources/case67_modified.json")
original_grid = _PM.parse_file(test_case_file)
test_case = _PM.parse_file(test_case_file)
#_PMACDC.process_additional_data!(test_case)

opf_67 = _PMACDC.run_acdcopf(test_case, LPACCPowerModel, ipopt; setting = s)
opf_67_ac = _PMACDC.run_acdcopf(test_case, ACPPowerModel, ipopt; setting = s_dual)

for (g_id,g) in test_case["gen"]
    if opf_67_ac["solution"]["gen"][g_id]["pg"] > 0.001
        println("Gen $g_id, gen bus $(g["gen_bus"]), dual $(opf_67_ac["solution"]["bus"]["$(g["gen_bus"])"]["lam_kcl_r"]), generating $(opf_67_ac["solution"]["gen"][g_id]["pg"])")
    end
end

opf_67_ac["solution"]["gen"]["1"]
for (l_id,l) in test_case["load"]
    l["pd"] = l["pd"]*2
end

for (g_id,g) in test_case["gen"]
    println("Gen $g_id, gen bus $(g["gen_bus"]), $(g["cost"])")
end


###################################
function split_one_bus_per_time(test_case,results_dict,results_dict_ac_check,results_dict_lpac_check)
    for (b_id,b) in test_case["bus"]
        results_dict["$b_id"] = Dict{String,Any}()
        results_dict_ac_check["$b_id"] = Dict{String,Any}()
        test_case_bs = deepcopy(test_case)
        splitted_bus_ac = parse(Int64,b_id)
        test_case_bs,  switches_couples_ac,  extremes_ZILs_ac  = _PMTP.AC_busbar_split_more_buses(test_case_bs,splitted_bus_ac)
        test_case_bs["switch"]["1"]["cost"] = 1.0
        results_dict["$b_id"] = _PMTP.run_acdcsw_AC_big_M(test_case_bs,LPACCPowerModel,gurobi_bs)
        test_case_bs_check = deepcopy(test_case_bs)
        test_case_bs_check_auxiliary = deepcopy(test_case_bs)
        if results_dict["$b_id"]["termination_status"] == JuMP.OPTIMAL
            _PMTP.prepare_AC_feasibility_check(results_dict["$b_id"],test_case_bs_check_auxiliary,test_case_bs_check,switches_couples_ac,extremes_ZILs_ac,test_case)
            results_dict_ac_check["$b_id"] = _PMACDC.run_acdcopf(test_case_bs_check,ACPPowerModel,ipopt; setting = s)
            results_dict_lpac_check["$b_id"] = _PMACDC.run_acdcopf(test_case_bs_check,LPACCPowerModel,gurobi; setting = s)
        end
    end
end


result_bs = Dict{String,Any}()
results_ac_check = Dict{String,Any}()
results_lpac_check = Dict{String,Any}()
split_one_bus_per_time(test_case,result_bs,results_ac_check,results_lpac_check)

minimum(results_ac_check["$b_id"]["objective"] for (b_id,b) in test_case["bus"] if haskey(results_ac_check["$b_id"],"objective"))
findmin([(b_id, results_ac_check["$b_id"]["objective"]) for (b_id, b) in test_case["bus"] if haskey(results_ac_check["$b_id"], "objective")])
results_ac_check["1"]

sorted_objectives = sort([(b_id, results_ac_check["$b_id"]["objective"]) for (b_id, b) in test_case["bus"] if haskey(results_ac_check["$b_id"], "objective")], by = x -> x[2])

println("Sorted objectives with corresponding b_id:")
for (b_id, obj) in sorted_objectives
    println("b_id: $b_id, objective: $obj")
end

obj_bs_ac = [results_ac_check["$b_id"]["objective"] for (b_id,b) in test_case["bus"] if haskey(results_ac_check["$b_id"],"objective")]

scatter(obj_bs_ac)
sort(obj_bs_ac)

buses = [b_id for (b_id,b) in test_case["bus"]]
obj_bs = [result_bs["$b_id"]["objective"] for (b_id,b) in test_case["bus"]]
findmin(obj_bs)


duals_67 = [[b_id,abs(opf_67["solution"]["bus"][b_id]["lam_kcl_r"])] for (b_id,b) in test_case_opf["bus"]]
duals_67 = sort(duals_67,by = x -> x[2], rev = true)


bus_duals_sum = Dict(b_id => 0.0 for b_id in keys(test_case["bus"]))

for (br_id, br) in test_case["branch"]
    f_bus = br["f_bus"]
    t_bus = br["t_bus"]
    dual_diff = abs(opf_67_ac["solution"]["bus"]["$(f_bus)"]["lam_kcl_r"] - opf_67_ac["solution"]["bus"]["$(t_bus)"]["lam_kcl_r"])
    bus_duals_sum["$f_bus"] += dual_diff
    bus_duals_sum["$t_bus"] += dual_diff
end
sorted_bus_duals_sum = sort(collect(bus_duals_sum), by = x -> x[2], rev = true)



#########################################################################################
# Busbar splitting
test_case_bs = deepcopy(test_case_json)
splitted_bus_ac = 36
test_case_bs,  switches_couples_ac,  extremes_ZILs_ac  = _PMTP.AC_busbar_split_more_buses(test_case_bs,splitted_bus_ac)

# Adding costs to the busbar couplers
for sw_id in 1:length(extremes_ZILs_ac)
    test_case_bs["switch"]["$sw_id"]["cost"] = 10.0
end

#result_bs = _PMTP.run_acdcsw_AC_big_M_hour(test_case_bs_40, LPACCPowerModel, gurobi)
result_bs = _PMTP.run_acdcsw_AC_big_M(test_case_bs, LPACCPowerModel, gurobi)

function print_switch_results(test_case,original_test_case,results)
    for sw_id in 1:length(test_case["switch"])
        if haskey(test_case["switch"]["$(sw_id)"],"auxiliary")
            println("Switch $sw_id, aux is $(test_case["switch"]["$(sw_id)"]["auxiliary"]), orig is $(test_case["switch"]["$(sw_id)"]["original"]), t_bus is $(test_case["switch"]["$(sw_id)"]["t_bus"]), $(results["solution"]["switch"]["$sw_id"]["status"]), bus_split is $(test_case["switch"]["$(sw_id)"]["bus_split"])")    
            if test_case["switch"]["$(sw_id)"]["auxiliary"] == "branch"
                println("      Branch $(test_case["switch"]["$(sw_id)"]["original"]), f_bus $(original_test_case["branch"]["$(test_case["switch"]["$(sw_id)"]["original"])"]["f_bus"]), t_bus $(original_test_case["branch"]["$(test_case["switch"]["$(sw_id)"]["original"])"]["t_bus"])")
            end
        else
            println("Switch $sw_id,  is $(results["solution"]["switch"]["$sw_id"]["status"]), bus_split is $(test_case["switch"]["$(sw_id)"]["bus_split"])")
        end
    end
end
print_switch_results(test_case_bs,test_case_json,result_bs)

feasibility_check = deepcopy(test_case_bs)
feasibility_check_input = deepcopy(test_case_bs)
_PMTP.prepare_AC_feasibility_check(result_bs,feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_json)
result_feasibility_check = _PMACDC.run_acdcopf(feasibility_check,LPACCPowerModel,gurobi_opf; setting = s)


#########################################################################################
# Hours
n_hours = 24
start_hour_simulation = 1
end_hour_simulation = 24
hours = collect(start_hour_simulation:end_hour_simulation)
one_scenario = 1
#n_scenarios = 8

#########################################################################################
# Add dimensions for stochastic part
_SPMTA.add_dimensions!(test_case_bs,one_scenario,n_hours)

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

measured_wind   = [Wind_data["$i"]["measured_pu"]   for i in 1:length(hours)]
forecasted_wind = [Wind_data["$i"]["P50_11hforecast_pu"] for i in 1:length(hours)]
load_pu = [Load_data["$i"]["total_load_pu"] for i in 1:length(hours)]


P50_11h = []
for i in 1:length(Elia_OFW)
    if Elia_OFW[i]["minute"] == "00"
        push!(P50_11h,Elia_OFW[i]["dayahead11hforecast"]/Elia_OFW[i]["monitoredcapacity"])
    end
end

plot(P50_11h[355:366])

forecasted_wind = P50_11h[355:378]

plot(measured_wind,grid = :none,label = :none)
plot!(forecasted_wind,label = :none)


# PUTTING EVERYTHING AT ONE
measured_wind   = [1.0 for i in 1:length(hours)]
forecasted_wind = [1.0 for i in 1:length(hours)]
load_pu         = [1.0 for i in 1:length(hours)]


#########################################################################################
## Running simulations
# Busbar splitting
test_case_opf_replicate = _PM.replicate(test_case_json, n_hours)
for (nw_id,nw) in test_case_opf_replicate["nw"]
    nw["probability"] = 1.0
    nw["per_unit"] = true
end

test_case_opf_mn_measured = deepcopy(test_case_opf_replicate)
test_case_opf_mn_forecasted = deepcopy(test_case_opf_replicate)
for i in 1:(n_hours*one_scenario)
    test_case_opf_mn_measured["nw"]["$i"]["gen"]["2"]["pmax"]   = deepcopy(test_case_opf_mn_measured["nw"]["$i"]["gen"]["2"]["pmax"]*measured_wind[i])
    test_case_opf_mn_forecasted["nw"]["$i"]["gen"]["2"]["pmax"] = deepcopy(test_case_opf_mn_forecasted["nw"]["$i"]["gen"]["2"]["pmax"]*forecasted_wind[i])

    test_case_opf_mn_measured["nw"]["$i"]["gen"]["4"]["pmax"]   = deepcopy(test_case_opf_mn_measured["nw"]["$i"]["gen"]["4"]["pmax"]*measured_wind[i])
    test_case_opf_mn_forecasted["nw"]["$i"]["gen"]["4"]["pmax"] = deepcopy(test_case_opf_mn_forecasted["nw"]["$i"]["gen"]["4"]["pmax"]*forecasted_wind[i])

    test_case_opf_mn_measured["nw"]["$i"]["gen"]["20"]["pmax"]   = deepcopy(test_case_opf_mn_measured["nw"]["$i"]["gen"]["20"]["pmax"]*measured_wind[i])
    test_case_opf_mn_forecasted["nw"]["$i"]["gen"]["20"]["pmax"] = deepcopy(test_case_opf_mn_forecasted["nw"]["$i"]["gen"]["20"]["pmax"]*forecasted_wind[i])
end


function adding_multinetwork_scenarios(test_case, n_hours, n_scenarios)
    for hour in 1:n_hours
        for scenario_idx in 1:n_scenarios
            n = (hour - 1)*n_scenarios + scenario_idx
            add_hour_scenario_probability(test_case,hour,scenario_idx,n)
        end
    end
    test_case["scenarios"] = n_scenarios
    test_case["hours"] = n_hours
    return test_case
end

function add_hour_scenario_probability(data,hour,scenario,index)
    data["nw"]["$index"]["hour"] = hour
    data["nw"]["$index"]["scenario"] = scenario
    data["nw"]["$index"]["hour_scenario_index"] = [hour,scenario,index]
    #data["nw"]["$index"]["probability"] = time_series["scenario_probability"]["$index"]
end

test_case_bs_replicate = _PM.replicate(test_case_bs, n_hours)
for (nw_id,nw) in test_case_bs_replicate["nw"]
    nw["probability"] = 1.0
    nw["per_unit"] = true
end

test_case_bs_replicate_mn_measured = deepcopy(test_case_bs_replicate)
test_case_bs_replicate_mn_forecasted = deepcopy(test_case_bs_replicate)
adding_multinetwork_scenarios(test_case_bs_replicate,n_hours,one_scenario)
for i in 1:(n_hours*one_scenario)
    test_case_bs_replicate_mn_measured["nw"]["$i"]["gen"]["2"]["pmax"]   = deepcopy(test_case_bs_replicate_mn_measured["nw"]["$i"]["gen"]["2"]["pmax"]*measured_wind[i])
    test_case_bs_replicate_mn_forecasted["nw"]["$i"]["gen"]["2"]["pmax"] = deepcopy(test_case_bs_replicate_mn_forecasted["nw"]["$i"]["gen"]["2"]["pmax"]*forecasted_wind[i])

    test_case_bs_replicate_mn_measured["nw"]["$i"]["gen"]["4"]["pmax"]   = deepcopy(test_case_bs_replicate_mn_measured["nw"]["$i"]["gen"]["4"]["pmax"]*measured_wind[i])
    test_case_bs_replicate_mn_forecasted["nw"]["$i"]["gen"]["4"]["pmax"] = deepcopy(test_case_bs_replicate_mn_forecasted["nw"]["$i"]["gen"]["4"]["pmax"]*forecasted_wind[i])

    test_case_bs_replicate_mn_measured["nw"]["$i"]["gen"]["20"]["pmax"]   = deepcopy(test_case_bs_replicate_mn_measured["nw"]["$i"]["gen"]["20"]["pmax"]*measured_wind[i])
    test_case_bs_replicate_mn_forecasted["nw"]["$i"]["gen"]["20"]["pmax"] = deepcopy(test_case_bs_replicate_mn_forecasted["nw"]["$i"]["gen"]["20"]["pmax"]*forecasted_wind[i])
end

adding_multinetwork_scenarios(test_case_bs_replicate_mn_measured,n_hours,one_scenario)
adding_multinetwork_scenarios(test_case_bs_replicate_mn_forecasted,n_hours,one_scenario)

##############################################################
## Running simulations
# Hourly busbar splitting 
function run_stochastic_acdcsw_AC_ZIL_per_hour(grid, model, optimizer, n_hours, n_scenarios; setting = s)
    result = Dict{String,Any}()
    
    #for hour in 1:n_hours
    #    result["$hour"] = Dict{String,Any}()
    #    scenarios_hour = collect(((hour-1)*n_scenarios + 1):(hour*n_scenarios))
    #    grid_hour = deepcopy(grid)
    #    grid_hour["hours"] = 1
    #    grid_hour["nw"]= Dict{String,Any}()
    #    for i in scenarios_hour
    #        grid_hour["nw"]["$i"] = deepcopy(grid["nw"]["$i"])
    #    end    
    #    result["$hour"] = _SPMTA.run_stochastic_acdcsw_AC_ZIL_hourly(grid_hour,model,optimizer; setting = setting)
    #end
    
    for hour in 1:n_hours*n_scenarios
        result["$hour"] = Dict{String,Any}()
        result["$hour"] = _PMTP.run_acdcsw_AC_big_M_hour(grid["nw"]["$hour"],model,optimizer; setting = setting) 
    end
    return result
end

function run_feasibility_checks_per_hour(grid, result_bs, model, optimizer,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
    result_feasibility_checks = Dict{String,Any}()
    for hour in 1:length(grid["nw"])
        result_feasibility_checks["$hour"] = Dict{String,Any}()
        feasibility_check = deepcopy(grid["nw"]["$hour"])
        feasibility_check_input = deepcopy(grid["nw"]["$hour"])
        _PMTP.prepare_AC_feasibility_check(result_bs["$hour"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
        result_feasibility_checks["$hour"] = _PMACDC.run_acdcopf(feasibility_check,model,optimizer; setting = s)
        #if isnan(result_feasibility_checks["$hour"]["objective"])
        #    result_feasibility_checks["$hour"] = deepcopy(result_opf["$hour"])
        #end
    end
    return result_feasibility_checks
end


result_forecasted_24_ac = Dict{String,Any}()
for hour in 1:(n_hours*one_scenario)
    result_forecasted_24_ac["$hour"] = _PMACDC.run_acdcopf(test_case_opf_mn_forecasted["nw"]["$hour"],ACPPowerModel,ipopt; setting = s)
end

result_forecasted_24_lpac = Dict{String,Any}()
for hour in 1:(n_hours*one_scenario)
    result_forecasted_24_lpac["$hour"] = _PMACDC.run_acdcopf(test_case_opf_mn_forecasted["nw"]["$hour"],LPACCPowerModel,gurobi; setting = s)
end

obj_opf_forecasted_24_ac = [result_forecasted_24_ac["$i"]["objective"] for i in 1:n_hours]
obj_opf_forecasted_24_lpac = [result_forecasted_24_lpac["$i"]["objective"] for i in 1:n_hours]


sum(obj_opf_forecasted_24)
sum(result_forecasted_24["$i"]["solve_time"] for i in 1:n_hours)

plot(obj_forecasted_24,label="Forecasted",grid = :none)
##############################################################
#=
result_bs_hourly_24 = run_stochastic_acdcsw_AC_ZIL_per_hour(test_case_bs_replicate,LPACCPowerModel,gurobi,n_hours,one_scenario)
result_feasibility_checks_24 = run_feasibility_checks_per_hour(test_case_bs_replicate,result_bs_hourly_24,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,result)

obj_bs = [result_bs_hourly["$i"]["objective"] for i in 1:n_hours]
sum(obj_bs)

obj_fc = [result_feasibility_checks["$i"]["objective"] for i in 1:n_hours]
sum(obj_fc)

##############################################################

result_bs_hourly_measured_24 = run_stochastic_acdcsw_AC_ZIL_per_hour(test_case_bs_replicate_mn_measured,LPACCPowerModel,gurobi,n_hours,one_scenario)
result_measured_feasibility_checks_24 = run_feasibility_checks_per_hour(test_case_bs_replicate_mn_measured,result_bs_hourly_measured_24,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,result_measured)

obj_bs_measured = [result_bs_hourly_measured["$i"]["objective"] for i in 1:n_hours]
sum(obj_bs_measured)

obj_fc_measured = [result_measured_feasibility_checks["$i"]["objective"] for i in 1:n_hours]
sum(obj_fc_measured)

[result_bs_hourly_measured["$i"]["solution"]["switch"]["1"]["status"] for i in 1:n_hours]
=#
##############################################################

result_bs_hourly_forecasted_24 = run_stochastic_acdcsw_AC_ZIL_per_hour(test_case_bs_replicate_mn_forecasted,LPACCPowerModel,gurobi,n_hours,one_scenario)
result_forecasted_feasibility_checks_24_ac = run_feasibility_checks_per_hour(test_case_bs_replicate_mn_forecasted,result_bs_hourly_forecasted_24,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_json)
result_forecasted_feasibility_checks_24_lpac = run_feasibility_checks_per_hour(test_case_bs_replicate_mn_forecasted,result_bs_hourly_forecasted_24,LPACCPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_json)

obj_opf_forecasted_24

obj_bs_forecasted = [result_bs_hourly_forecasted_24["$i"]["objective"] for i in 1:n_hours]
sum(obj_bs_forecasted)


obj_fc_forecasted_ac = [result_forecasted_feasibility_checks_24_ac["$i"]["objective"] for i in 1:n_hours]
obj_fc_forecasted_lpac = [result_forecasted_feasibility_checks_24_lpac["$i"]["objective"] for i in 1:n_hours]

sum(obj_forecasted_24) - sum(obj_fc_forecasted)
(obj_forecasted_24 .- obj_fc_forecasted)./sum(obj_forecasted_24)*100



for (g_id,g) in test_case["gen"]
    if result_bs_hourly_forecasted_24["1"]["solution"]["gen"]["$g_id"]["pg"] > 0.001
        println("Gen $g_id, bus $(g["gen_bus"]), cost $(g["cost"][1]), pmax $(g["pmax"]), pg is $(opf_67["solution"]["gen"]["$g_id"]["pg"])")
    end
end


##############################################################
function prepare_starting_value_dict_lpac_nw_sp(grid,start_hour_simulation,end_hour_simulation,n_scenarios)
    count_ = 0
    for hour in start_hour_simulation:end_hour_simulation
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

function prepare_starting_value_dict_lpac_nw_opf(grid,result,start_hour_simulation,end_hour_simulation,n_scenarios)
    count_ = 0

    for hour in start_hour_simulation:end_hour_simulation
        count_ += 1
        for scenario_idx in 1:n_scenarios
            n = (count_ - 1)*n_scenarios + scenario_idx
            for (b_id,b) in grid["nw"]["$n"]["bus"]
                if haskey(result["$n"]["solution"]["bus"],b_id)
                    if abs(result["$n"]["solution"]["bus"]["$b_id"]["va"]) < 10^(-4)
                        b["va_starting_value"] = 0.0
                    else
                        b["va_starting_value"] = result["$n"]["solution"]["bus"]["$b_id"]["va"]
                    end
                    if abs(result["$n"]["solution"]["bus"]["$b_id"]["phi"]) < 10^(-4)
                        b["phi_starting_value"] = 0.0
                    else
                        b["phi_starting_value"] = result["$n"]["solution"]["bus"]["$b_id"]["phi"]
                    end
                else
                    b["va_starting_value"] = 0.0
                    b["phi_starting_value"] = 0.1
                end
            end
            for (b_id,b) in grid["nw"]["$n"]["gen"]
                if abs(result["$n"]["solution"]["gen"]["$b_id"]["pg"]) < 10^(-5)
                    b["pg_starting_value"] = 0.0
                else
                    b["pg_starting_value"] = result["$n"]["solution"]["gen"]["$b_id"]["pg"]
                end
                if abs(result["$n"]["solution"]["gen"]["$b_id"]["qg"]) < 10^(-5)
                    b["qg_starting_value"] = 0.0
                else
                    b["qg_starting_value"] = result["$n"]["solution"]["gen"]["$b_id"]["qg"]
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
                end
            end
        end
    end
end

test_case_bs_replicate_mn_forecasted_sp_24 = deepcopy(test_case_bs_replicate_mn_forecasted)
prepare_starting_value_dict_lpac_nw_sp(test_case_bs_replicate_mn_forecasted_sp_24,start_hour_simulation,end_hour_simulation,one_scenario)

result_bs_hourly_forecasted_one_topology_24 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology_sp(test_case_bs_replicate_mn_forecasted_sp_24,LPACCPowerModel,gurobi; setting = s)
result_bs_hourly_forecasted_one_topology_24_no_sp = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology(test_case_bs_replicate_mn_forecasted_sp_24,LPACCPowerModel,gurobi; setting = s)

[result_bs_hourly_forecasted_one_topology_24["solution"]["nw"]["1"]["switch"]["$sw_id"]["status"] for (sw_id,sw) in test_case_bs["switch"]]

function prepare_AC_feasibility_check_hourly(result_dict, input_dict, input_ac_check, switch_couples, extremes_dict,input_base,hour)
    orig_buses = maximum(parse.(Int, keys(input_base["bus"]))) # maximum value before splitting (in case the buses are not in numerical order)
    for (sw_id,sw) in input_dict["switch"]
        if !haskey(sw,"auxiliary")
            println("SWITCH $sw_id, BUS from $(sw["f_bus"]), BUS to $(sw["t_bus"])")
            if result_dict["solution"]["nw"]["$hour"]["switch"][sw_id]["status"] >= 0.9 # Just reconnecting stuff
                println("Switch $sw_id is closed, Connecting everything back, no busbar splitting on bus $(sw["bus_split"])")
                for l in keys(switch_couples)
                    #if haskey(switch_couples,sw_id) && switch_couples[l]["bus_split"] == sw["bus_split"] -> wrong, you are checking the ZIL sw here
                    if switch_couples[l]["bus_split"] == sw["bus_split"] # coupling the switch couple to their split bus, if it closed, just connect everything back to the original switch
                        println("SWITCH COUPLE IS $l")

                        switch_t = deepcopy(input_dict["switch"]["$(switch_couples["$l"]["t_sw"])"])
                        switch_f = deepcopy(input_dict["switch"]["$(switch_couples["$l"]["f_sw"])"])
                        
                        if switch_t["t_bus"] == switch_couples[l]["bus_split"]
                            aux_t = switch_t["auxiliary"]
                            orig_t = switch_t["original"]
                            println("Element $aux_t $orig_t")
                            if aux_t == "gen"
                                input_ac_check["gen"]["$(orig_t)"]["gen_bus"] = deepcopy(input_dict["switch"]["$(switch_t["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                                delete!(input_ac_check["bus"],input_ac_check["gen"]["$(orig_t)"]["gen_bus"])
                                println("Element $aux_t $orig_t connected to $(input_ac_check["gen"]["$(orig_t)"]["gen_bus"])")
                            elseif aux_t == "load"
                                input_ac_check["load"]["$(orig_t)"]["load_bus"] = deepcopy(input_dict["switch"]["$(switch_t["index"])"]["t_bus"])
                                delete!(input_ac_check["bus"],input_ac_check["load"]["$(orig_t)"]["load_bus"])
                                println("Element $aux_t $orig_t connected to $(input_ac_check["load"]["$(orig_t)"]["load_bus"])")
                            elseif aux_t == "convdc"
                                input_ac_check["convdc"]["$(orig_t)"]["busac_i"] = deepcopy(input_dict["switch"]["$(switch_t["index"])"]["t_bus"])
                                delete!(input_ac_check["bus"],input_ac_check["convdc"]["$(orig_t)"]["busac_i"])
                                println("Element $aux_t $orig_t connected to $(input_ac_check["convdc"]["$(orig_t)"]["busac_i"])")
                            elseif aux_t == "branch" 
                                if input_ac_check["branch"]["$(orig_t)"]["f_bus"] > orig_buses && input_dict["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"] # useful if both ends of a branch are busbars being split
                                    input_ac_check["branch"]["$(orig_t)"]["f_bus"] = deepcopy(input_dict["switch"]["$(switch_t["index"])"]["t_bus"])
                                    delete!(input_ac_check["bus"],input_ac_check["branch"]["$(orig_t)"]["f_bus"])
                                    println("Element $aux_t $orig_t connected to $(input_ac_check["branch"]["$(orig_t)"]["f_bus"])")
                                elseif input_ac_check["branch"]["$(orig_t)"]["t_bus"] > orig_buses && input_dict["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                    input_ac_check["branch"]["$(orig_t)"]["t_bus"] = deepcopy(input_dict["switch"]["$(switch_t["index"])"]["t_bus"])
                                    delete!(input_ac_check["bus"],input_ac_check["branch"]["$(orig_t)"]["t_bus"])
                                    println("Element $aux_t $orig_t connected to $(input_ac_check["branch"]["$(orig_t)"]["t_bus"])")
                                end
                            end
                        elseif switch_f["t_bus"] == switch_couples[l]["bus_split"]
                            aux_f = switch_f["auxiliary"]
                            orig_f = switch_f["original"]
                            println("Element $aux_f $orig_f")
                            if aux_f == "gen"
                                input_ac_check["gen"]["$(orig_f)"]["gen_bus"] = deepcopy(input_dict["switch"]["$(switch_f["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                                delete!(input_ac_check["bus"],input_ac_check["gen"]["$(orig_f)"]["gen_bus"])
                                println("Element $aux_f $orig_f connected to $(input_ac_check["gen"]["$(orig_f)"]["gen_bus"])")
                            elseif aux_f == "load"
                                input_ac_check["load"]["$(orig_f)"]["load_bus"] = deepcopy(input_dict["switch"]["$(switch_f["index"])"]["t_bus"])
                                delete!(input_ac_check["bus"],input_ac_check["load"]["$(orig_f)"]["load_bus"])
                                println("Element $aux_f $orig_f connected to $(input_ac_check["load"]["$(orig_f)"]["load_bus"])")
                            elseif aux_f == "convdc"
                                input_ac_check["convdc"]["$(orig_f)"]["busac_i"] = deepcopy(input_dict["switch"]["$(switch_f["index"])"]["t_bus"])
                                delete!(input_ac_check["bus"],input_ac_check["convdc"]["$(orig_f)"]["busac_i"])
                                println("Element $aux_f $orig_f connected to $(input_ac_check["convdc"]["$(orig_f)"]["busac_i"])")
                            elseif aux_f == "branch" 
                                if input_ac_check["branch"]["$(orig_f)"]["f_bus"] > orig_buses && input_dict["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"] # useful if both ends of a branch are busbars being split
                                    input_ac_check["branch"]["$(orig_f)"]["f_bus"] = deepcopy(input_dict["switch"]["$(switch_f["index"])"]["t_bus"])
                                    delete!(input_ac_check["bus"],input_ac_check["branch"]["$(orig_f)"]["f_bus"])
                                    println("Element $aux_f $orig_f connected to $(input_ac_check["branch"]["$(orig_f)"]["f_bus"])")
                                elseif input_ac_check["branch"]["$(orig_f)"]["t_bus"] > orig_buses && input_dict["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                    input_ac_check["branch"]["$(orig_f)"]["t_bus"] = deepcopy(input_dict["switch"]["$(switch_f["index"])"]["t_bus"])
                                    delete!(input_ac_check["bus"],input_ac_check["branch"]["$(orig_f)"]["t_bus"])
                                    println("Element $aux_f $orig_f connected to $(input_ac_check["branch"]["$(orig_f)"]["t_bus"])")
                                end
                            end
                        end
                    end
                end
            elseif result_dict["solution"]["nw"]["$hour"]["switch"][sw_id]["status"] <= 0.1 # Connect elements to the right bus
                println("Switch $sw_id is open, busbar splitting on bus $(sw["bus_split"])")
                delete!(input_ac_check["switch"],sw_id)
                for l in keys(switch_couples)
                    #if haskey(switch_couples,sw_id) && switch_couples[l]["bus_split"] == sw["bus_split"] -> wrong, you are checking the ZIL sw here
                    if switch_couples[l]["bus_split"] == sw["bus_split"] # coupling the switch couple to their split bus
                        println("SWITCH COUPLE IS $l")
                            switch_t = deepcopy(input_dict["switch"]["$(switch_couples["$l"]["t_sw"])"]) 
                            aux_t = switch_t["auxiliary"]
                            orig_t = switch_t["original"]
                            println("Element $aux_t $orig_t")
                            if result_dict["solution"]["nw"]["$hour"]["switch"]["$(switch_t["index"])"]["status"] <= 0.1
                                println("Deleting switch $(switch_t["index"])")
                                delete!(input_ac_check["switch"],"$(switch_t["index"])")
                            elseif result_dict["solution"]["nw"]["$hour"]["switch"]["$(switch_t["index"])"]["status"] >= 0.9
                                if aux_t == "gen"
                                    input_ac_check["gen"]["$(orig_t)"]["gen_bus"] = deepcopy(input_dict["switch"]["$(switch_t["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                                    delete!(input_ac_check["bus"],input_ac_check["gen"]["$(orig_t)"]["gen_bus"])
                                    println("Element $aux_t $orig_t connected to $(input_ac_check["gen"]["$(orig_t)"]["gen_bus"])")
                                elseif aux_t == "load"
                                    input_ac_check["load"]["$(orig_t)"]["load_bus"] = deepcopy(input_dict["switch"]["$(switch_t["index"])"]["t_bus"])
                                    delete!(input_ac_check["bus"],input_ac_check["load"]["$(orig_t)"]["load_bus"])
                                    println("Element $aux_t $orig_t connected to $(input_ac_check["load"]["$(orig_t)"]["load_bus"])")
                                elseif aux_t == "convdc"
                                    input_ac_check["convdc"]["$(orig_t)"]["busac_i"] = deepcopy(input_dict["switch"]["$(switch_t["index"])"]["t_bus"])
                                    delete!(input_ac_check["bus"],input_ac_check["convdc"]["$(orig_t)"]["busac_i"])
                                    println("Element $aux_t $orig_t connected to $(input_ac_check["convdc"]["$(orig_t)"]["busac_i"])")
                                elseif aux_t == "branch" 
                                    if input_ac_check["branch"]["$(orig_t)"]["f_bus"] > orig_buses && input_dict["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"] # useful if both ends of a branch are busbars being split
                                        input_ac_check["branch"]["$(orig_t)"]["f_bus"] = deepcopy(input_dict["switch"]["$(switch_t["index"])"]["t_bus"])
                                        delete!(input_ac_check["bus"],input_ac_check["branch"]["$(orig_t)"]["f_bus"])
                                        println("Element $aux_t $orig_t connected to $(input_ac_check["branch"]["$(orig_t)"]["f_bus"])")
                                    elseif input_ac_check["branch"]["$(orig_t)"]["t_bus"] > orig_buses && input_dict["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                        input_ac_check["branch"]["$(orig_t)"]["t_bus"] = deepcopy(input_dict["switch"]["$(switch_t["index"])"]["t_bus"])
                                        delete!(input_ac_check["bus"],input_ac_check["branch"]["$(orig_t)"]["t_bus"])
                                        println("Element $aux_t $orig_t connected to $(input_ac_check["branch"]["$(orig_t)"]["t_bus"])")
                                    end
                                end
                            end
                        

                            switch_f = deepcopy(input_dict["switch"]["$(switch_couples["$l"]["f_sw"])"]) 
                            aux_f = switch_f["auxiliary"]
                            orig_f = switch_f["original"]
                            println("Element $aux_f $orig_f")
                            if result_dict["solution"]["nw"]["$hour"]["switch"]["$(switch_f["index"])"]["status"] <= 0.1
                                println("Deleting switch $(switch_f["index"])")
                                delete!(input_ac_check["switch"],"$(switch_f["index"])")
                            elseif result_dict["solution"]["nw"]["$hour"]["switch"]["$(switch_f["index"])"]["status"] >= 0.9
                                if aux_f == "gen"
                                    input_ac_check["gen"]["$(orig_f)"]["gen_bus"] = deepcopy(input_dict["switch"]["$(switch_f["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                                    delete!(input_ac_check["bus"],input_ac_check["gen"]["$(orig_f)"]["gen_bus"])
                                    println("Element $aux_f $orig_f connected to $(input_ac_check["gen"]["$(orig_f)"]["gen_bus"])")
                                elseif aux_f == "load"
                                    input_ac_check["load"]["$(orig_f)"]["load_bus"] = deepcopy(input_dict["switch"]["$(switch_f["index"])"]["t_bus"])
                                    delete!(input_ac_check["bus"],input_ac_check["load"]["$(orig_f)"]["load_bus"])
                                    println("Element $aux_f $orig_f connected to $(input_ac_check["load"]["$(orig_f)"]["load_bus"])")
                                elseif aux_f == "convdc"
                                    input_ac_check["convdc"]["$(orig_f)"]["busac_i"] = deepcopy(input_dict["switch"]["$(switch_f["index"])"]["t_bus"])
                                    delete!(input_ac_check["bus"],input_ac_check["convdc"]["$(orig_f)"]["busac_i"])
                                    println("Element $aux_f $orig_f connected to $(input_ac_check["convdc"]["$(orig_f)"]["busac_i"])")
                                elseif aux_f == "branch" 
                                    if input_ac_check["branch"]["$(orig_f)"]["f_bus"] > orig_buses && input_dict["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"] # useful if both ends of a branch are busbars being split
                                        input_ac_check["branch"]["$(orig_f)"]["f_bus"] = deepcopy(input_dict["switch"]["$(switch_f["index"])"]["t_bus"])
                                        delete!(input_ac_check["bus"],input_ac_check["branch"]["$(orig_f)"]["f_bus"])
                                        println("Element $aux_f $orig_f connected to $(input_ac_check["branch"]["$(orig_f)"]["f_bus"])")
                                    elseif input_ac_check["branch"]["$(orig_f)"]["t_bus"] > orig_buses && input_dict["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                        input_ac_check["branch"]["$(orig_f)"]["t_bus"] = deepcopy(input_dict["switch"]["$(switch_f["index"])"]["t_bus"])
                                        delete!(input_ac_check["bus"],input_ac_check["branch"]["$(orig_f)"]["t_bus"])
                                        println("Element $aux_f $orig_f connected to $(input_ac_check["branch"]["$(orig_f)"]["t_bus"])")
                                    end
                                end
                            end
                    end
                end
            end
            input_ac_check["switch"] = Dict{String,Any}()
            input_ac_check["switch_couples"] = Dict{String,Any}()
        end
    end
end

function run_feasibility_checks_hourly(grid, result_bs, model, optimizer,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
    result_feasibility_checks = Dict{String,Any}()
    for hour in 1:length(grid["nw"])
        result_feasibility_checks["$hour"] = Dict{String,Any}()
        feasibility_check = deepcopy(grid["nw"]["$hour"])
        feasibility_check_input = deepcopy(grid["nw"]["$hour"])
        prepare_AC_feasibility_check_hourly(result_bs,feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf,hour)
        result_feasibility_checks["$hour"] = _PM.solve_opf(feasibility_check,model,optimizer; setting = s)
        #if isnan(result_feasibility_checks["$hour"]["objective"])
        #    result_feasibility_checks["$hour"] = deepcopy(result_opf["$hour"])
        #end
    end
    return result_feasibility_checks
end

function print_switch_results_one_topology(test_case,original_test_case,results,hour)
    for sw_id in 1:length(test_case["nw"]["$hour"]["switch"])
        if haskey(test_case["nw"]["$hour"]["switch"]["$(sw_id)"],"auxiliary")
            println("Switch $sw_id, aux is $(test_case["nw"]["$hour"]["switch"]["$(sw_id)"]["auxiliary"]), orig is $(test_case["nw"]["$hour"]["switch"]["$(sw_id)"]["original"]), t_bus is $(test_case["nw"]["$hour"]["switch"]["$(sw_id)"]["t_bus"]), $(results["solution"]["nw"]["$hour"]["switch"]["$sw_id"]["status"]), bus_split is $(test_case["nw"]["$hour"]["switch"]["$(sw_id)"]["bus_split"])")    
            if test_case["nw"]["$hour"]["switch"]["$(sw_id)"]["auxiliary"] == "branch"
                println("      Branch $(test_case["nw"]["$hour"]["switch"]["$(sw_id)"]["original"]), f_bus $(original_test_case["branch"]["$(test_case["nw"]["$hour"]["switch"]["$(sw_id)"]["original"])"]["f_bus"]), t_bus $(original_test_case["branch"]["$(test_case["nw"]["$hour"]["switch"]["$(sw_id)"]["original"])"]["t_bus"])")
            end
        else
            println("Switch $sw_id,  is $(results["solution"]["nw"]["$hour"]["switch"]["$sw_id"]["status"]), bus_split is $(test_case["nw"]["$hour"]["switch"]["$(sw_id)"]["bus_split"])")
        end
    end
end

result_fc_hourly_forecasted_one_topology_24 = run_feasibility_checks_hourly(test_case_bs_replicate_mn_forecasted,result_bs_hourly_forecasted_one_topology_24,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
[result_fc_hourly_forecasted_one_topology_24["$i"]["objective"] for i in 1:n_hours]
sum(result_fc_hourly_forecasted_one_topology_24["$i"]["objective"] for i in 1:n_hours)

##############################################################

test_case_bs_1_24 = deepcopy(test_case_bs_replicate_mn_forecasted_sp_24)
test_case_bs_1_24["total_switching_actions"] = 2
test_case_bs_1_result_24 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp(test_case_bs_1_24,LPACCPowerModel,gurobi)
result_fc_1_sw_lpac = run_feasibility_checks_hourly(test_case_bs_replicate_mn_forecasted_sp_24,test_case_bs_1_result_24,DCPPowerModel,gurobi,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
result_fc_1_sw = run_feasibility_checks_hourly(test_case_bs_replicate_mn_forecasted_sp_24,test_case_bs_1_result_24,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
sum(result_fc_1_sw["$i"]["objective"] for i in 1:n_hours)

[result_fc_1_sw_lpac["$i"]["objective"] for i in 1:n_hours]

sum(obj_forecasted_24) - sum(result_fc_1_sw["$i"]["objective"] for i in 1:n_hours)
(sum(obj_forecasted_24) - sum(result_fc_1_sw["$i"]["objective"] for i in 1:n_hours))/sum(obj_forecasted_24)*100

sw_1_one_sw_actions = [test_case_bs_1_result_24["solution"]["nw"]["$i"]["switch"]["1"]["status"] for i in 1:n_hours]


##############################################################
# Analysis of the results

[result_forecasted_feasibility_checks["$i"]["termination_status"] for i in 1:n_hours]
[result_fc_hourly_forecasted_one_topology_24["$i"]["termination_status"] for i in 1:n_hours]

[result_forecasted_feasibility_checks["$i"]["solution"]["gen"]["2"]["pg"] for i in 1:n_hours]
[result_fc_hourly_forecasted_one_topology_24["$i"]["solution"]["gen"]["2"]["pg"] for i in 1:n_hours]


test_case_opf["branch"]["1"]
test_case_opf["branch"]["2"]
test_case_opf["branch"]["3"]
test_case_opf["branch"]["4"]
test_case_opf["branch"]["5"]
test_case_opf["branch"]["6"]

print_switch_results_hourly(test_case_bs_replicate_mn_forecasted_sp_24,test_case_opf,result_bs_hourly_forecasted,4)
print_switch_results_one_topology(test_case_bs_replicate_mn_forecasted,test_case_opf,result_bs_hourly_forecasted_one_topology_24,4)

result_bs_hourly_forecasted_one_topology_24["objective"]
sum(result_bs_hourly_forecasted_24["$i"]["objective"] for i in 1:n_hours)
test_case_bs_1_result_24["objective"]

result_bs_hourly_forecasted_one_topology_24["objective"]/result_bs_hourly_forecasted_one_topology_24["objective"]
(1-sum(result_bs_hourly_forecasted_24["$i"]["objective"] for i in 1:n_hours)/result_bs_hourly_forecasted_one_topology_24["objective"])*100
(1-test_case_bs_1_result_24["objective"]/result_bs_hourly_forecasted_one_topology_24["objective"])*100
(1-test_case_bs_3_result_24["objective"]/result_bs_hourly_forecasted_one_topology_24["objective"])*100

result_fc_hourly_forecasted_one_topology_24["objective"]/result_bs_hourly_forecasted_one_topology_24["objective"]
(1-sum(result_bs_hourly_forecasted_24["$i"]["objective"] for i in 1:n_hours)/result_bs_hourly_forecasted_one_topology_24["objective"])*100


sum(result_fc_1_sw["$i"]["objective"] for i in 1:n_hours)
sum(result_fc_3_sw["$i"]["objective"] for i in 1:n_hours)


###

full_forecasted_sw_1 = [result_bs_hourly_forecasted_24["$i"]["solution"]["switch"]["1"]["status"] for i in 1:n_hours]
one_topology_sw_1 = [result_bs_hourly_forecasted_one_topology_24["solution"]["nw"]["$i"]["switch"]["1"]["status"] for i in 1:n_hours]
max_switch_1_sw_1 = [test_case_bs_1_result_24["solution"]["nw"]["$i"]["switch"]["1"]["status"] for i in 1:n_hours]
max_switch_2_sw_1 = [test_case_bs_2_result_24["solution"]["nw"]["$i"]["switch"]["1"]["status"] for i in 1:n_hours]

scatter(full_forecasted_sw_1,grid = :none,ylims = (-0.05,1.1),yticks = 0:1:1,ylabel = "Status switch 1, 1 = closed, 0 = open",xlabel = "Hour",label = "Hourly optimization",xlims=(0.5,n_hours+0.5),xticks = 1:1:(n_hours), legend = :left)
scatter!(one_topology_sw_1.-0.03,label = "One topology")
scatter!(max_switch_1_sw_1.+0.03,label = "Maximum 1 switching action")
scatter!(max_switch_2_sw_1.+0.06,label = "Maximum 2 switching actions")

obj_full_forecasted = [result_bs_hourly_forecasted_24["$i"]["objective"] for i in 1:n_hours]

fc_forecasted    = [result_forecasted_feasibility_checks["$i"]["objective"] for i in 1:n_hours]
fc_one_topology  = [result_fc_hourly_forecasted_one_topology_24["$i"]["objective"] for i in 1:n_hours]
obj_max_switch_1 = [result_fc_1_sw["$i"]["objective"] for i in 1:n_hours]
obj_max_switch_3 = [result_fc_3_sw["$i"]["objective"] for i in 1:n_hours]

plot(obj_forecasted_24,ylims = (5*10^3,17*10^3),yticks = 0:5000:15000,ylabel = "Generation costs [\$/h]",xlabel = "Hour",label = "OPF",xlims=(0.9,9),xticks = 1:1:8, legend = :topright, grid = :none)
plot!(fc_forecasted   ,label = "Hourly optimization")
plot!(fc_one_topology ,label = "One topology")
plot!(obj_max_switch_1,label = "Maximum 1 switching action")
plot!(obj_max_switch_3,label = "Maximum 2 switching actions")

##############################################################

br_1_fc_hourly  = [result_forecasted_feasibility_checks["$i"]["solution"]["branch"]["1"]["pf"] for i in 1:n_hours]
br_1_fc_one_top = [result_fc_hourly_forecasted_one_topology_24["$i"]["solution"]["branch"]["1"]["pf"] for i in 1:n_hours]

br_6_fc_hourly  = [result_forecasted_feasibility_checks["$i"]["solution"]["branch"]["6"]["pf"] for i in 1:n_hours]
br_6_fc_one_top = [result_fc_hourly_forecasted_one_topology_24["$i"]["solution"]["branch"]["6"]["pf"] for i in 1:n_hours]

br_7_fc_hourly  = [result_forecasted_feasibility_checks["$i"]["solution"]["branch"]["7"]["pf"] for i in 1:n_hours]
br_7_fc_one_top = [result_fc_hourly_forecasted_one_topology_24["$i"]["solution"]["branch"]["7"]["pf"] for i in 1:n_hours]

br_9_fc_hourly  = [result_forecasted_feasibility_checks["$i"]["solution"]["branch"]["9"]["pf"] for i in 1:n_hours]
br_9_fc_one_top = [result_fc_hourly_forecasted_one_topology_24["$i"]["solution"]["branch"]["9"]["pf"] for i in 1:n_hours]

br_10_fc_hourly  = [result_forecasted_feasibility_checks["$i"]["solution"]["branch"]["10"]["pf"] for i in 1:n_hours]
br_10_fc_one_top = [result_fc_hourly_forecasted_one_topology_24["$i"]["solution"]["branch"]["10"]["pf"] for i in 1:n_hours]

br_11_fc_hourly  = [result_forecasted_feasibility_checks["$i"]["solution"]["branch"]["11"]["pf"] for i in 1:n_hours]
br_11_fc_one_top = [result_fc_hourly_forecasted_one_topology_24["$i"]["solution"]["branch"]["11"]["pf"] for i in 1:n_hours]

br_12_fc_hourly  = [result_forecasted_feasibility_checks["$i"]["solution"]["branch"]["12"]["pf"] for i in 1:n_hours]
br_12_fc_one_top = [result_fc_hourly_forecasted_one_topology_24["$i"]["solution"]["branch"]["12"]["pf"] for i in 1:n_hours]

br_41_fc_hourly  = [result_forecasted_feasibility_checks["$i"]["solution"]["branch"]["41"]["pf"] for i in 1:n_hours]
br_41_fc_one_top = [result_fc_hourly_forecasted_one_topology_24["$i"]["solution"]["branch"]["41"]["pf"] for i in 1:n_hours]
