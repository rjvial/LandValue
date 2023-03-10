
function bid_price_dinamico(valorMercado_lote, valorInmobiliario_lote, mu, sigma, T)
    # Este caso no considera aprendizaje

    function f(x::AbstractVector, valorInmobiliario_lote, T)
          
        prob = [Distributions.cdf(Distributions.LogNormal(mu, sigma), x[i]) for i = 1:T]
        utilEsp = 0
        for t = 1:T
            prob_t = prob[t]
            util_t = (valorInmobiliario_lote - x[t]) * prob_t
            for k = 1:t-1
                util_t *= (1 - prob[k])
            end
            utilEsp += util_t
        end
        return -utilEsp
    end

    g(x::AbstractVector) = -x[1]
    
    m = NonconvexBayesian.Model()
    set_objective!(m, x -> f(x, valorInmobiliario_lote, T))
    x_lb = vec(valorMercado_lote .* zeros(T,1))
    x_ub = vec(valorInmobiliario_lote .* ones(T,1))
    addvar!(m, x_lb, x_ub)
    add_ineq_constraint!(m, x -> g(x))

    alg = BayesOptAlg(IpoptAlg())
    options = BayesOptOptions(
        sub_options = IpoptOptions(print_level = 0), maxiter = 10, ctol = 1e-4,
        ninit = 2, initialize = true, postoptimize = false, fit_prior = true,
    )
    r = optimize(m, alg, x_lb .* 1.05, options = options);

    fopt = -r.minimum
    xopt = r.minimizer

    return fopt, xopt
end