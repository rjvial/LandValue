function optimal_pricing(C, valorMercado_lotes, superficie_lotes, valorInmobiliario_combis, delta_porcentual, minProb)

    function valorInmob_lotes(valorMercado_lotes, superficie_lotes, valorInmobiliario_combis, C)
        superficie_combis = [sum(C[k,:] .* superficie_lotes) for k in eachindex(valorInmobiliario_combis)]
        valorInmobiliario_lotes = zeros(size(valorMercado_lotes)) # genera vector del tamaño de valorMercado_lotes
        for i in eachindex(valorMercado_lotes)
            valorInmobiliarioUnit_lote_i =  sum(valorInmobiliario_combis[C[:,i] .== 1]) / sum(superficie_combis[C[:,i] .== 1]) # valor inmobiliario promedio por m2
            valorInmobiliario_lotes[i] = valorInmobiliarioUnit_lote_i * superficie_lotes[i]
        end
        return valorInmobiliario_lotes
    end
    function prob_lote(x, valorMercado_lote, valorInmobiliario_lote, delta_porcentual)
        # Entrega probabilidad de compra de un lote en función del precio ofertado, x.
        precio_lb = valorMercado_lote * (1 - delta_porcentual) #precio mínimo lote = bajo este precio con certeza se rechaza compra-venta
        precio_ub = valorInmobiliario_lote * (1 + delta_porcentual) #precio maximo lote = sobre este precio con certeza se acepta compra-venta
        # return x < precio_lb ? 0 : (x > precio_ub ? 1 : (x - precio_lb) / (precio_ub - precio_lb))
        return (x - precio_lb) / (precio_ub - precio_lb)
    end
    function prob_lotes(x_vec, valorMercado_lotes, valorInmobiliario_combis, delta_porcentual, superficie_lotes, C)
        # Entrega la probabilidad de compra de cada uno de los lotes que participan en una matriz de combinación
        # C = matriz combinaciones
        valorInmobiliario_lotes = valorInmob_lotes(valorMercado_lotes, superficie_lotes, valorInmobiliario_combis, C)
        return prob_lote.(x_vec, valorMercado_lotes, valorInmobiliario_lotes, delta_porcentual)[:]
    end
    
    function prob_combis(x_vec, valorMercado_lotes, valorInmobiliario_combis, delta_porcentual, superficie_lotes, C)
        # Entrega la probabilidad de compra conjunta de los lotes que forman cada combinación de la matriz de combinaciones
        numCombis, numLotes = size(C)
        probLotes = prob_lotes(x_vec, valorMercado_lotes, valorInmobiliario_combis, delta_porcentual, superficie_lotes, C)
        probCombis = [prod([C[k,i] == 1 ? probLotes[i] : 1 - probLotes[i] for i = 1:numLotes]) for k = 1:numCombis]
        return probCombis
    end
    
    function prob_compra(x_vec, valorMercado_lotes, valorInmobiliario_combis, delta_porcentual, superficie_lotes, C) 
        # Probabilidad de compra de alguna de las combinaciones
        probCombis = prob_combis(x_vec, valorMercado_lotes, valorInmobiliario_combis, delta_porcentual, superficie_lotes, C)
        probCompra = sum( probCombis )
        return probCompra
    end
    
    function util_esp(x_vec, valorMercado_lotes, valorInmobiliario_combis, delta_porcentual, superficie_lotes, C) 
        # Utilidad esperada 
        numCombis = size(C, 1)
        probCombis = prob_combis(x_vec, valorMercado_lotes, valorInmobiliario_combis, delta_porcentual, superficie_lotes, C)
        utilEsp = sum([ (valorInmobiliario_combis[k] - sum(C[k,:] .* x_vec)) * probCombis[k] for k = 1:numCombis ])
        return utilEsp
    end
    
    function inv_esp(x_vec, valorMercado_lotes, valorInmobiliario_combis, delta_porcentual, superficie_lotes, C) 
        # Inversión esperada
        numCombis = size(C, 1)
        probCombis = prob_combis(x_vec, valorMercado_lotes, valorInmobiliario_combis, delta_porcentual, superficie_lotes, C)
        invEsp = sum( [sum(C[k,:] .* x_vec) * probCombis[k] for k = 1:numCombis ])
        return invEsp
    end
    
    function f(x_vec, valorMercado_lotes, valorInmobiliario_combis, delta_porcentual, superficie_lotes, C, minProb) 
        # Función para ingresar a NOMAD la función objetivo y las restricciones del problema
        
        utilEsp = util_esp(x_vec, valorMercado_lotes, valorInmobiliario_combis, delta_porcentual, superficie_lotes, C)
    
        return -utilEsp
    end
    
    vec_sg = graphMod.getDisconnectedSubgraphs_v2(C)
    num_sg = length(vec_sg)

    xopt = copy(valorMercado_lotes)
    util_vec = zeros(num_sg,1)
    inv_vec = zeros(num_sg,1)
    for i = 1:num_sg
    
        flag = [sum(C[:, vec_sg[i]], dims=2) .>= 1][1][:]
        C_i = C[flag .== 1, vec_sg[i]]
    
        valorInmobiliario_combis_i = valorInmobiliario_combis[flag]

        valorMercado_lotes_i = valorMercado_lotes[vec_sg[i]]
        superficie_lotes_i = superficie_lotes[vec_sg[i]]
        valorInmobiliario_lotes_i = valorInmob_lotes(valorMercado_lotes_i, superficie_lotes_i, valorInmobiliario_combis_i, C_i)

        x0_i = (valorMercado_lotes_i .+ valorInmobiliario_lotes_i) * .5 #1.5 (23) # Solución inicial

        lb_lotes = valorMercado_lotes_i * (1 - delta_porcentual)  #precio mínimo lote = bajo este precio con certeza se rechaza compra-venta
        ub_lotes = valorInmobiliario_lotes_i * (1 + delta_porcentual)
    
        obj_fun = x -> f(x, valorMercado_lotes_i, valorInmobiliario_combis_i, delta_porcentual, superficie_lotes_i, C_i, minProb)
        result = optimize(obj_fun, lb_lotes, ub_lotes, x0_i, Fminbox(BFGS()); autodiff = :forward)

        xopt[vec_sg[i]] = Optim.minimizer(result)
    
        util_vec[i] = -Optim.minimum(result)
    
    end
    
    return xopt, sum(util_vec), xopt ./ superficie_lotes

end

