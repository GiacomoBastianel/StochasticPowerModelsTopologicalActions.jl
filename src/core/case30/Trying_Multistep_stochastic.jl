#### Run_multistep_stochastic.jl first to have the full data

forecasted_wind     = JSON.parsefile(joinpath(@__DIR__,"forecasted_wind.json")    )     
measured_wind       = JSON.parsefile(joinpath(@__DIR__,"measured_wind.json")      )    
expected_value_wind = JSON.parsefile(joinpath(@__DIR__,"expected_value_wind.json")) 
scenarios_wind      = JSON.parsefile(joinpath(@__DIR__,"scenarios_wind.json")     )


result_1 = _PMTP.run_acdcsw_AC_big_M(test_case_bs_mn_expected_sp["nw"]["1"],LPACCPowerModel,gurobi_opf; setting = s)
result_2 = _PMTP.run_acdcsw_AC_big_M(test_case_bs_mn_expected_sp["nw"]["2"],LPACCPowerModel,gurobi_opf; setting = s)
result_3 = _PMTP.run_acdcsw_AC_big_M(test_case_bs_mn_expected_sp["nw"]["3"],LPACCPowerModel,gurobi_opf; setting = s)
result_4 = _PMTP.run_acdcsw_AC_big_M(test_case_bs_mn_expected_sp["nw"]["4"],LPACCPowerModel,gurobi_opf; setting = s)


result_5 = _PMTP.run_acdcsw_AC_big_M(test_case_bs_mn_expected_sp["nw"]["5"],LPACCPowerModel,gurobi_opf; setting = s)
result_6 = _PMTP.run_acdcsw_AC_big_M(test_case_bs_mn_expected_sp["nw"]["6"],LPACCPowerModel,gurobi_opf; setting = s)

result_7 = _PMTP.run_acdcsw_AC_big_M(test_case_bs_mn_expected_sp["nw"]["7"],LPACCPowerModel,gurobi_opf; setting = s)
result_8 = _PMTP.run_acdcsw_AC_big_M(test_case_bs_mn_expected_sp["nw"]["8"],LPACCPowerModel,gurobi_opf; setting = s)



result_9 = _PMTP.run_acdcsw_AC_big_M(test_case_bs_mn_expected_sp["nw"]["9"],LPACCPowerModel,gurobi_opf; setting = s)
result_13 = _PMTP.run_acdcsw_AC_big_M(test_case_bs_mn_expected_sp["nw"]["13"],LPACCPowerModel,gurobi_opf; setting = s)


function print_switches(results,data)
    t_buses = unique(data["switch"]["$sw_id"]["t_bus"] for sw_id in 1:length(data["switch"]))
    count_t_bus_1 = 0
    count_t_bus_2 = 0
    for sw_id in 1:length(data["switch"])
        if haskey(data["switch"]["$sw_id"],"auxiliary")
            println("Switch ID: ", sw_id, " | Status: ", results["solution"]["switch"]["$sw_id"]["status"]," | Auxiliary: ", data["switch"]["$sw_id"]["auxiliary"]," | Original: ", data["switch"]["$sw_id"]["original"]," | t_bus: ", data["switch"]["$sw_id"]["t_bus"])
            if data["switch"]["$sw_id"]["t_bus"] == t_buses[1] && results["solution"]["switch"]["$sw_id"]["status"] == 1
                count_t_bus_1 += 1
            elseif data["switch"]["$sw_id"]["t_bus"] == t_buses[2] && results["solution"]["switch"]["$sw_id"]["status"] == 1
                count_t_bus_2 += 1
            end
        else
            println("Switch ID: ", sw_id, " | Status: ", results["solution"]["switch"]["$sw_id"]["status"])
        end
    end
    println("--------------------------------------------------")
    println("Switches connected to t_bus ", t_buses[1], "  is ", count_t_bus_1)
    println("Switches connected to t_bus ", t_buses[2], "  is ", count_t_bus_2)
end
print_switches(result_1, test_case_bs_mn_expected_sp["nw"]["5"])
print_switches(result_2, test_case_bs_mn_expected_sp["nw"]["6"])
print_switches(result_3, test_case_bs_mn_expected_sp["nw"]["5"])
print_switches(result_4, test_case_bs_mn_expected_sp["nw"]["6"])

print_switches(result_5, test_case_bs_mn_expected_sp["nw"]["5"])
print_switches(result_6, test_case_bs_mn_expected_sp["nw"]["6"])
print_switches(result_7, test_case_bs_mn_expected_sp["nw"]["9"])
print_switches(result_8, test_case_bs_mn_expected_sp["nw"]["13"])


for (br_id,br) in test_case_opf["branch"]
    if br["f_bus"] == 6 || br["t_bus"] == 6
        println("Branch $br_id, f_bus: ", br["f_bus"], ", t_bus: ", br["t_bus"])
    end
end 