export run_stochastic_acdcsw_AC_ZIL
export run_stochastic_acdcsw_AC_ZIL_limited_actions

# AC Busbar splitting for AC/DC grid
"ACDC opf with controllable switches in AC busbar splitting configuration for AC/DC grids"
function run_stochastic_acdcsw_AC_ZIL(file, model_constructor, optimizer; kwargs...)
    _FP.require_dim(file, :hour, :scenario)
    return _PM.solve_model(file, model_constructor, optimizer, build_stochastic_acdcsw_AC_ZIL; 
    ref_extensions=[_PMACDC.add_ref_dcgrid!,_PM.ref_add_on_off_va_bounds!], 
    multinetwork = true,
    kwargs...)
end

""
function build_stochastic_acdcsw_AC_ZIL(pm::_PM.AbstractPowerModel)
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
    _FP.require_dim(file, :hour, :scenario)
    return _PM.solve_model(file, model_constructor, optimizer, build_stochastic_acdcsw_AC_ZIL_limited_actions; 
    ref_extensions=[_PMACDC.add_ref_dcgrid!,_PM.ref_add_on_off_va_bounds!], 
    multinetwork = true,
    kwargs...)
end

""
function build_stochastic_acdcsw_AC_ZIL_limited_actions(pm::_PM.AbstractPowerModel)
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