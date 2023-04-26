function bid_price_aprendizaje_uniforme(valorMercado_lote, valorInmobiliario_lote, T)
    # Este caso asume que aprendizaje con precio de reserva distribuido uniforme

    function f(x::AbstractVector, valorMercado_lote, valorInmobiliario_lote, T)
        # Con Aprendizaje
        lb = valorMercado_lote
        ub = valorInmobiliario_lote
        
        utilEsp = 0
        for t = 1:T
            if t == 1
                prob_t = (x[t] - lb) / (ub - lb)
                util_t = (valorInmobiliario_lote - x[t]) * prob_t
            else
                util_t = (valorInmobiliario_lote - x[t])
                for k = 1:t-1
                    prob_k = k == 1 ? (x[k] - lb) / (ub - lb) : (x[k] - x[k-1]) / (ub - x[k-1])
                    util_t = util_t * (1 - prob_k)
                end
                prob_t = (x[t] - x[t-1]) / (ub - x[t-1])
                util_t = util_t * prob_t
            end
            utilEsp = utilEsp + util_t
        end
        return -utilEsp
    end

    # function f(x::AbstractVector, valorMercado_lote, valorInmobiliario_lote, T)
    #     # Sin Aprendizaje
    #     lb = valorMercado_lote
    #     ub = valorInmobiliario_lote
        
    #     utilEsp = 0
    #     for t = 1:T
    #         prob_t = (x[t] - lb) / (ub - lb)
    #         util_t = (valorInmobiliario_lote - x[t])
    #         if t >= 2
    #             for k = 1:t-1
    #                 prob_k = (ub - x[k]) / (ub - lb)
    #                 util_t = util_t * prob_k
    #             end
    #         end
    #         util_t = util_t * prob_t
    #         utilEsp = utilEsp + util_t
    #     end
    #     return -utilEsp
    # end

    g(x::AbstractVector) = -x[1]
    
    m = NonconvexBayesian.Model()
    set_objective!(m, x -> f(x, valorMercado_lote, valorInmobiliario_lote, T))
    x_lb = vec(90 .* ones(T,1))
    x_ub = vec(200 .* ones(T,1))
    addvar!(m, x_lb, x_ub)
    add_ineq_constraint!(m, x -> g(x))

    alg = BayesOptAlg(IpoptAlg())
    options = BayesOptOptions(
        sub_options = IpoptOptions(print_level = 0), maxiter = 10, ctol = 1e-4,
        ninit = 2, initialize = true, postoptimize = false, fit_prior = true,
    )
    r = optimize(m, alg, x_lb, options = options);

    fopt = -r.minimum
    xopt = r.minimizer

    return fopt, xopt
end