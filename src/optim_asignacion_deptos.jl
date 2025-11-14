using JuMP
using HiGHS

"""
    optim_asignacion_deptos(W, H, num_strips, vec_w_i, mat_h_ip, mat_corner_h, mat_d_corner_h, vec_area_i, vec_area_p, mat_area_ip, mat_area_ipn, mat_h_ipn, area_nucleo_depto, vec_w_t, vec_h_t, vec_area_t, mat_exposicion, mat_exposicion_corner, mat_exposicion_d_corner, min_deptos, max_deptos, num_pisos, max_constructibilidad)

Optimiza la asignación de departamentos en strips horizontales para maximizar superficie total.

# Argumentos
- `W::Float64`: Ancho del edificio (m)
- `H::Float64`: Altura total del edificio (m)
- `num_strips::Int`: Número de strips horizontales
- `vec_w_i`: Vector de anchos por tipo de departamento
- `mat_h_ip`: Matriz de alturas [k,j] para departamentos regulares (incluye pasillo)
- `mat_corner_h`: Matriz de alturas [k,j] para departamentos esquina
- `mat_d_corner_h`: Matriz de alturas [k,j] para departamentos doble esquina
- `vec_area_i`: Vector de áreas interiores por tipo de departamento
- `vec_area_p`: Vector de áreas de pasillo por ancho
- `mat_area_ip`: Matriz de áreas [k,j] para departamentos regulares (interior + pasillo)
- `mat_area_ipn`: Matriz de áreas [k,j] para departamentos núcleo (interior + pasillo + núcleo)
- `mat_h_ipn`: Matriz de alturas [k,j] para departamentos núcleo
- `area_nucleo_depto::Float64`: Área adicional para departamentos tipo núcleo (m²)
- `vec_w_t`: Vector de anchos de terraza por tipo
- `vec_h_t`: Vector de alturas de terraza por tipo
- `vec_area_t`: Vector de áreas de terraza por tipo
- `mat_exposicion`: Matriz de perímetros [k,j] para departamentos regulares
- `mat_exposicion_corner`: Matriz de perímetros [k,j] para departamentos esquina
- `mat_exposicion_d_corner`: Matriz de perímetros [k,j] para departamentos doble esquina
- `min_deptos::Int`: Número mínimo de departamentos totales
- `max_deptos::Int`: Número máximo de departamentos totales
- `num_pisos::Int`: Número total de pisos del edificio
- `max_constructibilidad`: Constructibilidad máxima permitida (m²)
"""
function optim_asignacion_deptos(
    W::Float64,
    H::Float64,
    num_strips::Int,
    vec_w_i, 
    mat_h_ip, mat_corner_h, mat_d_corner_h,
    vec_area_i, vec_area_p, mat_area_ip,
    mat_area_ipn, mat_h_ipn, area_nucleo_depto,
    vec_w_t, vec_h_t, vec_area_t,
    mat_exposicion, mat_exposicion_corner, mat_exposicion_d_corner,
    min_deptos::Int,
    max_deptos::Int,
    num_pisos,
    max_constructibilidad)

    flag_dfl2 = true

    num_pisos_superiores = num_pisos - 1

    num_areas_deptos = length(vec_area_i)
    K = 1:num_areas_deptos

    num_widths = size(mat_h_ip, 2)
    J = 1:num_widths

    model = Model(HiGHS.Optimizer)
    set_silent(model)
    set_time_limit_sec(model, 300.0)
    set_optimizer_attribute(model, "mip_rel_gap", 0.01)
    set_optimizer_attribute(model, "presolve", "on")

    S = 1:num_strips

    """
    Decision Variables:
    - H_s: Depth of each strip s (continuous, non-negative)
    - num_deptos_primer_piso: Number of regular apartments in first floor strip s, type i, height j (integer)
    - num_deptos_corner_primer_piso: Number of corner apartments in first floor strip s, type i, height j (integer)
    - num_deptos_d_corner_primer_piso: Number of double corner apartments in first floor strip s, type i, height j (integer)
    - area_comun_primer_piso: Common area for first floor (continuous, non-negative)
    - num_deptos_por_piso_superior: Number of regular apartments in upper floor strip s, type i, height j (integer)
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
    max_z_bounds = 20
    @variables(model, begin
        H_s[s in S] >= 0

        0 <= num_deptos_primer_piso[s in S, k in K, j in J] <= max_z_bounds, Int
        0 <= num_deptos_nucleo_primer_piso[s in S, k in K, j in J] <= max_z_bounds, Int
        0 <= num_deptos_corner_primer_piso[s in S, k in K, j in J] <= max_z_bounds, Int
        0 <= num_deptos_d_corner_primer_piso[s in S, k in K, j in J] <= max_z_bounds, Int
        area_comun_primer_piso >= 0

        0 <= num_deptos_por_piso_superior[s in S, k in K, j in J] <= max_z_bounds, Int
        0 <= num_deptos_nucleo_por_piso_superior[s in S, k in K, j in J] <= max_z_bounds, Int
        0 <= num_deptos_corner_por_piso_superior[s in S, k in K, j in J] <= max_z_bounds, Int
        0 <= num_deptos_d_corner_por_piso_superior[s in S, k in K, j in J] <= max_z_bounds, Int
        area_comun_por_piso_superior >= 0

        x[s in S, k in K, j in J], Bin
        x_n[s in S, k in K, j in J], Bin
        x_c[s in S, k in K, j in J], Bin
        x_cc[s in S, k in K, j in J], Bin

        y_c[s in S], Bin
        y_cc[s in S], Bin

        z[k in K], Bin       # Global indicator: apartment size k is used anywhere (regular)
        z_n[k in K], Bin     # Global indicator: apartment size k is used anywhere (nucleo)
        z_c[k in K], Bin     # Global indicator: apartment size k is used anywhere (corner)
        z_cc[k in K], Bin    # Global indicator: apartment size k is used anywhere (double corner)

        descuento_dfl2 >= 0  # DFL2 discount for social housing (up to 20% of useful area or total common area)
        area_no_utilizada_primer_piso >= 0          # Unused footprint area on first floor (m²)
        area_no_utilizada_por_piso_superior >= 0    # Unused footprint area per upper floor (m²)
    end)

    
    @expressions(model, begin
        # Total common area across all floors
        area_comun_total, area_comun_primer_piso + area_comun_por_piso_superior * num_pisos_superiores

        # Total unused footprint area across all floors
        area_no_utilizada, area_no_utilizada_primer_piso + area_no_utilizada_por_piso_superior * num_pisos_superiores

        # Total interior area for first floor apartments
        area_interior_primer_piso, sum((num_deptos_primer_piso[s,k,j] +
             num_deptos_nucleo_primer_piso[s,k,j] +
             num_deptos_corner_primer_piso[s,k,j] +
             num_deptos_d_corner_primer_piso[s,k,j]) * vec_area_i[k] for s in S, k in K, j in J)
        
        # Interior area per upper floor 
        area_interior_por_piso_superior, sum((num_deptos_por_piso_superior[s,k,j] +
             num_deptos_nucleo_por_piso_superior[s,k,j] +
             num_deptos_corner_por_piso_superior[s,k,j] +
             num_deptos_d_corner_por_piso_superior[s,k,j]) * vec_area_i[k] for s in S, k in K, j in J)

        # Total interior area for entire building
        area_interior_total, area_interior_primer_piso + area_interior_por_piso_superior * num_pisos_superiores

        # Total terrace area for first floor apartments
        area_terraza_primer_piso, sum((num_deptos_primer_piso[s,k,j] +
             num_deptos_nucleo_primer_piso[s,k,j] +
             num_deptos_corner_primer_piso[s,k,j] +
             num_deptos_d_corner_primer_piso[s,k,j]) * vec_area_t[k] for s in S, k in K, j in J)

        # Terrace area per upper floor
        area_terraza_por_piso_superior, sum((num_deptos_por_piso_superior[s,k,j] +
             num_deptos_nucleo_por_piso_superior[s,k,j] +
             num_deptos_corner_por_piso_superior[s,k,j] +
             num_deptos_d_corner_por_piso_superior[s,k,j]) * vec_area_t[k] for s in S, k in K, j in J)

        # Total terrace area for entire building
        area_terraza_total, area_terraza_primer_piso + area_terraza_por_piso_superior * num_pisos_superiores

        # Useful area for first floor (interior + 50% of terrace)
        area_util_primer_piso, area_interior_primer_piso + area_terraza_primer_piso / 2

        # Useful area per upper floor (interior + 50% of terrace)
        area_util_por_piso_superior, area_interior_por_piso_superior + area_terraza_por_piso_superior / 2

        # Total useful area for entire building
        area_util_total, area_util_primer_piso + area_util_por_piso_superior * num_pisos_superiores

        # Total hallway area for first floor apartments
        area_pasillo_primer_piso, sum((num_deptos_primer_piso[s,k,j] + num_deptos_nucleo_primer_piso[s,k,j]) * vec_area_p[j] for s in S, k in K, j in J)

        # Hallway area per upper floor
        area_pasillo_por_piso_superior, sum((num_deptos_por_piso_superior[s,k,j] + num_deptos_nucleo_por_piso_superior[s,k,j]) * vec_area_p[j] for s in S, k in K, j in J)

        # Total hallway area for entire building
        area_pasillo_total, area_pasillo_primer_piso + area_pasillo_por_piso_superior * num_pisos_superiores

        # Nucleo area for first floor (additional area per nucleo apartment)
        area_nucleo_primer_piso, sum(num_deptos_nucleo_primer_piso[s,k,j] * area_nucleo_depto for s in S, k in K, j in J)

        # Nucleo area per upper floor
        area_nucleo_por_piso_superior, sum(num_deptos_nucleo_por_piso_superior[s,k,j] * area_nucleo_depto for s in S, k in K, j in J)

        # Total nucleo area for entire building
        area_nucleo_total, area_nucleo_primer_piso + area_nucleo_por_piso_superior * num_pisos_superiores

        # Total SNT area (interior + terrace + common areas)
        area_snt, area_interior_total + area_terraza_total + area_comun_total

        # Total count of all apartment types across all strips and floors
        deptos_total, (sum(num_deptos_primer_piso[s,k,j] for s in S, k in K, j in J) +
            sum(num_deptos_nucleo_primer_piso[s,k,j] for s in S, k in K, j in J) +
            sum(num_deptos_corner_primer_piso[s,k,j] for s in S, k in K, j in J) +
            sum(num_deptos_d_corner_primer_piso[s,k,j] for s in S, k in K, j in J)) +
            (sum(num_deptos_por_piso_superior[s,k,j] for s in S, k in K, j in J) +
            sum(num_deptos_nucleo_por_piso_superior[s,k,j] for s in S, k in K, j in J) +
            sum(num_deptos_corner_por_piso_superior[s,k,j] for s in S, k in K, j in J) +
            sum(num_deptos_d_corner_por_piso_superior[s,k,j] for s in S, k in K, j in J)) * num_pisos_superiores

    end)


    @constraints(model, begin

        # First floor footprint must equal building footprint (all areas sum to W × j)
        constraint_1, area_interior_primer_piso + area_terraza_primer_piso + area_nucleo_primer_piso + area_comun_primer_piso + area_no_utilizada_primer_piso == W * H

        # Upper floor footprint must equal building footprint (all areas sum to W × j)
        constraint_2, area_interior_por_piso_superior + area_terraza_por_piso_superior + area_nucleo_por_piso_superior + area_comun_por_piso_superior + area_no_utilizada_por_piso_superior == W * H

        # Common area for first floor must include at least all hallway areas
        constraint_3, area_comun_primer_piso >= area_pasillo_primer_piso + area_nucleo_primer_piso

        # Common area for upper floors must include at least all hallway areas
        constraint_4, area_comun_por_piso_superior >= area_pasillo_por_piso_superior + area_nucleo_por_piso_superior

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

        # Exactly 2 corner apartments per strip if corner type is used
        constraint_12[s in S], sum(num_deptos_corner_por_piso_superior[s,k,j] for k in K, j in J) == 2 * y_c[s]

        # Exactly 1 double corner apartment per strip if double corner type is used
        constraint_13[s in S], sum(num_deptos_d_corner_por_piso_superior[s,k,j] for k in K, j in J) == y_cc[s]

        # Allows only one double corner apartment or several regular apartments, not both
        constraint_14[s in S], sum(x_cc[s,k,j] + x[s,k,j] + x_n[s,k,j] for k in K, j in J) <= y_cc[s] + (1 - y_cc[s]) * max_deptos

        # Strip can use either corner or double corner configuration, not both simultaneously
        constraint_15[s in S], y_c[s] + y_cc[s] <= 1

        # Total apartment count must be within specified bounds
        constraint_16, min_deptos <= deptos_total <= max_deptos

        # Sum of all strip depths cannot exceed building depth
        constraint_17, sum(H_s[s] for s in S) <= H

        # Each strip must have minimum depth
        constraint_18[s in S], H_s[s] >= 12.5

        # Apartment height (interior + terrace) must fit within strip depth for each apartment type
        constraint_19[s in S, k in K, j in J], x[s,k,j] * (mat_h_ip[k,j] + vec_h_t[k]) <= H_s[s]        # Regular apartments
        constraint_20[s in S, k in K, j in J], x_n[s,k,j] * (mat_h_ipn[k,j] + vec_h_t[k]) <= H_s[s]      # Nucleo apartments
        constraint_21[s in S, k in K, j in J], x_c[s,k,j] * (mat_corner_h[k,j] + vec_h_t[k]) <= H_s[s]   # Corner apartments
        constraint_22[s in S, k in K, j in J], x_cc[s,k,j] * (mat_d_corner_h[k,j] + vec_h_t[k]) <= H_s[s] # Double corner apartments

        # Total apartment area per strip cannot exceed strip footprint (W x H_s)
        constraint_23[s in S], sum(num_deptos_por_piso_superior[s,k,j] * (mat_area_ip[k,j] + vec_area_t[k]) +
             num_deptos_nucleo_por_piso_superior[s,k,j] * (mat_area_ipn[k,j] + vec_area_t[k]) +
             (num_deptos_corner_por_piso_superior[s,k,j] + num_deptos_d_corner_por_piso_superior[s,k,j]) * (vec_area_i[k] + vec_area_t[k]) 
              for k in K, j in J) <= W * H_s[s]

        # Apartment count is positive only if apartment type is selected (Big-M constraint linking binary and integer variables)
        constraint_24[s in S, k in K, j in J], num_deptos_por_piso_superior[s,k,j] <= max_deptos * x[s,k,j]           # Regular apartments
        constraint_25[s in S, k in K, j in J], num_deptos_nucleo_por_piso_superior[s,k,j] <= max_deptos * x_n[s,k,j]  # Nucleo apartments
        constraint_26[s in S, k in K, j in J], num_deptos_corner_por_piso_superior[s,k,j] <= max_deptos * x_c[s,k,j]  # Corner apartments
        constraint_27[s in S, k in K, j in J], num_deptos_d_corner_por_piso_superior[s,k,j] <= max_deptos * x_cc[s,k,j] # Double corner apartments

        # Link local binary x[s,k,j] to global binary z[k] (apartment size k used anywhere in building)
        constraint_28[k in K], sum(x[s,k,j] for s in S, j in J) <= max_deptos * z[k]      # Regular apartments
        constraint_29[k in K], sum(x_n[s,k,j] for s in S, j in J) <= max_deptos * z_n[k]  # Nucleo apartments
        constraint_30[k in K], sum(x_c[s,k,j] for s in S, j in J) <= max_deptos * z_c[k]  # Corner apartments
        constraint_31[k in K], sum(x_cc[s,k,j] for s in S, j in J) <= max_deptos * z_cc[k] # Double corner apartments


        # Total apartment widths per strip cannot exceed building width W
        constraint_32[s in S], sum((num_deptos_por_piso_superior[s,k,j] +
            num_deptos_nucleo_por_piso_superior[s,k,j] +
            num_deptos_corner_por_piso_superior[s,k,j] +
            num_deptos_d_corner_por_piso_superior[s,k,j]) * vec_w_i[k] for k in K, j in J) <= W

        # Sum of apartment perimeters must cover strip perimeter with 5m tolerance
        constraint_33[s in S],
            sum(num_deptos_por_piso_superior[s,k,j] * mat_exposicion[k,j] for k in K, j in J) +
            sum(num_deptos_nucleo_por_piso_superior[s,k,j] * mat_exposicion[k,j] for k in K, j in J) +
            sum(num_deptos_corner_por_piso_superior[s,k,j] * mat_exposicion_corner[k,j] for k in K, j in J) +
            sum(num_deptos_d_corner_por_piso_superior[s,k,j] * mat_exposicion_d_corner[k,j] for k in K, j in J) >= 2*H_s[s] + W - 5
            
        # First floor apartment counts cannot exceed upper floor counts (first floor is subset of upper floors)
        constraint_34[s in S, k in K, j in J], num_deptos_primer_piso[s,k,j] <= num_deptos_por_piso_superior[s,k,j]             # Regular apartments
        constraint_35[s in S, k in K, j in J], num_deptos_nucleo_primer_piso[s,k,j] <= num_deptos_nucleo_por_piso_superior[s,k,j]  # Nucleo apartments
        constraint_36[s in S, k in K, j in J], num_deptos_corner_primer_piso[s,k,j] <= num_deptos_corner_por_piso_superior[s,k,j]  # Corner apartments
        constraint_37[s in S, k in K, j in J], num_deptos_d_corner_primer_piso[s,k,j] <= num_deptos_d_corner_por_piso_superior[s,k,j] # Double corner apartments
    end)

    # Nucleo apartment constraints
    if area_nucleo_depto > 0
        # Require exactly 2 nucleo apartments per strip (first floor)
        @constraint(model, [s in S], sum(num_deptos_nucleo_primer_piso[s,k,j] for k in K, j in J) == 2)
        # Require exactly 2 nucleo apartments per strip (upper floors)
        @constraint(model, [s in S], sum(num_deptos_nucleo_por_piso_superior[s,k,j] for k in K, j in J) == 2)
    else
        # When area_nucleo_depto = 0, nucleo apartments are identical to regular apartments
        # Force all nucleo binaries to 0 (use regular apartments instead)
        @constraint(model, [s in S, k in K, j in J], x_n[s,k,j] == 0)
    end

    # Diversity constraints: prevent mixing very different apartment sizes (ratio > 2.5)
    for k1 in K, k2 in K
        if vec_area_i[k1] < vec_area_i[k2]  # Avoid duplicate constraints
            if vec_area_i[k2] > vec_area_i[k1] * 2.0
                @constraint(model, z[k1] + z[k2] <= 1)       # Regular apartments
                @constraint(model, z_n[k1] + z_n[k2] <= 1)   # Nucleo apartments
                @constraint(model, z_c[k1] + z_c[k2] <= 1)   # Corner apartments
                @constraint(model, z_cc[k1] + z_cc[k2] <= 1) # Double corner apartments
            end
        end
    end


    # Maximize total apartment interior area
    @objective(model, Max, area_util_total)

    # Print MIP model statistics
    println("\n" * "="^60)
    println("MIP MODEL SIZE")
    println("="^60)
    println("Total variables:     ", num_variables(model))
    println("  - Binary:          ", sum(is_binary(v) for v in all_variables(model)))
    println("  - Integer:         ", sum(is_integer(v) && !is_binary(v) for v in all_variables(model)))
    println("  - Continuous:      ", sum(!is_integer(v) for v in all_variables(model)))
    println("Total constraints:   ", num_constraints(model; count_variable_in_set_constraints=true))
    println("  - Linear:          ", sum(num_constraints(model, F, S) for (F,S) in list_of_constraint_types(model) if F == AffExpr || F == VariableRef))
    println("="^60 * "\n")

    optimize!(model)


    
    results = Dict{String,Any}()
    results["status"] = termination_status(model)
    results["solve_time"] = solve_time(model)
    results["num_deptos_por_piso_superior"] = Dict{Tuple{Int,Int,Int},Float64}()
    results["num_deptos_nucleo_por_piso_superior"] = Dict{Tuple{Int,Int,Int},Float64}()
    results["num_deptos_corner_por_piso_superior"] = Dict{Tuple{Int,Int,Int},Float64}()
    results["num_deptos_d_corner_por_piso_superior"] = Dict{Tuple{Int,Int,Int},Float64}()
    results["num_deptos_primer_piso"] = Dict{Tuple{Int,Int,Int},Float64}()
    results["num_deptos_nucleo_primer_piso"] = Dict{Tuple{Int,Int,Int},Float64}()
    results["num_deptos_corner_primer_piso"] = Dict{Tuple{Int,Int,Int},Float64}()
    results["num_deptos_d_corner_primer_piso"] = Dict{Tuple{Int,Int,Int},Float64}()
    results["x"] = Dict{Tuple{Int,Int,Int},Int}()
    results["x_n"] = Dict{Tuple{Int,Int,Int},Int}()
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
    results["vec_w_i"] = vec_w_i
    results["mat_h_ip"] = mat_h_ip
    results["mat_corner_h"] = mat_corner_h
    results["mat_d_corner_h"] = mat_d_corner_h
    results["mat_h_ipn"] = mat_h_ipn
    results["area_nucleo_depto"] = area_nucleo_depto
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

            perimetro_s_pp = sum(value(num_deptos_primer_piso[s,k,j]) * mat_exposicion[k,j] for k in K, j in J) +
                          sum(value(num_deptos_nucleo_primer_piso[s,k,j]) * mat_exposicion[k,j] for k in K, j in J) +
                          sum(value(num_deptos_corner_primer_piso[s,k,j]) * mat_exposicion_corner[k,j] for k in K, j in J) +
                          sum(value(num_deptos_d_corner_primer_piso[s,k,j]) * mat_exposicion_d_corner[k,j] for k in K, j in J)
            results["perimetro_strip_primer_piso"][s] = perimetro_s_pp

            apartment_area_s_pp = sum(value(num_deptos_primer_piso[s,k,j]) * vec_area_i[k] for k in K, j in J) +
                               sum(value(num_deptos_nucleo_primer_piso[s,k,j]) * vec_area_i[k] for k in K, j in J) +
                               sum(value(num_deptos_corner_primer_piso[s,k,j]) * vec_area_i[k] for k in K, j in J) +
                               sum(value(num_deptos_d_corner_primer_piso[s,k,j]) * vec_area_i[k] for k in K, j in J)
            results["apartment_area_strip_primer_piso"][s] = apartment_area_s_pp

            terrace_area_s_pp = sum(value(num_deptos_primer_piso[s,k,j]) * vec_area_t[k] for k in K, j in J) +
                             sum(value(num_deptos_nucleo_primer_piso[s,k,j]) * vec_area_t[k] for k in K, j in J) +
                             sum(value(num_deptos_corner_primer_piso[s,k,j]) * vec_area_t[k] for k in K, j in J) +
                             sum(value(num_deptos_d_corner_primer_piso[s,k,j]) * vec_area_t[k] for k in K, j in J)
            results["terrace_area_strip_primer_piso"][s] = terrace_area_s_pp

            pasillo_area_s_pp = sum(value(num_deptos_primer_piso[s,k,j]) * vec_area_p[j] for k in K, j in J) +
                             sum(value(num_deptos_nucleo_primer_piso[s,k,j]) * vec_area_p[j] for k in K, j in J) +
                             sum(value(num_deptos_corner_primer_piso[s,k,j]) * vec_area_p[j] for k in K, j in J) +
                             sum(value(num_deptos_d_corner_primer_piso[s,k,j]) * vec_area_p[j] for k in K, j in J)
            results["pasillo_area_strip_primer_piso"][s] = pasillo_area_s_pp

            perimetro_s_ps = sum(value(num_deptos_por_piso_superior[s,k,j]) * mat_exposicion[k,j] for k in K, j in J) +
                          sum(value(num_deptos_nucleo_por_piso_superior[s,k,j]) * mat_exposicion[k,j] for k in K, j in J) +
                          sum(value(num_deptos_corner_por_piso_superior[s,k,j]) * mat_exposicion_corner[k,j] for k in K, j in J) +
                          sum(value(num_deptos_d_corner_por_piso_superior[s,k,j]) * mat_exposicion_d_corner[k,j] for k in K, j in J)
            results["perimetro_strip_pisos_superiores"][s] = perimetro_s_ps

            apartment_area_s_ps = sum(value(num_deptos_por_piso_superior[s,k,j]) * vec_area_i[k] for k in K, j in J) +
                               sum(value(num_deptos_nucleo_por_piso_superior[s,k,j]) * vec_area_i[k] for k in K, j in J) +
                               sum(value(num_deptos_corner_por_piso_superior[s,k,j]) * vec_area_i[k] for k in K, j in J) +
                               sum(value(num_deptos_d_corner_por_piso_superior[s,k,j]) * vec_area_i[k] for k in K, j in J)
            results["apartment_area_strip_pisos_superiores"][s] = apartment_area_s_ps

            terrace_area_s_ps = sum(value(num_deptos_por_piso_superior[s,k,j]) * vec_area_t[k] for k in K, j in J) +
                             sum(value(num_deptos_nucleo_por_piso_superior[s,k,j]) * vec_area_t[k] for k in K, j in J) +
                             sum(value(num_deptos_corner_por_piso_superior[s,k,j]) * vec_area_t[k] for k in K, j in J) +
                             sum(value(num_deptos_d_corner_por_piso_superior[s,k,j]) * vec_area_t[k] for k in K, j in J)
            results["terrace_area_strip_pisos_superiores"][s] = terrace_area_s_ps

            pasillo_area_s_ps = sum(value(num_deptos_por_piso_superior[s,k,j]) * vec_area_p[j] for k in K, j in J) +
                             sum(value(num_deptos_nucleo_por_piso_superior[s,k,j]) * vec_area_p[j] for k in K, j in J) +
                             sum(value(num_deptos_corner_por_piso_superior[s,k,j]) * vec_area_p[j] for k in K, j in J) +
                             sum(value(num_deptos_d_corner_por_piso_superior[s,k,j]) * vec_area_p[j] for k in K, j in J)
            results["pasillo_area_strip_pisos_superiores"][s] = pasillo_area_s_ps

            for k in K, j in J
                for (var, key, threshold, is_binary) in [
                    (num_deptos_por_piso_superior[s,k,j], "num_deptos_por_piso_superior", 0.001, false),
                    (num_deptos_nucleo_por_piso_superior[s,k,j], "num_deptos_nucleo_por_piso_superior", 0.001, false),
                    (num_deptos_corner_por_piso_superior[s,k,j], "num_deptos_corner_por_piso_superior", 0.001, false),
                    (num_deptos_d_corner_por_piso_superior[s,k,j], "num_deptos_d_corner_por_piso_superior", 0.001, false),
                    (num_deptos_primer_piso[s,k,j], "num_deptos_primer_piso", 0.001, false),
                    (num_deptos_nucleo_primer_piso[s,k,j], "num_deptos_nucleo_primer_piso", 0.001, false),
                    (num_deptos_corner_primer_piso[s,k,j], "num_deptos_corner_primer_piso", 0.001, false),
                    (num_deptos_d_corner_primer_piso[s,k,j], "num_deptos_d_corner_primer_piso", 0.001, false),
                    (x[s,k,j], "x", 0.5, true),
                    (x_n[s,k,j], "x_n", 0.5, true),
                    (x_c[s,k,j], "x_c", 0.5, true),
                    (x_cc[s,k,j], "x_cc", 0.5, true)]

                    val = value(var)
                    if val > threshold
                        results[key][(s,k,j)] = is_binary ? 1 : val
                    end
                end
            end
        end

        deptos_primer_piso = sum(sum(values(results[k])) for k in ["num_deptos_primer_piso", "num_deptos_nucleo_primer_piso", "num_deptos_corner_primer_piso", "num_deptos_d_corner_primer_piso"])
        deptos_pisos_superiores = sum(sum(values(results[k])) for k in ["num_deptos_por_piso_superior", "num_deptos_nucleo_por_piso_superior", "num_deptos_corner_por_piso_superior", "num_deptos_d_corner_por_piso_superior"])

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

        vec_area_i_local = get(results, "vec_area_i", [])
        vec_w_i_local = get(results, "vec_w_i", [])
        num_strips = length(get(results, "H_s", Dict()))
        area_nucleo_depto_local = get(results, "area_nucleo_depto", 5.0)

        nucleo_primer_piso_dict = get(results, "num_deptos_nucleo_primer_piso", Dict())
        nucleo_por_piso_superior_dict = get(results, "num_deptos_nucleo_por_piso_superior", Dict())

        area_nucleo_pp = sum(get(nucleo_primer_piso_dict, (s,k,j), 0.0) * area_nucleo_depto_local for s in 1:num_strips for k in 1:length(vec_area_i_local) for j in 1:length(vec_w_i_local))
        area_nucleo_ps = sum(get(nucleo_por_piso_superior_dict, (s,k,j), 0.0) * area_nucleo_depto_local for s in 1:num_strips for k in 1:length(vec_area_i_local) for j in 1:length(vec_w_i_local))
        area_nucleo_total = area_nucleo_pp + area_nucleo_ps * num_pisos_sup

        println("┌─────────────────────┬──────────────────┬──────────────────┬──────────────────┐")
        println("│                     │  Primer Piso     │  Piso Superior   │  Total Edificio  │")
        println("│                     │    (1 piso)      │   (por piso)     │   ($(num_pisos_total) pisos)      │")
        println("├─────────────────────┼──────────────────┼──────────────────┼──────────────────┤")
        println("│ Área Interior       │ $(lpad(round(area_interior_pp, digits=1), 12)) m² │ $(lpad(round(area_interior_ps, digits=1), 12)) m² │ $(lpad(round(area_interior_pp + area_interior_ps * num_pisos_sup, digits=1), 12)) m² │")
        println("│ Área Terraza        │ $(lpad(round(area_terraza_pp, digits=1), 12)) m² │ $(lpad(round(area_terraza_ps, digits=1), 12)) m² │ $(lpad(round(area_terraza_pp + area_terraza_ps * num_pisos_sup, digits=1), 12)) m² │")
        println("│ Área Común          │ $(lpad(round(area_comun_pp, digits=1), 12)) m² │ $(lpad(round(area_comun_ps, digits=1), 12)) m² │ $(lpad(round(area_comun_pp + area_comun_ps * num_pisos_sup, digits=1), 12)) m² │")
        println("│   - Área Pasillo    │ $(lpad(round(area_pasillo_pp, digits=1), 12)) m² │ $(lpad(round(area_pasillo_ps, digits=1), 12)) m² │ $(lpad(round(area_pasillo_pp + area_pasillo_ps * num_pisos_sup, digits=1), 12)) m² │")
        println("│   - Área Núcleo     │ $(lpad(round(area_nucleo_pp, digits=1), 12)) m² │ $(lpad(round(area_nucleo_ps, digits=1), 12)) m² │ $(lpad(round(area_nucleo_total, digits=1), 12)) m² │")
        println("│   - Otros espacios  │ $(lpad(round(area_comun_pp - area_pasillo_pp - area_nucleo_pp, digits=1), 12)) m² │ $(lpad(round(area_comun_ps - area_pasillo_ps - area_nucleo_ps, digits=1), 12)) m² │ $(lpad(round((area_comun_pp - area_pasillo_pp - area_nucleo_pp) + (area_comun_ps - area_pasillo_ps - area_nucleo_ps) * num_pisos_sup, digits=1), 12)) m² │")
        println("├─────────────────────┼──────────────────┼──────────────────┼──────────────────┤")
        println("│ Área Losa SNT       │ $(lpad(round(area_total_losa_pp, digits=1), 12)) m² │ $(lpad(round(area_total_losa_ps, digits=1), 12)) m² │ $(lpad(round(area_total_losa_edificio, digits=1), 12)) m² │")
        println("│ Área No Utilizada   │ $(lpad(round(area_no_utilizada_pp, digits=1), 12)) m² │ $(lpad(round(area_no_utilizada_ps, digits=1), 12)) m² │ $(lpad(round(area_no_utilizada_total, digits=1), 12)) m² │")
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
        println("    - Área Núcleo: espacio adicional ($(area_nucleo_depto_local) m²) por cada departamento tipo núcleo")
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
    vec_w_i = results["vec_w_i"]
    mat_h_ip = results["mat_h_ip"]
    mat_h_ipn = results["mat_h_ipn"]
    mat_corner_h = results["mat_corner_h"]
    mat_d_corner_h = results["mat_d_corner_h"]
    area_nucleo_depto_local = results["area_nucleo_depto"]

    for (strip, profundidad) in sort(collect(results["H_s"]))
        perimetro_pp = get(results["perimetro_strip_primer_piso"], strip, 0.0)
        perimetro_ps = get(results["perimetro_strip_pisos_superiores"], strip, 0.0)

        all_deptos = []

        for (key, tipo_label, piso_label) in [
            ("num_deptos_primer_piso", "Regular", "1° Piso"),
            ("num_deptos_nucleo_primer_piso", "Núcleo", "1° Piso"),
            ("num_deptos_corner_primer_piso", "Corner", "1° Piso"),
            ("num_deptos_d_corner_primer_piso", "Double Corner", "1° Piso"),
            ("num_deptos_por_piso_superior", "Regular", "Pisos Sup."),
            ("num_deptos_nucleo_por_piso_superior", "Núcleo", "Pisos Sup."),
            ("num_deptos_corner_por_piso_superior", "Corner", "Pisos Sup."),
            ("num_deptos_d_corner_por_piso_superior", "Double Corner", "Pisos Sup.")
        ]
            strip_deptos = filter(p -> p[1][1] == strip, collect(get(results, key, Dict())))
            for ((s, k, j), count) in strip_deptos
                perimetro = piso_label == "1° Piso" ? perimetro_pp : perimetro_ps
                ancho = vec_w_i[j]
                area_interior = vec_area_i[k]
                area_terraza = vec_area_t[k]
                area_pasillo = vec_area_p[j]

                if tipo_label == "Regular"
                    alto = mat_h_ip[k,j]
                    area_nucleo = 0.0
                    area_total = ancho * alto
                elseif tipo_label == "Núcleo"
                    alto = mat_h_ipn[k,j]
                    area_nucleo = area_nucleo_depto_local
                    area_total = ancho * alto
                elseif tipo_label == "Corner"
                    alto = mat_corner_h[k,j]
                    area_nucleo = 0.0
                    area_total = area_interior
                else
                    alto = mat_d_corner_h[k,j]
                    area_nucleo = 0.0
                    area_total = area_interior
                end

                push!(all_deptos, (piso_label, tipo_label, k, j, count, area_interior, area_pasillo, area_nucleo, area_terraza, area_total, ancho, alto, perimetro, profundidad))
            end
        end

        if !isempty(all_deptos)
            println("\n" * "━"^80)
            println("STRIP $(strip) │ Profundidad: $(round(profundidad, digits=1)) m │ Perímetro: $(round(perimetro_ps, digits=1)) m")
            println("━"^80)

            for (piso, tipo, k, j, count, area_int, area_pas, area_nuc, area_terr, area_tot, ancho, alto, _, _) in all_deptos
                println("\n┌────────────────────────────────────────────────────────────────┐")
                println("│ $(rpad(piso, 12)) │ $(rpad(tipo, 14)) │ ($(k),$(j)) │ Unidades: $(round(Int, count))  │")
                println("├────────────────────────────────────────────────────────────────┤")
                println("│ DIMENSIONES                                                    │")
                println("│   Ancho:                              $(lpad(round(ancho, digits=1), 8)) m       │")
                println("│   Profundidad:                        $(lpad(round(alto, digits=1), 8)) m       │")
                println("├────────────────────────────────────────────────────────────────┤")
                println("│ ÁREAS DEPARTAMENTO (Ancho × Profundidad)                      │")
                println("│   Interior:                           $(lpad(round(area_int, digits=1), 8)) m²      │")
                println("│   Pasillo:                            $(lpad(round(area_pas, digits=1), 8)) m²      │")
                if area_nuc > 0
                println("│   Núcleo:                             $(lpad(round(area_nuc, digits=1), 8)) m²      │")
                end
                area_suma = area_int + area_pas + area_nuc
                println("│   ─────────────────────────────────────────────────────────    │")
                println("│   Subtotal:                           $(lpad(round(area_suma, digits=1), 8)) m²      │")
                println("│   TOTAL (Ancho × Profundidad):        $(lpad(round(area_tot, digits=1), 8)) m²      │")
                println("│                                                                │")
                println("│ ÁREAS ADICIONALES (fuera del rectángulo)                      │")
                println("│   Terraza:                            $(lpad(round(area_terr, digits=1), 8)) m²      │")
                println("└────────────────────────────────────────────────────────────────┘")
            end
        end
    end
    println("\n" * "="^140)
end
