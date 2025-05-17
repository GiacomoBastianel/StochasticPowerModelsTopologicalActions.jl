using PowerModels; const _PM = PowerModels
using PowerModelsACDC; const _PMACDC = PowerModelsACDC
import PowerModelsTopologicalActionsII; const _PMTP = PowerModelsTopologicalActionsII
using FlexPlan; const _FP = FlexPlan
using Gurobi, Ipopt, JSON, Plots
import StochasticPowerModelsTopologicalActions; const _SPMTA = StochasticPowerModelsTopologicalActions
using JuMP, Juniper, HSL_jll, MathOptInterface, HiGHS
using Statistics

mip_gap = 1e-4
gurobi = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 3600,"MIPGap" => mip_gap,"BarHomogeneous" => 1,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "ScaleFlag"=>2, "NumericFocus"=>2)#, "MIPfocus" => 1) 
gurobi_opf = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 7200,"MIPGap" => mip_gap,"BarHomogeneous" => 1)#,,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "ScaleFlag"=>2, "NumericFocus"=>2) 
gurobi_hot = JuMP.optimizer_with_attributes(Gurobi.Optimizer)
ipopt = JuMP.optimizer_with_attributes(Ipopt.Optimizer, "tol" => 1e-6, "print_level" => 0,"linear_solver" => "ma97")
juniper = JuMP.optimizer_with_attributes(Juniper.Optimizer, "nl_solver" => ipopt, "mip_solver" => gurobi, "time_limit" => 36000)

#########################################################################################
## Processing input data
s = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true)
s_dual = Dict("output" => Dict("branch_flows" => true,"duals" => true), "conv_losses_mp" => true)

#########################################################################################
## Processing input data
input_folder = dirname(dirname(dirname(@__DIR__)))
test_case_118_file = joinpath(input_folder,"data_sources/pglib_opf_case118_ieee.m")
original_grid_118 = _PM.parse_file(test_case_118_file)
#pm_original = _PM.instantiate_model(original_grid_118, LPACCPowerModel, _PM.build_opf)

for (b_id,b) in original_grid_118["bus"]
    b["vmin"] = 0.9
    b["vmax"] = 1.1
end
function add_VOLL_generators(data)
    first_l = maximum(parse.(Int, keys(data["gen"])))
    count = 0
    for (b_id,b) in data["bus"]
        count += 1
        l = first_l + count
        data["gen"]["$l"] = deepcopy(data["gen"]["1"])
        data["gen"]["$l"]["gen_bus"] = parse(Int64,b_id) 
        data["gen"]["$l"]["pmax"] = 99.99
        data["gen"]["$l"]["source_id"][2] = deepcopy(l)
        data["gen"]["$l"]["index"] = l 
        push!(data["gen"]["$l"]["cost"],10000)
        push!(data["gen"]["$l"]["cost"],0.0)
    end
end
add_VOLL_generators(original_grid_118)


test_case_118_opf = deepcopy(original_grid_118)
opf_118 = _PM.solve_opf(original_grid_118, LPACCPowerModel, gurobi_opf)
opf_118_ac = _PM.solve_opf(original_grid_118, ACPPowerModel, ipopt, setting = s_dual)

#for (b_id,b) in test_case_118_opf["bus"]
#    b["vm_hot_start"] = opf_118_ac["solution"]["bus"][b_id]["vm"]
#end
#opf_118_lpac_h = _PM.solve_opf(test_case_118_opf,LPACHPowerModel,gurobi_opf; setting = s)


#########################################################################################
# Busbar splitting
input_folder = dirname(dirname(dirname(@__DIR__)))
test_case_118_file = joinpath(input_folder,"data_sources/pglib_opf_case118_ieee.m")
original_grid_118 = _PM.parse_file(test_case_118_file)
for (b_id,b) in original_grid_118["bus"]
    b["vmin"] = 0.9
    b["vmax"] = 1.1
end

test_case_118_bs = deepcopy(original_grid_118)
test_case_118_opf = deepcopy(original_grid_118)
splitted_bus_ac = 69

test_case_118_bs,  switches_couples_ac,  extremes_ZILs_ac  = _PMTP.AC_busbar_split_AC_grid(test_case_118_opf,splitted_bus_ac)
# Adding costs to the busbar couplers
for sw_id in 1:length(extremes_ZILs_ac)
    test_case_118_bs["switch"]["$sw_id"]["cost"] = 15.0
end

function prepare_starting_value_dict_lpac_hourly(grid)
    for (sw_id,sw) in grid["switch"]
        if !haskey(sw,"auxiliary") # calling ZILs
            sw["starting_value"] = 1.0
        else
            if haskey(grid["switch_couples"],sw_id)
                grid["switch"]["$(grid["switch_couples"][sw_id]["f_sw"])"]["starting_value"] = 0.0
                grid["switch"]["$(grid["switch_couples"][sw_id]["t_sw"])"]["starting_value"] = 1.0
            end
        end
    end
end

result_bs_118 = _PMTP.run_acdcsw_AC_big_M(test_case_118_bs,LPACCPowerModel,gurobi; setting = s)
prepare_starting_value_dict_lpac_hourly(test_case_118_bs)
#result_sp = _PMTP.run_acdcsw_AC_grid_big_M_sp(test_case_118_bs,LPACCPowerModel,gurobi)
test_case_bs_check = deepcopy(test_case_118_bs)
test_case_bs_check_auxiliary = deepcopy(test_case_118_bs)

_PMTP.prepare_AC_feasibility_check(result_bs_118,test_case_bs_check_auxiliary,test_case_bs_check,switches_couples_ac,extremes_ZILs_ac,original_grid_118)
results_dict_ac_check = deepcopy(_PMACDC.run_acdcopf(test_case_bs_check,ACPPowerModel,ipopt; setting = s))
results_dict_lpac_check = deepcopy(_PMACDC.run_acdcopf(test_case_bs_check,LPACCPowerModel,gurobi; setting = s))


for (g_id,g) in original_grid_118["gen"]
    if length(g["cost"]) > 0#opf_118_ac["solution"]["gen"]["$g_id"]["pg"] > 0.0
        println("Gen $g_id, bus $(g["gen_bus"]), cost $(g["cost"][1]), pmax $(g["pmax"]), pg is $(opf_118_ac["solution"]["gen"]["$g_id"]["pg"])")
    end
end
# Gen 30, bus 69 -> generating the most
# Gen 45, bus 100 -> cheapest, generating 6.53

duals = [abs(opf_118_ac["solution"]["bus"]["$b_id"]["lam_kcl_r"]) for (b_id,b) in original_grid_118["bus"]]
duals_b_id = [[parse(Int,b_id),abs(opf_118_ac["solution"]["bus"]["$b_id"]["lam_kcl_r"])] for (b_id,b) in original_grid_118["bus"]]
avg_dual = mean(duals)
cong_index = [[parse(Int,b_id),abs(opf_118_ac["solution"]["bus"]["$b_id"]["lam_kcl_r"])/avg_dual] for (b_id,b) in original_grid_118["bus"]]
cong_index = sort(cong_index, by = x -> x[2], rev = true)

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
_SPMTA.add_dimensions!(test_case_118_bs,one_scenario,n_hours)

#########################################################################################
# Uploading pdf samples for offshore wind and load data for Belgium
year_wind = "2024"
folder_data = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Elia_data"
folder_results = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Deliverable_1_2_DIRECTIONS/Results/case_118"

Gaussian_samples = JSON.parsefile(joinpath(folder_data,"Gaussian_samples_8_Offshore_wind_$(year_wind)_Elia.json"))
Elia_OFW = JSON.parsefile(joinpath(folder_data,"Offshore_wind_$(year_wind)_Elia_sorted.json"))

# Only hours
differences_gen = [(Elia_OFW[i]["dayahead11hforecast"] - Elia_OFW[i]["measured"]) for i in 1:length(Elia_OFW) if Elia_OFW[i]["minute"] == "00"]
capacity_factors_ofw = [Elia_OFW[i]["measured"]/Elia_OFW[i]["monitoredcapacity"] for i in 1:length(Elia_OFW) if Elia_OFW[i]["minute"] == "00"]
is = [i for i in 1:length(Elia_OFW) if Elia_OFW[i]["minute"] == "00"]
capacity_factors_118 = capacity_factors_ofw[start_hour_simulation:end_hour_simulation]

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

P50_11h = []
for i in 1:length(Elia_OFW)
    if Elia_OFW[i]["minute"] == "00"
        push!(P50_11h,Elia_OFW[i]["dayahead11hforecast"]/Elia_OFW[i]["monitoredcapacity"])
    end
end
scatter(P50_11h)
findmin(P50_11h)
findmax(P50_11h)

plot(P50_11h[355:366])

forecasted_wind_118 = P50_11h[355:378]

#########################################################################################
## Running simulations
# Busbar splitting
test_case_118_opf_replicate = _PM.replicate(original_grid_118, n_hours)
test_case_118_bs_replicate = _PM.replicate(test_case_118_bs, n_hours)

for (nw_id,nw) in test_case_118_opf_replicate["nw"]
    nw["probability"] = 1.0
    nw["per_unit"] = true
end
test_case_118_opf_mn_measured = deepcopy(test_case_118_opf_replicate)
test_case_118_opf_mn_forecasted = deepcopy(test_case_118_opf_replicate)
for i in 1:(n_hours*one_scenario)
    for (g_id,g) in test_case_118_opf_mn_forecasted["nw"]["$i"]["gen"]
        if g_id == "45" || g_id == "30"
            g["pmax"] = deepcopy(test_case_118_bs_replicate["nw"]["$i"]["gen"][g_id]["pmax"]*forecasted_wind_118[i])
        end
    end
end
test_case_118_bs_replicate = _PM.replicate(test_case_118_bs, n_hours)
for (nw_id,nw) in test_case_118_bs_replicate["nw"]
    nw["probability"] = 1.0
    nw["per_unit"] = true
end
test_case_118_bs_replicate_mn_forecasted = deepcopy(test_case_118_bs_replicate)
for i in 1:(n_hours*one_scenario)
    for (g_id,g) in test_case_118_bs_replicate_mn_forecasted["nw"]["$i"]["gen"]
        if g_id == "45" || g_id == "30"
            g["pmax"] = deepcopy(test_case_118_bs_replicate["nw"]["$i"]["gen"][g_id]["pmax"]*forecasted_wind_118[i])
        end
    end
end

function adding_multinetwork_scenarios(test_case_118, n_hours, n_scenarios)
    for hour in 1:n_hours
        for scenario_idx in 1:n_scenarios
            n = (hour - 1)*n_scenarios + scenario_idx
            add_hour_scenario_probability(test_case_118,hour,scenario_idx,n)
        end
    end
    test_case_118["scenarios"] = n_scenarios
    test_case_118["hours"] = n_hours
    return test_case_118
end

function add_hour_scenario_probability(data,hour,scenario,index)
    data["nw"]["$index"]["hour"] = hour
    data["nw"]["$index"]["scenario"] = scenario
    data["nw"]["$index"]["hour_scenario_index"] = [hour,scenario,index]
    #data["nw"]["$index"]["probability"] = time_series["scenario_probability"]["$index"]
end

adding_multinetwork_scenarios(test_case_118_bs_replicate,n_hours,one_scenario)
adding_multinetwork_scenarios(test_case_118_bs_replicate_mn_forecasted,n_hours,one_scenario)

##############################################################
## Running simulations
# Busbar splitting for 12 hours, simulating one hour per time
# Busbar splitting 
function run_stochastic_acdcsw_AC_ZIL_per_hour(grid, model, optimizer, n_hours, n_scenarios; setting = s)
    result = Dict{String,Any}()
    #=
    for hour in 1:n_hours
        result["$hour"] = Dict{String,Any}()
        scenarios_hour = collect(((hour-1)*n_scenarios + 1):(hour*n_scenarios))
        grid_hour = deepcopy(grid)
        grid_hour["hours"] = 1
        grid_hour["nw"]= Dict{String,Any}()
        for i in scenarios_hour
            grid_hour["nw"]["$i"] = deepcopy(grid["nw"]["$i"])
        end    
        result["$hour"] = _SPMTA.run_stochastic_acdcsw_AC_ZIL_hourly(grid_hour,model,optimizer; setting = setting)
    end
    =#
    for hour in 1:n_hours*n_scenarios
        result["$hour"] = Dict{String,Any}()
        result["$hour"] = _PMTP.run_acdcsw_AC_big_M_hour(grid["nw"]["$hour"],model,optimizer; setting = setting) 
    end
    return result
end

function run_feasibility_checks_per_hour(grid, result_bs, model, optimizer,switches_couples_ac,extremes_ZILs_ac,test_case_118_opf)
    result_feasibility_checks = Dict{String,Any}()
    for hour in 1:length(grid["nw"])
        result_feasibility_checks["$hour"] = Dict{String,Any}()
        feasibility_check = deepcopy(grid["nw"]["$hour"])
        feasibility_check_input = deepcopy(grid["nw"]["$hour"])
        _PMTP.prepare_AC_feasibility_check(result_bs["$hour"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_118_opf)
        result_feasibility_checks["$hour"] = _PM.solve_opf(feasibility_check,model,optimizer; setting = s)
        #if isnan(result_feasibility_checks["$hour"]["objective"])
        #    result_feasibility_checks["$hour"] = deepcopy(result_opf["$hour"])
        #end
    end
    return result_feasibility_checks
end

result_118_opf_forecasted = Dict{String,Any}()
for hour in 1:(n_hours*one_scenario)
    result_118_opf_forecasted["$hour"] = _PM.solve_opf(test_case_118_opf_mn_forecasted["nw"]["$hour"],ACPPowerModel,ipopt; setting = s)
end
result_118_lpac = Dict{String,Any}()
for hour in 1:(n_hours*one_scenario)
    result_118_lpac["$hour"] = _PM.solve_opf(test_case_118_opf_mn_forecasted["nw"]["$hour"],LPACCPowerModel,gurobi_opf; setting = s)
end
result_118_lpac_hot = Dict{String,Any}()
for hour in 1:(n_hours*one_scenario)
    for (b_id,b) in test_case_118_opf_mn_forecasted["nw"]["$hour"]["bus"]
        b["vm_hot_start"] = result_118_opf_forecasted["$hour"]["solution"]["bus"][b_id]["vm"]
    end
    result_118_lpac_hot["$hour"] = _PM.solve_opf(test_case_118_opf_mn_forecasted["nw"]["$hour"],LPACHPowerModel,gurobi_opf; setting = s)
end

obj = [result_118_opf_forecasted["$i"]["objective"] for i in 1:n_hours]
sum(obj)
obj_lpac = [result_118_lpac["$i"]["objective"] for i in 1:n_hours]
sum(obj_lpac)

obj_lpac_hot = [result_118_lpac_hot["$i"]["objective"] for i in 1:n_hours]
sum(obj_lpac)


##############################################################

result_bs_hourly_forecasted_118 = run_stochastic_acdcsw_AC_ZIL_per_hour(test_case_118_bs_replicate_mn_forecasted,LPACCPowerModel,gurobi,n_hours,one_scenario)
result_forecasted_feasibility_checks_118_ac = run_feasibility_checks_per_hour(test_case_118_bs_replicate_mn_forecasted,result_bs_hourly_forecasted_118,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,original_grid_118)
result_forecasted_feasibility_checks_118_lpac = run_feasibility_checks_per_hour(test_case_118_bs_replicate_mn_forecasted,result_bs_hourly_forecasted_118,LPACCPowerModel,gurobi,switches_couples_ac,extremes_ZILs_ac,original_grid_118)

obj_bs_forecasted_118 = [result_bs_hourly_forecasted_118["$i"]["objective"] for i in 1:n_hours]
sum(obj_bs_forecasted_118)

obj_fc_forecasted_118_lpac = [result_forecasted_feasibility_checks_118_lpac["$i"]["objective"] for i in 1:n_hours]
sum(obj_fc_forecasted_118_lpac)

obj_fc_forecasted_118_ac = [result_forecasted_feasibility_checks_118_ac["$i"]["objective"] for i in 1:n_hours]
sum_obj_bs = sum(obj_fc_forecasted_118_ac)
obj
sum_obj = sum(obj)

((sum_obj - sum_obj_bs)/sum_obj)*100

[result_bs_hourly_forecasted_118["$i"]["solution"]["switch"]["1"]["status"] for i in 1:n_hours]


function print_switch_results_hourly(test_case_118,original_test_case_118,results,hour)
    for sw_id in 1:length(test_case_118["nw"]["$hour"]["switch"])
        if haskey(test_case_118["nw"]["$hour"]["switch"]["$(sw_id)"],"auxiliary")
            println("Switch $sw_id, aux is $(test_case_118["nw"]["$hour"]["switch"]["$(sw_id)"]["auxiliary"]), orig is $(test_case_118["nw"]["$hour"]["switch"]["$(sw_id)"]["original"]), t_bus is $(test_case_118["nw"]["$hour"]["switch"]["$(sw_id)"]["t_bus"]), $(results["$hour"]["solution"]["switch"]["$sw_id"]["status"]), bus_split is $(test_case_118["nw"]["$hour"]["switch"]["$(sw_id)"]["bus_split"])")    
            if test_case_118["nw"]["$hour"]["switch"]["$(sw_id)"]["auxiliary"] == "branch"
                println("      Branch $(test_case_118["nw"]["$hour"]["switch"]["$(sw_id)"]["original"]), f_bus $(original_test_case_118["branch"]["$(test_case_118["nw"]["$hour"]["switch"]["$(sw_id)"]["original"])"]["f_bus"]), t_bus $(original_test_case_118["branch"]["$(test_case_118["nw"]["$hour"]["switch"]["$(sw_id)"]["original"])"]["t_bus"])")
            end
        else
            println("Switch $sw_id,  is $(results["$hour"]["solution"]["switch"]["$sw_id"]["status"]), bus_split is $(test_case_118["nw"]["$hour"]["switch"]["$(sw_id)"]["bus_split"])")
        end
    end
end
switches = Dict{String,Any}()
for i in 1:(n_hours*one_scenario)
    switches["$i"] = []
    #print_switch_results_hourly(test_case_118_bs_replicate_mn_forecasted,test_case_118_opf,result_bs_hourly_forecasted_118,i)
    for (sw_id,sw) in test_case_118_bs_replicate_mn_forecasted["nw"]["1"]["switch"]
        println(sw_id)
        push!(switches["$i"],result_bs_hourly_forecasted_118["$i"]["solution"]["switch"]["$sw_id"]["status"])
    end
    println("--------")
end

[[g_id,result_bs_hourly_forecasted["1"]["solution"]["gen"]["$g_id"]["pg"] ] for (g_id,g) in test_case_118_bs_replicate_mn_forecasted["nw"]["1"]["gen"]]

##############################################################



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

test_case_118_bs_replicate_mn_forecasted_sp_118 = deepcopy(test_case_118_bs_replicate_mn_forecasted)
prepare_starting_value_dict_lpac_nw_sp(test_case_118_bs_replicate_mn_forecasted_sp_118,start_hour_simulation,end_hour_simulation,one_scenario)

#result_bs_hourly_one_topology_118            = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology_sp(test_case_118_bs_replicate_sp              ,LPACCPowerModel,gurobi; setting = s)
#result_bs_hourly_measured_one_topology   = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology_sp(test_case_118_bs_replicate_mn_measured_sp  ,LPACCPowerModel,gurobi_opf; setting = s)
result_bs_hourly_forecasted_one_topology_118 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology_sp(test_case_118_bs_replicate_mn_forecasted_sp_118,LPACCPowerModel,gurobi; setting = s)


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

function run_feasibility_checks_hourly(grid, result_bs, model, optimizer,switches_couples_ac,extremes_ZILs_ac,test_case_118_opf)
    result_feasibility_checks = Dict{String,Any}()
    for hour in 1:length(grid["nw"])
        result_feasibility_checks["$hour"] = Dict{String,Any}()
        feasibility_check = deepcopy(grid["nw"]["$hour"])
        feasibility_check_input = deepcopy(grid["nw"]["$hour"])
        prepare_AC_feasibility_check_hourly(result_bs,feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_118_opf,hour)
        result_feasibility_checks["$hour"] = _PM.solve_opf(feasibility_check,model,optimizer; setting = s)
        #if isnan(result_feasibility_checks["$hour"]["objective"])
        #    result_feasibility_checks["$hour"] = deepcopy(result_opf["$hour"])
        #end
    end
    return result_feasibility_checks
end

function print_switch_results_one_topology(test_case_118,original_test_case_118,results,hour)
    for sw_id in 1:length(test_case_118["nw"]["$hour"]["switch"])
        if haskey(test_case_118["nw"]["$hour"]["switch"]["$(sw_id)"],"auxiliary")
            println("Switch $sw_id, aux is $(test_case_118["nw"]["$hour"]["switch"]["$(sw_id)"]["auxiliary"]), orig is $(test_case_118["nw"]["$hour"]["switch"]["$(sw_id)"]["original"]), t_bus is $(test_case_118["nw"]["$hour"]["switch"]["$(sw_id)"]["t_bus"]), $(results["solution"]["nw"]["$hour"]["switch"]["$sw_id"]["status"]), bus_split is $(test_case_118["nw"]["$hour"]["switch"]["$(sw_id)"]["bus_split"])")    
            if test_case_118["nw"]["$hour"]["switch"]["$(sw_id)"]["auxiliary"] == "branch"
                println("      Branch $(test_case_118["nw"]["$hour"]["switch"]["$(sw_id)"]["original"]), f_bus $(original_test_case_118["branch"]["$(test_case_118["nw"]["$hour"]["switch"]["$(sw_id)"]["original"])"]["f_bus"]), t_bus $(original_test_case_118["branch"]["$(test_case_118["nw"]["$hour"]["switch"]["$(sw_id)"]["original"])"]["t_bus"])")
            end
        else
            println("Switch $sw_id,  is $(results["solution"]["nw"]["$hour"]["switch"]["$sw_id"]["status"]), bus_split is $(test_case_118["nw"]["$hour"]["switch"]["$(sw_id)"]["bus_split"])")
        end
    end
end

result_fc_hourly_forecasted_one_topology_118 = run_feasibility_checks_hourly(test_case_118_bs_replicate_mn_forecasted,result_bs_hourly_forecasted_one_topology_118,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_118_opf)
[result_fc_hourly_forecasted_one_topology_118["$i"]["objective"] for i in 1:n_hours]
sum(result_fc_hourly_forecasted_one_topology_118["$i"]["objective"] for i in 1:n_hours)


print_switch_results_hourly(test_case_118_bs_replicate_mn_forecasted_sp_118,test_case_118_opf,result_bs_hourly_forecasted,4)
print_switch_results_one_topology(test_case_118_bs_replicate_mn_forecasted,test_case_118_opf,result_bs_hourly_forecasted_one_topology_118,4)

result_bs_hourly_forecasted_one_topology_118["objective"]
sum(result_bs_hourly_forecasted_118["$i"]["objective"] for i in 1:n_hours)
test_case_118_bs_1_result_118["objective"]

result_bs_hourly_forecasted_one_topology_118["objective"]/result_bs_hourly_forecasted_one_topology_118["objective"]
(1-sum(result_bs_hourly_forecasted_118["$i"]["objective"] for i in 1:n_hours)/result_bs_hourly_forecasted_one_topology_118["objective"])*100
(1-test_case_118_bs_1_result_118["objective"]/result_bs_hourly_forecasted_one_topology_118["objective"])*100
(1-test_case_118_bs_3_result_118["objective"]/result_bs_hourly_forecasted_one_topology_118["objective"])*100


##############################################################

test_case_118_bs_1_118 = deepcopy(test_case_118_bs_replicate_mn_forecasted_sp_118)
test_case_118_bs_1_118["total_switching_actions"] = 1
test_case_118_bs_1_result_118 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp(test_case_118_bs_1_118,LPACCPowerModel,gurobi_opf)
result_fc_1_sw = run_feasibility_checks_hourly(test_case_118_bs_replicate_mn_forecasted_sp_118,test_case_118_bs_1_result_118,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_118_opf)
sum(result_fc_1_sw["$i"]["objective"] for i in 1:n_hours)

[test_case_118_bs_1_result_118["solution"]["nw"]["$i"]["switch"]["1"]["status"] for i in 1:n_hours]


test_case_118_bs_2_118 = deepcopy(test_case_118_bs_replicate_mn_forecasted_sp_118)
test_case_118_bs_2_118["total_switching_actions"] = 2
test_case_118_bs_2_result_118 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp(test_case_118_bs_2_118,LPACCPowerModel,gurobi)
result_fc_2_sw = run_feasibility_checks_hourly(test_case_118_bs_replicate_mn_forecasted_sp_118,test_case_118_bs_2_result_118,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_118_opf)
sum(result_fc_2_sw["$i"]["objective"] for i in 1:n_hours)

[test_case_118_bs_2_result_118["solution"]["nw"]["$i"]["switch"]["1"]["status"] for i in 1:n_hours]


test_case_118_bs_3_118 = deepcopy(test_case_118_bs_replicate_mn_forecasted_sp_118)
test_case_118_bs_3_118["total_switching_actions"] = 3
test_case_118_bs_3_result_118 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp(test_case_118_bs_3_118,LPACCPowerModel,gurobi)
result_fc_3_sw = run_feasibility_checks_hourly(test_case_118_bs_replicate_mn_forecasted_sp_118,test_case_118_bs_3_result_118,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_118_opf)
sum(result_fc_3_sw["$i"]["objective"] for i in 1:n_hours)

[test_case_118_bs_3_result_118["solution"]["nw"]["$i"]["switch"]["1"]["status"] for i in 1:n_hours]
