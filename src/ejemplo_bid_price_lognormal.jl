using NonconvexBayesian, NonconvexIpopt, NonconvexNLopt, Distributions
# Este caso asume multiples etapas de ofertas

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
    ub_param = [30, 30]

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

T = 3 # numero de ofertas que se puede hacer

valorMercado_lote = 35000.
valorInmobiliario_lote = 45000.

prob_ventaValorMercado = .01
prob_ventaValorInmobiliario = .90

_, mu, sigma = ajustaPrecioReserva(valorMercado_lote, valorInmobiliario_lote, prob_ventaValorMercado, prob_ventaValorInmobiliario)


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
