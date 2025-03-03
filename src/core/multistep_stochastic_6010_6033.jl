using PowerModels; const _PM = PowerModels
using PowerModelsACDC; const _PMACDC = PowerModelsACDC
import PowerModelsTopologicalActionsII; const _PMTP = PowerModelsTopologicalActionsII
using FlexPlan; const _FP = FlexPlan
using Gurobi
using Ipopt
using JSON
using Plots
import StochasticPowerModelsTopologicalActions; const _SPMTA = StochasticPowerModelsTopologicalActions
using JuMP
using Juniper
using HSL_jll
using MathOptInterface

mip_gap = 1e-3
gurobi = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "time_limit" => 600,"MIPGap" => mip_gap)#r, "ScaleFlag"=>2, "NumericFocus"=>2) 
ipopt = JuMP.optimizer_with_attributes(Ipopt.Optimizer, "tol" => 1e-6, "print_level" => 0,"linear_solver" => "ma97")
juniper = JuMP.optimizer_with_attributes(Juniper.Optimizer, "nl_solver" => ipopt, "mip_solver" => gurobi, "time_limit" => 36000)

#########################################################################################
## Processing input data
input_folder = "/Users/giacomobastianel/.julia/dev/DIRECTIONS_WP4.jl/src/Step_1"

#########################################################################################
# Uploading pdf samples for offshore wind
year_wind = "2023"
folder_data = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Elia_data"

Gaussian_samples_file = joinpath(folder_data,"Gaussian_samples_8_Offshore_wind_$(year_wind)_Elia.json")
Gaussian_samples = JSON.parsefile(Gaussian_samples_file)

Elia_OFW_file = joinpath(folder_data,"Offshore_wind_$(year_wind)_Elia.json")
Elia_OFW = JSON.parsefile(Elia_OFW_file)

results_folder = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Deliverable_4_1_DIRECTIONS/Results/Collab_Line"
wind_CF_Line = "Wind_capacity_factors_DE2050_1995"

file_cf_Line_name = joinpath(results_folder,"$wind_CF_Line.json")
cf_Line = JSON.parsefile(file_cf_Line_name)

#########################################################################################

n_hours = 2
start_hour_simulation = 6010
end_hour_simulation = 6012 #6033
hours = collect(start_hour_simulation:end_hour_simulation)
n_scenarios = 8

#########################################################################################
hours_wind = []
for l in cf_Line
    values_l = []
    for i in eachindex(Elia_OFW)
        if Elia_OFW[i]["minute"] == "00" && (Elia_OFW[i]["dayahead11hforecast"]/Elia_OFW[i]["monitoredcapacity"] < (l + 0.001) && Elia_OFW[i]["dayahead11hforecast"]/Elia_OFW[i]["monitoredcapacity"] >  (l - 0.001))
            push!(values_l,i)
        end
    end
    push!(hours_wind,values_l[1])
end

Wind_data = Dict{String,Any}()
for i in 1:length(hours_wind)
    h = start_hour_simulation + i - 1
    hw = hours_wind[i]   
    Wind_data["$h"] = Dict{String,Any}()
    Wind_data["$h"]["most_recent_forecast_pu"] = Elia_OFW[hw]["mostrecentforecast"]/Elia_OFW[hw]["monitoredcapacity"]
    Wind_data["$h"]["measured_pu"] = Elia_OFW[hw]["measured"]/Elia_OFW[hw]["monitoredcapacity"]
    Wind_data["$h"]["P50_11hforecast_pu"] = Elia_OFW[hw]["dayahead11hforecast"]/Elia_OFW[hw]["monitoredcapacity"]
    Wind_data["$h"]["samples_pu"] = Gaussian_samples["$hw"]["samples_pu"]
    Wind_data["$h"]["pdf_normalized"] = Gaussian_samples["$hw"]["pdf_normalized"]
    Wind_data["$h"]["Elia_timestep"] = hours_wind[i]
end

#########################################################################################
## Processing input data
input_folder = "/Users/giacomobastianel/.julia/dev/DIRECTIONS_WP4.jl/src/Step_1"

# Belgium grid without energy island
BE_grid_2024_file = joinpath(dirname(dirname(input_folder)),"test_cases/DIRECTIONS_test_case_Step_1_no_OWF_UK_corrected_LPAC.json")
BE_grid_6010_6033 = _PM.parse_file(BE_grid_2024_file)
#BE_grid_6010_6033["gen"]["1292"]["cost"][1] = 15.0
#for (g_id,g) in BE_grid_6010_6033["gen"]
#    if g["type"] != "Offshore Wind" #&& g["type"] != "Solar PV" && g["type"] != "Onshore Wind"
#        println(g_id,"  ",g["type"])
#        g["cost"][1] = g["cost"][1]*4.0
#    end
#end


BE_grid_bs_6010_6033 = deepcopy(BE_grid_6010_6033)
BE_grid_opf_6010_6033 = deepcopy(BE_grid_6010_6033)

splitted_bus_ac = [26,261]
name_splitted_buses = "26_261"


BE_grid_bs_6010_6033,  switches_couples_ac_6010_6033,  extremes_ZILs_ac_6010_6033  = _PMTP.AC_busbar_split_more_buses(BE_grid_bs_6010_6033,splitted_bus_ac)
BE_grid_bs_6010_6033["switch"]["1"]["maximum_actions"] = 12
BE_grid_bs_6010_6033["switch"]["2"]["maximum_actions"] = 12


s = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true)
s_dual = Dict("output" => Dict("branch_flows" => true,"duals" => true), "conv_losses_mp" => true)

#########################################################################################
# Add dimensions for stochastic part
_SPMTA.add_dimensions!(BE_grid_bs_6010_6033,n_scenarios,n_hours)
_SPMTA.add_dimensions!(BE_grid_opf_6010_6033,n_scenarios,n_hours)
BE_grid_bs_6010_6033["limit_actions"] = 4

#########################################################################################
# Calling scenario and climate year
results_folder = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Deliverable_4_1_DIRECTIONS/Results/Collab_Line"
scenario = "DE"
year = "2050"
climate_year = "1995"
zones = unique([g["zone"] for (g_id,g) in BE_grid_bs_6010_6033["gen"]])

#########################################################################################
# Uploading files
RES_time_series_file = joinpath(results_folder,"RES_time_series_$(scenario)$(year)_$(climate_year).json")
open(RES_time_series_file, "r") do f
    global RES_time_series = JSON.parse(read(f, String))
end

Load_time_series_file = joinpath(results_folder,"Load_time_series_$(scenario)$(year)_$(climate_year).json")
open(Load_time_series_file, "r") do f
    global Load_time_series = JSON.parse(read(f, String))
end
#########################################################################################
# Time series
res_time_series_hour = Dict{String,Any}()
_SPMTA.create_RES_time_series(BE_grid_bs_6010_6033,res_time_series_hour,Wind_data,n_scenarios,start_hour_simulation,end_hour_simulation)

gen_time_series_hour = Dict{String,Any}()
_SPMTA.create_gen_time_series_tyndp_scenarios(BE_grid_bs_6010_6033,gen_time_series_hour, Wind_data, RES_time_series,start_hour_simulation,end_hour_simulation,n_scenarios)

load_time_series_hour = Dict{String,Any}()
_SPMTA.add_load_time_series_tyndp_scenario(BE_grid_bs_6010_6033, load_time_series_hour, Load_time_series, start_hour_simulation, end_hour_simulation, n_scenarios)


time_series_hour = Dict{String,Any}()
_SPMTA.generate_input_dict_stochastic_optimization(time_series_hour,gen_time_series_hour,load_time_series_hour,start_hour_simulation,end_hour_simulation,Wind_data)
#########################################################################################

_SPMTA.add_hour_scenario_data(BE_grid_bs_6010_6033, n_hours, n_scenarios)
_SPMTA.add_hour_scenario_data(BE_grid_opf_6010_6033, n_hours, n_scenarios)

BE_grid_bs_mn_6010_6033 = _SPMTA.make_multinetwork_time_series_tyndp_scenarios(BE_grid_bs_6010_6033,n_hours,n_scenarios,start_hour_simulation,end_hour_simulation,time_series_hour,zones)
BE_grid_opf_mn_6010_6033 = _SPMTA.make_multinetwork_time_series_tyndp_scenarios(BE_grid_opf_6010_6033,n_hours,n_scenarios,start_hour_simulation,end_hour_simulation,time_series_hour,zones)


result_opf = _SPMTA.run_stochastic_acdc_opf(BE_grid_opf_mn_6010_6033,LPACCPowerModel,gurobi; setting = s)
result_ac_opf = _SPMTA.run_stochastic_acdc_opf(BE_grid_opf_mn_6010_6033,ACPPowerModel,ipopt; setting = s)

########################################################################################################
gurobi = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "time_limit" => 2400,"MIPGap" => mip_gap)#r, "ScaleFlag"=>2, "NumericFocus"=>2) 

result_ZIL = _SPMTA.run_stochastic_acdcsw_AC_ZIL(BE_grid_bs_mn_6010_6033,LPACCPowerModel,gurobi; setting = s)
BE_grid_bs_mn_6010_6033["limit_actions"] = 2
result_ZIL_la = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limited_actions(BE_grid_bs_mn_6010_6033,LPACCPowerModel,gurobi; setting = s)

println("The reduction in generation costs with busbar splitting is $(((result_opf["objective"] - result_ZIL["objective"]   )/result_opf["objective"])*100)%, with a MIP gap of $(mip_gap*100)%")
println("The reduction in generation costs with busbar splitting is $(((result_opf["objective"] - result_ZIL_la["objective"])/result_opf["objective"])*100)%, with a MIP gap of $(mip_gap*100)%")



result_ZIL["solution"]["nw"]["1"]["switch"]["1"]["status"]
result_ZIL["solution"]["nw"]["9"]["switch"]["2"]["status"]
result_ZIL["solution"]["nw"]["1"]["switch"]["1"]["status"]
result_ZIL["solution"]["nw"]["9"]["switch"]["2"]["status"]


result_ZIL_la["solution"]["nw"]["1"]["switch"]["1"]["status"]
result_ZIL_la["solution"]["nw"]["9"]["switch"]["2"]["status"]
result_ZIL_la["solution"]["nw"]["1"]["switch"]["1"]["status"]
result_ZIL_la["solution"]["nw"]["9"]["switch"]["2"]["status"]


########################################################################################################
dict_nw = Dict{String,Any}()
dict_hour = Dict{String,Any}()
dict_nw_opf = Dict{String,Any}()
dict_hour_opf = Dict{String,Any}()
_SPMTA.compute_gen_capacity_stochastic_multistep(BE_grid_bs_mn_6010_6033,result_ZIL,start_hour_simulation,end_hour_simulation,dict_nw,dict_hour,n_hours,n_scenarios)
_SPMTA.compute_gen_capacity_stochastic_multistep(BE_grid_bs_mn_6010_6033,result_opf,start_hour_simulation,end_hour_simulation,dict_nw_opf,dict_hour_opf,n_hours,n_scenarios)

dict_hour_opf["1"]
dict_hour["1"]

dict_nw_zone = Dict{String,Any}()
dict_hour_zone = Dict{String,Any}()
dict_nw_zone_opf = Dict{String,Any}()
dict_hour_zone_opf = Dict{String,Any}()
_SPMTA.compute_gen_capacity_stochastic_zone(BE_grid_bs_mn_6010_6033,result_ZIL,start_hour_simulation,end_hour_simulation,zones,dict_nw_zone,dict_hour_zone,n_hours,n_scenarios)
_SPMTA.compute_gen_capacity_stochastic_zone(BE_grid_bs_mn_6010_6033,result_opf,start_hour_simulation,end_hour_simulation,zones,dict_nw_zone_opf,dict_hour_zone_opf,n_hours,n_scenarios)


ofw_24 = [dict_hour["$i"]["Offshore Wind"] for i in 1:n_hours]
ofw_24_opf = [dict_hour_opf["$i"]["Offshore Wind"] for i in 1:n_hours]

ofw_24_BE = [dict_hour_zone["$i"]["BE00"]["Offshore Wind"] for i in 1:n_hours]
ofw_24_BE_opf = [dict_hour_zone_opf["$i"]["BE00"]["Offshore Wind"] for i in 1:n_hours]

ofw_24_UK = [dict_hour_zone["$i"]["UK00"]["Offshore Wind"] for i in 1:n_hours]
ofw_24_UK_opf = [dict_hour_zone_opf["$i"]["UK00"]["Offshore Wind"] for i in 1:n_hours]


#=
function prepare_starting_value_dict_nw(result,grid,start_hour_simulation,end_hour_simulation,n_scenarios)
    count_ = 1
    for hour in start_hour_simulation:end_hour_simulation
        count_ += 1
        n = (count_ - 1)*n_scenarios 
        for (b_id,b) in grid["nw"]["$n"]["bus"]
            if haskey(result["solution"]["nw"]["$n"]["bus"],b_id)
                if abs(result["solution"]["nw"]["$n"]["bus"]["$b_id"]["va"]) < 10^(-4)
                    b["va_starting_value"] = 0.0
                else
                    b["va_starting_value"] = result["solution"]["nw"]["$n"]["bus"]["$b_id"]["va"]
                end
                if abs(result["solution"]["nw"]["$n"]["bus"]["$b_id"]["vm"]) < 10^(-4)
                    b["vm_starting_value"] = 0.0
                else
                    b["vm_starting_value"] = result["solution"]["nw"]["$n"]["bus"]["$b_id"]["vm"]
                end
            else
                b["va_starting_value"] = 0.0
                b["vm_starting_value"] = 1.0
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
=#
function prepare_starting_value_dict_nw(result,grid,start_hour_simulation,end_hour_simulation,n_scenarios)
    count_ = 0
    for hour in start_hour_simulation:end_hour_simulation
        count_ += 1
        for scenario_idx in 1:n_scenarios
            n = (count_ - 1)*n_scenarios + scenario_idx
            for (b_id,b) in grid["nw"]["$n"]["bus"]
                if haskey(result["solution"]["nw"]["$n"]["bus"],b_id)
                    if abs(result["solution"]["nw"]["$n"]["bus"]["$b_id"]["va"]) < 10^(-4)
                        b["va_starting_value"] = 0.0
                    else
                        b["va_starting_value"] = result["solution"]["nw"]["$n"]["bus"]["$b_id"]["va"]
                    end
                    if abs(result["solution"]["nw"]["$n"]["bus"]["$b_id"]["vm"]) < 10^(-4)
                        b["vm_starting_value"] = 0.0
                    else
                        b["vm_starting_value"] = result["solution"]["nw"]["$n"]["bus"]["$b_id"]["vm"]
                    end
                else
                    b["va_starting_value"] = 0.0
                    b["vm_starting_value"] = 1.0
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

function prepare_starting_value_dict_lpac_nw(result,grid,start_hour_simulation,end_hour_simulation,n_scenarios)
    count_ = 0
    for hour in start_hour_simulation:end_hour_simulation
        count_ += 1
        for scenario_idx in 1:n_scenarios
            n = (count_ - 1)*n_scenarios + scenario_idx
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
                    b["phi_starting_value"] = 0.1
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
            #=
            for (b_id,b) in grid["nw"]["$n"]["branch"]
                if abs(result["solution"]["nw"]["$n"]["branch"]["$b_id"]["pf"]) < 10^(-5)
                    b["pf_starting_value"] = 0.0
                else
                    b["pf_starting_value"] = result["solution"]["nw"]["$n"]["branch"]["$b_id"]["pf"]
                end
                if abs(result["solution"]["nw"]["$n"]["branch"]["$b_id"]["qf"]) < 10^(-5)
                    b["qf_starting_value"] = 0.0
                else
                    b["qf_starting_value"] = result["solution"]["nw"]["$n"]["branch"]["$b_id"]["qf"]
                end
            end
            for (b_id,b) in grid["nw"]["$n"]["branchdc"]
                if abs(result["solution"]["nw"]["$n"]["branchdc"]["$b_id"]["pf"]) < 10^(-5)
                    b["pf_starting_value"] = 0.0
                else
                    b["pf_starting_value"] = result["solution"]["nw"]["$n"]["branchdc"]["$b_id"]["pf"]
                end
                if abs(result["solution"]["nw"]["$n"]["branchdc"]["$b_id"]["qf"]) < 10^(-5)
                    b["qf_starting_value"] = 0.0
                else
                    b["qf_starting_value"] = result["solution"]["nw"]["$n"]["branchdc"]["$b_id"]["qf"]
                end
            end
            =#
        end
    end
end

#=
function prepare_AC_grid_feasibility_check_stochastic_multistep(result_dict, input_dict, input_ac_check, switch_couples, extremes_dict, input_base, n_hours, n_scenarios)    
    orig_buses = maximum(parse.(Int, keys(input_base["bus"]))) + length(extremes_dict)
    for t in 1:(n_hours*n_scenarios)
        println("t is $(t)")
        for (sw_id,sw) in input_dict["nw"]["$t"]["switch"]
            if haskey(sw,"auxiliary") # Make sure ZILs are not included 
                aux =  deepcopy(input_ac_check["nw"]["$t"]["switch"][sw_id]["auxiliary"])
                orig = deepcopy(input_ac_check["nw"]["$t"]["switch"][sw_id]["original"])  
                for zil in eachindex(extremes_dict)
                    if haskey(input_ac_check["nw"]["$t"]["switch_couples"],sw_id)
                        if sw["bus_split"] == extremes_dict[zil][1] && result_dict["solution"]["nw"]["$t"]["switch"]["$(switch_couples[sw_id]["switch_split"])"]["status"] == 1.0  # Making sure to reconnect everything to the original if the ZIL is connected
                            if result_dict["solution"]["nw"]["$t"]["switch"][sw_id]["status"] >= 0.9
                                if aux == "gen"
                                    input_ac_check["nw"]["$t"]["gen"]["$(orig)"]["gen_bus"] = deepcopy(extremes_dict[zil][1])
                                elseif aux == "load"
                                    input_ac_check["nw"]["$t"]["load"]["$(orig)"]["load_bus"] = deepcopy(extremes_dict[zil][1])
                                elseif aux == "branch"  
                                    if input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] > orig_buses && switch_couples[sw_id]["bus_split"] == parse(Int64,zil)
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] = deepcopy(switch_couples[sw_id]["bus_split"])
                                    elseif input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] > orig_buses && switch_couples[sw_id]["bus_split"] == parse(Int64,zil)
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] = deepcopy(switch_couples[sw_id]["bus_split"])
                                    end
                                end
                                delete!(input_ac_check["nw"]["$t"]["switch"],sw_id)
                            else
                                delete!(input_ac_check["nw"]["$t"]["switch"],sw_id)
                            end
                        elseif sw["bus_split"] == extremes_dict[zil][1] && result_dict["solution"]["nw"]["$t"]["switch"]["$(switch_couples[sw_id]["switch_split"])"]["status"] == 0.0 # Reconnect everything to the split busbar
                            if result_dict["solution"]["nw"]["$t"]["switch"][sw_id]["status"] >= 0.9
                                if aux == "gen"
                                    input_ac_check["nw"]["$t"]["gen"]["$(orig)"]["gen_bus"] = deepcopy(sw["t_bus"])
                                elseif aux == "load"
                                    input_ac_check["nw"]["$t"]["load"]["$(orig)"]["load_bus"] = deepcopy(sw["t_bus"])
                                elseif aux == "branch" 
                                    if input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] > orig_buses && switch_couples[sw_id]["bus_split"] == parse(Int64,zil) 
                                            input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] = deepcopy(sw["t_bus"])
                                    elseif input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] > orig_buses && switch_couples[sw_id]["bus_split"] == parse(Int64,zil)
                                        if !haskey(input_ac_check["nw"]["$t"]["branch"]["$(orig)"],"checked")
                                            input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] = deepcopy(sw["t_bus"])
                                        end
                                    end
                                end
                                delete!(input_ac_check["nw"]["$t"]["switch"],sw_id)
                            else
                                delete!(input_ac_check["nw"]["$t"]["switch"],sw_id)
                            end
                        end
                    end
                end
            end
        end
    end
    return input_ac_check
end
=#
function prepare_AC_feasibility_check_stochastic_multistep(result_dict, input_dict, input_ac_check, switch_couples, extremes_dict, input_base, n_hours, n_scenarios)
    orig_buses = length(input_base["bus"]) # original bus length
    for t in 1:(n_hours*n_scenarios)
        println("t is $(t)")
        for (sw_id,sw) in input_dict["nw"]["$t"]["switch"]
            if !haskey(sw,"auxiliary")
                println("SWITCH $sw_id, BUS $(sw["t_bus"])")
                if result_dict["solution"]["nw"]["$t"]["switch"][sw_id]["status"] >= 0.9
                    println("Switch $sw_id is closed, Connecting everything back, no busbar splitting on bus $(sw["bus_split"])")
                    #delete!(input_ac_check["bus"],"$(input_ac_check["switch"][sw_id]["t_bus"])")
                    for l in keys(switch_couples)
                        if switch_couples[l]["bus_split"] == sw["bus_split"]
                            println("SWITCH COUPLE IS $l")
                            println("Starting from switch $(switch_couples[l]["f_sw"]), with t_bus $(input_ac_check["switch"]["$(switch_couples[l]["f_sw"])"]["t_bus"])")
                            println("Then switch $(switch_couples[l]["t_sw"]), with t_bus $(input_ac_check["switch"]["$(switch_couples[l]["t_sw"])"]["t_bus"])")
                            if input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["f_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                println("WE GO WITH SWITCH $(switch_couples[l]["f_sw"])")
                                aux =  deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["f_sw"])"]["auxiliary"])
                                orig = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["f_sw"])"]["original"])
                                if aux == "gen"
                                    input_ac_check["nw"]["$t"]["gen"]["$(orig)"]["gen_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "load"
                                    input_ac_check["nw"]["$t"]["load"]["$(orig)"]["load_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "convdc"
                                    input_ac_check["nw"]["$t"]["convdc"]["$(orig)"]["busac_i"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "branch"                
                                    if input_dict["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                    elseif input_dict["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                    end
                                end
                            elseif input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["t_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                println("WE GO WITH SWITCH $(switch_couples[l]["t_sw"])")
                                println("----------------------------")
                                aux =  deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["t_sw"])"]["auxiliary"])
                                orig = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["t_sw"])"]["original"])
                                if aux == "gen"
                                    input_ac_check["nw"]["$t"]["gen"]["$(orig)"]["gen_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "load"
                                    input_ac_check["nw"]["$t"]["load"]["$(orig)"]["load_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "convdc"
                                    input_ac_check["nw"]["$t"]["convdc"]["$(orig)"]["busac_i"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "branch"                
                                    if input_dict["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                    elseif input_dict["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] = deepcopy(switch_couples[l]["bus_split"])
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
                            println("Starting from switch $(switch_couples[l]["f_sw"]), with t_bus $(input_ac_check["nw"]["$t"]["switch"]["$(switch_couples[l]["f_sw"])"]["t_bus"])")
                            println("Then switch $(switch_couples[l]["t_sw"]), with t_bus $(input_ac_check["nw"]["$t"]["switch"]["$(switch_couples[l]["t_sw"])"]["t_bus"])")
                            if result_dict["solution"]["nw"]["$t"]["switch"]["$(switch_couples["$l"]["switch_split"])"]["status"] >= 0.9
                                aux =  deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["auxiliary"])
                                orig = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["original"])
                                if aux == "gen"
                                    input_ac_check["nw"]["$t"]["gen"]["$(orig)"]["gen_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "load"
                                    input_ac_check["nw"]["$t"]["load"]["$(orig)"]["load_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "convdc"
                                    input_ac_check["nw"]["$t"]["convdc"]["$(orig)"]["busac_i"] = deepcopy(switch_couples[l]["bus_split"])
                                elseif aux == "branch"                
                                    if input_dict["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                    elseif input_dict["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                    end
                                end
                            elseif result_dict["solution"]["nw"]["$t"]["switch"]["$(switch_couples["$l"]["switch_split"])"]["status"] <= 0.1
                                switch_t = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]) 
                                aux_t = switch_t["auxiliary"]
                                orig_t = switch_t["original"]
                                print([l,aux_t,orig_t],"\n")
                                if result_dict["solution"]["nw"]["$t"]["switch"]["$(switch_t["index"])"]["status"] <= 0.1
                                    delete!(input_ac_check["nw"]["$t"]["switch"],"$(switch_t["index"])")
                                elseif result_dict["solution"]["nw"]["$t"]["switch"]["$(switch_t["index"])"]["status"] >= 0.9
                                    if aux_t == "gen"
                                        input_ac_check["nw"]["$t"]["gen"]["$(orig_t)"]["gen_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["gen"]["$(orig_t)"]["gen_bus"]],"\n")
                                    elseif aux_t == "load"
                                        input_ac_check["nw"]["$t"]["load"]["$(orig_t)"]["load_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["load"]["$(orig_t)"]["load_bus"]],"\n")
                                    elseif aux_t == "convdc"
                                        input_ac_check["nw"]["$t"]["convdc"]["$(orig_t)"]["busac_i"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["convdc"]["$(orig_t)"]["busac_i"]],"\n")
                                    elseif aux_t == "branch" 
                                        if input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                            input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                            print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"]],"\n")
                                        elseif input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                            input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                            print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"]],"\n")
                                        end
                                    end
                                end
                            
                                switch_f = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]) 
                                aux_f = switch_f["auxiliary"]
                                orig_f = switch_f["original"]
                                print([l,aux_f,orig_f],"\n")
                                if result_dict["solution"]["nw"]["$t"]["switch"]["$(switch_f["index"])"]["status"] <= 0.1
                                    delete!(input_ac_check["nw"]["$t"]["switch"],"$(switch_t["index"])")
                                else
                                    if aux_f == "gen"
                                        input_ac_check["nw"]["$t"]["gen"]["$(orig_f)"]["gen_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["gen"]["$(orig_t)"]["gen_bus"]],"\n")
                                    elseif aux_f == "load"
                                        input_ac_check["nw"]["$t"]["load"]["$(orig_f)"]["load_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["load"]["$(orig_t)"]["load_bus"]],"\n")
                                    elseif aux_f == "convdc"
                                        input_ac_check["nw"]["$t"]["convdc"]["$(orig_f)"]["busac_i"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["convdc"]["$(orig_t)"]["busac_i"]],"\n")
                                    elseif aux_f == "branch"
                                        if input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                            input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["f_bus"] = deepcopy(input_ac_check["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                            print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"]],"\n")
                                        elseif input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                            input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"] = deepcopy(input_ac_check["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                            print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"]],"\n")
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end


feas_check_grid = deepcopy(BE_grid_bs_mn_6010_6033)
feas_check_grid_auxiliary = deepcopy(BE_grid_bs_mn_6010_6033)

prepare_AC_feasibility_check_stochastic_multistep(result_ZIL,feas_check_grid,feas_check_grid_auxiliary,switches_couples_ac_6010_6033, extremes_ZILs_ac_6010_6033,BE_grid_6010_6033,n_hours,n_scenarios)
result_opf_check = _SPMTA.run_stochastic_acdc_opf(feas_check_grid_auxiliary,LPACCPowerModel,gurobi; setting = s)



BE_grid_bs_mn_6010_6033_sp = deepcopy(BE_grid_bs_mn_6010_6033)
prepare_starting_value_dict_lpac_nw(result_opf,BE_grid_bs_mn_6010_6033_sp,start_hour_simulation,end_hour_simulation,n_scenarios)
result_ZIL_sp = _SPMTA.run_stochastic_acdcsw_AC_ZIL_sp(BE_grid_bs_mn_6010_6033_sp,LPACCPowerModel,gurobi; setting = s)
BE_grid_bs_mn_6010_6033_sp["limit_actions"] = 2
result_ZIL_sp_la = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limited_actions_sp(BE_grid_bs_mn_6010_6033_sp,LPACCPowerModel,gurobi; setting = s)



for (g_id,g) in BE_grid_6010_6033["gen"]
    if g["type"] == "Onshore Wind"
        println(g_id," ",g["zone"])
    end
end
BE_grid_6010_6033["gen"]["1292"]
time_series_hour["gen"]["1292"]["6010"]

BE_grid_bs_mn_6010_6033["nw"]["1"]["gen"]["1292"]



sw_1 = [result_ZIL["solution"]["nw"]["$n"]["switch"]["1"]["status"] for n in 1:n_hours*n_scenarios]
sw_1_la = [result_ZIL_la["solution"]["nw"]["$n"]["switch"]["1"]["status"] for n in 1:n_hours*n_scenarios]
sw_2 = [result_ZIL["solution"]["nw"]["$n"]["switch"]["2"]["status"] for n in 1:n_hours*n_scenarios]
sw_2_la = [result_ZIL_la["solution"]["nw"]["$n"]["switch"]["2"]["status"] for n in 1:n_hours*n_scenarios]

plot(sw_1,grid = :none, yticks = (0:1:1), xticks = :none,  label = "Busbar splitting",legend = :outertopright, title = "Zero Impedance Line 1")
plot!(sw_1_la, label = "Limited actions")

plot(sw_2,grid = :none, yticks = (0:1:1), xticks = :none,  label = "Busbar splitting",legend = :outertopright, title = "Zero Impedance Line 2")
plot!(sw_2_la, label = "Limited actions")



dict_hour_opf["1"]
dict_hour_zone_opf["1"]["BE00"]
dict_hour_zone_opf["1"]["UK00"]