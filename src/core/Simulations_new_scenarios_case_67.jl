using PowerModels; const _PM = PowerModels
using PowerModelsACDC; const _PMACDC = PowerModelsACDC
import PowerModelsTopologicalActionsII; const _PMTP = PowerModelsTopologicalActionsII
using FlexPlan; const _FP = FlexPlan
using Gurobi, Ipopt, JSON, Plots
import StochasticPowerModelsTopologicalActions; const _SPMTA = StochasticPowerModelsTopologicalActions
using JuMP, Juniper, HSL_jll, MathOptInterface, HiGHS
using Statistics

mip_gap = 1e-4
gurobi_bs = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 3600*7,"MIPGap" => mip_gap,"BarHomogeneous" => 1, "NumericFocus"=>2) 
gurobi = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 1200,"MIPGap" => mip_gap,"BarHomogeneous" => 1,"BarQCPConvTol"=>1e-6,"QCPDual" => 1, "ScaleFlag"=>2, "NumericFocus"=>2) 
gurobi_opf = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 600,"MIPGap" => mip_gap,"BarHomogeneous" => 1, "NumericFocus"=>2,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "ScaleFlag"=>2, "NumericFocus"=>3) 
gurobi_lpac = JuMP.optimizer_with_attributes(Gurobi.Optimizer)#,"time_limit" => 1200,"MIPGap" => mip_gap,"BarHomogeneous" => 1,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "ScaleFlag"=>2, "NumericFocus"=>2)
ipopt = JuMP.optimizer_with_attributes(Ipopt.Optimizer, "tol" => 1e-6, "print_level" => 0,"linear_solver" => "ma57")
juniper = JuMP.optimizer_with_attributes(Juniper.Optimizer, "nl_solver" => ipopt, "mip_solver" => gurobi, "time_limit" => 600)

#########################################################################################
## Processing input data
s = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true)
s_dual = Dict("output" => Dict("branch_flows" => true,"duals" => true), "conv_losses_mp" => true)

#########################################################################################
## Processing input data
input_folder = dirname(dirname(@__DIR__))
test_case_file = joinpath(input_folder,"data_sources/case24_3zones_acdc.m")
original_grid = _PM.parse_file(test_case_file)
_PMACDC.process_additional_data!(original_grid)
test_case = deepcopy(original_grid)

results_folder = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/IJEPES_paper/Results"
results_folder_figures = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/IJEPES_paper/Figures"
case = "case_24/stochastic_multistep"


function add_VOLL_generators(data,gen_to_be_duplicated)
    first_l = maximum(parse.(Int, keys(data["gen"])))
    count = 0
    for (b_id,b) in data["bus"]
        count += 1
        l = first_l + count
        data["gen"]["$l"] = deepcopy(data["gen"]["$gen_to_be_duplicated"])
        #data["gen"]["$l"]["installed_capacity"] = 99.99
        data["gen"]["$l"]["gen_bus"] = parse(Int64,b_id) 
        data["gen"]["$l"]["pmax"] = 99.99
        #data["gen"]["$l"]["mbase"] = 9999
        data["gen"]["$l"]["source_id"][2] = deepcopy(l)
        #data["gen"]["$l"]["gen_type"] = "VOLL"
        data["gen"]["$l"]["index"] = l 
        #data["gen"]["$l"]["type"] = "VOLL"
        data["gen"]["$l"]["cost"][1] = 4400
    end
end
add_VOLL_generators(test_case,1)



for (g_id,g) in test_case["gen"]
    g["pmin"] = 0
end
for (g_id,g) in test_case["gen"]
    if length(g["cost"]) > 2
        g["cost"] = deepcopy(g["cost"][1:2]) 
    elseif length(g["cost"]) == 0
        push!(g["cost"],183.846)
        push!(g["cost"],0.0)
    end
end

for (g_id,g) in test_case["gen"]
    g["ncost"] = 2
    g["cost"][2] = 0
    g["cost"][1] = g["cost"][1]*1.3
end

for (l_id,l) in test_case["load"]
    if l["pd"] > 2.0
        l["pd"] = l["pd"]*1.2
    end
end
test_case_opf = deepcopy(test_case)

#for (g_id,g) in test_case["gen"]
#    if length(g["cost"]) > 0 && g["cost"][1] == 10000.0
#        g["cost"][1] = 180.0 # Just to avoid problems with the cost function
#    end
#end

for (g_id,g) in test_case["gen"]
    println([g_id,g["cost"]])
end


opf_67 = _PMACDC.run_acdcopf(test_case, LPACCPowerModel, ipopt; setting = s)
opf_67_ac = _PMACDC.run_acdcopf(test_case, ACPPowerModel, ipopt; setting = s_dual)


#########################################################################################
# Busbar splitting
test_case_bs = deepcopy(test_case)

splitted_bus_ac = 211
test_case_bs,  switches_couples_ac,  extremes_ZILs_ac  = _PMTP.AC_busbar_split_AC_grid(test_case,splitted_bus_ac)
    
# Adding costs to the busbar couplers
for sw_id in 1:length(extremes_ZILs_ac)
    test_case_bs["switch"]["$sw_id"]["cost"] = 1.0
end

result_bs_6 = _PMTP.run_acdcsw_AC_big_M_hour(test_case_bs, LPACCPowerModel, gurobi_bs)


feasibility_check = deepcopy(test_case_bs)
feasibility_check_input = deepcopy(test_case_bs)
_PMTP.prepare_AC_feasibility_check(result_bs_6,feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
result_feasibility_check = _PMACDC.run_acdcopf(feasibility_check,ACPPowerModel,ipopt; setting = s)


#########################################################################################
# Add dimensions for stochastic part
input_data_folder_time_series = joinpath(@__DIR__,"case30")

n_days = 14
one_scenario = 1
n_scenarios = 1

if n_days == 1
    hours = collect(1:n_days*24)
    first_hour = 355
    last_hour  = 378
    n_hours = last_hour - first_hour + 1

    test_case["scenarios"] = n_scenarios
    test_case["hours"] = n_hours

    forecasted_wind = JSON.parsefile(joinpath(input_data_folder_time_series,"forecasted_wind_hours_$(first_hour)_$(last_hour)_modified.json"))
    measured_wind = JSON.parsefile(joinpath(input_data_folder_time_series,"measured_wind_$(first_hour)_$(last_hour)_modified.json"))

elseif n_days == 14
    hours = collect(1:n_days*24)
    first_hour = 8153
    last_hour  = 8488
    n_hours = last_hour - first_hour + 1

    forecasted_wind = JSON.parsefile(joinpath(input_data_folder_time_series,"forecasted_two_weeks_$(first_hour)_$(last_hour).json"))
    measured_wind = JSON.parsefile(joinpath(input_data_folder_time_series,"measured_two_weeks_$(first_hour)_$(last_hour).json"))
end


#average_forecasted_measured_wind = [mean([forecasted_wind[i],measured_wind[i]]) for i in 1:length(forecasted_wind)]

plot(forecasted_wind,label = "Forecasted wind",grid = :none,ylims = (0,1.2),legend = :topleft,xticks = 0:24:n_hours,xlims = (1,n_hours+1),xlabel = "Hour",ylabel = "Capacity factor [-]",)
plot!(measured_wind,label = "Measured wind")
#plot!(average_forecasted_measured_wind,label = "Measured wind")

#########################################################################################
## Running simulations
# Busbar splitting
test_case_opf_replicate_one_scenario = _PM.replicate(test_case_opf, n_hours*one_scenario)

test_case_opf_mn_measured = deepcopy(test_case_opf_replicate_one_scenario)
test_case_opf_mn_forecasted = deepcopy(test_case_opf_replicate_one_scenario)

_SPMTA.adding_multinetwork_scenarios(test_case_opf_mn_measured,n_hours,one_scenario,one_scenario)
_SPMTA.adding_multinetwork_scenarios(test_case_opf_mn_forecasted,n_hours,one_scenario,one_scenario)

for (g_id,g) in test_case["gen"]
    if length(test_case["gen"][g_id]["cost"]) > 0 && test_case["gen"][g_id]["cost"][1] <= 0.14 #&& test_case["gen"][g_id]["cost"][1] <= 750.0 
            for i in 1:(n_hours*one_scenario)
                println("Generator $g_id, cost $(test_case["gen"][g_id]["cost"]), pmax $(test_case["gen"][g_id]["pmax"]) MW")
                test_case_opf_mn_measured["nw"]["$i"]["gen"][g_id]["pmax"]   = deepcopy(test_case_opf_replicate_one_scenario["nw"]["$i"]["gen"][g_id]["pmax"]*measured_wind[i])
                println("Pmax gen $(g_id) is $(test_case_opf_mn_measured["nw"]["$i"]["gen"][g_id]["pmax"])") 
                test_case_opf_mn_forecasted["nw"]["$i"]["gen"][g_id]["pmax"] = deepcopy(test_case_opf_replicate_one_scenario["nw"]["$i"]["gen"][g_id]["pmax"]*forecasted_wind[i])
                #test_case_opf_mn_average["nw"]["$i"]["gen"][g_id]["pmax"] = deepcopy(test_case_opf_replicate_one_scenario["nw"]["$i"]["gen"][g_id]["pmax"]*average_forecasted_measured_wind[i])
            end
    end
end

################################################################################

result_forecasted_24_ac = Dict{String,Any}()
result_forecasted_24_lpac = Dict{String,Any}()

result_measured_24_ac = Dict{String,Any}()
result_measured_24_lpac = Dict{String,Any}()


for hour in 1:(n_hours*one_scenario)
    result_forecasted_24_ac["$hour"] = _PMACDC.run_acdcopf(test_case_opf_mn_forecasted["nw"]["$hour"],ACPPowerModel,ipopt; setting = s)
    result_forecasted_24_lpac["$hour"] = _PMACDC.run_acdcopf(test_case_opf_mn_forecasted["nw"]["$hour"],LPACCPowerModel,ipopt; setting = s)

    result_measured_24_ac["$hour"] = _PMACDC.run_acdcopf(test_case_opf_mn_measured["nw"]["$hour"],ACPPowerModel,ipopt; setting = s)
    result_measured_24_lpac["$hour"] = _PMACDC.run_acdcopf(test_case_opf_mn_measured["nw"]["$hour"],LPACCPowerModel,ipopt; setting = s)

    #result_average_24_ac["$hour"] = _PM.solve_opf(test_case_opf_mn_average["nw"]["$hour"],ACPPowerModel,ipopt; setting = s)
    #result_average_24_lpac["$hour"] = _PM.solve_opf(test_case_opf_mn_average["nw"]["$hour"],LPACCPowerModel,ipopt; setting = s)
end

sum(result_measured_24_ac["$h"]["objective"] for h in 1:(n_hours*one_scenario))
sum(result_forecasted_24_ac["$h"]["objective"] for h in 1:(n_hours*one_scenario))

json_hourly_forecasted_24 = JSON.json(result_forecasted_24_ac)
open(joinpath(results_folder,case,"Hourly_opf_ac_forecasted_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_hourly_forecasted_24) 
end 

json_hourly_measured_24 = JSON.json(result_measured_24_ac)
open(joinpath(results_folder,case,"Hourly_opf_ac_measured_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_hourly_measured_24) 
end 

json_hourly_forecasted_24 = JSON.json(result_forecasted_24_lpac)
open(joinpath(results_folder,case,"Hourly_opf_lpac_forecasted_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_hourly_forecasted_24) 
end 

json_hourly_measured_24 = JSON.json(result_measured_24_lpac)
open(joinpath(results_folder,case,"Hourly_opf_lpac_measured_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_hourly_measured_24) 
end 




function print_generation_per_hour(test_case, result, hour)
    for (g_id,g) in test_case["nw"]["$hour"]["gen"]
        if result["$hour"]["solution"]["gen"][g_id]["pg"] > 0.001
            println("Gen $g_id, cost $(g["cost"]), generating $(result["$hour"]["solution"]["gen"][g_id]["pg"]) out of $(g["pmax"]), gen_bus $(g["gen_bus"])")
        end
    end
end
print_generation_per_hour(test_case_opf_mn_forecasted, result_forecasted_24_ac, 12)

obj_forecasted_24_ac = [result_forecasted_24_ac["$i"]["objective"] for i in 1:(n_hours*one_scenario)]
obj_forecasted_24_lpac = [result_forecasted_24_lpac["$i"]["objective"] for i in 1:(n_hours*one_scenario)]
obj_measured_24_lpac = [result_measured_24_lpac["$i"]["objective"] for i in 1:(n_hours*one_scenario)]
obj_measured_24_ac = [result_measured_24_ac["$i"]["objective"] for i in 1:(n_hours*one_scenario)]
#obj_average_24_ac = [result_average_24_ac["$i"]["objective"] for i in 1:(n_hours*one_scenario)]
#obj_average_24_lpac = [result_average_24_lpac["$i"]["objective"] for i in 1:(n_hours*one_scenario)]


plot(obj_forecasted_24_ac)
#plot!(obj_average_24_ac)
plot!(obj_measured_24_ac)

exp_ = sum(obj_measured_24_ac)
for_ = sum(obj_forecasted_24_ac)
#avg_ = sum(obj_average_24_ac)


plot(obj_measured_24_ac./10^3,label = "Measured",grid = :none,xticks = 0:1:n_hours,xlims = (0.8,n_hours),xlabel = "Hour",ylabel = "Generation costs [k€]",
legend = :topleft,xlabelfontsize = 10,ylabelfontsize = 10,xtickfont = font(8),ytickfont = font(8),)
plot!(obj_forecasted_24_ac./10^3,label = "Forecasted")
#plot!(obj_average_24_ac./10^3,label = "Average")
savefig(joinpath(results_folder_figures,"case_24","OPF_results_$(first_hour)_$(last_hour).svg"))
savefig(joinpath(results_folder_figures,"case_24","OPF_results_$(first_hour)_$(last_hour).pdf"))
savefig(joinpath(results_folder_figures,"case_24","OPF_results_$(first_hour)_$(last_hour).png"))



#json_hourly_average_24 = JSON.json(result_average_24_ac)
#open(joinpath(results_folder,case,"Hourly_opf_average_$(first_hour)_$(last_hour).json"),"w") do f 
#    write(f, json_hourly_average_24) 
#end 


###########################################################################
# -> OPFs are comparable now, data set built, need to tweak the functions to have a multistep-stochastic formulation
test_case_bs_replicate_one_scenario = _PM.replicate(test_case_bs, n_hours*one_scenario)

test_case_bs_mn_measured = deepcopy(test_case_bs_replicate_one_scenario)
test_case_bs_mn_forecasted = deepcopy(test_case_bs_replicate_one_scenario)
test_case_bs_mn_average = deepcopy(test_case_bs_replicate_one_scenario)

_SPMTA.adding_multinetwork_scenarios(test_case_bs_mn_measured,n_hours,one_scenario,one_scenario)
_SPMTA.adding_multinetwork_scenarios(test_case_bs_mn_forecasted,n_hours,one_scenario,one_scenario)
_SPMTA.adding_multinetwork_scenarios(test_case_bs_mn_average,n_hours,one_scenario,one_scenario)

for (g_id,g) in test_case["gen"]
    if test_case["gen"][g_id]["cost"][1] <= 0.14 #&& test_case["gen"][g_id]["cost"][1] <= 750.0 
            for i in 1:(n_hours*one_scenario)
                println("Generator $g_id, cost $(test_case["gen"][g_id]["cost"]), pmax $(test_case["gen"][g_id]["pmax"]) MW")
                test_case_bs_mn_measured["nw"]["$i"]["gen"][g_id]["pmax"]   = deepcopy(test_case_bs_replicate_one_scenario["nw"]["$i"]["gen"][g_id]["pmax"]*measured_wind[i])
                test_case_bs_mn_forecasted["nw"]["$i"]["gen"][g_id]["pmax"] = deepcopy(test_case_bs_replicate_one_scenario["nw"]["$i"]["gen"][g_id]["pmax"]*forecasted_wind[i])
            end
    end
end

test_case_bs_mn_measured_sp   = deepcopy(test_case_bs_mn_measured)
test_case_bs_mn_forecasted_sp = deepcopy(test_case_bs_mn_forecasted)
#test_case_bs_mn_average_sp    = deepcopy(test_case_bs_mn_average)

_SPMTA.prepare_starting_value_dict_lpac_nw_sp(test_case_bs_mn_measured_sp,n_hours,one_scenario)
_SPMTA.prepare_starting_value_dict_lpac_nw_sp(test_case_bs_mn_forecasted_sp,n_hours,one_scenario)
#_SPMTA.prepare_starting_value_dict_lpac_nw_sp(test_case_bs_mn_average_sp,n_hours,one_scenario)

result_bs_hourly_forecasted_24 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_per_hour(test_case_bs_mn_forecasted,LPACCPowerModel,gurobi_bs,n_hours,one_scenario;setting = s)
json_hourly_forecasted_24 = JSON.json(result_bs_hourly_forecasted_24)
open(joinpath(results_folder,case,"Hourly_bs_forecasted_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_hourly_forecasted_24) 
end 

result_bs_hourly_measured_24 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_per_hour(test_case_bs_mn_measured,LPACCPowerModel,gurobi_lpac,n_hours,one_scenario;setting = s)
json_hourly_measured_24 = JSON.json(result_bs_hourly_measured_24)
open(joinpath(results_folder,case,"Hourly_bs_measured_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_hourly_measured_24) 
end 

#result_bs_hourly_average_24 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_per_hour(test_case_bs_mn_average,LPACCPowerModel,gurobi_lpac,n_hours,one_scenario;setting = s)

obj_opf_forecasted = [result_forecasted_24_lpac["$i"]["objective"] for i in 1:(n_hours*one_scenario)]
obj_bs_forecasted = [result_bs_hourly_forecasted_24["$i"]["objective"] for i in 1:(n_hours*one_scenario)]

((obj_opf_forecasted .- obj_bs_forecasted)./ obj_opf_forecasted)*100

obj_opf_measured = [result_measured_24_lpac["$i"]["objective"] for i in 1:(n_hours*one_scenario)]
obj_bs_measured = [result_bs_hourly_measured_24["$i"]["objective"] for i in 1:(n_hours*one_scenario)]

((obj_opf_measured .- obj_bs_measured)./ obj_opf_measured)*100




test_case_bs_mn_measured_days   = Dict{String,Any}()
test_case_bs_mn_forecasted_days = Dict{String,Any}()
#test_case_bs_mn_average_days    = Dict{String,Any}()
n_days = 14

for day in 1:n_days
    test_case_bs_mn_measured_days["$day"]   = Dict{String,Any}()
    test_case_bs_mn_forecasted_days["$day"] = Dict{String,Any}()
    #test_case_bs_mn_average_days["$day"]    = Dict{String,Any}()
    test_case_bs_mn_measured_days["$day"]   = deepcopy(test_case_bs_mn_measured_sp)
    test_case_bs_mn_measured_days["$day"]["hours"] = 24
    test_case_bs_mn_forecasted_days["$day"] = deepcopy(test_case_bs_mn_forecasted)
    test_case_bs_mn_forecasted_days["$day"]["hours"] = 24
    #test_case_bs_mn_average_days["$day"]    = deepcopy(test_case_bs_mn_average)
    #test_case_bs_mn_average_days["$day"]["hours"] = 24
    test_case_bs_mn_measured_days["$day"]["nw"]   = Dict{String,Any}()
    test_case_bs_mn_forecasted_days["$day"]["nw"] = Dict{String,Any}()
    #test_case_bs_mn_average_days["$day"]["nw"]    = Dict{String,Any}()
    nw_day_first_hour = (day-1)*24 + 1
    nw_day_last_hour = day*24
    count_hour = 0
    for hour in nw_day_first_hour:nw_day_last_hour
        count_hour += 1
        test_case_bs_mn_measured_days["$day"]["nw"]["$count_hour"]   = deepcopy(test_case_bs_mn_measured_sp["nw"]["$hour"])
        test_case_bs_mn_forecasted_days["$day"]["nw"]["$count_hour"] = deepcopy(test_case_bs_mn_forecasted_sp["nw"]["$hour"])
        #test_case_bs_mn_average_days["$day"]["nw"]["$count_hour"]    = deepcopy(test_case_bs_mn_average_sp["nw"]["$hour"])
    end
end



#########################################################################
results_one_topology_sp_forecasted = Dict{String,Any}()
results_one_topology_sp_measured   = Dict{String,Any}()
#results_one_topology_sp_average    = Dict{String,Any}()
for day in 1:n_days
    results_one_topology_sp_measured   = Dict{String,Any}()
    results_one_topology_sp_measured = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology_sp(test_case_bs_mn_measured_days["$day"],LPACCPowerModel,gurobi_bs; setting = s)
    #results_one_topology_sp_average["$day"] = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology(test_case_bs_mn_average,LPACCPowerModel,gurobi_bs; setting = s)
    json_results_one_topology_sp_measured = JSON.json(results_one_topology_sp_measured)
    open(joinpath(results_folder,case,"24_hours_BS_one_topology_measured_$(first_hour)_$(last_hour)_day_$(day).json"),"w") do f 
        write(f, json_results_one_topology_sp_measured) 
    end 
end


json_results_one_topology_sp_forecasted = JSON.json(results_one_topology_sp_forecasted)
open(joinpath(results_folder,case,"24_hours_BS_one_topology_forecasted_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_results_one_topology_sp_forecasted) 
end 

json_results_one_topology_sp_measured = JSON.json(results_one_topology_sp_measured)
open(joinpath(results_folder,case,"24_hours_BS_one_topology_measured_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_results_one_topology_sp_measured) 
end 

#json_results_one_topology_sp_average = JSON.json(results_one_topology_sp_average)
#open(joinpath(results_folder,case,"24_hours_BS_one_topology_average_$(first_hour)_$(last_hour).json"),"w") do f 
#    write(f, json_results_one_topology_sp_average) 
#end 

################################################


####################################################

test_case_bs_mn_forecasted_max_sw = deepcopy(test_case_bs_mn_forecasted_days)
test_case_bs_mn_measured_max_sw = deepcopy(test_case_bs_mn_measured_days)
#test_case_bs_mn_average_max_sw = deepcopy(test_case_bs_mn_average_days)

for day in 1:n_days
    test_case_bs_mn_forecasted_max_sw["$day"]["total_switching_actions"] = 1
    test_case_bs_mn_measured_max_sw["$day"]["total_switching_actions"] = 1
    #test_case_bs_mn_average_max_sw["$day"]["total_switching_actions"] = 1

    for (sw_id,sw) in test_case_bs_mn_forecasted_max_sw["$day"]["nw"]["1"]["switch"]
        sw["maximum_actions"] = 1
    end
    for (sw_id,sw) in test_case_bs_mn_measured_max_sw["$day"]["nw"]["1"]["switch"]
        sw["maximum_actions"] = 1
    end
    #for (sw_id,sw) in test_case_bs_mn_average_max_sw["$day"]["nw"]["1"]["switch"]
    #    sw["maximum_actions"] = 1
    #end
end

results_one_topology_sp_forecasted_one_max_sw = Dict{String,Any}()
results_one_topology_sp_measured_one_max_sw   = Dict{String,Any}()
#results_one_topology_sp_average_one_max_sw    = Dict{String,Any}()
for day in 1:n_days
    results_one_topology_sp_measured_one_max_sw   = Dict{String,Any}()
    results_one_topology_sp_measured_one_max_sw = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches(test_case_bs_mn_measured_max_sw["$day"],LPACCPowerModel,gurobi_bs; setting = s)
    #results_one_topology_sp_average["$day"] = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology(test_case_bs_mn_average,LPACCPowerModel,gurobi_bs; setting = s)
    json_results_one_topology_sp_measured = JSON.json(results_one_topology_sp_measured_one_max_sw)
    open(joinpath(results_folder,case,"One_maximum_actions_measured_$(first_hour)_$(last_hour)_day_$(day).json"),"w") do f 
        write(f, json_results_one_topology_sp_measured) 
    end 

    results_one_topology_sp_forecasted_one_max_sw   = Dict{String,Any}()
    results_one_topology_sp_forecasted_one_max_sw = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches(test_case_bs_mn_forecasted_max_sw["$day"],LPACCPowerModel,gurobi_bs; setting = s)
    #results_one_topology_sp_average["$day"] = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology(test_case_bs_mn_average,LPACCPowerModel,gurobi_bs; setting = s)
    json_results_one_topology_sp_forecasted = JSON.json(results_one_topology_sp_forecasted_one_max_sw)
    open(joinpath(results_folder,case,"One_maximum_actions_forecasted_$(first_hour)_$(last_hour)_day_$(day).json"),"w") do f 
        write(f, json_results_one_topology_sp_forecasted) 
    end 
end



function run_simulation_days(input_dict,result_dict,name_result_file)
    for day in 1:n_days
        result_dict["$day"] = Dict{String,Any}()
        result_dict["$day"] = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches(input_dict["$day"],LPACCPowerModel,gurobi_bs; setting = s)
    end
    json_result_dict = JSON.json(result_dict)
    open(joinpath(results_folder,case,"$(name_result_file)_$(first_hour)_$(last_hour).json"),"w") do f 
        write(f, json_result_dict) 
    end 
end
run_simulation_days(test_case_bs_mn_forecasted_max_sw,results_one_topology_sp_forecasted_one_max_sw,"One_maximum_actions_24_hours_forecasted")
run_simulation_days(test_case_bs_mn_measured_max_sw,results_one_topology_sp_measured_one_max_sw,"One_maximum_actions_24_hours_measured")
#run_simulation_days(test_case_bs_mn_average_max_sw,results_one_topology_sp_average_one_max_sw,"One_maximum_actions_24_hours_average")


#######

test_case_bs_mn_forecasted_two_max_sw = deepcopy(test_case_bs_mn_forecasted_days)
test_case_bs_mn_measured_two_max_sw = deepcopy(test_case_bs_mn_measured_days)

for day in 1:n_days
    test_case_bs_mn_forecasted_two_max_sw["$day"]["total_switching_actions"] = 2
    test_case_bs_mn_measured_two_max_sw["$day"]["total_switching_actions"] = 2

    for (sw_id,sw) in test_case_bs_mn_forecasted_two_max_sw["$day"]["nw"]["1"]["switch"]
        sw["maximum_actions"] = 2
    end
    for (sw_id,sw) in test_case_bs_mn_measured_two_max_sw["$day"]["nw"]["1"]["switch"]
        sw["maximum_actions"] = 2
    end
end

#results_one_topology_sp_forecasted_max_sw_2 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches(test_case_bs_mn_forecasted,LPACCPowerModel,gurobi_bs)
#results_one_topology_sp_measured_max_sw_2 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches(test_case_bs_mn_measured,LPACCPowerModel,gurobi_bs)


#results_one_topology_sp_average_one_max_sw    = Dict{String,Any}()
for day in 1:n_days
    results_one_topology_sp_forecasted_max_sw_2   = Dict{String,Any}()
    results_one_topology_sp_forecasted_max_sw_2 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches(test_case_bs_mn_forecasted_two_max_sw["$day"],LPACCPowerModel,gurobi_bs; setting = s)
    #results_one_topology_sp_average["$day"] = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology(test_case_bs_mn_average,LPACCPowerModel,gurobi_bs; setting = s)
    json_results_one_topology_sp_forecasted = JSON.json(results_one_topology_sp_forecasted_max_sw_2)
    open(joinpath(results_folder,case,"Two_maximum_actions_forecasted_$(first_hour)_$(last_hour)_day_$(day).json"),"w") do f 
        write(f, json_results_one_topology_sp_forecasted) 
    end 

    results_one_topology_sp_measured_max_sw_2    = Dict{String,Any}()
    results_one_topology_sp_measured_max_sw_2  = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches(test_case_bs_mn_measured_two_max_sw["$day"],LPACCPowerModel,gurobi_bs; setting = s)
    #results_one_topology_sp_average["$day"] = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology(test_case_bs_mn_average,LPACCPowerModel,gurobi_bs; setting = s)
    json_results_one_topology_sp_measured = JSON.json(results_one_topology_sp_measured_max_sw_2)
    open(joinpath(results_folder,case,"Two_maximum_actions_measured_$(first_hour)_$(last_hour)_day_$(day).json"),"w") do f 
        write(f, json_results_one_topology_sp_measured) 
    end 
end






json_results_two_topology_forecasted = JSON.json(results_one_topology_sp_forecasted_max_sw_2)
open(joinpath(results_folder,case,"Two_maximum_actions_24_hours_forecasted_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_results_two_topology_forecasted) 
end 

json_results_two_topology__measured = JSON.json(results_one_topology_sp_measured_max_sw_2)
open(joinpath(results_folder,case,"Two_maximum_actions_24_hours_measured_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_results_two_topology__measured) 
end 


