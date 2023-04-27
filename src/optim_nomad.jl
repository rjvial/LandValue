function optim_nomad(fo_nomad, num_penalizaciones, lb, ub, MaxSteps, initSol)

    num_inputs = length(lb); # Number of inputs of the blackbox. Is required to be > 0
    num_outputs = num_penalizaciones + 1; # Number of outputs of the blackbox. Is required to be > 0
    output_types = vcat(["OBJ"], ["PB" for i in 1:num_penalizaciones]); # "OBJ" objective value to be minimized, "PB" progressive barrier constraint, "EB" extreme barrier constraint
    input_types = vcat(["I"], ["R" for i in 1:num_inputs-1]); # A vector containing String objects that define the types of inputs to be given to eval_bb (the order is important). "R" Real/Continuous, "B" Binary,"I" Integer
    #granularity = [0. for i in 1:num_inputs]; # 0 for real variables, 1 for integer and binary ones.
    #min_mesh_size = [0.1 for i in 1:num_inputs];
    lower_bound = lb;
    upper_bound = ub;
    initial_mesh_size = vcat([1.], [0.1 for i in 1:num_inputs-1])
    p = NOMAD.NomadProblem(num_inputs, num_outputs, output_types, fo_nomad; 
                    input_types = input_types, 
                    #granularity = granularity,
                    #min_mesh_size = min_mesh_size,
                    lower_bound = lower_bound, 
                    upper_bound = upper_bound)


    # Nomad options:
    # display_degree - Integer between 0 and 3 that sets the level of display.
    # display_all_eval - If false, only evaluations that allow to improve the current state are displayed (false by default)
    # display_infeasible - If true, display best infeasible values reached by Nomad until the current step (false by default)
    # display_unsuccessful - If true, display evaluations that are unsuccessful (false by default)
    # max_bb_eval - Maximum of calls to eval_bb allowed. Must be positive (20000 by default)
    # opportunistic_eval - If true, the algorithm performs an opportunistic strategy at each iteration (true by default)
    # use_cache - If true, the algorithm only evaluates one time a given input. Avoids to recalculate a blackbox value if this last one has already be computed (true by default)
    # lh_search - LH search parameters. lh_search[1] is the lh_search_init parameter, i.e. the number of initial search points performed with Latin-Hypercube method (0 by default)
    #                                   lh_search[2] is the lh_search_iter parameter, i.e. the number of search points performed at each iteration with Latin-Hypercube method (0 by default)
    # speculative_search - If true, the algorithm executes a speculative search strategy at each iteration (true by default)
    # nm_search - If true, the algorithm executes a speculative search strategy at each iteration (true by default)

    p.options.display_degree = 0 #0;
    p.options.max_bb_eval = MaxSteps; # Fix some options

    # solve problem starting from the point
    result = NOMAD.solve(p, initSol);

    fopt = 99999.
    xopt = initSol
    try
        fopt = result.bbo_best_feas[1]
        xopt = result.x_best_feas
    catch
        fopt = 99999.
        xopt = initSol
    end

    return xopt, fopt



end

