using Nonconvex, NonconvexIpopt
Nonconvex.@load BayesOpt

f(x) = sqrt(x[2])
g(x, a, b) = (a*x[1] + b)^3 - x[2]

model = Model()
set_objective!(model, f)
addvar!(model, [1e-4, 1e-4], [10.0, 10.0])
add_ineq_constraint!(model, x -> g(x, 2, 0))
add_ineq_constraint!(model, x -> g(x, -1, 1))

alg = BayesOptAlg(IpoptAlg())
options = BayesOptOptions(
    sub_options = IpoptOptions(print_level = 0),
    maxiter = 50, ftol = 1e-4, ctol = 1e-5,
)
r = optimize(model, alg, [1.234, 2.345], options = options)
r.minimum
r.minimizer
