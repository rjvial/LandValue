using LandValue, JuMP, Cbc

M = 100000

# Ad = [0 1 1 0 0 0 0;
#       1 0 1 0 0 0 0;
#       1 1 0 1 0 0 0;
#       0 0 1 0 1 1 0;
#       0 0 0 1 0 0 1;
#       0 0 0 1 0 0 1;
#       0 0 0 0 1 1 0]
# C = graphMod.node_combis(Ad, flag_mat = true)
# graphMod.graphPlot(Ad)

# C = [ 1  1  1  1  1;
# 1  1  1  1  0;
# 1  1  1  0  0;
# 1  1  0  0  0;
# 1  0  1  1  1;
# 1  0  0  1  1;
# 1  0  0  0  1;
# 1  1  0  1  1;
# 1  1  0  0  1;
# 0  1  1  1  1;
# 0  1  1  1  0;
# 0  1  1  0  0;
# 1  1  1  0  1;
# 0  0  1  1  1;
# 0  0  1  1  0;
# 0  0  0  1  1]

# C = [1 1 0 0 0;
#      0 1 1 0 0;
#      0 0 1 1 0;
#      0 0 0 1 1;
#      1 1 1 0 0;
#      0 1 1 1 0;
#      0 0 1 1 1;
#      1 1 1 1 0;
#      0 1 1 1 1;
#      1 1 1 1 1]

# C = [1 1 0;
#      0 1 1;
#      1 1 1]

# C = [1 1 0 0; 0 1 1 0; 0 1 0 1; 1 1 1 0; 1 1 0 1; 0 1 1 1] #El problema con este es que no tiene 0s en la columna 2
# C = [1 1 0 0; 0 1 1 0; 1 0 0 1; 1 1 0 1; 1 1 1 0; 1 1 1 1]

numCombi, numLotes = size(C) 

idCombi = collect(1:numCombi)
m = JuMP.Model(Cbc.Optimizer)
JuMP.set_optimizer_attribute(m, "ratioGap", 0.001)
set_optimizer_attribute(m, "logLevel", 0)

largo_Ck = [length(idCombi[C[:,k] .== 0]) for k=1:numLotes]

if minimum(largo_Ck) >= 1
    @variables(m, begin
            x[i = 1:numLotes], Bin
            z[k = 1:numLotes, j in idCombi[C[:,k] .== 0]], Bin
        end)

    @constraints(m, begin
        C * x .>= 1
        [k = 1:numLotes, j in idCombi[C[:,k] .== 0]], sum(C[j,:] .* x) + M*(x[k] + (1 - z[k,j])) >= sum(x)
        [k = 1:numLotes], sum(z[k, idCombi[C[:,k] .== 0]]) >= 1  
    end)
else
    @variables(m, begin
        x[i = 1:numLotes], Bin
    end)

    @constraints(m, begin
        C * x .>= 1
    end)

end


@objective(m, Min, sum(x) )
JuMP.optimize!(m)

display(termination_status(m))

display(JuMP.value.(x))
# display(JuMP.value.(z))