export run_stochastic_acdcsw_AC_ZIL
export run_stochastic_acdcsw_AC_ZIL_limited_actions

# AC Busbar splitting for AC/DC grid
"ACDC opf with controllable switches in AC busbar splitting configuration for AC/DC grids"
function run_stochastic_acdcsw_AC_ZIL(file, model_constructor, optimizer; kwargs...)
    #_FP.require_dim(file, :hour, :scenario)
    return _PM.solve_model(file, model_constructor, optimizer, build_stochastic_acdcsw_AC_ZIL; 
    ref_extensions=[_PMACDC.add_ref_dcgrid!,_PM.ref_add_on_off_va_bounds!], 
    multinetwork = true,
    kwargs...)
end

""
function build_stochastic_acdcsw_AC_ZIL(pm::_PM.AbstractPowerModel)
    # Variables
    for n in 1:length(pm.ref[:it][_PM.pm_it_sym][:nw])
        println("n: ", n)
        _PM.variable_bus_voltage(pm; nw = n)
        _PM.variable_gen_power(pm; nw = n)
        _PM.variable_branch_power(pm; nw = n)

        _PMTP.variable_switch_indicator(pm; nw = n) # binary variable to indicate the status of an ac switch
        _PMTP.variable_switch_power(pm; nw = n) # variable to indicate the power flowing through an ac switch (if closed)

        # DC grid
        _PMACDC.variable_active_dcbranch_flow(pm; nw = n)
        _PMACDC.variable_dcbranch_current(pm; nw = n)
        _PMACDC.variable_dc_converter(pm; nw = n)
        _PMACDC.variable_dcgrid_voltage_magnitude(pm; nw = n)
    end

    # Constraints
    for n in 1:length(pm.ref[:it][_PM.pm_it_sym][:nw])
        _PM.constraint_model_voltage(pm; nw = n)
        _PMACDC.constraint_voltage_dc(pm; nw = n)

        for i in _PM.ids(pm, n, :ref_buses)
            _PM.constraint_theta_ref(pm, i; nw = n)
        end

        for i in _PM.ids(pm, n, :bus)
            _PMTP.constraint_power_balance_ac_switch(pm, i; nw = n) # including the ac switches in the power balance of the AC part of an AC/DC grid
        end

        for i in _PM.ids(pm, n, :switch)
            _PMTP.constraint_switch_thermal_limit(pm, i; nw = n) # limiting the apparent power flowing through an ac switch
            _PMTP.constraint_switch_voltage_on_off_big_M(pm, i; nw = n) # making sure that the voltage magnitude and angles are equal at the two extremes of a closed switch
            _PMTP.constraint_switch_power_on_off(pm, i; nw = n) # limiting the maximum active and reactive power through an ac switch
        end

        for i in _PM.ids(pm, n, :switch_couples)
            _PMTP.constraint_exclusivity_switch(pm, i; nw = n) # the sum of the switches in a couple must be lower or equal than one (if OTS is allowed, like here), as each grid element is connected to either part of a split busbar no matter if the ZIL switch is opened or closed
            _PMTP.constraint_BS_OTS_branch(pm, i; nw = n) # making sure that if the grid element is not reconnected to the split busbar, the active and reactive power flowing through the switch is 0
            _PMTP.constraint_ZIL_switch(pm,i; nw = n)
        end

        for i in _PM.ids(pm, n, :branch)
            _PM.constraint_ohms_yt_from(pm, i; nw = n)
            _PM.constraint_ohms_yt_to(pm, i; nw = n)
            _PM.constraint_voltage_angle_difference(pm, i; nw = n)
            _PM.constraint_thermal_limit_from(pm, i; nw = n)
            _PM.constraint_thermal_limit_to(pm, i; nw = n)
        end

        for i in _PM.ids(pm, n, :busdc)
            _PMACDC.constraint_power_balance_dc(pm, i; nw = n)
        end

        for i in _PM.ids(pm, n, :branchdc)
            _PMACDC.constraint_ohms_dc_branch(pm, i; nw = n)
        end

        for i in _PM.ids(pm, n, :convdc)
            _PMTP.constraint_converter_losses(pm, i; nw = n)
            _PMACDC.constraint_converter_current(pm, i; nw = n)
            _PMACDC.constraint_conv_transformer(pm, i; nw = n)
            _PMACDC.constraint_conv_reactor(pm, i; nw = n)
            _PMACDC.constraint_conv_filter(pm, i; nw = n)
            if _PM.ref(pm,n,:convdc,i,"islcc") == 1
                _PMACDC.constraint_conv_firing_angle(pm, i; nw = n)
            end
        end
    
    end

     # Common binary among all the scenarios
    for n in 1:length(pm.ref[:it][_PM.pm_it_sym][:nw])
        for i in _PM.ids(pm, :switch, nw=n)
            constraint_switching_binaries_hour(pm, n, i)
        end
    end

    # Objective function
    objective_stochastic_opf(pm)
    #objective_stochastic_opf_opf(pm)
    #=
    obj_vals = Float64[]  # Stores best known objective values
    bounds = Float64[]    # Stores best known bound values
    mip_gaps = Float64[]  # Stores MIP gap percentage

    function my_callback(obj_vals,bounds,mip_gaps)
        where = callback_where(cb_data)
        
        if where == GRB_CB_MIP
            obj_val = callback_value(cb_data, GRB_CB_MIP_OBJBST)
            best_bound = callback_value(cb_data, GRB_CB_MIP_OBJBND)
    
            if obj_val < Inf  # Ensure we have a valid objective value
                push!(obj_vals, obj_val)
                push!(bounds, best_bound)
    
                # Compute the MIP gap (handling zero objective case)
                mip_gap = (abs(best_bound - obj_val) / max(abs(obj_val), 1e-6)) * 100
                push!(mip_gaps, mip_gap)
                push!(iterations, length(obj_vals))
            end
        end
    end

    obj_vals = Float64[]  # Stores best known objective values
    bounds = Float64[]    # Stores best known bound values
    mip_gaps = Float64[]  # Stores MIP gap percentage
    iterations = Int[]    # Stores iteration numbers

    # Define a callback function
    function my_callback(cb_data, cb_where)
        if cb_where == Gurobi.Callback.MIP  # Ensure it's during MIP solving
            obj_val = Gurobi.cbget(cb_data, Gurobi.Callback.MIP_OBJBST)
            best_bound = Gurobi.cbget(cb_data, Gurobi.Callback.MIP_OBJBND)

            if obj_val < Inf && best_bound > -Inf  # Ensure valid values
                push!(obj_vals, obj_val)
                push!(bounds, best_bound)

                # Compute the MIP gap (handling zero objective case)
                mip_gap = (abs(best_bound - obj_val) / max(abs(obj_val), 1e-6)) * 100
                push!(mip_gaps, mip_gap)
                push!(iterations, length(obj_vals))
            end
        end
    end

    MOI.set(Gurobi.Optimizer, Gurobi.CallbackFunction(), my_callback)
    return obj_vals, bounds, mip_gaps
    =#
end

function run_stochastic_acdcsw_AC_ZIL_sp(file, model_constructor, optimizer; kwargs...)
    #_FP.require_dim(file, :hour, :scenario)
    return _PM.solve_model(file, model_constructor, optimizer, build_stochastic_acdcsw_AC_ZIL_sp; 
    ref_extensions=[_PMACDC.add_ref_dcgrid!,_PM.ref_add_on_off_va_bounds!], 
    multinetwork = true,
    kwargs...)
    MOI.set(pm, Gurobi.CallbackFunction(), my_callback_function)
end

""
function build_stochastic_acdcsw_AC_ZIL_sp(pm::_PM.AbstractPowerModel)
    # Variables
    for n in 1:length(pm.ref[:it][_PM.pm_it_sym][:nw])
        _PMTP.variable_bus_voltage_sp(pm; nw = n)
        _PMTP.variable_gen_power_sp(pm; nw = n)
        _PM.variable_branch_power(pm; nw = n)

        _PMTP.variable_switch_indicator_sp(pm; nw = n) # binary variable to indicate the status of an ac switch
        _PMTP.variable_switch_power(pm; nw = n) # variable to indicate the power flowing through an ac switch (if closed)

        # DC grid
        _PMACDC.variable_active_dcbranch_flow(pm; nw = n)
        _PMACDC.variable_dcbranch_current(pm; nw = n)
        _PMACDC.variable_dc_converter(pm; nw = n)
        _PMACDC.variable_dcgrid_voltage_magnitude(pm; nw = n)
    end

    # Constraints
    for n in 1:length(pm.ref[:it][_PM.pm_it_sym][:nw])
        _PM.constraint_model_voltage(pm; nw = n)
        _PMACDC.constraint_voltage_dc(pm; nw = n)

        for i in _PM.ids(pm, n, :ref_buses)
            _PM.constraint_theta_ref(pm, i; nw = n)
        end

        for i in _PM.ids(pm, n, :bus)
            _PMTP.constraint_power_balance_ac_switch(pm, i; nw = n) # including the ac switches in the power balance of the AC part of an AC/DC grid
        end

        for i in _PM.ids(pm, n, :switch)
            _PMTP.constraint_switch_thermal_limit(pm, i; nw = n) # limiting the apparent power flowing through an ac switch
            _PMTP.constraint_switch_voltage_on_off_big_M(pm, i; nw = n) # making sure that the voltage magnitude and angles are equal at the two extremes of a closed switch
            _PMTP.constraint_switch_power_on_off(pm, i; nw = n) # limiting the maximum active and reactive power through an ac switch
        end

        for i in _PM.ids(pm, n, :switch_couples)
            _PMTP.constraint_exclusivity_switch(pm, i; nw = n) # the sum of the switches in a couple must be lower or equal than one (if OTS is allowed, like here), as each grid element is connected to either part of a split busbar no matter if the ZIL switch is opened or closed
            _PMTP.constraint_BS_OTS_branch(pm, i; nw = n) # making sure that if the grid element is not reconnected to the split busbar, the active and reactive power flowing through the switch is 0
            _PMTP.constraint_ZIL_switch(pm,i; nw = n)
        end

        for i in _PM.ids(pm, n, :branch)
            _PM.constraint_ohms_yt_from(pm, i; nw = n)
            _PM.constraint_ohms_yt_to(pm, i; nw = n)
            _PM.constraint_voltage_angle_difference(pm, i; nw = n)
            _PM.constraint_thermal_limit_from(pm, i; nw = n)
            _PM.constraint_thermal_limit_to(pm, i; nw = n)
        end

        for i in _PM.ids(pm, n, :busdc)
            _PMACDC.constraint_power_balance_dc(pm, i; nw = n)
        end
        for i in _PM.ids(pm, n, :branchdc)
            _PMACDC.constraint_ohms_dc_branch(pm, i; nw = n)
        end
        for i in _PM.ids(pm, n, :convdc)
            _PMTP.constraint_converter_losses(pm, i; nw = n)
            _PMACDC.constraint_converter_current(pm, i; nw = n)
            _PMACDC.constraint_conv_transformer(pm, i; nw = n)
            _PMACDC.constraint_conv_reactor(pm, i; nw = n)
            _PMACDC.constraint_conv_filter(pm, i; nw = n)
            if _PM.ref(pm,n,:convdc,i,"islcc") == 1
                _PMACDC.constraint_conv_firing_angle(pm, i; nw = n)
            end
        end
    end

     # Common binary among all the scenarios
     for n in 1:length(pm.ref[:it][_PM.pm_it_sym][:nw])
        for i in _PM.ids(pm, :switch, nw=n)
            constraint_switching_binaries_hour(pm, n, i)
        end
    end

    # Objective function
    objective_stochastic_opf(pm)
    #=
    global objbnd = []
    global objbst = []
    function my_callback_function(objbnd, objbst)
        println("DIO PORCOOOOO")
        println(" GRB_CB_MIP_OBJBND is $(GRB_CB_MIP_OBJBND)")
        println(" GRB_CB_MIP_OBJBST is $(GRB_CB_MIP_OBJBST)")
        push!(objbnd,GRB_CB_MIP_OBJBND)
        push!(objbst,GRB_CB_MIP_OBJBST)
        return objbnd,objbst
    end
    return objbnd, objbst
    =#
end



function run_stochastic_acdcsw_AC_ZIL_no_OTS(file, model_constructor, optimizer; kwargs...)
    _FP.require_dim(file, :hour, :scenario)
    return _PM.solve_model(file, model_constructor, optimizer, build_stochastic_acdcsw_AC_ZIL_no_OTS; 
    ref_extensions=[_PMACDC.add_ref_dcgrid!,_PM.ref_add_on_off_va_bounds!], 
    multinetwork = true,
    kwargs...)
end

""
function build_stochastic_acdcsw_AC_ZIL_no_OTS(pm::_PM.AbstractPowerModel)
    # Variables
    for n in _FP.nw_ids(pm)
        _PM.variable_bus_voltage(pm; nw = n)
        _PM.variable_gen_power(pm; nw = n)
        _PM.variable_branch_power(pm; nw = n)

        _PMTP.variable_switch_indicator(pm; nw = n) # binary variable to indicate the status of an ac switch
        _PMTP.variable_switch_power(pm; nw = n) # variable to indicate the power flowing through an ac switch (if closed)

        # DC grid
        _PMACDC.variable_active_dcbranch_flow(pm; nw = n)
        _PMACDC.variable_dcbranch_current(pm; nw = n)
        _PMACDC.variable_dc_converter(pm; nw = n)
        _PMACDC.variable_dcgrid_voltage_magnitude(pm; nw = n)
    end

    # Constraints
    for n in _FP.nw_ids(pm)
        _PM.constraint_model_voltage(pm; nw = n)
        _PMACDC.constraint_voltage_dc(pm; nw = n)

        for i in _PM.ids(pm, n, :ref_buses)
            _PM.constraint_theta_ref(pm, i; nw = n)
        end

        for i in _PM.ids(pm, n, :bus)
            _PMTP.constraint_power_balance_ac_switch(pm, i; nw = n) # including the ac switches in the power balance of the AC part of an AC/DC grid
        end

        for i in _PM.ids(pm, n, :switch)
            _PMTP.constraint_switch_thermal_limit(pm, i; nw = n) # limiting the apparent power flowing through an ac switch
            _PMTP.constraint_switch_voltage_on_off_big_M(pm, i; nw = n) # making sure that the voltage magnitude and angles are equal at the two extremes of a closed switch
            _PMTP.constraint_switch_power_on_off(pm, i; nw = n) # limiting the maximum active and reactive power through an ac switch
        end

        for i in _PM.ids(pm, n, :switch_couples)
            _PMTP.constraint_exclusivity_switch_no_OTS(pm, i; nw = n) # the sum of the switches in a couple must be lower or equal than one (if OTS is allowed, like here), as each grid element is connected to either part of a split busbar no matter if the ZIL switch is opened or closed
            #_PMTP.constraint_BS_OTS_branch(pm, i; nw = n) # making sure that if the grid element is not reconnected to the split busbar, the active and reactive power flowing through the switch is 0
            _PMTP.constraint_ZIL_switch(pm,i; nw = n)
        end

        for i in _PM.ids(pm, n, :branch)
            _PM.constraint_ohms_yt_from(pm, i; nw = n)
            _PM.constraint_ohms_yt_to(pm, i; nw = n)
            _PM.constraint_voltage_angle_difference(pm, i; nw = n)
            _PM.constraint_thermal_limit_from(pm, i; nw = n)
            _PM.constraint_thermal_limit_to(pm, i; nw = n)
        end

        for i in _PM.ids(pm, n, :busdc)
            _PMACDC.constraint_power_balance_dc(pm, i; nw = n)
        end
        for i in _PM.ids(pm, n, :branchdc)
            _PMACDC.constraint_ohms_dc_branch(pm, i; nw = n)
        end
        for i in _PM.ids(pm, n, :convdc)
            _PMTP.constraint_converter_losses(pm, i; nw = n)
            _PMACDC.constraint_converter_current(pm, i; nw = n)
            _PMACDC.constraint_conv_transformer(pm, i; nw = n)
            _PMACDC.constraint_conv_reactor(pm, i; nw = n)
            _PMACDC.constraint_conv_filter(pm, i; nw = n)
            if _PM.ref(pm,n,:convdc,i,"islcc") == 1
                _PMACDC.constraint_conv_firing_angle(pm, i; nw = n)
            end
        end
    end

     # Common binary among all the scenarios
    for n in _FP.nw_ids(pm)
        for i in _PM.ids(pm, :switch, nw=n)
            constraint_switching_binaries_hour(pm, n, i)
        end
    end

    # Objective function
    objective_stochastic_opf(pm)

end


""

function run_stochastic_acdcsw_AC_ZIL_limited_actions(file, model_constructor, optimizer; kwargs...)
    #_FP.require_dim(file, :hour, :scenario)
    return _PM.solve_model(file, model_constructor, optimizer, build_stochastic_acdcsw_AC_ZIL_limited_actions; 
    ref_extensions=[_PMACDC.add_ref_dcgrid!,_PM.ref_add_on_off_va_bounds!], 
    multinetwork = true,
    kwargs...)
end

""
function build_stochastic_acdcsw_AC_ZIL_limited_actions(pm::_PM.AbstractPowerModel)
    # Variables
    for n in 1:length(pm.ref[:it][_PM.pm_it_sym][:nw])
        _PM.variable_bus_voltage(pm; nw = n)
        _PM.variable_gen_power(pm; nw = n)
        _PM.variable_branch_power(pm; nw = n)

        _PMTP.variable_switch_indicator(pm; nw = n) # binary variable to indicate the status of an ac switch
        _PMTP.variable_switch_power(pm; nw = n) # variable to indicate the power flowing through an ac switch (if closed)

        # DC grid
        _PMACDC.variable_active_dcbranch_flow(pm; nw = n)
        _PMACDC.variable_dcbranch_current(pm; nw = n)
        _PMACDC.variable_dc_converter(pm; nw = n)
        _PMACDC.variable_dcgrid_voltage_magnitude(pm; nw = n)
    end

    # Constraints
    for n in 1:length(pm.ref[:it][_PM.pm_it_sym][:nw])
        _PM.constraint_model_voltage(pm; nw = n)
        _PMACDC.constraint_voltage_dc(pm; nw = n)

        for i in _PM.ids(pm, n, :ref_buses)
            _PM.constraint_theta_ref(pm, i; nw = n)
        end

        for i in _PM.ids(pm, n, :bus)
            _PMTP.constraint_power_balance_ac_switch(pm, i; nw = n) # including the ac switches in the power balance of the AC part of an AC/DC grid
        end

        for i in _PM.ids(pm, n, :switch)
            _PMTP.constraint_switch_thermal_limit(pm, i; nw = n) # limiting the apparent power flowing through an ac switch
            _PMTP.constraint_switch_voltage_on_off_big_M(pm, i; nw = n) # making sure that the voltage magnitude and angles are equal at the two extremes of a closed switch
            _PMTP.constraint_switch_power_on_off(pm, i; nw = n) # limiting the maximum active and reactive power through an ac switch
        end

        for i in _PM.ids(pm, n, :switch_couples)
            _PMTP.constraint_exclusivity_switch(pm, i; nw = n) # the sum of the switches in a couple must be lower or equal than one (if OTS is allowed, like here), as each grid element is connected to either part of a split busbar no matter if the ZIL switch is opened or closed
            _PMTP.constraint_BS_OTS_branch(pm, i; nw = n) # making sure that if the grid element is not reconnected to the split busbar, the active and reactive power flowing through the switch is 0
            _PMTP.constraint_ZIL_switch(pm,i; nw = n)
            #_PMTP.constraint_ZIL_no_OTS(pm,i; nw = n)
        end

        for i in _PM.ids(pm, n, :branch)
            _PM.constraint_ohms_yt_from(pm, i; nw = n)
            _PM.constraint_ohms_yt_to(pm, i; nw = n)
            _PM.constraint_voltage_angle_difference(pm, i; nw = n)
            _PM.constraint_thermal_limit_from(pm, i; nw = n)
            _PM.constraint_thermal_limit_to(pm, i; nw = n)
        end

        for i in _PM.ids(pm, n, :busdc)
            _PMACDC.constraint_power_balance_dc(pm, i; nw = n)
        end
        for i in _PM.ids(pm, n, :branchdc)
            _PMACDC.constraint_ohms_dc_branch(pm, i; nw = n)
        end
        for i in _PM.ids(pm, n, :convdc)
            _PMTP.constraint_converter_losses(pm, i; nw = n)
            _PMACDC.constraint_converter_current(pm, i; nw = n)
            _PMACDC.constraint_conv_transformer(pm, i; nw = n)
            _PMACDC.constraint_conv_reactor(pm, i; nw = n)
            _PMACDC.constraint_conv_filter(pm, i; nw = n)
            if _PM.ref(pm,n,:convdc,i,"islcc") == 1
                _PMACDC.constraint_conv_firing_angle(pm, i; nw = n)
            end
        end
    end

     # Common binary among all the scenarios
     for n in 1:length(pm.ref[:it][_PM.pm_it_sym][:nw])
        for i in _PM.ids(pm, :switch, nw=n)
            constraint_switching_binaries_hour(pm, n, i)
        end
    end

    constraint_limit_switching_actions(pm)

    # Objective function
    objective_stochastic_opf(pm)

end

""

function run_stochastic_acdcsw_AC_ZIL_limited_actions_sp(file, model_constructor, optimizer; kwargs...)
    #_FP.require_dim(file, :hour, :scenario)
    return _PM.solve_model(file, model_constructor, optimizer, build_stochastic_acdcsw_AC_ZIL_limited_actions_sp; 
    ref_extensions=[_PMACDC.add_ref_dcgrid!,_PM.ref_add_on_off_va_bounds!], 
    multinetwork = true,
    kwargs...)
end

""
function build_stochastic_acdcsw_AC_ZIL_limited_actions_sp(pm::_PM.AbstractPowerModel)
    # Variables
    for n in 1:length(pm.ref[:it][_PM.pm_it_sym][:nw])
        _PMTP.variable_bus_voltage_sp(pm; nw = n)
        _PMTP.variable_gen_power_sp(pm; nw = n)
        _PM.variable_branch_power(pm; nw = n)

        _PMTP.variable_switch_indicator_sp(pm; nw = n) # binary variable to indicate the status of an ac switch
        _PMTP.variable_switch_power(pm; nw = n) # variable to indicate the power flowing through an ac switch (if closed)

        # DC grid
        _PMACDC.variable_active_dcbranch_flow(pm; nw = n)
        _PMACDC.variable_dcbranch_current(pm; nw = n)
        _PMACDC.variable_dc_converter(pm; nw = n)
        _PMACDC.variable_dcgrid_voltage_magnitude(pm; nw = n)
    end
    

    # Constraints
    for n in 1:length(pm.ref[:it][_PM.pm_it_sym][:nw])
        _PM.constraint_model_voltage(pm; nw = n)
        _PMACDC.constraint_voltage_dc(pm; nw = n)

        for i in _PM.ids(pm, n, :ref_buses)
            _PM.constraint_theta_ref(pm, i; nw = n)
        end

        for i in _PM.ids(pm, n, :bus)
            _PMTP.constraint_power_balance_ac_switch(pm, i; nw = n) # including the ac switches in the power balance of the AC part of an AC/DC grid
        end

        for i in _PM.ids(pm, n, :switch)
            _PMTP.constraint_switch_thermal_limit(pm, i; nw = n) # limiting the apparent power flowing through an ac switch
            _PMTP.constraint_switch_voltage_on_off_big_M(pm, i; nw = n) # making sure that the voltage magnitude and angles are equal at the two extremes of a closed switch
            _PMTP.constraint_switch_power_on_off(pm, i; nw = n) # limiting the maximum active and reactive power through an ac switch
        end

        for i in _PM.ids(pm, n, :switch_couples)
            _PMTP.constraint_exclusivity_switch(pm, i; nw = n) # the sum of the switches in a couple must be lower or equal than one (if OTS is allowed, like here), as each grid element is connected to either part of a split busbar no matter if the ZIL switch is opened or closed
            _PMTP.constraint_BS_OTS_branch(pm, i; nw = n) # making sure that if the grid element is not reconnected to the split busbar, the active and reactive power flowing through the switch is 0
            _PMTP.constraint_ZIL_switch(pm,i; nw = n)
            #_PMTP.constraint_ZIL_no_OTS(pm,i; nw = n)
        end

        for i in _PM.ids(pm, n, :branch)
            _PM.constraint_ohms_yt_from(pm, i; nw = n)
            _PM.constraint_ohms_yt_to(pm, i; nw = n)
            _PM.constraint_voltage_angle_difference(pm, i; nw = n)
            _PM.constraint_thermal_limit_from(pm, i; nw = n)
            _PM.constraint_thermal_limit_to(pm, i; nw = n)
        end

        for i in _PM.ids(pm, n, :busdc)
            _PMACDC.constraint_power_balance_dc(pm, i; nw = n)
        end
        for i in _PM.ids(pm, n, :branchdc)
            _PMACDC.constraint_ohms_dc_branch(pm, i; nw = n)
        end
        for i in _PM.ids(pm, n, :convdc)
            _PMTP.constraint_converter_losses(pm, i; nw = n)
            _PMACDC.constraint_converter_current(pm, i; nw = n)
            _PMACDC.constraint_conv_transformer(pm, i; nw = n)
            _PMACDC.constraint_conv_reactor(pm, i; nw = n)
            _PMACDC.constraint_conv_filter(pm, i; nw = n)
            if _PM.ref(pm,n,:convdc,i,"islcc") == 1
                _PMACDC.constraint_conv_firing_angle(pm, i; nw = n)
            end
        end
    end

     # Common binary among all the scenarios
     for n in 1:length(pm.ref[:it][_PM.pm_it_sym][:nw])
        for i in _PM.ids(pm, :switch, nw=n)
            constraint_switching_binaries_hour(pm, n, i)
        end
    end

    constraint_limit_switching_actions(pm)

    # Objective function
    objective_stochastic_opf(pm)

end

""
function run_stochastic_acdcsw_AC_ZIL_limited_actions_no_OTS(file, model_constructor, optimizer; kwargs...)
    _FP.require_dim(file, :hour, :scenario)
    return _PM.solve_model(file, model_constructor, optimizer, build_stochastic_acdcsw_AC_ZIL_limited_actions_no_OTS; 
    ref_extensions=[_PMACDC.add_ref_dcgrid!,_PM.ref_add_on_off_va_bounds!], 
    multinetwork = true,
    kwargs...)
end

""
function build_stochastic_acdcsw_AC_ZIL_limited_actions_no_OTS(pm::_PM.AbstractPowerModel)
    # Variables
    for n in _FP.nw_ids(pm)
        _PM.variable_bus_voltage(pm; nw = n)
        _PM.variable_gen_power(pm; nw = n)
        _PM.variable_branch_power(pm; nw = n)

        _PMTP.variable_switch_indicator(pm; nw = n) # binary variable to indicate the status of an ac switch
        _PMTP.variable_switch_power(pm; nw = n) # variable to indicate the power flowing through an ac switch (if closed)

        # DC grid
        _PMACDC.variable_active_dcbranch_flow(pm; nw = n)
        _PMACDC.variable_dcbranch_current(pm; nw = n)
        _PMACDC.variable_dc_converter(pm; nw = n)
        _PMACDC.variable_dcgrid_voltage_magnitude(pm; nw = n)
    end

    # Constraints
    for n in _FP.nw_ids(pm)
        _PM.constraint_model_voltage(pm; nw = n)
        _PMACDC.constraint_voltage_dc(pm; nw = n)

        for i in _PM.ids(pm, n, :ref_buses)
            _PM.constraint_theta_ref(pm, i; nw = n)
        end

        for i in _PM.ids(pm, n, :bus)
            _PMTP.constraint_power_balance_ac_switch(pm, i; nw = n) # including the ac switches in the power balance of the AC part of an AC/DC grid
        end

        for i in _PM.ids(pm, n, :switch)
            _PMTP.constraint_switch_thermal_limit(pm, i; nw = n) # limiting the apparent power flowing through an ac switch
            _PMTP.constraint_switch_voltage_on_off_big_M(pm, i; nw = n) # making sure that the voltage magnitude and angles are equal at the two extremes of a closed switch
            _PMTP.constraint_switch_power_on_off(pm, i; nw = n) # limiting the maximum active and reactive power through an ac switch
        end

        for i in _PM.ids(pm, n, :switch_couples)
            _PMTP.constraint_exclusivity_switch_no_OTS(pm, i; nw = n) # the sum of the switches in a couple must be lower or equal than one (if OTS is allowed, like here), as each grid element is connected to either part of a split busbar no matter if the ZIL switch is opened or closed
            #_PMTP.constraint_BS_OTS_branch(pm, i; nw = n) # making sure that if the grid element is not reconnected to the split busbar, the active and reactive power flowing through the switch is 0
            _PMTP.constraint_ZIL_switch(pm,i; nw = n)
            #_PMTP.constraint_ZIL_no_OTS(pm,i; nw = n)
        end

        for i in _PM.ids(pm, n, :branch)
            _PM.constraint_ohms_yt_from(pm, i; nw = n)
            _PM.constraint_ohms_yt_to(pm, i; nw = n)
            _PM.constraint_voltage_angle_difference(pm, i; nw = n)
            _PM.constraint_thermal_limit_from(pm, i; nw = n)
            _PM.constraint_thermal_limit_to(pm, i; nw = n)
        end

        for i in _PM.ids(pm, n, :busdc)
            _PMACDC.constraint_power_balance_dc(pm, i; nw = n)
        end
        for i in _PM.ids(pm, n, :branchdc)
            _PMACDC.constraint_ohms_dc_branch(pm, i; nw = n)
        end
        for i in _PM.ids(pm, n, :convdc)
            _PMTP.constraint_converter_losses(pm, i; nw = n)
            _PMACDC.constraint_converter_current(pm, i; nw = n)
            _PMACDC.constraint_conv_transformer(pm, i; nw = n)
            _PMACDC.constraint_conv_reactor(pm, i; nw = n)
            _PMACDC.constraint_conv_filter(pm, i; nw = n)
            if _PM.ref(pm,n,:convdc,i,"islcc") == 1
                _PMACDC.constraint_conv_firing_angle(pm, i; nw = n)
            end
        end
    end

     # Common binary among all the scenarios
    for n in _FP.nw_ids(pm)
        for i in _PM.ids(pm, :switch, nw=n)
            constraint_switching_binaries_hour(pm, n, i)
        end
    end

    constraint_limit_switching_actions(pm)

    # Objective function
    objective_stochastic_opf(pm)

end




""
function run_stochastic_acdcsw_AC_ZIL_limited_actions_single_switch(file, model_constructor, optimizer; kwargs...)
    _FP.require_dim(file, :hour, :scenario)
    return _PM.solve_model(file, model_constructor, optimizer, build_stochastic_acdcsw_AC_ZIL_limited_actions_single_switch; 
    ref_extensions=[_PMACDC.add_ref_dcgrid!,_PM.ref_add_on_off_va_bounds!], 
    multinetwork = true,
    kwargs...)
end

""
function build_stochastic_acdcsw_AC_ZIL_limited_actions_single_switch(pm::_PM.AbstractPowerModel)
    # Variables
    for n in _FP.nw_ids(pm)
        _PM.variable_bus_voltage(pm; nw = n)
        _PM.variable_gen_power(pm; nw = n)
        _PM.variable_branch_power(pm; nw = n)

        _PMTP.variable_switch_indicator(pm; nw = n) # binary variable to indicate the status of an ac switch
        _PMTP.variable_switch_power(pm; nw = n) # variable to indicate the power flowing through an ac switch (if closed)

        # DC grid
        _PMACDC.variable_active_dcbranch_flow(pm; nw = n)
        _PMACDC.variable_dcbranch_current(pm; nw = n)
        _PMACDC.variable_dc_converter(pm; nw = n)
        _PMACDC.variable_dcgrid_voltage_magnitude(pm; nw = n)
    end

    # Constraints
    for n in _FP.nw_ids(pm)
        _PM.constraint_model_voltage(pm; nw = n)
        _PMACDC.constraint_voltage_dc(pm; nw = n)

        for i in _PM.ids(pm, n, :ref_buses)
            _PM.constraint_theta_ref(pm, i; nw = n)
        end

        for i in _PM.ids(pm, n, :bus)
            _PMTP.constraint_power_balance_ac_switch(pm, i; nw = n) # including the ac switches in the power balance of the AC part of an AC/DC grid
        end

        for i in _PM.ids(pm, n, :switch)
            _PMTP.constraint_switch_thermal_limit(pm, i; nw = n) # limiting the apparent power flowing through an ac switch
            _PMTP.constraint_switch_voltage_on_off_big_M(pm, i; nw = n) # making sure that the voltage magnitude and angles are equal at the two extremes of a closed switch
            _PMTP.constraint_switch_power_on_off(pm, i; nw = n) # limiting the maximum active and reactive power through an ac switch
        end

        for i in _PM.ids(pm, n, :switch_couples)
            _PMTP.constraint_exclusivity_switch(pm, i; nw = n) # the sum of the switches in a couple must be lower or equal than one (if OTS is allowed, like here), as each grid element is connected to either part of a split busbar no matter if the ZIL switch is opened or closed
            _PMTP.constraint_BS_OTS_branch(pm, i; nw = n) # making sure that if the grid element is not reconnected to the split busbar, the active and reactive power flowing through the switch is 0
            _PMTP.constraint_ZIL_switch(pm,i; nw = n)
            #_PMTP.constraint_ZIL_no_OTS(pm,i; nw = n)
        end

        for i in _PM.ids(pm, n, :branch)
            _PM.constraint_ohms_yt_from(pm, i; nw = n)
            _PM.constraint_ohms_yt_to(pm, i; nw = n)
            _PM.constraint_voltage_angle_difference(pm, i; nw = n)
            _PM.constraint_thermal_limit_from(pm, i; nw = n)
            _PM.constraint_thermal_limit_to(pm, i; nw = n)
        end

        for i in _PM.ids(pm, n, :busdc)
            _PMACDC.constraint_power_balance_dc(pm, i; nw = n)
        end
        for i in _PM.ids(pm, n, :branchdc)
            _PMACDC.constraint_ohms_dc_branch(pm, i; nw = n)
        end
        for i in _PM.ids(pm, n, :convdc)
            _PMTP.constraint_converter_losses(pm, i; nw = n)
            _PMACDC.constraint_converter_current(pm, i; nw = n)
            _PMACDC.constraint_conv_transformer(pm, i; nw = n)
            _PMACDC.constraint_conv_reactor(pm, i; nw = n)
            _PMACDC.constraint_conv_filter(pm, i; nw = n)
            if _PM.ref(pm,n,:convdc,i,"islcc") == 1
                _PMACDC.constraint_conv_firing_angle(pm, i; nw = n)
            end
        end
    end

     # Common binary among all the scenarios
    for n in _FP.nw_ids(pm)
        for i in _PM.ids(pm, :switch, nw=n)
            constraint_switching_binaries_hour(pm, n, i)
        end
    end

    constraint_limit_switching_actions_single_switches(pm)

    # Objective function
    objective_stochastic_opf(pm)

end

""
function run_stochastic_acdcsw_AC_ZIL_limited_actions_single_switch_no_OTS(file, model_constructor, optimizer; kwargs...)
    _FP.require_dim(file, :hour, :scenario)
    return _PM.solve_model(file, model_constructor, optimizer, build_stochastic_acdcsw_AC_ZIL_limited_actions_single_switch_no_OTS; 
    ref_extensions=[_PMACDC.add_ref_dcgrid!,_PM.ref_add_on_off_va_bounds!], 
    multinetwork = true,
    kwargs...)
end

""
function build_stochastic_acdcsw_AC_ZIL_limited_actions_single_switch_no_OTS(pm::_PM.AbstractPowerModel)
    # Variables
    for n in _FP.nw_ids(pm)
        _PM.variable_bus_voltage(pm; nw = n)
        _PM.variable_gen_power(pm; nw = n)
        _PM.variable_branch_power(pm; nw = n)

        _PMTP.variable_switch_indicator(pm; nw = n) # binary variable to indicate the status of an ac switch
        _PMTP.variable_switch_power(pm; nw = n) # variable to indicate the power flowing through an ac switch (if closed)

        # DC grid
        _PMACDC.variable_active_dcbranch_flow(pm; nw = n)
        _PMACDC.variable_dcbranch_current(pm; nw = n)
        _PMACDC.variable_dc_converter(pm; nw = n)
        _PMACDC.variable_dcgrid_voltage_magnitude(pm; nw = n)
    end

    # Constraints
    for n in _FP.nw_ids(pm)
        _PM.constraint_model_voltage(pm; nw = n)
        _PMACDC.constraint_voltage_dc(pm; nw = n)

        for i in _PM.ids(pm, n, :ref_buses)
            _PM.constraint_theta_ref(pm, i; nw = n)
        end

        for i in _PM.ids(pm, n, :bus)
            _PMTP.constraint_power_balance_ac_switch(pm, i; nw = n) # including the ac switches in the power balance of the AC part of an AC/DC grid
        end

        for i in _PM.ids(pm, n, :switch)
            _PMTP.constraint_switch_thermal_limit(pm, i; nw = n) # limiting the apparent power flowing through an ac switch
            _PMTP.constraint_switch_voltage_on_off_big_M(pm, i; nw = n) # making sure that the voltage magnitude and angles are equal at the two extremes of a closed switch
            _PMTP.constraint_switch_power_on_off(pm, i; nw = n) # limiting the maximum active and reactive power through an ac switch
        end

        for i in _PM.ids(pm, n, :switch_couples)
            _PMTP.constraint_exclusivity_switch_no_OTS(pm, i; nw = n) # the sum of the switches in a couple must be lower or equal than one (if OTS is allowed, like here), as each grid element is connected to either part of a split busbar no matter if the ZIL switch is opened or closed
            #_PMTP.constraint_BS_OTS_branch(pm, i; nw = n) # making sure that if the grid element is not reconnected to the split busbar, the active and reactive power flowing through the switch is 0
            _PMTP.constraint_ZIL_switch(pm,i; nw = n)
            #_PMTP.constraint_ZIL_no_OTS(pm,i; nw = n)
        end

        for i in _PM.ids(pm, n, :branch)
            _PM.constraint_ohms_yt_from(pm, i; nw = n)
            _PM.constraint_ohms_yt_to(pm, i; nw = n)
            _PM.constraint_voltage_angle_difference(pm, i; nw = n)
            _PM.constraint_thermal_limit_from(pm, i; nw = n)
            _PM.constraint_thermal_limit_to(pm, i; nw = n)
        end

        for i in _PM.ids(pm, n, :busdc)
            _PMACDC.constraint_power_balance_dc(pm, i; nw = n)
        end
        for i in _PM.ids(pm, n, :branchdc)
            _PMACDC.constraint_ohms_dc_branch(pm, i; nw = n)
        end
        for i in _PM.ids(pm, n, :convdc)
            _PMTP.constraint_converter_losses(pm, i; nw = n)
            _PMACDC.constraint_converter_current(pm, i; nw = n)
            _PMACDC.constraint_conv_transformer(pm, i; nw = n)
            _PMACDC.constraint_conv_reactor(pm, i; nw = n)
            _PMACDC.constraint_conv_filter(pm, i; nw = n)
            if _PM.ref(pm,n,:convdc,i,"islcc") == 1
                _PMACDC.constraint_conv_firing_angle(pm, i; nw = n)
            end
        end
    end

     # Common binary among all the scenarios
    for n in _FP.nw_ids(pm)
        for i in _PM.ids(pm, :switch, nw=n)
            constraint_switching_binaries_hour(pm, n, i)
        end
    end

    constraint_limit_switching_actions_single_switches(pm)

    # Objective function
    objective_stochastic_opf(pm)

end




""
function run_stochastic_acdcsw_AC_ZIL_limited_actions_limited_single_switch(file, model_constructor, optimizer; kwargs...)
    _FP.require_dim(file, :hour, :scenario)
    return _PM.solve_model(file, model_constructor, optimizer, build_stochastic_acdcsw_AC_ZIL_limited_actions_limited_single_switch; 
    ref_extensions=[_PMACDC.add_ref_dcgrid!,_PM.ref_add_on_off_va_bounds!], 
    multinetwork = true,
    kwargs...)
end

""
function build_stochastic_acdcsw_AC_ZIL_limited_actions_limited_single_switch(pm::_PM.AbstractPowerModel)
    # Variables
    for n in _FP.nw_ids(pm)
        _PM.variable_bus_voltage(pm; nw = n)
        _PM.variable_gen_power(pm; nw = n)
        _PM.variable_branch_power(pm; nw = n)

        _PMTP.variable_switch_indicator(pm; nw = n) # binary variable to indicate the status of an ac switch
        _PMTP.variable_switch_power(pm; nw = n) # variable to indicate the power flowing through an ac switch (if closed)

        # DC grid
        _PMACDC.variable_active_dcbranch_flow(pm; nw = n)
        _PMACDC.variable_dcbranch_current(pm; nw = n)
        _PMACDC.variable_dc_converter(pm; nw = n)
        _PMACDC.variable_dcgrid_voltage_magnitude(pm; nw = n)
    end

    # Constraints
    for n in _FP.nw_ids(pm)
        _PM.constraint_model_voltage(pm; nw = n)
        _PMACDC.constraint_voltage_dc(pm; nw = n)

        for i in _PM.ids(pm, n, :ref_buses)
            _PM.constraint_theta_ref(pm, i; nw = n)
        end

        for i in _PM.ids(pm, n, :bus)
            _PMTP.constraint_power_balance_ac_switch(pm, i; nw = n) # including the ac switches in the power balance of the AC part of an AC/DC grid
        end

        for i in _PM.ids(pm, n, :switch)
            _PMTP.constraint_switch_thermal_limit(pm, i; nw = n) # limiting the apparent power flowing through an ac switch
            _PMTP.constraint_switch_voltage_on_off_big_M(pm, i; nw = n) # making sure that the voltage magnitude and angles are equal at the two extremes of a closed switch
            _PMTP.constraint_switch_power_on_off(pm, i; nw = n) # limiting the maximum active and reactive power through an ac switch
        end

        for i in _PM.ids(pm, n, :switch_couples)
            _PMTP.constraint_exclusivity_switch(pm, i; nw = n) # the sum of the switches in a couple must be lower or equal than one (if OTS is allowed, like here), as each grid element is connected to either part of a split busbar no matter if the ZIL switch is opened or closed
            _PMTP.constraint_BS_OTS_branch(pm, i; nw = n) # making sure that if the grid element is not reconnected to the split busbar, the active and reactive power flowing through the switch is 0
            _PMTP.constraint_ZIL_switch(pm,i; nw = n)
            #_PMTP.constraint_ZIL_no_OTS(pm,i; nw = n)
        end

        for i in _PM.ids(pm, n, :branch)
            _PM.constraint_ohms_yt_from(pm, i; nw = n)
            _PM.constraint_ohms_yt_to(pm, i; nw = n)
            _PM.constraint_voltage_angle_difference(pm, i; nw = n)
            _PM.constraint_thermal_limit_from(pm, i; nw = n)
            _PM.constraint_thermal_limit_to(pm, i; nw = n)
        end

        for i in _PM.ids(pm, n, :busdc)
            _PMACDC.constraint_power_balance_dc(pm, i; nw = n)
        end
        for i in _PM.ids(pm, n, :branchdc)
            _PMACDC.constraint_ohms_dc_branch(pm, i; nw = n)
        end
        for i in _PM.ids(pm, n, :convdc)
            _PMTP.constraint_converter_losses(pm, i; nw = n)
            _PMACDC.constraint_converter_current(pm, i; nw = n)
            _PMACDC.constraint_conv_transformer(pm, i; nw = n)
            _PMACDC.constraint_conv_reactor(pm, i; nw = n)
            _PMACDC.constraint_conv_filter(pm, i; nw = n)
            if _PM.ref(pm,n,:convdc,i,"islcc") == 1
                _PMACDC.constraint_conv_firing_angle(pm, i; nw = n)
            end
        end
    end

     # Common binary among all the scenarios
    for n in _FP.nw_ids(pm)
        for i in _PM.ids(pm, :switch, nw=n)
            constraint_switching_binaries_hour(pm, n, i)
        end
    end

    constraint_limit_switching_actions_single_switches(pm)
    constraint_limit_switching_actions(pm)

    # Objective function
    objective_stochastic_opf(pm)

end

""
function run_stochastic_acdcsw_AC_ZIL_limited_actions_limited_single_switch_no_OTS(file, model_constructor, optimizer; kwargs...)
    _FP.require_dim(file, :hour, :scenario)
    return _PM.solve_model(file, model_constructor, optimizer, build_stochastic_acdcsw_AC_ZIL_limited_actions_limited_single_switch_no_OTS; 
    ref_extensions=[_PMACDC.add_ref_dcgrid!,_PM.ref_add_on_off_va_bounds!], 
    multinetwork = true,
    kwargs...)
end

""
function build_stochastic_acdcsw_AC_ZIL_limited_actions_limited_single_switch_no_OTS(pm::_PM.AbstractPowerModel)
    # Variables
    for n in _FP.nw_ids(pm)
        _PM.variable_bus_voltage(pm; nw = n)
        _PM.variable_gen_power(pm; nw = n)
        _PM.variable_branch_power(pm; nw = n)

        _PMTP.variable_switch_indicator(pm; nw = n) # binary variable to indicate the status of an ac switch
        _PMTP.variable_switch_power(pm; nw = n) # variable to indicate the power flowing through an ac switch (if closed)

        # DC grid
        _PMACDC.variable_active_dcbranch_flow(pm; nw = n)
        _PMACDC.variable_dcbranch_current(pm; nw = n)
        _PMACDC.variable_dc_converter(pm; nw = n)
        _PMACDC.variable_dcgrid_voltage_magnitude(pm; nw = n)
    end

    # Constraints
    for n in _FP.nw_ids(pm)
        _PM.constraint_model_voltage(pm; nw = n)
        _PMACDC.constraint_voltage_dc(pm; nw = n)

        for i in _PM.ids(pm, n, :ref_buses)
            _PM.constraint_theta_ref(pm, i; nw = n)
        end

        for i in _PM.ids(pm, n, :bus)
            _PMTP.constraint_power_balance_ac_switch(pm, i; nw = n) # including the ac switches in the power balance of the AC part of an AC/DC grid
        end

        for i in _PM.ids(pm, n, :switch)
            _PMTP.constraint_switch_thermal_limit(pm, i; nw = n) # limiting the apparent power flowing through an ac switch
            _PMTP.constraint_switch_voltage_on_off_big_M(pm, i; nw = n) # making sure that the voltage magnitude and angles are equal at the two extremes of a closed switch
            _PMTP.constraint_switch_power_on_off(pm, i; nw = n) # limiting the maximum active and reactive power through an ac switch
        end

        for i in _PM.ids(pm, n, :switch_couples)
            _PMTP.constraint_exclusivity_switch_no_OTS(pm, i; nw = n) # the sum of the switches in a couple must be lower or equal than one (if OTS is allowed, like here), as each grid element is connected to either part of a split busbar no matter if the ZIL switch is opened or closed
            #_PMTP.constraint_BS_OTS_branch(pm, i; nw = n) # making sure that if the grid element is not reconnected to the split busbar, the active and reactive power flowing through the switch is 0
            _PMTP.constraint_ZIL_switch(pm,i; nw = n)
            #_PMTP.constraint_ZIL_no_OTS(pm,i; nw = n)
        end

        for i in _PM.ids(pm, n, :branch)
            _PM.constraint_ohms_yt_from(pm, i; nw = n)
            _PM.constraint_ohms_yt_to(pm, i; nw = n)
            _PM.constraint_voltage_angle_difference(pm, i; nw = n)
            _PM.constraint_thermal_limit_from(pm, i; nw = n)
            _PM.constraint_thermal_limit_to(pm, i; nw = n)
        end

        for i in _PM.ids(pm, n, :busdc)
            _PMACDC.constraint_power_balance_dc(pm, i; nw = n)
        end
        for i in _PM.ids(pm, n, :branchdc)
            _PMACDC.constraint_ohms_dc_branch(pm, i; nw = n)
        end
        for i in _PM.ids(pm, n, :convdc)
            _PMTP.constraint_converter_losses(pm, i; nw = n)
            _PMACDC.constraint_converter_current(pm, i; nw = n)
            _PMACDC.constraint_conv_transformer(pm, i; nw = n)
            _PMACDC.constraint_conv_reactor(pm, i; nw = n)
            _PMACDC.constraint_conv_filter(pm, i; nw = n)
            if _PM.ref(pm,n,:convdc,i,"islcc") == 1
                _PMACDC.constraint_conv_firing_angle(pm, i; nw = n)
            end
        end
    end

     # Common binary among all the scenarios
    for n in _FP.nw_ids(pm)
        for i in _PM.ids(pm, :switch, nw=n)
            constraint_switching_binaries_hour(pm, n, i)
        end
    end

    constraint_limit_switching_actions_single_switches(pm)
    constraint_limit_switching_actions(pm)

    # Objective function
    objective_stochastic_opf(pm)

end