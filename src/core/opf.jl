function hourly_opf(grid,hour_start,hour_end,zones,load_time_series,res_time_series,s,optimizer,formulation)
    results = Dict()
    hourly_grid = deepcopy(grid)
    for hour in hour_start:hour_end
        fix_hourly_load(hourly_grid,hour,zones,load_time_series) 
        fix_res_time_series(hourly_grid,hour,zones,res_time_series)
        hourly_results = _PMACDC.run_acdcopf(hourly_grid,formulation, optimizer; setting = s)
        results["$hour"] = deepcopy(hourly_results)
    end
    return results
end

function hourly_opf_nw(grid,hour_start,hour_end,zones,load_time_series,res_time_series,s,optimizer,formulation)
    results = Dict()
    hourly_grid = deepcopy(grid)
    for hour in hour_start:hour_end
        fix_hourly_load(hourly_grid,hour,zones,load_time_series) 
        fix_res_time_series(hourly_grid,hour,zones,res_time_series)
        hourly_results = _PMACDC.run_acdcopf(hourly_grid,formulation, optimizer; setting = s)
        results["$hour"] = deepcopy(hourly_results)
    end
    return results
end

function hourly_opf_measured(grid,hour_start,hour_end,zones,load_time_series,res_time_series,s,optimizer,formulation,measured_pu)
    results = Dict()
    hourly_grid = deepcopy(grid)
    for hour in hour_start:hour_end
        fix_hourly_load(hourly_grid,hour,zones,load_time_series) 
        fix_res_time_series_measured(hourly_grid,hour,zones,res_time_series,measured_pu)
        hourly_results = _PMACDC.run_acdcopf(hourly_grid,formulation, optimizer; setting = s)
        results["$hour"] = deepcopy(hourly_results)
    end
    return results
end


function hourly_opf_scenarios(grid,hours,zones,load_time_series,res_time_series,P_value,s,optimizer,formulation)
    results = Dict()
    hourly_grid = deepcopy(grid)
    for hour in hours
        fix_hourly_load(hourly_grid,hour,zones,load_time_series) 
        fix_res_time_series_measured(hourly_grid,hour,zones,res_time_series,P_value)
        hourly_results = _PMTP.run_acdcopf(hourly_grid,formulation, optimizer; setting = s)
        results["$hour"] = deepcopy(hourly_results)
    end
    return results
end

function hourly_feasibility_check_bs_scenarios(grid,results_bs,switches_couples,extremes_ZILs,hours,zones,load_time_series,res_time_series,P_value,optimizer,formulation,opf_grid,s)
    results = Dict()
    hourly_grid = deepcopy(grid)
    grid_check = Dict{String,Any}()
    for hour in hours
        fix_hourly_load(hourly_grid,hour,zones,load_time_series) 
        fix_res_time_series_measured(hourly_grid,hour,zones,res_time_series,P_value)
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

function hourly_feasibility_check_bs_scenarios_stochastic(grid,results_bs,switches_couples,extremes_ZILs,hours,zones,load_time_series,res_time_series,P_value,optimizer,formulation,opf_grid,s,hour_scenario)
    results = Dict()
    hourly_grid = deepcopy(grid)
    grid_check = Dict{String,Any}()
    for hour in hours
        fix_hourly_load(hourly_grid,hour,zones,load_time_series) 
        fix_res_time_series_measured(hourly_grid,hour,zones,res_time_series,P_value)
        prepare_AC_feasibility_check_hourly_stochastic(results_bs,hourly_grid,hourly_grid,switches_couples,extremes_ZILs,opf_grid,hour,hour_scenario)
        hourly_results = _PMACDC.run_acdcopf(hourly_grid,formulation,optimizer; setting = s)
        results["$hour"] = deepcopy(hourly_results)
        grid_check["$hour"] = deepcopy(hourly_grid)
    end
    return results, grid_check
end

function prepare_AC_feasibility_check_hourly_stochastic(result_dict, input_dict, input_ac_check, switch_couples, extremes_dict,input_base,hour,hour_scenario)    
    orig_buses = maximum(parse.(Int, keys(input_base["bus"]))) + length(extremes_dict)
    #print("Orig buses is $orig_buses","\n")
    for (sw_id,sw) in input_dict["switch"]
        if haskey(sw,"auxiliary") && haskey(sw,"auxiliary") # Make sure ZILs are not included 
            aux =  deepcopy(input_ac_check["switch"][sw_id]["auxiliary"])
            orig = deepcopy(input_ac_check["switch"][sw_id]["original"])  
            for zil in eachindex(extremes_dict)
                if sw["bus_split"] == extremes_dict[zil][1] && result_dict["solution"]["nw"]["$hour_scenario"]["switch"]["$(switch_couples[sw_id]["switch_split"])"]["status"] == 1.0  # Making sure to reconnect everything to the original if the ZIL is connected
                    if result_dict["solution"]["nw"]["$hour_scenario"]["switch"][sw_id]["status"] >= 0.9
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
                elseif sw["bus_split"] == extremes_dict[zil][1] && result_dict["solution"]["nw"]["$hour_scenario"]["switch"]["$(switch_couples[sw_id]["switch_split"])"]["status"] == 0.0 # Reconnect everything to the split busbar
                    if result_dict["solution"]["nw"]["$hour_scenario"]["switch"][sw_id]["status"] >= 0.9
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

