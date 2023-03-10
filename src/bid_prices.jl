
function bid_prices(valorMercado_lotes, valorInmobiliario_combis, C, mu, sigma, minProb)

    lb_lotes = valorMercado_lotes
    ub_lotes = 3 .* valorMercado_lotes

    function f(x::AbstractVector, mu, sigma, valorInmobiliario_combis, C) 
        numCombis, numLotes = size(C)
        prob_vec = [Distributions.cdf(Distributions.LogNormal(mu[i], sigma[i]), x[i]) for i = 1:numLotes]

        utilEsp = sum(
            # expected utility for a single combination
            (valorInmobiliario_combis[k] - sum(C[k,i] * x[i] for i=1:numLotes)) * 
            prod(C[k,i] == 1 ? prob_vec[i] : 1 - prob_vec[i] for i=1:numLotes)
            
            # loop over all combinations
            for k=1:numCombis
        )

        return -utilEsp
    end

    function g(x::AbstractVector, mu, sigma, C, minProb) #Restricción para asegurar una probabilidad mínima de éxito
        numCombis, numLotes = size(C)
        prob_vec = [Distributions.cdf(Distributions.LogNormal(mu[i], sigma[i]), x[i]) for i = 1:numLotes]

        # calculate the sum of the product of probabilities for each combination
        probCombis = sum(
            # calculate the product of probabilities for a single combination
            prod(C[k,i] == 1 ? prob_vec[i] : 1 - prob_vec[i] for i=1:numLotes)
            
            # loop over all combinations
            for k=1:numCombis
        )

        return minProb - probCombis
    end


    m = NonconvexBayesian.Model()
    # set_objective!(m, x -> f(x, mu, sigma, C))
    set_objective!(m, x -> f(x, mu, sigma, valorInmobiliario_combis, C))
    addvar!(m, lb_lotes, ub_lotes)
    # add_ineq_constraint!(m, x -> g(x, mu, sigma, valorInmobiliario_combis, C))
    add_ineq_constraint!(m, x -> g(x, mu, sigma, C, minProb))

    alg = BayesOptAlg(IpoptAlg())
    options = BayesOptOptions(
        sub_options = IpoptOptions(print_level = 0), maxiter = 10, ctol = 1e-4,
        ninit = 2, initialize = true, postoptimize = false, fit_prior = true,
    )
    r = optimize(m, alg, lb_lotes, options = options);
    fopt = -r.minimum
    xopt = r.minimizer

    numCombis, numLotes = size(C)
    prob_lotes = [Distributions.cdf(Distributions.LogNormal(mu[i], sigma[i]), xopt[i]) for i = 1:numLotes]
    
    # Compute the probability of each combination
    prob_combis = [prod( C[k,i] == 1 ? prob_lotes[i] : 1 - prob_lotes[i] for i in 1:numLotes ) for k in 1:numCombis]

    return fopt, xopt, prob_lotes, prob_combis
end