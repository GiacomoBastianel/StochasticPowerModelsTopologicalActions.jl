using PowerModels; const _PM = PowerModels
using PowerModelsACDC; const _PMACDC = PowerModelsACDC
import PowerModelsTopologicalActionsII; const _PMTP = PowerModelsTopologicalActionsII
using FlexPlan; const _FP = FlexPlan
using Gurobi
using Ipopt
using JSON
import StochasticPowerModelsTopologicalActions; const _SPMTA = StochasticPowerModelsTopologicalActions
using JuMP
using Juniper
using HSL_jll

gurobi = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"BarQCPConvTol"=>1e-6,"QCPDual" => 1)#r, "ScaleFlag"=>2, "NumericFocus"=>2) 
ipopt = JuMP.optimizer_with_attributes(Ipopt.Optimizer, "tol" => 1e-6, "print_level" => 0,"linear_solver" => "ma97")
juniper = JuMP.optimizer_with_attributes(Juniper.Optimizer, "nl_solver" => ipopt, "mip_solver" => gurobi, "time_limit" => 36000)

#########################################################################################
## Processing input data
input_folder = "/Users/giacomobastianel/.julia/dev/DIRECTIONS_WP4.jl/src/Step_1"

# Belgium grid without energy island
BE_grid_2024_file = joinpath(dirname(dirname(input_folder)),"test_cases/DIRECTIONS_test_case_Step_1_no_OWF_UK_corrected.json")
BE_grid = _PM.parse_file(BE_grid_2024_file)

BE_grid_2024_lpac_file = joinpath(dirname(dirname(input_folder)),"test_cases/DIRECTIONS_test_case_Step_1_no_OWF_UK_corrected_LPAC.json")
BE_grid_lpac = _PM.parse_file(BE_grid_2024_lpac_file)

s = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true)
s_dual = Dict("output" => Dict("branch_flows" => true,"duals" => true), "conv_losses_mp" => true)

#########################################################################################
# Calling scenario and climate year
results_folder = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Deliverable_4_1_DIRECTIONS/Results/Collab_Line"
scenario = "DE"
year = "2050"
climate_year = "1995"

simulated_hour = 761
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

BE_grid_lpac_check_file = joinpath(results_folder,"BE_grid_lpac_check_$(simulated_hour)_$(scenario)$(year)_$(climate_year).json")
open(BE_grid_lpac_check_file, "r") do f
    global BE_grid_lpac_check = JSON.parse(read(f, String))
end

BE_grid_ac_check_file = joinpath(results_folder,"BE_grid_ac_check_$(simulated_hour)_$(scenario)$(year)_$(climate_year).json")
open(BE_grid_ac_check_file, "r") do f
    global BE_grid_ac_check = JSON.parse(read(f, String))
end

Results_lpac_feasibility_check_file = joinpath(results_folder,"Results_lpac_feasibility_check_$(simulated_hour)_$(scenario)$(year)_$(climate_year).json")
open(Results_lpac_feasibility_check_file, "r") do f
    global Results_lpac_feasibility_check = JSON.parse(read(f, String))
end

Results_ac_feasibility_check_file = joinpath(results_folder,"Results_ac_feasibility_check_$(simulated_hour)_$(scenario)$(year)_$(climate_year).json")
open(Results_ac_feasibility_check_file, "r") do f
    global Results_ac_feasibility_check = JSON.parse(read(f, String))
end

Results_lpac_file = joinpath(results_folder,"Results_lpac_$(simulated_hour)_$(scenario)$(year)_$(climate_year).json")
open(Results_lpac_file, "r") do f
    global Results_lpac = JSON.parse(read(f, String))
end

Results_ac_file = joinpath(results_folder,"Results_ac_$(simulated_hour)_$(scenario)$(year)_$(climate_year).json")
open(Results_ac_file, "r") do f
    global Results_ac = JSON.parse(read(f, String))
end
zones = ["BE00","UK00","FR00"]

#########################################################################################
# Uploading pdf samples for offshore wind
year_wind = "2023"
folder_data = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Elia_data"

Gaussian_samples_file = joinpath(folder_data,"Gaussian_samples_8_Offshore_wind_$(year_wind)_Elia.json")
Gaussian_samples = JSON.parsefile(Gaussian_samples_file)

Elia_OFW_file = joinpath(folder_data,"Offshore_wind_$(year_wind)_Elia.json")
Elia_OFW = JSON.parsefile(Elia_OFW_file)

#########################################################################################
# Selecting the hour
for i in eachindex(Elia_OFW)
    if Elia_OFW[i]["minute"] == "00" && (Elia_OFW[i]["dayahead11hforecast"]/Elia_OFW[i]["monitoredcapacity"] < 0.91001 && Elia_OFW[i]["dayahead11hforecast"]/Elia_OFW[i]["monitoredcapacity"] > 0.9099)
        println(i)
    end
end

# Hour information
Elia_OFW[29561]

# Processing numbers to be used later
most_recent_forecast_pu = Elia_OFW[29561]["mostrecentforecast"]/Elia_OFW[29561]["monitoredcapacity"]
measured_pu = Elia_OFW[29561]["measured"]/Elia_OFW[29561]["monitoredcapacity"]
P50_forecast_pu = Elia_OFW[29561]["dayahead11hforecast"]/Elia_OFW[29561]["monitoredcapacity"]

#######################################################################################
# Busbar splitting
BE_grid_bs = deepcopy(BE_grid_lpac)

Results_ac_761 = _SPMTA.hourly_opf(BE_grid,simulated_hour,simulated_hour,zones,Load_time_series,RES_time_series,s_dual,ipopt,ACPPowerModel)
Results_lpac_761 = _SPMTA.hourly_opf(BE_grid_lpac,simulated_hour,simulated_hour,zones,Load_time_series,RES_time_series,s_dual,gurobi,LPACCPowerModel)

#######################################################################################
# Selecting which busbars are split
splitted_bus_ac = [26,261]
name_splitted_buses = "26_261"

optimizer = gurobi
formulation = LPACCPowerModel

BE_grid_bs,  switches_couples_ac,  extremes_ZILs_ac  = _PMTP.AC_busbar_split_more_buses(BE_grid_bs,splitted_bus_ac)
Results_bs = _SPMTA.hourly_bs(BE_grid_bs,simulated_hour,simulated_hour,zones,Load_time_series,RES_time_series,optimizer,formulation)

# Print connection switches
for i in 1:length(BE_grid_bs["switch"])
    if !haskey(BE_grid_bs["switch"]["$i"],"auxiliary")
            println(i," f_bus ",BE_grid_bs["switch"]["$i"]["f_bus"]," t_bus ",BE_grid_bs["switch"]["$i"]["t_bus"]," status ", Results_bs["761"]["solution"]["switch"]["$i"]["status"])
    else
        if Results_bs["761"]["solution"]["switch"]["$i"]["status"] == 1.0
            println(i," t_bus ",BE_grid_bs["switch"]["$i"]["t_bus"]," status ", Results_bs["761"]["solution"]["switch"]["$i"]["status"]," auxiliary ", BE_grid_bs["switch"]["$i"]["auxiliary"], " original ", BE_grid_bs["switch"]["$i"]["original"])
        end
    end
end

Results_feasibility_check, BE_grid_check = hourly_feasibility_check_bs_scenarios(BE_grid_bs,Results_bs,switches_couples_ac,extremes_ZILs_ac,hour,zones,Load_time_series,RES_time_series,gurobi,LPACCPowerModel,BE_grid,s_dual)
Results_lpac_761["761"]["objective"]*10^2 - Results_feasibility_check["761"]["objective"]*10^2

###############################
# Add dimensions for stochastic part
n_hours = 1
n_scenarios = 8
hour_wind = 29561

_FP._initialize_dim()
_FP.add_dimension!(BE_grid_bs, :scenario, n_scenarios)
_FP.add_dimension!(BE_grid_bs, :hour, n_hours)

_FP.add_dimension!(BE_grid_lpac, :scenario, n_scenarios)
_FP.add_dimension!(BE_grid_lpac, :hour, n_hours)


# Time series
RES_time_series_hour = Dict{String,Any}()
_SPMTA.create_RES_time_series_scenarios(BE_grid_bs,RES_time_series_hour,Gaussian_samples,n_scenarios,simulated_hour,hour_wind)

scenarios_probabilities = Dict{String,Any}()
_SPMTA.add_scenarios_probabilities(scenarios_probabilities,hour_wind,n_hours,n_scenarios,Gaussian_samples)

gen_time_series_hour = Dict{String,Any}()
_SPMTA.add_gen_time_series(BE_grid_bs, gen_time_series_hour, RES_time_series_hour, simulated_hour, n_scenarios)

load_time_series_hour = Dict{String,Any}()
_SPMTA.add_load_time_series(BE_grid_bs, load_time_series_hour, Load_time_series, simulated_hour, n_scenarios)

time_series_hour = Dict{String,Any}()
_SPMTA.generate_input_dict_stochastic_optimization(time_series_hour,gen_time_series_hour,load_time_series_hour,scenarios_probabilities)


_SPMTA.add_hour_scenario_data(BE_grid_bs, n_hours, n_scenarios)
_SPMTA.add_hour_scenario_data(BE_grid_lpac, n_hours, n_scenarios)


BE_grid_bs_mn = _SPMTA.make_multinetwork_time_series_scenarios(BE_grid_bs,n_scenarios,hour_wind,simulated_hour,time_series_hour)
BE_grid_bs_opf_mn = _SPMTA.make_multinetwork_time_series_scenarios(BE_grid_lpac,n_scenarios,hour_wind,simulated_hour,time_series_hour)

#######################################
result = _SPMTA.run_stochastic_acdcsw_AC_ZIL(BE_grid_bs_mn, LPACCPowerModel, gurobi)
result_opf = _SPMTA.run_stochastic_acdc_opf(BE_grid_bs_opf_mn, LPACCPowerModel, gurobi)


for i in 1:length(BE_grid_bs["switch"])
    if !haskey(BE_grid_bs["switch"]["$i"],"auxiliary")
            println(i," f_bus ",BE_grid_bs["switch"]["$i"]["f_bus"]," t_bus ",BE_grid_bs["switch"]["$i"]["t_bus"]," status ", result["solution"]["nw"]["1"]["switch"]["$i"]["status"])
    else
        if result["solution"]["nw"]["1"]["switch"]["$i"]["status"] == 1.0
            println(i," t_bus ",BE_grid_bs["switch"]["$i"]["t_bus"]," status ", result["solution"]["nw"]["1"]["switch"]["$i"]["status"]," auxiliary ", BE_grid_bs["switch"]["$i"]["auxiliary"], " original ", BE_grid_bs["switch"]["$i"]["original"])
        end
    end
end



optimizer_feasibility_check = ipopt
formulation_feasibility_check = ACPPowerModel
hour = 761
Results_feasibility_check, BE_grid_check_try = _SPMTA.hourly_feasibility_check_bs_scenarios_stochastic(BE_grid_lpac,result,switches_couples_ac,extremes_ZILs_ac,simulated_hour,zones,Load_time_series,RES_time_series,measured_pu,optimizer_feasibility_check,formulation_feasibility_check,BE_grid_lpac,s,1)
Results_feasibility_check["$simulated_hour"]



#################################
# OPF measured
BE_grid_bs_measured = deepcopy(BE_grid_lpac)
BE_grid_bs_measured,  switches_couples_ac,  extremes_ZILs_ac  = _PMTP.AC_busbar_split_more_buses(BE_grid_bs_measured,splitted_bus_ac)

Results_ac_measured = _SPMTA.hourly_opf_measured(BE_grid_lpac,simulated_hour,simulated_hour,zones,Load_time_series,RES_time_series,s_dual,ipopt,ACPPowerModel,measured_pu)
Results_bs_measured = _SPMTA.hourly_bs_measured(BE_grid_bs_measured,simulated_hour,simulated_hour,zones,Load_time_series,RES_time_series,gurobi,LPACCPowerModel,measured_pu)


for i in 1:length(BE_grid_bs["switch"])
    if !haskey(BE_grid_bs["switch"]["$i"],"auxiliary")
            println(i," f_bus ",BE_grid_bs["switch"]["$i"]["f_bus"]," t_bus ",BE_grid_bs["switch"]["$i"]["t_bus"]," status ", Result_bs_measured["$hour"]["solution"]["switch"]["$i"]["status"])
    else
        if Result_bs_measured["$hour"]["solution"]["switch"]["$i"]["status"] == 1.0
            println(i," t_bus ",BE_grid_bs["switch"]["$i"]["t_bus"]," status ", Result_bs_measured["$hour"]["solution"]["switch"]["$i"]["status"]," auxiliary ", BE_grid_bs["switch"]["$i"]["auxiliary"], " original ", BE_grid_bs["switch"]["$i"]["original"])
        end
    end
end
