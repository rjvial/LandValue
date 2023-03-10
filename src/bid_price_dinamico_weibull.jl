function bid_price_dinamico_weibull(valorInmobiliario_lote, α, λ, T)
    

    # function f(x::AbstractVector, valor_high, α, λ, T)
    #     # Con Aprendizaje
    #     utilEsp = 0
    #     for t = 1:T
            
    #         if t == 1
    #             prob_t = x[t] < 90 ? 0 : 1 - exp(-(x[t]/λ)^α)
    #             util_t = (valor_high - x[t]) * prob_t
    #         else
    #             util_t = (valor_high - x[t])
    #             for k = 1:t-1
    #                 valor_lb = k == 1 ? 90 : x[k-1]
    #                 valor_ub = valorInmobiliario_lote
    #                 prob_lb = .10
    #                 prob_ub = .90
    #                 α = log( log(1-prob_lb) / log(1-prob_ub) ) / log( valor_lb / valor_ub )
    #                 λ = valor_ub / exp( log(log(1/(1-prob_ub))) / α )
    #                 prob_k = x[k] < (k == 1 ? 90 : x[k-1]) ? 0 : 1 - exp(-(x[k]/λ)^α)
    #                 util_t = util_t * (1 - prob_k)
    #             end
    #             valor_lb = x[t-1]
    #             valor_ub = valorInmobiliario_lote
    #             prob_lb = .10
    #             prob_ub = .90
    #             α = log( log(1-prob_lb) / log(1-prob_ub) ) / log( valor_lb / valor_ub )
    #             λ = valor_ub / exp( log(log(1/(1-prob_ub))) / α )
    #             prob_t = x[t] < x[t-1] ? -1 : 1 - exp(-(x[t]/λ)^α)
    #             util_t = util_t * prob_t
    #         end
    #         utilEsp = utilEsp + util_t

    #     end
    #     return -utilEsp
    # end

    function f(x::AbstractVector, valor_high, α, λ, T)
        # Sin Aprendizaje
        utilEsp = 0
        for t = 1:T
            
            if t == 1
                prob_t = 1 - exp(-(x[t]/λ)^α)
                util_t = (valor_high - x[t]) * prob_t
            else
                util_t = (valor_high - x[t])
                for k = 1:t-1
                    prob_k = 1 - exp(-(x[k]/λ)^α)
                    util_t = util_t * (1 - prob_k)
                end
                prob_t = 1 - exp(-(x[t]/λ)^α)
                util_t = util_t * prob_t
            end
            utilEsp = utilEsp + util_t

        end
        return -utilEsp
    end

    function g(x::AbstractVector, T)
        return [- x[t] for t=1:T]
    end
    
    m = NonconvexBayesian.Model()
    set_objective!(m, x -> f(x, valorInmobiliario_lote, α, λ, T))
    x_lb = vec(90 .* ones(T,1))
    x_ub = vec(200 .* ones(T,1))
    addvar!(m, x_lb, x_ub)
    add_ineq_constraint!(m, x -> g(x, T))

    alg = BayesOptAlg(IpoptAlg())
    options = BayesOptOptions(
        sub_options = IpoptOptions(print_level = 0), maxiter = 10, ctol = 1e-4,
        ninit = 2, initialize = true, postoptimize = false, fit_prior = true,
    )
    r = optimize(m, alg, x_lb , options = options);

    fopt = -r.minimum
    xopt = r.minimizer

    return fopt, xopt
end