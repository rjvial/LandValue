function optimal_lot_selection(C)

    numCombi, numLotes = size(C)

    M = 100000

    idCombi = collect(1:numCombi)
    m = JuMP.Model(Cbc.Optimizer)
    JuMP.set_optimizer_attribute(m, "ratioGap", 0.001)
    set_optimizer_attribute(m, "logLevel", 0)

    largo_Ck = [length(idCombi[C[:, k].==0]) for k = 1:numLotes]

    if minimum(largo_Ck) >= 1
        @variables(m, begin
            x[i=1:numLotes], Bin
            z[k=1:numLotes, j in idCombi[C[:, k].==0]], Bin
        end)

        @constraints(m, begin
            C * x .>= 1
            [k = 1:numLotes, j in idCombi[C[:, k].==0]], sum(C[j, :] .* x) + M * (x[k] + (1 - z[k, j])) >= sum(x)
            [k = 1:numLotes], sum(z[k, idCombi[C[:, k].==0]]) >= 1
        end)
    else
        @variables(m, begin
            x[i=1:numLotes], Bin
        end)

        @constraints(m, begin
            C * x .>= 1
        end)

    end


    @objective(m, Min, sum(x))
    JuMP.optimize!(m)

    return JuMP.value.(x)
end