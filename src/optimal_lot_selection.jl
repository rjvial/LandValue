function optimal_lot_selection(C, df)

    numCombi, numPredios = size(C)

    M = 100000

    idCombi = collect(1:numCombi)
    m = JuMP.Model(Cbc.Optimizer)
    JuMP.set_optimizer_attribute(m, "ratioGap", 0.001)
    JuMP.set_optimizer_attribute(m, "logLevel", 0)
    JuMP.set_time_limit_sec(m, 1*60.0)

    largo_Ck_cero = [length(idCombi[C[:, k].==0]) for k = 1:numPredios] # Vector que indica para cada k el numero de combis donde el predio k NO participa
    set_predios = collect(1:numPredios)

    @variables(m, begin
        x[i in set_predios], Bin # x_i = 1 si se selecciona el predio i
        z[k in set_predios[largo_Ck_cero.>=1], j in idCombi[C[:, k].==0]], Bin # z_kj = 1 si se selecciona el combi j que exluye el predio k
    end)

    # debe haber al menos un predio x activo en cada combi
    @constraint(m, sum(x) .>= 1) # debe haber al menos un predio x activo 

    for k in set_predios # Para cada predio k,
        if largo_Ck_cero[k] >= 1  # si existe uno o más combi's en los que el predio k NO participa, 
            @constraint(m, sum(z[k, idCombi[C[:, k].==0]]) >= 1) # al menos uno de estos combi's que excluyen al predio k debe ser seleccionado
            for j in idCombi[C[:, k].==0] # Para cada combi j que excluye al predio k,
                @constraint(m, sum(C[j, :] .* x) + M * (x[k] + (1 - z[k, j])) >= sum(x)) # los predios x seleccionados deben estar presentes simultáneamente en cada uno de estos combi's 
                # Si x_k = 0 y z_kj = 1 los x's no presentes en el combi j deben tener valor igual a 0
                # En caso contrario (i.e. x_k = 1 || x_k = 0 & z_kj = 0) esta restriccion no impone ningun límite a los x's
            end
        else  # si en cambio, el predio k participa en todos los combi's disponibles, 
            @constraint(m, x[k] == 1) # entonces se debe seleccionar el predio k, x_k = 1
        end
    end

    @objective(m, Min, sum(x) + sum(x .* df.sup_terreno) / 10^5) # Se busca minimizar el número de predios seleccionados y la suma de las superficies de los predios seleccionados  
    JuMP.optimize!(m)

    if termination_status(m) == MOI.OPTIMAL
        return JuMP.value.(x.data)
    else
        return zeros(Int, numPredios)
    end

    
end