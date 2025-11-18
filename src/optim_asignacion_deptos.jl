using JuMP
using HiGHS

"""
Optimiza la asignación de departamentos en strips horizontales para maximizar superficie total.

# Argumentos
- `W::Float64`: Ancho del edificio (m)
- `H::Float64`: Altura total del edificio (m)
- `num_strips::Int`: Número de strips horizontales
- `vec_w_i`: Vector de anchos por tipo de departamento
- `mat_h_ip`: Matriz de alturas [k,j] para departamentos regulares (incluye pasillo)
- `mat_h_in`: Matriz de alturas [k,j] para departamentos esquina
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
- `mat_flag_feasible`: Matriz booleana [k,j] indicando combinaciones factibles (>0 = factible)
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
    mat_h_ip, mat_h_in, 
    vec_area_i, vec_area_p, vec_area_in, mat_area_ip,
    mat_area_ipn, mat_h_ipn, area_nucleo_depto,
    vec_w_t, vec_h_t, vec_area_t,
    mat_exposicion, mat_exposicion_corner, mat_exposicion_d_corner, mat_flag_feasible,
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

    KJ_feasible = [(k, j) for k in K, j in J if mat_flag_feasible[k, j] > 0]

    model = Model(HiGHS.Optimizer)
    # set_silent(model)
    set_time_limit_sec(model, 300.0)
    set_optimizer_attribute(model, "mip_rel_gap", 0.01)
    set_optimizer_attribute(model, "presolve", "on")

    S = 1:num_strips

    # Calculate tighter Big-M bound based on minimum width
    min_width = minimum(vec_w_i)
    max_apts_per_strip = floor(Int, W / min_width)

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
    @variables(model, begin
        H_s[s in S] >= 0

        0 <= num_deptos_primer_piso[s in S, (k, j) in KJ_feasible] <= max_deptos, Int
        0 <= num_deptos_nucleo_primer_piso[s in S, (k, j) in KJ_feasible] <= max_deptos, Int
        0 <= num_deptos_corner_primer_piso[s in S, (k, j) in KJ_feasible] <= 2, Int
        0 <= num_deptos_corner_nucleo_primer_piso[s in S, (k, j) in KJ_feasible] <= 2, Int
        0 <= num_deptos_d_corner_primer_piso[s in S, (k, j) in KJ_feasible] <= 1, Int
        0 <= num_deptos_d_corner_nucleo_primer_piso[s in S, (k, j) in KJ_feasible] <= 1, Int
        area_comun_primer_piso >= 0

        0 <= num_deptos_por_piso_superior[s in S, (k, j) in KJ_feasible] <= max_deptos, Int
        0 <= num_deptos_nucleo_por_piso_superior[s in S, (k, j) in KJ_feasible] <= max_deptos, Int
        0 <= num_deptos_corner_por_piso_superior[s in S, (k, j) in KJ_feasible] <= 2, Int
        0 <= num_deptos_corner_nucleo_por_piso_superior[s in S, (k, j) in KJ_feasible] <= 2, Int
        0 <= num_deptos_d_corner_por_piso_superior[s in S, (k, j) in KJ_feasible] <= 1, Int
        0 <= num_deptos_d_corner_nucleo_por_piso_superior[s in S, (k, j) in KJ_feasible] <= 1, Int
        area_comun_por_piso_superior >= 0

        x[s in S, (k, j) in KJ_feasible], Bin
        x_n[s in S, (k, j) in KJ_feasible], Bin
        x_c[s in S, (k, j) in KJ_feasible], Bin
        x_cn[s in S, (k, j) in KJ_feasible], Bin
        x_cc[s in S, (k, j) in KJ_feasible], Bin
        x_ccn[s in S, (k, j) in KJ_feasible], Bin

        y[s in S], Bin        # Binary indicator: strip s uses regular configuration
        y_c[s in S], Bin      # Binary indicator: strip s uses corner configuration
        y_cn[s in S], Bin     # Binary indicator: strip s uses corner nucleo configuration
        y_cc[s in S], Bin     # Binary indicator: strip s uses double corner configuration
        y_ccn[s in S], Bin    # Binary indicator: strip s uses double corner nucleo configuration
        y_n[s in S], Bin      # Binary indicator: strip s uses regular nucleo configuration

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
        area_interior_primer_piso, sum((num_deptos_primer_piso[s,(k,j)] +
             num_deptos_nucleo_primer_piso[s,(k,j)] +
             num_deptos_corner_primer_piso[s,(k,j)] +
             num_deptos_corner_nucleo_primer_piso[s,(k,j)] +
             num_deptos_d_corner_primer_piso[s,(k,j)] + 
             num_deptos_d_corner_nucleo_primer_piso[s,(k,j)]
             ) * vec_area_i[k] for s in S, (k, j) in KJ_feasible)

        # Interior area per upper floor
        area_interior_por_piso_superior, sum((num_deptos_por_piso_superior[s,(k,j)] +
             num_deptos_nucleo_por_piso_superior[s,(k,j)] +
             num_deptos_corner_por_piso_superior[s,(k,j)] +
             num_deptos_corner_nucleo_por_piso_superior[s,(k,j)] +
             num_deptos_d_corner_por_piso_superior[s,(k,j)] +
             num_deptos_d_corner_nucleo_por_piso_superior[s,(k,j)]
             ) * vec_area_i[k] for s in S, (k, j) in KJ_feasible)

        # Total interior area for entire building
        area_interior_total, area_interior_primer_piso + area_interior_por_piso_superior * num_pisos_superiores

        # Total terrace area for first floor apartments
        area_terraza_primer_piso, sum((num_deptos_primer_piso[s,(k,j)] +
             num_deptos_nucleo_primer_piso[s,(k,j)] +
             num_deptos_corner_primer_piso[s,(k,j)] +
             num_deptos_corner_nucleo_primer_piso[s,(k,j)] +
             num_deptos_d_corner_primer_piso[s,(k,j)] +
             num_deptos_d_corner_nucleo_primer_piso[s,(k,j)]
             ) * vec_area_t[k] for s in S, (k, j) in KJ_feasible)

        # Terrace area per upper floor
        area_terraza_por_piso_superior, sum((num_deptos_por_piso_superior[s,(k,j)] +
             num_deptos_nucleo_por_piso_superior[s,(k,j)] +
             num_deptos_corner_por_piso_superior[s,(k,j)] +
             num_deptos_corner_nucleo_por_piso_superior[s,(k,j)] +
             num_deptos_d_corner_por_piso_superior[s,(k,j)] +
             num_deptos_d_corner_nucleo_por_piso_superior[s,(k,j)]
             ) * vec_area_t[k] for s in S, (k, j) in KJ_feasible)

        # Total terrace area for entire building
        area_terraza_total, area_terraza_primer_piso + area_terraza_por_piso_superior * num_pisos_superiores

        # Useful area for first floor (interior + 50% of terrace)
        area_util_primer_piso, area_interior_primer_piso + area_terraza_primer_piso / 2

        # Useful area per upper floor (interior + 50% of terrace)
        area_util_por_piso_superior, area_interior_por_piso_superior + area_terraza_por_piso_superior / 2

        # Total useful area for entire building
        area_util_total, area_util_primer_piso + area_util_por_piso_superior * num_pisos_superiores

        # Total hallway area for first floor apartments
        area_pasillo_primer_piso, sum((num_deptos_primer_piso[s,(k,j)] + num_deptos_nucleo_primer_piso[s,(k,j)]) * vec_area_p[j] for s in S, (k, j) in KJ_feasible)

        # Hallway area per upper floor
        area_pasillo_por_piso_superior, sum((num_deptos_por_piso_superior[s,(k,j)] + num_deptos_nucleo_por_piso_superior[s,(k,j)]) * vec_area_p[j] for s in S, (k, j) in KJ_feasible)

        # Total hallway area for entire building
        area_pasillo_total, area_pasillo_primer_piso + area_pasillo_por_piso_superior * num_pisos_superiores

        # Nucleo area for first floor (additional area per nucleo apartment)
        area_nucleo_primer_piso, sum((num_deptos_nucleo_primer_piso[s,(k,j)] + 
                                      num_deptos_corner_nucleo_primer_piso[s,(k,j)] +
                                      num_deptos_d_corner_nucleo_primer_piso[s,(k,j)]) * area_nucleo_depto for s in S, (k, j) in KJ_feasible)

        # Nucleo area per upper floor
        area_nucleo_por_piso_superior, sum((num_deptos_nucleo_por_piso_superior[s,(k,j)] +
                                            num_deptos_corner_nucleo_por_piso_superior[s,(k,j)] +
                                            num_deptos_d_corner_nucleo_por_piso_superior[s,(k,j)]
                                            ) * area_nucleo_depto for s in S, (k, j) in KJ_feasible)

        # Total nucleo area for entire building
        area_nucleo_total, area_nucleo_primer_piso + area_nucleo_por_piso_superior * num_pisos_superiores

        # Total SNT area (interior + terrace + common areas)
        area_snt, area_interior_total + area_terraza_total + area_comun_total

        # Total count of all apartment types across all strips and floors
        deptos_total, (sum(num_deptos_primer_piso[s,(k,j)] for s in S, (k, j) in KJ_feasible) +
            sum(num_deptos_nucleo_primer_piso[s,(k,j)] for s in S, (k, j) in KJ_feasible) +
            sum(num_deptos_corner_primer_piso[s,(k,j)] for s in S, (k, j) in KJ_feasible) +
            sum(num_deptos_corner_nucleo_primer_piso[s,(k,j)] for s in S, (k, j) in KJ_feasible) +
            sum(num_deptos_d_corner_primer_piso[s,(k,j)] for s in S, (k, j) in KJ_feasible) +
            sum(num_deptos_d_corner_nucleo_primer_piso[s,(k,j)] for s in S, (k, j) in KJ_feasible)) +
            (sum(num_deptos_por_piso_superior[s,(k,j)] for s in S, (k, j) in KJ_feasible) +
            sum(num_deptos_nucleo_por_piso_superior[s,(k,j)] for s in S, (k, j) in KJ_feasible) +
            sum(num_deptos_corner_por_piso_superior[s,(k,j)] for s in S, (k, j) in KJ_feasible) +
            sum(num_deptos_corner_nucleo_por_piso_superior[s,(k,j)] for s in S, (k, j) in KJ_feasible) +
            sum(num_deptos_d_corner_por_piso_superior[s,(k,j)] for s in S, (k, j) in KJ_feasible) +
            sum(num_deptos_d_corner_nucleo_por_piso_superior[s,(k,j)] for s in S, (k, j) in KJ_feasible)
            ) * num_pisos_superiores

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

        # Link regular apartments to y indicator (if any regular apartments exist, y = 1)
        constraint_12[s in S], sum(num_deptos_por_piso_superior[s,(k,j)] for (k, j) in KJ_feasible) <= max_apts_per_strip * y[s]
        constraint_12_[s in S], sum(num_deptos_por_piso_superior[s,(k,j)] for (k, j) in KJ_feasible) >= y[s]

        # Exactly 2 corner apartments per strip if corner type is used
        constraint_12a[s in S], sum(num_deptos_corner_por_piso_superior[s,(k,j)] for (k, j) in KJ_feasible) == 2 * y_c[s]

        # Exactly 2 corner nucleo apartments per strip if corner nucleo type is used
        constraint_12b[s in S], sum(num_deptos_corner_nucleo_por_piso_superior[s,(k,j)] for (k, j) in KJ_feasible) == 2 * y_cn[s]

        # Link regular nucleo apartments to y_n indicator (if any nucleo apartments exist, y_n = 1)
        constraint_12c[s in S], sum(num_deptos_nucleo_por_piso_superior[s,(k,j)] for (k, j) in KJ_feasible) <= max_apts_per_strip * y_n[s]
        constraint_12d[s in S], sum(num_deptos_nucleo_por_piso_superior[s,(k,j)] for (k, j) in KJ_feasible) >= y_n[s]

        # Exactly 1 double corner apartment per strip if double corner type is used
        constraint_13[s in S], sum(num_deptos_d_corner_por_piso_superior[s,(k,j)] for (k, j) in KJ_feasible) == y_cc[s]

        # Exactly 1 double corner nucleo apartment per strip if double corner nucleo type is used
        constraint_13a[s in S], sum(num_deptos_d_corner_nucleo_por_piso_superior[s,(k,j)] for (k, j) in KJ_feasible) == y_ccn[s]

        # Allows only one double corner apartment or several regular apartments, not both
        constraint_14[s in S], sum(x_cc[s,(k,j)] + x[s,(k,j)] + x_n[s,(k,j)] for (k, j) in KJ_feasible) <= y_cc[s] + (1 - y_cc[s]) * max_apts_per_strip

        # Mutual exclusivity constraints (simplified)
        # Each strip can have at most one configuration type from incompatible groups
        constraint_15[s in S], y_c[s] + y_cn[s] + y_cc[s] + y_ccn[s] <= 1           # At most one corner/double-corner type
        constraint_15a[s in S], y[s] + y_cn[s] + y_ccn[s] <= 1                      # Regular incompatible with corner/double-corner núcleo
        constraint_15b[s in S], y_c[s] + y_n[s] + y_cn[s] <= 1                      # Regular núcleo incompatible with any corner type
        constraint_15c[s in S], y_cc[s] + y_ccn[s] + y_n[s] <= 1                    # Regular núcleo incompatible with double corners

        # Total apartment count must be within specified bounds
        constraint_16, min_deptos <= deptos_total <= max_deptos

        # Sum of all strip depths cannot exceed building depth
        constraint_17, sum(H_s[s] for s in S) <= H

        # Each strip must have minimum depth
        constraint_18[s in S], H_s[s] >= (H - 3) / 2

        # Apartment height (interior + terrace) must fit within strip depth for each apartment type
        constraint_19[s in S, (k, j) in KJ_feasible], x[s,(k,j)] * (mat_h_ip[k,j] + vec_h_t[k]) <= H_s[s]        # Regular apartments
        constraint_20[s in S, (k, j) in KJ_feasible], x_n[s,(k,j)] * (mat_h_ipn[k,j] + vec_h_t[k]) <= H_s[s]      # Nucleo apartments
        constraint_21[s in S, (k, j) in KJ_feasible], x_c[s,(k,j)] * (mat_h_in[k,j] + vec_h_t[k]) <= H_s[s]   # Corner apartments
        constraint_22[s in S, (k, j) in KJ_feasible], x_cn[s,(k,j)] * (mat_h_in[k,j] + vec_h_t[k]) <= H_s[s]   # Corner apartments
        constraint_23[s in S, (k, j) in KJ_feasible], x_cc[s,(k,j)] * (mat_h_in[k,j] + vec_h_t[k]) <= H_s[s] # Double corner apartments
        constraint_24[s in S, (k, j) in KJ_feasible], x_ccn[s,(k,j)] * (mat_h_in[k,j] + vec_h_t[k]) <= H_s[s] # Double corner apartments

        # Total apartment area per strip cannot exceed strip footprint (W x H_s)
        constraint_25[s in S], sum(num_deptos_por_piso_superior[s,(k,j)] * (mat_area_ip[k,j] + vec_area_t[k]) +
             num_deptos_nucleo_por_piso_superior[s,(k,j)] * (mat_area_ipn[k,j] + vec_area_t[k]) +
             (num_deptos_corner_por_piso_superior[s,(k,j)] + num_deptos_d_corner_por_piso_superior[s,(k,j)]) * (vec_area_i[k] + vec_area_t[k]) +
             (num_deptos_corner_nucleo_por_piso_superior[s,(k,j)] + num_deptos_d_corner_nucleo_por_piso_superior[s,(k,j)]) * (vec_area_in[k] + vec_area_t[k])
              for (k, j) in KJ_feasible) <= W * H_s[s]

        # Apartment count is positive only if apartment type is selected (Big-M constraint linking binary and integer variables)
        constraint_26[s in S, (k, j) in KJ_feasible], num_deptos_por_piso_superior[s,(k,j)] <= max_apts_per_strip * x[s,(k,j)]           # Regular apartments
        constraint_27[s in S, (k, j) in KJ_feasible], num_deptos_nucleo_por_piso_superior[s,(k,j)] <= max_apts_per_strip * x_n[s,(k,j)]  # Nucleo apartments
        constraint_28[s in S, (k, j) in KJ_feasible], num_deptos_corner_por_piso_superior[s,(k,j)] <= 2 * x_c[s,(k,j)]  # Corner apartments (max 2)
        constraint_29[s in S, (k, j) in KJ_feasible], num_deptos_corner_nucleo_por_piso_superior[s,(k,j)] <= 2 * x_cn[s,(k,j)]  # Corner nucleo apartments (max 2)
        constraint_30[s in S, (k, j) in KJ_feasible], num_deptos_d_corner_por_piso_superior[s,(k,j)] <= 1 * x_cc[s,(k,j)] # Double corner apartments (max 1)
        constraint_31[s in S, (k, j) in KJ_feasible], num_deptos_d_corner_nucleo_por_piso_superior[s,(k,j)] <= 1 * x_ccn[s,(k,j)] # Double corner nucleo apartments (max 1)



        # Total apartment widths per strip cannot exceed building width W
        constraint_38[s in S], sum((num_deptos_por_piso_superior[s,(k,j)] +
            num_deptos_nucleo_por_piso_superior[s,(k,j)] +
            num_deptos_corner_por_piso_superior[s,(k,j)] +
            num_deptos_corner_nucleo_por_piso_superior[s,(k,j)] +
            num_deptos_d_corner_por_piso_superior[s,(k,j)] +
            num_deptos_d_corner_nucleo_por_piso_superior[s,(k,j)]
            ) * vec_w_i[j] for (k, j) in KJ_feasible) <= W

        # Sum of apartment perimeters must cover strip perimeter
        # constraint_39[s in S],
        #     sum(num_deptos_por_piso_superior[s,(k,j)] * mat_exposicion[k,j] for (k, j) in KJ_feasible) +
        #     sum(num_deptos_nucleo_por_piso_superior[s,(k,j)] * mat_exposicion[k,j] for (k, j) in KJ_feasible) +
        #     sum(num_deptos_corner_por_piso_superior[s,(k,j)] * mat_exposicion_corner[k,j] for (k, j) in KJ_feasible) +
        #     sum(num_deptos_corner_nucleo_por_piso_superior[s,(k,j)] * mat_exposicion_corner[k,j] for (k, j) in KJ_feasible) +
        #     sum(num_deptos_d_corner_por_piso_superior[s,(k,j)] * mat_exposicion_d_corner[k,j] for (k, j) in KJ_feasible) +
        #     sum(num_deptos_d_corner_nucleo_por_piso_superior[s,(k,j)] * mat_exposicion_d_corner[k,j] for (k, j) in KJ_feasible) >= 2*H_s[s] + W - 10

        # First floor apartment counts cannot exceed upper floor counts (first floor is subset of upper floors)
        constraint_40[s in S, (k, j) in KJ_feasible], num_deptos_primer_piso[s,(k,j)] <= num_deptos_por_piso_superior[s,(k,j)]             # Regular apartments
        constraint_41[s in S, (k, j) in KJ_feasible], num_deptos_nucleo_primer_piso[s,(k,j)] <= num_deptos_nucleo_por_piso_superior[s,(k,j)]  # Nucleo apartments
        constraint_42[s in S, (k, j) in KJ_feasible], num_deptos_corner_primer_piso[s,(k,j)] <= num_deptos_corner_por_piso_superior[s,(k,j)]  # Corner apartments
        constraint_43[s in S, (k, j) in KJ_feasible], num_deptos_corner_nucleo_primer_piso[s,(k,j)] <= num_deptos_corner_nucleo_por_piso_superior[s,(k,j)]  # Corner apartments
        constraint_44[s in S, (k, j) in KJ_feasible], num_deptos_d_corner_primer_piso[s,(k,j)] <= num_deptos_d_corner_por_piso_superior[s,(k,j)] # Double corner apartments
        constraint_45[s in S, (k, j) in KJ_feasible], num_deptos_d_corner_nucleo_primer_piso[s,(k,j)] <= num_deptos_d_corner_nucleo_por_piso_superior[s,(k,j)] # Double corner apartments
    end)

    # Nucleo apartment constraints
    # Require exactly 2 nucleo apartments per strip (regular + corner + double corner combined, first floor)
    @constraints(model, begin
        constraint_46[s in S], sum(num_deptos_nucleo_primer_piso[s,(k,j)] for (k, j) in KJ_feasible) +
                                    sum(num_deptos_corner_nucleo_primer_piso[s,(k,j)] for (k, j) in KJ_feasible) +
                                    sum(num_deptos_d_corner_nucleo_primer_piso[s,(k,j)] for (k, j) in KJ_feasible) == 2
        constraint_47[s in S], sum(num_deptos_nucleo_por_piso_superior[s,(k,j)] for (k, j) in KJ_feasible) +
                                    sum(num_deptos_corner_nucleo_por_piso_superior[s,(k,j)] for (k, j) in KJ_feasible) +
                                    sum(num_deptos_d_corner_nucleo_por_piso_superior[s,(k,j)] for (k, j) in KJ_feasible) == 2 
    end)

    # Symmetry breaking: order strips by total apartments to reduce search space
    @constraint(model, sum(num_deptos_por_piso_superior[1,(k,j)] + num_deptos_nucleo_por_piso_superior[1,(k,j)] +
                           num_deptos_corner_por_piso_superior[1,(k,j)] + num_deptos_corner_nucleo_por_piso_superior[1,(k,j)] +
                           num_deptos_d_corner_por_piso_superior[1,(k,j)] + num_deptos_d_corner_nucleo_por_piso_superior[1,(k,j)]
                           for (k, j) in KJ_feasible) >=
                       sum(num_deptos_por_piso_superior[2,(k,j)] + num_deptos_nucleo_por_piso_superior[2,(k,j)] +
                           num_deptos_corner_por_piso_superior[2,(k,j)] + num_deptos_corner_nucleo_por_piso_superior[2,(k,j)] +
                           num_deptos_d_corner_por_piso_superior[2,(k,j)] + num_deptos_d_corner_nucleo_por_piso_superior[2,(k,j)]
                           for (k, j) in KJ_feasible))

    # Diversity constraints: prevent mixing very different apartment sizes (ratio > 2.0)
    for k1 in K, k2 in K
        if vec_area_i[k1] < vec_area_i[k2]  # Avoid duplicate constraints
            if vec_area_i[k2] > vec_area_i[k1] * 2.0
                # Prevent using both sizes simultaneously across all apartment types
                for s in S
                    @constraints(model, begin
                        sum(x[s,(k1,j)] for (k, j) in KJ_feasible if k == k1) + sum(x[s,(k2,j)] for (k, j) in KJ_feasible if k == k2) <= 1
                        sum(x_n[s,(k1,j)] for (k, j) in KJ_feasible if k == k1) + sum(x_n[s,(k2,j)] for (k, j) in KJ_feasible if k == k2) <= 1
                        sum(x_c[s,(k1,j)] for (k, j) in KJ_feasible if k == k1) + sum(x_c[s,(k2,j)] for (k, j) in KJ_feasible if k == k2) <= 1
                        sum(x_cn[s,(k1,j)] for (k, j) in KJ_feasible if k == k1) + sum(x_cn[s,(k2,j)] for (k, j) in KJ_feasible if k == k2) <= 1
                        sum(x_cc[s,(k1,j)] for (k, j) in KJ_feasible if k == k1) + sum(x_cc[s,(k2,j)] for (k, j) in KJ_feasible if k == k2) <= 1
                        sum(x_ccn[s,(k1,j)] for (k, j) in KJ_feasible if k == k1) + sum(x_ccn[s,(k2,j)] for (k, j) in KJ_feasible if k == k2) <= 1
                    end)
                end
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
    results["num_deptos_corner_nucleo_por_piso_superior"] = Dict{Tuple{Int,Int,Int},Float64}()
    results["num_deptos_d_corner_por_piso_superior"] = Dict{Tuple{Int,Int,Int},Float64}()
    results["num_deptos_d_corner_nucleo_por_piso_superior"] = Dict{Tuple{Int,Int,Int},Float64}()
    results["num_deptos_primer_piso"] = Dict{Tuple{Int,Int,Int},Float64}()
    results["num_deptos_nucleo_primer_piso"] = Dict{Tuple{Int,Int,Int},Float64}()
    results["num_deptos_corner_primer_piso"] = Dict{Tuple{Int,Int,Int},Float64}()
    results["num_deptos_corner_nucleo_primer_piso"] = Dict{Tuple{Int,Int,Int},Float64}()
    results["num_deptos_d_corner_primer_piso"] = Dict{Tuple{Int,Int,Int},Float64}()
    results["num_deptos_d_corner_nucleo_primer_piso"] = Dict{Tuple{Int,Int,Int},Float64}()
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
    results["mat_h_in"] = mat_h_in
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

            perimetro_s_pp = sum(value(num_deptos_primer_piso[s,(k,j)]) * mat_exposicion[k,j] for (k, j) in KJ_feasible) +
                          sum(value(num_deptos_nucleo_primer_piso[s,(k,j)]) * mat_exposicion[k,j] for (k, j) in KJ_feasible) +
                          sum(value(num_deptos_corner_primer_piso[s,(k,j)]) * mat_exposicion_corner[k,j] for (k, j) in KJ_feasible) +
                          sum(value(num_deptos_corner_nucleo_primer_piso[s,(k,j)]) * mat_exposicion_corner[k,j] for (k, j) in KJ_feasible) +
                          sum(value(num_deptos_d_corner_primer_piso[s,(k,j)]) * mat_exposicion_d_corner[k,j] for (k, j) in KJ_feasible) +
                          sum(value(num_deptos_d_corner_nucleo_primer_piso[s,(k,j)]) * mat_exposicion_d_corner[k,j] for (k, j) in KJ_feasible)
            results["perimetro_strip_primer_piso"][s] = perimetro_s_pp

            apartment_area_s_pp = sum(value(num_deptos_primer_piso[s,(k,j)]) * vec_area_i[k] for (k, j) in KJ_feasible) +
                               sum(value(num_deptos_nucleo_primer_piso[s,(k,j)]) * vec_area_i[k] for (k, j) in KJ_feasible) +
                               sum(value(num_deptos_corner_primer_piso[s,(k,j)]) * vec_area_i[k] for (k, j) in KJ_feasible) +
                               sum(value(num_deptos_corner_nucleo_primer_piso[s,(k,j)]) * vec_area_i[k] for (k, j) in KJ_feasible) +
                               sum(value(num_deptos_d_corner_primer_piso[s,(k,j)]) * vec_area_i[k] for (k, j) in KJ_feasible) +
                               sum(value(num_deptos_d_corner_nucleo_primer_piso[s,(k,j)]) * vec_area_i[k] for (k, j) in KJ_feasible)
            results["apartment_area_strip_primer_piso"][s] = apartment_area_s_pp

            terrace_area_s_pp = sum(value(num_deptos_primer_piso[s,(k,j)]) * vec_area_t[k] for (k, j) in KJ_feasible) +
                             sum(value(num_deptos_nucleo_primer_piso[s,(k,j)]) * vec_area_t[k] for (k, j) in KJ_feasible) +
                             sum(value(num_deptos_corner_primer_piso[s,(k,j)]) * vec_area_t[k] for (k, j) in KJ_feasible) +
                             sum(value(num_deptos_corner_nucleo_primer_piso[s,(k,j)]) * vec_area_t[k] for (k, j) in KJ_feasible) +
                             sum(value(num_deptos_d_corner_primer_piso[s,(k,j)]) * vec_area_t[k] for (k, j) in KJ_feasible) +
                             sum(value(num_deptos_d_corner_nucleo_primer_piso[s,(k,j)]) * vec_area_t[k] for (k, j) in KJ_feasible)
            results["terrace_area_strip_primer_piso"][s] = terrace_area_s_pp

            pasillo_area_s_pp = sum(value(num_deptos_primer_piso[s,(k,j)]) * vec_area_p[j] for (k, j) in KJ_feasible) +
                             sum(value(num_deptos_nucleo_primer_piso[s,(k,j)]) * vec_area_p[j] for (k, j) in KJ_feasible) +
                             sum(value(num_deptos_corner_primer_piso[s,(k,j)]) * vec_area_p[j] for (k, j) in KJ_feasible) +
                             sum(value(num_deptos_d_corner_primer_piso[s,(k,j)]) * vec_area_p[j] for (k, j) in KJ_feasible)
            results["pasillo_area_strip_primer_piso"][s] = pasillo_area_s_pp

            perimetro_s_ps = sum(value(num_deptos_por_piso_superior[s,(k,j)]) * mat_exposicion[k,j] for (k, j) in KJ_feasible) +
                          sum(value(num_deptos_nucleo_por_piso_superior[s,(k,j)]) * mat_exposicion[k,j] for (k, j) in KJ_feasible) +
                          sum(value(num_deptos_corner_por_piso_superior[s,(k,j)]) * mat_exposicion_corner[k,j] for (k, j) in KJ_feasible) +
                          sum(value(num_deptos_corner_nucleo_por_piso_superior[s,(k,j)]) * mat_exposicion_corner[k,j] for (k, j) in KJ_feasible) +
                          sum(value(num_deptos_d_corner_por_piso_superior[s,(k,j)]) * mat_exposicion_d_corner[k,j] for (k, j) in KJ_feasible) +
                          sum(value(num_deptos_d_corner_nucleo_por_piso_superior[s,(k,j)]) * mat_exposicion_d_corner[k,j] for (k, j) in KJ_feasible)
            results["perimetro_strip_pisos_superiores"][s] = perimetro_s_ps

            apartment_area_s_ps = sum(value(num_deptos_por_piso_superior[s,(k,j)]) * vec_area_i[k] for (k, j) in KJ_feasible) +
                               sum(value(num_deptos_nucleo_por_piso_superior[s,(k,j)]) * vec_area_i[k] for (k, j) in KJ_feasible) +
                               sum(value(num_deptos_corner_por_piso_superior[s,(k,j)]) * vec_area_i[k] for (k, j) in KJ_feasible) +
                               sum(value(num_deptos_corner_nucleo_por_piso_superior[s,(k,j)]) * vec_area_i[k] for (k, j) in KJ_feasible) +
                               sum(value(num_deptos_d_corner_por_piso_superior[s,(k,j)]) * vec_area_i[k] for (k, j) in KJ_feasible) +
                               sum(value(num_deptos_d_corner_nucleo_por_piso_superior[s,(k,j)]) * vec_area_i[k] for (k, j) in KJ_feasible)
            results["apartment_area_strip_pisos_superiores"][s] = apartment_area_s_ps

            terrace_area_s_ps = sum(value(num_deptos_por_piso_superior[s,(k,j)]) * vec_area_t[k] for (k, j) in KJ_feasible) +
                             sum(value(num_deptos_nucleo_por_piso_superior[s,(k,j)]) * vec_area_t[k] for (k, j) in KJ_feasible) +
                             sum(value(num_deptos_corner_por_piso_superior[s,(k,j)]) * vec_area_t[k] for (k, j) in KJ_feasible) +
                             sum(value(num_deptos_corner_nucleo_por_piso_superior[s,(k,j)]) * vec_area_t[k] for (k, j) in KJ_feasible) +
                             sum(value(num_deptos_d_corner_por_piso_superior[s,(k,j)]) * vec_area_t[k] for (k, j) in KJ_feasible) +
                             sum(value(num_deptos_d_corner_nucleo_por_piso_superior[s,(k,j)]) * vec_area_t[k] for (k, j) in KJ_feasible)
            results["terrace_area_strip_pisos_superiores"][s] = terrace_area_s_ps

            pasillo_area_s_ps = sum(value(num_deptos_por_piso_superior[s,(k,j)]) * vec_area_p[j] for (k, j) in KJ_feasible) +
                             sum(value(num_deptos_nucleo_por_piso_superior[s,(k,j)]) * vec_area_p[j] for (k, j) in KJ_feasible) +
                             sum(value(num_deptos_corner_por_piso_superior[s,(k,j)]) * vec_area_p[j] for (k, j) in KJ_feasible) +
                             sum(value(num_deptos_d_corner_por_piso_superior[s,(k,j)]) * vec_area_p[j] for (k, j) in KJ_feasible)
            results["pasillo_area_strip_pisos_superiores"][s] = pasillo_area_s_ps

            for (k, j) in KJ_feasible
                for (var, key, threshold, is_binary) in [
                    (num_deptos_por_piso_superior[s,(k,j)], "num_deptos_por_piso_superior", 0.001, false),
                    (num_deptos_nucleo_por_piso_superior[s,(k,j)], "num_deptos_nucleo_por_piso_superior", 0.001, false),
                    (num_deptos_corner_por_piso_superior[s,(k,j)], "num_deptos_corner_por_piso_superior", 0.001, false),
                    (num_deptos_corner_nucleo_por_piso_superior[s,(k,j)], "num_deptos_corner_nucleo_por_piso_superior", 0.001, false),
                    (num_deptos_d_corner_por_piso_superior[s,(k,j)], "num_deptos_d_corner_por_piso_superior", 0.001, false),
                    (num_deptos_d_corner_nucleo_por_piso_superior[s,(k,j)], "num_deptos_d_corner_nucleo_por_piso_superior", 0.001, false),
                    (num_deptos_primer_piso[s,(k,j)], "num_deptos_primer_piso", 0.001, false),
                    (num_deptos_nucleo_primer_piso[s,(k,j)], "num_deptos_nucleo_primer_piso", 0.001, false),
                    (num_deptos_corner_primer_piso[s,(k,j)], "num_deptos_corner_primer_piso", 0.001, false),
                    (num_deptos_corner_nucleo_primer_piso[s,(k,j)], "num_deptos_corner_nucleo_primer_piso", 0.001, false),
                    (num_deptos_d_corner_primer_piso[s,(k,j)], "num_deptos_d_corner_primer_piso", 0.001, false),
                    (num_deptos_d_corner_nucleo_primer_piso[s,(k,j)], "num_deptos_d_corner_nucleo_primer_piso", 0.001, false),
                    (x[s,(k,j)], "x", 0.5, true),
                    (x_n[s,(k,j)], "x_n", 0.5, true),
                    (x_c[s,(k,j)], "x_c", 0.5, true),
                    (x_cc[s,(k,j)], "x_cc", 0.5, true)]

                    val = value(var)
                    if val > threshold
                        results[key][(s,k,j)] = is_binary ? 1 : val
                    end
                end
            end
        end

        deptos_primer_piso = sum(sum(values(results[k])) for k in ["num_deptos_primer_piso", "num_deptos_nucleo_primer_piso", "num_deptos_corner_primer_piso", "num_deptos_corner_nucleo_primer_piso", "num_deptos_d_corner_primer_piso", "num_deptos_d_corner_nucleo_primer_piso"])
        deptos_pisos_superiores = sum(sum(values(results[k])) for k in ["num_deptos_por_piso_superior", "num_deptos_nucleo_por_piso_superior", "num_deptos_corner_por_piso_superior", "num_deptos_corner_nucleo_por_piso_superior", "num_deptos_d_corner_por_piso_superior", "num_deptos_d_corner_nucleo_por_piso_superior"])

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
        corner_nucleo_primer_piso_dict = get(results, "num_deptos_corner_nucleo_primer_piso", Dict())
        corner_nucleo_por_piso_superior_dict = get(results, "num_deptos_corner_nucleo_por_piso_superior", Dict())
        d_corner_nucleo_primer_piso_dict = get(results, "num_deptos_d_corner_nucleo_primer_piso", Dict())
        d_corner_nucleo_por_piso_superior_dict = get(results, "num_deptos_d_corner_nucleo_por_piso_superior", Dict())

        area_nucleo_pp = sum(get(nucleo_primer_piso_dict, (s,k,j), 0.0) * area_nucleo_depto_local for s in 1:num_strips for k in 1:length(vec_area_i_local) for j in 1:length(vec_w_i_local)) +
                        sum(get(corner_nucleo_primer_piso_dict, (s,k,j), 0.0) * area_nucleo_depto_local for s in 1:num_strips for k in 1:length(vec_area_i_local) for j in 1:length(vec_w_i_local)) +
                        sum(get(d_corner_nucleo_primer_piso_dict, (s,k,j), 0.0) * area_nucleo_depto_local for s in 1:num_strips for k in 1:length(vec_area_i_local) for j in 1:length(vec_w_i_local))
        area_nucleo_ps = sum(get(nucleo_por_piso_superior_dict, (s,k,j), 0.0) * area_nucleo_depto_local for s in 1:num_strips for k in 1:length(vec_area_i_local) for j in 1:length(vec_w_i_local)) +
                        sum(get(corner_nucleo_por_piso_superior_dict, (s,k,j), 0.0) * area_nucleo_depto_local for s in 1:num_strips for k in 1:length(vec_area_i_local) for j in 1:length(vec_w_i_local)) +
                        sum(get(d_corner_nucleo_por_piso_superior_dict, (s,k,j), 0.0) * area_nucleo_depto_local for s in 1:num_strips for k in 1:length(vec_area_i_local) for j in 1:length(vec_w_i_local))
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

    println("\n" * "="^180)
    println("ASIGNACIÓN DE DEPARTAMENTOS")
    println("="^180)

    vec_area_i = results["vec_area_i"]
    vec_area_t = results["vec_area_t"]
    vec_area_p = results["vec_area_p"]
    vec_h_t = results["vec_h_t"]
    vec_w_i = results["vec_w_i"]
    mat_h_ip = results["mat_h_ip"]
    mat_h_ipn = results["mat_h_ipn"]
    mat_h_in = results["mat_h_in"]
    area_nucleo_depto_local = results["area_nucleo_depto"]

    all_deptos_global = []

    for (strip, profundidad) in sort(collect(results["H_s"]))
        perimetro_pp = get(results["perimetro_strip_primer_piso"], strip, 0.0)
        perimetro_ps = get(results["perimetro_strip_pisos_superiores"], strip, 0.0)

        for (key, tipo_label, piso_label) in [
            ("num_deptos_primer_piso", "Regular", "1° Piso"),
            ("num_deptos_nucleo_primer_piso", "Núcleo", "1° Piso"),
            ("num_deptos_corner_primer_piso", "Corner", "1° Piso"),
            ("num_deptos_corner_nucleo_primer_piso", "Corner Núcleo", "1° Piso"),
            ("num_deptos_d_corner_primer_piso", "Double Corner", "1° Piso"),
            ("num_deptos_d_corner_nucleo_primer_piso", "D-Corner Núc.", "1° Piso"),
            ("num_deptos_por_piso_superior", "Regular", "Pisos Sup."),
            ("num_deptos_nucleo_por_piso_superior", "Núcleo", "Pisos Sup."),
            ("num_deptos_corner_por_piso_superior", "Corner", "Pisos Sup."),
            ("num_deptos_corner_nucleo_por_piso_superior", "Corner Núcleo", "Pisos Sup."),
            ("num_deptos_d_corner_por_piso_superior", "Double Corner", "Pisos Sup."),
            ("num_deptos_d_corner_nucleo_por_piso_superior", "D-Corner Núc.", "Pisos Sup.")
        ]
            strip_deptos = filter(p -> p[1][1] == strip, collect(get(results, key, Dict())))
            for ((s, k, j), count) in strip_deptos
                perimetro = piso_label == "1° Piso" ? perimetro_pp : perimetro_ps
                ancho = vec_w_i[j]
                area_interior = vec_area_i[k]
                area_terraza = vec_area_t[k]

                if tipo_label == "Regular"
                    alto = mat_h_ip[k,j]
                    area_pasillo = vec_area_p[j]
                    area_nucleo = 0.0
                    area_total = ancho * alto
                elseif tipo_label == "Núcleo"
                    alto = mat_h_ipn[k,j]
                    area_pasillo = vec_area_p[j]
                    area_nucleo = area_nucleo_depto_local
                    area_total = ancho * alto
                elseif tipo_label == "Corner"
                    alto = mat_h_in[k,j]
                    area_pasillo = 0.0
                    area_nucleo = 0.0
                    area_total = area_interior
                elseif tipo_label == "Corner Núcleo"
                    alto = mat_h_in[k,j]
                    area_pasillo = 0.0
                    area_nucleo = area_nucleo_depto_local
                    area_total = area_interior + area_nucleo
                elseif tipo_label == "Double Corner"
                    alto = mat_h_in[k,j]
                    area_pasillo = 0.0
                    area_nucleo = 0.0
                    area_total = area_interior
                else
                    alto = mat_h_in[k,j]
                    area_pasillo = 0.0
                    area_nucleo = area_nucleo_depto_local
                    area_total = area_interior + area_nucleo
                end

                push!(all_deptos_global, (strip, piso_label, tipo_label, k, j, count, area_interior, area_pasillo, area_nucleo, area_terraza, area_total, ancho, alto, perimetro, profundidad))
            end
        end
    end

    if !isempty(all_deptos_global)
        println("\n┌──────┬────────────┬──────────────┬──────┬────────┬───────┬──────────┬──────────┬──────────┬─────────┬─────────┬──────────┬──────────┐")
        println("│Strip │ Piso       │ Tipo         │ (k,j)│ Unid.  │ Ancho │ Prof.    │ Interior │ Pasillo  │ Núcleo  │ Terraza │ Total    │ A×P      │")
        println("│      │            │              │      │        │ (m)   │ (m)      │ (m²)     │ (m²)     │ (m²)    │ (m²)    │ (m²)     │ (m²)     │")
        println("├──────┼────────────┼──────────────┼──────┼────────┼───────┼──────────┼──────────┼──────────┼─────────┼─────────┼──────────┼──────────┤")

        current_strip = nothing
        for (strip, piso, tipo, k, j, count, area_int, area_pas, area_nuc, area_terr, area_tot, ancho, alto, _, _) in all_deptos_global
            if current_strip !== nothing && strip != current_strip
                println("├──────┼────────────┼──────────────┼──────┼────────┼───────┼──────────┼──────────┼──────────┼─────────┼─────────┼──────────┼──────────┤")
            end
            current_strip = strip

            area_axp = ancho * alto

            println("│  $(lpad(strip, 2))  │ $(rpad(piso, 10)) │ $(rpad(tipo, 12)) │ $(lpad("($k,$j)", 4)) │ $(lpad(round(Int, count), 4))   │ $(lpad(round(ancho, digits=1), 5)) │ $(lpad(round(alto, digits=1), 8)) │ $(lpad(round(area_int, digits=1), 8)) │ $(lpad(round(area_pas, digits=1), 8)) │ $(lpad(round(area_nuc, digits=1), 7)) │ $(lpad(round(area_terr, digits=1), 7)) │ $(lpad(round(area_tot, digits=1), 8)) │ $(lpad(round(area_axp, digits=1), 8)) │")
        end

        println("└──────┴────────────┴──────────────┴──────┴────────┴───────┴──────────┴──────────┴──────────┴─────────┴─────────┴──────────┴──────────┘")
        println("\nNotas:")
        println("  • Total = área del rectángulo principal (Ancho × Profundidad para Regular/Núcleo, solo Interior para Corner)")
        println("  • A×P = verificación de Ancho × Profundidad")
        println("  • Terraza está fuera del rectángulo principal")
    end
    println("\n" * "="^180)
end
