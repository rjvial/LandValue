### NOMAD ##########################################################################

using NonconvexNOMAD, LinearAlgebra

f(x::AbstractVector) = sqrt(x[2])
g(x::AbstractVector, a, b) = (a*x[1] + b)^3 - x[2]
x0 = [0.5, 2.3]
alg_type = :progressive #[:explicit, :progressive, :custom]

display("Simple constraints 1")
options = NOMADOptions()
m = Model(f)
addvar!(m, [0.0, 0.0], [10.0, 10.0])
add_ineq_constraint!(m, x -> g(x, 2, 0), flags = [:explicit])
add_ineq_constraint!(m, x -> g(x, -1, 1), flags = [:progressive])

alg = NOMADAlg(alg_type)
r1 = NonconvexNOMAD.optimize(m, alg, x0, options = options)



options = NOMADOptions(linear_equality_constraints = true)
m = Model(f)
addvar!(m, [0.0, 0.0], [10.0, 10.0])
add_ineq_constraint!(m, x -> g(x, 2, 0), flags = [:explicit])
add_eq_constraint!(m, x -> sum(x) - 1/3 - 8/27)

alg = NOMADAlg(alg_type)
_x0 = x0 / sum(x0) * (1 / 3 + 8 / 27)
r = NonconvexNOMAD.optimize(m, alg, _x0, options = options)



using Nonconvex
Nonconvex.@load NOMAD

f(x::AbstractVector) = sqrt(x[2])
g(x::AbstractVector, a, b) = (a*x[1] + b)^3 - x[2]
x0 = [0.5, 2.3]

alg = NOMADAlg()
options = NOMADOptions()

m = Model(f)
addvar!(m, [0.0, 0.0], [10.0, 10.0])
add_ineq_constraint!(m, x -> g(x, 2, 0), flags = [:explicit])
add_ineq_constraint!(m, x -> g(x, -1, 1), flags = [:progressive])

result = optimize(m, alg, x0, options = options)

### Bayesian ##########################################################################

using NonconvexBayesian, NonconvexIpopt, NonconvexNLopt
f(x::AbstractVector) = sqrt(x[2])
g(x::AbstractVector, a, b) = -x[1] #(a*x[1] + b)^3 - x[2]

m = Model()
set_objective!(m, f)
addvar!(m, [1e-4, 1e-4], [10.0, 10.0])
add_ineq_constraint!(m, x -> g(x, 2, 0))
#add_ineq_constraint!(m, x -> g(x, -1, 1))

alg = BayesOptAlg(IpoptAlg())
options = BayesOptOptions(
    sub_options = IpoptOptions(print_level = 0), maxiter = 10, ctol = 1e-4,
    ninit = 2, initialize = true, postoptimize = false, fit_prior = true,
)
r = optimize(m, alg, [1.234, 2.345], options = options);
r.minimum
r.minimizer



### Multistart ##########################################################################

using NonconvexMultistart, NonconvexIpopt, LinearAlgebra

f(x::AbstractVector) = sqrt(x[2])
g(x::AbstractVector, a, b) = (a*x[1] + b)^3 - x[2]

alg = HyperoptAlg(IpoptAlg())

(spl_name, spl) = ("Hyperband", Hyperband(R=100, η=3, inner=RandomSampler()))

options = HyperoptOptions(
            sub_options = max_iter -> IpoptOptions(first_order = true, max_iter = max_iter),
            sampler = spl,
        )

m = Model(f)
addvar!(m, [0.0, 0.0], [10.0, 10.0])
add_ineq_constraint!(m, x -> g(x, 2, 0))
add_ineq_constraint!(m, x -> g(x, -1, 1))

r = NonconvexMultistart.optimize(m, alg, [1.234, 2.345], options = options)