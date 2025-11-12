

W = 30.0
H = 25.0

max_constructibilidad = 2000

num_pisos = 5

num_strips = 2

vec_area_interior = [40.0, 55.0, 70.0, 90.0, 110.0, 120.0]

vec_w = [7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0]

num_apartment_types = length(vec_area_interior)
set_i = 1:num_apartment_types

num_widths = length(vec_w)
set_w = 1:num_widths

vec_area_pasillo = vec_w .* .75
mat_ap = [vec_area_interior[i] + vec_area_pasillo[j] for i in set_i, j in set_w]
mat_h = [mat_ap[i,j] / vec_w[j] for i in set_i, j in set_w]


vec_area_terraza = vec_area_interior .* .1
vec_h_terraza = ones(length(vec_area_interior)) .* 2
vec_w_terraza = vec_area_terraza ./ vec_h_terraza


mat_exposicion = [vec_w[i] for i in eachindex(vec_area_interior), j in eachindex(set_w)]
mat_exposicion_corner = [vec_w[i] + mat_h[i,j] for i in eachindex(vec_area_interior), j in eachindex(set_w)]
mat_exposicion_double_corner = [vec_w[i] + 2*mat_h[i,j] for i in eachindex(vec_area_interior), j in eachindex(set_w)]


min_deptos = 20
max_deptos = 40

println("Ejecutando optimización de asignación de departamentos...")
results = optim_asignacion_deptos(
    W, H,
    num_strips,
    vec_w, mat_h, vec_area_interior, vec_area_pasillo,
    vec_w_terraza, vec_h_terraza, vec_area_terraza,
    mat_exposicion, mat_exposicion_corner, mat_exposicion_double_corner,
    min_deptos, max_deptos,
    num_pisos,
    max_constructibilidad
)

print_results(results)
