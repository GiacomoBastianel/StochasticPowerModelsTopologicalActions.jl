using PowerModels; const _PM = PowerModels
using PowerModelsACDC; const _PMACDC = PowerModelsACDC
import PowerModelsTopologicalActionsII; const _PMTP = PowerModelsTopologicalActionsII
using FlexPlan; const _FP = FlexPlan
using Gurobi, Ipopt, JSON, Plots
import StochasticPowerModelsTopologicalActions; const _SPMTA = StochasticPowerModelsTopologicalActions
using JuMP, Juniper, HSL_jll, MathOptInterface, HiGHS
using Statistics

mip_gap = 1e-3
gurobi_bs = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 5400,"MIPGap" => mip_gap,"BarHomogeneous" => 1, "NumericFocus"=>2) 
gurobi = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 1800,"MIPGap" => mip_gap,"BarHomogeneous" => 1,"BarQCPConvTol"=>1e-6,"QCPDual" => 1, "ScaleFlag"=>2, "NumericFocus"=>2) 
gurobi_opf = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 1200,"MIPGap" => mip_gap,"BarHomogeneous" => 1, "NumericFocus"=>2,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "ScaleFlag"=>2, "NumericFocus"=>3) 
gurobi_lpac = JuMP.optimizer_with_attributes(Gurobi.Optimizer)#,"time_limit" => 1200,"MIPGap" => mip_gap,"BarHomogeneous" => 1,"BarQCPConvTol"=>1e-4,"QCPDual" => 1, "ScaleFlag"=>2, "NumericFocus"=>2)
ipopt = JuMP.optimizer_with_attributes(Ipopt.Optimizer, "tol" => 1e-6, "print_level" => 0,"linear_solver" => "ma97")
juniper = JuMP.optimizer_with_attributes(Juniper.Optimizer, "nl_solver" => ipopt, "mip_solver" => gurobi, "time_limit" => 36000)

#########################################################################################
## Processing input data
s = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true)
s_dual = Dict("output" => Dict("branch_flows" => true,"duals" => true), "conv_losses_mp" => true)

#########################################################################################
## Processing input data
input_folder = dirname(dirname(dirname(@__DIR__)))
test_case_file = joinpath(input_folder,"data_sources/pglib_opf_case30_ieee.m")
original_grid = _PM.parse_file(test_case_file)

results_folder = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/IJEPES_paper/Results"
case = "case_30/stochastic_multistep"

test_case = _PM.parse_file(test_case_file)
test_case_opf = deepcopy(test_case)

# THIS IS APPARENTLY FUNDAMENTAL TO GUARANTEE FEASIBILITY
_SPMTA.add_VOLL_generators(test_case_opf)
_SPMTA.add_VOLL_generators(test_case)

opf_30 = _PM.solve_opf(test_case_opf, LPACCPowerModel, ipopt)

#########################################################################################
# Busbar splitting
test_case_bs = deepcopy(test_case_opf)
splitted_bus_ac = 6
test_case_bs,  switches_couples_ac,  extremes_ZILs_ac  = _PMTP.AC_busbar_split_AC_grid(test_case,splitted_bus_ac)

# Adding costs to the busbar couplers
for sw_id in 1:length(extremes_ZILs_ac)
    test_case_bs["switch"]["$sw_id"]["cost"] = 10.0
end

result_bs_6 = _PMTP.run_acdcsw_AC_big_M_hour(test_case_bs, LPACCPowerModel, gurobi)
result_bs_6_no_cost = _PMTP.run_acdcsw_AC_big_M(test_case_bs, LPACCPowerModel, gurobi)


feasibility_check = deepcopy(test_case_bs)
feasibility_check_input = deepcopy(test_case_bs)
_PMTP.prepare_AC_feasibility_check(result_bs_6,feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
result_feasibility_check = _PMACDC.run_acdcopf(feasibility_check,ACPPowerModel,ipopt; setting = s)


feasibility_check_pf = deepcopy(feasibility_check)
for (b_id,b) in feasibility_check_pf["gen"]
    if test_case_bs["bus"]["$(b["gen_bus"])"]["bus_type"] == 1
        feasibility_check_pf["bus"]["$(b["gen_bus"])"]["bus_type"] = 2
    end
end

for (g_id,g) in feasibility_check_pf["gen"]
    g["pg"] = result_feasibility_check["solution"]["gen"]["$g_id"]["pg"]
    g["qg"] = result_feasibility_check["solution"]["gen"]["$g_id"]["qg"]
end
for (g_id,g) in feasibility_check_pf["bus"]
    g["va"] = result_feasibility_check["solution"]["bus"]["$g_id"]["va"]
    g["vm"] = result_feasibility_check["solution"]["bus"]["$g_id"]["vm"]
end

pf_check_ac = _PM.solve_pf(feasibility_check_pf, ACPPowerModel, ipopt; setting = s)


for (g_id,g) in feasibility_check_pf["gen"]
    if pf_check_ac["solution"]["gen"]["$g_id"]["pg"] >= 0.05
        println("PF Generator $g_id is ON, pg = ", pf_check_ac["solution"]["gen"]["$g_id"]["pg"])
    end
    if result_feasibility_check["solution"]["gen"]["$g_id"]["pg"] >= 0.05
        println("OPF Generator $g_id is ON, pg = ", result_feasibility_check["solution"]["gen"]["$g_id"]["pg"])
    end
end
#########################################################################################
# Add dimensions for stochastic part
n_scenarios = 4
n_hours = 24
one_scenario = 1
hours = collect(1:n_hours)
_SPMTA.add_dimensions!(test_case_bs,n_scenarios,n_hours)

start_hour_simulation = 1
end_hour_simulation = 8760

#########################################################################################
# Uploading pdf samples for offshore wind and load data for Belgium
year_wind = "2024"
folder_data = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Elia_data"
#folder_results = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/Deliverable_1_2_DIRECTIONS/Results/case_30"

Gaussian_samples = JSON.parsefile(joinpath(folder_data,"Gaussian_samples_8_Offshore_wind_$(year_wind)_Elia.json"))
Elia_OFW = JSON.parsefile(joinpath(folder_data,"Offshore_wind_$(year_wind)_Elia_sorted.json"))

# Only hours
differences_gen = [(Elia_OFW[i]["dayahead11hforecast"] - Elia_OFW[i]["measured"]) for i in 1:length(Elia_OFW) if Elia_OFW[i]["minute"] == "00"]
capacity_factors_ofw = [Elia_OFW[i]["measured"]/Elia_OFW[i]["monitoredcapacity"] for i in 1:length(Elia_OFW) if Elia_OFW[i]["minute"] == "00"]
is = [i for i in 1:length(Elia_OFW) if Elia_OFW[i]["minute"] == "00"]
capacity_factors_30 = capacity_factors_ofw[start_hour_simulation:end_hour_simulation]

Load_2024 = JSON.parsefile(joinpath(folder_data,"Elia_load_$(year_wind).json"))
total_loads = [Load_2024[i]["totalload"] for i in 1:length(Load_2024)]
max_load = maximum(total_loads)

# Time series
Wind_data = Dict{String,Any}()
for i in hours
    h = start_hour_simulation + i - 1
    hw = is[i]   
    Wind_data["$h"] = Dict{String,Any}()
    Wind_data["$h"]["most_recent_forecast_pu"] = Elia_OFW[hw]["mostrecentforecast"]/Elia_OFW[hw]["monitoredcapacity"]
    Wind_data["$h"]["measured_pu"] = Elia_OFW[hw]["measured"]/Elia_OFW[hw]["monitoredcapacity"]
    Wind_data["$h"]["P50_11hforecast_pu"] = Elia_OFW[hw]["dayahead11hforecast"]/Elia_OFW[hw]["monitoredcapacity"]
    Wind_data["$h"]["samples_pu"] = Gaussian_samples["$hw"]["samples_pu"]
    Wind_data["$h"]["pdf_normalized"] = Gaussian_samples["$hw"]["pdf_normalized"]
    Wind_data["$h"]["Elia_timestep"] = is[i]
end

Load_data = Dict{String,Any}()
for i in hours
    h = start_hour_simulation + i - 1
    hw = is[i]   
    Load_data["$h"] = Dict{String,Any}()
    Load_data["$h"]["total_load"] = Load_2024[hw]["totalload"]
    Load_data["$h"]["total_load_pu"] = Load_2024[hw]["totalload"]/max_load
    Load_data["$h"]["Elia_timestep"] = is[i]
end


measured_wind   = [Wind_data["$i"]["measured_pu"]   for i in 1:length(hours)]
forecasted_wind = [Wind_data["$i"]["P50_11hforecast_pu"] for i in 1:length(hours)]
load_pu = [Load_data["$i"]["total_load_pu"] for i in 1:length(hours)]


P50_11h = []
for i in 1:length(Elia_OFW)
    if Elia_OFW[i]["minute"] == "00"
        push!(P50_11h,Elia_OFW[i]["dayahead11hforecast"]/Elia_OFW[i]["monitoredcapacity"])
    end
end

measured_11h = []
for i in 1:length(Elia_OFW)
    if Elia_OFW[i]["minute"] == "00"
        push!(measured_11h,Elia_OFW[i]["measured"]/Elia_OFW[i]["monitoredcapacity"])
    end
end

diff_ = measured_11h .- P50_11h
scatter(diff_)
histogram(diff_, bins=50, normalize=true,xticks = -1.0:0.1:1.0,xlims = (-1.0,1.0),
ylims = (0,8),xlabel = "Forecast error [pu]",ylabel = "Probability density [-]",
color = :green,legend =:none,grid = :none, xlabelfontsize = 10,ylabelfontsize = 10)

using KernelDensity, Distributions, StatsBase, Random
normal_fit = fit(Normal, diff_)
println("Fitted Normal: μ = $(mean(normal_fit)), σ = $(std(normal_fit))")


forecast = 0.9663144865390567  # e.g., forecasted wind power in MW
N = 10000          # number of scenarios
N_4 = 4
N_8 = 8


sorted_diff_ = sort(diff_)
kde_ = kde(sorted_diff_)
pdf_value = pdf(kde_, -0.945)

n_scenarios = 10

# Sample errors from KDE

# Generate wind scenarios
sampled_errors = rand(normal_fit, N)
scenarios = forecast .+ sampled_errors
clamped_scenarios = clamp.(scenarios, 0.0, 1.0)

sampled_errors_4 = rand(normal_fit, N_4)
scenarios_4 = forecast .+ sampled_errors_4
clamped_scenarios_4 = clamp.(scenarios_4, 0.0, 1.0)

sampled_errors_8 = rand(normal_fit, N_8)
scenarios_8 = forecast .+ sampled_errors_8
clamped_scenarios_8 = clamp.(scenarios_8, 0.0, 1.0)

histogram(clamped_scenarios, bins=50, normalize=true, label="Scenarios")
vline!([forecast], label="Forecast", lw=2, lc=:red)

histogram(clamped_scenarios_4, bins=50, normalize=true, label="Scenarios")
vline!([forecast], label="Forecast", lw=2, lc=:red)

histogram(clamped_scenarios_8, bins=50, normalize=true, label="Scenarios")
vline!([forecast], label="Forecast", lw=2, lc=:red)


sampled_errors_prob = []
for i in 1:length(sampled_errors_4)
    push!(sampled_errors_prob, pdf(kde_, sampled_errors_4[i]))
end
sampled_errors_rel_prob = sampled_errors_prob ./ sum(sampled_errors_prob)



first_hour = 355
last_hour  = 378


#first_hour = 6590
#last_hour  = 6613

forecasted_wind = P50_11h[first_hour:last_hour]
measured_wind   = measured_11h[first_hour:last_hour]
hours_simulation_Elia = collect(first_hour:last_hour)

n_hours = last_hour - first_hour + 1
start_hour_simulation = 1
end_hour_simulation = last_hour - first_hour + 1
hours = collect(start_hour_simulation:end_hour_simulation)
n_scenarios = 4
one_scenario = 1


expected_value_wind = []
scenarios_wind = Dict{String,Any}()
count_hour = 0
for i in hours_simulation_Elia
    count_hour += 1
    expected_value_wind_hourly = 0.0  
    for s in 1:n_scenarios
        n = (count_hour - 1)*n_scenarios + s
        scenarios_wind["$n"] = Dict{String,Any}()
        scenarios_wind["$n"]["probability"] = deepcopy(expected_h["$i"]["pdf_normalized"][s])
        scenarios_wind["$n"]["samples_pu"] = deepcopy(expected_h["$i"]["samples_pu"][s])
        scenarios_wind["$n"]["hour"] = i
        scenarios_wind["$n"]["scenario"] = s
        expected_value_wind_hourly += expected_h["$i"]["samples_pu"][s]*expected_h["$i"]["pdf_normalized"][s]
    end
    push!(expected_value_wind, expected_value_wind_hourly)
end


forecasted_wind[20] = forecasted_wind[1]
forecasted_wind[21] = forecasted_wind[2]
forecasted_wind[22] = forecasted_wind[3]
forecasted_wind[23] = forecasted_wind[4]
forecasted_wind[24] = forecasted_wind[5]

measured_wind[20] = measured_wind[1]
measured_wind[21] = measured_wind[2]
measured_wind[22] = measured_wind[3]
measured_wind[23] = measured_wind[4]
measured_wind[24] = measured_wind[5]

expected_value_wind[20] = expected_value_wind[1]
expected_value_wind[21] = expected_value_wind[2]
expected_value_wind[22] = expected_value_wind[3]
expected_value_wind[23] = expected_value_wind[4]
expected_value_wind[24] = expected_value_wind[5]
for h in 20:24
    for s in 1:n_scenarios
        l = (h - 1)*n_scenarios + s
        n = (h - 19)*n_scenarios + s
        scenarios_wind["$l"] = scenarios_wind["$n"]
    end
end


json_forecasted_wind     = JSON.json(forecasted_wind    )
json_measured_wind       = JSON.json(measured_wind      )
json_expected_value_wind = JSON.json(expected_value_wind)
json_scenarios_wind      = JSON.json(scenarios_wind     )

plot(1:n_hours,forecasted_wind, label = "Forecasted", grid = :none,xticks = 1:n_hours,yticks = 0:0.2:1,ylims = (-0.01,1.1),xlims = (0.8,n_hours+0.2),xlabel = "Hour",ylabel = "Capacity factor [-]"
,legend = :topright,xlabelfontsize = 10,ylabelfontsize = 10,xtickfont = font(8),ytickfont = font(8))
plot!(measured_wind, label = "Measured")
plot!(expected_value_wind, label = "Expected value")
savefig(joinpath(results_folder_figures,case_figures,"Wind_capacity_factors_$(first_hour)_$(last_hour)_modified.svg"))
 

open(joinpath(@__DIR__,"forecasted_wind_hours_$(first_hour)_$(last_hour)_modified.json"),"w") do f 
    write(f, json_forecasted_wind) 
end 
open(joinpath(@__DIR__,"measured_wind_$(first_hour)_$(last_hour)_modified.json"),"w") do f 
    write(f, json_measured_wind) 
end 
open(joinpath(@__DIR__,"expected_value_wind_$(first_hour)_$(last_hour)_modified.json"),"w") do f 
    write(f, json_expected_value_wind) 
end 
open(joinpath(@__DIR__,"scenarios_wind_$(first_hour)_$(last_hour)_modified.json"),"w") do f 
    write(f, json_scenarios_wind) 
end 



values = []
x_values = []
x_values_single = []
first_hour_show = 13
last_hour_show = 24
for i in first_hour_show:last_hour_show
    push!(x_values_single,i)
    for s in 1:n_scenarios
        l = (i - 1)*n_scenarios + s
        push!(values,scenarios_wind["$l"]["samples_pu"])
        push!(x_values,i)
    end
end
scatter(x_values,values,label = "Scenario samples",grid = :none,ylims = (-0.01,1.1),xticks = 1:n_hours,yticks = 0:0.2:1,xlims = (first_hour_show-0.2,last_hour_show+0.2),xlabel = "Hour",ylabel = "Capacity factor [-]",
legend = :bottomleft,xlabelfontsize = 10,ylabelfontsize = 10,xtickfont = font(8),ytickfont = font(8))
scatter!(x_values_single,forecasted_wind[first_hour_show:last_hour_show],label = "Forecasted")
scatter!(x_values_single,measured_wind[first_hour_show:last_hour_show],label = "Measured")

savefig(joinpath(results_folder_figures,case_figures,"Wind_capacity_factors_with_samples_$(first_hour)_$(last_hour)_$(first_hour_show)_$(last_hour_show)_modified.svg"))


scatter(x_values[1:n_scenarios*2],values[1:n_scenarios*2],label = "Scenario samples",grid = :none,xlims = (0.8,2.4))
for i in 1:n_scenarios*2
    annotate!(x_values[i]+0.03, values[i]+0.001, (x_values_single[i], 9, :blue))
end
display(current())


diff_forecasted_measured = []
for h in 1:length(P50_11h)
    push!(diff_forecasted_measured,abs((P50_11h[h] - measured_11h[h])))
end

###############################
# Messy, let me try if it works first
using KernelDensity, Distributions, StatsBase, Random

diff_ = measured_11h .- P50_11h
scatter(diff_*100,grid = :none, ylabel = "Error difference between forecasted and measured value [%]",label=:none,ylabelfontsize = 8,ylims = (-100,100))
histogram(diff_, bins=50, normalize=true,xticks = -1.0:0.1:1.0,xlims = (-1.0,1.0),
ylims = (0,8),xlabel = "Forecast error [pu]",ylabel = "Probability density [-]",
color = :green,legend =:none,grid = :none, xlabelfontsize = 10,ylabelfontsize = 10)

normal_fit = fit(Normal, diff_)
println("Fitted Normal: μ = $(mean(normal_fit)), σ = $(std(normal_fit))")

# Creating two series of scenarios
#N = 10000          # number of scenarios
N_4 = 4
N_8 = 8

# Creating pdf of the actual error
sorted_diff_ = sort(diff_)
kde_ = kde(sorted_diff_)

#pdf_value = pdf(kde_, -0.945) -> this gives the probability of getting this


# Sample errors from KDE
sampled_errors_4_dict = Dict{String,Any}()
sampled_errors_8_dict = Dict{String,Any}()
for i in 1:length(forecasted_wind)
    sampled_errors_4_dict["$i"] = rand(normal_fit, N_4)
    sampled_errors_8_dict["$i"] = rand(normal_fit, N_8)
end

p1 = scatter(ones(length(sampled_errors_4_dict["1"])),sampled_errors_4_dict["1"])
for i in 2:24
    scatter!(p1,ones(length(sampled_errors_4_dict["$i"])),sampled_errors_4_dict["$i"])
end

N_4 = 4
N_8 = 8
scenarios_wind_4 = Dict{String,Any}()
scenarios_wind_8 = Dict{String,Any}()
n_hours = 24
# Generate wind scenarios
for i in 1:n_hours
    for s in 1:N_4
        h = (i - 1)*N_4 + s
        scenarios_wind_4["$h"] = Dict{String,Any}()
        scenarios_wind_4["$h"]["scenario"] = s 
        scenarios_wind_4["$h"]["hour"] = first_hour - 1 + i 
        scenarios_wind_4["$h"]["sampled_error"] = sampled_errors_4_dict["$i"][s]
        scenarios_wind_4["$h"]["error"] = sampled_errors_4_dict["$i"][s]
        scenarios_wind_4["$h"]["samples_pu"] = forecasted_wind[i] + sampled_errors_4_dict["$i"][s]
        if scenarios_wind_4["$h"]["samples_pu"] > 1.0
            orig_sample = deepcopy(scenarios_wind_4["$h"]["samples_pu"])
            #clamp.(scenarios_wind_4["$h"]["samples_pu"], 0.0, 1.0)
            scenarios_wind_4["$h"]["samples_pu"] = 1.0
            scenarios_wind_4["$h"]["error"] = scenarios_wind_4["$h"]["samples_pu"] - forecasted_wind[i]
        end
        scenarios_wind_4["$h"]["probability_abs"] = pdf(kde_, scenarios_wind_4["$h"]["error"]) 
    end
    for s in 1:N_4
        h = (i - 1)*N_4 + s
        h_sum_first = (i - 1)*N_4 + 1
        h_sum_last = (i - 1)*N_4 + N_4
        scenarios_wind_4["$h"]["probability"] = scenarios_wind_4["$h"]["probability_abs"]./sum(scenarios_wind_4["$h_sum"]["probability_abs"] for h_sum in h_sum_first:h_sum_last)
    end
    for s in 1:N_8
        h = (i - 1)*N_8 + s
        scenarios_wind_8["$h"] = Dict{String,Any}()
        scenarios_wind_8["$h"]["scenario"] = s 
        scenarios_wind_8["$h"]["hour"] = first_hour - 1 + i 
        scenarios_wind_8["$h"]["sampled_error"] = sampled_errors_8_dict["$i"][s]
        scenarios_wind_8["$h"]["error"] = sampled_errors_8_dict["$i"][s]
        scenarios_wind_8["$h"]["samples_pu"] = forecasted_wind[i] + sampled_errors_8_dict["$i"][s]
        if scenarios_wind_8["$h"]["samples_pu"] > 1
            orig_sample = deepcopy(scenarios_wind_8["$h"]["samples_pu"])
            scenarios_wind_8["$h"]["samples_pu"] = 1.0
            scenarios_wind_8["$h"]["error"] = scenarios_wind_8["$h"]["samples_pu"] - forecasted_wind[i]
        end
        scenarios_wind_8["$h"]["probability_abs"] = pdf(kde_, sampled_errors_8_dict["$i"][s]) 
    end
    for s in 1:N_8
        h = (i - 1)*N_8 + s
        h_sum_first = (i - 1)*N_8 + 1
        h_sum_last = (i - 1)*N_8 + N_8
        scenarios_wind_8["$h"]["probability"] = scenarios_wind_8["$h"]["probability_abs"]./sum(scenarios_wind_8["$h_sum"]["probability_abs"] for h_sum in h_sum_first:h_sum_last)
    end
end

x_values_4 = []
x_values_8 = []
forecasted_values_4 = []
forecasted_values_8 = []
first_hour_show = 1
last_hour_show = 24
for i in first_hour_show:last_hour_show
    for s in 1:N_4
        l = (i - 1)*N_4 + s
        push!(x_values_4,i)
        push!(forecasted_values_4,forecasted_wind[i])
    end
    for s in 1:N_8
        l = (i - 1)*N_8 + s
        push!(x_values_8,i)
        push!(forecasted_values_8,forecasted_wind[i])
    end
end
errors_4 = [scenarios_wind_4["$i"]["error"] for i in 1:(N_4*24)]
forecast_4 = [forecasted_values_4[i]+scenarios_wind_4["$i"]["error"] for i in 1:(N_4*24)]
errors_8 = [scenarios_wind_8["$i"]["error"] for i in 1:(N_8*24)]
forecast_8 = [forecasted_values_8[i]+scenarios_wind_8["$i"]["error"] for i in 1:(N_8*24)]

hours = collect(1:24)
scatter(hours,measured_wind,label = "Measured")
scatter!(hours,forecasted_wind,label = "Forecasted")
scatter!(x_values_4,forecast_4,xticks = 1:1:24,label = "Stochastic")

scatter(hours,measured_wind,label = "Measured")
scatter!(hours,forecasted_wind,label = "Forecasted")
scatter!(x_values_8,forecast_8,xticks = 1:1:24,label = "Stochastic")


json_scenario_4 = JSON.json(scenarios_wind_4)
open(joinpath(results_folder,case,"scenario_wind_4_$(first_hour)_$(last_hour)_modfiied.json"),"w") do f 
    write(f, json_scenario_4) 
end 

json_scenario_8 = JSON.json(scenarios_wind_8)
open(joinpath(results_folder,case,"scenario_wind_8_$(first_hour)_$(last_hour)_modfiied.json"),"w") do f 
    write(f, json_scenario_8) 
end 


#########################################################################################
## Running simulations
# Busbar splitting
test_case_opf_replicate = _PM.replicate(test_case_opf, n_hours*n_scenarios)
test_case_opf_replicate_one_scenario = _PM.replicate(test_case_opf, n_hours*one_scenario)

test_case_opf_mn_measured = deepcopy(test_case_opf_replicate_one_scenario)
test_case_opf_mn_forecasted = deepcopy(test_case_opf_replicate_one_scenario)
test_case_opf_mn_expected = deepcopy(test_case_opf_replicate)
#=
function adding_multinetwork_scenarios(test_case, n_hours, n_scenarios,uncertainty)
    for hour in 1:n_hours
        for scenario_idx in 1:n_scenarios
            n = (hour - 1)*n_scenarios + scenario_idx
            add_hour_scenario_probability(test_case,hour,scenario_idx,n_scenarios,n,uncertainty)
        end
    end
    test_case["scenarios"] = n_scenarios
    test_case["hours"] = n_hours
    return test_case
end

function add_hour_scenario_probability(data,hour,scenario_idx,n_scenarios,index,uncertainty)
    data["nw"]["$index"]["hour"] = hour
    data["nw"]["$index"]["scenario"] = scenario_idx
    data["nw"]["$index"]["hour_scenario_index"] = [hour,scenario_idx,index]
    if n_scenarios == 1
        data["nw"]["$index"]["probability"] = 1.0
        data["nw"]["$index"]["per_unit"] = true
    elseif n_scenarios > 1
        data["nw"]["$index"]["probability"] = uncertainty["$index"]["probability"]
        data["nw"]["$index"]["per_unit"] = true
    end
end
=#
n_hours = 24
_SPMTA.adding_multinetwork_scenarios(test_case_opf_mn_measured,n_hours,one_scenario,scenarios_wind_8)
_SPMTA.adding_multinetwork_scenarios(test_case_opf_mn_forecasted,n_hours,one_scenario,scenarios_wind_8)
_SPMTA.adding_multinetwork_scenarios(test_case_opf_mn_expected,n_hours,N_4,scenarios_wind_4)


for i in 1:(n_hours*one_scenario)
    test_case_opf_mn_measured["nw"]["$i"]["gen"]["1"]["pmax"]   = deepcopy(test_case_opf_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*measured_wind[i])
    test_case_opf_mn_forecasted["nw"]["$i"]["gen"]["1"]["pmax"] = deepcopy(test_case_opf_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*forecasted_wind[i])
end
for i in 1:(n_hours*N_4)
    test_case_opf_mn_expected["nw"]["$i"]["gen"]["1"]["pmax"]   = deepcopy(test_case_opf_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*scenarios_wind_8["$i"]["samples_pu"])
end

################################################################################

result_forecasted_24_ac = Dict{String,Any}()
result_forecasted_24_lpac = Dict{String,Any}()

result_measured_24_ac = Dict{String,Any}()
result_measured_24_lpac = Dict{String,Any}()

result_expected_24_ac = Dict{String,Any}()
result_expected_24_lpac = Dict{String,Any}()

for hour in 1:(n_hours*one_scenario)
    result_forecasted_24_ac["$hour"] = _PM.solve_opf(test_case_opf_mn_forecasted["nw"]["$hour"],ACPPowerModel,ipopt; setting = s)
    result_forecasted_24_lpac["$hour"] = _PM.solve_opf(test_case_opf_mn_forecasted["nw"]["$hour"],LPACCPowerModel,ipopt; setting = s)

    result_measured_24_ac["$hour"] = _PM.solve_opf(test_case_opf_mn_measured["nw"]["$hour"],ACPPowerModel,ipopt; setting = s)
    result_measured_24_lpac["$hour"] = _PM.solve_opf(test_case_opf_mn_measured["nw"]["$hour"],LPACCPowerModel,ipopt; setting = s)
end
for hour in 1:(n_hours*N_4)
    result_expected_24_lpac["$hour"] = _PM.solve_opf(test_case_opf_mn_expected["nw"]["$hour"],LPACCPowerModel,ipopt; setting = s)
end

for (g_id,g) in test_case_opf_mn_forecasted["nw"]["1"]["gen"]
    if result_forecasted_24_lpac["1"]["solution"]["gen"][g_id]["pg"] > 0.001
        println("Gen $g_id, pg $(result_forecasted_24_lpac["1"]["solution"]["gen"][g_id]["pg"])")
    end
end


obj_forecasted_24_ac = [result_forecasted_24_ac["$i"]["objective"] for i in 1:(n_hours*one_scenario)]
obj_forecasted_24_lpac = [result_forecasted_24_lpac["$i"]["objective"] for i in 1:(n_hours*one_scenario)]
obj_measured_24_lpac = [result_measured_24_lpac["$i"]["objective"] for i in 1:(n_hours*one_scenario)]

obj_expected = []
for hour in 1:n_hours
    first_n = (hour - 1)*N_8 + 1
    println("first_n: ", first_n)
    last_n = n_scenarios*hour
    println("last_n: ", last_n)
    opf_hour = sum(result_expected_24_lpac["$h"]["objective"]*test_case_opf_mn_expected["nw"]["$h"]["probability"] for h in first_n:last_n)
    push!(obj_expected,opf_hour)
end

exp_ = sum(obj_expected)
for_ = sum(obj_forecasted_24_lpac)
mea_ = sum(obj_measured_24_lpac)


plot(obj_expected./10^3,label = "Forecasted",grid = :none,ylims = (-0.01,25),xticks = 1:n_hours,xlims = (0.8,24.5),xlabel = "Hour",ylabel = "Generation costs [k€]",
legend = :bottomleft,xlabelfontsize = 10,ylabelfontsize = 10,xtickfont = font(8),ytickfont = font(8))
plot!(obj_measured_24_lpac./10^3,label = "Measured")
plot!(obj_forecasted_24_lpac)
savefig(joinpath(results_folder_figures,case_figures,"OPF_results_$(first_hour)_$(last_hour)_modified.svg"))

#=
json_opf_results_opf_forecasted_ac = JSON.json(result_forecasted_24_ac)
open(joinpath(results_folder,case,"24_hours_OPF_ac_forecasted_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_opf_results_opf_forecasted_ac) 
end 

json_opf_results_opf_forecasted_lpac = JSON.json(result_forecasted_24_lpac)
open(joinpath(results_folder,case,"24_hours_OPF_lpac_forecasted_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_opf_results_opf_forecasted_lpac) 
end 

json_opf_results_opf_measured_ac = JSON.json(result_measured_24_ac)
open(joinpath(results_folder,case,"24_hours_OPF_ac_measured_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_opf_results_opf_measured_ac) 
end 

json_opf_results_opf_measured_lpac = JSON.json(result_measured_24_lpac)
open(joinpath(results_folder,case,"24_hours_OPF_lpac_measured_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_opf_results_opf_measured_lpac) 
end 
=#




###########################################################################
# -> OPFs are comparable now, data set built, need to tweak the functions to have a multistep-stochastic formulation

test_case_bs_replicate = _PM.replicate(test_case_bs, n_hours*n_scenarios)
test_case_bs_replicate_one_scenario = _PM.replicate(test_case_bs, n_hours*one_scenario)

test_case_bs_mn_measured = deepcopy(test_case_bs_replicate_one_scenario)
test_case_bs_mn_forecasted = deepcopy(test_case_bs_replicate_one_scenario)
test_case_bs_mn_expected = deepcopy(test_case_bs_replicate)

_SPMTA.adding_multinetwork_scenarios(test_case_bs_mn_measured,n_hours,one_scenario,scenarios_wind_8)
_SPMTA.adding_multinetwork_scenarios(test_case_bs_mn_forecasted,n_hours,one_scenario,scenarios_wind_8)
_SPMTA.adding_multinetwork_scenarios(test_case_bs_mn_expected,n_hours,N_4,scenarios_wind_4)


for i in 1:(n_hours*one_scenario)
    test_case_bs_mn_measured["nw"]["$i"]["gen"]["1"]["pmax"]   = deepcopy(test_case_bs_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*measured_wind[i])
    test_case_bs_mn_forecasted["nw"]["$i"]["gen"]["1"]["pmax"] = deepcopy(test_case_bs_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*forecasted_wind[i])
end
for i in 1:(n_hours*n_scenarios)
    test_case_bs_mn_expected["nw"]["$i"]["gen"]["1"]["pmax"]   = deepcopy(test_case_bs_replicate["nw"]["$i"]["gen"]["1"]["pmax"]*scenarios_wind["$i"]["samples_pu"])
end
#=
function prepare_starting_value_dict_lpac_nw_sp(grid,n_hours,n_scenarios)
    count_ = 0
    for hour in 1:n_hours
        count_ += 1
        for scenario_idx in 1:n_scenarios
            n = (count_ - 1)*n_scenarios + scenario_idx
            for (sw_id,sw) in grid["nw"]["$n"]["switch"]
                if !haskey(sw,"auxiliary") # calling ZILs
                    sw["starting_value"] = 1.0
                else
                    if haskey(grid["nw"]["$n"]["switch_couples"],sw_id)
                        grid["nw"]["$n"]["switch"]["$(grid["nw"]["$n"]["switch_couples"][sw_id]["f_sw"])"]["starting_value"] = 0.0
                        grid["nw"]["$n"]["switch"]["$(grid["nw"]["$n"]["switch_couples"][sw_id]["t_sw"])"]["starting_value"] = 1.0
                    end
                end
            end
        end
    end
end
# Add everything for a warm start
function prepare_starting_value_dict_lpac_nw_sp_all_variables(grid,n_hours,n_scenarios)
    count_ = 0
    for hour in 1:n_hours
        count_ += 1
        for scenario_idx in 1:n_scenarios
            n = (count_ - 1)*n_scenarios + scenario_idx
            for (sw_id,sw) in grid["nw"]["$n"]["switch"]
                if !haskey(sw,"auxiliary") # calling ZILs
                    sw["starting_value"] = 1.0
                else
                    if haskey(grid["nw"]["$n"]["switch_couples"],sw_id)
                        grid["nw"]["$n"]["switch"]["$(grid["nw"]["$n"]["switch_couples"][sw_id]["f_sw"])"]["starting_value"] = 0.0
                        grid["nw"]["$n"]["switch"]["$(grid["nw"]["$n"]["switch_couples"][sw_id]["t_sw"])"]["starting_value"] = 1.0
                    end
                end
            end
        end
    end
end

function run_stochastic_acdcsw_AC_ZIL_per_hour(grid, model, optimizer, n_hours, n_scenarios; setting = s)
    result = Dict{String,Any}()
    for hour in 1:n_hours*n_scenarios
        result["$hour"] = Dict{String,Any}()
        result["$hour"] = _PMTP.run_acdcsw_AC_big_M_ZIL_sp(grid["nw"]["$hour"],model,optimizer; setting = setting) 
    end
    return result
end

function run_feasibility_checks_per_hour(grid, result_bs, model, optimizer,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
    result_feasibility_checks = Dict{String,Any}()
    for hour in 1:length(grid["nw"])
        result_feasibility_checks["$hour"] = Dict{String,Any}()
        feasibility_check = deepcopy(grid["nw"]["$hour"])
        feasibility_check_input = deepcopy(grid["nw"]["$hour"])
        _PMTP.prepare_AC_feasibility_check(result_bs["$hour"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
        result_feasibility_checks["$hour"] = _PM.solve_opf(feasibility_check,model,optimizer; setting = s)
        #if isnan(result_feasibility_checks["$hour"]["objective"])
        #    result_feasibility_checks["$hour"] = deepcopy(result_opf["$hour"])
        #end
    end
    return result_feasibility_checks
end

function run_pf_per_hour(grid, result_bs, model, optimizer,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
    result_feasibility_checks = Dict{String,Any}()
    for hour in 1:length(grid["nw"])
        result_feasibility_checks["$hour"] = Dict{String,Any}()
        feasibility_check = deepcopy(grid["nw"]["$hour"])
        feasibility_check_input = deepcopy(grid["nw"]["$hour"])
        prepare_AC_pf(result_bs["$hour"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
        result_feasibility_checks["$hour"] = _PM.solve_pf(feasibility_check,model,optimizer; setting = s)
        #if isnan(result_feasibility_checks["$hour"]["objective"])
        #    result_feasibility_checks["$hour"] = deepcopy(result_opf["$hour"])
        #end
    end
    return result_feasibility_checks
end

function prepare_AC_pf(result_dict, input_dict, input_ac_check, switch_couples, extremes_dict,input_base)
    orig_buses = maximum(parse.(Int, keys(input_base["bus"]))) # maximum value before splitting (in case the buses are not in numerical order)
    for (sw_id,sw) in input_dict["switch"]
        if !haskey(sw,"auxiliary")
            println("SWITCH $sw_id, BUS from $(sw["f_bus"]), BUS to $(sw["t_bus"])")
            if result_dict["solution"]["switch"][sw_id]["status"] >= 0.9 # Just reconnecting stuff
                println("Switch $sw_id is closed, Connecting everything back, no busbar splitting on bus $(sw["bus_split"])")
                for l in keys(switch_couples)
                    #if haskey(switch_couples,sw_id) && switch_couples[l]["bus_split"] == sw["bus_split"] -> wrong, you are checking the ZIL sw here
                    if switch_couples[l]["bus_split"] == sw["bus_split"] # coupling the switch couple to their split bus, if it closed, just connect everything back to the original switch
                        println("SWITCH COUPLE IS $l")

                        switch_t = deepcopy(input_dict["switch"]["$(switch_couples["$l"]["t_sw"])"])
                        switch_f = deepcopy(input_dict["switch"]["$(switch_couples["$l"]["f_sw"])"])
                        
                        if switch_t["t_bus"] == switch_couples[l]["bus_split"]
                            aux_t = switch_t["auxiliary"]
                            orig_t = switch_t["original"]
                            println("Element $aux_t $orig_t")
                            if aux_t == "gen"
                                input_ac_check["gen"]["$(orig_t)"]["gen_bus"] = deepcopy(input_dict["switch"]["$(switch_t["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                                delete!(input_ac_check["bus"],input_ac_check["gen"]["$(orig_t)"]["gen_bus"])
                                println("Element $aux_t $orig_t connected to $(input_ac_check["gen"]["$(orig_t)"]["gen_bus"])")
                            elseif aux_t == "load"
                                input_ac_check["load"]["$(orig_t)"]["load_bus"] = deepcopy(input_dict["switch"]["$(switch_t["index"])"]["t_bus"])
                                delete!(input_ac_check["bus"],input_ac_check["load"]["$(orig_t)"]["load_bus"])
                                println("Element $aux_t $orig_t connected to $(input_ac_check["load"]["$(orig_t)"]["load_bus"])")
                            elseif aux_t == "convdc"
                                input_ac_check["convdc"]["$(orig_t)"]["busac_i"] = deepcopy(input_dict["switch"]["$(switch_t["index"])"]["t_bus"])
                                delete!(input_ac_check["bus"],input_ac_check["convdc"]["$(orig_t)"]["busac_i"])
                                println("Element $aux_t $orig_t connected to $(input_ac_check["convdc"]["$(orig_t)"]["busac_i"])")
                            elseif aux_t == "branch" 
                                if input_ac_check["branch"]["$(orig_t)"]["f_bus"] > orig_buses && input_dict["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"] # useful if both ends of a branch are busbars being split
                                    input_ac_check["branch"]["$(orig_t)"]["f_bus"] = deepcopy(input_dict["switch"]["$(switch_t["index"])"]["t_bus"])
                                    delete!(input_ac_check["bus"],input_ac_check["branch"]["$(orig_t)"]["f_bus"])
                                    println("Element $aux_t $orig_t connected to $(input_ac_check["branch"]["$(orig_t)"]["f_bus"])")
                                elseif input_ac_check["branch"]["$(orig_t)"]["t_bus"] > orig_buses && input_dict["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                    input_ac_check["branch"]["$(orig_t)"]["t_bus"] = deepcopy(input_dict["switch"]["$(switch_t["index"])"]["t_bus"])
                                    delete!(input_ac_check["bus"],input_ac_check["branch"]["$(orig_t)"]["t_bus"])
                                    println("Element $aux_t $orig_t connected to $(input_ac_check["branch"]["$(orig_t)"]["t_bus"])")
                                end
                            end
                        elseif switch_f["t_bus"] == switch_couples[l]["bus_split"]
                            aux_f = switch_f["auxiliary"]
                            orig_f = switch_f["original"]
                            println("Element $aux_f $orig_f")
                            if aux_f == "gen"
                                input_ac_check["gen"]["$(orig_f)"]["gen_bus"] = deepcopy(input_dict["switch"]["$(switch_f["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                                delete!(input_ac_check["bus"],input_ac_check["gen"]["$(orig_f)"]["gen_bus"])
                                println("Element $aux_f $orig_f connected to $(input_ac_check["gen"]["$(orig_f)"]["gen_bus"])")
                            elseif aux_f == "load"
                                input_ac_check["load"]["$(orig_f)"]["load_bus"] = deepcopy(input_dict["switch"]["$(switch_f["index"])"]["t_bus"])
                                delete!(input_ac_check["bus"],input_ac_check["load"]["$(orig_f)"]["load_bus"])
                                println("Element $aux_f $orig_f connected to $(input_ac_check["load"]["$(orig_f)"]["load_bus"])")
                            elseif aux_f == "convdc"
                                input_ac_check["convdc"]["$(orig_f)"]["busac_i"] = deepcopy(input_dict["switch"]["$(switch_f["index"])"]["t_bus"])
                                delete!(input_ac_check["bus"],input_ac_check["convdc"]["$(orig_f)"]["busac_i"])
                                println("Element $aux_f $orig_f connected to $(input_ac_check["convdc"]["$(orig_f)"]["busac_i"])")
                            elseif aux_f == "branch" 
                                if input_ac_check["branch"]["$(orig_f)"]["f_bus"] > orig_buses && input_dict["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"] # useful if both ends of a branch are busbars being split
                                    input_ac_check["branch"]["$(orig_f)"]["f_bus"] = deepcopy(input_dict["switch"]["$(switch_f["index"])"]["t_bus"])
                                    delete!(input_ac_check["bus"],input_ac_check["branch"]["$(orig_f)"]["f_bus"])
                                    println("Element $aux_f $orig_f connected to $(input_ac_check["branch"]["$(orig_f)"]["f_bus"])")
                                elseif input_ac_check["branch"]["$(orig_f)"]["t_bus"] > orig_buses && input_dict["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                    input_ac_check["branch"]["$(orig_f)"]["t_bus"] = deepcopy(input_dict["switch"]["$(switch_f["index"])"]["t_bus"])
                                    delete!(input_ac_check["bus"],input_ac_check["branch"]["$(orig_f)"]["t_bus"])
                                    println("Element $aux_f $orig_f connected to $(input_ac_check["branch"]["$(orig_f)"]["t_bus"])")
                                end
                            end
                        end
                    end
                end
            elseif result_dict["solution"]["switch"][sw_id]["status"] <= 0.1 # Connect elements to the right bus
                println("Switch $sw_id is open, busbar splitting on bus $(sw["bus_split"])")
                delete!(input_ac_check["switch"],sw_id)
                for l in keys(switch_couples)
                    #if haskey(switch_couples,sw_id) && switch_couples[l]["bus_split"] == sw["bus_split"] -> wrong, you are checking the ZIL sw here
                    if switch_couples[l]["bus_split"] == sw["bus_split"] # coupling the switch couple to their split bus
                        println("SWITCH COUPLE IS $l")
                        #if result_dict["solution"]["switch"]["$(switch_couples["$l"]["switch_split"])"]["status"] >= 0.9 # Switch is closed
                            #aux =  deepcopy(input_dict["switch"]["$(switch_couples["$l"]["t_sw"])"]["auxiliary"])
                            #orig = deepcopy(input_dict["switch"]["$(switch_couples["$l"]["t_sw"])"]["original"])
                            #if aux == "gen"
                            #    delete!(input_ac_check["bus"],input_ac_check["gen"]["$(orig)"]["gen_bus"])
                            #    input_ac_check["gen"]["$(orig)"]["gen_bus"] = deepcopy(switch_couples[l]["bus_split"])
                            #elseif aux == "load"
                            #    delete!(input_ac_check["bus"],input_ac_check["load"]["$(orig)"]["load_bus"])
                            #    input_ac_check["load"]["$(orig)"]["load_bus"] = deepcopy(switch_couples[l]["bus_split"])
                            #elseif aux == "convdc"
                            #    delete!(input_ac_check["bus"],input_ac_check["convdc"]["$(orig)"]["busac_i"])
                            #    input_ac_check["convdc"]["$(orig)"]["busac_i"] = deepcopy(switch_couples[l]["bus_split"])
                            #elseif aux == "branch"                
                            #    if input_dict["branch"]["$(orig)"]["f_bus"] > orig_buses && input_dict["switch"]["$(switch_couples["$l"]["t_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                            #        println("BRANCH $(orig), f_bus $(input_dict["branch"]["$(orig)"]["f_bus"])")
                            #        delete!(input_ac_check["bus"],input_ac_check["branch"]["$(orig)"]["f_bus"])
                            #        input_ac_check["branch"]["$(orig)"]["f_bus"] = deepcopy(switch_couples[l]["bus_split"])
                            #    elseif input_dict["branch"]["$(orig)"]["t_bus"] > orig_buses && input_dict["switch"]["$(switch_couples["$l"]["t_sw"])"]["t_bus"] == switch_couples[l]["bus_split"]
                            #        println("BRANCH $(orig), t_bus $(input_dict["branch"]["$(orig)"]["t_bus"])")
                            #        delete!(input_ac_check["bus"],input_ac_check["branch"]["$(orig)"]["t_bus"])
                            #        input_ac_check["branch"]["$(orig)"]["t_bus"] = deepcopy(switch_couples[l]["bus_split"])
                            #    end
                            #end
                        #if result_dict["solution"]["switch"]["$(switch_couples["$l"]["switch_split"])"]["status"] <= 0.1 # Switch is open
                            switch_t = deepcopy(input_dict["switch"]["$(switch_couples["$l"]["t_sw"])"]) 
                            aux_t = switch_t["auxiliary"]
                            orig_t = switch_t["original"]
                            println("Element $aux_t $orig_t")
                            if result_dict["solution"]["switch"]["$(switch_t["index"])"]["status"] <= 0.1
                                println("Deleting switch $(switch_t["index"])")
                                delete!(input_ac_check["switch"],"$(switch_t["index"])")
                            elseif result_dict["solution"]["switch"]["$(switch_t["index"])"]["status"] >= 0.9
                                if aux_t == "gen"
                                    input_ac_check["gen"]["$(orig_t)"]["gen_bus"] = deepcopy(input_dict["switch"]["$(switch_t["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                                    delete!(input_ac_check["bus"],input_ac_check["gen"]["$(orig_t)"]["gen_bus"])
                                    println("Element $aux_t $orig_t connected to $(input_ac_check["gen"]["$(orig_t)"]["gen_bus"])")
                                elseif aux_t == "load"
                                    input_ac_check["load"]["$(orig_t)"]["load_bus"] = deepcopy(input_dict["switch"]["$(switch_t["index"])"]["t_bus"])
                                    delete!(input_ac_check["bus"],input_ac_check["load"]["$(orig_t)"]["load_bus"])
                                    println("Element $aux_t $orig_t connected to $(input_ac_check["load"]["$(orig_t)"]["load_bus"])")
                                elseif aux_t == "convdc"
                                    input_ac_check["convdc"]["$(orig_t)"]["busac_i"] = deepcopy(input_dict["switch"]["$(switch_t["index"])"]["t_bus"])
                                    delete!(input_ac_check["bus"],input_ac_check["convdc"]["$(orig_t)"]["busac_i"])
                                    println("Element $aux_t $orig_t connected to $(input_ac_check["convdc"]["$(orig_t)"]["busac_i"])")
                                elseif aux_t == "branch" 
                                    if input_ac_check["branch"]["$(orig_t)"]["f_bus"] > orig_buses && input_dict["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"] # useful if both ends of a branch are busbars being split
                                        input_ac_check["branch"]["$(orig_t)"]["f_bus"] = deepcopy(input_dict["switch"]["$(switch_t["index"])"]["t_bus"])
                                        delete!(input_ac_check["bus"],input_ac_check["branch"]["$(orig_t)"]["f_bus"])
                                        println("Element $aux_t $orig_t connected to $(input_ac_check["branch"]["$(orig_t)"]["f_bus"])")
                                    elseif input_ac_check["branch"]["$(orig_t)"]["t_bus"] > orig_buses && input_dict["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                        input_ac_check["branch"]["$(orig_t)"]["t_bus"] = deepcopy(input_dict["switch"]["$(switch_t["index"])"]["t_bus"])
                                        delete!(input_ac_check["bus"],input_ac_check["branch"]["$(orig_t)"]["t_bus"])
                                        println("Element $aux_t $orig_t connected to $(input_ac_check["branch"]["$(orig_t)"]["t_bus"])")
                                    end
                                end
                            end
                        

                            switch_f = deepcopy(input_dict["switch"]["$(switch_couples["$l"]["f_sw"])"]) 
                            aux_f = switch_f["auxiliary"]
                            orig_f = switch_f["original"]
                            println("Element $aux_f $orig_f")
                            if result_dict["solution"]["switch"]["$(switch_f["index"])"]["status"] <= 0.1
                                println("Deleting switch $(switch_f["index"])")
                                delete!(input_ac_check["switch"],"$(switch_f["index"])")
                            elseif result_dict["solution"]["switch"]["$(switch_f["index"])"]["status"] >= 0.9
                                if aux_f == "gen"
                                    input_ac_check["gen"]["$(orig_f)"]["gen_bus"] = deepcopy(input_dict["switch"]["$(switch_f["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                                    delete!(input_ac_check["bus"],input_ac_check["gen"]["$(orig_f)"]["gen_bus"])
                                    println("Element $aux_f $orig_f connected to $(input_ac_check["gen"]["$(orig_f)"]["gen_bus"])")
                                elseif aux_f == "load"
                                    input_ac_check["load"]["$(orig_f)"]["load_bus"] = deepcopy(input_dict["switch"]["$(switch_f["index"])"]["t_bus"])
                                    delete!(input_ac_check["bus"],input_ac_check["load"]["$(orig_f)"]["load_bus"])
                                    println("Element $aux_f $orig_f connected to $(input_ac_check["load"]["$(orig_f)"]["load_bus"])")
                                elseif aux_f == "convdc"
                                    input_ac_check["convdc"]["$(orig_f)"]["busac_i"] = deepcopy(input_dict["switch"]["$(switch_f["index"])"]["t_bus"])
                                    delete!(input_ac_check["bus"],input_ac_check["convdc"]["$(orig_f)"]["busac_i"])
                                    println("Element $aux_f $orig_f connected to $(input_ac_check["convdc"]["$(orig_f)"]["busac_i"])")
                                elseif aux_f == "branch" 
                                    if input_ac_check["branch"]["$(orig_f)"]["f_bus"] > orig_buses && input_dict["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"] # useful if both ends of a branch are busbars being split
                                        input_ac_check["branch"]["$(orig_f)"]["f_bus"] = deepcopy(input_dict["switch"]["$(switch_f["index"])"]["t_bus"])
                                        delete!(input_ac_check["bus"],input_ac_check["branch"]["$(orig_f)"]["f_bus"])
                                        println("Element $aux_f $orig_f connected to $(input_ac_check["branch"]["$(orig_f)"]["f_bus"])")
                                    elseif input_ac_check["branch"]["$(orig_f)"]["t_bus"] > orig_buses && input_dict["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                        input_ac_check["branch"]["$(orig_f)"]["t_bus"] = deepcopy(input_dict["switch"]["$(switch_f["index"])"]["t_bus"])
                                        delete!(input_ac_check["bus"],input_ac_check["branch"]["$(orig_f)"]["t_bus"])
                                        println("Element $aux_f $orig_f connected to $(input_ac_check["branch"]["$(orig_f)"]["t_bus"])")
                                    end
                                end
                            end
                        #end
                    end
                end
            end
            input_ac_check["switch"] = Dict{String,Any}()
            input_ac_check["switch_couples"] = Dict{String,Any}()
        end
    end
    for (b_id,b) in input_ac_check["gen"]
        if  input_ac_check["bus"]["$(b["gen_bus"])"]["bus_type"] == 1
            input_ac_check["bus"]["$(b["gen_bus"])"]["bus_type"] = 2
        end
    end
    
    for (g_id,g) in input_ac_check["gen"]
        g["pg"] = result_dict["solution"]["gen"]["$g_id"]["pg"]
        g["qg"] = result_dict["solution"]["gen"]["$g_id"]["qg"]
    end
    for (g_id,g) in input_ac_check["bus"]
        g["va"] = result_dict["solution"]["bus"]["$g_id"]["va"]            
        g["vm"] = 1 + result_dict["solution"]["bus"]["$g_id"]["phi"]
    end
end
=#

test_case_bs_mn_expected_sp = deepcopy(test_case_bs_mn_expected)
_SPMTA.prepare_starting_value_dict_lpac_nw_sp(test_case_bs_mn_expected_sp,n_hours,n_scenarios)

test_case_bs_mn_expected_hours_sp = Dict{String,Any}()
for hour in 1:n_hours
    first_n = (hour - 1)*n_scenarios + 1
    last_n = n_scenarios*hour
    test_case_bs_mn_expected_hours_sp["$hour"] = Dict{String,Any}()
    test_case_bs_mn_expected_hours_sp["$hour"]["nw"] = Dict{String,Any}()
    test_case_bs_mn_expected_hours_sp["$hour"]["multinetwork"] = true
    test_case_bs_mn_expected_hours_sp["$hour"]["per_unit"] = true
    for i in first_n:last_n
        test_case_bs_mn_expected_hours_sp["$hour"]["nw"]["$i"] = deepcopy(test_case_bs_mn_expected_sp["nw"]["$i"])
    end
end

result_bs_hourly_forecasted_24 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_per_hour(test_case_bs_mn_forecasted,LPACCPowerModel,gurobi_lpac,n_hours,one_scenario;setting = s)
result_bs_hourly_measured_24 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_per_hour(test_case_bs_mn_measured,LPACCPowerModel,gurobi_lpac,n_hours,one_scenario;setting = s)
#result_bs_hourly_expected_24 = run_stochastic_acdcsw_AC_ZIL_per_hour(test_case_bs_mn_expected,LPACCPowerModel,gurobi_lpac,n_hours,N_8;setting = s)

result_bs_hourly_expected_24 = Dict{String,Any}()
for i in 1:n_hours
    println("---------------------")
    println("Starting hour $(i)")
    println("---------------------")
    hourly_grid_stochastic = deepcopy(test_case_bs_mn_expected)
    hourly_grid_stochastic["nw"] = Dict{String,Any}()
    println("---------------------")
    println("Hourly grid stochastic created")
    println("---------------------")
    for s in 1:N_8
        println("---------------------")
        println("Preparing scenario $s")
        println("---------------------")
        h = (i - 1)*N_8 + s
        hourly_grid_stochastic["nw"]["$s"] = deepcopy(test_case_bs_mn_expected["nw"]["$h"])
    end
    result_bs_hourly_expected_24["$i"] = Dict{String,Any}()
    result_bs_hourly_expected_24["$i"] = deepcopy(_SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology(hourly_grid_stochastic,LPACCPowerModel,gurobi_lpac; setting = s))
end


hour_1_sw = [result_bs_hourly_expected_24["1"]["solution"]["switch"][sw_id]["status"] for (sw_id,sw) in test_case_bs_mn_expected["nw"]["5"]["switch"]]
hour_5_sw = [result_bs_hourly_expected_24["5"]["solution"]["switch"][sw_id]["status"] for (sw_id,sw) in test_case_bs_mn_expected["nw"]["5"]["switch"]]
hour_8_sw = [result_bs_hourly_expected_24["8"]["solution"]["switch"][sw_id]["status"] for (sw_id,sw) in test_case_bs_mn_expected["nw"]["5"]["switch"]]

hour_9_sw = [result_bs_hourly_expected_24["9"]["solution"]["switch"][sw_id]["status"] for (sw_id,sw) in test_case_bs_mn_expected["nw"]["5"]["switch"]]
hour_13_sw = [result_bs_hourly_expected_24["13"]["solution"]["switch"][sw_id]["status"] for (sw_id,sw) in test_case_bs_mn_expected["nw"]["5"]["switch"]]
hour_15_sw = [result_bs_hourly_expected_24["15"]["solution"]["switch"][sw_id]["status"] for (sw_id,sw) in test_case_bs_mn_expected["nw"]["5"]["switch"]]



json_result_bs_hourly_forecasted_24 = JSON.json(result_bs_hourly_forecasted_24)
open(joinpath(results_folder,case,"24_hours_BS_forecasted_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_result_bs_hourly_forecasted_24) 
end 

json_result_bs_hourly_measured_24 = JSON.json(result_bs_hourly_measured_24)
open(joinpath(results_folder,case,"24_hours_BS_measured_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_result_bs_hourly_measured_24) 
end 

[result_bs_hourly_forecasted_24["$i"]["objective"] for i in 1:n_hours]
[result_bs_hourly_measured_24["$i"]["objective"] for i in 1:n_hours]


""
function solve_acdc_redispatch_opf(data::Dict{String,Any}, model_type::Type, solver; kwargs...)
    return _PM.solve_model(data, model_type, solver, build_acdc_redispatch_opf; ref_extensions = [_PMACDC.add_ref_dcgrid!], kwargs...)
end

""

function objective_stochastic_redispatch_opf(pm::_PM.AbstractPowerModel)
    cost = JuMP.AffExpr(0.0)

    #for n in 1:length(pm.ref[:it][_PM.pm_it_sym][:nw])
        JuMP.add_to_expression!(cost, calc_gen_redispatch_cost(pm))
    #end
    JuMP.@objective(pm.model, Min, cost)
end


function calc_gen_redispatch_cost(pm::_PM.AbstractPowerModel)
    cost = JuMP.AffExpr(0.0)
    for (i,g) in pm.ref[:it][:pm][:nw][_PM.nw_id_default][:gen]
        JuMP.add_to_expression!(cost, g["redispatch_cost_up"], _PM.var(pm,:pg_up,i))# - pm.ref[:it][:pm][:nw][_PM.nw_id_default][:gen][i]["pg_start"]))
        JuMP.add_to_expression!(cost, g["redispatch_cost_down"], _PM.var(pm,:pg_down,i))#-(pm.ref[:it][:pm][:nw][_PM.nw_id_default][:gen][i]["pg_start"]))
        #JuMP.add_to_expression!(cost, g["redispatch_cost_up"], _PM.var(pm,:qg_up,i))# - pm.ref[:it][:pm][:nw][_PM.nw_id_default][:gen][i]["qg_start"]))
        #JuMP.add_to_expression!(cost, g["redispatch_cost_down"], _PM.var(pm,:qg_down,i))# -(pm.ref[:it][:pm][:nw][_PM.nw_id_default][:gen][i]["qg_start"] - _PM.var(pm,:qg_down,i)))
    end
    return cost
end


function build_acdc_redispatch_opf(pm::_PM.AbstractPowerModel)
    _PM.variable_bus_voltage(pm)
    _PM.variable_gen_power(pm)
    _PM.variable_branch_power(pm)
    _PM.variable_storage_power(pm)

    _PMACDC.variable_active_dcbranch_flow(pm)
    _PMACDC.variable_dcbranch_current(pm)
    _PMACDC.variable_dc_converter(pm)
    _PMACDC.variable_dcgrid_voltage_magnitude(pm)

    objective_stochastic_redispatch_opf(pm)

    _PM.constraint_model_voltage(pm)
    _PMACDC.constraint_voltage_dc(pm)

    for i in _PM.ids(pm, :ref_buses)
        _PM.constraint_theta_ref(pm, i)
    end

    for i in _PM.ids(pm, :bus)
        _PMACDC.constraint_power_balance_ac(pm, i)
    end

    for i in _PM.ids(pm, :branch)
        _PM.constraint_ohms_yt_from(pm, i)
        _PM.constraint_ohms_yt_to(pm, i)
        _PM.constraint_voltage_angle_difference(pm, i) #angle difference across transformer and reactor - useful for LPAC if available?
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
        _PMACDC.constraint_converter_losses(pm, i)
        _PMACDC.constraint_converter_current(pm, i)
        _PMACDC.constraint_conv_transformer(pm, i)
        _PMACDC.constraint_conv_reactor(pm, i)
        _PMACDC.constraint_conv_filter(pm, i)
        if pm.ref[:it][:pm][:nw][_PM.nw_id_default][:convdc][i]["islcc"] == 1
            _PMACDC.constraint_conv_firing_angle(pm, i)
        end
    end
end


function run_hourly_redispatch(grid, result_bs, model, optimizer,switches_couples_ac,extremes_ZILs_ac,test_case_opf,settings)
    result_feasibility_checks = Dict{String,Any}()
    for hour in 1:length(grid["nw"])
        result_feasibility_checks["$hour"] = Dict{String,Any}()
        feasibility_check = deepcopy(grid["nw"]["$hour"])
        feasibility_check_input = deepcopy(grid["nw"]["$hour"])
        _PMTP.prepare_AC_feasibility_check(result_bs["$hour"],feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)

        # Adding set points
        for (g_id,g) in feasibility_check["gen"]
            g["pg_start"] = result_bs["$hour"]["solution"]["gen"][g_id]["pg"]
            g["qg_start"] = result_bs["$hour"]["solution"]["gen"][g_id]["qg"]
            g["redispatch_cost_up"] = 5000.0
            g["redispatch_cost_down"] = 5500.0
        end

        result_feasibility_checks["$hour"] = _SPMTA.solve_acdc_full_redispatch_opf(feasibility_check,model,optimizer)
    end
    return result_feasibility_checks
end

function solve_acdc_full_redispatch_opf(data::Dict{String,Any}, model_type::Type, solver; kwargs...)
    return _PM.solve_model(data, model_type, solver, build_acdc_full_redispatch_opf; ref_extensions = [_PMACDC.add_ref_dcgrid!], kwargs...)
end

""
function build_acdc_full_redispatch_opf(pm::_PM.AbstractPowerModel)
    _PM.variable_bus_voltage(pm)
    variable_gen_redispatch_upward(pm)
    variable_gen_redispatch_downward(pm)
    _PM.variable_branch_power(pm)
    _PM.variable_storage_power(pm)

    _PMACDC.variable_active_dcbranch_flow(pm)
    _PMACDC.variable_dcbranch_current(pm)
    _PMACDC.variable_dc_converter(pm)
    _PMACDC.variable_dcgrid_voltage_magnitude(pm)

    objective_stochastic_redispatch_opf(pm)

    _PM.constraint_model_voltage(pm)
    _PMACDC.constraint_voltage_dc(pm)

    for i in _PM.ids(pm, :ref_buses)
        _PM.constraint_theta_ref(pm, i)
    end

    for i in _PM.ids(pm, :bus)
        constraint_power_balance_ac_redispatch(pm, i)
    end

    for i in _PM.ids(pm, :branch)
        _PM.constraint_ohms_yt_from(pm, i)
        _PM.constraint_ohms_yt_to(pm, i)
        _PM.constraint_voltage_angle_difference(pm, i) #angle difference across transformer and reactor - useful for LPAC if available?
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
        _PMACDC.constraint_converter_losses(pm, i)
        _PMACDC.constraint_converter_current(pm, i)
        _PMACDC.constraint_conv_transformer(pm, i)
        _PMACDC.constraint_conv_reactor(pm, i)
        _PMACDC.constraint_conv_filter(pm, i)
        if pm.ref[:it][:pm][:nw][_PM.nw_id_default][:convdc][i]["islcc"] == 1
            _PMACDC.constraint_conv_firing_angle(pm, i)
        end
    end
end

function constraint_power_balance_ac_redispatch(pm::_PM.AbstractPowerModel, i::Int; nw::Int=_PM.nw_id_default)
    bus = _PM.ref(pm, nw, :bus, i)
    bus_arcs = _PM.ref(pm, nw, :bus_arcs, i)
    bus_arcs_dc = _PM.ref(pm, nw, :bus_arcs_dc, i)
    bus_gens = _PM.ref(pm, nw, :bus_gens, i)
    bus_convs_ac = _PM.ref(pm, nw, :bus_convs_ac, i)
    bus_loads = _PM.ref(pm, nw, :bus_loads, i)
    bus_shunts = _PM.ref(pm, nw, :bus_shunts, i)

    pd = Dict(k => _PM.ref(pm, nw, :load, k, "pd") for k in bus_loads)
    qd = Dict(k => _PM.ref(pm, nw, :load, k, "qd") for k in bus_loads)

    gs = Dict(k => _PM.ref(pm, nw, :shunt, k, "gs") for k in bus_shunts)
    bs = Dict(k => _PM.ref(pm, nw, :shunt, k, "bs") for k in bus_shunts)

    pg_start = Dict(k => _PM.ref(pm, nw, :gen, k, "pg_start") for k in bus_gens)
    qg_start = Dict(k => _PM.ref(pm, nw, :gen, k, "qg_start") for k in bus_gens)

    constraint_power_balance_ac_redispatch(pm, nw, i, bus_arcs, bus_arcs_dc, bus_gens, bus_convs_ac, bus_loads, bus_shunts, pd, qd, gs, bs, pg_start, qg_start)
end

function constraint_power_balance_ac_redispatch(pm::_PM.AbstractPowerModel, n::Int,  i::Int, bus_arcs, bus_arcs_dc, bus_gens, bus_convs_ac, bus_loads, bus_shunts, pd, qd, gs, bs, pg_start, qg_start)
    vm = _PM.var(pm, n,  :vm, i)
    p = _PM.var(pm, n,  :p)
    q = _PM.var(pm, n,  :q)
    pg_up = _PM.var(pm, n,  :pg_up)
    qg_up = _PM.var(pm, n,  :qg_up)
    pg_down = _PM.var(pm, n,  :pg_down)
    qg_down = _PM.var(pm, n,  :qg_down)
    pconv_grid_ac = _PM.var(pm, n,  :pconv_tf_fr)
    qconv_grid_ac = _PM.var(pm, n,  :qconv_tf_fr)

    cstr_p = JuMP.@constraint(pm.model, sum(p[a] for a in bus_arcs) + sum(pconv_grid_ac[c] for c in bus_convs_ac)  == sum(pg_start[g] for g in bus_gens) + sum(pg_up[g] for g in bus_gens) - sum(pg_down[g] for g in bus_gens) - sum(pd[d] for d in bus_loads) - sum(gs[s] for s in bus_shunts)*vm^2)
    cstr_q = JuMP.@constraint(pm.model, sum(q[a] for a in bus_arcs) + sum(qconv_grid_ac[c] for c in bus_convs_ac)  == sum(qg_start[g] for g in bus_gens) + sum(qg_up[g] for g in bus_gens) - sum(qg_down[g] for g in bus_gens) - sum(qd[d] for d in bus_loads) + sum(bs[s] for s in bus_shunts)*vm^2)
end

function variable_gen_redispatch_upward(pm::_PM.AbstractPowerModel; kwargs...)
    variable_gen_redispatch_upward_real(pm; kwargs...)
    variable_gen_redispatch_upward_imaginary(pm; kwargs...)
end

function variable_gen_redispatch_downward(pm::_PM.AbstractPowerModel; kwargs...)
    variable_gen_redispatch_downward_real(pm; kwargs...)
    variable_gen_redispatch_downward_imaginary(pm; kwargs...)
end


"variable: `pg[j]` for `j` in `gen`"
function variable_gen_redispatch_upward_real(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default, bounded::Bool=true, report::Bool=true)
    pg_up = _PM.var(pm, nw)[:pg_up] = JuMP.@variable(pm.model,
        [i in _PM.ids(pm, nw, :gen)], base_name="$(nw)_pg_up",
        start = _PM.comp_start_value(_PM.ref(pm, nw, :gen, i), "pg_start")
    )

    if bounded
        for (i, gen) in _PM.ref(pm, nw, :gen)
            JuMP.set_lower_bound(pg_up[i], 0.0)
            JuMP.set_upper_bound(pg_up[i], gen["pmax"])
        end
    end

    report && _PM.sol_component_value(pm, nw, :gen, :pg_up, _PM.ids(pm, nw, :gen), pg_up)
end

"variable: `qq[j]` for `j` in `gen`"
function variable_gen_redispatch_upward_imaginary(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default, bounded::Bool=true, report::Bool=true)
    qg_up = _PM.var(pm, nw)[:qg_up] = JuMP.@variable(pm.model,
        [i in _PM.ids(pm, nw, :gen)], base_name="$(nw)_qg_up",
        start = _PM.comp_start_value(_PM.ref(pm, nw, :gen, i), "qg_start")
    )

    if bounded
        for (i, gen) in _PM.ref(pm, nw, :gen)
            JuMP.set_lower_bound(qg_up[i], gen["qmin"])
            JuMP.set_upper_bound(qg_up[i], gen["qmax"])
        end
    end

    report && _PM.sol_component_value(pm, nw, :gen, :qg_up, _PM.ids(pm, nw, :gen), qg_up)
end

function variable_gen_redispatch_downward_real(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default, bounded::Bool=true, report::Bool=true)
    pg_down = _PM.var(pm, nw)[:pg_down] = JuMP.@variable(pm.model,
        [i in _PM.ids(pm, nw, :gen)], base_name="$(nw)_pg_down",
        start = _PM.comp_start_value(_PM.ref(pm, nw, :gen, i), "pg_start")
    )

    if bounded
        for (i, gen) in _PM.ref(pm, nw, :gen)
            JuMP.set_lower_bound(pg_down[i], 0.0)
            JuMP.set_upper_bound(pg_down[i], gen["pmax"])
        end
    end

    report && _PM.sol_component_value(pm, nw, :gen, :pg_down, _PM.ids(pm, nw, :gen), pg_down)
end

"variable: `qq[j]` for `j` in `gen`"
function variable_gen_redispatch_downward_imaginary(pm::_PM.AbstractPowerModel; nw::Int=_PM.nw_id_default, bounded::Bool=true, report::Bool=true)
    qg_down = _PM.var(pm, nw)[:qg_down] = JuMP.@variable(pm.model,
        [i in _PM.ids(pm, nw, :gen)], base_name="$(nw)_qg_down",
        start = _PM.comp_start_value(_PM.ref(pm, nw, :gen, i), "qg_start")
    )

    if bounded
        for (i, gen) in _PM.ref(pm, nw, :gen)
            JuMP.set_lower_bound(qg_down[i], gen["qmin"])
            JuMP.set_upper_bound(qg_down[i], gen["qmax"])
        end
    end

    report && _PM.sol_component_value(pm, nw, :gen, :qg_down, _PM.ids(pm, nw, :gen), qg_down)
end

result_forecasted_feasibility_checks_24_ac = run_hourly_redispatch(test_case_bs_mn_measured,result_bs_hourly_forecasted_24,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)
#result_forecasted_feasibility_checks_24_lpac = run_feasibility_checks_per_hour(test_case_bs_mn_forecasted,result_bs_hourly_forecasted_24,LPACCPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)

for h in 1:n_hours
    println("Hour $h")
    println("----------------------------------")
    for (g_id,g) in test_case_bs_mn_forecasted["nw"]["1"]["gen"]
        if result_forecasted_feasibility_checks_24_ac["$h"]["solution"]["gen"]["$g_id"]["pg_up"] > 0.001
            println("Generator $g_id: pg_up = $(result_forecasted_feasibility_checks_24_ac["$h"]["solution"]["gen"]["$g_id"]["pg_up"]) MW")
        elseif result_forecasted_feasibility_checks_24_ac["$h"]["solution"]["gen"]["$g_id"]["pg_down"] > 0.001
            println("Generator $g_id: pg_down = $(result_forecasted_feasibility_checks_24_ac["$h"]["solution"]["gen"]["$g_id"]["pg_up"]) MW")
        end
    end
    println("----------------------------------")
end
obj_redispatch = [result_forecasted_feasibility_checks_24_ac["$h"]["objective"] for h in 1:n_hours]


result_forecasted_pf_check_24_ac = run_pf_per_hour(test_case_bs_mn_forecasted,result_bs_hourly_forecasted_24,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
#result_forecasted_pf_check_24_lpac = run_pf_per_hour(test_case_bs_mn_forecasted,result_bs_hourly_forecasted_24,LPACCPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf)


[result_bs_hourly_forecasted_24["$h"]["solution"]["switch"]["1"]["status"] for h in 1:n_hours]
[result_forecasted_pf_check_24_ac["$h"]["termination_status"] for h in 1:n_hours]


result_measured_feasibility_checks_24_ac = run_feasibility_checks_per_hour(test_case_bs_mn_measured,result_bs_hourly_measured_24,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
result_measured_feasibility_checks_24_lpac = run_feasibility_checks_per_hour(test_case_bs_mn_measured,result_bs_hourly_measured_24,LPACCPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf)

result_measured_pf_check_24_ac = run_pf_per_hour(test_case_bs_mn_measured,result_bs_hourly_measured_24,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
[result_measured_pf_check_24_ac["$h"]["termination_status"] for h in 1:n_hours]


result_measured_forecasted_feasibility_checks_24_ac = run_feasibility_checks_per_hour(test_case_bs_mn_measured,result_bs_hourly_forecasted_24,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
result_measured_forecasted_feasibility_checks_24_lpac = run_feasibility_checks_per_hour(test_case_bs_mn_measured,result_bs_hourly_forecasted_24,LPACCPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf)

result_measured_forecasted_pf_check_24_ac = run_pf_per_hour(test_case_bs_mn_measured,result_bs_hourly_measured_24,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
[result_measured_pf_check_24_ac["$h"]["termination_status"] for h in 1:n_hours]


obj_bs_forecasted_ac = [result_forecasted_feasibility_checks_24_ac["$i"]["objective"] for i in 1:n_hours]
sum(obj_bs_forecasted_ac)

obj_bs_forecasted_lpac = [result_forecasted_feasibility_checks_24_lpac["$i"]["objective"] for i in 1:n_hours]
sum(obj_bs_forecasted_lpac)

obj_bs_measured_ac = [result_measured_feasibility_checks_24_ac["$i"]["objective"] for i in 1:n_hours]
sum(obj_bs_measured_ac)

obj_bs_measured_lpac = [result_measured_feasibility_checks_24_lpac["$i"]["objective"] for i in 1:n_hours]
sum(obj_bs_measured_lpac)

obj_bs_measured_forecasted_ac = [result_measured_forecasted_feasibility_checks_24_ac["$i"]["objective"] for i in 1:n_hours]
sum(obj_bs_measured_forecasted_ac)

obj_bs_measured_forecasted_lpac = [result_measured_forecasted_feasibility_checks_24_lpac["$i"]["objective"] for i in 1:n_hours]
sum(obj_bs_measured_forecasted_lpac)

plot(obj_bs_measured_ac/10^3,label = "Measured",grid = :none,ylims = (-0.01,25),xticks = 1:n_hours,xlims = (0.8,24.5),xlabel = "Hour",ylabel = "Generation costs [k€]",
legend = :topright,xlabelfontsize = 10,ylabelfontsize = 10,xtickfont = font(8),ytickfont = font(8))
plot!(1:n_hours,obj_bs_measured_forecasted_ac/10^3,label = "Measured with topology based on forecast input data")
plot!(twinx(), 1:n_hours, diff_measured, color = :green, ylabel = "Diff between the two simulations [%]",ylims = (-0.03,10),yticks = 0:1:10,ytickfont = font(8),ylabelfontsize = 10,label = :none)


diff_measured = []
for i in 1:length(obj_bs_measured_ac)
    push!(diff_measured,abs(obj_bs_measured_ac[i] - obj_bs_measured_forecasted_ac[i])/obj_bs_measured_ac[i]*100)
end

savefig(joinpath(results_folder_figures,case_figures,"24_hours_hourly_comparison_$(first_hour)_$(last_hour).json.svg"))


#########################################################################
#results_one_topology_sp_expected = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology_sp(test_case_bs_mn_expected_try,LPACCPowerModel,gurobi; setting = s)
results_one_topology_sp_forecasted = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology(test_case_bs_mn_forecasted,LPACCPowerModel,gurobi; setting = s)
results_one_topology_sp_measured = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology(test_case_bs_mn_measured,LPACCPowerModel,gurobi; setting = s)


result_forecasted_feasibility_checks_24_ac_one_topology = run_hourly_redispatch(test_case_bs_mn_measured,result_bs_hourly_forecasted_24,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf,s)



network_data = PowerModels.parse_file("/Users/giacomobastianel/.julia/dev/PowerModels.jl/test/data/matpower/case5.m")

result = solve_pf(original_grid, ACPPowerModel, ipopt)

result = solve_pf(test_case_bs_mn_forecasted["nw"]["1"], ACPPowerModel, ipopt)


for sw_id in 1:length(test_case_bs_mn_forecasted["nw"]["1"]["switch"])
    if haskey(test_case_bs_mn_forecasted["nw"]["1"]["switch"]["$sw_id"],"auxiliary")
        println("SWITCH $sw_id, BUS from $(test_case_bs_mn_forecasted["nw"]["1"]["switch"]["$sw_id"]["f_bus"]), BUS to $(test_case_bs_mn_forecasted["nw"]["1"]["switch"]["$sw_id"]["t_bus"]), auxiliary $(test_case_bs_mn_forecasted["nw"]["1"]["switch"]["$sw_id"]["auxiliary"]), original $(test_case_bs_mn_forecasted["nw"]["1"]["switch"]["$sw_id"]["original"]) , STATUS FORECASTED $(results_one_topology_sp_forecasted["solution"]["nw"]["1"]["switch"]["$sw_id"]["status"]), STATUS MEASURED $(results_one_topology_sp_measured["solution"]["nw"]["1"]["switch"]["$sw_id"]["status"])")
    else
        println("SWITCH $sw_id, BUS from $(test_case_bs_mn_forecasted["nw"]["1"]["switch"]["$sw_id"]["f_bus"]), BUS to $(test_case_bs_mn_forecasted["nw"]["1"]["switch"]["$sw_id"]["t_bus"]), BUS COUPLER , STATUS FORECASTED $(results_one_topology_sp_forecasted["solution"]["nw"]["1"]["switch"]["$sw_id"]["status"]), STATUS MEASURED $(results_one_topology_sp_measured["solution"]["nw"]["1"]["switch"]["$sw_id"]["status"])")
    end
end


#=
function prepare_AC_feasibility_check_mn(result_dict, input_dict, input_ac_check, switch_couples, extremes_dict,input_base)
    orig_buses = maximum(parse.(Int, keys(input_base["bus"]))) # maximum value before splitting (in case the buses are not in numerical order)
    for nw in eachindex(result_dict["solution"]["nw"])
        for (sw_id,sw) in input_dict["nw"][nw]["switch"]
         if !haskey(sw,"auxiliary")
            println("SWITCH $sw_id, BUS from $(sw["f_bus"]), BUS to $(sw["t_bus"])")
            if result_dict["solution"]["nw"][nw]["switch"][sw_id]["status"] >= 0.9 # Just reconnecting stuff
                println("Switch $sw_id is closed, Connecting everything back, no busbar splitting on bus $(sw["bus_split"])")
                for l in keys(switch_couples)
                    #if haskey(switch_couples,sw_id) && switch_couples[l]["bus_split"] == sw["bus_split"] -> wrong, you are checking the ZIL sw here
                    if switch_couples[l]["bus_split"] == sw["bus_split"] # coupling the switch couple to their split bus, if it closed, just connect everything back to the original switch
                        println("SWITCH COUPLE IS $l")

                        switch_t = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_couples["$l"]["t_sw"])"])
                        switch_f = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_couples["$l"]["f_sw"])"])
                        
                        if switch_t["t_bus"] == switch_couples[l]["bus_split"]
                            aux_t = switch_t["auxiliary"]
                            orig_t = switch_t["original"]
                            println("Element $aux_t $orig_t")
                            if aux_t == "gen"
                                input_ac_check["nw"][nw]["gen"]["$(orig_t)"]["gen_bus"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_t["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                                delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["gen"]["$(orig_t)"]["gen_bus"])
                                println("Element $aux_t $orig_t connected to $(input_ac_check["nw"][nw]["gen"]["$(orig_t)"]["gen_bus"])")
                            elseif aux_t == "load"
                                input_ac_check["nw"][nw]["load"]["$(orig_t)"]["load_bus"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_t["index"])"]["t_bus"])
                                delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["load"]["$(orig_t)"]["load_bus"])
                                println("Element $aux_t $orig_t connected to $(input_ac_check["nw"][nw]["load"]["$(orig_t)"]["load_bus"])")
                            elseif aux_t == "convdc"
                                input_ac_check["nw"][nw]["convdc"]["$(orig_t)"]["busac_i"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_t["index"])"]["t_bus"])
                                delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["convdc"]["$(orig_t)"]["busac_i"])
                                println("Element $aux_t $orig_t connected to $(input_ac_check["nw"][nw]["convdc"]["$(orig_t)"]["busac_i"])")
                            elseif aux_t == "branch" 
                                if input_ac_check["nw"][nw]["branch"]["$(orig_t)"]["f_bus"] > orig_buses && input_dict["nw"][nw]["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"] # useful if both ends of a branch are busbars being split
                                    input_ac_check["nw"][nw]["branch"]["$(orig_t)"]["f_bus"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_t["index"])"]["t_bus"])
                                    delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["branch"]["$(orig_t)"]["f_bus"])
                                    println("Element $aux_t $orig_t connected to $(input_ac_check["nw"][nw]["branch"]["$(orig_t)"]["f_bus"])")
                                elseif input_ac_check["nw"][nw]["branch"]["$(orig_t)"]["t_bus"] > orig_buses && input_dict["nw"][nw]["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                    input_ac_check["nw"][nw]["branch"]["$(orig_t)"]["t_bus"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_t["index"])"]["t_bus"])
                                    delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["branch"]["$(orig_t)"]["t_bus"])
                                    println("Element $aux_t $orig_t connected to $(input_ac_check["nw"][nw]["branch"]["$(orig_t)"]["t_bus"])")
                                end
                            end
                        elseif switch_f["t_bus"] == switch_couples[l]["bus_split"]
                            aux_f = switch_f["auxiliary"]
                            orig_f = switch_f["original"]
                            println("Element $aux_f $orig_f")
                            if aux_f == "gen"
                                input_ac_check["nw"][nw]["gen"]["$(orig_f)"]["gen_bus"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_f["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                                delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["gen"]["$(orig_f)"]["gen_bus"])
                                println("Element $aux_f $orig_f connected to $(input_ac_check["nw"][nw]["gen"]["$(orig_f)"]["gen_bus"])")
                            elseif aux_f == "load"
                                input_ac_check["nw"][nw]["load"]["$(orig_f)"]["load_bus"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_f["index"])"]["t_bus"])
                                delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["load"]["$(orig_f)"]["load_bus"])
                                println("Element $aux_f $orig_f connected to $(input_ac_check["nw"][nw]["load"]["$(orig_f)"]["load_bus"])")
                            elseif aux_f == "convdc"
                                input_ac_check["nw"][nw]["convdc"]["$(orig_f)"]["busac_i"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_f["index"])"]["t_bus"])
                                delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["convdc"]["$(orig_f)"]["busac_i"])
                                println("Element $aux_f $orig_f connected to $(input_ac_check["nw"][nw]["convdc"]["$(orig_f)"]["busac_i"])")
                            elseif aux_f == "branch" 
                                if input_ac_check["nw"][nw]["branch"]["$(orig_f)"]["f_bus"] > orig_buses && input_dict["nw"][nw]["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"] # useful if both ends of a branch are busbars being split
                                    input_ac_check["nw"][nw]["branch"]["$(orig_f)"]["f_bus"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_f["index"])"]["t_bus"])
                                    delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["branch"]["$(orig_f)"]["f_bus"])
                                    println("Element $aux_f $orig_f connected to $(input_ac_check["nw"][nw]["branch"]["$(orig_f)"]["f_bus"])")
                                elseif input_ac_check["nw"][nw]["branch"]["$(orig_f)"]["t_bus"] > orig_buses && input_dict["nw"][nw]["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                    input_ac_check["nw"][nw]["branch"]["$(orig_f)"]["t_bus"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_f["index"])"]["t_bus"])
                                    delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["branch"]["$(orig_f)"]["t_bus"])
                                    println("Element $aux_f $orig_f connected to $(input_ac_check["nw"][nw]["branch"]["$(orig_f)"]["t_bus"])")
                                end
                            end
                        end
                    end
                end
            elseif result_dict["solution"]["nw"][nw]["switch"][sw_id]["status"] <= 0.1 # Connect elements to the right bus
                println("Switch $sw_id is open, busbar splitting on bus $(sw["bus_split"])")
                delete!(input_ac_check["nw"][nw]["switch"],sw_id)
                for l in keys(switch_couples)
                    if switch_couples[l]["bus_split"] == sw["bus_split"] # coupling the switch couple to their split bus
                        println("SWITCH COUPLE IS $l")
                            switch_t = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_couples["$l"]["t_sw"])"]) 
                            aux_t = switch_t["auxiliary"]
                            orig_t = switch_t["original"]
                            println("Element $aux_t $orig_t")
                            if result_dict["solution"]["nw"][nw]["switch"]["$(switch_t["index"])"]["status"] <= 0.1
                                println("Deleting switch $(switch_t["index"])")
                                delete!(input_ac_check["nw"][nw]["switch"],"$(switch_t["index"])")
                            elseif result_dict["solution"]["nw"][nw]["switch"]["$(switch_t["index"])"]["status"] >= 0.9
                                if aux_t == "gen"
                                    input_ac_check["nw"][nw]["gen"]["$(orig_t)"]["gen_bus"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_t["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                                    delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["gen"]["$(orig_t)"]["gen_bus"])
                                    println("Element $aux_t $orig_t connected to $(input_ac_check["nw"][nw]["gen"]["$(orig_t)"]["gen_bus"])")
                                elseif aux_t == "load"
                                    input_ac_check["nw"][nw]["load"]["$(orig_t)"]["load_bus"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_t["index"])"]["t_bus"])
                                    delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["load"]["$(orig_t)"]["load_bus"])
                                    println("Element $aux_t $orig_t connected to $(input_ac_check["nw"][nw]["load"]["$(orig_t)"]["load_bus"])")
                                elseif aux_t == "convdc"
                                    input_ac_check["nw"][nw]["convdc"]["$(orig_t)"]["busac_i"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_t["index"])"]["t_bus"])
                                    delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["convdc"]["$(orig_t)"]["busac_i"])
                                    println("Element $aux_t $orig_t connected to $(input_ac_check["nw"][nw]["convdc"]["$(orig_t)"]["busac_i"])")
                                elseif aux_t == "branch" 
                                    if input_ac_check["nw"][nw]["branch"]["$(orig_t)"]["f_bus"] > orig_buses && input_dict["nw"][nw]["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"] # useful if both ends of a branch are busbars being split
                                        input_ac_check["nw"][nw]["branch"]["$(orig_t)"]["f_bus"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_t["index"])"]["t_bus"])
                                        delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["branch"]["$(orig_t)"]["f_bus"])
                                        println("Element $aux_t $orig_t connected to $(input_ac_check["nw"][nw]["branch"]["$(orig_t)"]["f_bus"])")
                                    elseif input_ac_check["nw"][nw]["branch"]["$(orig_t)"]["t_bus"] > orig_buses && input_dict["nw"][nw]["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                        input_ac_check["nw"][nw]["branch"]["$(orig_t)"]["t_bus"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_t["index"])"]["t_bus"])
                                        delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["branch"]["$(orig_t)"]["t_bus"])
                                        println("Element $aux_t $orig_t connected to $(input_ac_check["nw"][nw]["branch"]["$(orig_t)"]["t_bus"])")
                                    end
                                end
                            end
                        

                            switch_f = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_couples["$l"]["f_sw"])"]) 
                            aux_f = switch_f["auxiliary"]
                            orig_f = switch_f["original"]
                            println("Element $aux_f $orig_f")
                            if result_dict["solution"]["nw"][nw]["switch"]["$(switch_f["index"])"]["status"] <= 0.1
                                println("Deleting switch $(switch_f["index"])")
                                delete!(input_ac_check["nw"][nw]["switch"],"$(switch_f["index"])")
                            elseif result_dict["solution"]["nw"][nw]["switch"]["$(switch_f["index"])"]["status"] >= 0.9
                                if aux_f == "gen"
                                    input_ac_check["nw"][nw]["gen"]["$(orig_f)"]["gen_bus"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_f["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                                    delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["gen"]["$(orig_f)"]["gen_bus"])
                                    println("Element $aux_f $orig_f connected to $(input_ac_check["nw"][nw]["gen"]["$(orig_f)"]["gen_bus"])")
                                elseif aux_f == "load"
                                    input_ac_check["nw"][nw]["load"]["$(orig_f)"]["load_bus"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_f["index"])"]["t_bus"])
                                    delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["load"]["$(orig_f)"]["load_bus"])
                                    println("Element $aux_f $orig_f connected to $(input_ac_check["nw"][nw]["load"]["$(orig_f)"]["load_bus"])")
                                elseif aux_f == "convdc"
                                    input_ac_check["nw"][nw]["convdc"]["$(orig_f)"]["busac_i"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_f["index"])"]["t_bus"])
                                    delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["convdc"]["$(orig_f)"]["busac_i"])
                                    println("Element $aux_f $orig_f connected to $(input_ac_check["nw"][nw]["convdc"]["$(orig_f)"]["busac_i"])")
                                elseif aux_f == "branch" 
                                    if input_ac_check["nw"][nw]["branch"]["$(orig_f)"]["f_bus"] > orig_buses && input_dict["nw"][nw]["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"] # useful if both ends of a branch are busbars being split
                                        input_ac_check["nw"][nw]["branch"]["$(orig_f)"]["f_bus"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_f["index"])"]["t_bus"])
                                        delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["branch"]["$(orig_f)"]["f_bus"])
                                        println("Element $aux_f $orig_f connected to $(input_ac_check["nw"][nw]["branch"]["$(orig_f)"]["f_bus"])")
                                    elseif input_ac_check["nw"][nw]["branch"]["$(orig_f)"]["t_bus"] > orig_buses && input_dict["nw"][nw]["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                        input_ac_check["nw"][nw]["branch"]["$(orig_f)"]["t_bus"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_f["index"])"]["t_bus"])
                                        delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["branch"]["$(orig_f)"]["t_bus"])
                                        println("Element $aux_f $orig_f connected to $(input_ac_check["nw"][nw]["branch"]["$(orig_f)"]["t_bus"])")
                                    end
                                end
                            end
                    end
                end
            end
            input_ac_check["nw"][nw]["switch"] = Dict{String,Any}()
            input_ac_check["nw"][nw]["switch_couples"] = Dict{String,Any}()
        end
    end
    end
end

function prepare_AC_pf_mn(result_dict, input_dict, input_ac_check, switch_couples, extremes_dict,input_base)
    orig_buses = maximum(parse.(Int, keys(input_base["bus"]))) # maximum value before splitting (in case the buses are not in numerical order)
    for nw in eachindex(result_dict["solution"]["nw"])
        for (sw_id,sw) in input_dict["nw"][nw]["switch"]
         if !haskey(sw,"auxiliary")
            println("SWITCH $sw_id, BUS from $(sw["f_bus"]), BUS to $(sw["t_bus"])")
            if result_dict["solution"]["nw"][nw]["switch"][sw_id]["status"] >= 0.9 # Just reconnecting stuff
                println("Switch $sw_id is closed, Connecting everything back, no busbar splitting on bus $(sw["bus_split"])")
                for l in keys(switch_couples)
                    #if haskey(switch_couples,sw_id) && switch_couples[l]["bus_split"] == sw["bus_split"] -> wrong, you are checking the ZIL sw here
                    if switch_couples[l]["bus_split"] == sw["bus_split"] # coupling the switch couple to their split bus, if it closed, just connect everything back to the original switch
                        println("SWITCH COUPLE IS $l")

                        switch_t = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_couples["$l"]["t_sw"])"])
                        switch_f = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_couples["$l"]["f_sw"])"])
                        
                        if switch_t["t_bus"] == switch_couples[l]["bus_split"]
                            aux_t = switch_t["auxiliary"]
                            orig_t = switch_t["original"]
                            println("Element $aux_t $orig_t")
                            if aux_t == "gen"
                                input_ac_check["nw"][nw]["gen"]["$(orig_t)"]["gen_bus"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_t["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                                delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["gen"]["$(orig_t)"]["gen_bus"])
                                println("Element $aux_t $orig_t connected to $(input_ac_check["nw"][nw]["gen"]["$(orig_t)"]["gen_bus"])")
                            elseif aux_t == "load"
                                input_ac_check["nw"][nw]["load"]["$(orig_t)"]["load_bus"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_t["index"])"]["t_bus"])
                                delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["load"]["$(orig_t)"]["load_bus"])
                                println("Element $aux_t $orig_t connected to $(input_ac_check["nw"][nw]["load"]["$(orig_t)"]["load_bus"])")
                            elseif aux_t == "convdc"
                                input_ac_check["nw"][nw]["convdc"]["$(orig_t)"]["busac_i"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_t["index"])"]["t_bus"])
                                delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["convdc"]["$(orig_t)"]["busac_i"])
                                println("Element $aux_t $orig_t connected to $(input_ac_check["nw"][nw]["convdc"]["$(orig_t)"]["busac_i"])")
                            elseif aux_t == "branch" 
                                if input_ac_check["nw"][nw]["branch"]["$(orig_t)"]["f_bus"] > orig_buses && input_dict["nw"][nw]["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"] # useful if both ends of a branch are busbars being split
                                    input_ac_check["nw"][nw]["branch"]["$(orig_t)"]["f_bus"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_t["index"])"]["t_bus"])
                                    delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["branch"]["$(orig_t)"]["f_bus"])
                                    println("Element $aux_t $orig_t connected to $(input_ac_check["nw"][nw]["branch"]["$(orig_t)"]["f_bus"])")
                                elseif input_ac_check["nw"][nw]["branch"]["$(orig_t)"]["t_bus"] > orig_buses && input_dict["nw"][nw]["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                    input_ac_check["nw"][nw]["branch"]["$(orig_t)"]["t_bus"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_t["index"])"]["t_bus"])
                                    delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["branch"]["$(orig_t)"]["t_bus"])
                                    println("Element $aux_t $orig_t connected to $(input_ac_check["nw"][nw]["branch"]["$(orig_t)"]["t_bus"])")
                                end
                            end
                        elseif switch_f["t_bus"] == switch_couples[l]["bus_split"]
                            aux_f = switch_f["auxiliary"]
                            orig_f = switch_f["original"]
                            println("Element $aux_f $orig_f")
                            if aux_f == "gen"
                                input_ac_check["nw"][nw]["gen"]["$(orig_f)"]["gen_bus"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_f["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                                delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["gen"]["$(orig_f)"]["gen_bus"])
                                println("Element $aux_f $orig_f connected to $(input_ac_check["nw"][nw]["gen"]["$(orig_f)"]["gen_bus"])")
                            elseif aux_f == "load"
                                input_ac_check["nw"][nw]["load"]["$(orig_f)"]["load_bus"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_f["index"])"]["t_bus"])
                                delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["load"]["$(orig_f)"]["load_bus"])
                                println("Element $aux_f $orig_f connected to $(input_ac_check["nw"][nw]["load"]["$(orig_f)"]["load_bus"])")
                            elseif aux_f == "convdc"
                                input_ac_check["nw"][nw]["convdc"]["$(orig_f)"]["busac_i"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_f["index"])"]["t_bus"])
                                delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["convdc"]["$(orig_f)"]["busac_i"])
                                println("Element $aux_f $orig_f connected to $(input_ac_check["nw"][nw]["convdc"]["$(orig_f)"]["busac_i"])")
                            elseif aux_f == "branch" 
                                if input_ac_check["nw"][nw]["branch"]["$(orig_f)"]["f_bus"] > orig_buses && input_dict["nw"][nw]["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"] # useful if both ends of a branch are busbars being split
                                    input_ac_check["nw"][nw]["branch"]["$(orig_f)"]["f_bus"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_f["index"])"]["t_bus"])
                                    delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["branch"]["$(orig_f)"]["f_bus"])
                                    println("Element $aux_f $orig_f connected to $(input_ac_check["nw"][nw]["branch"]["$(orig_f)"]["f_bus"])")
                                elseif input_ac_check["nw"][nw]["branch"]["$(orig_f)"]["t_bus"] > orig_buses && input_dict["nw"][nw]["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                    input_ac_check["nw"][nw]["branch"]["$(orig_f)"]["t_bus"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_f["index"])"]["t_bus"])
                                    delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["branch"]["$(orig_f)"]["t_bus"])
                                    println("Element $aux_f $orig_f connected to $(input_ac_check["nw"][nw]["branch"]["$(orig_f)"]["t_bus"])")
                                end
                            end
                        end
                    end
                end
            elseif result_dict["solution"]["nw"][nw]["switch"][sw_id]["status"] <= 0.1 # Connect elements to the right bus
                println("Switch $sw_id is open, busbar splitting on bus $(sw["bus_split"])")
                delete!(input_ac_check["nw"][nw]["switch"],sw_id)
                for l in keys(switch_couples)
                    if switch_couples[l]["bus_split"] == sw["bus_split"] # coupling the switch couple to their split bus
                        println("SWITCH COUPLE IS $l")
                            switch_t = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_couples["$l"]["t_sw"])"]) 
                            aux_t = switch_t["auxiliary"]
                            orig_t = switch_t["original"]
                            println("Element $aux_t $orig_t")
                            if result_dict["solution"]["nw"][nw]["switch"]["$(switch_t["index"])"]["status"] <= 0.1
                                println("Deleting switch $(switch_t["index"])")
                                delete!(input_ac_check["nw"][nw]["switch"],"$(switch_t["index"])")
                            elseif result_dict["solution"]["nw"][nw]["switch"]["$(switch_t["index"])"]["status"] >= 0.9
                                if aux_t == "gen"
                                    input_ac_check["nw"][nw]["gen"]["$(orig_t)"]["gen_bus"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_t["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                                    delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["gen"]["$(orig_t)"]["gen_bus"])
                                    println("Element $aux_t $orig_t connected to $(input_ac_check["nw"][nw]["gen"]["$(orig_t)"]["gen_bus"])")
                                elseif aux_t == "load"
                                    input_ac_check["nw"][nw]["load"]["$(orig_t)"]["load_bus"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_t["index"])"]["t_bus"])
                                    delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["load"]["$(orig_t)"]["load_bus"])
                                    println("Element $aux_t $orig_t connected to $(input_ac_check["nw"][nw]["load"]["$(orig_t)"]["load_bus"])")
                                elseif aux_t == "convdc"
                                    input_ac_check["nw"][nw]["convdc"]["$(orig_t)"]["busac_i"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_t["index"])"]["t_bus"])
                                    delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["convdc"]["$(orig_t)"]["busac_i"])
                                    println("Element $aux_t $orig_t connected to $(input_ac_check["nw"][nw]["convdc"]["$(orig_t)"]["busac_i"])")
                                elseif aux_t == "branch" 
                                    if input_ac_check["nw"][nw]["branch"]["$(orig_t)"]["f_bus"] > orig_buses && input_dict["nw"][nw]["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"] # useful if both ends of a branch are busbars being split
                                        input_ac_check["nw"][nw]["branch"]["$(orig_t)"]["f_bus"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_t["index"])"]["t_bus"])
                                        delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["branch"]["$(orig_t)"]["f_bus"])
                                        println("Element $aux_t $orig_t connected to $(input_ac_check["nw"][nw]["branch"]["$(orig_t)"]["f_bus"])")
                                    elseif input_ac_check["nw"][nw]["branch"]["$(orig_t)"]["t_bus"] > orig_buses && input_dict["nw"][nw]["switch"]["$(switch_couples["$l"]["t_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                        input_ac_check["nw"][nw]["branch"]["$(orig_t)"]["t_bus"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_t["index"])"]["t_bus"])
                                        delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["branch"]["$(orig_t)"]["t_bus"])
                                        println("Element $aux_t $orig_t connected to $(input_ac_check["nw"][nw]["branch"]["$(orig_t)"]["t_bus"])")
                                    end
                                end
                            end
                        

                            switch_f = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_couples["$l"]["f_sw"])"]) 
                            aux_f = switch_f["auxiliary"]
                            orig_f = switch_f["original"]
                            println("Element $aux_f $orig_f")
                            if result_dict["solution"]["nw"][nw]["switch"]["$(switch_f["index"])"]["status"] <= 0.1
                                println("Deleting switch $(switch_f["index"])")
                                delete!(input_ac_check["nw"][nw]["switch"],"$(switch_f["index"])")
                            elseif result_dict["solution"]["nw"][nw]["switch"]["$(switch_f["index"])"]["status"] >= 0.9
                                if aux_f == "gen"
                                    input_ac_check["nw"][nw]["gen"]["$(orig_f)"]["gen_bus"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_f["index"])"]["t_bus"]) # here it needs to be the bus of the switch
                                    delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["gen"]["$(orig_f)"]["gen_bus"])
                                    println("Element $aux_f $orig_f connected to $(input_ac_check["nw"][nw]["gen"]["$(orig_f)"]["gen_bus"])")
                                elseif aux_f == "load"
                                    input_ac_check["nw"][nw]["load"]["$(orig_f)"]["load_bus"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_f["index"])"]["t_bus"])
                                    delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["load"]["$(orig_f)"]["load_bus"])
                                    println("Element $aux_f $orig_f connected to $(input_ac_check["nw"][nw]["load"]["$(orig_f)"]["load_bus"])")
                                elseif aux_f == "convdc"
                                    input_ac_check["nw"][nw]["convdc"]["$(orig_f)"]["busac_i"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_f["index"])"]["t_bus"])
                                    delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["convdc"]["$(orig_f)"]["busac_i"])
                                    println("Element $aux_f $orig_f connected to $(input_ac_check["nw"][nw]["convdc"]["$(orig_f)"]["busac_i"])")
                                elseif aux_f == "branch" 
                                    if input_ac_check["nw"][nw]["branch"]["$(orig_f)"]["f_bus"] > orig_buses && input_dict["nw"][nw]["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"] # useful if both ends of a branch are busbars being split
                                        input_ac_check["nw"][nw]["branch"]["$(orig_f)"]["f_bus"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_f["index"])"]["t_bus"])
                                        delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["branch"]["$(orig_f)"]["f_bus"])
                                        println("Element $aux_f $orig_f connected to $(input_ac_check["nw"][nw]["branch"]["$(orig_f)"]["f_bus"])")
                                    elseif input_ac_check["nw"][nw]["branch"]["$(orig_f)"]["t_bus"] > orig_buses && input_dict["nw"][nw]["switch"]["$(switch_couples["$l"]["f_sw"])"]["bus_split"] == switch_couples[l]["bus_split"]
                                        input_ac_check["nw"][nw]["branch"]["$(orig_f)"]["t_bus"] = deepcopy(input_dict["nw"][nw]["switch"]["$(switch_f["index"])"]["t_bus"])
                                        delete!(input_ac_check["nw"][nw]["bus"],input_ac_check["nw"][nw]["branch"]["$(orig_f)"]["t_bus"])
                                        println("Element $aux_f $orig_f connected to $(input_ac_check["nw"][nw]["branch"]["$(orig_f)"]["t_bus"])")
                                    end
                                end
                            end
                    end
                end
            end
            input_ac_check["nw"][nw]["switch"] = Dict{String,Any}()
            input_ac_check["nw"][nw]["switch_couples"] = Dict{String,Any}()
        end
        for (b_id,b) in input_dict["nw"][nw]["gen"]
            if  input_dict["nw"][nw]["bus"]["$(b["gen_bus"])"]["bus_type"] == 1
                input_dict["nw"][nw]["bus"]["$(b["gen_bus"])"]["bus_type"] = 2
            end
        end
        
        for (g_id,g) in input_dict["nw"][nw]["gen"]
            g["pg"] = result_dict["solution"]["nw"][nw]["gen"]["$g_id"]["pg"]
            g["qg"] = result_dict["solution"]["nw"][nw]["gen"]["$g_id"]["qg"]
        end
        for (g_id,g) in input_dict["nw"][nw]["bus"]
            g["va"] = result_dict["solution"]["nw"][nw]["bus"]["$g_id"]["va"]            
            g["vm"] = 1 + result_dict["solution"]["nw"][nw]["bus"]["$g_id"]["phi"]
        end
    end
    end
end


function run_feasibility_checks_per_hour_one_topology(grid, result_bs, model, optimizer,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
    result_feasibility_checks = Dict{String,Any}()
    for hour in 1:length(grid["nw"])
        result_feasibility_checks["$hour"] = Dict{String,Any}()
        feasibility_check = deepcopy(grid)
        feasibility_check_input = deepcopy(grid)
        prepare_AC_feasibility_check_mn(result_bs,feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
        result_feasibility_checks["$hour"] = _PM.solve_opf(feasibility_check["nw"]["$hour"],model,optimizer; setting = s)
        #if isnan(result_feasibility_checks["$hour"]["objective"])
        #    result_feasibility_checks["$hour"] = deepcopy(result_opf["$hour"])
        #end
    end
    return result_feasibility_checks
end

function run_pf_per_hour_one_topology(grid, result_bs, model, optimizer,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
    result_feasibility_checks = Dict{String,Any}()
    for hour in 1:length(grid["nw"])
        result_feasibility_checks["$hour"] = Dict{String,Any}()
        feasibility_check = deepcopy(grid)
        feasibility_check_input = deepcopy(grid)
        prepare_AC_pf_mn(result_bs,feasibility_check_input,feasibility_check,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
        result_feasibility_checks["$hour"] = _PM.solve_pf(feasibility_check["nw"]["$hour"],model,optimizer; setting = s)
    end
    return result_feasibility_checks
end
=#
for (b_id,b) in test_case_opf["bus"]
    println(b_id," ", b["bus_type"])
end

test_case_bs_mn_measured_pf = deepcopy(test_case_bs_mn_measured)
for h in 1:24
    for (b_id,b) in test_case_bs_mn_measured_pf["nw"]["$h"]["gen"]
        if b["bus_type"] == 1
            b["bus_type"] = 2
        end
    end
end

result_measured_pf_24_ac_one_topology = run_pf_per_hour_one_topology(test_case_bs_mn_measured,results_one_topology_sp_measured,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
result_measured_forecasted_pf_24_ac_one_topology = run_pf_per_hour_one_topology(test_case_bs_mn_measured,results_one_topology_sp_forecasted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf)

[result_measured_pf_24_ac_one_topology["$h"]["termination_status"] for h in 1:24]
[result_measured_forecasted_pf_24_ac_one_topology["$h"]["termination_status"] for h in 1:24]


json_results_one_topology_sp_forecasted = JSON.json(results_one_topology_sp_forecasted)
open(joinpath(results_folder,case,"One_topology_24_hours_forecasted_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_results_one_topology_sp_forecasted) 
end 

json_results_one_topology_sp_measured = JSON.json(results_one_topology_sp_measured)
open(joinpath(results_folder,case,"One_topology_24_hours_measured_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_results_one_topology_sp_measured) 
end 

result_forecasted_feasibility_checks_24_ac_one_topology = run_feasibility_checks_per_hour_one_topology(test_case_bs_mn_forecasted,results_one_topology_sp_forecasted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
result_forecasted_feasibility_checks_24_lpac_one_topology = run_feasibility_checks_per_hour_one_topology(test_case_bs_mn_forecasted,results_one_topology_sp_forecasted,LPACCPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
result_measured_feasibility_checks_24_ac_one_topology = run_feasibility_checks_per_hour_one_topology(test_case_bs_mn_measured,results_one_topology_sp_measured,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
result_measured_feasibility_checks_24_lpac_one_topology = run_feasibility_checks_per_hour_one_topology(test_case_bs_mn_measured,results_one_topology_sp_measured,LPACCPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
result_measured_forecasted_feasibility_checks_24_ac_one_topology = run_feasibility_checks_per_hour_one_topology(test_case_bs_mn_measured,results_one_topology_sp_forecasted,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
result_measured_forecasted_feasibility_checks_24_lpac_one_topology = run_feasibility_checks_per_hour_one_topology(test_case_bs_mn_measured,results_one_topology_sp_forecasted,LPACCPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf)

obj_bs_forecasted_lpac_one_topology   = [result_forecasted_feasibility_checks_24_lpac_one_topology["$h"]["objective"] for h in 1:24]
obj_bs_forecasted_ac_one_topology = [result_forecasted_feasibility_checks_24_ac_one_topology["$h"]["objective"] for h in 1:24]
obj_bs_measured_ac_one_topology   = [result_measured_feasibility_checks_24_ac_one_topology["$h"]["objective"] for h in 1:24]
obj_bs_measured_lpac_one_topology = [result_measured_feasibility_checks_24_lpac_one_topology["$h"]["objective"] for h in 1:24]
obj_bs_measured_forecasted_ac_one_topology   = [result_measured_forecasted_feasibility_checks_24_ac_one_topology["$h"]["objective"] for h in 1:24]
obj_bs_measured_forecasted_lpac_one_topology = [result_measured_forecasted_feasibility_checks_24_lpac_one_topology["$h"]["objective"] for h in 1:24]

obj_bs_forecasted_ac = [result_forecasted_feasibility_checks_24_ac["$i"]["objective"] for i in 1:n_hours]
obj_bs_forecasted_lpac = [result_forecasted_feasibility_checks_24_lpac["$i"]["objective"] for i in 1:n_hours]
obj_bs_measured_ac = [result_measured_feasibility_checks_24_ac["$i"]["objective"] for i in 1:n_hours]
obj_bs_measured_lpac = [result_measured_feasibility_checks_24_lpac["$i"]["objective"] for i in 1:n_hours]


plot(obj_bs_measured_ac/10^3,label = "Measured",grid = :none,ylims = (-0.01,22),xticks = 1:n_hours,xlims = (0.8,24.5),xlabel = "Hour",ylabel = "Generation costs [k€]",
legend = :bottomright,xlabelfontsize = 10,ylabelfontsize = 10,xtickfont = font(8),ytickfont = font(8))
plot!(obj_bs_measured_ac_one_topology/10^3,label = "Measured one topology")
plot!(1:n_hours,obj_bs_measured_forecasted_ac/10^3,label = "Measured with topology based on forecast input data")
plot!(obj_bs_measured_forecasted_ac_one_topology/10^3,label = "Measured one topology with topology based on forecast input data")

savefig(joinpath(results_folder_figures,case_figures,"Gen_cost_comparison_hourly_BS_and_one_topology_$(first_hour)_$(last_hour).json.svg"))


diff_measured_best_one_topology = []
diff_measured_best_one_topology_forecasted = []
#diff_measured_best_one_topology = []
for i in 1:length(obj_bs_measured_ac)
    push!(diff_measured_best_one_topology,abs(obj_bs_measured_ac[i] - obj_bs_measured_ac_one_topology[i])/obj_bs_measured_ac[i]*100)
    push!(diff_measured_best_one_topology_forecasted,abs(obj_bs_measured_ac[i] - obj_bs_measured_forecasted_ac_one_topology[i])/obj_bs_measured_ac[i]*100)
end

plot(1:n_hours, diff_measured, ylabel = "Diff in total gen costs between the two simulations [%]", grid = :none,xticks = 1:n_hours,xlims = (0.8,24.5),
ylims = (-0.03,5),yticks = 0:1:5,ytickfont = font(8),ylabelfontsize = 9,label = "Hourly BS, measured with topology based on forecast input data")
plot!(1:n_hours, diff_measured_best_one_topology, label = "One topology, measured input data")
plot!(1:n_hours, diff_measured_best_one_topology_forecasted, label = "One topology, measured with topology based on forecast input data")

savefig(joinpath(results_folder_figures,case_figures,"Percentage_gen_cost_comparison_hourly_BS_and_one_topology_$(first_hour)_$(last_hour).json.svg"))



result = Dict{String,Any}()
for hour in 1:n_hours
    result["$hour"] = Dict{String,Any}()
    result["$hour"] = _SPMTA.run_stochastic_acdcsw_AC_ZIL_one_topology_sp(test_case_bs_mn_expected_hours_sp["$hour"],LPACCPowerModel,gurobi_opf; setting = s)
end

[results_one_topology_sp["solution"]["nw"]["$h"]["switch"]["1"]["status"] for h in 1:16]

####################################################

test_case_bs_mn_forecasted_try_max_sw = deepcopy(test_case_bs_mn_forecasted_try)
test_case_bs_mn_measured_try_max_sw = deepcopy(test_case_bs_mn_measured_try)
test_case_bs_mn_expected_try_max_sw = deepcopy(test_case_bs_mn_expected_try)

test_case_bs_mn_forecasted["total_switching_actions"] = 1
test_case_bs_mn_measured["total_switching_actions"] = 1
test_case_bs_mn_expected["total_switching_actions"] = 1

for (sw_id,sw) in test_case_bs_mn_forecasted["nw"]["1"]["switch"]
    sw["maximum_actions"] = 1
end
for (sw_id,sw) in test_case_bs_mn_measured["nw"]["1"]["switch"]
    sw["maximum_actions"] = 1
end
for (sw_id,sw) in test_case_bs_mn_expected["nw"]["1"]["switch"]
    sw["maximum_actions"] = 1
end

results_one_topology_sp_forecasted_max_sw = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches(test_case_bs_mn_forecasted,LPACCPowerModel,gurobi)
results_one_topology_sp_measured_max_sw = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches(test_case_bs_mn_measured,LPACCPowerModel,gurobi)


json_results_one_topology_sp_forecasted = JSON.json(results_one_topology_sp_forecasted_max_sw)
open(joinpath(results_folder,case,"One_maximum_actions_24_hours_forecasted_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_results_one_topology_sp_forecasted) 
end 

json_results_one_topology_sp_measured = JSON.json(results_one_topology_sp_measured_max_sw)
open(joinpath(results_folder,case,"One_maximum_actions_24_hours_measured_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_results_one_topology_sp_measured) 
end 


result_forecasted_feasibility_checks_24_ac_one_max_sw = run_feasibility_checks_per_hour_one_topology(test_case_bs_mn_forecasted,results_one_topology_sp_forecasted_max_sw,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
result_forecasted_feasibility_checks_24_lpac_one_max_sw = run_feasibility_checks_per_hour_one_topology(test_case_bs_mn_forecasted,results_one_topology_sp_forecasted_max_sw,LPACCPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
result_measured_feasibility_checks_24_ac_one_max_sw = run_feasibility_checks_per_hour_one_topology(test_case_bs_mn_measured,results_one_topology_sp_measured_max_sw,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
result_measured_feasibility_checks_24_lpac_one_max_sw = run_feasibility_checks_per_hour_one_topology(test_case_bs_mn_measured,results_one_topology_sp_measured_max_sw,LPACCPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
result_forecasted_with_measured_values_feasibility_checks_24_lpac_max_sw = run_feasibility_checks_per_hour_one_topology(test_case_bs_mn_measured,results_one_topology_sp_forecasted_max_sw,LPACCPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
result_forecasted_with_measured_values_feasibility_checks_24_ac_max_sw = run_feasibility_checks_per_hour_one_topology(test_case_bs_mn_measured,results_one_topology_sp_forecasted_max_sw,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf)


obj_bs_forecasted_lpac_one_sw   = [result_forecasted_feasibility_checks_24_lpac_one_max_sw["$h"]["objective"] for h in 1:24]
obj_bs_forecasted_ac_one_sw = [result_forecasted_feasibility_checks_24_ac_one_max_sw["$h"]["objective"] for h in 1:24]
obj_bs_measured_ac_one_sw   = [result_measured_feasibility_checks_24_ac_one_max_sw["$h"]["objective"] for h in 1:24]
obj_bs_measured_lpac_one_sw = [result_measured_feasibility_checks_24_lpac_one_max_sw["$h"]["objective"] for h in 1:24]
obj_bs_forecasted_with_measured_lpac_one_sw = [result_forecasted_with_measured_values_feasibility_checks_24_lpac_max_sw["$h"]["objective"] for h in 1:24]
obj_bs_forecasted_with_measured_ac_one_sw = [result_forecasted_with_measured_values_feasibility_checks_24_ac_max_sw["$h"]["objective"] for h in 1:24]


diff_measured_best_one_sw = []
diff_measured_best_one_sw_forecasted = []

for i in 1:length(obj_bs_measured_ac)
    push!(diff_measured_best_one_sw,abs(obj_bs_measured_ac[i] - obj_bs_measured_ac_one_sw[i])/obj_bs_measured_ac[i]*100)
    push!(diff_measured_best_one_sw_forecasted,abs(obj_bs_measured_ac[i] - obj_bs_forecasted_with_measured_ac_one_sw[i])/obj_bs_measured_ac[i]*100)
end


plot(1:n_hours, diff_measured, ylabel = "Diff in total gen costs between the two simulations [%]", grid = :none,xticks = 1:n_hours,xlims = (0.8,24.5),
ylims = (-0.03,5),yticks = 0:1:5,ytickfont = font(8),ylabelfontsize = 9,label = "Hourly BS, measured with topology based on forecast input data")
plot!(1:n_hours, diff_measured_best_one_topology, label = "One topology, measured input data")
plot!(1:n_hours, diff_measured_best_one_topology_forecasted, label = "One topology, measured with topology based on forecast input data")
plot!(1:n_hours, diff_measured_best_one_sw, label = "Max one switching action, measured input data")
plot!(1:n_hours, diff_measured_best_one_sw_forecasted, label = "Max one switching action, measured with topology based on forecast input data")


savefig(joinpath(results_folder_figures,case_figures,"Percentage_gen_cost_comparison_hourly_BS_and_one_sw_action_$(first_hour)_$(last_hour).json.svg"))




#######

test_case_bs_mn_forecasted_try_max_sw_2 = deepcopy(test_case_bs_mn_forecasted)
test_case_bs_mn_measured_try_max_sw_2 = deepcopy(test_case_bs_mn_measured)
test_case_bs_mn_expected_try_max_sw_2 = deepcopy(test_case_bs_mn_expected)

test_case_bs_mn_forecasted["total_switching_actions"] = 2
test_case_bs_mn_measured["total_switching_actions"] = 2
test_case_bs_mn_expected["total_switching_actions"] = 2

for (sw_id,sw) in test_case_bs_mn_forecasted["nw"]["1"]["switch"]
    sw["maximum_actions"] = 2
end
for (sw_id,sw) in test_case_bs_mn_measured["nw"]["1"]["switch"]
    sw["maximum_actions"] = 2
end
for (sw_id,sw) in test_case_bs_mn_expected["nw"]["1"]["switch"]
    sw["maximum_actions"] = 2
end

results_one_topology_sp_forecasted_max_sw_2 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches(test_case_bs_mn_forecasted,LPACCPowerModel,gurobi)
results_one_topology_sp_measured_max_sw_2 = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches(test_case_bs_mn_measured,LPACCPowerModel,gurobi)



json_results_one_topology_sp_forecasted = JSON.json(results_one_topology_sp_forecasted_max_sw_2)
open(joinpath(results_folder,case,"Two_maximum_actions_24_hours_forecasted_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_results_one_topology_sp_forecasted) 
end 

json_results_one_topology_sp_measured = JSON.json(results_one_topology_sp_measured_max_sw_2)
open(joinpath(results_folder,case,"Two_maximum_actions_24_hours_measured_$(first_hour)_$(last_hour).json"),"w") do f 
    write(f, json_results_one_topology_sp_measured) 
end 


result_forecasted_feasibility_checks_24_ac_two_max_sw = run_feasibility_checks_per_hour_one_topology(test_case_bs_mn_forecasted,results_one_topology_sp_forecasted_max_sw_2,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
result_forecasted_feasibility_checks_24_lpac_two_max_sw = run_feasibility_checks_per_hour_one_topology(test_case_bs_mn_forecasted,results_one_topology_sp_forecasted_max_sw_2,LPACCPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
result_measured_feasibility_checks_24_ac_two_max_sw = run_feasibility_checks_per_hour_one_topology(test_case_bs_mn_measured,results_one_topology_sp_measured_max_sw_2,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
result_measured_feasibility_checks_24_lpac_two_max_sw = run_feasibility_checks_per_hour_one_topology(test_case_bs_mn_measured,results_one_topology_sp_measured_max_sw_2,LPACCPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
result_forecasted_with_measured_values_feasibility_checks_24_lpac_max_sw = run_feasibility_checks_per_hour_one_topology(test_case_bs_mn_measured,results_one_topology_sp_forecasted_max_sw_2,LPACCPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf)
result_forecasted_with_measured_values_feasibility_checks_24_ac_max_sw = run_feasibility_checks_per_hour_one_topology(test_case_bs_mn_measured,results_one_topology_sp_forecasted_max_sw_2,ACPPowerModel,ipopt,switches_couples_ac,extremes_ZILs_ac,test_case_opf)


obj_bs_forecasted_lpac_two_sw   = [result_forecasted_feasibility_checks_24_lpac_two_max_sw["$h"]["objective"] for h in 1:24]
obj_bs_forecasted_ac_one_sw = [result_forecasted_feasibility_checks_24_ac_two_max_sw["$h"]["objective"] for h in 1:24]
obj_bs_measured_ac_two_sw   = [result_measured_feasibility_checks_24_ac_two_max_sw["$h"]["objective"] for h in 1:24]
obj_bs_measured_lpac_two_sw = [result_measured_feasibility_checks_24_lpac_two_max_sw["$h"]["objective"] for h in 1:24]
obj_bs_forecasted_with_measured_lpac_two_sw = [result_forecasted_with_measured_values_feasibility_checks_24_lpac_max_sw["$h"]["objective"] for h in 1:24]
obj_bs_forecasted_with_measured_ac_two_sw = [result_forecasted_with_measured_values_feasibility_checks_24_ac_max_sw["$h"]["objective"] for h in 1:24]


diff_measured_best_two_sw = []
diff_measured_best_two_sw_forecasted = []

for i in 1:length(obj_bs_measured_ac)
    push!(diff_measured_best_two_sw,abs(obj_bs_measured_ac[i] - obj_bs_measured_ac_two_sw[i])/obj_bs_measured_ac[i]*100)
    push!(diff_measured_best_two_sw_forecasted,abs(obj_bs_measured_ac[i] - obj_bs_forecasted_with_measured_ac_two_sw[i])/obj_bs_measured_ac[i]*100)
end


plot(1:n_hours, diff_measured, ylabel = "Diff in total gen costs between the two simulations [%]", grid = :none,xticks = 1:n_hours,xlims = (0.8,24.5),
ylims = (-0.03,5),yticks = 0:1:5,ytickfont = font(8),ylabelfontsize = 9,label = "Hourly BS, measured with topology based on forecast input data")
plot!(1:n_hours, diff_measured_best_one_topology, label = "One topology, measured input data")
plot!(1:n_hours, diff_measured_best_one_topology_forecasted, label = "One topology, measured with topology based on forecast input data")
plot!(1:n_hours, diff_measured_best_two_sw, label = "Max two switching action, measured input data")
plot!(1:n_hours, diff_measured_best_two_sw_forecasted, label = "Max two switching action, measured with topology based on forecast input data")

savefig(joinpath(results_folder_figures,case_figures,"Percentage_gen_cost_comparison_hourly_BS_and_two_sw_action_$(first_hour)_$(last_hour).json.svg"))


plot(1:n_hours, diff_measured, ylabel = "Diff in total gen costs between the two simulations [%]", grid = :none,xticks = 1:n_hours,xlims = (0.8,24.5),
ylims = (-0.03,5),yticks = 0:1:5,ytickfont = font(8),ylabelfontsize = 9,label = "Hourly BS, measured with topology based on forecast input data")
plot!(1:n_hours, diff_measured_best_one_topology, label = "One topology, measured input data")
plot!(1:n_hours, diff_measured_best_one_topology_forecasted, label = "One topology, measured with topology based on forecast input data")
plot!(1:n_hours, diff_measured_best_one_sw, label = "Max one switching action, measured input data")
plot!(1:n_hours, diff_measured_best_one_sw_forecasted, label = "Max one switching action, measured with topology based on forecast input data")
plot!(1:n_hours, diff_measured_best_two_sw, label = "Max two switching action, measured input data")
plot!(1:n_hours, diff_measured_best_two_sw_forecasted, label = "Max two switching action, measured with topology based on forecast input data")

savefig(joinpath(results_folder_figures,case_figures,"Percentage_gen_cost_comparison_everything_$(first_hour)_$(last_hour).json.svg"))




































gurobi_bs = JuMP.optimizer_with_attributes(Gurobi.Optimizer,"time_limit" => 1800,"MIPGap" => mip_gap,"BarHomogeneous" => 1,"ScaleFlag"=>2,"MIPFocus"=>3) 
results_one_topology_sp_expected_max_sw = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches(test_case_bs_mn_expected,LPACCPowerModel,gurobi_bs)

results_one_topology_sp_expected_max_sw = _SPMTA.run_stochastic_acdcsw_AC_ZIL_limit_switching_actions_sp_all_switches_stochastic(test_case_bs_mn_expected,LPACCPowerModel,gurobi)

first_hours = []
scenario_idx = 1
scenarios = 8
for hour in 1:24
    push!(first_hours,(hour - 1)*scenarios + scenario_idx)
end





[results_one_topology_sp_expected_max_sw["solution"]["nw"]["1"]["switch"][sw_id]["status"] for (sw_id,sw) in test_case_bs_mn_expected_try_max_sw["nw"]["1"]["switch"]]
[results_one_topology_sp_expected_max_sw["solution"]["nw"]["$h"]["switch"]["1"]["status"] for h in eachindex(test_case_bs_mn_expected_try_max_sw["nw"])]
[results_one_topology_sp_expected_max_sw["solution"]["nw"]["$h"]["switch"]["2"]["status"] for h in 1:32]
[results_one_topology_sp_expected_max_sw["solution"]["nw"]["$h"]["switch"]["3"]["status"] for h in 1:32]
[results_one_topology_sp_expected_max_sw["solution"]["nw"]["$h"]["switch"]["4"]["status"] for h in 1:32]
[results_one_topology_sp_expected_max_sw["solution"]["nw"]["$h"]["switch"]["5"]["status"] for h in 1:32]
[results_one_topology_sp_expected_max_sw["solution"]["nw"]["$h"]["switch"]["6"]["status"] for h in 1:32]
[results_one_topology_sp_expected_max_sw["solution"]["nw"]["$h"]["switch"]["7"]["status"] for h in 1:32]
[results_one_topology_sp_expected_max_sw["solution"]["nw"]["$h"]["switch"]["8"]["status"] for h in 1:32]
[results_one_topology_sp_expected_max_sw["solution"]["nw"]["$h"]["switch"]["9"]["status"] for h in 1:32]
[results_one_topology_sp_expected_max_sw["solution"]["nw"]["$h"]["switch"]["10"]["status"] for h in eachindex(test_case_bs_mn_expected_try_max_sw["nw"])]