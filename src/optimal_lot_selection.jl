function optimal_lot_selection(C, df; tipo_opt="sin_control")
    numCombi, numPredios = size(C)

    model = JuMP.Model(Cbc.Optimizer)
    JuMP.set_optimizer_attribute(model, "ratioGap", 0.001)
    JuMP.set_optimizer_attribute(model, "logLevel", 0)
    JuMP.set_time_limit_sec(model, 60.0)

    combi_ids  = 1:numCombi
    predio_ids = 1:numPredios

    @variable(model, x[k in predio_ids], Bin)
    @variable(model, y[j in combi_ids], Bin)

    for k in predio_ids
        if all(C[:,k] .== 1)
            @constraint(model, x[k] == 1)
        end
    end

    @constraint(model, sum(y) >= 1)

    @constraints(model, begin
        [j in combi_ids, k in predio_ids; C[j,k] == 0], y[j] + x[k] <= 1
    end)

    if tipo_opt == "con_control"
        @constraint(model, [j in combi_ids], sum(C[j,:] .* x) >= 1)
    else
        @constraint(model, sum(x) >= 1)
    end

    @objective(model, Min, sum(x) + sum(df.sup_terreno_sii .* x) / 1e5)
    optimize!(model)

    return termination_status(model) == MOI.OPTIMAL ?
        Int.(value.(x) .>= 0.5) :
        zeros(Int, numPredios)
end
