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

mip_gap = 1e-4
gurobi = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 300,"MIPGap" => mip_gap)#,"BarQCPConvTol"=>1e-4,"QCPDual" => 1)#r, "ScaleFlag"=>2, "NumericFocus"=>2) 
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

n_hours = 24
start_hour_simulation = 6010
end_hour_simulation = 6033
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
limit_actions = 12
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
function run_stochastic_acdcsw_AC_ZIL_hourly(grid, model, optimizer, n_hours, n_scenarios,result; setting = s)
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

result_hourly_bs = Dict{String,Any}()
@time run_stochastic_acdcsw_AC_ZIL_hourly(BE_grid_bs_mn_6010_6033,LPACCPowerModel,gurobi,n_hours,n_scenarios,result_hourly_bs; setting = s)
bs_total_costs = sum([result_hourly_bs["$i"]["objective"] for i in 1:n_hours])
term_status = [result_hourly_bs["$i"]["primal_status"] for i in 1:n_hours]


result_ZIL_short = _SPMTA.run_stochastic_acdcsw_AC_ZIL(BE_grid_bs_mn_6010_6033,LPACCPowerModel,gurobi; setting = s)
BE_grid_bs_mn_6010_6033["limit_actions"] = 26
result_ZIL_la_short = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limited_actions(BE_grid_bs_mn_6010_6033,LPACCPowerModel,gurobi; setting = s)

println("The reduction in generation costs with busbar splitting is $(((result_opf["objective"] - result_ZIL["objective"]   )/result_opf["objective"])*100)%, with a MIP gap of $(mip_gap*100)%")
println("The reduction in generation costs with busbar splitting is $(((result_opf["objective"] - result_ZIL_la["objective"])/result_opf["objective"])*100)%, with a MIP gap of $(mip_gap*100)%")


#=
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
=#

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
    orig_buses = maximum(parse.(Int, keys(input_base["bus"])))
    println("Number of original buses is $orig_buses")
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
                            #println("Starting from switch $(switch_couples[l]["f_sw"]), with t_bus $(input_ac_check["nw"]["$t"]["switch"]["$(switch_couples[l]["f_sw"])"]["t_bus"])")
                            #println("Then switch $(switch_couples[l]["t_sw"]), with t_bus $(input_ac_check["nw"]["$t"]["switch"]["$(switch_couples[l]["t_sw"])"]["t_bus"])")
                            if input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["f_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                println("WE GO WITH SWITCH $(switch_couples[l]["f_sw"])")
                                aux =  deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["f_sw"])"]["auxiliary"])
                                orig = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["f_sw"])"]["original"])
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
                                    if input_dict["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"])
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["f_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                    elseif input_dict["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"])
                                        input_ac_check["nw"]["$t"]["branch"]["$(orig)"]["t_bus"] = deepcopy(switch_couples[l]["bus_split"])
                                    end
                                end
                            elseif input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["t_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                                println("WE GO WITH SWITCH $(switch_couples[l]["t_sw"])")
                                println("----------------------------")
                                aux =  deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["t_sw"])"]["auxiliary"])
                                orig = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples[l]["t_sw"])"]["original"])
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
                                switch_t = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]) 
                                aux_t = switch_t["auxiliary"]
                                orig_t = switch_t["original"]
                                print([l,aux_t,orig_t],"\n")
                                if result_dict["solution"]["nw"]["$t"]["switch"]["$(switch_t["index"])"]["status"] <= 0.1
                                    delete!(input_ac_check["nw"]["$t"]["switch"],"$(switch_t["index"])")
                                elseif result_dict["solution"]["nw"]["$t"]["switch"]["$(switch_t["index"])"]["status"] >= 0.9
                                    if aux_t == "gen"
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["gen"]["$(orig_t)"]["gen_bus"])
                                        input_ac_check["nw"]["$t"]["gen"]["$(orig_t)"]["gen_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["gen"]["$(orig_t)"]["gen_bus"]],"\n")
                                    elseif aux_t == "load"
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["load"]["$(orig_t)"]["load_bus"])
                                        input_ac_check["nw"]["$t"]["load"]["$(orig_t)"]["load_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["load"]["$(orig_t)"]["load_bus"]],"\n")
                                    elseif aux_t == "convdc"
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["convdc"]["$(orig_t)"]["busac_i"])
                                        input_ac_check["nw"]["$t"]["convdc"]["$(orig_t)"]["busac_i"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["convdc"]["$(orig_t)"]["busac_i"]],"\n")
                                    elseif aux_t == "branch" 
                                        if input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                            delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"])
                                            input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_t["index"])"]["t_bus"])
                                            print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"]],"\n")
                                        elseif input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                            delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["t_bus"])
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
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["gen"]["$(orig_f)"]["gen_bus"])
                                        input_ac_check["nw"]["$t"]["gen"]["$(orig_f)"]["gen_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["gen"]["$(orig_f)"]["gen_bus"]],"\n")
                                    elseif aux_f == "load"
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["load"]["$(orig_f)"]["load_bus"])
                                        input_ac_check["nw"]["$t"]["load"]["$(orig_f)"]["load_bus"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["load"]["$(orig_f)"]["load_bus"]],"\n")
                                    elseif aux_f == "convdc"
                                        delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["convdc"]["$(orig_f)"]["busac_i"])
                                        input_ac_check["nw"]["$t"]["convdc"]["$(orig_f)"]["busac_i"] = deepcopy(input_dict["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                        print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["convdc"]["$(orig_f)"]["busac_i"]],"\n")
                                    elseif aux_f == "branch"
                                        if input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["f_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                            delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["f_bus"])
                                            input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["f_bus"] = deepcopy(input_ac_check["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                            print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["branch"]["$(orig_t)"]["f_bus"]],"\n")
                                        elseif input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"] > orig_buses && input_dict["nw"]["$t"]["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                            delete!(input_ac_check["nw"]["$t"]["bus"],input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"])
                                            input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"] = deepcopy(input_ac_check["nw"]["$t"]["switch"]["$(switch_f["index"])"]["t_bus"])
                                            print([l,aux_t,orig_t,input_ac_check["nw"]["$t"]["branch"]["$(orig_f)"]["t_bus"]],"\n")
                                        end
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

feas_check_grid = deepcopy(BE_grid_bs_mn_6010_6033)
feas_check_grid_auxiliary = deepcopy(BE_grid_bs_mn_6010_6033)
feas_check_grid_la = deepcopy(BE_grid_bs_mn_6010_6033)
feas_check_grid_auxiliary_la = deepcopy(BE_grid_bs_mn_6010_6033)

prepare_AC_feasibility_check_stochastic_multistep(result_ZIL,feas_check_grid,feas_check_grid_auxiliary,switches_couples_ac_6010_6033, extremes_ZILs_ac_6010_6033,BE_grid_6010_6033,n_hours,n_scenarios)
result_opf_check = _SPMTA.run_stochastic_acdc_opf(feas_check_grid_auxiliary,LPACCPowerModel,gurobi; setting = s)

prepare_AC_feasibility_check_stochastic_multistep(result_ZIL_la,feas_check_grid_la,feas_check_grid_auxiliary_la,switches_couples_ac_6010_6033, extremes_ZILs_ac_6010_6033,BE_grid_6010_6033,n_hours,n_scenarios)
result_opf_check_la = _SPMTA.run_stochastic_acdc_opf(feas_check_grid_auxiliary_la,LPACCPowerModel,gurobi; setting = s)

BE_grid_bs_mn_6010_6033_sp = deepcopy(BE_grid_bs_mn_6010_6033)
BE_grid_bs_mn_6010_6033_ac_sp = deepcopy(BE_grid_bs_mn_6010_6033)
prepare_starting_value_dict_nw(result_ac_opf,BE_grid_bs_mn_6010_6033_ac_sp,start_hour_simulation,end_hour_simulation,n_scenarios)
prepare_starting_value_dict_lpac_nw(result_opf,BE_grid_bs_mn_6010_6033_sp,start_hour_simulation,end_hour_simulation,n_scenarios)
result_ZIL_sp_short = _SPMTA.run_stochastic_acdcsw_AC_ZIL_sp(BE_grid_bs_mn_6010_6033_sp,LPACCPowerModel,gurobi; setting = s)
BE_grid_bs_mn_6010_6033_sp["limit_actions"] = 26
result_ZIL_sp_la_short = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limited_actions_sp(BE_grid_bs_mn_6010_6033_sp,LPACCPowerModel,gurobi; setting = s)

feas_check_grid_sp = deepcopy(BE_grid_bs_mn_6010_6033)
feas_check_grid_auxiliary_sp = deepcopy(BE_grid_bs_mn_6010_6033)
feas_check_grid_la_sp = deepcopy(BE_grid_bs_mn_6010_6033)
feas_check_grid_auxiliary_la_sp = deepcopy(BE_grid_bs_mn_6010_6033)

prepare_AC_feasibility_check_stochastic_multistep(result_ZIL_sp,feas_check_grid_sp,feas_check_grid_auxiliary_sp,switches_couples_ac_6010_6033, extremes_ZILs_ac_6010_6033,BE_grid_6010_6033,n_hours,n_scenarios)
result_opf_check_sp = _SPMTA.run_stochastic_acdc_opf(feas_check_grid_auxiliary,LPACCPowerModel,gurobi; setting = s)
result_opf_check_sp_ac = _SPMTA.run_stochastic_acdc_opf(feas_check_grid_auxiliary,ACPPowerModel,ipopt; setting = s)

prepare_AC_feasibility_check_stochastic_multistep(result_ZIL_sp_la,feas_check_grid_la_sp,feas_check_grid_auxiliary_la_sp,switches_couples_ac_6010_6033, extremes_ZILs_ac_6010_6033,BE_grid_6010_6033,n_hours,n_scenarios)
result_opf_check_la_sp = _SPMTA.run_stochastic_acdc_opf(feas_check_grid_auxiliary_la_sp,LPACCPowerModel,gurobi; setting = s)
result_opf_check_la_sp_ac = _SPMTA.run_stochastic_acdc_opf(feas_check_grid_auxiliary_la_sp,ACPPowerModel,ipopt; setting = s)


println("The reduction in generation costs with busbar splitting is $(((result_opf["objective"] - result_ZIL["objective"]   )/result_opf["objective"])*100)%, with a MIP gap of $(mip_gap*100)%")
println("The reduction in generation costs with busbar splitting is $(((result_opf["objective"] - result_ZIL_la["objective"])/result_opf["objective"])*100)%, with a MIP gap of $(mip_gap*100)%")

folder_results = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Deliverable_1_2_DIRECTIONS/Results/Synthetic_Belgian_grid"

ZIL = JSON.json(result_ZIL)
ZIL_la = JSON.json(result_ZIL_la)
ZIL_sp = JSON.json(result_ZIL_sp)
ZIL_la_sp = JSON.json(result_ZIL_sp_la)

open(joinpath(folder_results,"Results_ZIL_$(n_hours)_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year).json"),"w" ) do f
    write(f,ZIL)
end
open(joinpath(folder_results,"Results_ZIL_la_$(limit_actions)_$(n_hours)_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year).json"),"w" ) do f
    write(f,ZIL_la)
end

open(joinpath(folder_results,"Results_ZIL_sp_$(n_hours)_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year).json"),"w" ) do f
    write(f,ZIL_sp)
end

open(joinpath(folder_results,"Results_ZIL_la_$(limit_actions)_sp_$(n_hours)_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year).json"),"w" ) do f
    write(f,ZIL_la_sp)
end

################################################################
# Dictionary with wind data
Wind_data
p_50_forecast = [Wind_data["$hour"]["P50_11hforecast_pu"] for hour in start_hour_simulation:end_hour_simulation]
measured = [Wind_data["$hour"]["measured_pu"] for hour in start_hour_simulation:end_hour_simulation]


function make_multinetwork_time_series_opf_check(
    sn_data::Dict{String,Any},n_hours,n_scenarios,start_hour_simulation,end_hour_simulation,time_series,zones,wind_values;
    global_keys = ["hours","scenarios","name","per_unit","source_type","source_version"],
    check_dim::Bool = true,
    )

    mn_data = Dict{String,Any}("nw"=>Dict{String,Any}())
    _FP._add_mn_global_values!(mn_data, sn_data, global_keys)
    #template_nw = _make_template_nw(sn_data, global_keys)
    for hour in start_hour_simulation:end_hour_simulation
        scenario_idx = 1
        nw_hour = hour - start_hour_simulation + 1
        mn_data["nw"]["$nw_hour"] = deepcopy(sn_data)
        add_hour_opf_check(mn_data,hour,nw_hour,scenario_idx,time_series,start_hour_simulation)
        fix_hourly_load_nw(mn_data["nw"]["$nw_hour"],hour,zones,time_series,scenario_idx) 
        fix_gen_time_series_nw(mn_data["nw"]["$nw_hour"],hour,zones,time_series,scenario_idx)
        add_OFW_time_series(mn_data["nw"]["$nw_hour"],nw_hour,zones,wind_values) # this is just to check if it works, to be modified
    end
    mn_data["scenarios"] = n_scenarios
    mn_data["hours"] = n_hours
    return mn_data
end

function add_hour_opf_check(data,hour,index,scenario_idx,time_series,start_hour_simulation)
    nw_hour = hour - start_hour_simulation + 1
    data["nw"]["$index"]["hour"] = nw_hour
    data["nw"]["$index"]["hour_original"] = hour
    data["nw"]["$index"]["scenario"] = scenario_idx
    data["nw"]["$index"]["hour_scenario_index"] = [nw_hour,scenario_idx]
    data["nw"]["$index"]["probability"] = 1.0
end

function fix_hourly_load_nw(grid,hour,zones,load_time_series,scenario_idx) 
    for zone in zones
        for (l_id,l) in grid["load"]
            if l["zone"] == zone
                l["pd"] = deepcopy(load_time_series["load"][l_id]["$hour"]["$scenario_idx"]["pd"]) #pu
                l["qd"] = deepcopy(l["pd"]/20) #pu
            end
        end   
    end
end

function fix_gen_time_series_nw(grid,hour,zones,res_time_series,scenario_idx)
    for zone in zones
        for (g_id,g) in grid["gen"]
            g["pmax"] = g["installed_capacity"]*res_time_series["gen"][g_id]["$hour"]["$scenario_idx"]["capacity_factor"] #pu
        end
    end
end

function add_OFW_time_series(grid,hour,zones,wind_values)
    for zone in zones
        for (g_id,g) in grid["gen"]
            if g["type"] == "Offshore Wind" && g["zone"] == "BE00"
                g["pmax"] = g["installed_capacity"]*wind_values[hour] #pu
            end
        end
    end
end


BE_grid_bs_6010_6033_measured = deepcopy(BE_grid_bs_6010_6033)
BE_grid_opf_6010_6033_measured = deepcopy(BE_grid_opf_6010_6033)
BE_grid_bs_6010_6033_forecasted = deepcopy(BE_grid_bs_6010_6033)
BE_grid_opf_6010_6033_forecasted = deepcopy(BE_grid_opf_6010_6033)

BE_grid_bs_mn_6010_6033_measured    = make_multinetwork_time_series_opf_check(BE_grid_bs_6010_6033_measured,n_hours,n_scenarios,start_hour_simulation,end_hour_simulation,time_series_hour,zones,measured)
BE_grid_opf_mn_6010_6033_measured   = make_multinetwork_time_series_opf_check(BE_grid_opf_6010_6033_measured,n_hours,n_scenarios,start_hour_simulation,end_hour_simulation,time_series_hour,zones,measured)
BE_grid_bs_mn_6010_6033_forecasted  = make_multinetwork_time_series_opf_check(BE_grid_bs_6010_6033_measured,n_hours,n_scenarios,start_hour_simulation,end_hour_simulation,time_series_hour,zones,p_50_forecast)
BE_grid_opf_mn_6010_6033_forecasted = make_multinetwork_time_series_opf_check(BE_grid_opf_6010_6033_measured,n_hours,n_scenarios,start_hour_simulation,end_hour_simulation,time_series_hour,zones,p_50_forecast)


opf_measured = _SPMTA.run_stochastic_acdc_opf(BE_grid_opf_mn_6010_6033_measured,LPACCPowerModel,gurobi; setting = s)
opf_forecasted = _SPMTA.run_stochastic_acdc_opf(BE_grid_opf_mn_6010_6033_forecasted,LPACCPowerModel,gurobi; setting = s)

function run_stochastic_acdcsw_AC_ZIL_hourly_measured(grid, model, optimizer, n_hours,result; setting = s)
    for hour in 1:n_hours
        grid_hour = deepcopy(grid)
        grid_hour["hours"] = 1
        grid_hour["nw"]= Dict{String,Any}()
        grid_hour["nw"]["$hour"] = deepcopy(grid["nw"]["$hour"])  
        result["$hour"] = _SPMTA.run_stochastic_acdcsw_AC_ZIL_hourly(grid_hour,model,optimizer; setting = setting)
    end
    return result
end

bs_measured = Dict{String,Any}()
run_stochastic_acdcsw_AC_ZIL_hourly_measured(BE_grid_bs_mn_6010_6033_measured,LPACCPowerModel,gurobi,n_hours,bs_measured; setting = s)
sum(bs_measured["$i"]["objective"] for i in 1:n_hours)

BE_grid_bs_mn_6010_6033_measured["limit_actions"] = 12
BE_grid_bs_mn_6010_6033_measured["scenarios"] = 1
bs_measured_la = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limited_actions_sp(BE_grid_bs_mn_6010_6033_measured,LPACCPowerModel,gurobi; setting = s)
bs_forecasted = _SPMTA.run_stochastic_acdcsw_AC_ZIL_sp(BE_grid_bs_mn_6010_6033_forecasted,LPACCPowerModel,gurobi; setting = s)
BE_grid_bs_mn_6010_6033_forecasted["limit_actions"] = 12
BE_grid_bs_mn_6010_6033_forecasted["scenarios"] = 1
bs_forecasted_la = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limited_actions_sp(BE_grid_bs_mn_6010_6033_forecasted,LPACCPowerModel,gurobi; setting = s)

opf_measured_json = JSON.json(opf_measured)
opf_forecasted_json = JSON.json(opf_forecasted)

bs_measured_json = JSON.json(bs_measured)
bs_forecasted_json = JSON.json(bs_forecasted)

bs_measured_la_json = JSON.json(bs_measured_la)
bs_forecasted_la_json = JSON.json(bs_forecasted_la)

open(joinpath(folder_results,"Results_OPF_measured_$(n_hours)_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year).json"),"w" ) do f
    write(f,opf_measured_json)
end

open(joinpath(folder_results,"Results_OPF_forecasted_$(n_hours)_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year).json"),"w" ) do f
    write(f,opf_forecasted_json)
end

open(joinpath(folder_results,"Results_BS_measured_$(n_hours)_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year).json"),"w" ) do f
    write(f,bs_measured_json)
end
open(joinpath(folder_results,"Results_BS_forecasted_$(n_hours)_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year).json"),"w" ) do f
    write(f,bs_forecasted_json)
end

open(joinpath(folder_results,"Results_BS_la_measured_$(n_hours)_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year).json"),"w" ) do f
    write(f,bs_measured_la_json)
end

open(joinpath(folder_results,"Results_BS_la_forecasted_$(n_hours)_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year).json"),"w" ) do f
    write(f,bs_forecasted_la_json)
end
## I HAVE TO TAKE THE STATUS OF THE SWITCHES AND APPLY THE MEASURED TIME SERIES
feas_check_grid_measured              = deepcopy(BE_grid_bs_mn_6010_6033_measured   )
feas_check_grid_auxiliary_measured    = deepcopy(BE_grid_opf_mn_6010_6033_measured  )
feas_check_grid_la_measured              = deepcopy(BE_grid_bs_mn_6010_6033_measured   )
feas_check_grid_la_auxiliary_measured    = deepcopy(BE_grid_opf_mn_6010_6033_measured  )

feas_check_grid_forecasted           = deepcopy(BE_grid_bs_mn_6010_6033_forecasted )
feas_check_grid_auxiliary_forecasted = deepcopy(BE_grid_opf_mn_6010_6033_forecasted)
feas_check_grid_la_forecasted           = deepcopy(BE_grid_bs_mn_6010_6033_forecasted )
feas_check_grid_auxiliary_la_forecasted = deepcopy(BE_grid_opf_mn_6010_6033_forecasted)


prepare_AC_feasibility_check_stochastic_multistep(bs_measured,feas_check_grid_measured,feas_check_grid_auxiliary_measured,switches_couples_ac_6010_6033, extremes_ZILs_ac_6010_6033,BE_grid_6010_6033,n_hours,1)
result_opf_check_measured = _SPMTA.run_stochastic_acdc_opf(feas_check_grid_auxiliary,LPACCPowerModel,gurobi; setting = s)

# Something shady is going here, check 
prepare_AC_feasibility_check_stochastic_multistep(bs_forecasted,feas_check_grid_forecasted,feas_check_grid_auxiliary_forecasted,switches_couples_ac_6010_6033, extremes_ZILs_ac_6010_6033,BE_grid_6010_6033,n_hours,1)
result_opf_check_forecasted = _SPMTA.run_stochastic_acdc_opf(feas_check_grid_auxiliary_forecasted,LPACCPowerModel,gurobi; setting = s)


### Checking if the topology with forecasted is feasible in measure
feas_check_grid_forecasted_check           = deepcopy(BE_grid_bs_mn_6010_6033_measured)
feas_check_grid_auxiliary_forecasted_check           = deepcopy(BE_grid_bs_mn_6010_6033_measured)
prepare_AC_feasibility_check_stochastic_multistep(bs_forecasted,feas_check_grid_forecasted_check,feas_check_grid_auxiliary_forecasted_check,switches_couples_ac_6010_6033, extremes_ZILs_ac_6010_6033,BE_grid_6010_6033,n_hours,1)
result_opf_check_measured_with_forecasted_topology = _SPMTA.run_stochastic_acdc_opf(feas_check_grid_auxiliary_forecasted_check,LPACCPowerModel,gurobi; setting = s)
# -> good this seems to work as intended

check_json = JSON.json(result_opf_check_measured_with_forecasted_topology)

open(joinpath(folder_results,"Results_OPF_measured_with_forecasted_topology_$(n_hours)_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year).json"),"w" ) do f
    write(f,check_json)
end

#############################################################################################
# Uploading results
result_ZIL = JSON.parsefile(joinpath(folder_results,"Results_ZIL_$(n_hours)_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year).json"))
result_ZIL_la = JSON.parsefile(joinpath(folder_results,"Results_ZIL_la_$(n_hours)_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year).json"))

result_ZIL_sp    = JSON.parsefile(joinpath(folder_results,"Results_ZIL_sp_$(n_hours)_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year).json"))
result_ZIL_sp_la = JSON.parsefile(joinpath(folder_results,"Results_ZIL_la_sp_$(n_hours)_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year).json"))

bs_measured   = JSON.parsefile(joinpath(folder_results,"Results_BS_measured_$(n_hours)_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year).json"))
bs_forecasted = JSON.parsefile(joinpath(folder_results,"Results_BS_forecasted_$(n_hours)_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year).json"))
opf_forecasted   = JSON.parsefile(joinpath(folder_results,"Results_OPF_measured_$(n_hours)_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year).json"))
opf_measured = JSON.parsefile(joinpath(folder_results,"Results_OPF_forecasted_$(n_hours)_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year).json"))
result_opf_check_measured_with_forecasted_topology = JSON.parsefile(joinpath(folder_results,"Results_OPF_measured_with_forecasted_topology_$(n_hours)_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year).json"))

#############################################################################################
CHECK_result_ZIL   = deepcopy(BE_grid_bs_mn_6010_6033_measured)
CHECK_result_ZIL_auxiliary = deepcopy(BE_grid_bs_mn_6010_6033_measured)

CHECK_result_ZIL_la   = deepcopy(BE_grid_bs_mn_6010_6033_measured)
CHECK_result_ZIL_la_auxiliary = deepcopy(BE_grid_bs_mn_6010_6033_measured)


CHECK_result_ZIL_sp   = deepcopy(BE_grid_bs_mn_6010_6033_measured)
CHECK_result_ZIL_sp_auxiliary = deepcopy(BE_grid_bs_mn_6010_6033_measured)

CHECK_result_ZIL_sp_la   = deepcopy(BE_grid_bs_mn_6010_6033_measured)
CHECK_result_ZIL_sp_la_auxiliary = deepcopy(BE_grid_bs_mn_6010_6033_measured)


prepare_AC_feasibility_check_stochastic_multistep(result_ZIL,CHECK_result_ZIL,CHECK_result_ZIL_auxiliary,switches_couples_ac_6010_6033, extremes_ZILs_ac_6010_6033,BE_grid_6010_6033,n_hours,1)
OPF_CHECK_result_ZIL = _SPMTA.run_stochastic_acdc_opf(CHECK_result_ZIL_auxiliary,LPACCPowerModel,gurobi; setting = s)

prepare_AC_feasibility_check_stochastic_multistep(result_ZIL_la,CHECK_result_ZIL_la,CHECK_result_ZIL_la_auxiliary,switches_couples_ac_6010_6033, extremes_ZILs_ac_6010_6033,BE_grid_6010_6033,n_hours,1)
OPF_CHECK_result_ZIL_la = _SPMTA.run_stochastic_acdc_opf(CHECK_result_ZIL_la_auxiliary,LPACCPowerModel,gurobi; setting = s)

prepare_AC_feasibility_check_stochastic_multistep(result_ZIL_sp,CHECK_result_ZIL_sp,CHECK_result_ZIL_sp_auxiliary,switches_couples_ac_6010_6033, extremes_ZILs_ac_6010_6033,BE_grid_6010_6033,n_hours,1)
OPF_CHECK_result_ZIL_sp = _SPMTA.run_stochastic_acdc_opf(CHECK_result_ZIL_sp_auxiliary,LPACCPowerModel,gurobi; setting = s)

prepare_AC_feasibility_check_stochastic_multistep(result_ZIL_la,CHECK_result_ZIL_sp_la,CHECK_result_ZIL_sp_la_auxiliary,switches_couples_ac_6010_6033, extremes_ZILs_ac_6010_6033,BE_grid_6010_6033,n_hours,1)
OPF_CHECK_result_ZIL_sp_la = _SPMTA.run_stochastic_acdc_opf(CHECK_result_ZIL_sp_la_auxiliary,LPACCPowerModel,gurobi; setting = s)


opf_forecasted["objective"]*100 - opf_measured["objective"]*100
OPF_CHECK_result_ZIL["objective"]*100 - opf_measured["objective"]*100
obj_measured_hourly = sum(bs_measured_hourly["$i"]["objective"] for i in 1:n_hours)




#############################################################################################
# OFW generators Belgium
ofw_gen_BE = []
for (g_id,g) in BE_grid_bs_6010_6033["gen"]
    if g["type"] == "Offshore Wind" && g["zone"] == "BE00"
        push!(ofw_gen_BE,g_id)
    end
end
ofw_BE_generation = []
ofw_BE_max = []
for nw in 1:n_hours
    push!(ofw_BE_generation,sum(opf_measured["solution"]["nw"]["$nw"]["gen"][g_id]["pg"] for g_id in ofw_gen_BE))
    push!(ofw_BE_max,sum(BE_grid_bs_6010_6033["gen"][g_id]["pmax"] for g_id in ofw_gen_BE)*measured[nw])
end
plot(ofw_BE_generation,label = "OFW generation")
plot!(ofw_BE_max,label = "OFW theoretical maximum")

opf_measured["objective"]
hourly_opf_value_measured = [sum(opf_measured["solution"]["nw"]["$nw"]["gen"][g_id]["pg"]*g["cost"][1]*100 for (g_id,g) in BE_grid_bs_6010_6033["gen"]) for nw in 1:n_hours]
hourly_opf_value_forecasted = [sum(opf_forecasted["solution"]["nw"]["$nw"]["gen"][g_id]["pg"]*g["cost"][1]*100 for (g_id,g) in BE_grid_bs_6010_6033["gen"]) for nw in 1:n_hours]
hourly_opf_value_measured_with_forecasted = [sum(result_opf_check_measured_with_forecasted_topology["solution"]["nw"]["$nw"]["gen"][g_id]["pg"]*g["cost"][1]*100 for (g_id,g) in BE_grid_bs_6010_6033["gen"]) for nw in 1:n_hours]


function compute_hourly_costs_stochastic_multistep_simulations(grid,result,start_hour_simulation,end_hour_simulation,time_series_hour,n_scenarios,vector)
    for hour in start_hour_simulation:end_hour_simulation
        hourly_cost_hour = 0
        for scenario_idx in 1:n_scenarios
            hourly_cost_scenario = 0
            nw = (hour - start_hour_simulation)*n_scenarios + scenario_idx
            for (g_id,g) in grid["gen"]
                hourly_cost_scenario += result["solution"]["nw"]["$nw"]["gen"][g_id]["pg"]*g["cost"][1]*100
            end
            hourly_cost_hour += hourly_cost_scenario*time_series_hour["scenario_probability"]["$hour"][scenario_idx]
        end
        push!(vector,hourly_cost_hour)
    end
end

result_hourly_bs

function compute_hourly_costs_stochastic_multistep_simulations_hourly(grid,result,start_hour_simulation,end_hour_simulation,time_series_hour,n_scenarios,vector)
    for hour in start_hour_simulation:end_hour_simulation
        hourly_cost_hour = 0
        for scenario_idx in 1:n_scenarios
            hourly_cost_scenario = 0
            nw = (hour - start_hour_simulation)*n_scenarios + scenario_idx
            for (g_id,g) in grid["gen"]
                hourly_cost_scenario += result["$(hour+1-start_hour_simulation)"]["solution"]["nw"]["$nw"]["gen"][g_id]["pg"]*g["cost"][1]*100
            end
            hourly_cost_hour += hourly_cost_scenario*time_series_hour["scenario_probability"]["$hour"][scenario_idx]
        end
        push!(vector,hourly_cost_hour)
    end
end

function compute_hourly_costs_stochastic_multistep_simulations_hourly_measured(grid,result,start_hour_simulation,end_hour_simulation,time_series_hour,vector)
    for hour in start_hour_simulation:end_hour_simulation
        println("hour: $hour")
        hourly_cost_hour = 0
        for scenario_idx in 1:1
            hourly_cost_scenario = 0
            for (g_id,g) in grid["gen"]
                hourly_cost_scenario += result["$(hour - start_hour_simulation+1)"]["solution"]["nw"]["$(hour - start_hour_simulation+1)"]["gen"][g_id]["pg"]*g["cost"][1]*100
            end
            hourly_cost_hour += hourly_cost_scenario*time_series_hour["scenario_probability"]["$hour"][scenario_idx]
        end
        push!(vector,hourly_cost_hour)
    end
end

hourly_ZIL = []
hourly_ZIL_la = []
hourly_ZIL_sp = []
hourly_ZIL_sp_la = []
hourly_ZIL_hourly = []
hourly_ZIL_measured_hourly = [bs_measured_hourly["$nw"]["objective"]*100 for nw in 1:n_hours]
term_status = [bs_measured_hourly["$nw"]["termination_status"] for nw in 1:n_hours]
term_status = [result_hourly_bs["$nw"]["termination_status"] for nw in 1:n_hours]

compute_hourly_costs_stochastic_multistep_simulations(BE_grid_bs_6010_6033,result_ZIL,start_hour_simulation,end_hour_simulation,time_series_hour,n_scenarios,hourly_ZIL)
compute_hourly_costs_stochastic_multistep_simulations(BE_grid_bs_6010_6033,result_ZIL_la,start_hour_simulation,end_hour_simulation,time_series_hour,n_scenarios,hourly_ZIL_la)
compute_hourly_costs_stochastic_multistep_simulations(BE_grid_bs_6010_6033,result_ZIL_sp,start_hour_simulation,end_hour_simulation,time_series_hour,n_scenarios,hourly_ZIL_sp)
compute_hourly_costs_stochastic_multistep_simulations(BE_grid_bs_6010_6033,result_ZIL_sp_la,start_hour_simulation,end_hour_simulation,time_series_hour,n_scenarios,hourly_ZIL_sp_la)
compute_hourly_costs_stochastic_multistep_simulations_hourly(BE_grid_bs_6010_6033,result_hourly_bs,start_hour_simulation,end_hour_simulation,time_series_hour,n_scenarios,hourly_ZIL_hourly)
#compute_hourly_costs_stochastic_multistep_simulations_hourly_measured(BE_grid_bs_6010_6033,bs_measured_hourly,start_hour_simulation,end_hour_simulation,time_series_hour,hourly_ZIL_measured_hourly)
sum(hourly_ZIL_hourly)
sum(hourly_ZIL_measured_hourly)


rel_hourly_opf_value_measured = (1 .- hourly_opf_value_measured./hourly_opf_value_measured)*100
rel_hourly_opf_value_measured_with_forecasted = (1 .- hourly_opf_value_measured_with_forecasted./hourly_opf_value_measured)*100
rel_hourly_ZIL = (1 .- hourly_ZIL./hourly_opf_value_measured)*100
rel_hourly_ZIL_la = (1 .- hourly_ZIL_la./hourly_opf_value_measured)*100
rel_hourly_ZIL_sp = (1 .- hourly_ZIL_sp./hourly_opf_value_measured)*100
rel_hourly_ZIL_sp_la = (1 .- hourly_ZIL_sp_la./hourly_opf_value_measured)*100
rel_hourly_ZIL_hourly = (1 .- hourly_ZIL_hourly./hourly_opf_value_measured)*100


plot(rel_hourly_opf_value_measured,label = "Perfect foresight",
    ylims = [-1.0,1.5],xticks = 1:24, ylabel = "Cost decrease wrt perfect foresight OPF [%]", 
    ylabelfontsize = 10,xlabel = "Hour", xlabelfontsize = 10, 
    legend = :topright, grid = :none)
plot!(rel_hourly_opf_value_measured_with_forecasted,label = "Day-ahead topology")
plot!(rel_hourly_ZIL,label = "ZIL")
plot!(rel_hourly_ZIL_la,label = "ZIL limited actions")
plot!(rel_hourly_ZIL_sp,label = "ZIL sp")
plot!(rel_hourly_ZIL_sp_la,label = "ZIL limited actions sp")
plot!(rel_hourly_ZIL_hourly,label = "ZIL hourly")

result_figures_folder = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Deliverable_1_2_DIRECTIONS/Figures"
savefig(joinpath(result_figures_folder,"Cost_decrease_$(n_hours)_$(start_hour_simulation)_$(end_hour_simulation)_$(scenario)$(year)_$(climate_year).svg")) 

#########################################################################
# Status of the switches
first_hours = []
for hour in start_hour_simulation:end_hour_simulation
    scenario_idx = 1
    push!(first_hours,(hour - start_hour_simulation)*n_scenarios + scenario_idx)
end

sw_status_1_ZIL       = [result_ZIL["solution"]["nw"]["$i"]["switch"]["1"]["status"] for i in first_hours]
sw_status_1_ZIL_la    = [result_ZIL_la["solution"]["nw"]["$i"]["switch"]["1"]["status"] for i in first_hours]
sw_status_1_ZIL_sp    = [result_ZIL_sp["solution"]["nw"]["$i"]["switch"]["1"]["status"] for i in first_hours]
sw_status_1_ZIL_sp_la = [result_ZIL_sp_la["solution"]["nw"]["$i"]["switch"]["1"]["status"] for i in first_hours]

sw_status_2_ZIL       = [result_ZIL["solution"]["nw"]["$i"]["switch"]["2"]["status"] for i in first_hours]
sw_status_2_ZIL_la    = [result_ZIL_la["solution"]["nw"]["$i"]["switch"]["2"]["status"] for i in first_hours]
sw_status_2_ZIL_sp    = [result_ZIL_sp["solution"]["nw"]["$i"]["switch"]["2"]["status"] for i in first_hours]
sw_status_2_ZIL_sp_la = [result_ZIL_sp_la["solution"]["nw"]["$i"]["switch"]["2"]["status"] for i in first_hours]


for i in 1:24
    if sw_status_1_ZIL_la[i] == 0.0
        sw_status_1_ZIL_la[i] = 0.3
    end
    if sw_status_1_ZIL[i] == 0.0
        sw_status_1_ZIL[i] = 0.1
    end
end
scatter(sw_status_1_ZIL,yticks = :none,xticks = (0:1:24),ylims = (0,1.2),ylabel = "Closed                           Open",label = "Stochastic Multistep")
scatter!(sw_status_1_ZIL_la,label = "Stochastic Multistep limited actions")



