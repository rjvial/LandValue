using Nonconvex
Nonconvex.@load NOMAD

function bb(x)
    a = x[1]
    b = x[2]
    return exp(sin(50 * a)) + sin(60 * exp(b)) + sin(70 * sin(a)) + sin(sin(80*b)) - sin(10 * (a+b)) + 0.25 * (a^2 + b^2)
end

g(x) = x[1] + x[2]

model = Model()
set_objective!(model, bb)
addvar!(model, [-10., -10.], [10.0, 10.0])
add_ineq_constraint!(model, x -> g(x))

alg = NOMADAlg()
options = NOMADOptions(display_degree = 0)
result = optimize(model, alg, [-1.,0.], options = options)
result.minimum
result.minimizer
