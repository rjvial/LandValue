using NonconvexBayesian, NonconvexIpopt, NonconvexNLopt, Distributions, Plots

function f_w2b(x::AbstractVector, p, k, λ, s)

    α = x[1] # Shape param in the Beta distribution (θ random variable). Parámetro asociado a la venta
    β = x[2] # Shape param in the Beta distribution (θ random variable). Parametro asociado a la no venta
    # α chico y β grande hace que la distribución se cargue a la izquierda

    mean_beta = α/(α+β)
    coefOfVar_beta = sqrt(β/(α*(α+β+1)))
    sellProb_weibull = 1-exp(-(p/λ)^k)

    dif_total =  (mean_beta - sellProb_weibull)^2 + (coefOfVar_beta - s)^2

    return dif_total
end

function f_b2w(x::AbstractVector, p, k, α, β)

    λ = x[1] # Scale param in the Weibull distribution (Reservtion price). Contrae función hacia la izquierda
    s = x[2]

    mean_beta = α/(α+β)
    coefOfVar_beta = sqrt(β/(α*(α+β+1)))
    sellProb_weibull = 1-exp(-(p/λ)^k)

    dif_total =  (mean_beta - sellProb_weibull)^2 + (coefOfVar_beta - s)^2

    return dif_total
end

function weibull_rnd(k, λ)
    dist = Weibull(k, λ)
    return rand(dist)
end

g(x::AbstractVector) = -x[1]



function sim(p, k, λ_real, λ, s)
    alg = BayesOptAlg(IpoptAlg())
    options = BayesOptOptions(
        sub_options = IpoptOptions(print_level = 0), maxiter = 10, ctol = 1e-4,
        ninit = 2, initialize = true, postoptimize = false, fit_prior = true,
    )
    for i = 1:500
        m = Model()
        set_objective!(m, x -> f_w2b(x, p, k, λ, s))
        addvar!(m, [0., 0.], [50.0, 50.0])
        add_ineq_constraint!(m, x -> g(x))
        res = optimize(m, alg, [0., 0.], options = options);
        res.minimum
        res.minimizer
        (α, β) = (res.minimizer[1], res.minimizer[2])

        r = weibull_rnd(k, λ_real)
        if r <= p 
            x = 1
        else
            x = 0
        end

        (α, β) = (α + x, β + 1 - x)
        m = Model()
        set_objective!(m, x -> f_b2w(x, p, k, α, β))
        addvar!(m, [0., 0.], [50.0, 50.0])
        add_ineq_constraint!(m, x -> g(x))
        res = optimize(m, alg, [0., 0.], options = options);
        res.minimum
        res.minimizer
        (λ, s) = (res.minimizer[1], res.minimizer[2])

        display([x, λ, s])
        display(" ")
        # beta_dist = Beta(α, β) 
        # Θ = 0:0.01:1
        # plot(Θ, pdf.(beta_dist, Θ), label="Beta (a, a)")
    end
end

p = 2
k = 2 # Shape param in the Weibull distribution (Reservtion price). Cambia la forma: desde exponencial a normal

λ_real = 2

λ = 5
s = .5


sim(p, k, λ_real, λ, s)