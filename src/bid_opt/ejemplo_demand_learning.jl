using NonconvexBayesian, NonconvexIpopt, NonconvexNLopt

function f_w2b(x::AbstractVector, p, λ, s)

    α = x[1] # Shape param in the Beta distribution (θ random variable). Parámetro asociado a la venta
    β = x[2] # Shape param in the Beta distribution (θ random variable). Parametro asociado a la no venta
    # α chico y β grande hace que la distribución se cargue a la izquierda

    k = 2 # Shape param in the Weibull distribution (Reservtion price). Cambia la forma: desde exponencial a normal

    mean_beta = α/(α+β)
    coefOfVar_beta = sqrt(β/(α*(α+β+1)))
    sellProb_weibull = 1-exp(-(p/λ)^k)

    dif_total =  (mean_beta - sellProb_weibull)^2 + (coefOfVar_beta - s)^2

    return dif_total
end

function f_b2w(x::AbstractVector, p, α, β)

    k = 2 # Shape param in the Weibull distribution (Reservtion price). Cambia la forma: desde exponencial a normal
    λ = x[1] # Scale param in the Weibull distribution (Reservtion price). Contrae función hacia la izquierda
    s = x[2]

    mean_beta = α/(α+β)
    coefOfVar_beta = sqrt(β/(α*(α+β+1)))
    sellProb_weibull = 1-exp(-(p/λ)^k)

    dif_total =  (mean_beta - sellProb_weibull)^2 + (coefOfVar_beta - s)^2

    return dif_total
end


p = 1

g(x::AbstractVector) = -x[1]

m = Model()

# λ = 2 # Scale param in the Weibull distribution (Reservtion price). Contrae función hacia la izquierda
# s = .5
# set_objective!(m, x -> f_w2b(x, p, λ, s))

α = 2.8940052551265323 # Shape param in the Beta distribution (θ random variable). Parámetro asociado a la venta
β = 10.189248170864987 # Shape param in the Beta distribution (θ random variable). Parametro asociado a la no venta
set_objective!(m, x -> f_b2w(x, p, α, β))

addvar!(m, [0., 0.], [1000.0, 1000.0])
add_ineq_constraint!(m, x -> g(x))


alg = BayesOptAlg(IpoptAlg())
options = BayesOptOptions(
    sub_options = IpoptOptions(print_level = 0), maxiter = 10, ctol = 1e-4,
    ninit = 2, initialize = true, postoptimize = false, fit_prior = true,
)
r = optimize(m, alg, [0., 0.], options = options);
r.minimum
r.minimizer
