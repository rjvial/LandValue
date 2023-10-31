function optimal_lot_selection(C)

    numCombi, numLotes = size(C)

    M = 100000

    idCombi = collect(1:numCombi)
    m = JuMP.Model(Cbc.Optimizer)
    JuMP.set_optimizer_attribute(m, "ratioGap", 0.001)
    set_optimizer_attribute(m, "logLevel", 0)

    largo_Ck_cero = [length(idCombi[C[:, k].==0]) for k = 1:numLotes] # numero de combis donde el lote k NO participa
    set_lotes = collect(1:numLotes)

    @variables(m, begin
        x[i in set_lotes], Bin # xi = 1 si se selecciona el lote i
        z[k in set_lotes[largo_Ck_cero.>=1], j in idCombi[C[:, k].==0]], Bin # zkj = 1 si la combi j, que exluye al lote k, es seleccionado
    end)

    # debe haber al menos un x activo en cada combi
    for j in idCombi # Para cada combi j,
        @constraint(m, sum(C[j, :] .* x) .>= 1) # debe haber al menos un x activo 
    end

    # @constraint(m, C * x .>= 1) # debe haber al menos un x activo en cada combi
    for k in set_lotes # Para cada lote k,
        if largo_Ck_cero[k] >= 1  # si existe una o más combi's en las que el lote k no participa, 
            @constraint(m, sum(z[k, idCombi[C[:, k].==0]]) >= 1) # al menos una de estas combi's que excluyen al lote k debe ser seleccionada
            for j in idCombi[C[:, k].==0] # Para cada combi j que excluye al lote k,
                @constraint(m, sum(C[j, :] .* x) + M * (x[k] + (1 - z[k, j])) >= sum(x)) #los lotes x seleccionados deben estar presentes simultáneamente en al menos una de estas combi's 
            end
            # Si xk = 1, esta restriccion no impone ningún limite a los x's
            # Si xk = 0 y zkj = 0, esta restriccion no impone ningún limite a los x's
            # Si xk = 0 y zkj = 1 los x seleccionados deben estar en la combi j
        else  # si en cambio, el lote k participa en todas las combi's disponibles, 
            @constraint(m, x[k] == 1) # entonces se debe seleccionar el lote xk
        end
    end

    @objective(m, Min, sum(x))
    JuMP.optimize!(m)

    return JuMP.value.(x.data)
    
end