function optimal_pricing(C, valorMercado_lotes, superficie_lotes, valorInmobiliario_combis, delta_lotes, delta_combis, delta_opt_lotes, delta_opt_combis)

    function valor_inmob_lotes(valorMercado_lotes, superficie_lotes, valorInmobiliario_combis, C)
        superficie_combis = C * superficie_lotes
        valorInmobiliario_lotes = zeros(size(valorMercado_lotes)) # genera vector del tamaño de valorMercado_lotes
        for i in eachindex(valorMercado_lotes)
            valorInmobiliarioUnit_lote_i =  sum(valorInmobiliario_combis[C[:,i] .== 1]) / sum(superficie_combis[C[:,i] .== 1]) # valor inmobiliario promedio por m2
            valorInmobiliario_lotes[i] = valorInmobiliarioUnit_lote_i * superficie_lotes[i]
        end
        return valorInmobiliario_lotes
    end

    function prob_compra_lotes(p_lotes, lb_lotes, ub_lotes)
        # Entrega la probabilidad de compra de cada uno de los lotes que participan en una matriz de combinación
        return (p_lotes .- lb_lotes) ./ (ub_lotes .- lb_lotes)
    end
    function prob_compra_combis(p_lotes, lb_lotes, ub_lotes, C)
        # Entrega la probabilidad de compra conjunta de los lotes que forman cada combinación de la matriz de combinaciones
        numCombis, numLotes = size(C)
        probLotes = prob_compra_lotes(p_lotes, lb_lotes, ub_lotes)
        probCombis = [prod( [ C[k,i] * probLotes[i] + (1 - C[k,i]) * (1 - probLotes[i]) for i = 1:numLotes] ) for k = 1:numCombis]
        return probCombis
    end

    function prob_venta_combis(p_combis, lb_combis, ub_combis)
        return (ub_combis .- p_combis) ./ (ub_combis .- lb_combis)
    end

    function utilidad_esperada(p, lb_lotes, ub_lotes, lb_combis, ub_combis, valorMercado_lotes, C) 
        num_lotes = length(lb_lotes)
        p_lotes = p[1:num_lotes]
        p_combis = p[num_lotes+1:end]
        probCompraCombis = prob_compra_combis(p_lotes, lb_lotes, ub_lotes, C)
        probVentaCombis = prob_venta_combis(p_combis, lb_combis, ub_combis)
        utilEsp = ( (p_combis .- C*p_lotes) .* probVentaCombis + 
                    C*(valorMercado_lotes .- p_lotes) .* (1 .- probVentaCombis) )' * probCompraCombis
        return -utilEsp
    end
    
    vec_sg = graphMod.getDisconnectedSubgraphs_v2(C)
    num_sg = length(vec_sg)

    popt = []
    util = []
    # probCombis = zeros(num_sg,1)
    for i = 1:num_sg
    
        flag = [sum(C[:, vec_sg[i]], dims=2) .>= 1][1][:]
        C_i = C[flag .== 1, vec_sg[i]]
    
        valorInmobiliario_combis_i = Float64.(valorInmobiliario_combis[flag])

        valorMercado_lotes_i = Float64.(valorMercado_lotes[vec_sg[i]])
        superficie_lotes_i = Float64.(superficie_lotes[vec_sg[i]])
        valorInmobiliario_lotes_i = valor_inmob_lotes(valorMercado_lotes_i, superficie_lotes_i, valorInmobiliario_combis_i, C_i)

        lb_lotes = min.(valorMercado_lotes_i, valorInmobiliario_lotes_i) * (1 - delta_lotes)  #precio mínimo lote = bajo este precio con certeza se rechaza compra-venta
        ub_lotes = max.(valorMercado_lotes_i, valorInmobiliario_lotes_i) * (1 + delta_lotes)
        lb_combis = valorInmobiliario_combis_i * (1 - delta_combis)
        ub_combis = valorInmobiliario_combis_i * (1 + delta_combis)

        obj_fun = p -> utilidad_esperada(p, lb_lotes, ub_lotes, lb_combis, ub_combis, valorMercado_lotes_i, C_i)

        lb_lotes_opt = valorMercado_lotes_i * (1 - delta_opt_lotes)
        lb_combis_opt = valorInmobiliario_combis_i * (1 - delta_opt_combis)
        lb_opt = [lb_lotes_opt; lb_combis_opt]
        ub_lotes_opt = valorInmobiliario_lotes_i * (1 + delta_opt_lotes)
        ub_combis_opt = valorInmobiliario_combis_i * (1 + delta_opt_combis)
        ub_opt = [ub_lotes_opt; ub_combis_opt]

        p0_lotes = (lb_lotes .+ ub_lotes) * .5 #1.5 (23) # Solución inicial
        p0_combis = (lb_combis .+ ub_combis) * .5 #1.5 (23) # Solución inicial
        p0 = [p0_lotes; p0_combis]

        result = optimize(obj_fun, lb_opt, ub_opt, p0, Fminbox(BFGS()); autodiff = :forward)

        push!(popt, Optim.minimizer(result))
        push!(util, -Optim.minimum(result))
    end
    
    return popt, sum(util)

end

