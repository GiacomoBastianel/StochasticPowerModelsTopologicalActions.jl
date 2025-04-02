using PowerModels; const _PM = PowerModels
using PowerModelsACDC; const _PMACDC = PowerModelsACDC
import PowerModelsTopologicalActionsII; const _PMTP = PowerModelsTopologicalActionsII
using FlexPlan; const _FP = FlexPlan
using Gurobi, Ipopt, JSON, Plots
import StochasticPowerModelsTopologicalActions; const _SPMTA = StochasticPowerModelsTopologicalActions
using JuMP, Juniper, HSL_jll, MathOptInterface, HiGHS

mip_gap = 1e-4
gurobi = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 10800,"MIPGap" => mip_gap,"BarHomogeneous" => 1,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "ScaleFlag"=>2, "NumericFocus"=>2) 
gurobi_opf = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 1200,"MIPGap" => mip_gap)#,"BarHomogeneous" => 1,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "ScaleFlag"=>2, "NumericFocus"=>2) 
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

test_case_opf["gen"]["1"]
#########################################################################################
# Busbar splitting

test_case_bs = deepcopy(test_case_opf)
splitted_bus_ac = 6
test_case_bs,  switches_couples_ac,  extremes_ZILs_ac  = _PMTP.AC_busbar_split_AC_grid(test_case,splitted_bus_ac)
# Adding costs to the busbar couplers
for sw_id in 1:length(extremes_ZILs_ac)
    test_case_bs["switch"]["$sw_id"]["cost"] = 10.0
end
test_case_bs["switch"]["1"]

result_bs_6 = _PMTP.run_acdcsw_AC_big_M_hour(test_case_bs, LPACCPowerModel, gurobi)
result_bs_6_no_cost = _PMTP.run_acdcsw_AC_big_M(test_case_bs, LPACCPowerModel, gurobi)

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
print_switch_results(test_case_bs,test_case_opf,result_bs_6)

function prepare_AC_feasibility_check(result_dict, input_dict, input_ac_check, switch_couples, extremes_dict,input_base)
    orig_buses = maximum(parse.(Int, keys(input_base["bus"]))) # maximum value before splitting (in case the buses are not in numerical order)
    for (sw_id,sw) in input_dict["switch"]
        if !haskey(sw,"auxiliary")
            println("SWITCH $sw_id, BUS from $(sw["f_bus"]), BUS to $(sw["t_bus"])")
            if result_dict["solution"]["switch"][sw_id]["status"] >= 0.9 # Just reconnecting stuff
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
            elseif result_dict["solution"]["switch"][sw_id]["status"] <= 0.1 # Connect elements to the right bus
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
                            if result_dict["solution"]["switch"]["$(switch_t["index"])"]["status"] <= 0.1
                                println("Deleting switch $(switch_t["index"])")
                                delete!(input_ac_check["switch"],"$(switch_t["index"])")
                            elseif result_dict["solution"]["switch"]["$(switch_t["index"])"]["status"] >= 0.9
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
                            if result_dict["solution"]["switch"]["$(switch_f["index"])"]["status"] <= 0.1
                                println("Deleting switch $(switch_f["index"])")
                                delete!(input_ac_check["switch"],"$(switch_f["index"])")
                            elseif result_dict["solution"]["switch"]["$(switch_f["index"])"]["status"] >= 0.9
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

feasibility_check = deepcopy(test_case_bs)
feasibility_check_input = deepcopy(test_case_bs)
prepare_AC_feasibility_check(result_bs_6,feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
result_feasibility_check = _PMACDC.run_acdcopf(feasibility_check,LPACCPowerModel,gurobi_opf; setting = s)


#########################################################################################
# Hours
n_hours = 12
start_hour_simulation = 1
end_hour_simulation = 12
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

#measured_wind[4] = 0.4
#measured_wind[8] = 0.5
forecasted_wind[4] = 0.4
#forecasted_wind[6] = measured_wind[6]
forecasted_wind[8] = 0.6
#measured_wind[8] = 0.6
#forecasted_wind[9] = measured_wind[9]

forecasted_wind[3] = 0.4

forecasted_wind[10] = 0.4
forecasted_wind[11] = 0.4

#forecasted_wind[5] = measured_wind[5]
#forecasted_wind[7] = measured_wind[4]

plot(forecasted_wind,label = :none,ylims = (0,1.0),xlabel = "Hours", ylabel = "Capacity factor [-]",grid = :none,xticks = (1:1:12))
#########################################################################################
## Running simulations
# Busbar splitting
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
test_case_bs_replicate = _PM.replicate(test_case_bs, n_hours)
for (nw_id,nw) in test_case_bs_replicate["nw"]
    nw["probability"] = 1.0
    nw["per_unit"] = true
end
test_case_bs_replicate_mn_measured = deepcopy(test_case_bs_replicate)
test_case_bs_replicate_mn_forecasted = deepcopy(test_case_bs_replicate)
for i in 1:(n_hours*one_scenario)
    test_case_bs_replicate_mn_measured["nw"]["$i"]["gen"]["1"]["pmax"]   = deepcopy(test_case_bs_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*measured_wind[i])
    test_case_bs_replicate_mn_forecasted["nw"]["$i"]["gen"]["1"]["pmax"] = deepcopy(test_case_bs_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*forecasted_wind[i])
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

adding_multinetwork_scenarios(test_case_bs_replicate,n_hours,one_scenario)
adding_multinetwork_scenarios(test_case_bs_replicate_mn_measured,n_hours,one_scenario)
adding_multinetwork_scenarios(test_case_bs_replicate_mn_forecasted,n_hours,one_scenario)

##############################################################
## Running simulations
# Busbar splitting for 12 hours, simulating one hour per time
#result_bs = _SPMTA.run_stochastic_acdcsw_AC_ZIL(test_case_bs_replicate,LPACCPowerModel,gurobi; setting = s)
#result_bs_measured   = _SPMTA.run_stochastic_acdcsw_AC_ZIL(test_case_bs_replicate_mn_measured  ,LPACCPowerModel,gurobi_opf; setting = s)
#result_bs_forecasted = _SPMTA.run_stochastic_acdcsw_AC_ZIL(test_case_bs_replicate_mn_forecasted,LPACCPowerModel,gurobi_opf; setting = s)

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

function run_feasibility_checks_per_hour(grid, result_bs, model, optimizer,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
    result_feasibility_checks = Dict{String,Any}()
    for hour in 1:length(grid["nw"])
        result_feasibility_checks["$hour"] = Dict{String,Any}()
        feasibility_check = deepcopy(grid["nw"]["$hour"])
        feasibility_check_input = deepcopy(grid["nw"]["$hour"])
        prepare_AC_feasibility_check(result_bs["$hour"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
        result_feasibility_checks["$hour"] = _PM.solve_opf(feasibility_check,model,optimizer; setting = s)
        #if isnan(result_feasibility_checks["$hour"]["objective"])
        #    result_feasibility_checks["$hour"] = deepcopy(result_opf["$hour"])
        #end
    end
    return result_feasibility_checks
end

#result_24 = Dict{String,Any}()
#for hour in 1:(n_hours*one_scenario)
#    result_24["$hour"] = _PM.solve_opf(test_case_opf_replicate["nw"]["$hour"],ACPPowerModel,ipopt; setting = s)
#end
#obj = [result_24["$i"]["objective"] for i in 1:n_hours]
#sum(obj)
#
#result_measured_24 = Dict{String,Any}()
#for hour in 1:(n_hours*one_scenario)
#    result_measured_24["$hour"] = _PM.solve_opf(test_case_opf_mn_measured["nw"]["$hour"],ACPPowerModel,ipopt; setting = s)
#end
#obj_measured_24 = [result_measured_24["$i"]["objective"] for i in 1:n_hours]
#sum(obj_measured_24)

result_forecasted_24 = Dict{String,Any}()
for hour in 1:(n_hours*one_scenario)
    result_forecasted_24["$hour"] = _PM.solve_opf(test_case_opf_mn_forecasted["nw"]["$hour"],ACPPowerModel,ipopt; setting = s)
end
obj_forecasted_24 = [result_forecasted_24["$i"]["objective"] for i in 1:n_hours]
sum(obj_forecasted_24)
sum(result_forecasted_24["$i"]["solve_time"] for i in 1:n_hours)

plot(obj_forecasted_24,ylims = (0,2.0e4),label="Forecasted",grid = :none)
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
result_forecasted_feasibility_checks_24 = run_feasibility_checks_per_hour(test_case_bs_replicate_mn_forecasted,result_bs_hourly_forecasted_24,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf)

obj_bs_forecasted = [result_bs_hourly_forecasted_24["$i"]["objective"] for i in 1:n_hours]
sum(obj_bs_forecasted)

obj_fc_forecasted = [result_forecasted_feasibility_checks_24["$i"]["objective"] for i in 1:n_hours]

sum(obj_forecasted_24) - sum(obj_fc_forecasted)
(sum(obj_forecasted_24) - sum(obj_fc_forecasted))/sum(obj_forecasted_24)*100

sum(result_bs_hourly_forecasted_24["$i"]["solve_time"] for i in 1:n_hours)


# Reduction in costs
(sum(obj_forecasted_24) - sum(obj_fc_forecasted))/sum(obj_forecasted_24)*100

sw_1_hourly_bs = [result_bs_hourly_forecasted_24["$i"]["solution"]["switch"]["1"]["status"] for i in 1:n_hours]

function print_switch_results_hourly(test_case,original_test_case,results,hour)
    for sw_id in 1:length(test_case["nw"]["$hour"]["switch"])
        if haskey(test_case["nw"]["$hour"]["switch"]["$(sw_id)"],"auxiliary")
            println("Switch $sw_id, aux is $(test_case["nw"]["$hour"]["switch"]["$(sw_id)"]["auxiliary"]), orig is $(test_case["nw"]["$hour"]["switch"]["$(sw_id)"]["original"]), t_bus is $(test_case["nw"]["$hour"]["switch"]["$(sw_id)"]["t_bus"]), $(results["$hour"]["solution"]["switch"]["$sw_id"]["status"]), bus_split is $(test_case["nw"]["$hour"]["switch"]["$(sw_id)"]["bus_split"])")    
            if test_case["nw"]["$hour"]["switch"]["$(sw_id)"]["auxiliary"] == "branch"
                println("      Branch $(test_case["nw"]["$hour"]["switch"]["$(sw_id)"]["original"]), f_bus $(original_test_case["branch"]["$(test_case["nw"]["$hour"]["switch"]["$(sw_id)"]["original"])"]["f_bus"]), t_bus $(original_test_case["branch"]["$(test_case["nw"]["$hour"]["switch"]["$(sw_id)"]["original"])"]["t_bus"])")
            end
        else
            println("Switch $sw_id,  is $(results["$hour"]["solution"]["switch"]["$sw_id"]["status"]), bus_split is $(test_case["nw"]["$hour"]["switch"]["$(sw_id)"]["bus_split"])")
        end
    end
end
print_switch_results_hourly(test_case_bs_replicate_mn_forecasted,test_case_opf,result_bs_hourly_forecasted_24,4)

##############################################################

##############################################################
#=
# Busbar splitting for 12 hours, one topology
result_bs_hourly_one_topology_24            = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology(test_case_bs_replicate              ,LPACCPowerModel,gurobi; setting = s)
#result_bs_hourly_measured_one_topology   = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology(test_case_bs_replicate_mn_measured  ,LPACCPowerModel,gurobi_opf; setting = s)
result_bs_hourly_forecasted_one_topology_24 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology(test_case_bs_replicate_mn_forecasted,LPACCPowerModel,gurobi_opf; setting = s)

[result_bs_hourly["1"]["solution"]["switch"]["$sw_id"]["status"] for sw_id in 1:length(test_case_bs["switch"])]
[result_bs_hourly_one_topology["solution"]["nw"]["1"]["switch"]["$sw_id"]["status"] for sw_id in 1:length(test_case_bs["switch"])]
[result_bs_hourly_measured_one_topology["solution"]["nw"]["1"]["switch"]["$sw_id"]["status"] for sw_id in 1:length(test_case_bs["switch"])]
[result_bs_hourly_forecasted_one_topology["solution"]["nw"]["1"]["switch"]["$sw_id"]["status"] for sw_id in 1:length(test_case_bs["switch"])]

[result_bs_hourly_forecasted_one_topology["solution"]["nw"]["$i"]["switch"]["1"]["status"] for i in 1:n_hours]


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
                        end
                    end
                end
            end
        end
        input_ac_check["nw"]["$t"]["switch"] = Dict{String,Any}()
        input_ac_check["nw"]["$t"]["switch_couples"] = Dict{String,Any}()
    end
end
fc_test_case_bs_replicate = deepcopy(test_case_bs_replicate)
fc_test_case_bs_replicate_auxiliary = deepcopy(test_case_bs_replicate)
prepare_AC_feasibility_check_stochastic_multistep(result_bs_hourly_one_topology,fc_test_case_bs_replicate,fc_test_case_bs_replicate_auxiliary,switches_couples_ac,extremes_ZILs_ac,test_case_opf,n_hours,one_scenario)
fc_one_topology = _PM.solve_mn_opf(fc_test_case_bs_replicate_auxiliary,ACPPowerModel,ipopt)

fc_test_case_bs_replicate_mn_measured = deepcopy(test_case_bs_replicate_mn_measured)
fc_test_case_bs_replicate_mn_measured_auxiliary = deepcopy(test_case_bs_replicate_mn_measured)
prepare_AC_feasibility_check_stochastic_multistep(result_bs_hourly_measured_one_topology,fc_test_case_bs_replicate_mn_measured,fc_test_case_bs_replicate_mn_measured_auxiliary,switches_couples_ac,extremes_ZILs_ac,test_case_opf,n_hours,one_scenario)
fc_one_topology_measured = _PM.solve_mn_opf(fc_test_case_bs_replicate_mn_measured_auxiliary,ACPPowerModel,ipopt)

fc_test_case_bs_replicate_forecasted = deepcopy(test_case_bs_replicate_mn_forecasted)
fc_test_case_bs_replicate_forecasted_auxiliary = deepcopy(test_case_bs_replicate_mn_forecasted)
prepare_AC_feasibility_check_stochastic_multistep(result_bs_hourly_forecasted_one_topology,fc_test_case_bs_replicate_forecasted,fc_test_case_bs_replicate_forecasted_auxiliary,switches_couples_ac,extremes_ZILs_ac,test_case_opf,n_hours,one_scenario)
fc_one_topology_forecasted = _PM.solve_mn_opf(fc_test_case_bs_replicate_forecasted_auxiliary,ACPPowerModel,ipopt)
=#



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

#test_case_bs_replicate_sp_24               = deepcopy(test_case_bs_replicate              )
#test_case_bs_replicate_mn_measured_sp_24   = deepcopy(test_case_bs_replicate_mn_measured  )
test_case_bs_replicate_mn_forecasted_sp_24 = deepcopy(test_case_bs_replicate_mn_forecasted)
#prepare_starting_value_dict_lpac_nw_sp(test_case_bs_replicate_sp_24           ,start_hour_simulation,end_hour_simulation,one_scenario)
#prepare_starting_value_dict_lpac_nw_sp(test_case_bs_replicate_mn_measured_sp_24  ,start_hour_simulation,end_hour_simulation,one_scenario)
prepare_starting_value_dict_lpac_nw_sp(test_case_bs_replicate_mn_forecasted_sp_24,start_hour_simulation,end_hour_simulation,one_scenario)

#result_bs_hourly_one_topology_24            = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology_sp(test_case_bs_replicate_sp              ,LPACCPowerModel,gurobi; setting = s)
#result_bs_hourly_measured_one_topology   = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology_sp(test_case_bs_replicate_mn_measured_sp  ,LPACCPowerModel,gurobi_opf; setting = s)
result_bs_hourly_forecasted_one_topology_24 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology_sp(test_case_bs_replicate_mn_forecasted_sp_24,LPACCPowerModel,gurobi; setting = s)
result_bs_hourly_forecasted_one_topology_24_no_sp = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology(test_case_bs_replicate_mn_forecasted_sp_24,LPACCPowerModel,gurobi; setting = s)

[result_bs_hourly_forecasted_one_topology_24["solution"]["nw"]["1"]["switch"]["$sw_id"]["status"] for (sw_id,sw) in test_case_bs["switch"]]
[result_bs_hourly_forecasted_one_topology_24["solution"]["nw"]["$i"]["switch"]["$sw_id"]["status"] for i in 1:n_hours]
#[result_bs_hourly_forecasted["4"]["solution"]["switch"]["$sw_id"]["status"] for (sw_id,sw) in test_case_bs["switch"]]

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


sum(obj_forecasted_24) - sum(result_fc_hourly_forecasted_one_topology_24["$i"]["objective"] for i in 1:n_hours)
(sum(obj_forecasted_24) - sum(result_fc_hourly_forecasted_one_topology_24["$i"]["objective"] for i in 1:n_hours))/sum(obj_forecasted_24)*100

sw_1_one_topology = [result_bs_hourly_forecasted_one_topology_24["solution"]["nw"]["$i"]["switch"]["1"]["status"] for i in 1:n_hours]



#=
print_switch_results_hourly(test_case_bs_replicate_mn_forecasted_sp_24,test_case_opf,result_bs_hourly_forecasted,4)
print_switch_results_one_topology(test_case_bs_replicate_mn_forecasted,test_case_opf,result_bs_hourly_forecasted_one_topology_24,4)

result_bs_hourly_forecasted_one_topology_24["objective"]
sum(result_bs_hourly_forecasted_24["$i"]["objective"] for i in 1:n_hours)
test_case_bs_1_result_24["objective"]

result_bs_hourly_forecasted_one_topology_24["objective"]/result_bs_hourly_forecasted_one_topology_24["objective"]
(1-sum(result_bs_hourly_forecasted_24["$i"]["objective"] for i in 1:n_hours)/result_bs_hourly_forecasted_one_topology_24["objective"])*100
(1-test_case_bs_1_result_24["objective"]/result_bs_hourly_forecasted_one_topology_24["objective"])*100
(1-test_case_bs_3_result_24["objective"]/result_bs_hourly_forecasted_one_topology_24["objective"])*100
=#

##############################################################

#test_case_bs_replicate_sp_opf               = deepcopy(test_case_bs_replicate              )
#test_case_bs_replicate_mn_measured_sp_opf   = deepcopy(test_case_bs_replicate_mn_measured  )
#test_case_bs_replicate_mn_forecasted_sp_opf = deepcopy(test_case_bs_replicate_mn_forecasted)
#prepare_starting_value_dict_lpac_nw_opf(test_case_bs_replicate_sp_opf              ,result,start_hour_simulation,end_hour_simulation,one_scenario)
#prepare_starting_value_dict_lpac_nw_opf(test_case_bs_replicate_mn_measured_sp_opf  ,result_measured,start_hour_simulation,end_hour_simulation,one_scenario)
#prepare_starting_value_dict_lpac_nw_opf(test_case_bs_replicate_mn_forecasted_sp_opf,result_forecasted,start_hour_simulation,end_hour_simulation,one_scenario)
#
#result_bs_hourly_one_topology_sp_opf            = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology_sp(test_case_bs_replicate_sp_opf              ,LPACCPowerModel,gurobi_opf; setting = s)
#result_bs_hourly_measured_one_topology_sp_opf   = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology_sp(test_case_bs_replicate_mn_measured_sp_opf  ,LPACCPowerModel,gurobi_opf; setting = s)
#result_bs_hourly_forecasted_one_topology_sp_opf = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology_sp(test_case_bs_replicate_mn_forecasted_sp_opf,LPACCPowerModel,gurobi_opf; setting = s)
#
#fc_test_case_bs_replicate = deepcopy(test_case_bs_replicate_sp_opf)
#fc_test_case_bs_replicate_auxiliary = deepcopy(test_case_bs_replicate_sp_opf)
#prepare_AC_feasibility_check_stochastic_multistep(result_bs_hourly_one_topology_sp_opf,fc_test_case_bs_replicate,fc_test_case_bs_replicate_auxiliary,switches_couples_ac,extremes_ZILs_ac,test_case_opf,n_hours,one_scenario)
#fc_one_topology_sp = _PM.solve_mn_opf(fc_test_case_bs_replicate_auxiliary,LPACCPowerModel,gurobi_opf)
#
#fc_test_case_bs_replicate_mn_measured = deepcopy(test_case_bs_replicate_mn_measured_sp_opf)
#fc_test_case_bs_replicate_mn_measured_auxiliary = deepcopy(test_case_bs_replicate_mn_measured_sp_opf)
#prepare_AC_feasibility_check_stochastic_multistep(result_bs_hourly_measured_one_topology_sp_opf,fc_test_case_bs_replicate_mn_measured,fc_test_case_bs_replicate_mn_measured_auxiliary,switches_couples_ac,extremes_ZILs_ac,test_case_opf,n_hours,one_scenario)
#fc_one_topology_measured_sp = _PM.solve_mn_opf(fc_test_case_bs_replicate_mn_measured_auxiliary,LPACCPowerModel,gurobi_opf)
#
#fc_test_case_bs_replicate_forecasted = deepcopy(test_case_bs_replicate_mn_forecasted_sp_opf)
#fc_test_case_bs_replicate_forecasted_auxiliary = deepcopy(test_case_bs_replicate_mn_forecasted_sp_opf)
#prepare_AC_feasibility_check_stochastic_multistep(result_bs_hourly_forecasted_one_topology_sp_opf,fc_test_case_bs_replicate_forecasted,fc_test_case_bs_replicate_forecasted_auxiliary,switches_couples_ac,extremes_ZILs_ac,test_case_opf,n_hours,one_scenario)
#fc_one_topology_forecasted_sp = _PM.solve_mn_opf(fc_test_case_bs_replicate_forecasted_auxiliary,LPACCPowerModel,gurobi_opf)


#test_case_bs_replicate_mn_forecasted_sp["total_switching_actions"] = 0
#result_bs_hourly_forecasted_switching_actions = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp(test_case_bs_replicate_mn_forecasted_sp,LPACCPowerModel,gurobi_opf)
#
#
#[result_bs_hourly_forecasted_switching_actions["solution"]["nw"]["$i"]["switch"]["1"]["status"] for i in 1:n_hours]


test_case_bs_1_24 = deepcopy(test_case_bs_replicate_mn_forecasted_sp_24)
test_case_bs_1_24["total_switching_actions"] = 1
test_case_bs_1_result_24 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp(test_case_bs_1_24,LPACCPowerModel,gurobi)
result_fc_1_sw = run_feasibility_checks_hourly(test_case_bs_replicate_mn_forecasted_sp_24,test_case_bs_1_result_24,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
sum(result_fc_1_sw["$i"]["objective"] for i in 1:n_hours)

sum(obj_forecasted_24) - sum(result_fc_1_sw["$i"]["objective"] for i in 1:n_hours)
(sum(obj_forecasted_24) - sum(result_fc_1_sw["$i"]["objective"] for i in 1:n_hours))/sum(obj_forecasted_24)*100

sw_1_one_sw_actions = [test_case_bs_1_result_24["solution"]["nw"]["$i"]["switch"]["1"]["status"] for i in 1:n_hours]





test_case_bs_2_24 = deepcopy(test_case_bs_replicate_mn_forecasted_sp_24)
test_case_bs_2_24["total_switching_actions"] = 2
test_case_bs_2_result_24 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp(test_case_bs_2_24,LPACCPowerModel,gurobi)
result_fc_2_sw = run_feasibility_checks_hourly(test_case_bs_replicate_mn_forecasted_sp_24,test_case_bs_2_result_24,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
sum(result_fc_2_sw["$i"]["objective"] for i in 1:n_hours)

sw_1_two_sw_actions = [test_case_bs_2_result_24["solution"]["nw"]["$i"]["switch"]["1"]["status"] for i in 1:n_hours]


sum(obj_forecasted_24) - sum(result_fc_2_sw["$i"]["objective"] for i in 1:n_hours)
(sum(obj_forecasted_24) - sum(result_fc_2_sw["$i"]["objective"] for i in 1:n_hours))/sum(obj_forecasted_24)*100

sw_1_one_topology = [result_bs_hourly_forecasted_one_topology_24["solution"]["nw"]["$i"]["switch"]["1"]["status"] for i in 1:n_hours]


#=
test_case_bs_3_24 = deepcopy(test_case_bs_replicate_mn_forecasted_sp)
test_case_bs_3_24["total_switching_actions"] = 3
test_case_bs_3_result_24 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp(test_case_bs_3_24,LPACCPowerModel,gurobi_opf)
result_fc_3_sw = run_feasibility_checks_hourly(test_case_bs_replicate_mn_forecasted_sp,test_case_bs_3_result_24,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
sum(result_fc_3_sw["$i"]["objective"] for i in 1:n_hours)

[test_case_bs_3_result_24["solution"]["nw"]["$i"]["switch"]["1"]["status"] for i in 1:n_hours]

test_case_bs_4_24 = deepcopy(test_case_bs_replicate_mn_forecasted_sp)
test_case_bs_4_24["total_switching_actions"] = 4
test_case_bs_4_result_24 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp(test_case_bs_4_24,LPACCPowerModel,gurobi_opf)

[test_case_bs_4_result_24["solution"]["nw"]["$i"]["switch"]["1"]["status"] for i in 1:n_hours]

test_case_bs_5_24 = deepcopy(test_case_bs_replicate_mn_forecasted_sp)
test_case_bs_5_24["total_switching_actions"] = 5
test_case_bs_5_result_24 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp(test_case_bs_5_24,LPACCPowerModel,gurobi_opf)

[test_case_bs_5_result_24["solution"]["nw"]["$i"]["switch"]["1"]["status"] for i in 1:8]


test_case_bs_6_24 = deepcopy(test_case_bs_replicate_mn_forecasted_sp)
test_case_bs_6_24["total_switching_actions"] = 6
test_case_bs_6_result_24 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp(test_case_bs_6_24,LPACCPowerModel,gurobi_opf)

[test_case_bs_6_result_24["solution"]["nw"]["$i"]["switch"]["1"]["status"] for i in 1:n_hours]
=#


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

#=
function compute_hourly_objective(results,test_case,n_hours)
    obj = []
    for nw in 1:n_hours
        obj_i = 0
        for (g_id,g) in test_case["gen"]
            if g["pmax"] != 0.0
                obj_i += results["solution"]["nw"]["$nw"]["gen"]["$g_id"]["pg"]*g["cost"][1]
            end
        end
        push!(obj,obj_i)
    end
    return obj
end
=#
#obj_one_topology = compute_hourly_objective(result_bs_hourly_forecasted_one_topology_24,test_case_bs,n_hours)
#obj_max_switch_1 = compute_hourly_objective(test_case_bs_1_result,test_case_bs,n_hours)
#obj_max_switch_3 = compute_hourly_objective(test_case_bs_3_result,test_case_bs,n_hours)

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
