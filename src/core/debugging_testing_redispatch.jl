# Uploading results

hourly_opf_forecasted           = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Hourly_opf_forecasted_$(first_hour)_$(last_hour).json"))
hourly_bs_forecasted           = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Hourly_bs_forecasted_$(first_hour)_$(last_hour).json"))
one_topology_forecasted  = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","24_hours_BS_one_topology_forecasted_$(first_hour)_$(last_hour).json"))
one_switching_action_forecasted  = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","One_maximum_actions_24_hours_forecasted_$(first_hour)_$(last_hour).json"))
two_switching_action_forecasted  = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","Two_maximum_actions_24_hours_forecasted_$(first_hour)_$(last_hour).json"))

# Uploading results fc
fc_one_sw_forecasted_debugging       = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","fc_one_sw_forecasted_$(first_hour)_$(last_hour).json"))
fc_two_sw_forecasted_debugging       = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","fc_two_sw_forecasted_$(first_hour)_$(last_hour).json"))
fc_one_topology_forecasted_debugging = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","fc_one_topology_forecasted_$(first_hour)_$(last_hour).json"))
hourly_fc_forecasted_debugging       = JSON.parsefile(joinpath(results_folder,"case_30","stochastic_multistep","hourly_fc_forecasted_$(first_hour)_$(last_hour).json"))


function compute_total_pg_cost(grid,results,n_hours)
    cost_vector = []
    for hour in 1:n_hours
        cost = 0.0
        for (g_id,g) in grid["gen"]
            if haskey(results,"$hour")
                if haskey(results["$hour"]["solution"]["gen"],"$g_id") && length(g["cost"]) > 1
                    cost += results["$hour"]["solution"]["gen"]["$g_id"]["pg"]*g["cost"][end-1]
                end
            else
                if haskey(results["solution"]["nw"]["$hour"]["gen"],"$g_id") && length(g["cost"]) > 1
                    cost += results["solution"]["nw"]["$hour"]["gen"]["$g_id"]["pg"]*g["cost"][end-1]
                end
            end
        end
        push!(cost_vector,cost)
    end 
    return cost_vector       
end

cost_vector_hourly_bs_forecasted_debugging    = compute_total_pg_cost(test_case_opf,fc_one_sw_forecasted_debugging      ,n_hours)
cost_vector_one_topology_forecasted_debugging = compute_total_pg_cost(test_case_opf,fc_two_sw_forecasted_debugging      ,n_hours)
cost_vector_one_sw_forecasted_debugging       = compute_total_pg_cost(test_case_opf,fc_one_topology_forecasted_debugging,n_hours)
cost_vector_two_sw_forecasted_debugging       = compute_total_pg_cost(test_case_opf,hourly_fc_forecasted_debugging      ,n_hours)




[hourly_opf_forecasted["$hour"]["solution"]["gen"]["1"]["pg"] for hour in 1:n_hours]
[fc_one_sw_forecasted_debugging["$hour"]["solution"]["gen"]["1"]["pg"] for hour in 1:n_hours]






sum(hourly_fc_forecasted["$hour"]["objective"] for hour in 1:24)
sum(fc_one_sw_forecasted["$hour"]["objective"] for hour in 1:24)
sum(fc_two_sw_forecasted["$hour"]["objective"] for hour in 1:24)
sum(fc_one_topology_forecasted["$hour"]["objective"] for hour in 1:24)


hourly_redispatch_forecasted = _SPMTA.run_hourly_redispatch_fc(test_case_bs_mn_measured,hourly_bs_forecasted,hourly_fc_forecasted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
redispatch_one_topology_forecasted = _SPMTA.run_hourly_redispatch_one_topology_fc(test_case_bs_mn_measured,one_topology_forecasted,fc_one_topology_forecasted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
redispatch_one_sw_forecasted = _SPMTA.run_hourly_redispatch_one_topology_fc(test_case_bs_mn_measured,one_switching_action_forecasted,fc_one_sw_forecasted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
redispatch_two_sw_forecasted = _SPMTA.run_hourly_redispatch_one_topology_fc(test_case_bs_mn_measured,two_switching_action_forecasted,fc_two_sw_forecasted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)

####################
# -> OPF
function run_hourly_redispatch_opf(grid, result_opf, model, optimizer,settings)
    result_feasibility_checks = Dict{String,Any}()
    for hour in 1:length(grid["nw"])
        result_feasibility_checks["$hour"] = Dict{String,Any}()
        feasibility_check = deepcopy(grid["nw"]["$hour"])
        feasibility_check_input = deepcopy(grid["nw"]["$hour"])
        #_PMTP.prepare_AC_feasibility_check(result_opf["$hour"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)

        # Adding set points
        for (g_id,g) in feasibility_check["gen"]
            g["pg_start"] = result_opf["$hour"]["solution"]["gen"][g_id]["pg"]
            g["qg_start"] = result_opf["$hour"]["solution"]["gen"][g_id]["qg"]
            if length(g["cost"]) > 1
                g["redispatch_cost_up"] = g["cost"][1]
                g["redispatch_cost_down"] = g["cost"][1]
            elseif length(g["cost"]) <= 1
                g["redispatch_cost_up"] = 0.0
                g["redispatch_cost_down"] = 0.0
            end
            #if g_id == "1"
            #    g["redispatch_cost_up"] = 10.0
            #    g["redispatch_cost_down"] = 10.0
            #    #println("Generator 1 has a cost up of $(g["redispatch_cost_up"])")
            #    #println("Generator 1 has a cost down of $(g["redispatch_cost_down"])")
            #end
        end

        result_feasibility_checks["$hour"] = _SPMTA.solve_acdc_full_redispatch_opf(feasibility_check,model,optimizer)
    end
    return result_feasibility_checks
end

function run_hourly_redispatch_opf_stochastic(grid, stochastic_grid, result_opf, model, optimizer,settings)
    result_feasibility_checks = Dict{String,Any}()
    for hour in 1:n_hours
        for s in 1:n_scenarios
            # This has to include all the scenarios
            timestep = (hour - 1)*n_scenarios + s
            result_feasibility_checks["$timestep"] = Dict{String,Any}()
            feasibility_check = deepcopy(grid["nw"]["$hour"])
            feasibility_check_input = deepcopy(grid["nw"]["$hour"])
            # Adding set points
            for (g_id,g) in feasibility_check["gen"]
                g["pg_start"] = result_opf["$timestep"]["solution"]["gen"][g_id]["pg"]
                g["qg_start"] = result_opf["$timestep"]["solution"]["gen"][g_id]["qg"]
                if length(g["cost"]) > 1 
                    g["redispatch_cost_up"] = g["cost"][1]
                    g["redispatch_cost_down"] = g["cost"][1]
                elseif length(g["cost"]) < 1
                    g["redispatch_cost_up"] = 0.0
                    g["redispatch_cost_down"] = 0.0
                end
                #if g_id == "1"
                #    g["redispatch_cost_up"] = 10.0
                #    g["redispatch_cost_down"] = 10.0
                #    #println("Generator 1 has a cost up of $(g["redispatch_cost_up"])")
                #    #println("Generator 1 has a cost down of $(g["redispatch_cost_down"])")
                #end
            end
            result_feasibility_checks["$timestep"] = _SPMTA.solve_acdc_full_redispatch_opf(feasibility_check,model,optimizer)
            result_feasibility_checks["$timestep"]["probability"] = stochastic_grid["nw"]["$timestep"]["probability"]
        end
    end    
    return result_feasibility_checks
end

redispatch_opf_forecasted           = run_hourly_redispatch_opf(test_case_opf_mn_measured,hourly_opf_forecasted          ,ACPPowerModel,ipopt,s)

sum(redispatch_opf_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(redispatch_one_sw_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(redispatch_two_sw_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(redispatch_one_topology_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(hourly_redispatch_forecasted["$hour"]["objective"] for hour in 1:n_hours)

function print_gen_redispatch(grid,results,n_hours)
    for hour in 1:n_hours
        println("------------------------")
        println("Hour: $hour")
        println("Objective: $(results["$hour"]["objective"])")
        println("------------------------")
        for (g_id,g) in grid["gen"]
            if results["$hour"]["solution"]["gen"][g_id]["pg_up"] > 10^(-4)
                println("Generator $g_id: pg_up = $(results["$hour"]["solution"]["gen"][g_id]["pg_up"])")
            end
            if results["$hour"]["solution"]["gen"][g_id]["pg_down"] > 10^(-4)
                println("Generator $g_id: pg_down = $(results["$hour"]["solution"]["gen"][g_id]["pg_down"])")
            end
        end
    end
end

print_gen_redispatch(test_case_opf,redispatch_opf_forecasted,12)
print_gen_redispatch(test_case_opf,hourly_redispatch_measured,n_hours)

[redispatch_opf_forecasted["$h"]["solution"]["gen"]["1"]["pg_up"] for h in 1:n_hours]
[redispatch_opf_forecasted["$h"]["solution"]["gen"]["1"]["pg_down"] for h in 1:n_hours]


redispatch_opf_forecasted["2"]["solution"]["gen"]["1"]["pg_up"]*test_case_opf["gen"]["1"]["cost"][1]
redispatch_opf_forecasted["2"]["solution"]["gen"]["1"]["pg_down"]*test_case_opf["gen"]["1"]["cost"][1]

redispatch_opf_forecasted["2"]["solution"]["gen"]["2"]["pg_up"]  *test_case_opf["gen"]["2"]["cost"][1]
redispatch_opf_forecasted["2"]["solution"]["gen"]["2"]["pg_down"]*test_case_opf["gen"]["2"]["cost"][1]

test_case_opf["gen"]["2"]["pmax"]
hourly_opf_forecasted["12"]["solution"]["gen"]["2"]["pg"]
redispatch_opf_scenarios_4["12"]["solution"]["gen"]["1"]["pg_up"]
redispatch_opf_scenarios_4["12"]["solution"]["gen"]["1"]["pg_down"]  
redispatch_opf_forecasted["12"]["solution"]["gen"]["2"]["pg_down"]


using StatsBase

solutions = [redispatch_opf_scenarios_4_adjusted["$h"]["termination_status"] for h in 1:(n_hours*n_scenarios)]

countmap(solutions)


###########################################


sum(hourly_opf_forecasted["$hour"]["objective"] for hour in 1:n_hours)      #+ sum(redispatch_opf_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_one_sw_forecasted["$hour"]["objective"] for hour in 1:n_hours)       #+ sum(redispatch_one_sw_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_two_sw_forecasted["$hour"]["objective"] for hour in 1:n_hours)       #+ sum(redispatch_two_sw_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(fc_one_topology_forecasted["$hour"]["objective"] for hour in 1:n_hours) #+ sum(redispatch_one_topology_forecasted["$hour"]["objective"] for hour in 1:n_hours)
sum(hourly_fc_forecasted["$hour"]["objective"] for hour in 1:n_hours)       #+ sum(hourly_redispatch_forecasted["$hour"]["objective"] for hour in 1:n_hours)

print_gen_redispatch(test_case_opf,redispatch_one_topology_forecasted,12)
