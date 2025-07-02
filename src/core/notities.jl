scenario_wind_4 = JSON.parsefile(joinpath(input_folder,"case30","scenario_wind_4_$(first_hour)_$(last_hour)_modified.json"))
scenario_wind_4_adjusted = JSON.parsefile(joinpath(input_folder,"case30","scenario_wind_4_$(first_hour)_$(last_hour)_adjusted.json"))
scenario_wind_8 = JSON.parsefile(joinpath(input_folder,"case30","scenario_wind_8_$(first_hour)_$(last_hour)_modified.json"))
N_4 = 4
N_8 = 8

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
errors_4 = [scenario_wind_4["$i"]["error"] for i in 1:(N_4*24)]
forecast_4 = [forecasted_values_4[i]+scenario_wind_4["$i"]["error"] for i in 1:(N_4*24)]
probabilities_4 = [scenario_wind_4["$i"]["probability"] for i in 1:(N_4*24)]
probabilities_4 = round.(probabilities_4, digits=2)

errors_8 = [scenario_wind_8["$i"]["error"] for i in 1:(N_8*24)]
forecast_8 = [forecasted_values_8[i]+scenario_wind_8["$i"]["error"] for i in 1:(N_8*24)]
probabilities_8 = [scenario_wind_8["$i"]["probability"] for i in 1:(N_8*24)]
probabilities_8 = round.(probabilities_8, digits=2)

figures_folder = "/Users/giacomobastianel/Library/CloudStorage/OneDrive-KULeuven/IJEPES_paper/Figures/RES_uncertainty"


hours = collect(1:24)
scatter(hours,measured_wind,label = "Measured",grid = :none,color = :lightblue)
scatter!(hours,forecasted_wind,label = "Forecasted",color = :orange)
scatter!(x_values_4,forecast_4,xticks = 1:1:24,label = "Stochastic",color = :green)
plot!(hours,forecasted_wind,label = :none,color = :orange,linewidth = 2)
plot!(hours,measured_wind,label = :none,color = :lightblue,linewidth = 2)
savefig(joinpath(figures_folder, "Scenarios_4.pdf"))
savefig(joinpath(figures_folder, "Scenarios_4.svg"))

for i in 1:N_4*24
    annotate!(x_values_4[i]+0.2, forecast_4[i]+0.03, (probabilities_4[i], 5, :green))
end
display(current())



scatter(hours,measured_wind,label = "Measured",grid = :none,color = :lightblue)
scatter!(hours,forecasted_wind,label = "Forecasted",color = :orange)
scatter!(x_values_8,forecast_8,xticks = 1:1:24,label = "Stochastic",color = :green)
plot!(hours,forecasted_wind,label = :none,color = :orange,linewidth = 2)
plot!(hours,measured_wind,label = :none,color = :lightblue,linewidth = 2)
savefig(joinpath(figures_folder, "Scenarios_8.pdf"))
savefig(joinpath(figures_folder, "Scenarios_8.svg"))

case_5 = _PM.parse_file(joinpath(dirname(dirname(input_folder)),"data_sources","case5_acdc.m"))
_PMACDC.process_additional_data!(case_5)

result_dc_opf = _PMACDC.run_acdcopf(case_5,DCPPowerModel,settings = s)