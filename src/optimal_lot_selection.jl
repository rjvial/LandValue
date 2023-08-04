function optimal_lot_selection(C)

    numCombi, numLotes = size(C)

    M = 100000

    idCombi = collect(1:numCombi)
    m = JuMP.Model(Cbc.Optimizer)
    JuMP.set_optimizer_attribute(m, "ratioGap", 0.001)
    set_optimizer_attribute(m, "logLevel", 0)

    largo_Ck = [length(idCombi[C[:, k].==0]) for k = 1:numLotes]
    set_lotes = collect(1:numLotes)

    @variables(m, begin
        x[i in set_lotes], Bin # xi = 1 si se selecciona el lote i
        z[k in set_lotes[largo_Ck.>=1], j in idCombi[C[:, k].==0]], Bin # zkj = 1 si la combi j del subconjunto de combinaciones que exluyen el lote k es seleccionado
    end)

    for j in idCombi # Para cada combi j,
        @constraint(m, sum(C[j, :] .* x) .>= 1) # debe haber al menos un x activo 
    end
    for k in set_lotes # Para cada lote k,
        if largo_Ck[k] >= 1  # si existen combi's en las que el lote k no participa, 
            @constraint(m, sum(z[k, idCombi[C[:, k].==0]]) >= 1) # la suma de las combis seleccionados que excluyen el lote k debe ser mayor a 1
            for j in idCombi[C[:, k].==0] # para cada combi j que excluye al lote k,
                @constraint(m, sum(C[j, :] .* x) + M * (x[k] + (1 - z[k, j])) >= sum(x)) #los lotes x seleccionados deben estar presentes simultáneamente en al menos una de estas combi's 
            end
        else  # si en cambio, el lote k participa en todas las combi's disponibles, 
            @constraint(m, x[k] == 1) # entonces se debe seleccionar xk
        end
    end

    @objective(m, Min, sum(x))
    JuMP.optimize!(m)

    return JuMP.value.(x.data)
    
end