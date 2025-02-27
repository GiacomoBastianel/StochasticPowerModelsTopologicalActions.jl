function hourly_bs(grid,hour_start,hour_end,zones,load_time_series,res_time_series,optimizer,formulation)
    results = Dict()
    hourly_grid = deepcopy(grid)
    for hour in hour_start:hour_end
        fix_hourly_load(hourly_grid,hour,zones,load_time_series) 
        fix_res_time_series(hourly_grid,hour,zones,res_time_series)
        hourly_results = _PMTP.run_acdcsw_AC_big_M_ZIL(hourly_grid,formulation,optimizer)
        results["$hour"] = deepcopy(hourly_results)
    end
    return results
end

function hourly_bs_measured(grid,hour_start,hour_end,zones,load_time_series,res_time_series,optimizer,formulation,measured_pu)
    results = Dict()
    hourly_grid = deepcopy(grid)
    for hour in hour_start:hour_end
        fix_hourly_load(hourly_grid,hour,zones,load_time_series) 
        fix_res_time_series_measured(hourly_grid,hour,zones,res_time_series,measured_pu)
        hourly_results = _PMTP.run_acdcsw_AC_big_M_ZIL(hourly_grid,formulation,optimizer)
        results["$hour"] = deepcopy(hourly_results)
    end
    return results
end

function hourly_bs_scenarios(grid,hours,zones,load_time_series,res_time_series,P_value,optimizer,formulation)
    results = Dict()
    hourly_grid = deepcopy(grid)
    for hour in hours
        fix_hourly_load(hourly_grid,hour,zones,load_time_series) 
        fix_res_time_series_P(hourly_grid,hour,zones,res_time_series,P_value)
        hourly_results = _PMTP.run_acdcsw_AC_big_M_ZIL(hourly_grid,formulation,optimizer)
        results["$hour"] = deepcopy(hourly_results)
    end
    return results
end

function add_dimensions!(data::Dict{String,Any},n_scenarios::Int,n_hours::Int)
    data["scenarios"] = n_scenarios
    data["hours"] = n_hours
end
