
function bid_prices_pivot(valorMercado_lotes, valorInmobiliario_combis, C, mu_pre, sigma_pre, mu_post, sigma_post, p, minProb)

    
    function f(x::AbstractVector, mu_pre, sigma_pre, mu_post, sigma_post, valorInmobiliario_combis, C, p)
        numCombis, numLotes = size(C)
        prob_vec_pre = [Distributions.cdf(Distributions.LogNormal(mu_pre[i], sigma_pre[i]), x[i]) for i = 1:numLotes]
        prob_vec_post = [Distributions.cdf(Distributions.LogNormal(mu_post[i], sigma_post[i]), x[i]) for i = 1:numLotes]

        utilEsp = sum(
                        (valorInmobiliario_combis[k] - sum(C[k,i] * x[i] for i in 1:numLotes)) * 
                        prod(C[k,i] == 1 ? 
                            (i == p ? prob_vec_pre[i] : prob_vec_post[i]) : 
                            1 - (i == p ? prob_vec_pre[i] : prob_vec_post[i]) for i in 1:numLotes) for k in 1:numCombis)

        return -utilEsp
    end

    lb_lotes = valorMercado_lotes
    ub_lotes = 3 .* valorMercado_lotes

    function g(x::AbstractVector, mu_pre, sigma_pre, mu_post, sigma_post, C, minProb)
        numCombis, numLotes = size(C)
        prob_vec_pre = [Distributions.cdf(Distributions.LogNormal(mu_pre[i], sigma_pre[i]), x[i]) for i = 1:numLotes]
        prob_vec_post = [Distributions.cdf(Distributions.LogNormal(mu_post[i], sigma_post[i]), x[i]) for i = 1:numLotes]

        probCombis = sum( [ prod([C[k, i] == 1 ? (i == p ? prob_vec_pre[i] : prob_vec_post[i]) : 1 - (i == p ? prob_vec_pre[i] : prob_vec_post[i]) for i = 1:numLotes]) 
                        for k = 1:numCombis ] )

        return minProb - probCombis
    end

    
    m = NonconvexBayesian.Model()
    set_objective!(m, x -> f(x, mu_pre, sigma_pre, mu_post, sigma_post, valorInmobiliario_combis, C, p))
    addvar!(m, lb_lotes, ub_lotes)
    add_ineq_constraint!(m, x -> g(x, mu_pre, sigma_pre, mu_post, sigma_post, C, minProb))

    alg = BayesOptAlg(IpoptAlg())
    options = BayesOptOptions(
        sub_options = IpoptOptions(print_level = 0), maxiter = 10, ctol = 1e-4,
        ninit = 2, initialize = true, postoptimize = false, fit_prior = true,
    )
    r = optimize(m, alg, lb_lotes, options = options);

    fopt = -r.minimum
    xopt = r.minimizer

    return fopt, xopt
end