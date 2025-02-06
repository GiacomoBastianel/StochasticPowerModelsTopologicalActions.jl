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

function fix_res_time_series_measured(grid,hour,zones,res_time_series,P_value)
    for zone in zones
        for (g_id,g) in grid["gen"]
            if g["zone"] == zone
                if g["type"] == "Onshore Wind" 
                    g["pmax"] = g["installed_capacity"]*res_time_series[zone]["Onshore_wind"][hour] #pu
                elseif g["type"] == "Offshore Wind" 
                    if zone == "BE00"
                        g["pmax"] = g["installed_capacity"]*P_value #pu
                    else
                        g["pmax"] = g["installed_capacity"]*res_time_series[zone]["Offshore_wind"][hour] #pu
                    end
                elseif g["type"] == "Solar PV" 
                    g["pmax"] = g["installed_capacity"]*res_time_series[zone]["Solar_PV"][hour] #pu
                end
            end
        end
    end
end

function add_scenarios_probabilities(scenarios_probabilities_dict,hour_wind,n_hours,n_scenarios,scenario_samples_dict)
    for i in 1:n_hours
        for j in 1:n_scenarios
            n = (i - 1)*n_scenarios + j
            scenarios_probabilities_dict["$n"] = scenario_samples_dict["$hour_wind"]["pdf_normalized"][j]
        end
    end
end

function create_RES_time_series_scenarios(grid,res_dict,scenario_samples_dict,n_scenarios,hours,hour_wind)
    for (g_id,g) in grid["gen"]
     res_dict[g_id] = Dict{String,Any}()
        for hour in hours
         res_dict[g_id]["$hour"] = Dict{String,Any}()
             if g["type"] == "Offshore Wind" && g["zone"] == "BE00"
                 for i in 1:n_scenarios
                     res_dict[g_id]["$hour"]["$i"] = Dict{String,Any}(
                         "pdf" => scenario_samples_dict["$hour_wind"]["pdf_normalized"][i], 
                         "samples_pu" => scenario_samples_dict["$hour_wind"]["samples_pu"][i])
                 end
             elseif g["type"] == "Offshore Wind" && g["zone"] != "BE00"
                 for i in 1:n_scenarios
                     res_dict[g_id]["$hour"]["$i"] = Dict{String,Any}(
                         "pdf" => scenario_samples_dict["$hour"]["pdf_normalized"][i], 
                         "samples_pu" => 1.0)
                 end
             else
                 for i in 1:n_scenarios
                     res_dict[g_id]["$hour"]["$i"] = Dict{String,Any}(
                         "pdf" => scenario_samples_dict["$hour"]["pdf_normalized"][i], 
                         "samples_pu" => 1.0)
                 end
             end
        end
    end
end

function add_load_time_series(grid, load_dict, load_input_dict, hours, n_scenarios)
    for (l_id,l) in grid["load"]
        load_dict[l_id] = Dict{String,Any}("$h" => Dict{String,Any}("$scenario" => Dict{String,Any}(
            "pd" => load_input_dict[l["zone"]]["pu"][h]) for scenario in 1:n_scenarios) for h in hours)
    end
end

function add_gen_time_series(grid, gen_dict, res_dict, hours, n_scenarios)
    for (g_id,g) in grid["gen"]
        gen_dict[g_id] = Dict{String,Any}("$h" => Dict{String,Any}("$scenario" => Dict{String,Any}(
            "Capacity_factor" => res_dict[g_id]["$h"]["$scenario"]["samples_pu"], 
            "pmax_hourly" => g["pmax"]*res_dict[g_id]["$h"]["$scenario"]["samples_pu"],
            "pmax" => g["pmax"]) for scenario in 1:n_scenarios) for h in hours)
    end
end

function generate_input_dict_stochastic_optimization(dict,gen_time_series,load_time_series,scenarios_probabilities)
    dict["gen"] = gen_time_series
    dict["load"] = load_time_series
    dict["scenario_probability"] = scenarios_probabilities
    return dict
end

function make_multinetwork_time_series_scenarios(
    sn_data::Dict{String,Any},n_scenarios,hours,hour_simulation,time_series::Dict{String,Any};
    global_keys = ["dim","name","per_unit","source_type","source_version"],
    check_dim::Bool = true,
    )

    mn_data = Dict{String,Any}("nw"=>Dict{String,Any}())
    _FP._add_mn_global_values!(mn_data, sn_data, global_keys)
    #template_nw = _make_template_nw(sn_data, global_keys)
    for hour in 1:length(hours)
        for scenario_idx in 1:n_scenarios
            n = (hour - 1)*n_scenarios + scenario_idx
            mn_data["nw"]["$n"] = deepcopy(sn_data)#_build_nw(template_nw, sn_data, time_series_idx; share_data = true)
            delete!(mn_data["nw"]["$n"],"dim")
            add_hour_scenario_probability(mn_data,hour,scenario_idx,n,time_series)
            for (g_id,g) in mn_data["nw"]["$n"]["gen"]
                mn_data["nw"]["$n"]["gen"][g_id]["pmax"] = time_series["gen"][g_id]["$hour_simulation"]["$scenario_idx"]["pmax_hourly"]
            end
            for (l_id,l) in mn_data["nw"]["$n"]["load"]
                mn_data["nw"]["$n"]["load"][l_id]["pd"] = time_series["load"][l_id]["$hour_simulation"]["$scenario_idx"]["pd"]
            end
        end
    end
    return mn_data
end

function add_hour_scenario_probability(data,hour,scenario,index,time_series)
    data["nw"]["$index"]["hour"] = hour
    data["nw"]["$index"]["scenario"] = scenario
    data["nw"]["$index"]["hour_scenario_index"] = [hour,scenario,index]
    data["nw"]["$index"]["probability"] = time_series["scenario_probability"]["$index"]
end