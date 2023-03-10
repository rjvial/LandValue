function optim_bbo(fo_bbo, lb, ub)

    # Repetición de optimizaciones bb para encontrar buena solución
    sr = [(lb[i], ub[i]) for i in eachindex(lb)] # Search Region    
    fopt = 10000
    xopt = []
    maxSteps = 2*13500
    for i=1:10
        result = BlackBoxOptim.bboptimize(fo_bbo; SearchRange = sr, NumDimensions = length(lb),
                    Method = :adaptive_de_rand_1_bin_radiuslimited, MaxSteps = maxSteps,
                    TraceMode = :silent) 
        f_i = BlackBoxOptim.best_fitness(result)
        if f_i < fopt
            fopt = f_i
            xopt = BlackBoxOptim.best_candidate(result)
        end
    end

    # Optimización sobre mejor sector encontrado en etapa anterior  
    sr = [(xopt[i]-0.05*abs(xopt[i]), xopt[i]+0.05*abs(xopt[i])) for i=1:length(lb)] # Search Region
    sr[end] = (lb[end], lb[end])
    sr = [(lb[i], ub[i]) for i in eachindex(lb)]
    maxSteps = 30000
    result = BlackBoxOptim.bboptimize(fo_bbo; SearchRange = sr, NumDimensions = length(lb),
            Method = :adaptive_de_rand_1_bin_radiuslimited, MaxSteps = maxSteps,
            TraceMode = :silent) 
    fopt = BlackBoxOptim.best_fitness(result)
    xopt = BlackBoxOptim.best_candidate(result)

    return xopt, fopt

end