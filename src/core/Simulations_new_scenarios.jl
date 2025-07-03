using PowerModels; const _PM = PowerModels
using PowerModelsACDC; const _PMACDC = PowerModelsACDC
import PowerModelsTopologicalActionsII; const _PMTP = PowerModelsTopologicalActionsII
using FlexPlan; const _FP = FlexPlan
using Gurobi, Ipopt, JSON, Plots
import StochasticPowerModelsTopologicalActions; const _SPMTA = StochasticPowerModelsTopologicalActions
using JuMP, Juniper, HSL_jll, MathOptInterface, HiGHS
using Statistics

mip_gap = 5e-4
gurobi_bs = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 3600*7,"MIPGap" => mip_gap,"BarHomogeneous" => 1, "NumericFocus"=>2) 
gurobi = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 1200,"MIPGap" => mip_gap,"BarHomogeneous" => 1,"BarQCPConvTol"=>1e-6,"QCPDual" => 1, "ScaleFlag"=>2, "NumericFocus"=>2) 
gurobi_opf = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 600,"MIPGap" => mip_gap,"BarHomogeneous" => 1, "NumericFocus"=>2,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "ScaleFlag"=>2, "NumericFocus"=>3) 
gurobi_lpac = JuMP.optimizer_with_attributes(Gurobi.Optimizer)#,"time_limit" => 1200,"MIPGap" => mip_gap,"BarHomogeneous" => 1,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "ScaleFlag"=>2, "NumericFocus"=>2)
ipopt = JuMP.optimizer_with_attributes(Ipopt.Optimizer, "tol" => 1e-6, "print_level" => 0,"linear_solver" => "ma97")
juniper = JuMP.optimizer_with_attributes(Juniper.Optimizer, "nl_solver" => ipopt, "mip_solver" => gurobi, "time_limit" => 600)

#########################################################################################
## Processing input data
s = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true)
s_dual = Dict("output" => Dict("branch_flows" => true,"duals" => true), "conv_losses_mp" => true)

#########################################################################################
## Processing input data
input_folder = dirname(dirname(@__DIR__))
test_case_file = joinpath(input_folder,"data_sources/pglib_opf_case30_ieee.m")
original_grid = _PM.parse_file(test_case_file)

results_folder = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/IJEPES_paper/Results"
results_folder_figures = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/IJEPES_paper/Figures"
case = "case_30/stochastic_multistep"

test_case = _PM.parse_file(test_case_file)
test_case_opf = deepcopy(test_case)

# THIS IS APPARENTLY FUNDAMENTAL TO GUARANTEE FEASIBILITY
_SPMTA.add_VOLL_generators(test_case_opf)
_SPMTA.add_VOLL_generators(test_case)

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
result_feasibility_check = _PMACDC.run_acdcopf(feasibility_check,ACPPowerModel,ipopt; setting = s)


#########################################################################################
# Add dimensions for stochastic part
first_hour = 8153
last_hour  = 8488

n_hours = last_hour - first_hour + 1
one_scenario = 1
hours = collect(1:n_hours)
_SPMTA.add_dimensions!(test_case_bs,one_scenario,n_hours)

start_hour_simulation = 1
end_hour_simulation = 8760

#########################################################################################
# Uploading pdf samples for offshore wind and load data for Belgium
year_wind = "2024"
folder_data = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Elia_data"
#folder_results = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Deliverable_1_2_DIRECTIONS/Results/case_30"

input_data_folder = joinpath(@__DIR__,"case30")
#first_hour = 355 
#last_hour = 378

forecasted_wind = JSON.parsefile(joinpath(input_data_folder,"forecasted_two_weeks_$(first_hour)_$(last_hour).json"))
measured_wind = JSON.parsefile(joinpath(input_data_folder,"measured_two_weeks_$(first_hour)_$(last_hour).json"))

#forecasted_wind = JSON.parsefile(joinpath(input_data_folder,"forecasted_wind_hours_$(first_hour)_$(last_hour).json"))
#measured_wind = JSON.parsefile(joinpath(input_data_folder,"measured_wind_$(first_hour)_$(last_hour).json"))
average_forecasted_measured_wind = [mean([forecasted_wind[i],measured_wind[i]]) for i in 1:length(forecasted_wind)]

plot(forecasted_wind,label = "Forecasted wind",grid = :none,ylims = (0,1.2),legend = :topleft,xticks = 0:24:n_hours,xlims = (1,n_hours+1),xlabel = "Hour",ylabel = "Capacity factor [-]",)
plot!(measured_wind,label = "Average forecasted-measured wind")
plot!(average_forecasted_measured_wind,label = "Measured wind")

#########################################################################################
## Running simulations
# Busbar splitting
test_case_opf_replicate_one_scenario = _PM.replicate(test_case_opf, n_hours*one_scenario)

test_case_opf_mn_measured = deepcopy(test_case_opf_replicate_one_scenario)
test_case_opf_mn_forecasted = deepcopy(test_case_opf_replicate_one_scenario)
test_case_opf_mn_average = deepcopy(test_case_opf_replicate_one_scenario)


_SPMTA.adding_multinetwork_scenarios(test_case_opf_mn_measured,n_hours,one_scenario,one_scenario)
_SPMTA.adding_multinetwork_scenarios(test_case_opf_mn_forecasted,n_hours,one_scenario,one_scenario)
_SPMTA.adding_multinetwork_scenarios(test_case_opf_mn_average,n_hours,one_scenario,one_scenario)


for i in 1:(n_hours*one_scenario)
    test_case_opf_mn_measured["nw"]["$i"]["gen"]["1"]["pmax"]   = deepcopy(test_case_opf_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*measured_wind[i])
    test_case_opf_mn_forecasted["nw"]["$i"]["gen"]["1"]["pmax"] = deepcopy(test_case_opf_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*forecasted_wind[i])
    test_case_opf_mn_average["nw"]["$i"]["gen"]["1"]["pmax"]   = deepcopy(test_case_opf_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*average_forecasted_measured_wind[i])
end

################################################################################

result_forecasted_24_ac = Dict{String,Any}()
result_forecasted_24_lpac = Dict{String,Any}()

result_measured_24_ac = Dict{String,Any}()
result_measured_24_lpac = Dict{String,Any}()

result_average_24_ac = Dict{String,Any}()
result_average_24_lpac = Dict{String,Any}()

for hour in 1:(n_hours*one_scenario)
    result_forecasted_24_ac["$hour"] = _PM.solve_opf(test_case_opf_mn_forecasted["nw"]["$hour"],ACPPowerModel,ipopt; setting = s)
    result_forecasted_24_lpac["$hour"] = _PM.solve_opf(test_case_opf_mn_forecasted["nw"]["$hour"],LPACCPowerModel,ipopt; setting = s)

    result_measured_24_ac["$hour"] = _PM.solve_opf(test_case_opf_mn_measured["nw"]["$hour"],ACPPowerModel,ipopt; setting = s)
    result_measured_24_lpac["$hour"] = _PM.solve_opf(test_case_opf_mn_measured["nw"]["$hour"],LPACCPowerModel,ipopt; setting = s)

    result_average_24_ac["$hour"] = _PM.solve_opf(test_case_opf_mn_average["nw"]["$hour"],ACPPowerModel,ipopt; setting = s)
    result_average_24_lpac["$hour"] = _PM.solve_opf(test_case_opf_mn_average["nw"]["$hour"],LPACCPowerModel,ipopt; setting = s)
end


obj_forecasted_24_ac = [result_forecasted_24_ac["$i"]["objective"] for i in 1:(n_hours*one_scenario)]
obj_forecasted_24_lpac = [result_forecasted_24_lpac["$i"]["objective"] for i in 1:(n_hours*one_scenario)]
obj_measured_24_lpac = [result_measured_24_lpac["$i"]["objective"] for i in 1:(n_hours*one_scenario)]
obj_measured_24_ac = [result_measured_24_ac["$i"]["objective"] for i in 1:(n_hours*one_scenario)]
obj_average_24_ac = [result_average_24_ac["$i"]["objective"] for i in 1:(n_hours*one_scenario)]
obj_average_24_lpac = [result_average_24_lpac["$i"]["objective"] for i in 1:(n_hours*one_scenario)]


plot(obj_forecasted_24_ac)
plot!(obj_average_24_ac)
plot!(obj_measured_24_ac)

exp_ = sum(obj_expected_24_ac)
for_ = sum(obj_forecasted_24_ac)
avg_ = sum(obj_average_24_ac)


plot(obj_measured_24_ac./10^3,label = "Measured",grid = :none,ylims = (5,25),xticks = 0:24:n_hours,xlims = (0.8,n_hours),xlabel = "Hour",ylabel = "Generation costs [k€]",
legend = :topleft,xlabelfontsize = 10,ylabelfontsize = 10,xtickfont = font(8),ytickfont = font(8))
plot!(obj_forecasted_24_ac./10^3,label = "Forecasted")
plot!(obj_average_24_ac./10^3,label = "Average")
savefig(joinpath(results_folder_figures,"case_30","OPF_results_$(first_hour)_$(last_hour).svg"))
savefig(joinpath(results_folder_figures,"case_30","OPF_results_$(first_hour)_$(last_hour).pdf"))
savefig(joinpath(results_folder_figures,"case_30","OPF_results_$(first_hour)_$(last_hour).png"))


json_hourly_forecasted_24 = JSON.json(result_forecasted_24_ac)
open(joinpath(results_folder,case,"Hourly_opf_forecasted_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_hourly_forecasted_24) 
end 

json_hourly_measured_24 = JSON.json(result_measured_24_ac)
open(joinpath(results_folder,case,"Hourly_opf_measured_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_hourly_measured_24) 
end 

json_hourly_average_24 = JSON.json(result_average_24_ac)
open(joinpath(results_folder,case,"Hourly_opf_average_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_hourly_average_24) 
end 


###########################################################################
# -> OPFs are comparable now, data set built, need to tweak the functions to have a multistep-stochastic formulation
test_case_bs_replicate_one_scenario = _PM.replicate(test_case_bs, n_hours*one_scenario)

test_case_bs_mn_measured = deepcopy(test_case_bs_replicate_one_scenario)
test_case_bs_mn_forecasted = deepcopy(test_case_bs_replicate_one_scenario)
test_case_bs_mn_average = deepcopy(test_case_bs_replicate_one_scenario)

_SPMTA.adding_multinetwork_scenarios(test_case_bs_mn_measured,n_hours,one_scenario,one_scenario)
_SPMTA.adding_multinetwork_scenarios(test_case_bs_mn_forecasted,n_hours,one_scenario,one_scenario)
_SPMTA.adding_multinetwork_scenarios(test_case_bs_mn_average,n_hours,one_scenario,one_scenario)

for i in 1:(n_hours*one_scenario)
    test_case_bs_mn_measured["nw"]["$i"]["gen"]["1"]["pmax"]   = deepcopy(test_case_bs_replicate_one_scenario["nw"]["$i"]["gen"]["1"]["pmax"]*measured_wind[i])
    test_case_bs_mn_forecasted["nw"]["$i"]["gen"]["1"]["pmax"] = deepcopy(test_case_bs_replicate_one_scenario["nw"]["$i"]["gen"]["1"]["pmax"]*forecasted_wind[i])
    test_case_bs_mn_average["nw"]["$i"]["gen"]["1"]["pmax"] = deepcopy(test_case_bs_replicate_one_scenario["nw"]["$i"]["gen"]["1"]["pmax"]*average_forecasted_measured_wind[i])
end

test_case_bs_mn_measured_sp   = deepcopy(test_case_bs_mn_measured)
test_case_bs_mn_forecasted_sp = deepcopy(test_case_bs_mn_forecasted)
test_case_bs_mn_average_sp    = deepcopy(test_case_bs_mn_average)

_SPMTA.prepare_starting_value_dict_lpac_nw_sp(test_case_bs_mn_measured_sp,n_hours,one_scenario)
_SPMTA.prepare_starting_value_dict_lpac_nw_sp(test_case_bs_mn_forecasted_sp,n_hours,one_scenario)
_SPMTA.prepare_starting_value_dict_lpac_nw_sp(test_case_bs_mn_average_sp,n_hours,one_scenario)


result_bs_hourly_forecasted_24 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_per_hour(test_case_bs_mn_forecasted,LPACCPowerModel,gurobi_lpac,n_hours,one_scenario;setting = s)
result_bs_hourly_measured_24 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_per_hour(test_case_bs_mn_measured,LPACCPowerModel,gurobi_lpac,n_hours,one_scenario;setting = s)
result_bs_hourly_average_24 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_per_hour(test_case_bs_mn_average,LPACCPowerModel,gurobi_lpac,n_hours,one_scenario;setting = s)



json_hourly_forecasted_24 = JSON.json(result_bs_hourly_forecasted_24)
open(joinpath(results_folder,case,"Hourly_bs_forecasted_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_hourly_forecasted_24) 
end 

json_hourly_measured_24 = JSON.json(result_bs_hourly_measured_24)
open(joinpath(results_folder,case,"Hourly_bs_measured_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_hourly_measured_24) 
end 

json_hourly_average_24 = JSON.json(result_bs_hourly_average_24)
open(joinpath(results_folder,case,"Hourly_bs_average_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_hourly_average_24) 
end 


#=
function run_feasibility_checks_per_hour(grid, result_bs, model, optimizer,switches_couples_ac,extremes_ZILs_ac,test_case_opf,settings,n_scenarios)
    result_feasibility_checks = Dict{String,Any}()
    for hour in 1:length(grid["nw"])
        if !haskey(result_bs["$hour"]["solution"],"nw")
            result_feasibility_checks["$hour"] = Dict{String,Any}()
            feasibility_check = deepcopy(grid["nw"]["$hour"])
            feasibility_check_input = deepcopy(grid["nw"]["$hour"])
            _PMTP.prepare_AC_feasibility_check(result_bs["$hour"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
            result_feasibility_checks["$hour"] = _PM.solve_opf(feasibility_check,model,optimizer; setting = settings)
        elseif haskey(result_bs["$hour"]["solution"],"nw")
            result_feasibility_checks["$hour"] = Dict{String,Any}()
            feasibility_check = deepcopy(grid["nw"]["$hour"])
            feasibility_check_input = deepcopy(grid["nw"]["$hour"])
            prepare_AC_feasibility_check_stochastic(result_bs["$hour"]["solution"]["nw"]["$n_scenarios"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
            result_feasibility_checks["$hour"] = _PM.solve_opf(feasibility_check,model,optimizer; setting = settings)    
        end
    end
    return result_feasibility_checks
end

function prepare_AC_feasibility_check_stochastic(result_dict, input_dict, input_ac_check, switch_couples, extremes_dict,input_base)
    orig_buses = maximum(parse.(Int, keys(input_base["bus"]))) # maximum value before splitting (in case the buses are not in numerical order)
    for (sw_id,sw) in input_dict["switch"]
        if !haskey(sw,"auxiliary")
            println("SWITCH $sw_id, BUS from $(sw["f_bus"]), BUS to $(sw["t_bus"])")
            if result_dict["switch"][sw_id]["status"] >= 0.9 # Just reconnecting stuff
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
            elseif result_dict["switch"][sw_id]["status"] <= 0.1 # Connect elements to the right bus
                println("Switch $sw_id is open, busbar splitting on bus $(sw["bus_split"])")
                delete!(input_ac_check["switch"],sw_id)
                for l in keys(switch_couples)
                    if switch_couples[l]["bus_split"] == sw["bus_split"] # coupling the switch couple to their split bus
                        println("SWITCH COUPLE IS $l")
                            switch_t = deepcopy(input_dict["switch"]["$(switch_couples["$l"]["t_sw"])"]) 
                            aux_t = switch_t["auxiliary"]
                            orig_t = switch_t["original"]
                            println("Element $aux_t $orig_t")
                            if result_dict["switch"]["$(switch_t["index"])"]["status"] <= 0.1
                                println("Deleting switch $(switch_t["index"])")
                                delete!(input_ac_check["switch"],"$(switch_t["index"])")
                            elseif result_dict["switch"]["$(switch_t["index"])"]["status"] >= 0.9
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
                            if result_dict["switch"]["$(switch_f["index"])"]["status"] <= 0.1
                                println("Deleting switch $(switch_f["index"])")
                                delete!(input_ac_check["switch"],"$(switch_f["index"])")
                            elseif result_dict["switch"]["$(switch_f["index"])"]["status"] >= 0.9
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
                        #end
                    end
                end
            end
            input_ac_check["switch"] = Dict{String,Any}()
            input_ac_check["switch_couples"] = Dict{String,Any}()
        end
    end
end


result_forecasted_feasibility_checks_24_ac   = run_feasibility_checks_per_hour(test_case_bs_mn_forecasted,result_bs_hourly_forecasted_24,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s,n_scenarios)
result_forecasted_feasibility_checks_24_lpac = run_feasibility_checks_per_hour(test_case_bs_mn_forecasted,result_bs_hourly_forecasted_24,LPACCPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s,n_scenarios)

result_measured_feasibility_checks_24_ac   = run_feasibility_checks_per_hour(test_case_bs_mn_measured,result_bs_hourly_measured_24,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s,n_scenarios)
result_measured_feasibility_checks_24_lpac = run_feasibility_checks_per_hour(test_case_bs_mn_measured,result_bs_hourly_measured_24,LPACCPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s,n_scenarios)

result_expected_feasibility_checks_24_ac   = run_feasibility_checks_per_hour(test_case_bs_mn_forecasted,result_bs_hourly_expected_24,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s,n_scenarios)
result_expected_feasibility_checks_24_lpac = run_feasibility_checks_per_hour(test_case_bs_mn_forecasted,result_bs_hourly_expected_24,LPACCPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s,n_scenarios)


hourly_forecasted_bs = [result_forecasted_feasibility_checks_24_ac["$h"]["objective"] for h in 1:n_hours]
hourly_measured_bs = [result_measured_feasibility_checks_24_ac["$h"]["objective"] for h in 1:n_hours]
hourly_expected_bs = [result_expected_feasibility_checks_24_ac["$h"]["objective"] for h in 1:n_hours]



plot(obj_expected_24_ac./10^3,label = "Stochastic OPF",grid = :none,ylims = (5,25),xticks = 1:n_hours,xlims = (0.8,24.5),xlabel = "Hour",ylabel = "Generation costs [k€]",
legend = :topleft,xlabelfontsize = 10,ylabelfontsize = 10,xtickfont = font(8),ytickfont = font(8))
plot!(obj_measured_24_ac./10^3,label = "Measured OPF")
plot!(obj_forecasted_24_ac./10^3,label = "Forecasted OPF")
plot!(hourly_expected_bs./10^3,label = "Stochastic hourly BS")
plot!(hourly_measured_bs./10^3,label = "Measured hourly BS")
plot!(hourly_forecasted_bs./10^3,label = "Forecasted hourly BS")
=#

test_case_bs_mn_measured_days   = Dict{String,Any}()
test_case_bs_mn_forecasted_days = Dict{String,Any}()
test_case_bs_mn_average_days    = Dict{String,Any}()
n_days = 14

for day in 1:n_days
    test_case_bs_mn_measured_days["$day"]   = Dict{String,Any}()
    test_case_bs_mn_forecasted_days["$day"] = Dict{String,Any}()
    test_case_bs_mn_average_days["$day"]    = Dict{String,Any}()
    test_case_bs_mn_measured_days["$day"]   = deepcopy(test_case_bs_mn_measured_sp)
    test_case_bs_mn_measured_days["$day"]["hours"] = 24
    test_case_bs_mn_forecasted_days["$day"] = deepcopy(test_case_bs_mn_forecasted)
    test_case_bs_mn_average_days["$day"]    = deepcopy(test_case_bs_mn_average)
    test_case_bs_mn_measured_days["$day"]["nw"]   = Dict{String,Any}()
    test_case_bs_mn_forecasted_days["$day"]["nw"] = Dict{String,Any}()
    test_case_bs_mn_average_days["$day"]["nw"]    = Dict{String,Any}()
    nw_day_first_hour = (day-1)*24 + 1
    nw_day_last_hour = day*24
    count_hour = 0
    for hour in nw_day_first_hour:nw_day_last_hour
        count_hour += 1
        test_case_bs_mn_measured_days["$day"]["nw"]["$count_hour"]   = deepcopy(test_case_bs_mn_measured_sp["nw"]["$hour"])
        test_case_bs_mn_forecasted_days["$day"]["nw"]["$count_hour"] = deepcopy(test_case_bs_mn_forecasted_sp["nw"]["$hour"])
        test_case_bs_mn_average_days["$day"]["nw"]["$count_hour"]    = deepcopy(test_case_bs_mn_average_sp["nw"]["$hour"])
    end
end



#########################################################################
results_one_topology_sp_forecasted = Dict{String,Any}()
results_one_topology_sp_measured   = Dict{String,Any}()
results_one_topology_sp_average    = Dict{String,Any}()
for day in 2:n_days
    results_one_topology_sp_forecasted["$day"] = Dict{String,Any}()
    #results_one_topology_sp_measured["$day"]   = Dict{String,Any}()
    #results_one_topology_sp_average["$day"]    = Dict{String,Any}()    
    results_one_topology_sp_forecasted["$day"] = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology_sp(test_case_bs_mn_forecasted_days["$day"],LPACCPowerModel,gurobi_bs; setting = s)
    #results_one_topology_sp_measured["$day"] = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology_sp(test_case_bs_mn_measured_days["$day"],LPACCPowerModel,gurobi_bs; setting = s)
    #results_one_topology_sp_average["$day"] = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology(test_case_bs_mn_average,LPACCPowerModel,gurobi_bs; setting = s)
end


[results_one_topology_sp_measured["$day"]["objective"] for day in 1:14]

json_results_one_topology_sp_forecasted = JSON.json(results_one_topology_sp_forecasted)
open(joinpath(results_folder,case,"24_hours_BS_one_topology_forecasted_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_results_one_topology_sp_forecasted) 
end 

json_results_one_topology_sp_measured = JSON.json(results_one_topology_sp_measured)
open(joinpath(results_folder,case,"24_hours_BS_one_topology_measured_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_results_one_topology_sp_measured) 
end 

json_results_one_topology_sp_average = JSON.json(results_one_topology_sp_average)
open(joinpath(results_folder,case,"24_hours_BS_one_topology_average_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_results_one_topology_sp_average) 
end 

json_results_one_topology_sp_stochastic = JSON.json(results_one_topology_sp_stochastic)
open(joinpath(results_folder,case,"24_hours_BS_one_topology_stochastic_$(n_scenarios)_scenarios_$(first_hour)_$(last_hour)_25_06_25200.json"),"w") do f 
    write(f, json_results_one_topology_sp_stochastic) 
end 

json_results_one_topology_sp_adjusted = JSON.json(results_one_topology_sp_adjusted)
open(joinpath(results_folder,case,"24_hours_BS_one_topology_adjusted_4_scenarios_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_results_one_topology_sp_adjusted) 
end 

################################################


####################################################

test_case_bs_mn_forecasted_try_max_sw = deepcopy(test_case_bs_mn_forecasted)
test_case_bs_mn_measured_try_max_sw = deepcopy(test_case_bs_mn_measured)
test_case_bs_mn_average_try_max_sw = deepcopy(test_case_bs_mn_average)
test_case_bs_mn_expected_try_max_sw = deepcopy(test_case_bs_mn_expected)
test_case_bs_mn_adjusted_try_max_sw = deepcopy(test_case_bs_mn_adjusted)

test_case_bs_mn_forecasted["total_switching_actions"] = 1
test_case_bs_mn_measured["total_switching_actions"] = 1
test_case_bs_mn_average["total_switching_actions"] = 1
test_case_bs_mn_expected["total_switching_actions"] = 1
test_case_bs_mn_adjusted["total_switching_actions"] = 1

for (sw_id,sw) in test_case_bs_mn_forecasted["nw"]["1"]["switch"]
    sw["maximum_actions"] = 1
end
for (sw_id,sw) in test_case_bs_mn_measured["nw"]["1"]["switch"]
    sw["maximum_actions"] = 1
end
for (sw_id,sw) in test_case_bs_mn_average["nw"]["1"]["switch"]
    sw["maximum_actions"] = 1
end
for (sw_id,sw) in test_case_bs_mn_expected["nw"]["1"]["switch"]
    sw["maximum_actions"] = 1
end
for (sw_id,sw) in test_case_bs_mn_adjusted["nw"]["1"]["switch"]
    sw["maximum_actions"] = 1
end

results_one_topology_sp_forecasted_one_max_sw = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches(test_case_bs_mn_forecasted,LPACCPowerModel,gurobi_bs)
results_one_topology_sp_measured_one_max_sw = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches(test_case_bs_mn_measured,LPACCPowerModel,gurobi_bs)
results_one_topology_sp_average_one_max_sw = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches(test_case_bs_mn_average,LPACCPowerModel,gurobi_bs)
results_one_topology_sp_expected_one_max_sw = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches_stochastic(test_case_bs_mn_expected,LPACCPowerModel,gurobi_bs)
results_one_topology_sp_adjusted_one_max_sw = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches_stochastic(test_case_bs_mn_adjusted,LPACCPowerModel,gurobi)


json_results_one_topology_sp_forecasted_one_max_sw = JSON.json(results_one_topology_sp_forecasted_one_max_sw)
open(joinpath(results_folder,case,"One_maximum_actions_24_hours_forecasted_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_results_one_topology_sp_forecasted_one_max_sw) 
end 

json_results_one_topology_sp_measured_one_max_sw = JSON.json(results_one_topology_sp_measured_one_max_sw)
open(joinpath(results_folder,case,"One_maximum_actions_24_hours_measured_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_results_one_topology_sp_measured_one_max_sw) 
end 

json_results_one_topology_sp_average_one_max_sw = JSON.json(results_one_topology_sp_average_one_max_sw)
open(joinpath(results_folder,case,"One_maximum_actions_24_hours_average_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_results_one_topology_sp_average_one_max_sw) 
end 

json_results_one_topology_sp_expected_one_max_sw = JSON.json(results_one_topology_sp_expected_one_max_sw)
open(joinpath(results_folder,case,"One_maximum_actions_24_hours_expected_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_results_one_topology_sp_expected_one_max_sw) 
end 

json_results_one_topology_sp_adjusted_one_max_sw = JSON.json(results_one_topology_sp_adjusted_one_max_sw)
open(joinpath(results_folder,case,"One_maximum_actions_24_hours_adjusted_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_results_one_topology_sp_adjusted_one_max_sw) 
end 


#######

test_case_bs_mn_forecasted_two_max_sw = deepcopy(test_case_bs_mn_forecasted)
test_case_bs_mn_measured_two_max_sw = deepcopy(test_case_bs_mn_measured)
test_case_bs_mn_average_two_max_sw = deepcopy(test_case_bs_mn_average)
test_case_bs_mn_expected_two_max_sw = deepcopy(test_case_bs_mn_expected)
test_case_bs_mn_adjusted_two_max_sw = deepcopy(test_case_bs_mn_adjusted)

test_case_bs_mn_forecasted["total_switching_actions"] = 2
test_case_bs_mn_measured["total_switching_actions"] = 2
test_case_bs_mn_average["total_switching_actions"] = 2
test_case_bs_mn_expected["total_switching_actions"] = 2
test_case_bs_mn_adjusted["total_switching_actions"] = 2

for (sw_id,sw) in test_case_bs_mn_forecasted["nw"]["1"]["switch"]
    sw["maximum_actions"] = 2
end
for (sw_id,sw) in test_case_bs_mn_measured["nw"]["1"]["switch"]
    sw["maximum_actions"] = 2
end
for (sw_id,sw) in test_case_bs_mn_average["nw"]["1"]["switch"]
    sw["maximum_actions"] = 2
end
for (sw_id,sw) in test_case_bs_mn_expected["nw"]["1"]["switch"]
    sw["maximum_actions"] = 2
end
for (sw_id,sw) in test_case_bs_mn_adjusted["nw"]["1"]["switch"]
    sw["maximum_actions"] = 2
end

results_one_topology_sp_forecasted_max_sw_2 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches(test_case_bs_mn_forecasted,LPACCPowerModel,gurobi_bs)
results_one_topology_sp_measured_max_sw_2 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches(test_case_bs_mn_measured,LPACCPowerModel,gurobi_bs)
results_one_topology_sp_average_max_sw_2 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches(test_case_bs_mn_average,LPACCPowerModel,gurobi_bs)
results_one_topology_sp_expected_max_sw_2 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches_stochastic(test_case_bs_mn_expected,LPACCPowerModel,gurobi_bs)
results_one_topology_sp_adjusted_max_sw_2 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches_stochastic(test_case_bs_mn_adjusted,LPACCPowerModel,gurobi_bs)



json_results_two_topology_forecasted = JSON.json(results_one_topology_sp_forecasted_max_sw_2)
open(joinpath(results_folder,case,"Two_maximum_actions_24_hours_forecasted_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_results_two_topology_forecasted) 
end 

json_results_two_topology__measured = JSON.json(results_one_topology_sp_measured_max_sw_2)
open(joinpath(results_folder,case,"Two_maximum_actions_24_hours_measured_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_results_two_topology__measured) 
end 

json_results_two_topology_average = JSON.json(results_one_topology_sp_average_max_sw_2)
open(joinpath(results_folder,case,"Two_maximum_actions_24_hours_average_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_results_two_topology_average) 
end 

json_results_two_topology_expected = JSON.json(results_one_topology_sp_expected_max_sw_2)
open(joinpath(results_folder,case,"Two_maximum_actions_24_hours_expected_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_results_two_topology_expected) 
end 

json_results_two_topology_adjusted = JSON.json(results_one_topology_sp_adjusted_max_sw_2)
open(joinpath(results_folder,case,"Two_maximum_actions_24_hours_adjusted_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_results_two_topology_adjusted) 
end 

