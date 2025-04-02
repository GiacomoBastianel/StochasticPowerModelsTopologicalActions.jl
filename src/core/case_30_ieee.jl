using PowerModels; const _PM = PowerModels
using PowerModelsACDC; const _PMACDC = PowerModelsACDC
import PowerModelsTopologicalActionsII; const _PMTP = PowerModelsTopologicalActionsII
using FlexPlan; const _FP = FlexPlan
using Gurobi, Ipopt, JSON, Plots
import StochasticPowerModelsTopologicalActions; const _SPMTA = StochasticPowerModelsTopologicalActions
using JuMP, Juniper, HSL_jll, MathOptInterface, HiGHS

mip_gap = 1e-4
gurobi = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 300,"MIPGap" => mip_gap,"BarHomogeneous" => 1,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "ScaleFlag"=>2, "NumericFocus"=>2) 
gurobi_opf = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 600,"MIPGap" => mip_gap)#,"BarHomogeneous" => 1,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "ScaleFlag"=>2, "NumericFocus"=>2) 
ipopt = JuMP.optimizer_with_attributes(Ipopt.Optimizer, "tol" => 1e-6, "print_level" => 0,"linear_solver" => "ma97")
juniper = JuMP.optimizer_with_attributes(Juniper.Optimizer, "nl_solver" => ipopt, "mip_solver" => gurobi, "time_limit" => 36000)

#########################################################################################
## Processing input data
s = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true)
s_dual = Dict("output" => Dict("branch_flows" => true,"duals" => true), "conv_losses_mp" => true)

#########################################################################################
## Processing input data
input_folder = dirname(dirname(@__DIR__))
test_case_file = joinpath(input_folder,"data_sources/pglib_opf_case30_ieee.m")
test_case = _PM.parse_file(test_case_file)

#=
function add_OFW_generator!(grid_data, gen_bus, power_rating, gen_cost; gen_id = nothing, status = 1) 
    if isnothing(gen_id)
        gen_idx = maximum([gen["index"] for (g, gen) in grid_data["gen"]]) + 1
    else
        gen_idx = gen_id
    end
    grid_data["gen"]["$gen_idx"] = Dict{String, Any}()  
    grid_data["gen"]["$gen_idx"]["type_tyndp"] = "Offshore Wind"
    grid_data["gen"]["$gen_idx"]["model"] = 2  
    grid_data["gen"]["$gen_idx"]["gen_bus"] = gen_bus
    grid_data["gen"]["$gen_idx"]["pmax"] = power_rating 
    grid_data["gen"]["$gen_idx"]["installed_capacity"] = power_rating 
    grid_data["gen"]["$gen_idx"]["vg"] = 1.0
    grid_data["gen"]["$gen_idx"]["source_id"] = []
    push!(grid_data["gen"]["$gen_idx"]["source_id"],"gen")
    push!(grid_data["gen"]["$gen_idx"]["source_id"],gen_idx)
    grid_data["gen"]["$gen_idx"]["index"] = gen_idx
    grid_data["gen"]["$gen_idx"]["cost"] = []
    push!(grid_data["gen"]["$gen_idx"]["cost"],gen_cost)
    push!(grid_data["gen"]["$gen_idx"]["cost"],0.0)
    grid_data["gen"]["$gen_idx"]["qmax"] = 6.0 
    grid_data["gen"]["$gen_idx"]["gen_status"] = 1
    grid_data["gen"]["$gen_idx"]["qmin"] = - 6.0 
    grid_data["gen"]["$gen_idx"]["type"] = "Offshore Wind"  
    grid_data["gen"]["$gen_idx"]["pmin"] = 0.0 
    grid_data["gen"]["$gen_idx"]["ncost"] = 2 
    
    return gen_idx
end
add_OFW_generator!(test_case,2,1.5,20.0)
=#

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
# Results from busbar splitting
result_bs_30 = JSON.parsefile("/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Busbar_splitting_metrics_results/case_30/split_one_bus_per_time.json")
obj_bs = [[result_bs_30["$i"]["objective"],i] for i in 1:length(result_bs_30) if result_bs_30["$i"]["objective"] != nothing]
# -> busbars 2, 4 and 6 are the best candidates for splitting

test_case_bs = deepcopy(test_case)
splitted_bus_ac = 6
test_case_bs,  switches_couples_ac,  extremes_ZILs_ac  = _PMTP.AC_busbar_split_AC_grid(test_case,splitted_bus_ac)
result_bs_6 = _PMTP.run_acdcsw_AC_grid_big_M(test_case_bs, LPACCPowerModel, gurobi)

#########################################################################################
n_hours = 12
start_hour_simulation = 1
end_hour_simulation = 12
hours = collect(start_hour_simulation:end_hour_simulation)
n_scenarios = 1

#########################################################################################
# Uploading pdf samples for offshore wind and load data for Belgium
year_wind = "2024"
folder_data = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Elia_data"
folder_results = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Deliverable_1_2_DIRECTIONS/Results/case_30"

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
capacity_factors_30 = capacity_factors_ofw[start_hour_simulation:end_hour_simulation]

Load_2024_file = joinpath(folder_data,"Elia_load_$(year_wind).json")
Load_2024 = JSON.parsefile(Load_2024_file)
total_loads = [Load_2024[i]["totalload"] for i in 1:length(Load_2024)]
max_load = maximum(total_loads)

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

measured   = [Wind_data["$i"]["measured_pu"]   for i in 1:length(hours)]
forecasted = [Wind_data["$i"]["P50_11hforecast_pu"] for i in 1:length(hours)]

#########################################################################################
# OFW at gen 30 and 45
res_time_series_hour  = _SPMTA.create_RES_time_series_base(test_case_bs,Wind_data,n_scenarios,start_hour_simulation,end_hour_simulation)
gen_time_series_hour  = _SPMTA.create_gen_time_series_base_scenarios(test_case_bs,Wind_data,start_hour_simulation,end_hour_simulation,n_scenarios)
load_time_series_hour = _SPMTA.add_load_time_series_base_scenario(test_case_bs, test_case, start_hour_simulation, end_hour_simulation, n_scenarios)
time_series_hour      = _SPMTA.generate_input_dict_stochastic_optimization(gen_time_series_hour,res_time_series_hour,load_time_series_hour,start_hour_simulation,end_hour_simulation,Wind_data)

#########################################################################################
_SPMTA.add_hour_scenario_data(test_case_bs, n_hours, n_scenarios)
_SPMTA.add_hour_scenario_data(test_case_opf, n_hours, n_scenarios)

test_case_bs_mn = _SPMTA.make_multinetwork_time_series_base_scenarios(test_case_bs,n_hours,n_scenarios,start_hour_simulation,end_hour_simulation,time_series_hour)
test_case_opf_mn = _SPMTA.make_multinetwork_time_series_base_scenarios(test_case_opf,n_hours,n_scenarios,start_hour_simulation,end_hour_simulation,time_series_hour)

test_case_opf_mn_measured = deepcopy(test_case_opf_mn)
test_case_opf_mn_forecasted = deepcopy(test_case_opf_mn)


for (nw_id,nw) in test_case_opf_mn["nw"]
    nw["per_unit"] = true
    nw["probability"] = 1.0
end
#test_case_opf_test = _PM.replicate(test_case_opf,24)
#for (nw_id,nw) in test_case_opf_test["nw"]
#    nw["per_unit"] = true
#    nw["probability"] = 1.0
#end
test_case_opf_test_measured = deepcopy(test_case_opf_mn)
test_case_opf_test_forecasted = deepcopy(test_case_opf_mn)


for i in 1:n_hours
    test_case_opf_mn_measured["nw"]["$i"]["gen"]["1"]["pmax"] = test_case_opf_mn_measured["nw"]["$i"]["gen"]["1"]["pmax"]*measured[i]
    test_case_opf_mn_forecasted["nw"]["$i"]["gen"]["1"]["pmax"] = test_case_opf_mn_forecasted["nw"]["$i"]["gen"]["1"]["pmax"]*forecasted[i]
    #test_case_opf_test["nw"]["$i"]["gen"]["1"]["pmax"] = test_case_opf_test["nw"]["$i"]["gen"]["1"]["pmax"]*forecasted[i]
end

result_opf = _SPMTA.run_stochastic_acdc_opf(test_case_opf_mn_measured,LPACCPowerModel,gurobi_opf; setting = s)


test_case_bs_test_measured   = deepcopy(test_case_bs_mn)
test_case_bs_test_forecasted = deepcopy(test_case_bs_mn)
for i in 1:n_hours
    test_case_bs_test_measured["nw"]["$i"]["gen"]["1"]["pmax"] = test_case_bs_test_measured["nw"]["$i"]["gen"]["1"]["pmax"]*measured[i]
    test_case_bs_test_forecasted["nw"]["$i"]["gen"]["1"]["pmax"] = test_case_bs_test_forecasted["nw"]["$i"]["gen"]["1"]["pmax"]*forecasted[i]
end

test_case_bs_mn_sp_measured   = deepcopy(test_case_bs_test_measured)
test_case_bs_mn_sp_forecasted = deepcopy(test_case_bs_test_forecasted)

result_bs_one_topology = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology(test_case_bs_mn_sp_measured,LPACCPowerModel,gurobi_opf; setting = s)

[result_bs_one_topology["solution"]["nw"]["1"]["switch"]["$sw"]["status"] for sw in 1:length(test_case["switch"])]

#prepare_starting_value_dict_lpac_nw(test_case_bs_mn_sp,start_hour_simulation,end_hour_simulation,n_scenarios)

#result_bs = _SPMTA.run_stochastic_acdcsw_AC_ZIL_sp(test_case_bs_mn_sp,LPACCPowerModel,gurobi; setting = s)

test_case_bs_mn_la = deepcopy(test_case_bs_mn)
test_case_bs_mn_la["switching_actions"] = 4
test_case_bs_mn_la_sp = deepcopy(test_case_bs_mn_la)
#prepare_starting_value_dict_lpac_nw(test_case_bs_mn_la_sp,start_hour_simulation,end_hour_simulation,n_scenarios)

result_bs_mn_la = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions(test_case_bs_mn_la,LPACCPowerModel,gurobi_opf; setting = s)


function run_stochastic_acdcsw_AC_ZIL_h(grid, model, optimizer, n_hours, n_scenarios; setting = s)
    result = Dict{String,Any}()
    for hour in 1:n_hours
        scenarios_hour = collect(((hour-1)*n_scenarios + 1):(hour*n_scenarios))
        grid_hour = deepcopy(grid)
        grid_hour["hours"] = 1
        grid_hour["nw"]= Dict{String,Any}()
        for i in scenarios_hour
            grid_hour["nw"]["$i"] = deepcopy(grid["nw"]["$i"])
        end    
        result["$hour"] = _SPMTA.run_stochastic_acdcsw_AC_ZIL_hourly(grid_hour,model,optimizer; setting = setting)
    end
    return result
end

function prepare_starting_value_dict_lpac_nw(grid,start_hour_simulation,end_hour_simulation,n_scenarios)
    count_ = 0
    for hour in start_hour_simulation:end_hour_simulation
        count_ += 1
        for scenario_idx in 1:n_scenarios
            n = (count_ - 1)*n_scenarios + scenario_idx
            #=
            for (b_id,b) in grid["nw"]["$n"]["bus"]
                if haskey(result["solution"]["nw"]["$n"]["bus"],b_id)
                    if abs(result["solution"]["nw"]["$n"]["bus"]["$b_id"]["va"]) < 10^(-4)
                        b["va_starting_value"] = 0.0
                    else
                        b["va_starting_value"] = result["solution"]["nw"]["$n"]["bus"]["$b_id"]["va"]
                    end
                    if abs(result["solution"]["nw"]["$n"]["bus"]["$b_id"]["phi"]) < 10^(-4)
                        b["phi_starting_value"] = 0.0
                    else
                        b["phi_starting_value"] = result["solution"]["nw"]["$n"]["bus"]["$b_id"]["phi"]
                    end
                else
                    b["va_starting_value"] = 0.0
                    b["phi_starting_value"] = 0.0
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
            =#
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

function run_stochastic_acdcsw_AC_ZIL_per_hour(grid, model, optimizer, n_hours, n_scenarios; setting = s)
    result = Dict{String,Any}()
    for hour in 1:n_hours
        result["$hour"] = Dict{String,Any}()
        scenarios_hour = collect(((hour-1)*n_scenarios + 1):(hour*n_scenarios))
        grid_hour = deepcopy(grid)
        grid_hour["hours"] = 1
        grid_hour["nw"]= Dict{String,Any}()
        for i in scenarios_hour
            grid_hour["nw"]["$i"] = deepcopy(grid["nw"]["$i"])
        end    
        result["$hour"] = _SPMTA.run_stochastic_acdcsw_AC_ZIL_sp(grid_hour,model,optimizer; setting = setting)
    end
    return result
end

function run_hourly_opf(grid, model, optimizer,n_hours; settings = s)
    result = Dict{String,Any}()
    for nw in 1:n_hours
        result["$nw"] = _PM.solve_opf(grid["nw"]["$nw"],model,optimizer; setting = settings)
    end
    return result
end

test_case_bs_mn_sp = deepcopy(test_case_bs_mn)
prepare_starting_value_dict_lpac_nw(test_case_bs_mn_sp,start_hour_simulation,end_hour_simulation,n_scenarios)

result_bs_hourly_stochastic = run_stochastic_acdcsw_AC_ZIL_per_hour(test_case_bs_mn_sp,LPACCPowerModel,gurobi_opf,n_hours,n_scenarios)

result_bs_hourly_measured = run_stochastic_acdcsw_AC_ZIL_h(test_case_bs_mn_sp_measured,LPACCPowerModel,gurobi,n_hours,n_scenarios)
result_bs_hourly_forecasted = run_stochastic_acdcsw_AC_ZIL_h(test_case_bs_mn_sp_forecasted,LPACCPowerModel,gurobi,n_hours,n_scenarios)

obj_measured = 0.0
obj_forecasted = 0.0
for i in 1:n_hours
    obj_measured += result_bs_hourly_measured["$i"]["objective"]
    obj_forecasted += result_bs_hourly_forecasted["$i"]["objective"]

end
obj_measured
obj_forecasted
obj_opf = result_opf["objective"]

result_opf_hourly = run_hourly_opf(test_case_opf_mn_measured,LPACCPowerModel,gurobi,n_hours)
sum(result_opf_hourly["$i"]["objective"] for i in 1:n_hours)

test_case_bs_mn_la_23 = deepcopy(test_case_bs_mn)
test_case_bs_mn_la_23["limit_actions"] = 23
result_bs_mn_la_23 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limited_actions(test_case_bs_mn_la_23,LPACCPowerModel,gurobi; setting = s)


sw_1 = [result_bs_mn_la["solution"]["nw"]["$i"]["switch"]["1"]["status"] for i in 1:24]
sw_1_la_23 = [result_bs_mn_la_23["solution"]["nw"]["$i"]["switch"]["1"]["status"] for i in 1:24]


function prepare_AC_feasibility_check_stochastic_multistep(result_dict, input_dict, input_ac_check, switch_couples, extremes_dict, input_base, n_hours, n_scenarios)
    orig_buses = maximum(parse.(Int, keys(input_base["bus"])))
    println("Number of original buses is $orig_buses")
    for t in 1:(n_hours*n_scenarios)
        println("t is $(t)")
        for (sw_id,sw) in input_dict["nw"]["$t"]["switch"]
            if !haskey(sw,"auxiliary")
                println("SWITCH $sw_id, BUS from $(sw["f_bus"]), BUS to $(sw["t_bus"])")
                if result_dict["solution"]["nw"]["$t"]["switch"][sw_id]["status"] >= 0.9
                    println("Switch $sw_id is closed, Connecting everything back, no busbar splitting on bus $(sw["bus_split"])")
                    #delete!(input_ac_check["bus"],"$(input_ac_check["switch"][sw_id]["t_bus"])")
                    for l in keys(switch_couples)
                        if switch_couples[l]["bus_split"] == sw["bus_split"]
                            println("SWITCH COUPLE IS $l")

                            switch_t = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"])
                            switch_f = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"])
                   
                            if switch_t["t_bus"] == switch_couples[l]["bus_split"]
                                aux_t = switch_t["auxiliary"]
                                orig_t = switch_t["original"]
                                println("Element $aux_t $orig_t")
                                if aux_t == "gen"
                                    input_ac_check["nw"]["$t"]["gen"]["$(orig_t)"]["gen_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["gen"]["$(orig_t)"]["gen_bus"])
                                    println("Element $aux_t $orig_t connected to $(input_ac_check["nw"]["$t"]["gen"]["$(orig_t)"]["gen_bus"])")
                                elseif aux_t == "load"
                                    input_ac_check["nw"]["$t"]["load"]["$(orig_t)"]["load_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["load"]["$(orig_t)"]["load_bus"])
                                    println("Element $aux_t $orig_t connected to $(input_ac_check["nw"]["$t"]["load"]["$(orig_t)"]["load_bus"])")
                                elseif aux_t == "convdc"
                                    input_ac_check["nw"]["$t"]["convdc"]["$(orig_t)"]["busac_i"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["convdc"]["$(orig_t)"]["busac_i"])
                                    println("Element $aux_t $orig_t connected to $(input_ac_check["nw"]["$t"]["convdc"]["$(orig_t)"]["busac_i"])")
                                elseif aux_t == "branch" 
                                    if input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"] # useful if both ends of a branch are busbars being split
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"])
                                        println("Element $aux_t $orig_t connected to $(input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"])")
                                    elseif input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"])
                                        println("Element $aux_t $orig_t connected to $(input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"])")
                                    end
                                end
                            elseif switch_f["t_bus"] == switch_couples[l]["bus_split"]
                                aux_f = switch_f["auxiliary"]
                                orig_f = switch_f["original"]
                                println("Element $aux_f $orig_f")
                                if aux_f == "gen"
                                    input_ac_check["nw"]["$t"]["gen"]["$(orig_f)"]["gen_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["gen"]["$(orig_f)"]["gen_bus"])
                                    println("Element $aux_f $orig_f connected to $(input_ac_check["nw"]["$t"]["gen"]["$(orig_f)"]["gen_bus"])")
                                elseif aux_f == "load"
                                    input_ac_check["nw"]["$t"]["load"]["$(orig_f)"]["load_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["load"]["$(orig_f)"]["load_bus"])
                                    println("Element $aux_f $orig_f connected to $(input_ac_check["nw"]["$t"]["load"]["$(orig_f)"]["load_bus"])")
                                elseif aux_f == "convdc"
                                    input_ac_check["nw"]["$t"]["convdc"]["$(orig_f)"]["busac_i"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["convdc"]["$(orig_f)"]["busac_i"])
                                    println("Element $aux_f $orig_f connected to $(input_ac_check["nw"]["$t"]["convdc"]["$(orig_f)"]["busac_i"])")
                                elseif aux_f == "branch" 
                                    if input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"] # useful if both ends of a branch are busbars being split
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["f_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["f_bus"])
                                        println("Element $aux_f $orig_f connected to $(input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["f_bus"])")
                                    elseif input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"])
                                        println("Element $aux_f $orig_f connected to $(input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"])")
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
                                println("Switch $sw_id is open, busbar splitting on bus $(sw["bus_split"])")
                                delete!(input_ac_check["nw"]["$t"]["switch"],sw_id)
                                for l in keys(switch_couples)
                                    #if haskey(switch_couples,sw_id) && switch_couples[l]["bus_split"] == sw["bus_split"] -> wrong, you are checking the ZIL sw here
                                    if switch_couples[l]["bus_split"] == sw["bus_split"] # coupling the switch couple to their split bus
                                        println("SWITCH COUPLE IS $l")
                                            switch_t = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]) 
                                            aux_t = switch_t["auxiliary"]
                                            orig_t = switch_t["original"]
                                            println("Element $aux_t $orig_t")
                                            if result_dict["solution"]["nw"]["$t"]["switch"]["$(switch_t["index"])"]["status"] <= 0.1
                                                println("Deleting switch $(switch_t["index"])")
                                                delete!(input_ac_check["nw"]["$t"]["switch"],"$(switch_t["index"])")
                                            elseif result_dict["solution"]["nw"]["$t"]["switch"]["$(switch_t["index"])"]["status"] >= 0.9
                                                if aux_t == "gen"
                                                    input_ac_check["nw"]["$t"]["gen"]["$(orig_t)"]["gen_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["gen"]["$(orig_t)"]["gen_bus"])
                                                    println("Element $aux_t $orig_t connected to $(input_ac_check["nw"]["$t"]["gen"]["$(orig_t)"]["gen_bus"])")
                                                elseif aux_t == "load"
                                                    input_ac_check["nw"]["$t"]["load"]["$(orig_t)"]["load_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["load"]["$(orig_t)"]["load_bus"])
                                                    println("Element $aux_t $orig_t connected to $(input_ac_check["nw"]["$t"]["load"]["$(orig_t)"]["load_bus"])")
                                                elseif aux_t == "convdc"
                                                    input_ac_check["nw"]["$t"]["convdc"]["$(orig_t)"]["busac_i"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["convdc"]["$(orig_t)"]["busac_i"])
                                                    println("Element $aux_t $orig_t connected to $(input_ac_check["nw"]["$t"]["convdc"]["$(orig_t)"]["busac_i"])")
                                                elseif aux_t == "branch" 
                                                    if input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"] # useful if both ends of a branch are busbars being split
                                                        input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"])
                                                        println("Element $aux_t $orig_t connected to $(input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"])")
                                                    elseif input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                                        input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"])
                                                        println("Element $aux_t $orig_t connected to $(input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"])")
                                                    end
                                                end
                                            end
                                        
                
                                            switch_f = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]) 
                                            aux_f = switch_f["auxiliary"]
                                            orig_f = switch_f["original"]
                                            println("Element $aux_f $orig_f")
                                            if result_dict["solution"]["nw"]["$t"]["switch"]["$(switch_f["index"])"]["status"] <= 0.1
                                                println("Deleting switch $(switch_f["index"])")
                                                delete!(input_ac_check["nw"]["$t"]["switch"],"$(switch_f["index"])")
                                            elseif result_dict["solution"]["nw"]["$t"]["switch"]["$(switch_f["index"])"]["status"] >= 0.9
                                                if aux_f == "gen"
                                                    input_ac_check["nw"]["$t"]["gen"]["$(orig_f)"]["gen_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["gen"]["$(orig_f)"]["gen_bus"])
                                                    println("Element $aux_f $orig_f connected to $(input_ac_check["nw"]["$t"]["gen"]["$(orig_f)"]["gen_bus"])")
                                                elseif aux_f == "load"
                                                    input_ac_check["nw"]["$t"]["load"]["$(orig_f)"]["load_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["load"]["$(orig_f)"]["load_bus"])
                                                    println("Element $aux_f $orig_f connected to $(input_ac_check["nw"]["$t"]["load"]["$(orig_f)"]["load_bus"])")
                                                elseif aux_f == "convdc"
                                                    input_ac_check["nw"]["$t"]["convdc"]["$(orig_f)"]["busac_i"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["convdc"]["$(orig_f)"]["busac_i"])
                                                    println("Element $aux_f $orig_f connected to $(input_ac_check["nw"]["$t"]["convdc"]["$(orig_f)"]["busac_i"])")
                                                elseif aux_f == "branch" 
                                                    if input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"] # useful if both ends of a branch are busbars being split
                                                        input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["f_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["f_bus"])
                                                        println("Element $aux_f $orig_f connected to $(input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["f_bus"])")
                                                    elseif input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                                        input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"])
                                                        println("Element $aux_f $orig_f connected to $(input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"])")
                                                    end
                                                end
                                            end
                                        #end
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

function prepare_AC_feasibility_check_stochastic_multistep_hourly(result_dict, input_dict, input_ac_check, switch_couples, extremes_dict, input_base, n_hours, n_scenarios)
    orig_buses = maximum(parse.(Int, keys(input_base["bus"])))
    println("Number of original buses is $orig_buses")
    for t in 1:(n_hours*n_scenarios)
        println("t is $(t)")
        for (sw_id,sw) in input_dict["nw"]["$t"]["switch"]
            if !haskey(sw,"auxiliary")
                println("SWITCH $sw_id, BUS from $(sw["f_bus"]), BUS to $(sw["t_bus"])")
                if result_dict["$t"]["solution"]["nw"]["$t"]["switch"][sw_id]["status"] >= 0.9
                    println("Switch $sw_id is closed, Connecting everything back, no busbar splitting on bus $(sw["bus_split"])")
                    #delete!(input_ac_check["bus"],"$(input_ac_check["switch"][sw_id]["t_bus"])")
                    for l in keys(switch_couples)
                        if switch_couples[l]["bus_split"] == sw["bus_split"]
                            println("SWITCH COUPLE IS $l")

                            switch_t = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"])
                            switch_f = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"])
                   
                            if switch_t["t_bus"] == switch_couples[l]["bus_split"]
                                aux_t = switch_t["auxiliary"]
                                orig_t = switch_t["original"]
                                println("Element $aux_t $orig_t")
                                if aux_t == "gen"
                                    input_ac_check["nw"]["$t"]["gen"]["$(orig_t)"]["gen_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["gen"]["$(orig_t)"]["gen_bus"])
                                    println("Element $aux_t $orig_t connected to $(input_ac_check["nw"]["$t"]["gen"]["$(orig_t)"]["gen_bus"])")
                                elseif aux_t == "load"
                                    input_ac_check["nw"]["$t"]["load"]["$(orig_t)"]["load_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["load"]["$(orig_t)"]["load_bus"])
                                    println("Element $aux_t $orig_t connected to $(input_ac_check["nw"]["$t"]["load"]["$(orig_t)"]["load_bus"])")
                                elseif aux_t == "convdc"
                                    input_ac_check["nw"]["$t"]["convdc"]["$(orig_t)"]["busac_i"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["convdc"]["$(orig_t)"]["busac_i"])
                                    println("Element $aux_t $orig_t connected to $(input_ac_check["nw"]["$t"]["convdc"]["$(orig_t)"]["busac_i"])")
                                elseif aux_t == "branch" 
                                    if input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"] # useful if both ends of a branch are busbars being split
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"])
                                        println("Element $aux_t $orig_t connected to $(input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"])")
                                    elseif input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"])
                                        println("Element $aux_t $orig_t connected to $(input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"])")
                                    end
                                end
                            elseif switch_f["t_bus"] == switch_couples[l]["bus_split"]
                                aux_f = switch_f["auxiliary"]
                                orig_f = switch_f["original"]
                                println("Element $aux_f $orig_f")
                                if aux_f == "gen"
                                    input_ac_check["nw"]["$t"]["gen"]["$(orig_f)"]["gen_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["gen"]["$(orig_f)"]["gen_bus"])
                                    println("Element $aux_f $orig_f connected to $(input_ac_check["nw"]["$t"]["gen"]["$(orig_f)"]["gen_bus"])")
                                elseif aux_f == "load"
                                    input_ac_check["nw"]["$t"]["load"]["$(orig_f)"]["load_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["load"]["$(orig_f)"]["load_bus"])
                                    println("Element $aux_f $orig_f connected to $(input_ac_check["nw"]["$t"]["load"]["$(orig_f)"]["load_bus"])")
                                elseif aux_f == "convdc"
                                    input_ac_check["nw"]["$t"]["convdc"]["$(orig_f)"]["busac_i"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["convdc"]["$(orig_f)"]["busac_i"])
                                    println("Element $aux_f $orig_f connected to $(input_ac_check["nw"]["$t"]["convdc"]["$(orig_f)"]["busac_i"])")
                                elseif aux_f == "branch" 
                                    if input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"] # useful if both ends of a branch are busbars being split
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["f_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["f_bus"])
                                        println("Element $aux_f $orig_f connected to $(input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["f_bus"])")
                                    elseif input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"])
                                        println("Element $aux_f $orig_f connected to $(input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"])")
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
                                println("Switch $sw_id is open, busbar splitting on bus $(sw["bus_split"])")
                                delete!(input_ac_check["nw"]["$t"]["switch"],sw_id)
                                for l in keys(switch_couples)
                                    #if haskey(switch_couples,sw_id) && switch_couples[l]["bus_split"] == sw["bus_split"] -> wrong, you are checking the ZIL sw here
                                    if switch_couples[l]["bus_split"] == sw["bus_split"] # coupling the switch couple to their split bus
                                        println("SWITCH COUPLE IS $l")
                                            switch_t = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]) 
                                            aux_t = switch_t["auxiliary"]
                                            orig_t = switch_t["original"]
                                            println("Element $aux_t $orig_t")
                                            if result_dict["$t"]["solution"]["nw"]["$t"]["switch"]["$(switch_t["index"])"]["status"] <= 0.1
                                                println("Deleting switch $(switch_t["index"])")
                                                delete!(input_ac_check["nw"]["$t"]["switch"],"$(switch_t["index"])")
                                            elseif result_dict["$t"]["solution"]["nw"]["$t"]["switch"]["$(switch_t["index"])"]["status"] >= 0.9
                                                if aux_t == "gen"
                                                    input_ac_check["nw"]["$t"]["gen"]["$(orig_t)"]["gen_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["gen"]["$(orig_t)"]["gen_bus"])
                                                    println("Element $aux_t $orig_t connected to $(input_ac_check["nw"]["$t"]["gen"]["$(orig_t)"]["gen_bus"])")
                                                elseif aux_t == "load"
                                                    input_ac_check["nw"]["$t"]["load"]["$(orig_t)"]["load_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["load"]["$(orig_t)"]["load_bus"])
                                                    println("Element $aux_t $orig_t connected to $(input_ac_check["nw"]["$t"]["load"]["$(orig_t)"]["load_bus"])")
                                                elseif aux_t == "convdc"
                                                    input_ac_check["nw"]["$t"]["convdc"]["$(orig_t)"]["busac_i"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["convdc"]["$(orig_t)"]["busac_i"])
                                                    println("Element $aux_t $orig_t connected to $(input_ac_check["nw"]["$t"]["convdc"]["$(orig_t)"]["busac_i"])")
                                                elseif aux_t == "branch" 
                                                    if input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"] # useful if both ends of a branch are busbars being split
                                                        input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"])
                                                        println("Element $aux_t $orig_t connected to $(input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"])")
                                                    elseif input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                                        input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"])
                                                        println("Element $aux_t $orig_t connected to $(input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"])")
                                                    end
                                                end
                                            end
                                        
                
                                            switch_f = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]) 
                                            aux_f = switch_f["auxiliary"]
                                            orig_f = switch_f["original"]
                                            println("Element $aux_f $orig_f")
                                            if result_dict["$t"]["solution"]["nw"]["$t"]["switch"]["$(switch_f["index"])"]["status"] <= 0.1
                                                println("Deleting switch $(switch_f["index"])")
                                                delete!(input_ac_check["nw"]["$t"]["switch"],"$(switch_f["index"])")
                                            elseif result_dict["$t"]["solution"]["nw"]["$t"]["switch"]["$(switch_f["index"])"]["status"] >= 0.9
                                                if aux_f == "gen"
                                                    input_ac_check["nw"]["$t"]["gen"]["$(orig_f)"]["gen_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["gen"]["$(orig_f)"]["gen_bus"])
                                                    println("Element $aux_f $orig_f connected to $(input_ac_check["nw"]["$t"]["gen"]["$(orig_f)"]["gen_bus"])")
                                                elseif aux_f == "load"
                                                    input_ac_check["nw"]["$t"]["load"]["$(orig_f)"]["load_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["load"]["$(orig_f)"]["load_bus"])
                                                    println("Element $aux_f $orig_f connected to $(input_ac_check["nw"]["$t"]["load"]["$(orig_f)"]["load_bus"])")
                                                elseif aux_f == "convdc"
                                                    input_ac_check["nw"]["$t"]["convdc"]["$(orig_f)"]["busac_i"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                                    delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["convdc"]["$(orig_f)"]["busac_i"])
                                                    println("Element $aux_f $orig_f connected to $(input_ac_check["nw"]["$t"]["convdc"]["$(orig_f)"]["busac_i"])")
                                                elseif aux_f == "branch" 
                                                    if input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"] # useful if both ends of a branch are busbars being split
                                                        input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["f_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["f_bus"])
                                                        println("Element $aux_f $orig_f connected to $(input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["f_bus"])")
                                                    elseif input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                                        input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"])
                                                        println("Element $aux_f $orig_f connected to $(input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"])")
                                                    end
                                                end
                                            end
                                        #end
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

AC_feas_check_auxiliary_measured = deepcopy(test_case_bs_mn)
AC_feas_check_measured = deepcopy(test_case_bs_mn)
AC_feas_check_auxiliary_forecasted = deepcopy(test_case_bs_mn)
AC_feas_check_forecasted = deepcopy(test_case_bs_mn)

prepare_AC_feasibility_check_stochastic_multistep_hourly(result_bs_hourly_measured, AC_feas_check_auxiliary_measured, AC_feas_check_measured, switches_couples_ac, extremes_ZILs_ac, test_case, n_hours, n_scenarios)    
prepare_AC_feasibility_check_stochastic_multistep_hourly(result_bs_hourly_forecasted, AC_feas_check_auxiliary_forecasted, AC_feas_check_forecasted, switches_couples_ac, extremes_ZILs_ac, test_case, n_hours, n_scenarios)    

result_opf_check_measured = _SPMTA.run_stochastic_acdc_opf(AC_feas_check,LPACCPowerModel,gurobi_opf; setting = s)
result_opf_check_forecasted = _SPMTA.run_stochastic_acdc_opf(AC_feas_check,LPACCPowerModel,gurobi_opf; setting = s)
