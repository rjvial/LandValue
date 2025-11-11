

W = 30.0
H = 25.0

num_strips = 2

set_i = [1, 2, 3, 4, 5, 6]
vec_a = [40.0, 55.0, 70.0, 90.0, 110.0, 120.0]

set_w = [1, 2, 3, 4, 5, 6, 7]
vec_w = [7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0]

vec_pasillo_a = vec_w .* .75
mat_ap = [vec_a[i] + vec_pasillo_a[j] for i in set_i, j in set_w]
mat_h = [mat_ap[i,j] / vec_w[j] for i in set_i, j in set_w]


vec_t_a = vec_a .* .1
vec_t_h = ones(length(vec_a)) .* 2
vec_t_w = vec_t_a ./ vec_t_h


mat_p = [vec_w[i] for i in eachindex(vec_a), j in eachindex(set_w)]
mat_pc = [vec_w[i] + mat_h[i,j] for i in eachindex(vec_a), j in eachindex(set_w)]
mat_pcc = [vec_w[i] + 2*mat_h[i,j] for i in eachindex(vec_a), j in eachindex(set_w)]


min_deptos = 5
max_deptos = 20

println("Ejecutando optimización de asignación de departamentos...")
results = optim_asignacion_deptos(
    W, H,
    num_strips,
    set_i, set_w,
    vec_w, mat_h, vec_a, vec_pasillo_a,
    vec_t_w, vec_t_h, vec_t_a,
    mat_p, mat_pc, mat_pcc,
    min_deptos, max_deptos
)

print_results(results)
