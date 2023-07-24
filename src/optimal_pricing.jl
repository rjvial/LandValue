function optimal_pricing(C, valorMercado_lotes, superficie_lotes, valorInmobiliario_combis, prob_compraValorMercado, prob_compraValorInmobiliario, minProb)

    function prob_lote(x, valorMercado_lote, valorInmobiliario_lote, prob_compraValorMercado, prob_compraValorInmobiliario)
        # Entrega probabilidad de compra de un lote en función del precio ofertado, x.
        precio_lb = valorMercado_lote * (1 - prob_compraValorMercado) #precio mínimo lote = bajo este precio con certeza se rechaza compra-venta
        precio_ub = valorInmobiliario_lote / prob_compraValorInmobiliario #precio maximo lote = sobre este precio con certeza se acepta compra-venta
        return x < precio_lb ? 0 : (x > precio_ub ? 1 : (x - precio_lb) / (precio_ub - precio_lb))
    end
    function prob_lotes(x, valorMercado_lotes, valorInmobiliario_combis, prob_compraValorMercado, prob_compraValorInmobiliario, superficie_lotes, C)
        # Entrega la probabilidad de compra de cada uno de los lotes que participan en una matriz de combinación
        # C = matriz combinaciones
        superficie_combis = [sum(C[i,:] .* superficie_lotes) for i in eachindex(valorInmobiliario_combis)]
        valorInmobiliario_lotes = copy(valorMercado_lotes) # copia vector para tener un arreglo del tamaño de valorMercado_lotes
        for k in eachindex(valorMercado_lotes)
            valorInmobiliarioUnit_lote_k =  sum(valorInmobiliario_combis[C[:,k] .== 1]) / sum(superficie_combis[C[:,k] .== 1]) # valor inmobiliario por m2
            valorInmobiliario_lotes[k] = valorInmobiliarioUnit_lote_k * superficie_lotes[k]
        end
        return prob_lote.(x, valorMercado_lotes, valorInmobiliario_lotes, prob_compraValorMercado, prob_compraValorInmobiliario)[:]
    end
    
    function prob_combis(x, valorMercado_lotes, valorInmobiliario_combis, prob_compraValorMercado, prob_compraValorInmobiliario, superficie_lotes, C)
        # Entrega la probabilidad de compra conjunta de los lotes que forman cada combinación de la matriz de combinaciones
        numCombis, numLotes = size(C)
        probLotes = prob_lotes(x, valorMercado_lotes, valorInmobiliario_combis, prob_compraValorMercado, prob_compraValorInmobiliario, superficie_lotes, C)
        probCombis = [prod([C[k,i] == 1 ? probLotes[i] : 1 - probLotes[i] for i = 1:numLotes]) for k = 1:numCombis]
        return probCombis
    end
    
    function prob_compra(x, valorMercado_lotes, valorInmobiliario_combis, prob_compraValorMercado, prob_compraValorInmobiliario, superficie_lotes, C) 
        # Probabilidad de compra de alguna de las combinaciones
        probCombis = prob_combis(x, valorMercado_lotes, valorInmobiliario_combis, prob_compraValorMercado, prob_compraValorInmobiliario, superficie_lotes, C)
        probCompra = sum( probCombis )
        return probCompra
    end
    
    function util_esp(x, valorMercado_lotes, valorInmobiliario_combis, prob_compraValorMercado, prob_compraValorInmobiliario, superficie_lotes, C) 
        # Utilidad esperada 
        numCombis = size(C, 1)
        probCombis = prob_combis(x, valorMercado_lotes, valorInmobiliario_combis, prob_compraValorMercado, prob_compraValorInmobiliario, superficie_lotes, C)
        utilEsp = sum([ (valorInmobiliario_combis[k] - sum(C[k,:] .* x)) * probCombis[k] for k = 1:numCombis ])
        return utilEsp
    end
    
    function inv_esp(x, valorMercado_lotes, valorInmobiliario_combis, prob_compraValorMercado, prob_compraValorInmobiliario, superficie_lotes, C) 
        # Inversión esperada
        numCombis = size(C, 1)
        probCombis = prob_combis(x, valorMercado_lotes, valorInmobiliario_combis, prob_compraValorMercado, prob_compraValorInmobiliario, superficie_lotes, C)
        invEsp = sum( [sum(C[k,:] .* x) * probCombis[k] for k = 1:numCombis ])
        return invEsp
    end
    
    function f(x, valorMercado_lotes, valorInmobiliario_combis, prob_compraValorMercado, prob_compraValorInmobiliario, superficie_lotes, C, minProb) 
        # Función para ingresar a NOMAD la función objetivo y las restricciones del problema
        
        utilEsp = util_esp(x, valorMercado_lotes, valorInmobiliario_combis, prob_compraValorMercado, prob_compraValorInmobiliario, superficie_lotes, C)
    
        constraints = []
        probCompra = prob_compra(x, valorMercado_lotes, valorInmobiliario_combis, prob_compraValorMercado, prob_compraValorInmobiliario, superficie_lotes, C)
        constraints = push!(constraints, 10000*(minProb - probCompra))
    
        # Integración Función Objetivo con Restricciones
        bb_outputs = [-utilEsp; constraints]
        success = true
        count_eval = true
    
        return (success, count_eval, bb_outputs)
    end
    
    vec_sg = graphMod.getDisconnectedSubgraphs_v2(C)
    num_sg = length(vec_sg)

    x0 = valorMercado_lotes # Solución inicial
    xopt = copy(x0)
    util_vec = zeros(num_sg,1)
    inv_vec = zeros(num_sg,1)
    for i = 1:num_sg
    
        flag = [sum(C[:, vec_sg[i]], dims=2) .>= 1][1][:]
        C_i = C[flag .== 1, vec_sg[i]]
    
        valorMercado_lotes_i = valorMercado_lotes[vec_sg[i]]
        valorInmobiliario_combis_i = valorInmobiliario_combis[flag]
    
        superficie_lotes_i = superficie_lotes[vec_sg[i]]
    
        lb_lotes = valorMercado_lotes_i
        ub_lotes = 3 .* valorMercado_lotes_i
    
        obj_nomad = x -> f(x, valorMercado_lotes_i, valorInmobiliario_combis_i, prob_compraValorMercado, prob_compraValorInmobiliario, superficie_lotes_i, C_i, minProb)
    
        numCombis = length(valorInmobiliario_combis_i)
        num_inputs = length(lb_lotes); # Number of inputs of the blackbox. Is required to be > 0
        num_outputs = 1 + 1 ; # Number of outputs of the blackbox. Is required to be > 0
        output_types = vcat(["OBJ"], ["PB" for i in 1:(num_outputs-1)]); # "OBJ" objective value to be minimized, "PB" progressive barrier constraint, "EB" extreme barrier constraint
        input_types = vcat(["R" for i in 1:num_inputs]); # A vector containing String objects that define the types of inputs to be given to eval_bb (the order is important). "R" Real/Continuous, "B" Binary,"I" Integer
    
        p = NOMAD.NomadProblem(num_inputs, num_outputs, output_types, obj_nomad; 
                        input_types = input_types, 
                        lower_bound = lb_lotes, 
                        upper_bound = ub_lotes)
    
        p.options.display_degree = 0 
        #p.options.max_bb_eval = MaxSteps; # Fix some options
    
        result = NOMAD.solve(p, x0[vec_sg[i]])
    
        xopt[vec_sg[i]] = result.x_best_feas
    
        util_vec[i] = util_esp(xopt[vec_sg[i]], valorMercado_lotes_i, valorInmobiliario_combis_i, prob_compraValorMercado, prob_compraValorInmobiliario, superficie_lotes_i, C_i)
        inv_vec[i] = inv_esp(xopt[vec_sg[i]], valorMercado_lotes_i, valorInmobiliario_combis_i, prob_compraValorMercado, prob_compraValorInmobiliario, superficie_lotes_i, C_i)
    
    end
    
    return xopt, sum(util_vec), sum(inv_vec)

end

