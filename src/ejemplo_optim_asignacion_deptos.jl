

W = 30.0
H = 20.0

max_constructibilidad = 1800

num_pisos = 4
num_strips = 2

vec_area_i = [40.0, 55.0, 70.0, 90.0, 110.0, 120.0]
num_apartment_types = length(vec_area_i)
set_i = 1:num_apartment_types

vec_w = [7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0]
num_widths = length(vec_w)
set_w = 1:num_widths

vec_area_p = vec_w .* .5
mat_reg_area_ip = [vec_area_i[i] + vec_area_p[j] for i in set_i, j in set_w]
mat_reg_h_ip = [mat_reg_area_ip[i,j] / vec_w[j] for i in set_i, j in set_w]

mat_corner_h = [vec_area_i[i] / vec_w[j] for i in set_i, j in set_w]
mat_d_corner_h = [vec_area_i[i] / vec_w[j] for i in set_i, j in set_w]

vec_area_t = vec_area_i .* .1
vec_h_t = ones(length(vec_area_i)) .* 2
vec_w_t = vec_area_t ./ vec_h_t


mat_exposicion = [vec_w[i] for i in eachindex(vec_area_i), j in eachindex(set_w)]
mat_exposicion_corner = [vec_w[i] + mat_corner_h[i,j] for i in eachindex(vec_area_i), j in eachindex(set_w)]
mat_exposicion_d_corner = [vec_w[i] + 2*mat_d_corner_h[i,j] for i in eachindex(vec_area_i), j in eachindex(set_w)]


min_deptos = 20
max_deptos = 40

println("Ejecutando optimización de asignación de departamentos...")
results = optim_asignacion_deptos(
    W, H,
    num_strips,
    vec_w, 
    mat_reg_h_ip, mat_corner_h, mat_d_corner_h,
    vec_area_i, vec_area_p, mat_reg_area_ip,
    vec_w_t, vec_h_t, vec_area_t,
    mat_exposicion, mat_exposicion_corner, mat_exposicion_d_corner,
    min_deptos, max_deptos,
    num_pisos,
    max_constructibilidad
)

print_results(results)
