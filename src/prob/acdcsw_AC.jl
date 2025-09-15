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
    objective_stochastic_ac_switch(pm)

end


function run_stochastic_acdcsw_AC_ZIL_hourly(file, model_constructor, optimizer; kwargs...)
    #_FP.require_dim(file, :hour, :scenario)
    return _PM.solve_model(file, model_constructor, optimizer, build_stochastic_acdcsw_AC_ZIL_hourly; 
    ref_extensions=[_PMACDC.add_ref_dcgrid!,_PM.ref_add_on_off_va_bounds!], 
    multinetwork = true,
    kwargs...)
end

""
function build_stochastic_acdcsw_AC_ZIL_hourly(pm::_PM.AbstractPowerModel)
    # Variables
    for (n,network) in pm.ref[:it][_PM.pm_it_sym][:nw]
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
    for (n,network) in pm.ref[:it][_PM.pm_it_sym][:nw]
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
     for (n,network) in pm.ref[:it][_PM.pm_it_sym][:nw]
        for i in _PM.ids(pm, :switch, nw=n)
            constraint_switching_binaries_hour(pm, n, i)
        end
    end

    # Objective function
    objective_stochastic_opf_hourly(pm)

end

function run_stochastic_acdcsw_AC_ZIL_hourly_sp(file, model_constructor, optimizer; kwargs...)
    #_FP.require_dim(file, :hour, :scenario)
    return _PM.solve_model(file, model_constructor, optimizer, build_stochastic_acdcsw_AC_ZIL_hourly_sp; 
    ref_extensions=[_PMACDC.add_ref_dcgrid!,_PM.ref_add_on_off_va_bounds!], 
    multinetwork = true,
    kwargs...)
end

""
function build_stochastic_acdcsw_AC_ZIL_hourly_sp(pm::_PM.AbstractPowerModel)
    # Variables
    for (n,network) in pm.ref[:it][_PM.pm_it_sym][:nw]
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
    for (n,network) in pm.ref[:it][_PM.pm_it_sym][:nw]
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
     for (n,network) in pm.ref[:it][_PM.pm_it_sym][:nw]
        for i in _PM.ids(pm, :switch, nw=n)
            constraint_switching_binaries_hour(pm, n, i)
        end
    end

    # Objective function
    objective_stochastic_opf_hourly(pm)

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
    objective_stochastic_ac_switch(pm)
    #objective_stochastic_opf(pm)

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
        objective_stochastic_ac_switch(pm)
    #objective_stochastic_opf(pm)


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
        objective_stochastic_ac_switch(pm)
    #objective_stochastic_opf(pm)


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
        objective_stochastic_ac_switch(pm)
    #objective_stochastic_opf(pm)


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
        objective_stochastic_ac_switch(pm)
    #objective_stochastic_opf(pm)


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
        objective_stochastic_ac_switch(pm)
    #objective_stochastic_opf(pm)


end

""

function run_stochastic_acdcsw_AC_ZIL_limit_switching_actions(file, model_constructor, optimizer; kwargs...)
    #_FP.require_dim(file, :hour, :scenario)
    return _PM.solve_model(file, model_constructor, optimizer, build_stochastic_acdcsw_AC_ZIL_limit_switching_actions; 
    ref_extensions=[_PMACDC.add_ref_dcgrid!,_PM.ref_add_on_off_va_bounds!], 
    multinetwork = true,
    kwargs...)
end

""
function build_stochastic_acdcsw_AC_ZIL_limit_switching_actions(pm::_PM.AbstractPowerModel)
    # Variables
    for n in 1:length(pm.ref[:it][_PM.pm_it_sym][:nw])
        _PM.variable_bus_voltage(pm; nw = n)
        _PM.variable_gen_power(pm; nw = n)
        _PM.variable_branch_power(pm; nw = n)

        _PMTP.variable_switch_indicator(pm; nw = n) # binary variable to indicate the status of an ac switch
        _PMTP.variable_switch_power(pm; nw = n) # variable to indicate the power flowing through an ac switch (if closed)
        variable_switch_action(pm; nw = n)

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

    constraint_limit_number_of_switching_actions(pm)
    constraint_sum_of_switching_actions(pm)

    # Objective function
    objective_multistep_ac_switch(pm)
    #objective_stochastic_opf(pm)


end

function run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp(file, model_constructor, optimizer; kwargs...)
    #_FP.require_dim(file, :hour, :scenario)
    return _PM.solve_model(file, model_constructor, optimizer, build_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp; 
    ref_extensions=[_PMACDC.add_ref_dcgrid!,_PM.ref_add_on_off_va_bounds!], 
    multinetwork = true,
    kwargs...)
end

function run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches(file, model_constructor, optimizer; kwargs...)
    #_FP.require_dim(file, :hour, :scenario)
    return _PM.solve_model(file, model_constructor, optimizer, build_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches; 
    ref_extensions=[_PMACDC.add_ref_dcgrid!,_PM.ref_add_on_off_va_bounds!], 
    multinetwork = true,
    kwargs...)
end

""
function build_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp(pm::_PM.AbstractPowerModel)
    # Variables
    for n in 1:length(pm.ref[:it][_PM.pm_it_sym][:nw])
        _PMTP.variable_bus_voltage_sp(pm; nw = n)
        _PMTP.variable_gen_power_sp(pm; nw = n)
        _PM.variable_branch_power(pm; nw = n)

        _PMTP.variable_switch_indicator_sp(pm; nw = n) # binary variable to indicate the status of an ac switch
        _PMTP.variable_switch_power(pm; nw = n) # variable to indicate the power flowing through an ac switch (if closed)
        variable_switch_action(pm; nw = n)


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

    # Dirty implementation for now but it works, to be fixed later
    constraint_limit_number_of_switching_actions(pm)
    constraint_sum_of_switching_actions(pm)

    # Objective function
    objective_multistep_ac_switch(pm)
    #objective_stochastic_opf(pm)


end

function build_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches(pm::_PM.AbstractPowerModel)
    # Variables
    for n in 1:length(pm.ref[:it][_PM.pm_it_sym][:nw])
        _PMTP.variable_bus_voltage_sp(pm; nw = n)
        _PMTP.variable_gen_power_sp(pm; nw = n)
        _PM.variable_branch_power(pm; nw = n)

        _PMTP.variable_switch_indicator_sp(pm; nw = n) # binary variable to indicate the status of an ac switch
        _PMTP.variable_switch_power(pm; nw = n) # variable to indicate the power flowing through an ac switch (if closed)
        variable_switch_action_all_switches(pm; nw = n)


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

    # Dirty implementation for now but it works, to be cleaned up later hopefully
    constraint_limit_number_of_switching_actions_all_switches(pm)
    constraint_limit_switching_actions_all_switches(pm)
    for n in 1:length(pm.ref[:it][_PM.pm_it_sym][:nw])
        constraint_equalling_all_switching_actions_in_one_hour(pm,n)
    end
    # Objective function
    objective_multistep_ac_switch(pm)
    #objective_stochastic_opf(pm)


end



function run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches_stochastic(file, model_constructor, optimizer; kwargs...)
    #_FP.require_dim(file, :hour, :scenario)
    return _PM.solve_model(file, model_constructor, optimizer, build_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches_stochastic; 
    ref_extensions=[_PMACDC.add_ref_dcgrid!,_PM.ref_add_on_off_va_bounds!], 
    multinetwork = true,
    kwargs...)
end

""

function build_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches_stochastic(pm::_PM.AbstractPowerModel)
    # Variables
    for n in 1:length(pm.ref[:it][_PM.pm_it_sym][:nw])
        _PMTP.variable_bus_voltage_sp(pm; nw = n)
        _PMTP.variable_gen_power_sp(pm; nw = n)
        _PM.variable_branch_power(pm; nw = n)

        _PMTP.variable_switch_indicator_sp(pm; nw = n) # binary variable to indicate the status of an ac switch
        _PMTP.variable_switch_power(pm; nw = n) # variable to indicate the power flowing through an ac switch (if closed)
        variable_switch_action_all_switches(pm; nw = n)


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

    # Dirty implementation for now but it works, to be cleaned up later hopefully
    constraint_limit_number_of_switching_actions_all_switches_stochastic(pm)

    for i in _PM.ids(pm, 1, :switch)
        constraint_equalling_all_switching_actions_in_one_hour_stochastic(pm,i) 
        constraint_limit_switching_actions_all_switches_stochastic(pm,i)
    end


    # Objective function
    objective_multistep_ac_switch(pm)
    #objective_stochastic_opf(pm)


end








function run_stochastic_acdcsw_AC_ZIL_one_topology(file, model_constructor, optimizer; kwargs...)
    #_FP.require_dim(file, :hour, :scenario)
    return _PM.solve_model(file, model_constructor, optimizer, build_stochastic_acdcsw_AC_ZIL_one_topology; 
    ref_extensions=[_PMACDC.add_ref_dcgrid!,_PM.ref_add_on_off_va_bounds!], 
    multinetwork = true,
    kwargs...)
end

""
function build_stochastic_acdcsw_AC_ZIL_one_topology(pm::_PM.AbstractPowerModel)
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
            constraint_equalling_all_binaries(pm, i; nw = n)
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

    # Objective function
    objective_multistep_ac_switch(pm)
    #objective_stochastic_opf(pm)


end

function run_stochastic_acdcsw_AC_ZIL_one_topology_sp(file, model_constructor, optimizer; kwargs...)
    #_FP.require_dim(file, :hour, :scenario)
    return _PM.solve_model(file, model_constructor, optimizer, build_stochastic_acdcsw_AC_ZIL_one_topology_sp; 
    ref_extensions=[_PMACDC.add_ref_dcgrid!,_PM.ref_add_on_off_va_bounds!], 
    multinetwork = true,
    kwargs...)
end

""
function build_stochastic_acdcsw_AC_ZIL_one_topology_sp(pm::_PM.AbstractPowerModel)
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
            constraint_equalling_all_binaries(pm, i; nw = n)
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

    # Objective function
    objective_multistep_ac_switch(pm)
    #objective_stochastic_opf(pm)


end

""
function run_acdcsw_AC_big_M_hour_scenarios(file, model_constructor, optimizer; kwargs...)
    return _PM.solve_model(file, model_constructor, optimizer, build_acdcsw_AC_big_M_hour_scenarios; ref_extensions=[_PMACDC.add_ref_dcgrid!,_PM.ref_add_on_off_va_bounds!], kwargs...)
end

""
function build_acdcsw_AC_big_M_hour_scenarios(pm::_PM.AbstractPowerModel)
    
    # AC grid
    _PM.variable_bus_voltage(pm)
    _PM.variable_gen_power(pm)
    _PM.variable_branch_power(pm)

    variable_switch_indicator(pm) # binary variable to indicate the status of an ac switch
    variable_switch_power(pm) # variable to indicate the power flowing through an ac switch (if closed)

    # DC grid
    _PMACDC.variable_active_dcbranch_flow(pm)
    _PMACDC.variable_dcbranch_current(pm)
    _PMACDC.variable_dc_converter(pm)
    _PMACDC.variable_dcgrid_voltage_magnitude(pm)

    # Objective function
    objective_min_fuel_cost_ac_switch(pm)

    # Constraints
    _PM.constraint_model_voltage(pm)
    _PMACDC.constraint_voltage_dc(pm)

    for i in _PM.ids(pm, :ref_buses)
        _PM.constraint_theta_ref(pm, i)
    end

    for i in _PM.ids(pm, :bus)
        constraint_power_balance_ac_switch(pm, i) # including the ac switches in the power balance of the AC part of an AC/DC grid
    end

    for i in _PM.ids(pm, :switch)
        constraint_switch_thermal_limit(pm, i) # limiting the apparent power flowing through an ac switch
        constraint_switch_power_on_off(pm,i) # limiting the maximum active and reactive power through an ac switch
        constraint_switch_voltage_on_off_big_M(pm,i)
    end

    for i in _PM.ids(pm, :switch_couples)
        constraint_exclusivity_switch(pm, i) # the sum of the switches in a couple must be lower or equal than one (if OTS is allowed, like here), as each grid element is connected to either part of a split busbar no matter if the ZIL switch is opened or closed
        constraint_BS_OTS_branch(pm,i) # making sure that if the grid element is not reconnected to the split busbar, the active and reactive power flowing through the switch is 0
    end

    for i in _PM.ids(pm, :branch)
        _PM.constraint_ohms_yt_from(pm, i)
        _PM.constraint_ohms_yt_to(pm, i)
        _PM.constraint_voltage_angle_difference(pm, i)
        _PM.constraint_thermal_limit_from(pm, i)
        _PM.constraint_thermal_limit_to(pm, i)
    end

    for i in _PM.ids(pm, :busdc)
        _PMACDC.constraint_power_balance_dc(pm, i)
    end
    for i in _PM.ids(pm, :branchdc)
        _PMACDC.constraint_ohms_dc_branch(pm, i)
    end
    for i in _PM.ids(pm, :convdc)
        constraint_converter_losses(pm, i)
        _PMACDC.constraint_converter_current(pm, i)
        _PMACDC.constraint_conv_transformer(pm, i)
        _PMACDC.constraint_conv_reactor(pm, i)
        _PMACDC.constraint_conv_filter(pm, i)
        if pm.ref[:it][:pm][:nw][_PM.nw_id_default][:convdc][i]["islcc"] == 1
            _PMACDC.constraint_conv_firing_angle(pm, i)
        end
    end
end
