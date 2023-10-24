function optim_bbo(fo_bbo, lb_bbo, ub_bbo, maxSteps, numIter)

    # Repetición de optimizaciones bb para encontrar buena solución
    lb_bbo[1] = ub_bbo[1]
    sr = [(lb_bbo[i], ub_bbo[i]) for i in eachindex(lb_bbo)] # Search Region    
    
    fopt = 10000
    xopt = []
    for i=1:numIter
        # display(i)
        result = BlackBoxOptim.bboptimize(fo_bbo; SearchRange = sr, NumDimensions = length(lb_bbo),
                    Method = :adaptive_de_rand_1_bin_radiuslimited, MaxSteps = maxSteps,
                    TraceMode = :silent) 
        f_i = BlackBoxOptim.best_fitness(result)
        if f_i < fopt
            fopt = f_i
            xopt = BlackBoxOptim.best_candidate(result)
        end
    end

    return xopt, fopt

end