using Distributions
using Plots

# (α,β) = (2.8940052551265323, 10.189248170864987)

# # Define the beta distributions
# beta_dist_1 = Beta(α, β) # shape parameters = 2, 2
# beta_dist_2 = Beta(2, 5) # shape parameters = 2, 5
# beta_dist_3 = Beta(5, 2) # shape parameters = 5, 2

# # Plot the distributions
# Θ = 0:0.01:1
# plot(Θ, pdf.(beta_dist_1, Θ), label="Beta (2.9, 10.2)")
# plot!(Θ, pdf.(beta_dist_2, Θ), label="Beta (2, 5)")
# plot!(Θ, pdf.(beta_dist_3, Θ), label="Beta (5, 2)")
# xlabel!("θ")
# ylabel!("Probability Density")
# title!("Beta Distributions")

Θ = 0:1:500

valor_lb = 90.
valor_ub = 200.
prob_lb = .10
prob_ub = 1 - prob_lb

α = log( log(1-prob_lb) / log(1-prob_ub) ) / log( valor_lb / valor_ub )
λ = valor_ub / exp( log(log(1/(1-prob_ub))) / α )
weibull_dist = Weibull(α, λ) 
#plot(Θ, pdf.(weibull_dist, Θ), label="Weibull")


_, μ, σ = ajustaPrecioReserva(valor_lb, valor_ub, prob_lb, prob_ub)
lognormal_dist = LogNormal(μ, σ) 
#plot!(Θ, pdf.(lognormal_dist, Θ), label="LogNormal")


uniform_dist = Uniform(valor_lb, valor_ub) 
plot!(Θ, pdf.(uniform_dist, Θ), label="Uniform")