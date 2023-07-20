using Plots

Θ = 30000:5:50000.

valor_lb = 38888.; prob_lb = .10
δ = valor_lb * .9
valor_ub = 45000.; prob_ub = 1 - prob_lb


α = log( log(1-prob_lb) / log(1-prob_ub) ) / log( (valor_lb - δ) / (valor_ub - δ) )
λ = (valor_ub - δ) / exp( log(log(1/(1-prob_ub))) / α )
cdf_weibull = [Θ[i] - δ < 0 ? 0 : 1 - exp(-((Θ[i] - δ) / λ)^α) for i in eachindex(Θ)]
pdf_weibull = cdf_weibull[2:end] .- cdf_weibull[1:end-1]
plot(Θ[1:end-1], pdf_weibull, label="Weibull")

