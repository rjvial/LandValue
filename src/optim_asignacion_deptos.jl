using JuMP
using HiGHS

"""
    optim_asignacion_deptos(W, H, num_strips, set_i, set_w, vec_w, mat_reg_h_ip, vec_area_i, vec_area_p, vec_w_t, vec_h_t, vec_area_t, mat_exposicion, mat_exposicion_corner, mat_exposicion_d_corner, min_deptos, max_deptos)

Optimiza la asignación de departamentos en strips horizontales para maximizar superficie total.

# Argumentos
- `W::Float64`: Ancho del edificio (m)
- `H::Float64`: Altura total del edificio (m)
- `num_strips::Int`: Número de strips horizontales
- `set_i::Vector{Int}`: Conjunto de índices de tipos de departamentos
- `set_w::Vector{Int}`: Conjunto de índices de alturas
- `vec_w`: Vector de anchos por tipo de departamento i
- `mat_reg_h_ip`: Matriz de alturas [i,h] por tipo de departamento e índice de altura
- `vec_area_i`: Vector de áreas por tipo i
- `vec_area_p`: Vector de áreas de pasillo por tipo i
- `vec_w_t`: Vector de anchos de terraza por tipo i
- `vec_h_t`: Vector de alturas de terraza por tipo i
- `vec_area_t`: Vector de áreas de terraza por tipo i
- `mat_exposicion, mat_exposicion_corner, mat_exposicion_d_corner`: Matrices de perímetros [i,h] (regular, corner, corner2)
- `min_deptos::Int`: Número mínimo de departamentos
- `max_deptos::Int`: Número máximo de departamentos
"""
function optim_asignacion_deptos(
    W::Float64,
    H::Float64,
    num_strips::Int,
    vec_w, 
    mat_reg_h_ip, mat_corner_h, mat_d_corner_h,
    vec_area_i, vec_area_p, mat_reg_area_ip,
    vec_w_t, vec_h_t, vec_area_t,
    mat_exposicion, mat_exposicion_corner, mat_exposicion_d_corner,
    min_deptos::Int,
    max_deptos::Int,
    num_pisos,
    max_constructibilidad)

    flag_dfl2 = true

    num_pisos_superiores = num_pisos - 1

    num_areas_deptos = length(vec_area_i)
    set_i = 1:num_areas_deptos

    num_widths = size(mat_reg_h_ip, 2)
    set_w = 1:num_widths

    model = Model(HiGHS.Optimizer)
    set_silent(model)
    set_time_limit_sec(model, 300.0)
    set_optimizer_attribute(model, "mip_rel_gap", 0.01)
    set_optimizer_attribute(model, "presolve", "on")

    S = 1:num_strips

    max_z_bounds = Dict()
    for i in set_i, j in set_w
        if (mat_reg_h_ip[i,j] + vec_h_t[i]) <= H && vec_w[i] <= W
            max_by_width = floor(Int, W / vec_w[i])
            max_by_height = floor(Int, H / (mat_reg_h_ip[i,j] + vec_h_t[i]))
            max_by_area = floor(Int, (W * H) / (vec_area_i[i] + vec_area_t[i]))
            max_z_bounds[(i,j)] = min(max_by_width, max_by_height, max_by_area, max_deptos)
        else
            max_z_bounds[(i,j)] = 0
        end
    end

    """
    Decision Variables:
    - H_s: Depth of each strip s (continuous, non-negative)
    - num_deptos_reg_primer_piso: Number of regular apartments in first floor strip s, type i, height j (integer)
    - num_deptos_corner_primer_piso: Number of corner apartments in first floor strip s, type i, height j (integer)
    - num_deptos_d_corner_primer_piso: Number of double corner apartments in first floor strip s, type i, height j (integer)
    - area_comun_primer_piso: Common area for first floor (continuous, non-negative)
    - num_deptos_reg_por_piso_superior: Number of regular apartments in upper floor strip s, type i, height j (integer)
    - num_deptos_corner_por_piso_superior: Number of corner apartments in upper floor strip s, type i, height j (integer)
    - num_deptos_d_corner_por_piso_superior: Number of double corner apartments in upper floor strip s, type i, height j (integer)
    - area_comun_por_piso_superior: Common area for upper floors (continuous, non-negative)
    - x: Binary indicator for regular apartment type selection in strip s, type i, height j
    - x_c: Binary indicator for corner apartment type selection in strip s, type i, height j
    - x_cc: Binary indicator for double corner apartment type selection in strip s, type i, height j
    - y_c: Binary indicator for strip s using corner configuration
    - y_cc: Binary indicator for strip s using double corner configuration
    - descuento_dfl2: DFL2 discount amount for buildability calculation (continuous, non-negative)
    - area_no_utilizada_primer_piso: Unused area in first floor footprint (continuous, non-negative)
    - area_no_utilizada_por_piso_superior: Unused area in upper floors footprint (continuous, non-negative)
    """
    @variables(model, begin
        H_s[s in S] >= 0

        0 <= num_deptos_reg_primer_piso[s in S, i in set_i, j in set_w] <= max_z_bounds[(i,j)], Int
        0 <= num_deptos_corner_primer_piso[s in S, i in set_i, j in set_w] <= max_z_bounds[(i,j)], Int
        0 <= num_deptos_d_corner_primer_piso[s in S, i in set_i, j in set_w] <= max_z_bounds[(i,j)], Int
        area_comun_primer_piso >= 0

        0 <= num_deptos_reg_por_piso_superior[s in S, i in set_i, j in set_w] <= max_z_bounds[(i,j)], Int
        0 <= num_deptos_corner_por_piso_superior[s in S, i in set_i, j in set_w] <= max_z_bounds[(i,j)], Int
        0 <= num_deptos_d_corner_por_piso_superior[s in S, i in set_i, j in set_w] <= max_z_bounds[(i,j)], Int
        area_comun_por_piso_superior >= 0

        x[s in S, i in set_i, j in set_w], Bin
        x_c[s in S, i in set_i, j in set_w], Bin
        x_cc[s in S, i in set_i, j in set_w], Bin

        y_c[s in S], Bin
        y_cc[s in S], Bin

        descuento_dfl2 >= 0
        area_no_utilizada_primer_piso >= 0
        area_no_utilizada_por_piso_superior >= 0
    end)

    
    @expressions(model, begin
        # Total common area across all floors
        area_comun_total, area_comun_primer_piso + area_comun_por_piso_superior * num_pisos_superiores

        area_no_utilizada, area_no_utilizada_primer_piso + area_no_utilizada_por_piso_superior * num_pisos_superiores

        # Total interior area for first floor apartments
        area_interior_primer_piso, sum((num_deptos_reg_primer_piso[s,i,j] +
             num_deptos_corner_primer_piso[s,i,j] +
             num_deptos_d_corner_primer_piso[s,i,j]) * vec_area_i[i] for s in S, i in set_i, j in set_w)
        
        # Interior area per upper floor 
        area_interior_por_piso_superior, sum((num_deptos_reg_por_piso_superior[s,i,j] +
             num_deptos_corner_por_piso_superior[s,i,j] +
             num_deptos_d_corner_por_piso_superior[s,i,j]) * vec_area_i[i] for s in S, i in set_i, j in set_w)

        # Total interior area for entire building
        area_interior_total, area_interior_primer_piso + area_interior_por_piso_superior * num_pisos_superiores

        # Total terrace area for first floor apartments
        area_terraza_primer_piso, sum((num_deptos_reg_primer_piso[s,i,j] +
             num_deptos_corner_primer_piso[s,i,j] +
             num_deptos_d_corner_primer_piso[s,i,j]) * vec_area_t[i] for s in S, i in set_i, j in set_w)

        # Terrace area per upper floor
        area_terraza_por_piso_superior, sum((num_deptos_reg_por_piso_superior[s,i,j] +
             num_deptos_corner_por_piso_superior[s,i,j] +
             num_deptos_d_corner_por_piso_superior[s,i,j]) * vec_area_t[i] for s in S, i in set_i, j in set_w)

        # Total terrace area for entire building
        area_terraza_total, area_terraza_primer_piso + area_terraza_por_piso_superior * num_pisos_superiores

        # Useful area for first floor (interior + 50% of terrace)
        area_util_primer_piso, area_interior_primer_piso + area_terraza_primer_piso / 2

        # Useful area per upper floor (interior + 50% of terrace)
        area_util_por_piso_superior, area_interior_por_piso_superior + area_terraza_por_piso_superior / 2

        # Total useful area for entire building
        area_util_total, area_util_primer_piso + area_util_por_piso_superior * num_pisos_superiores

        # Total hallway area for first floor apartments
        area_pasillo_primer_piso, sum(num_deptos_reg_primer_piso[s,i,j] * vec_area_p[i] for s in S, i in set_i, j in set_w)

        # Hallway area per upper floor
        area_pasillo_por_piso_superior, sum(num_deptos_reg_por_piso_superior[s,i,j] * vec_area_p[i] for s in S, i in set_i, j in set_w)

        # Total hallway area for entire building
        area_pasillo_total, area_pasillo_primer_piso + area_pasillo_por_piso_superior * num_pisos_superiores

        # Total SNT area (interior + terrace + common areas)
        area_snt, area_interior_total + area_terraza_total + area_comun_total

        # Total count of all apartment types across all strips and floors
        deptos_total, (sum(num_deptos_reg_primer_piso[s,i,j] for s in S, i in set_i, j in set_w) +
            sum(num_deptos_corner_primer_piso[s,i,j] for s in S, i in set_i, j in set_w) +
            sum(num_deptos_d_corner_primer_piso[s,i,j] for s in S, i in set_i, j in set_w)) +
            (sum(num_deptos_reg_por_piso_superior[s,i,j] for s in S, i in set_i, j in set_w) +
            sum(num_deptos_corner_por_piso_superior[s,i,j] for s in S, i in set_i, j in set_w) +
            sum(num_deptos_d_corner_por_piso_superior[s,i,j] for s in S, i in set_i, j in set_w)) * num_pisos_superiores

    end)


    @constraints(model, begin

        # First floor footprint must equal building footprint (all areas sum to W × H)
        constraint_1, area_interior_primer_piso + area_terraza_primer_piso + area_comun_primer_piso + area_no_utilizada_primer_piso == W * H

        # Upper floor footprint must equal building footprint (all areas sum to W × H)
        constraint_2, area_interior_por_piso_superior + area_terraza_por_piso_superior + area_comun_por_piso_superior + area_no_utilizada_por_piso_superior == W * H

        # Common area for first floor must include at least all hallway areas
        constraint_3, area_comun_primer_piso >= area_pasillo_primer_piso

        # Common area for upper floors must include at least all hallway areas
        constraint_4, area_comun_por_piso_superior >= area_pasillo_por_piso_superior

        # First floor common area must be at least as large as upper floor common area
        constraint_5, area_comun_primer_piso >= area_comun_por_piso_superior

        # Buildability constraint: useful area + common area - DFL2 discount must not exceed maximum buildability
        constraint_6, area_util_total + area_comun_total - descuento_dfl2 <= max_constructibilidad

        # DFL2 discount cannot exceed 20% of useful area
        constraint_7, descuento_dfl2 <= flag_dfl2 * 0.2 * area_util_total

        # DFL2 discount cannot exceed total common area
        constraint_8, descuento_dfl2 <= flag_dfl2 * area_comun_total

        # Common area for upper floors must be at least 12% of useful area
        constraint_9, area_comun_por_piso_superior >= 0.12 * area_util_por_piso_superior

        # Total common area must be at least 18% of total useful area
        constraint_10, area_comun_total >= 0.18 * area_util_total

        # Total common area cannot exceed 25% of total useful area
        constraint_11, area_comun_total <= 0.25 * area_util_total

        # Exactly 2 corner apartments per strip if corner type is used (corner apartments come in pairs)
        constraint_12[s in S], sum(num_deptos_corner_por_piso_superior[s,i,j] for i in set_i, j in set_w) == 2 * y_c[s]

        # Exactly 1 double corner apartment per strip if double corner type is used
        constraint_13[s in S], sum(num_deptos_d_corner_por_piso_superior[s,i,j] for i in set_i, j in set_w) == y_cc[s]

        # Allows only one double corner apartment or several regular apartments, not both
        constraint_14[s in S], sum(x_cc[s,i,j] + x[s,i,j] for i in set_i, j in set_w) <= y_cc[s] + (1 - y_cc[s]) * max_deptos

        # Strip can use either corner or double corner configuration, not both simultaneously
        constraint_15[s in S], y_c[s] + y_cc[s] <= 1

        # Total apartment count must be within specified bounds
        constraint_16, min_deptos <= deptos_total <= max_deptos

        # Sum of all strip depths cannot exceed building depth
        constraint_17, sum(H_s[s] for s in S) <= H

        # Each strip must have minimum depth of 7.0m
        constraint_18[s in S], H_s[s] >= 8.0

        # Apartment height (interior + terrace) must fit within strip depth for each apartment type
        constraint_19[s in S, i in set_i, j in set_w], x[s,i,j] * (mat_reg_h_ip[i,j] + vec_h_t[i]) <= H_s[s]
        constraint_20[s in S, i in set_i, j in set_w], x_c[s,i,j] * (mat_corner_h[i,j] + vec_h_t[i]) <= H_s[s]
        constraint_21[s in S, i in set_i, j in set_w], x_cc[s,i,j] * (mat_d_corner_h[i,j] + vec_h_t[i]) <= H_s[s]

        # Total apartment area per strip cannot exceed strip footprint (W x H_s)
        constraint_22[s in S], sum(num_deptos_reg_por_piso_superior[s,i,j] * (mat_reg_area_ip[i,j] + vec_area_t[i]) +
             (num_deptos_corner_por_piso_superior[s,i,j] + num_deptos_d_corner_por_piso_superior[s,i,j]) * (vec_area_i[i] + vec_area_t[i]) 
              for i in set_i, j in set_w) <= W * H_s[s]

        # Apartment count is positive only if apartment type is selected (Big-M constraint linking binary and integer variables)
        constraint_23[s in S, i in set_i, j in set_w], num_deptos_reg_por_piso_superior[s,i,j] <= max_deptos * x[s,i,j]
        constraint_24[s in S, i in set_i, j in set_w], num_deptos_corner_por_piso_superior[s,i,j] <= max_deptos * x_c[s,i,j]
        constraint_25[s in S, i in set_i, j in set_w], num_deptos_d_corner_por_piso_superior[s,i,j] <= max_deptos * x_cc[s,i,j]

        # Total apartment widths per strip cannot exceed building width W
        constraint_26[s in S], sum((num_deptos_reg_por_piso_superior[s,i,j] +
            num_deptos_corner_por_piso_superior[s,i,j] +
            num_deptos_d_corner_por_piso_superior[s,i,j]) * vec_w[i] for i in set_i, j in set_w) <= W

        # Sum of apartment perimeters must cover strip perimeter with 5m tolerance (ensures adequate facade coverage)
        constraint_27[s in S],
            sum(num_deptos_reg_por_piso_superior[s,i,j] * mat_exposicion[i,j] for i in set_i, j in set_w) +
            sum(num_deptos_corner_por_piso_superior[s,i,j] * mat_exposicion_corner[i,j] for i in set_i, j in set_w) +
            sum(num_deptos_d_corner_por_piso_superior[s,i,j] * mat_exposicion_d_corner[i,j] for i in set_i, j in set_w) >= 2*H_s[s] + W - 5
            
        # First floor apartment counts cannot exceed upper floor counts (first floor is subset of upper floors)
        constraint_28[s in S, i in set_i, j in set_w], num_deptos_reg_primer_piso[s,i,j] <= num_deptos_reg_por_piso_superior[s,i,j]
        constraint_29[s in S, i in set_i, j in set_w], num_deptos_corner_primer_piso[s,i,j] <= num_deptos_corner_por_piso_superior[s,i,j]
        constraint_30[s in S, i in set_i, j in set_w], num_deptos_d_corner_primer_piso[s,i,j] <= num_deptos_d_corner_por_piso_superior[s,i,j]
    end)


    # Maximize total apartment interior area
    @objective(model, Max, area_util_total)

    optimize!(model)


    
    results = Dict{String,Any}()
    results["status"] = termination_status(model)
    results["solve_time"] = solve_time(model)
    results["num_deptos_reg_por_piso_superior"] = Dict{Tuple{Int,Int,Int},Float64}()
    results["num_deptos_corner_por_piso_superior"] = Dict{Tuple{Int,Int,Int},Float64}()
    results["num_deptos_d_corner_por_piso_superior"] = Dict{Tuple{Int,Int,Int},Float64}()
    results["num_deptos_reg_primer_piso"] = Dict{Tuple{Int,Int,Int},Float64}()
    results["num_deptos_corner_primer_piso"] = Dict{Tuple{Int,Int,Int},Float64}()
    results["num_deptos_d_corner_primer_piso"] = Dict{Tuple{Int,Int,Int},Float64}()
    results["x"] = Dict{Tuple{Int,Int,Int},Int}()
    results["x_c"] = Dict{Tuple{Int,Int,Int},Int}()
    results["x_cc"] = Dict{Tuple{Int,Int,Int},Int}()
    results["H_s"] = Dict{Int,Float64}()
    results["perimetro_strip_primer_piso"] = Dict{Int,Float64}()
    results["apartment_area_strip_primer_piso"] = Dict{Int,Float64}()
    results["terrace_area_strip_primer_piso"] = Dict{Int,Float64}()
    results["pasillo_area_strip_primer_piso"] = Dict{Int,Float64}()
    results["perimetro_strip_pisos_superiores"] = Dict{Int,Float64}()
    results["apartment_area_strip_pisos_superiores"] = Dict{Int,Float64}()
    results["terrace_area_strip_pisos_superiores"] = Dict{Int,Float64}()
    results["pasillo_area_strip_pisos_superiores"] = Dict{Int,Float64}()
    results["vec_area_t"] = vec_area_t
    results["vec_w_t"] = vec_w_t
    results["vec_h_t"] = vec_h_t
    results["vec_area_i"] = vec_area_i
    results["vec_area_p"] = vec_area_p
    results["vec_w"] = vec_w
    results["mat_reg_h_ip"] = mat_reg_h_ip
    results["W"] = W
    results["H"] = H

    if has_values(model)
        results["objective_value"] = objective_value(model)
        results["area_comun_primer_piso"] = value(area_comun_primer_piso)
        results["area_comun_por_piso_superior"] = value(area_comun_por_piso_superior)
        results["area_no_utilizada_primer_piso"] = value(area_no_utilizada_primer_piso)
        results["area_no_utilizada_por_piso_superior"] = value(area_no_utilizada_por_piso_superior)

        for s in S
            results["H_s"][s] = value(H_s[s])

            perimetro_s_pp = sum(value(num_deptos_reg_primer_piso[s,i,j]) * mat_exposicion[i,j] for i in set_i, j in set_w) +
                          sum(value(num_deptos_corner_primer_piso[s,i,j]) * mat_exposicion_corner[i,j] for i in set_i, j in set_w) +
                          sum(value(num_deptos_d_corner_primer_piso[s,i,j]) * mat_exposicion_d_corner[i,j] for i in set_i, j in set_w)
            results["perimetro_strip_primer_piso"][s] = perimetro_s_pp

            apartment_area_s_pp = sum(value(num_deptos_reg_primer_piso[s,i,j]) * vec_area_i[i] for i in set_i, j in set_w) +
                               sum(value(num_deptos_corner_primer_piso[s,i,j]) * vec_area_i[i] for i in set_i, j in set_w) +
                               sum(value(num_deptos_d_corner_primer_piso[s,i,j]) * vec_area_i[i] for i in set_i, j in set_w)
            results["apartment_area_strip_primer_piso"][s] = apartment_area_s_pp

            terrace_area_s_pp = sum(value(num_deptos_reg_primer_piso[s,i,j]) * vec_area_t[i] for i in set_i, j in set_w) +
                             sum(value(num_deptos_corner_primer_piso[s,i,j]) * vec_area_t[i] for i in set_i, j in set_w) +
                             sum(value(num_deptos_d_corner_primer_piso[s,i,j]) * vec_area_t[i] for i in set_i, j in set_w)
            results["terrace_area_strip_primer_piso"][s] = terrace_area_s_pp

            pasillo_area_s_pp = sum(value(num_deptos_reg_primer_piso[s,i,j]) * vec_area_p[i] for i in set_i, j in set_w) +
                             sum(value(num_deptos_corner_primer_piso[s,i,j]) * vec_area_p[i] for i in set_i, j in set_w) +
                             sum(value(num_deptos_d_corner_primer_piso[s,i,j]) * vec_area_p[i] for i in set_i, j in set_w)
            results["pasillo_area_strip_primer_piso"][s] = pasillo_area_s_pp

            perimetro_s_ps = sum(value(num_deptos_reg_por_piso_superior[s,i,j]) * mat_exposicion[i,j] for i in set_i, j in set_w) +
                          sum(value(num_deptos_corner_por_piso_superior[s,i,j]) * mat_exposicion_corner[i,j] for i in set_i, j in set_w) +
                          sum(value(num_deptos_d_corner_por_piso_superior[s,i,j]) * mat_exposicion_d_corner[i,j] for i in set_i, j in set_w)
            results["perimetro_strip_pisos_superiores"][s] = perimetro_s_ps

            apartment_area_s_ps = sum(value(num_deptos_reg_por_piso_superior[s,i,j]) * vec_area_i[i] for i in set_i, j in set_w) +
                               sum(value(num_deptos_corner_por_piso_superior[s,i,j]) * vec_area_i[i] for i in set_i, j in set_w) +
                               sum(value(num_deptos_d_corner_por_piso_superior[s,i,j]) * vec_area_i[i] for i in set_i, j in set_w)
            results["apartment_area_strip_pisos_superiores"][s] = apartment_area_s_ps

            terrace_area_s_ps = sum(value(num_deptos_reg_por_piso_superior[s,i,j]) * vec_area_t[i] for i in set_i, j in set_w) +
                             sum(value(num_deptos_corner_por_piso_superior[s,i,j]) * vec_area_t[i] for i in set_i, j in set_w) +
                             sum(value(num_deptos_d_corner_por_piso_superior[s,i,j]) * vec_area_t[i] for i in set_i, j in set_w)
            results["terrace_area_strip_pisos_superiores"][s] = terrace_area_s_ps

            pasillo_area_s_ps = sum(value(num_deptos_reg_por_piso_superior[s,i,j]) * vec_area_p[i] for i in set_i, j in set_w) +
                             sum(value(num_deptos_corner_por_piso_superior[s,i,j]) * vec_area_p[i] for i in set_i, j in set_w) +
                             sum(value(num_deptos_d_corner_por_piso_superior[s,i,j]) * vec_area_p[i] for i in set_i, j in set_w)
            results["pasillo_area_strip_pisos_superiores"][s] = pasillo_area_s_ps

            for i in set_i, h in set_w
                for (var, key, threshold, is_binary) in [
                    (num_deptos_reg_por_piso_superior[s,i,h], "num_deptos_reg_por_piso_superior", 0.001, false),
                    (num_deptos_corner_por_piso_superior[s,i,h], "num_deptos_corner_por_piso_superior", 0.001, false),
                    (num_deptos_d_corner_por_piso_superior[s,i,h], "num_deptos_d_corner_por_piso_superior", 0.001, false),
                    (num_deptos_reg_primer_piso[s,i,h], "num_deptos_reg_primer_piso", 0.001, false),
                    (num_deptos_corner_primer_piso[s,i,h], "num_deptos_corner_primer_piso", 0.001, false),
                    (num_deptos_d_corner_primer_piso[s,i,h], "num_deptos_d_corner_primer_piso", 0.001, false),
                    (x[s,i,h], "x", 0.5, true),
                    (x_c[s,i,h], "x_c", 0.5, true),
                    (x_cc[s,i,h], "x_cc", 0.5, true)]

                    val = value(var)
                    if val > threshold
                        results[key][(s,i,h)] = is_binary ? 1 : val
                    end
                end
            end
        end

        deptos_primer_piso = sum(sum(values(results[k])) for k in ["num_deptos_reg_primer_piso", "num_deptos_corner_primer_piso", "num_deptos_d_corner_primer_piso"])
        deptos_pisos_superiores = sum(sum(values(results[k])) for k in ["num_deptos_reg_por_piso_superior", "num_deptos_corner_por_piso_superior", "num_deptos_d_corner_por_piso_superior"])

        results["total_deptos_primer_piso"] = deptos_primer_piso
        results["total_deptos_pisos_superiores"] = deptos_pisos_superiores
        results["total_deptos"] = deptos_primer_piso + deptos_pisos_superiores * num_pisos_superiores

        results["total_apartment_area_primer_piso"] = sum(values(results["apartment_area_strip_primer_piso"]))
        results["total_terrace_area_primer_piso"] = sum(values(results["terrace_area_strip_primer_piso"]))
        results["total_pasillo_area_primer_piso"] = sum(values(results["pasillo_area_strip_primer_piso"]))

        results["total_apartment_area_pisos_superiores"] = sum(values(results["apartment_area_strip_pisos_superiores"]))
        results["total_terrace_area_pisos_superiores"] = sum(values(results["terrace_area_strip_pisos_superiores"]))
        results["total_pasillo_area_pisos_superiores"] = sum(values(results["pasillo_area_strip_pisos_superiores"]))

        results["total_area_pisos_superiores"] = (results["total_apartment_area_pisos_superiores"] + results["total_terrace_area_pisos_superiores"] + results["total_pasillo_area_pisos_superiores"]) * num_pisos_superiores

        results["total_apartment_area_building"] = results["total_apartment_area_primer_piso"] + results["total_apartment_area_pisos_superiores"] * num_pisos_superiores
        results["total_terrace_area_building"] = results["total_terrace_area_primer_piso"] + results["total_terrace_area_pisos_superiores"] * num_pisos_superiores
        results["total_pasillo_area_building"] = results["total_pasillo_area_primer_piso"] + results["total_pasillo_area_pisos_superiores"] * num_pisos_superiores
        results["total_area_building"] = results["total_apartment_area_building"] + results["total_terrace_area_building"] + results["total_pasillo_area_building"]

        results["num_pisos_superiores"] = num_pisos_superiores
        results["num_pisos_total"] = num_pisos
    else
        results["objective_value"] = nothing
        results["total_deptos"] = 0.0
        println("\n⚠️  WARNING: No feasible solution found!")
        println("Status: $(results["status"])")
    end

    return results
end

function print_results(results::Dict)
    println("\n" * "="^60)
    println("RESULTADOS OPTIMIZACIÓN ASIGNACIÓN DEPTOS")
    println("="^60)
    println("Estado: $(results["status"])")

    if isnothing(results["objective_value"])
        println("Valor objetivo: N/A (sin solución factible)")
    else
        println("Valor objetivo: $(round(results["objective_value"], digits=2))")
    end

    println("Tiempo de solución: $(round(results["solve_time"], digits=2)) segundos")

    if !isnothing(results["objective_value"])
        total_deptos_pp = get(results, "total_deptos_primer_piso", 0.0)
        total_deptos_ps = get(results, "total_deptos_pisos_superiores", 0.0)
        total_deptos = get(results, "total_deptos", 0.0)
        num_pisos_sup = get(results, "num_pisos_superiores", 1)

        println("Total departamentos edificio: $(round(total_deptos, digits=0))")
        println("  - Primer piso: $(round(total_deptos_pp, digits=0)) deptos")
        println("  - Pisos superiores: $(round(total_deptos_ps, digits=0)) deptos/piso × $(num_pisos_sup) pisos = $(round(total_deptos_ps * num_pisos_sup, digits=0)) deptos")
    else
        println("Total departamentos: 0")
    end

    if !isnothing(results["objective_value"])
        area_interior_pp = get(results, "total_apartment_area_primer_piso", 0.0)
        area_terraza_pp = get(results, "total_terrace_area_primer_piso", 0.0)
        area_pasillo_pp = get(results, "total_pasillo_area_primer_piso", 0.0)
        area_comun_pp = get(results, "area_comun_primer_piso", 0.0)
        area_util_pp = area_interior_pp + area_terraza_pp / 2

        area_interior_ps = get(results, "total_apartment_area_pisos_superiores", 0.0)
        area_terraza_ps = get(results, "total_terrace_area_pisos_superiores", 0.0)
        area_pasillo_ps = get(results, "total_pasillo_area_pisos_superiores", 0.0)
        area_comun_ps = get(results, "area_comun_por_piso_superior", 0.0)
        area_util_ps = area_interior_ps + area_terraza_ps / 2

        num_pisos_sup = get(results, "num_pisos_superiores", 1)
        num_pisos_total = get(results, "num_pisos_total", 1)

        area_total_losa_pp = area_interior_pp + area_terraza_pp + area_comun_pp
        area_total_losa_ps = area_interior_ps + area_terraza_ps + area_comun_ps
        area_total_losa_edificio = area_total_losa_pp + area_total_losa_ps * num_pisos_sup

        println("\n" * "="^80)
        println("RESUMEN DE ÁREAS POR PISO")
        println("="^80)
        println("")

        W_building = get(results, "W", 0.0)
        H_building = get(results, "H", 0.0)
        area_emplazamiento_por_piso = W_building * H_building
        area_emplazamiento_total = area_emplazamiento_por_piso * num_pisos_total

        area_no_utilizada_pp = area_emplazamiento_por_piso - (area_interior_pp + area_terraza_pp + area_comun_pp)
        area_no_utilizada_ps = area_emplazamiento_por_piso - (area_interior_ps + area_terraza_ps + area_comun_ps)
        area_no_utilizada_total = area_no_utilizada_pp + area_no_utilizada_ps * num_pisos_sup

        println("┌─────────────────────┬──────────────────┬──────────────────┬──────────────────┐")
        println("│                     │  Primer Piso     │  Piso Superior   │  Total Edificio  │")
        println("│                     │    (1 piso)      │   (por piso)     │   ($(num_pisos_total) pisos)      │")
        println("├─────────────────────┼──────────────────┼──────────────────┼──────────────────┤")
        println("│ Área Interior       │ $(lpad(round(area_interior_pp, digits=1), 12)) m² │ $(lpad(round(area_interior_ps, digits=1), 12)) m² │ $(lpad(round(area_interior_pp + area_interior_ps * num_pisos_sup, digits=1), 12)) m² │")
        println("│ Área Terraza        │ $(lpad(round(area_terraza_pp, digits=1), 12)) m² │ $(lpad(round(area_terraza_ps, digits=1), 12)) m² │ $(lpad(round(area_terraza_pp + area_terraza_ps * num_pisos_sup, digits=1), 12)) m² │")
        println("│ Área Común          │ $(lpad(round(area_comun_pp, digits=1), 12)) m² │ $(lpad(round(area_comun_ps, digits=1), 12)) m² │ $(lpad(round(area_comun_pp + area_comun_ps * num_pisos_sup, digits=1), 12)) m² │")
        println("│   - Área Pasillo    │ $(lpad(round(area_pasillo_pp, digits=1), 12)) m² │ $(lpad(round(area_pasillo_ps, digits=1), 12)) m² │ $(lpad(round(area_pasillo_pp + area_pasillo_ps * num_pisos_sup, digits=1), 12)) m² │")
        println("│   - Otros espacios  │ $(lpad(round(area_comun_pp - area_pasillo_pp, digits=1), 12)) m² │ $(lpad(round(area_comun_ps - area_pasillo_ps, digits=1), 12)) m² │ $(lpad(round((area_comun_pp - area_pasillo_pp) + (area_comun_ps - area_pasillo_ps) * num_pisos_sup, digits=1), 12)) m² │")
        println("│ Área No Utilizada   │ $(lpad(round(area_no_utilizada_pp, digits=1), 12)) m² │ $(lpad(round(area_no_utilizada_ps, digits=1), 12)) m² │ $(lpad(round(area_no_utilizada_total, digits=1), 12)) m² │")
        println("├─────────────────────┼──────────────────┼──────────────────┼──────────────────┤")
        println("│ Área Losa SNT       │ $(lpad(round(area_total_losa_pp, digits=1), 12)) m² │ $(lpad(round(area_total_losa_ps, digits=1), 12)) m² │ $(lpad(round(area_total_losa_edificio, digits=1), 12)) m² │")
        println("├─────────────────────┼──────────────────┼──────────────────┼──────────────────┤")
        println("│ Área Emplazamiento  │ $(lpad(round(area_emplazamiento_por_piso, digits=1), 12)) m² │ $(lpad(round(area_emplazamiento_por_piso, digits=1), 12)) m² │ $(lpad(round(area_emplazamiento_total, digits=1), 12)) m² │")
        println("│ (W × Profundidad)   │                  │                  │                  │")
        println("├─────────────────────┼──────────────────┼──────────────────┼──────────────────┤")
        println("│ Área Útil           │ $(lpad(round(area_util_pp, digits=1), 12)) m² │ $(lpad(round(area_util_ps, digits=1), 12)) m² │ $(lpad(round(area_util_pp + area_util_ps * num_pisos_sup, digits=1), 12)) m² │")
        println("│ (Interior + Terr/2) │                  │                  │                  │")
        println("└─────────────────────┴──────────────────┴──────────────────┴──────────────────┘")
        println("")
        println("Notas:")
        println("  • Área Losa SNT = Área Interior + Área Terraza + Área Común")
        println("  • Área Emplazamiento = Área Losa SNT + Área No Utilizada")
        println("  • Área Útil = Área Interior + Área Terraza/2")
        println("    (Las terrazas cuentan al 50% para área útil)")
        println("  • Área Común se desglosa en:")
        println("    - Área Pasillo: espacio de circulación asignado a cada departamento")
        println("    - Otros espacios: áreas comunes adicionales (lobbies, salas, etc.)")
        println("  • Área No Utilizada = espacio del emplazamiento no ocupado por deptos ni áreas comunes")
    end

    println("\n" * "="^140)
    println("ASIGNACIÓN DE DEPARTAMENTOS POR STRIP")
    println("="^140)

    vec_area_i = results["vec_area_i"]
    vec_area_t = results["vec_area_t"]
    vec_area_p = results["vec_area_p"]
    vec_h_t = results["vec_h_t"]

    println("\n┌────────┬──────────┬────────────┬──────────────┬──────┬──────┬──────────┬─────────────┬─────────────┬─────────────┬────────────┐")
    println("│ Strip  │ Piso     │ Tipo Depto │ (i,h)        │ Unid │ Área │ Área     │ Área        │ Perímetro   │ Profundidad │")
    println("│        │          │            │              │      │ Dpto │ Terraza  │ Pasillo     │ Strip       │ Strip       │")
    println("├────────┼──────────┼────────────┼──────────────┼──────┼──────┼──────────┼─────────────┼─────────────┼─────────────┤")

    for (strip, profundidad) in sort(collect(results["H_s"]))
        perimetro_pp = get(results["perimetro_strip_primer_piso"], strip, 0.0)
        perimetro_ps = get(results["perimetro_strip_pisos_superiores"], strip, 0.0)

        all_rows = []

        for (key, tipo_label, piso_label) in [
            ("num_deptos_reg_primer_piso", "Regular", "1° Piso"),
            ("num_deptos_corner_primer_piso", "Corner", "1° Piso"),
            ("num_deptos_d_corner_primer_piso", "Double Corner", "1° Piso"),
            ("num_deptos_reg_por_piso_superior", "Regular", "Pisos Sup."),
            ("num_deptos_corner_por_piso_superior", "Corner", "Pisos Sup."),
            ("num_deptos_d_corner_por_piso_superior", "Double Corner", "Pisos Sup.")
        ]
            strip_deptos = filter(p -> p[1][1] == strip, collect(get(results, key, Dict())))
            for ((s, i, h), count) in strip_deptos
                perimetro = piso_label == "1° Piso" ? perimetro_pp : perimetro_ps
                push!(all_rows, (strip, piso_label, tipo_label, i, h, count, vec_area_i[i], vec_area_t[i], vec_area_p[i], perimetro, profundidad))
            end
        end

        for (idx, (s, piso, tipo, i, h, count, area_int, area_terr, area_pas, perim, prof)) in enumerate(all_rows)
            strip_col = idx == 1 ? lpad(s, 6) : "      "
            perim_col = idx == 1 ? lpad(round(perim, digits=1), 9) : "         "
            prof_col = idx == 1 ? lpad(round(prof, digits=1), 9) : "         "

            println("│ $(strip_col) │ $(rpad(piso, 8)) │ $(rpad(tipo, 10)) │ ($(lpad(i,2)),$(lpad(h,2)))      │ $(lpad(round(Int, count), 4)) │ $(lpad(round(area_int, digits=1), 4)) │ $(lpad(round(area_terr, digits=1), 8)) │ $(lpad(round(area_pas, digits=1), 11)) │ $(perim_col) m² │ $(prof_col) m │")
        end

        if strip < maximum(keys(results["H_s"]))
            println("├────────┼──────────┼────────────┼──────────────┼──────┼──────┼──────────┼─────────────┼─────────────┼─────────────┤")
        end
    end

    println("└────────┴──────────┴────────────┴──────────────┴──────┴──────┴──────────┴─────────────┴─────────────┴─────────────┘")
    println("\n" * "="^140)
end
