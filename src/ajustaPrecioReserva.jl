function ajustaPrecioReserva(valorMercado_lotes::Float64, valorInmobiliario::Float64, prob_ventaValorMercado::Float64, prob_ventaValorInmobiliario::Float64)
    #Esta función ajusta los parámetros mu y sigma de una distribución LogNormal del precio de reserva r de manera que:
    # prob(r < valorMercado) = prob_ventaValorMercado y prob(r < valorInmobiliario) = prob_ventaValorInmobiliario

    function f(x::AbstractVector, valorMercado, valorInmobiliario, prob_ventaValorMercado, prob_ventaValorInmobiliario)

        mu = x[1]
        sigma = x[2]

        prob_valorMercado = Distributions.cdf(Distributions.LogNormal(mu, sigma), valorMercado)
        prob_valorInmobiliario = Distributions.cdf(Distributions.LogNormal(mu, sigma), valorInmobiliario)
    
        dif_cuad = (prob_valorMercado-prob_ventaValorMercado)^2 + (prob_valorInmobiliario - prob_ventaValorInmobiliario)^2

        return dif_cuad
    end

    g(x::AbstractVector) = -x[1]

    lb_param = [0, 0]
    ub_param = [10, 10]

    m = NonconvexBayesian.Model()
    set_objective!(m, x -> f(x, valorMercado_lotes, valorInmobiliario, prob_ventaValorMercado, prob_ventaValorInmobiliario))
    addvar!(m, lb_param, ub_param)
    add_ineq_constraint!(m, x -> g(x))

    alg = BayesOptAlg(IpoptAlg())
    options = BayesOptOptions(
        sub_options = IpoptOptions(print_level = 0), maxiter = 10, ctol = 1e-4,
        ninit = 2, initialize = true, postoptimize = false, fit_prior = true,
    )
    r = optimize(m, alg, lb_param, options = options);
    fopt = r.minimum
    mu_opt = r.minimizer[1]
    sigma_opt = r.minimizer[2]

    return fopt, mu_opt, sigma_opt
end

function ajustaPrecioReserva(valorMercado_lotes::Vector{Float64}, valorInmobiliario_combis::Vector{Float64}, C::Matrix{Int64}, prob_ventaValorMercado, prob_ventaValorInmobiliario)
    #Esta versión acepta los vectores valorMercado_lotes y valorInmobiliario_combis además de la matriz de combinaciones C
    
    numLotes = length(valorMercado_lotes)
    fopt = zeros(numLotes,1)
    mu_vec = zeros(numLotes,1)
    sigma_vec = zeros(numLotes,1)
    for k = 1:numLotes
        flag = C[:,k]
        valorInmobiliario_vec = valorInmobiliario_combis[ flag .== 1] ./ sum(C[flag .== 1,:], dims=2)
        valorInmobiliario = sum(valorInmobiliario_vec) / length(valorInmobiliario_vec)
        fopt[k], mu_vec[k], sigma_vec[k] = ajustaPrecioReserva(valorMercado_lotes[k], valorInmobiliario, prob_ventaValorMercado, prob_ventaValorInmobiliario)
    end
    return fopt, mu_vec, sigma_vec
end