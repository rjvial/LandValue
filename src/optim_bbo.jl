function optim_bbo(fo_bbo, lb_bbo, ub_bbo)

    # Repetición de optimizaciones bb para encontrar buena solución
    lb_bbo[1] = ub_bbo[1]
    sr = [(lb_bbo[i], ub_bbo[i]) for i in eachindex(lb_bbo)] # Search Region 

    fopt = 10000
    xopt = []
    maxSteps = 20000
    for i=1:20
        result = BlackBoxOptim.bboptimize(fo_bbo; SearchRange = sr, NumDimensions = length(lb_bbo),
                    Method = :adaptive_de_rand_1_bin_radiuslimited, MaxSteps = maxSteps,
                    TraceMode = :silent) 
        f_i = BlackBoxOptim.best_fitness(result)
        if f_i < fopt
            fopt = f_i
            xopt = BlackBoxOptim.best_candidate(result)
        end
    end

    # # Optimización sobre mejor sector encontrado en etapa anterior  
    # sr = [(xopt[i]-0.1*abs(xopt[i]), xopt[i]+0.1*abs(xopt[i])) for i=1:length(lb)] # Search Region
    # sr[end-2] = (lb[end-2], ub_bbo[end-2])
    # sr[end-1] = (lb[end-1], ub_bbo[end-1])
    # sr[end] = (lb[end], ub_bbo[end])

    # # sr = [(lb[i], ub[i]) for i in eachindex(lb)]
    # maxSteps = 30000
    # result = BlackBoxOptim.bboptimize(fo_bbo; SearchRange = sr, NumDimensions = length(lb),
    #         Method = :adaptive_de_rand_1_bin_radiuslimited, MaxSteps = maxSteps,
    #         TraceMode = :silent) 
    # fopt = BlackBoxOptim.best_fitness(result)
    # xopt = BlackBoxOptim.best_candidate(result)

    return xopt, fopt

end