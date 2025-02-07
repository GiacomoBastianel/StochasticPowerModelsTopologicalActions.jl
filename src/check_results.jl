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
zones = ["BE00", "FR00", "UK00"]

simulated_hour = 761

BE_grid_bs = deepcopy(BE_grid_lpac)
# Selecting which busbars are split
splitted_bus_ac = [26,261]
name_splitted_buses = "26_261"

optimizer = gurobi
formulation = LPACCPowerModel

BE_grid_bs,  switches_couples_ac,  extremes_ZILs_ac  = _PMTP.AC_busbar_split_more_buses(BE_grid_bs,splitted_bus_ac)


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

BE_grid_lpac_check_file = joinpath(results_folder,"BE_grid_lpac_check_761_$(scenario)$(year)_$(climate_year).json")
open(BE_grid_lpac_check_file, "r") do f
    global BE_grid_lpac_check = JSON.parse(read(f, String))
end


Results_lpac_fc_file = joinpath(results_folder,"Results_lpac_feasibility_check_$(simulated_hour)_$(scenario)$(year)_$(climate_year).json")
open(Results_lpac_fc_file, "r") do f
    global Results_lpac_fc = JSON.parse(read(f, String))
end

Results_lpac_file = joinpath(results_folder,"Results_lpac_$(simulated_hour)_$(scenario)$(year)_$(climate_year).json")
open(Results_lpac_file, "r") do f
    global Results_lpac = JSON.parse(read(f, String))
end

#########################################################################################

Results_ac   = _SPMTA.hourly_opf(BE_grid,simulated_hour,simulated_hour,zones,Load_time_series,RES_time_series,s_dual,ipopt,ACPPowerModel)
Results_lpac = _SPMTA.hourly_opf(BE_grid_lpac,simulated_hour,simulated_hour,zones,Load_time_series,RES_time_series,s_dual,gurobi,LPACCPowerModel)

Duals = Dict()
for (b_id,b) in BE_grid_lpac["bus"]
    Duals["$b_id"] = Dict()
    Duals["$b_id"]["lam_kcl_i"] = Results_lpac["$simulated_hour"]["solution"]["bus"]["$b_id"]["lam_kcl_i"]
    Duals["$b_id"]["lam_kcl_r"] = Results_lpac["$simulated_hour"]["solution"]["bus"]["$b_id"]["lam_kcl_r"]
end

Duals = Dict()
for (b_id,b) in BE_grid_lpac_check["761"]["bus"]
    Duals["$b_id"] = Dict()
    Duals["$b_id"]["lam_kcl_i"] = Results_lpac_fc["solution"]["bus"]["$b_id"]["lam_kcl_i"]
    Duals["$b_id"]["lam_kcl_r"] = Results_lpac_fc["solution"]["bus"]["$b_id"]["lam_kcl_r"]
end


#########################################################################################
# Busbar splitting
BE_grid_bs = deepcopy(BE_grid_lpac)

# Selecting which busbars are split
splitted_bus_ac = [26,261]
name_splitted_buses = "26_261"

optimizer = gurobi
formulation = LPACCPowerModel

BE_grid_bs,  switches_couples_ac,  extremes_ZILs_ac  = _PMTP.AC_busbar_split_more_buses(BE_grid_bs,splitted_bus_ac)


Results_bs = _SPMTA.hourly_bs(BE_grid_bs,simulated_hour,simulated_hour,zones,Load_time_series,RES_time_series,optimizer,formulation)


# Feasibility check
function hourly_feasibility_check_bs(grid,results_bs,switches_couples,extremes_ZILs,hours,zones,load_time_series,res_time_series,optimizer,formulation,opf_grid,s)
    results = Dict()
    hourly_grid = deepcopy(grid)
    grid_check = Dict{String,Any}()
    for hour in hours
        fix_hourly_load(hourly_grid,hour,zones,load_time_series) 
        fix_res_time_series(hourly_grid,hour,zones,res_time_series)
        prepare_AC_feasibility_check_hourly(results_bs,hourly_grid,hourly_grid,switches_couples,extremes_ZILs,opf_grid,hour)
        hourly_results = _PMACDC.run_acdcopf(hourly_grid,formulation,optimizer; setting = s)
        results["$hour"] = deepcopy(hourly_results)
        grid_check["$hour"] = deepcopy(hourly_grid)
    end
    return results, grid_check
end

function prepare_AC_feasibility_check_hourly(result_dict, input_dict, input_ac_check, switch_couples, extremes_dict,input_base,hour)    
    orig_buses = maximum(parse.(Int, keys(input_base["bus"]))) + length(extremes_dict)
    #print("Orig buses is $orig_buses","\n")
    for (sw_id,sw) in input_dict["switch"]
        if haskey(sw,"auxiliary") && haskey(sw,"auxiliary") # Make sure ZILs are not included 
            aux =  deepcopy(input_ac_check["switch"][sw_id]["auxiliary"])
            orig = deepcopy(input_ac_check["switch"][sw_id]["original"])  
            for zil in eachindex(extremes_dict)
                if sw["bus_split"] == extremes_dict[zil][1] && result_dict["$hour"]["solution"]["switch"]["$(switch_couples[sw_id]["switch_split"])"]["status"] == 1.0  # Making sure to reconnect everything to the original if the ZIL is connected
                    if result_dict["$hour"]["solution"]["switch"][sw_id]["status"] >= 0.9
                        if aux == "gen"
                            input_ac_check["gen"]["$(orig)"]["gen_bus"] = deepcopy(extremes_dict[zil][1])
                        elseif aux == "load"
                            input_ac_check["load"]["$(orig)"]["load_bus"] = deepcopy(extremes_dict[zil][1])
                        elseif aux == "convdc"
                            input_ac_check["convdc"]["$(orig)"]["busac_i"] = deepcopy(extremes_dict[zil][1])
                        elseif aux == "branch"  
                            if input_ac_check["branch"]["$(orig)"]["f_bus"] > orig_buses && switch_couples[sw_id]["bus_split"] == parse(Int64,zil)
                                    input_ac_check["branch"]["$(orig)"]["f_bus"] = deepcopy(switch_couples[sw_id]["bus_split"])
                            elseif input_ac_check["branch"]["$(orig)"]["t_bus"] > orig_buses && switch_couples[sw_id]["bus_split"] == parse(Int64,zil)
                                    input_ac_check["branch"]["$(orig)"]["t_bus"] = deepcopy(switch_couples[sw_id]["bus_split"])
                            end
                        end
                        delete!(input_ac_check["switch"],sw_id)
                    else
                        delete!(input_ac_check["switch"],sw_id)
                    end
                elseif sw["bus_split"] == extremes_dict[zil][1] && result_dict["$hour"]["solution"]["switch"]["$(switch_couples[sw_id]["switch_split"])"]["status"] == 0.0 # Reconnect everything to the split busbar
                    if result_dict["$hour"]["solution"]["switch"][sw_id]["status"] >= 0.9
                        if aux == "gen"
                            input_ac_check["gen"]["$(orig)"]["gen_bus"] = deepcopy(sw["t_bus"])
                        elseif aux == "load"
                            input_ac_check["load"]["$(orig)"]["load_bus"] = deepcopy(sw["t_bus"])
                        elseif aux == "convdc"
                            input_ac_check["convdc"]["$(orig)"]["busac_i"] = deepcopy(sw["t_bus"])
                        elseif aux == "branch" 
                            if input_ac_check["branch"]["$(orig)"]["f_bus"] > orig_buses && switch_couples[sw_id]["bus_split"] == parse(Int64,zil) 
                                    input_ac_check["branch"]["$(orig)"]["f_bus"] = deepcopy(sw["t_bus"])
                            elseif input_ac_check["branch"]["$(orig)"]["t_bus"] > orig_buses && switch_couples[sw_id]["bus_split"] == parse(Int64,zil)
                                if !haskey(input_ac_check["branch"]["$(orig)"],"checked")
                                    input_ac_check["branch"]["$(orig)"]["t_bus"] = deepcopy(sw["t_bus"])
                                end
                            end
                        end
                        delete!(input_ac_check["switch"],sw_id)
                    else
                        delete!(input_ac_check["switch"],sw_id)
                    end
                end
            end
        end
    end
    return input_ac_check

end

function fix_hourly_load(grid,hour,zones,load_time_series) 
    for zone in zones
        for (l_id,l) in grid["load"]
            if l["zone"] == zone
                l["pd"] = deepcopy(load_time_series[zone]["pu"][hour]) #pu
                l["qd"] = deepcopy(l["pd"]/20) #pu
            end
        end   
    end
end

function fix_res_time_series(grid,hour,zones,res_time_series)
    for zone in zones
        for (g_id,g) in grid["gen"]
            if g["zone"] == zone
                if g["type"] == "Onshore Wind" 
                    g["pmax"] = g["installed_capacity"]*res_time_series[zone]["Onshore_wind"][hour] #pu
                elseif g["type"] == "Offshore Wind" 
                    g["pmax"] = g["installed_capacity"]*res_time_series[zone]["Offshore_wind"][hour] #pu
                elseif g["type"] == "Solar PV" 
                    g["pmax"] = g["installed_capacity"]*res_time_series[zone]["Solar_PV"][hour] #pu
                end
            end
        end
    end
end

BE_grid_bs_check = prepare_AC_feasibility_check_hourly(Results_bs, BE_grid_bs, BE_grid_bs, switches_couples_ac, extremes_ZILs_ac,BE_grid_lpac,simulated_hour)    
Results_bs_fc, BE_grid_bs_check_fc = hourly_feasibility_check_bs(BE_grid_bs_check,Results_bs,switches_couples_ac,extremes_ZILs_ac,simulated_hour,zones,Load_time_series,RES_time_series,optimizer,formulation,BE_grid_lpac,s_dual)

Duals_fc = Dict()
for (b_id,b) in BE_grid_bs_check_fc["761"]["bus"]
    if !haskey(b,"auxiliary_bus")
        Duals["$b_id"] = Dict()
        Duals["$b_id"]["lam_kcl_i"] = Results_bs_fc["761"]["solution"]["bus"]["$b_id"]["lam_kcl_i"]
        Duals["$b_id"]["lam_kcl_r"] = Results_bs_fc["761"]["solution"]["bus"]["$b_id"]["lam_kcl_r"]
    end
end

#########################################################################################




function compute_vas_single_hour(dict,grid,results)
    #dict = Dict{Stri}()
    for (b_id,b) in grid["bus"]
        if b["bus_type"] != 3 && results["solution"]["bus"]["$b_id"]["va"] != 0.0
            dict["$b_id"] = results["solution"]["bus"]["$b_id"]["va"]
        elseif b["bus_type"] == 3 
            dict["$b_id"] = results["solution"]["bus"]["$b_id"]["va"]
        end
    end
end

function compute_vms_single_hour(dict,grid,results)
    #dict = Dict{Stri}()
    for (b_id,b) in grid["bus"]
        if b["bus_type"] != 3 && results["solution"]["bus"]["$b_id"]["va"] != 0.0
            dict["$b_id"] = 1 - results["solution"]["bus"]["$b_id"]["phi"]
        elseif b["bus_type"] == 3 
            dict["$b_id"] = 1 - results["solution"]["bus"]["$b_id"]["phi"]
        end
    end
end

vas_lpac = Dict()
compute_vas_single_hour(vas_lpac,BE_grid_lpac,Results_lpac)

vas_lpac_fc = Dict()
compute_vas_single_hour(vas_lpac_fc,BE_grid_lpac_check["761"],Results_lpac_fc)

vms_lpac = Dict()
compute_vms_single_hour(vms_lpac,BE_grid_lpac,Results_lpac)

vms_lpac_fc = Dict()
compute_vms_single_hour(vms_lpac_fc,BE_grid_lpac_check["761"],Results_lpac_fc)


for i in eachindex(vas_lpac)
    if i != "261"
        if i != "1343"
            println("$i => va OPF $(vas_lpac[i]), va BS $(vas_lpac_fc[i])")
        else
            println("$i => va OPF NOT HERE, va BS $(vas_lpac_fc[i])")
        end
    end
end

vas_lpac["261"]
Results_lpac["solution"]["bus"]["261"]
Results_lpac_fc["solution"]["bus"]["1342"]
Results_lpac_fc["solution"]["bus"]["1343"]

for i in eachindex(vms_lpac)
    if i != "261"
        if i != "1343"
            println("$i => vm OPF $(vms_lpac[i]), vm BS $(vms_lpac_fc[i])")
        else
            println("$i => vm OPF NOT HERE, vm BS $(vms_lpac_fc[i])")
        end
    end
end

function compute_diff_vas_single_hour(dict,grid,results)
    for (br_id,br) in grid["branch"]
        dict["$br_id"] = []
        f_bus = br["f_bus"]
        t_bus = br["t_bus"]
        dict["$br_id"] = abs(results["solution"]["bus"]["$f_bus"]["va"]-results["solution"]["bus"]["$t_bus"]["va"])
    end
end

function compute_diff_vms_single_hour(dict,grid,results)
    for (br_id,br) in grid["branch"]
        dict["$br_id"] = []
        f_bus = br["f_bus"]
        t_bus = br["t_bus"]
        dict["$br_id"] = abs((1-results["solution"]["bus"]["$f_bus"]["phi"])-(1-results["solution"]["bus"]["$t_bus"]["phi"]))
    end
end

diff_vas_lpac = Dict()
diff_vas_lpac_fc = Dict()
compute_diff_vas_single_hour(diff_vas_lpac,BE_grid_lpac,Results_lpac)
compute_diff_vas_single_hour(diff_vas_lpac_fc,BE_grid_lpac_check["761"],Results_lpac_fc)

diff_vms_lpac = Dict()
diff_vms_lpac_fc = Dict()
compute_diff_vms_single_hour(diff_vms_lpac,BE_grid_lpac,Results_lpac)
compute_diff_vms_single_hour(diff_vms_lpac_fc,BE_grid_lpac_check["761"],Results_lpac_fc)

#p -> lam_kcl_r
#q -> lam_kcl_i

Duals_fc = Dict()
for (b_id,b) in BE_grid_lpac_check["761"]["bus"]
    if !haskey(b,"auxiliary_bus")
        Duals_fc["$b_id"] = Dict()
        Duals_fc["$b_id"]["lam_kcl_i"] = Results_lpac_fc["solution"]["bus"]["$b_id"]["lam_kcl_i"]
        Duals_fc["$b_id"]["lam_kcl_r"] = Results_lpac_fc["solution"]["bus"]["$b_id"]["lam_kcl_r"]
    end
end
delete!(Duals_fc,"261")

Duals_fc
Results_lpac_fc["solution"]["bus"]["1"]["va"]

function compute_diff_duals_va_single_hour(dict,grid,results)
    for (br_id,br) in grid["branch"]
        dict["$br_id"] = []
        f_bus = br["f_bus"]
        t_bus = br["t_bus"]
        dict["$br_id"] = abs(results["solution"]["bus"]["$f_bus"]["lam_kcl_r"]-results["solution"]["bus"]["$t_bus"]["lam_kcl_r"])
    end
end

function compute_diff_duals_vm_single_hour(dict,grid,results)
    for (br_id,br) in grid["branch"]
        dict["$br_id"] = []
        f_bus = br["f_bus"]
        t_bus = br["t_bus"]
        dict["$br_id"] = abs(results["solution"]["bus"]["$f_bus"]["lam_kcl_i"]-results["solution"]["bus"]["$t_bus"]["lam_kcl_i"])
    end
end

diff_duals_va_lpac = Dict()
diff_duals_va_lpac_fc = Dict()
compute_diff_duals_va_single_hour(diff_duals_va_lpac_fc,BE_grid_lpac_check["761"],Results_lpac_fc)
compute_diff_duals_va_single_hour(diff_duals_va_lpac,BE_grid_lpac,Results_lpac["761"])

findmax(diff_duals_va_lpac)
findmax(diff_duals_va_lpac_fc)



diff_duals_vm_lpac = Dict()
diff_duals_vm_lpac_fc = Dict()
compute_diff_duals_vm_single_hour(diff_duals_vm_lpac_fc,BE_grid_lpac_check["761"],Results_lpac_fc)
compute_diff_duals_vm_single_hour(diff_duals_vm_lpac,BE_grid_lpac,Results_lpac["761"])

findmax(diff_duals_vm_lpac)
findmax(diff_duals_vm_lpac_fc)


Duals
Duals_fc

avg_nodal_price = abs(sum(Duals[b]["lam_kcl_i"] for b in eachindex(Duals)))
n_buses = length(Duals)
cong_index_single_node = Dict()
for b in eachindex(Duals)
    cong_index_single_node["$b"] = (Duals["$b"]["lam_kcl_i"] - avg_nodal_price)/avg_nodal_price
end
cong_index = sum(abs(Duals["$b"]["lam_kcl_i"] - avg_nodal_price) for b in eachindex(cong_index_single_node))/(avg_nodal_price*n_buses)


avg_nodal_price_fc = abs(sum(Duals_fc[b]["lam_kcl_i"] for b in eachindex(Duals_fc)))
n_buses_fc = length(Duals_fc)
cong_index_single_node_fc = Dict()
for b in eachindex(Duals_fc)
    cong_index_single_node_fc["$b"] = (Duals_fc["$b"]["lam_kcl_i"] - avg_nodal_price_fc)/avg_nodal_price_fc
end
cong_index_fc = sum(abs(Duals_fc["$b"]["lam_kcl_i"] - avg_nodal_price_fc) for b in eachindex(cong_index_single_node_fc))/(avg_nodal_price_fc*n_buses_fc)