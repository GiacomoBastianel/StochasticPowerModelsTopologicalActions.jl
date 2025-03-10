function compute_gen_capacity_stochastic_multistep(data,results,start_hour,end_hour,dict_nw,dict_hour,n_hours,n_scenarios)
    gen_type = []
    for (g_id,g) in data["nw"]["1"]["gen"]
        push!(gen_type,g["type"])
    end
    types = unique(gen_type)

    for nw in 1:(n_hours*n_scenarios)
        dict_nw["$nw"] = Dict{String,Any}()
        for t in types
            dict_nw["$nw"]["$t"] = 0
        end
        for t in types
            for (g_id,g) in data["nw"]["$nw"]["gen"]
                if g["type"] == t
                    dict_nw["$nw"]["$t"] += results["solution"]["nw"]["$nw"]["gen"][g_id]["pg"]
                end
            end
        end
    end
    for h in 1:n_hours
        dict_hour["$h"] = Dict{String,Any}()
        for t in types
            dict_hour["$h"]["$t"] = 0
        end
        for scenario_idx in 1:n_scenarios
            nw = (h - 1)*n_scenarios + scenario_idx
            for t in types
                dict_hour["$h"]["$t"] += dict_nw["$nw"]["$t"]*data["nw"]["$nw"]["probability"]
            end
        end
    end
end

function compute_gen_capacity_stochastic_zone(data,results,start_hour,end_hour,zones,dict_nw,dict_hour,n_hours,n_scenarios)
    gen_type = []
    for (g_id,g) in data["nw"]["1"]["gen"]
        push!(gen_type,g["type"])
    end
    types = unique(gen_type)
    for nw in 1:(n_hours*n_scenarios)
        dict_nw["$nw"] = Dict{String,Any}()
        for zone in zones
            dict_nw["$nw"]["$zone"] = Dict{String,Any}()
            gen_type = []

            for t in types
                dict_nw["$nw"]["$zone"]["$t"] = 0
            end
            for t in types
                for (g_id,g) in data["nw"]["$nw"]["gen"]
                    if g["zone"] == zone && g["type"] == t
                        dict_nw["$nw"]["$zone"]["$t"] += results["solution"]["nw"]["$nw"]["gen"][g_id]["pg"]
                    end
                end
            end
        end
    end
    for h in 1:n_hours
        dict_hour["$h"] = Dict{String,Any}()
        for zone in zones
            dict_hour["$h"]["$zone"] = Dict{String,Any}()
            for t in types
                dict_hour["$h"]["$zone"]["$t"] = 0
            end
            for scenario_idx in 1:n_scenarios
                nw = (h - 1)*n_scenarios + scenario_idx
                for t in types
                    dict_hour["$h"]["$zone"]["$t"] += dict_nw["$nw"]["$zone"]["$t"]*data["nw"]["$nw"]["probability"]
                end
            end
        end
    end
end


function add_hour_scenario_probability_tyndp_scenario(data,hour,index,scenario_idx,time_series,start_hour_simulation)
    nw_hour = hour - start_hour_simulation + 1
    data["nw"]["$index"]["hour"] = nw_hour
    data["nw"]["$index"]["hour_original"] = hour
    data["nw"]["$index"]["scenario"] = scenario_idx
    data["nw"]["$index"]["hour_scenario_index"] = [nw_hour,scenario_idx]
    data["nw"]["$index"]["probability"] = time_series["scenario_probability"]["$hour"][scenario_idx]
end

function make_multinetwork_time_series_tyndp_scenarios(
    sn_data::Dict{String,Any},n_hours,n_scenarios,start_hour_simulation,end_hour_simulation,time_series,zones;
    global_keys = ["hours","scenarios","name","per_unit","source_type","source_version"],
    check_dim::Bool = true,
    )

    mn_data = Dict{String,Any}("nw"=>Dict{String,Any}())
    _FP._add_mn_global_values!(mn_data, sn_data, global_keys)
    #template_nw = _make_template_nw(sn_data, global_keys)
    for hour in start_hour_simulation:end_hour_simulation
        nw_hour = hour - start_hour_simulation + 1
        for scenario_idx in 1:n_scenarios
            n = (nw_hour - 1)*n_scenarios + scenario_idx
            mn_data["nw"]["$n"] = deepcopy(sn_data)#_build_nw(template_nw, sn_data, time_series_idx; share_data = true)
            add_hour_scenario_probability_tyndp_scenario(mn_data,hour,n,scenario_idx,time_series,start_hour_simulation)
            fix_hourly_load_nw(mn_data["nw"]["$n"],hour,zones,time_series,scenario_idx) 
            fix_gen_time_series_nw(mn_data["nw"]["$n"],hour,zones,time_series,scenario_idx)
        end
    end
    mn_data["scenarios"] = n_scenarios
    mn_data["hours"] = n_hours
    return mn_data
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

function create_RES_time_series(grid,res_dict,scenario_samples_dict,n_scenarios,start_hour_simulation,end_hour_simulation)
    count_ = 0
    for (g_id,g) in grid["gen"]
        res_dict[g_id] = Dict{String,Any}()
        for i in start_hour_simulation:end_hour_simulation
            hour = i - start_hour_simulation + 1
            res_dict[g_id]["$i"] = Dict{String,Any}()
            if n_scenarios > 1
                if g["type"] == "Offshore Wind" && g["zone"] == "BE00"
                    res_dict[g_id]["$i"]["P50_11hforecast_pu"] = scenario_samples_dict["$i"]["P50_11hforecast_pu"]
                    res_dict[g_id]["$i"]["most_recent_forecast_pu"] = scenario_samples_dict["$i"]["most_recent_forecast_pu"]
                    res_dict[g_id]["$i"]["measured_pu"] = scenario_samples_dict["$i"]["measured_pu"]
                    res_dict[g_id]["$i"]["pdf"] = []
                    res_dict[g_id]["$i"]["samples_pu"] = []
                    for s in 1:n_scenarios
                       push!(res_dict[g_id]["$i"]["pdf"],scenario_samples_dict["$i"]["pdf_normalized"][s])
                       push!(res_dict[g_id]["$i"]["samples_pu"],scenario_samples_dict["$i"]["samples_pu"][s])
                    end
                elseif g["type"] == "Offshore Wind" && g["zone"] != "BE00"
                    res_dict[g_id]["$i"]["P50_11hforecast_pu"] = scenario_samples_dict["$i"]["P50_11hforecast_pu"]
                    res_dict[g_id]["$i"]["most_recent_forecast_pu"] = scenario_samples_dict["$i"]["most_recent_forecast_pu"]
                    res_dict[g_id]["$i"]["measured_pu"] = scenario_samples_dict["$i"]["measured_pu"]
                    res_dict[g_id]["$i"]["pdf"] = []
                    res_dict[g_id]["$i"]["samples_pu"] = []
                    for s in 1:n_scenarios
                        push!(res_dict[g_id]["$i"]["pdf"],scenario_samples_dict["$i"]["pdf_normalized"][s])
                        push!(res_dict[g_id]["$i"]["samples_pu"],1.0)
                    end
                else
                    res_dict[g_id]["$i"]["P50_11hforecast_pu"] = scenario_samples_dict["$i"]["P50_11hforecast_pu"]
                    res_dict[g_id]["$i"]["most_recent_forecast_pu"] = scenario_samples_dict["$i"]["most_recent_forecast_pu"]
                    res_dict[g_id]["$i"]["measured_pu"] = scenario_samples_dict["$i"]["measured_pu"]
                    res_dict[g_id]["$i"]["pdf"] = []
                    res_dict[g_id]["$i"]["samples_pu"] = []
                    for s in 1:n_scenarios
                        push!(res_dict[g_id]["$i"]["pdf"],scenario_samples_dict["$i"]["pdf_normalized"][s])
                        push!(res_dict[g_id]["$i"]["samples_pu"],1.0)
                    end
                end
            else
                if g["type"] == "Offshore Wind" && g["zone"] == "BE00"
                    res_dict[g_id]["$i"]["P50_11hforecast_pu"] = scenario_samples_dict["$i"]["P50_11hforecast_pu"]
                    res_dict[g_id]["$i"]["most_recent_forecast_pu"] = scenario_samples_dict["$i"]["most_recent_forecast_pu"]
                    res_dict[g_id]["$i"]["measured_pu"] = scenario_samples_dict["$i"]["measured_pu"]
                    res_dict[g_id]["$i"]["pdf"] = 1.0
                    res_dict[g_id]["$i"]["samples_pu"] = 1.0
                elseif g["type"] == "Offshore Wind" && g["zone"] != "BE00"
                    res_dict[g_id]["$i"]["P50_11hforecast_pu"] = scenario_samples_dict["$i"]["P50_11hforecast_pu"]
                    res_dict[g_id]["$i"]["most_recent_forecast_pu"] = scenario_samples_dict["$i"]["most_recent_forecast_pu"]
                    res_dict[g_id]["$i"]["measured_pu"] = scenario_samples_dict["$i"]["measured_pu"]
                    res_dict[g_id]["$i"]["pdf"] = 1.0
                    res_dict[g_id]["$i"]["samples_pu"] = 1.0
                else
                    res_dict[g_id]["$i"]["P50_11hforecast_pu"] = scenario_samples_dict["$i"]["P50_11hforecast_pu"]
                    res_dict[g_id]["$i"]["most_recent_forecast_pu"] = scenario_samples_dict["$i"]["most_recent_forecast_pu"]
                    res_dict[g_id]["$i"]["measured_pu"] = scenario_samples_dict["$i"]["measured_pu"]
                    res_dict[g_id]["$i"]["pdf"] = 1.0
                    res_dict[g_id]["$i"]["samples_pu"] = 1.0
                end
            end
        end
    end
end

function create_gen_time_series_tyndp_scenario(grid,res_dict,RES_time_series, start_hour_simulation, end_hour_simulation)
    for (g_id,g) in grid["gen"]
        res_dict[g_id] = Dict{String,Any}()
        for i in start_hour_simulation:end_hour_simulation
            res_dict[g_id]["$i"] = Dict{String,Any}()
            if g["type"] == "Offshore Wind" && g["zone"] == "BE00"
                res_dict[g_id]["$i"]["capacity_factor"] = RES_time_series["BE00"]["Offshore_wind"][i]
            elseif g["type"] == "Offshore Wind" && g["zone"] != "UK00"
                res_dict[g_id]["$i"]["capacity_factor"] = RES_time_series["UK00"]["Offshore_wind"][i]
            elseif g["type"] == "Offshore Wind" && g["zone"] != "FR00"
                res_dict[g_id]["$i"]["capacity_factor"] = RES_time_series["FR00"]["Offshore_wind"][i]
            elseif g["type"] == "Onshore Wind" && g["zone"] == "BE00"
                res_dict[g_id]["$i"]["capacity_factor"] = RES_time_series["BE00"]["Onshore_wind"][i]
            elseif g["type"] == "Onshore Wind" && g["zone"] != "UK00"
                res_dict[g_id]["$i"]["capacity_factor"] = RES_time_series["UK00"]["Onshore_wind"][i]
            elseif g["type"] == "Onshore Wind" && g["zone"] != "FR00"
                res_dict[g_id]["$i"]["capacity_factor"] = RES_time_series["FR00"]["Onshore_wind"][i]
            elseif g["type"] == "Solar PV" && g["zone"] == "BE00"
                res_dict[g_id]["$i"]["capacity_factor"] = RES_time_series["BE00"]["Solar_PV"][i]
            elseif g["type"] == "Solar PV" && g["zone"] != "UK00"
                res_dict[g_id]["$i"]["capacity_factor"] = RES_time_series["UK00"]["Solar_PV"][i]
            elseif g["type"] == "Solar PV" && g["zone"] != "FR00"
                res_dict[g_id]["$i"]["capacity_factor"] = RES_time_series["FR00"]["Solar_PV"][i]
            else
                res_dict[g_id]["$i"]["capacity_factor"] = 1.0
            end
        end
    end
end

function create_gen_time_series_tyndp_scenarios(grid,res_dict, wind_data, RES_time_series, start_hour_simulation, end_hour_simulation, n_scenarios)
    for (g_id,g) in grid["gen"]
        res_dict[g_id] = Dict{String,Any}()
        for i in start_hour_simulation:end_hour_simulation
            res_dict[g_id]["$i"] = Dict{String,Any}()
            for scenario_idx in 1:n_scenarios
                res_dict[g_id]["$i"]["$scenario_idx"] = Dict{String,Any}()
                if g["type"] == "Offshore Wind" && g["zone"] == "BE00"
                    res_dict[g_id]["$i"]["$scenario_idx"]["capacity_factor"] = wind_data["$i"]["samples_pu"][scenario_idx]
                elseif g["type"] == "Offshore Wind" && g["zone"] != "UK00"
                    res_dict[g_id]["$i"]["$scenario_idx"]["capacity_factor"] = RES_time_series["UK00"]["Offshore_wind"][i]
                elseif g["type"] == "Offshore Wind" && g["zone"] != "FR00"
                    res_dict[g_id]["$i"]["$scenario_idx"]["capacity_factor"] = RES_time_series["FR00"]["Offshore_wind"][i]
                elseif g["type"] == "Onshore Wind" && g["zone"] == "BE00"
                    res_dict[g_id]["$i"]["$scenario_idx"]["capacity_factor"] = RES_time_series["BE00"]["Onshore_wind"][i]
                elseif g["type"] == "Onshore Wind" && g["zone"] != "UK00"
                    res_dict[g_id]["$i"]["$scenario_idx"]["capacity_factor"] = RES_time_series["UK00"]["Onshore_wind"][i]
                elseif g["type"] == "Onshore Wind" && g["zone"] != "FR00"
                    res_dict[g_id]["$i"]["$scenario_idx"]["capacity_factor"] = RES_time_series["FR00"]["Onshore_wind"][i]
                elseif g["type"] == "Solar PV" && g["zone"] == "BE00"
                    res_dict[g_id]["$i"]["$scenario_idx"]["capacity_factor"] = RES_time_series["BE00"]["Solar_PV"][i]
                elseif g["type"] == "Solar PV" && g["zone"] != "UK00"
                    res_dict[g_id]["$i"]["$scenario_idx"]["capacity_factor"] = RES_time_series["UK00"]["Solar_PV"][i]
                elseif g["type"] == "Solar PV" && g["zone"] != "FR00"
                    res_dict[g_id]["$i"]["$scenario_idx"]["capacity_factor"] = RES_time_series["FR00"]["Solar_PV"][i]
                else
                    res_dict[g_id]["$i"]["$scenario_idx"]["capacity_factor"] = 1.0
                end
            end
        end
    end
end

function add_load_time_series_tyndp_scenario(grid, load_dict, load_input_dict, start_hour_simulation, end_hour_simulation, n_scenarios)
    for (l_id,l) in grid["load"]
        load_dict[l_id] = Dict{String,Any}("$h" => Dict{String,Any}("$scenario" => Dict{String,Any}(
            "pd" => load_input_dict[l["zone"]]["pu"][h]) for scenario in 1:n_scenarios) for h in start_hour_simulation:end_hour_simulation)
    end
end

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
                    b["phi_starting_value"] = 1.0
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

function generate_input_dict_stochastic_optimization(dict,gen_time_series,load_time_series,start_hour_simulation,end_hour_simulation,scenario_data)
    dict["gen"] = gen_time_series
    dict["load"] = load_time_series
    dict["scenario_probability"] = Dict{String,Any}()
    for i in start_hour_simulation:end_hour_simulation
        dict["scenario_probability"]["$i"] = deepcopy(scenario_data["$i"]["pdf_normalized"])
    end
    return dict
end

function run_stochastic_acdcsw_AC_ZIL_hourly(grid, model, optimizer, n_hours, n_scenarios,result; setting = s)
    for hour in 1:n_hours
        scenarios_hour = collect(((hour-1)*n_scenarios + 1):(hour*n_scenarios))
        grid_hour = deepcopy(grid)
        grid_hour["hours"] = 1
        grid_hour["nw"]= Dict{String,Any}()
        for i in scenarios_hour
            grid_hour["nw"]["$i"] = deepcopy(grid["nw"]["$i"])
        end    
        result["$hour"] = run_stochastic_acdcsw_AC_ZIL_hourly(grid_hour,model,optimizer; setting = setting)
    end
    return result
end

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