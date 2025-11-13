

W = 30.0
H = 20.0

max_constructibilidad = 1800

num_pisos = 4
num_strips = 2

vec_area_i = [40.0, 55.0, 70.0, 90.0, 110.0, 120.0]
num_sizes = length(vec_area_i)
K = 1:num_sizes

vec_w_i = [7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0]
num_widths = length(vec_w_i)
J = 1:num_widths

vec_area_p = vec_w_i .* .5
mat_reg_area_ip = [vec_area_i[k] + vec_area_p[j] for k in K, j in J]
mat_reg_h_ip = [mat_reg_area_ip[k,j] / vec_w_i[j] for k in K, j in J]

mat_corner_h = [vec_area_i[k] / vec_w_i[j] for k in K, j in J]
mat_d_corner_h = [vec_area_i[k] / vec_w_i[j] for k in K, j in J]

vec_area_t = vec_area_i .* .1
vec_h_t = ones(length(vec_area_i)) .* 2
vec_w_t = vec_area_t ./ vec_h_t


mat_exposicion = [vec_w_i[k] for k in eachindex(vec_area_i), j in eachindex(J)]
mat_exposicion_corner = [vec_w_i[k] + mat_corner_h[k,j] for k in eachindex(vec_area_i), j in eachindex(J)]
mat_exposicion_d_corner = [vec_w_i[k] + 2*mat_d_corner_h[k,j] for k in eachindex(vec_area_i), j in eachindex(J)]


min_deptos = 20
max_deptos = 40

println("Ejecutando optimización de asignación de departamentos...")
results = optim_asignacion_deptos(
    W, H,
    num_strips,
    vec_w_i, 
    mat_reg_h_ip, mat_corner_h, mat_d_corner_h,
    vec_area_i, vec_area_p, mat_reg_area_ip,
    vec_w_t, vec_h_t, vec_area_t,
    mat_exposicion, mat_exposicion_corner, mat_exposicion_d_corner,
    min_deptos, max_deptos,
    num_pisos,
    max_constructibilidad
)

print_results(results)
