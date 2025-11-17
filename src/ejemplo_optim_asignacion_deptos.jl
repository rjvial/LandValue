
min_deptos = 20
max_deptos = 40


W = 30.0
H = 25.0

max_constructibilidad = 2400 #1800

num_pisos = 4
num_strips = 2

vec_area_i = [40.0, 55.0, 70.0, 90.0, 110.0, 120.0]
# vec_area_i = collect(40:120)
num_sizes = length(vec_area_i)
K = 1:num_sizes

# vec_w_i = [7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0]
vec_w_i = collect(7.:.1:13.) # m
num_widths = length(vec_w_i)
J = 1:num_widths

mat_h_i = [vec_area_i[k] / vec_w_i[j] for k in K, j in J] # m

# mat_flag_feasible = mat_h_i .<= 12 .&& mat_h_i .>= 7
mat_flag_feasible = mat_h_i .<= 10 .&& mat_h_i .>= 7


vec_area_p = vec_w_i .* .75 # m2
mat_area_ip = [vec_area_i[k] + vec_area_p[j] for k in K, j in J] # m2
mat_h_ip = [mat_area_ip[k,j] / vec_w_i[j] for k in K, j in J] # m

area_nucleo_depto = 5 # m2
mat_area_ipn = mat_area_ip .+ area_nucleo_depto # m2
mat_h_ipn = [mat_area_ipn[k,j] / vec_w_i[j] for k in K, j in J] # m

mat_corner_h = [vec_area_i[k] / vec_w_i[j] for k in K, j in J] # m
mat_d_corner_h = [vec_area_i[k] / vec_w_i[j] for k in K, j in J] # m

vec_area_t = vec_area_i .* .1 # m2
vec_h_t = ones(length(vec_area_i)) .* 2 # m
vec_w_t = vec_area_t ./ vec_h_t # m


mat_exposicion = [vec_w_i[j] for k in eachindex(vec_area_i), j in eachindex(J)]
mat_exposicion_corner = [vec_w_i[j] + mat_corner_h[k,j] for k in eachindex(vec_area_i), j in eachindex(J)]
mat_exposicion_d_corner = [vec_w_i[j] + 2*mat_d_corner_h[k,j] for k in eachindex(vec_area_i), j in eachindex(J)]


println("Ejecutando optimización de asignación de departamentos...")
results = optim_asignacion_deptos(
    W, H,
    num_strips,
    vec_w_i, 
    mat_h_ip, mat_corner_h, mat_d_corner_h,
    vec_area_i, vec_area_p, mat_area_ip,
    mat_area_ipn, mat_h_ipn, area_nucleo_depto,
    vec_w_t, vec_h_t, vec_area_t,
    mat_exposicion, mat_exposicion_corner, mat_exposicion_d_corner, mat_flag_feasible,
    min_deptos, max_deptos,
    num_pisos,
    max_constructibilidad
)

print_results(results)
