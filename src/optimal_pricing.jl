function optimal_pricing(C, valorMercado_lotes, superficie_lotes, valorInmobiliario_combis, delta_porcentual)

    function valorInmob_lotes(valorMercado_lotes, superficie_lotes, valorInmobiliario_combis, C)
        superficie_combis = C * superficie_lotes
        valorInmobiliario_lotes = zeros(size(valorMercado_lotes)) # genera vector del tamaño de valorMercado_lotes
        for i in eachindex(valorMercado_lotes)
            valorInmobiliarioUnit_lote_i =  sum(valorInmobiliario_combis[C[:,i] .== 1]) / sum(superficie_combis[C[:,i] .== 1]) # valor inmobiliario promedio por m2
            valorInmobiliario_lotes[i] = valorInmobiliarioUnit_lote_i * superficie_lotes[i]
        end
        return valorInmobiliario_lotes
    end

    function prob_lotes(x_vec, lb_lotes, ub_lotes)
        # Entrega la probabilidad de compra de cada uno de los lotes que participan en una matriz de combinación
        return (x_vec .- lb_lotes) ./ (ub_lotes .- lb_lotes)
    end
    function prob_combis(x_vec, lb_lotes, ub_lotes, C)
        # Entrega la probabilidad de compra conjunta de los lotes que forman cada combinación de la matriz de combinaciones
        numCombis, numLotes = size(C)
        probLotes = prob_lotes(x_vec, lb_lotes, ub_lotes)
        probCombis = [prod( [ C[k,i] * probLotes[i] + (1 - C[k,i]) * (1 - probLotes[i]) for i = 1:numLotes] ) for k = 1:numCombis]
        return probCombis
    end

    function f(x_vec, lb_lotes, ub_lotes, valorInmobiliario_combis, C) 
        probCombis = prob_combis(x_vec, lb_lotes, ub_lotes, C)
        utilEsp = (valorInmobiliario_combis .- C * x_vec)' * probCombis
        return -utilEsp
    end
    
    vec_sg = graphMod.getDisconnectedSubgraphs_v2(C)
    num_sg = length(vec_sg)

    xopt = Float64.(copy(valorMercado_lotes))
    util_vec = zeros(num_sg,1)
    for i = 1:num_sg
    
        flag = [sum(C[:, vec_sg[i]], dims=2) .>= 1][1][:]
        C_i = C[flag .== 1, vec_sg[i]]
    
        valorInmobiliario_combis_i = Float64.(valorInmobiliario_combis[flag])

        valorMercado_lotes_i = Float64.(valorMercado_lotes[vec_sg[i]])
        superficie_lotes_i = Float64.(superficie_lotes[vec_sg[i]])
        valorInmobiliario_lotes_i = valorInmob_lotes(valorMercado_lotes_i, superficie_lotes_i, valorInmobiliario_combis_i, C_i)

        x0_i = (valorMercado_lotes_i .+ valorInmobiliario_lotes_i) * .5 #1.5 (23) # Solución inicial

        lb_lotes = valorMercado_lotes_i * (1 - delta_porcentual)  #precio mínimo lote = bajo este precio con certeza se rechaza compra-venta
        ub_lotes = valorInmobiliario_lotes_i * (1 + delta_porcentual)
    
        obj_fun = x -> f(x, lb_lotes, ub_lotes, valorInmobiliario_combis_i, C_i)
        result = optimize(obj_fun, lb_lotes, ub_lotes, x0_i, Fminbox(BFGS()); autodiff = :forward)

        xopt[vec_sg[i]] = Optim.minimizer(result)
    
        util_vec[i] = -Optim.minimum(result)    
    end
    
    return xopt, sum(util_vec), xopt ./ superficie_lotes

end

