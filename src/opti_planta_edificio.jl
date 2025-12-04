
"""
Optimiza la asignación de departamentos en strips norte/sures para maximizar superficie total.

# Argumentos
- `W::Float64`: Ancho del edificio (m)
- `H::Float64`: Altura total del edificio (m)
- `num_strips::Int`: Número de strips norte/sures
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
- `mat_h_t`: Matriz de alturas de terraza por tipo
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
function opti_planta_edificio(dict_arquitectura, max_constructibilidad, max_deptos,
                                vec_ps_opt, vec_np_opt, flag_dfl2, flag_vivienda_economica)

    # Rotates floor plan to axis-aligned rectangle with width > height, returns dimensions and transformation
    function normaliza_planta_rectangular(ps_planta::PolyShape, layout)
        V_planta = ps_planta.Vertices[1]
        x_cr = sum(V_planta[1:end, 1]) / (size(V_planta, 1) - 1)
        y_cr = sum(V_planta[1:end, 2]) / (size(V_planta, 1) - 1)
        cr = [x_cr, y_cr]

        edge1 = V_planta[2, :] - V_planta[1, :]
        angulo_rotacion = -atan(edge1[2], edge1[1])

        ps_planta_normalizado = polyShape.polyRotate(ps_planta, angulo_rotacion, cr)
        V_planta_normalizado = ps_planta_normalizado.Vertices[1]

        vec_x_planta = V_planta_normalizado[:, 1]
        vec_y_planta = V_planta_normalizado[:, 2]
        W_raw = maximum(vec_x_planta) - minimum(vec_x_planta)
        H_raw = maximum(vec_y_planta) - minimum(vec_y_planta)

        if layout == 2
            W = H_raw
            H = W_raw
        else
            W = W_raw
            H = H_raw
        end

        println("Layout $(layout): Angle=$(round(rad2deg(angulo_rotacion), digits=1))°, Raw=$(round(W_raw,digits=2))×$(round(H_raw,digits=2)) → Final W=$(round(W,digits=2))×H=$(round(H,digits=2))")

        return W, H, angulo_rotacion, cr, ps_planta_normalizado
    end

    function compute_arquitectura_params(dict_arquitectura)
        num_intervalos = 2

        vec_area_i_original = dict_arquitectura["arq_vecSupInterior"]
        vec_area_i = Float64[]
        for i in eachindex(vec_area_i_original)
            push!(vec_area_i, vec_area_i_original[i])
            if i < lastindex(vec_area_i_original)
                interval = vec_area_i_original[i+1] - vec_area_i_original[i]
                step = interval / (num_intervalos + 1)
                for n in 1:num_intervalos
                    push!(vec_area_i, vec_area_i_original[i] + n * step)
                end
            end
        end
        num_sizes = length(vec_area_i)
        K = 1:num_sizes

        vec_w_i = collect(6.0:0.5:14.0)
        num_widths = length(vec_w_i)
        J = 1:num_widths

        vec_area_p = vec_w_i .* .75
        mat_area_ip = [vec_area_i[k] + vec_area_p[j] for k in K, j in J]
        mat_h_ip = [mat_area_ip[k,j] / vec_w_i[j] for k in K, j in J]

        area_nucleo_depto = 5
        area_nucleo_depto_d_corner = 2*area_nucleo_depto

        vec_area_in = vec_area_i .+ area_nucleo_depto
        mat_h_in = [vec_area_in[k] / vec_w_i[j] for k in K, j in J]

        vec_area_in_d_corner = vec_area_i .+ area_nucleo_depto_d_corner
        mat_h_in_d_corner = [vec_area_in_d_corner[k] / vec_w_i[j] for k in K, j in J]

        mat_area_ipn = mat_area_ip .+ area_nucleo_depto
        mat_h_ipn = [mat_area_ipn[k,j] / vec_w_i[j] for k in K, j in J]

        vec_area_t_original = dict_arquitectura["arq_vecSupTerraza"]
        vec_area_t_temp = Float64[]
        for i in eachindex(vec_area_t_original)
            push!(vec_area_t_temp, vec_area_t_original[i])
            if i < lastindex(vec_area_t_original)
                interval = vec_area_t_original[i+1] - vec_area_t_original[i]
                step = interval / (num_intervalos + 1)
                for n in 1:num_intervalos
                    push!(vec_area_t_temp, vec_area_t_original[i] + n * step)
                end
            end
        end

        if length(vec_area_t_temp) < length(vec_area_i)
            vec_area_t = vcat(vec_area_t_temp, fill(vec_area_t_temp[end], length(vec_area_i) - length(vec_area_t_temp)))
        elseif length(vec_area_t_temp) > length(vec_area_i)
            vec_area_t = vec_area_t_temp[1:length(vec_area_i)]
        else
            vec_area_t = vec_area_t_temp
        end

        mat_h_t = [vec_area_t[k] <= 2 * vec_w_i[j] ? 2.0 : vec_area_t[k] / vec_w_i[j] for k in K, j in J]

        return vec_area_i, vec_area_t, vec_area_p, mat_h_t, vec_w_i, mat_h_ip, mat_h_ipn, mat_h_in, mat_h_in_d_corner, area_nucleo_depto, area_nucleo_depto_d_corner
    end

    function opti_planta_edificio_layout(vec_area_i, vec_area_t, vec_area_p, mat_h_t, vec_w_i,
                                mat_h_ip, mat_h_ipn, mat_h_in, mat_h_in_d_corner,
                                area_nucleo_depto, area_nucleo_depto_d_corner,
                                max_constructibilidad, max_deptos,
                                vec_ps_opt, vec_np_opt, flag_dfl2, flag_vivienda_economica,
                                layout, num_threads_highs)

        flag_dfl2 = flag_dfl2 || flag_vivienda_economica

        ps_planta = vec_ps_opt[1]
        W, H, angulo_rotacion, cr, ps_planta_normalizado = normaliza_planta_rectangular(ps_planta, layout)

        min_deptos = 4

        num_pisos = vec_np_opt[1]
        num_strips = 2

        num_sizes = length(vec_area_i)
        K = 1:num_sizes

        num_widths = length(vec_w_i)
        J = 1:num_widths

        mat_h_i = [vec_area_i[k] / vec_w_i[j] for k in K, j in J]
        mat_w_i = [vec_w_i[j] for k in K, j in J]

        mat_area_i = [mat_h_i[k,j] * vec_w_i[j] for k in K, j in J]

        mat_area_t = [vec_area_t[k] for k in K, j in J]

        mat_area_ip = [vec_area_i[k] + vec_area_p[j] for k in K, j in J]
        mat_area_ipn = mat_area_ip .+ area_nucleo_depto

        mat_corner_h = [vec_area_i[k] / vec_w_i[j] for k in K, j in J]
        mat_d_corner_h = [vec_area_i[k] / vec_w_i[j] for k in K, j in J]

        mat_exposicion = [vec_w_i[j] for k in K, j in J]
        mat_exposicion_corner = [vec_w_i[j] + mat_corner_h[k,j] for k in K, j in J]
        mat_exposicion_d_corner = [vec_w_i[j] + 2*mat_d_corner_h[k,j] for k in K, j in J]

        mat_aspect_ratio = mat_h_i ./ mat_w_i

        mat_flag_feasible = (mat_h_i .<= (mat_area_i .- 30 .+ 22.5*6) ./ 22.5) .&&
                            (mat_h_i .>= 4) .&&
                            (mat_w_i .>= 6) .&&
                            (mat_area_i .+ mat_area_t ./ 2) .<= 140 * (1*flag_dfl2 + 10*(1 - flag_dfl2)) .&&
                            (mat_aspect_ratio .>= 0.4) .&&
                            (mat_aspect_ratio .<= 2.5)               

        num_pisos_superiores = num_pisos - 1

        num_areas_deptos = length(vec_area_i)
        K = 1:num_areas_deptos

        num_widths = size(mat_h_ip, 2)
        J = 1:num_widths

        KJ_feasible = [(k, j) for k in K, j in J if mat_flag_feasible[k, j] > 0]  # Filtered list of valid (apartment_size_index, width_index) combinations based on feasibility matrix

        S = 1:num_strips
        T = [:regular, :regular_nucleo, :corner, :corner_nucleo, :d_corner_nucleo]
        T_nucleo = [:regular_nucleo, :corner_nucleo, :d_corner_nucleo]
        T_corner = [:corner, :corner_nucleo, :d_corner_nucleo]
        T_regular = [:regular, :regular_nucleo]

        model = Model(HiGHS.Optimizer)
        set_silent(model)
        set_time_limit_sec(model, 300.0)
        set_optimizer_attribute(model, "mip_rel_gap", 0.01)
        set_optimizer_attribute(model, "presolve", "on")
        set_optimizer_attribute(model, "mip_detect_symmetry", true)
        set_optimizer_attribute(model, "mip_heuristic_effort", 0.3)
        set_optimizer_attribute(model, "parallel", "on")
        set_optimizer_attribute(model, "threads", num_threads_highs)
        set_optimizer_attribute(model, "mip_feasibility_tolerance", 1e-6)

        min_width = minimum(vec_w_i)
        min_height = minimum(mat_h_ip)

        max_apts_per_strip = floor(Int, W / min_width)
        max_apts_per_strip_tight = min(max_apts_per_strip, ceil(Int, (W * H) / (min_width * min_height)))

        max_corner_deptos_por_strip = 2
        max_d_corner_deptos_por_strip = 1

        max_deptos_by_type = Dict(
            :regular => Int(round(max_deptos / num_pisos)),
            :regular_nucleo => 2,
            :corner => max_corner_deptos_por_strip,
            :corner_nucleo => max_corner_deptos_por_strip,
            :d_corner_nucleo => max_d_corner_deptos_por_strip
        )

        area_interior_by_type = Dict(
            :regular => (k,j) -> vec_area_i[k],
            :regular_nucleo => (k,j) -> vec_area_i[k],
            :corner => (k,j) -> vec_area_i[k],
            :corner_nucleo => (k,j) -> vec_area_i[k],
            :d_corner_nucleo => (k,j) -> vec_area_i[k]
        )

        area_ipn_by_type = Dict(
            :regular => (k,j) -> mat_area_ip[k,j],
            :regular_nucleo => (k,j) -> mat_area_ipn[k,j],
            :corner => (k,j) -> vec_area_i[k],
            :corner_nucleo => (k,j) -> vec_area_i[k],
            :d_corner_nucleo => (k,j) -> vec_area_i[k]
        )

        mat_h_ipn_by_type = Dict(
            :regular => (k,j) -> mat_h_ip[k,j],
            :regular_nucleo => (k,j) -> mat_h_ipn[k,j],
            :corner => (k,j) -> mat_h_i[k,j],
            :corner_nucleo => (k,j) -> mat_h_in[k,j],
            :d_corner_nucleo => (k,j) -> mat_h_in[k,j]
        )

        mat_exposicion_by_type = Dict(
            :regular => mat_exposicion,
            :regular_nucleo => mat_exposicion,
            :corner => mat_exposicion_corner,
            :corner_nucleo => mat_exposicion_corner,
            :d_corner_nucleo => mat_exposicion_d_corner
        )

        @variables(model, begin
            H_s[s in S] >= 0  # Depth of strip s (m)

            0 <= num_deptos_primer_piso[t in T, s in S, (k, j) in KJ_feasible] <= max_deptos_by_type[t], Int  # Number of apartments of type t in first floor strip s with size k and width j
            area_comun_primer_piso >= 0  # Common area on first floor (m²)

            0 <= num_deptos_por_piso_superior[t in T, s in S, (k, j) in KJ_feasible] <= max_deptos_by_type[t], Int  # Number of apartments of type t per upper floor in strip s with size k and width j
            area_comun_por_piso_superior >= 0  # Common area per upper floor (m²)

            x[t in T, s in S, (k, j) in KJ_feasible], Bin  # Binary indicator: apartment type t with size k and width j is used in strip s

            y[t in T, s in S], Bin  # Binary indicator: if strip s uses apartment type t configuration
            y_active[s in S], Bin  # Binary indicator: if strip s is active

            z[k in K], Bin  # Binary indicator: apartment size k is used anywhere in the building

            descuento_dfl2 >= 0  # DFL2 discount for social housing (up to 20% of useful area or total common area) (m²)
            area_no_utilizada_primer_piso >= 0  # Unused footprint area on first floor (m²)
            area_no_utilizada_por_piso_superior >= 0  # Unused footprint area per upper floor (m²)
            area_util_no_utilizada >= 0  # Slack variable: unused useful area under max constructibilidad (m²)

        end)

        @expressions(model, begin
            # Total number of apartments on first floor
            total_num_deptos_primer_piso, sum(num_deptos_primer_piso[t,s,(k,j)] for t in T, s in S, (k, j) in KJ_feasible)

            # Total number of apartments per upper floor
            total_num_deptos_por_piso_superior, sum(num_deptos_por_piso_superior[t,s,(k,j)] for t in T, s in S, (k, j) in KJ_feasible)

            # Total common area across all floors
            area_comun_total, area_comun_primer_piso + area_comun_por_piso_superior * num_pisos_superiores

            # Total unused footprint area across all floors
            area_no_utilizada, area_no_utilizada_primer_piso + area_no_utilizada_por_piso_superior * num_pisos_superiores

            # Total interior area for first floor apartments
            area_interior_primer_piso, sum(num_deptos_primer_piso[t,s,(k,j)] * area_interior_by_type[t](k,j) for t in T, s in S, (k, j) in KJ_feasible)

            # Interior area per upper floor
            area_interior_por_piso_superior, sum(num_deptos_por_piso_superior[t,s,(k,j)] * area_interior_by_type[t](k,j) for t in T, s in S, (k, j) in KJ_feasible)

            # Total interior area for entire building
            area_interior_total, area_interior_primer_piso + area_interior_por_piso_superior * num_pisos_superiores

            # Total terrace area for first floor apartments
            area_terraza_primer_piso, sum(num_deptos_primer_piso[t,s,(k,j)] * vec_area_t[k] for t in T, s in S, (k, j) in KJ_feasible)

            # Terrace area per upper floor
            area_terraza_por_piso_superior, sum(num_deptos_por_piso_superior[t,s,(k,j)] * vec_area_t[k] for t in T, s in S, (k, j) in KJ_feasible)

            # Total terrace area for entire building
            area_terraza_total, area_terraza_primer_piso + area_terraza_por_piso_superior * num_pisos_superiores

            # Useful area for first floor (interior + 50% of terrace)
            area_util_primer_piso, area_interior_primer_piso + area_terraza_primer_piso / 2

            # Useful area per upper floor (interior + 50% of terrace)
            area_util_por_piso_superior, area_interior_por_piso_superior + area_terraza_por_piso_superior / 2

            # Total useful area for entire building
            area_util_total, area_util_primer_piso + area_util_por_piso_superior * num_pisos_superiores

            # Total hallway area for first floor apartments
            area_pasillo_primer_piso, sum(num_deptos_primer_piso[t,s,(k,j)] * vec_area_p[j] for t in T_regular, s in S, (k, j) in KJ_feasible)

            # Hallway area per upper floor
            area_pasillo_por_piso_superior, sum(num_deptos_por_piso_superior[t,s,(k,j)] * vec_area_p[j] for t in T_regular, s in S, (k, j) in KJ_feasible)

            # Total hallway area for entire building
            area_pasillo_total, area_pasillo_primer_piso + area_pasillo_por_piso_superior * num_pisos_superiores

            # Nucleo area for first floor (additional area per nucleo apartment)
            area_nucleo_primer_piso, sum((num_deptos_primer_piso[:regular_nucleo,s,(k,j)] + num_deptos_primer_piso[:corner_nucleo,s,(k,j)]) * area_nucleo_depto +
                                        num_deptos_primer_piso[:d_corner_nucleo,s,(k,j)] * area_nucleo_depto_d_corner for s in S, (k, j) in KJ_feasible)

            # Nucleo area per upper floor
            area_nucleo_por_piso_superior, sum((num_deptos_por_piso_superior[:regular_nucleo,s,(k,j)] + num_deptos_por_piso_superior[:corner_nucleo,s,(k,j)]) * area_nucleo_depto +
                                                num_deptos_por_piso_superior[:d_corner_nucleo,s,(k,j)] * area_nucleo_depto_d_corner for s in S, (k, j) in KJ_feasible)

            # Total nucleo area for entire building
            area_nucleo_total, area_nucleo_primer_piso + area_nucleo_por_piso_superior * num_pisos_superiores

            # Total SNT area (interior + terrace + common areas)
            area_snt, area_interior_total + area_terraza_total + area_comun_total

            # Total count of all apartment types across all strips and floors
            deptos_total, total_num_deptos_primer_piso + total_num_deptos_por_piso_superior * num_pisos_superiores

        end)

        @constraints(model, begin

            # Upper floor and First floor footprint must equal building footprint (all areas sum to W × j)
            constraint_1, area_interior_primer_piso + area_terraza_primer_piso + 
                            area_nucleo_primer_piso + area_comun_primer_piso + 
                            area_no_utilizada_primer_piso == W * H
            constraint_2, area_interior_por_piso_superior + area_terraza_por_piso_superior + 
                            area_nucleo_por_piso_superior + area_comun_por_piso_superior + 
                            area_no_utilizada_por_piso_superior == W * H

            # Common area for first floor and upper floors must include at least all hallway areas
            constraint_3, area_comun_primer_piso == area_pasillo_primer_piso + area_nucleo_primer_piso +
                                                     (area_interior_por_piso_superior - area_interior_primer_piso)
            constraint_4, area_comun_por_piso_superior == area_pasillo_por_piso_superior + area_nucleo_por_piso_superior

            # First floor common area must be at least as large as upper floor common area
            constraint_5, area_comun_primer_piso >= area_comun_por_piso_superior

            # Buildability constraint: useful area + common area - DFL2 discount + unused util area equals maximum buildability
            constraint_6, area_util_total + area_comun_total - descuento_dfl2 + area_util_no_utilizada == max_constructibilidad

            # DFL2 discount cannot exceed 20% of useful area nor total common area
            constraint_7a, descuento_dfl2 <= flag_dfl2 * 0.2 * area_util_total
            constraint_7b, descuento_dfl2 <= flag_dfl2 * area_comun_total

            # Link apartment counts to y indicators for each type
            constraint_8a[t in T_regular, s in S], sum(num_deptos_por_piso_superior[t,s,(k,j)] for (k, j) in KJ_feasible) <= max_apts_per_strip_tight * y[t,s]
            constraint_8b[t in T_regular, s in S], sum(num_deptos_por_piso_superior[t,s,(k,j)] for (k, j) in KJ_feasible) >= y[t,s]

            # Exactly 2 corner or 2 corner nucleo apartments per strip if corner type is used
            constraint_9a[t in T_corner, s in S], sum(num_deptos_por_piso_superior[t,s,(k,j)] for (k, j) in KJ_feasible) <= max_corner_deptos_por_strip * y[t,s]
            constraint_9b[t in T_corner, s in S], sum(num_deptos_por_piso_superior[t,s,(k,j)] for (k, j) in KJ_feasible) >= y[t,s]

            # Apartment count is positive only if apartment type is selected (Big-M constraint linking binary and integer variables)
            constraint_10a[t in T_regular, s in S, (k, j) in KJ_feasible], num_deptos_por_piso_superior[t,s,(k,j)] <= max_apts_per_strip_tight * x[t,s,(k,j)]
            constraint_10b[t in T_corner, s in S, (k, j) in KJ_feasible], num_deptos_por_piso_superior[t,s,(k,j)] <= max_corner_deptos_por_strip * x[t,s,(k,j)]

            # Link y_active to configuration indicators (strip is active if any configuration is used)
            constraint_11a[t in T, s in S], y_active[s] >= y[t,s]
            constraint_11b[s in S], y_active[s] <= sum(y[t,s] for t in T)

            # Each strip can have at most one configuration type from incompatible groups
            constraint_12a[s in S], y[:regular,s] + y[:d_corner_nucleo,s] <= 1
            constraint_12b[s in S], y[:regular_nucleo,s] + y[:d_corner_nucleo,s] <= 1
            constraint_12c[s in S], y[:corner,s] + y[:d_corner_nucleo,s] <= 1
            constraint_12d[s in S], y[:corner_nucleo,s] + y[:d_corner_nucleo,s] <= 1
            
            constraint_12e[s in S], y[:regular,s] + y[:corner_nucleo,s] <= 1
            constraint_12f[s in S], y[:regular_nucleo,s] + y[:corner_nucleo,s] <= 1
            constraint_12g[s in S], y[:corner,s] + y[:corner_nucleo,s] <= 1

            # Total apartment count must be within specified bounds
            constraint_13a, deptos_total >= min_deptos
            constraint_13b, deptos_total <= max_deptos

            # Sum of all strip depths cannot exceed building depth
            constraint_14, sum(H_s[s] for s in S) == H

            # Each strip must have minimum depth
            constraint_15[s in S], H_s[s] >= (H - 3) / 2

            # Apartment height (interior + terrace) + unused depth equals strip depth for each apartment type
            constraint_16[t in T, s in S, (k, j) in KJ_feasible], x[t,s,(k,j)] * (mat_h_ipn_by_type[t](k,j) + mat_h_t[k,j])  <= H_s[s]

            # Total apartment area per strip cannot exceed strip footprint (W x H_s)
            constraint_17[s in S], sum(num_deptos_por_piso_superior[t,s,(k,j)] * (area_ipn_by_type[t](k,j) + vec_area_t[k]) for t in T, (k, j) in KJ_feasible) <= W * H_s[s]

            # Total apartment widths per strip cannot exceed building width W
            constraint_18[s in S], sum(num_deptos_por_piso_superior[t,s,(k,j)] * vec_w_i[j] for t in T, (k, j) in KJ_feasible) <= W

            # First floor apartment counts cannot exceed upper floor counts (first floor is subset of upper floors)
            constraint_19[t in T, s in S, (k, j) in KJ_feasible], num_deptos_primer_piso[t,s,(k,j)] <= num_deptos_por_piso_superior[t,s,(k,j)]

            # First floor must have at least one fewer apartment than upper floors
            constraint_20, total_num_deptos_primer_piso <= total_num_deptos_por_piso_superior - 1
        end)

        # Nucleo apartment count: each active strip must have exactly 2 nucleo apartments (regular, corner, or d-corner), except d-corner strips have only 1
        @constraints(model, begin
            constraint_21[s in S], sum(num_deptos_por_piso_superior[t,s,(k,j)] for t in T_nucleo, (k, j) in KJ_feasible) ==
                                   2 * y_active[s] - y[:d_corner_nucleo,s]
        end)

        # Symmetry breaking: order strips by total apartments to reduce search space
        @constraint(model, sum(sum(num_deptos_por_piso_superior[t,1,(k,j)] for t in T) for (k,j) in KJ_feasible) >=
                           sum(sum(num_deptos_por_piso_superior[t,2,(k,j)] for t in T) for (k,j) in KJ_feasible))

        # Link z[k] binary indicators to apartment type usage: z[k]=1 if apartment type k is used anywhere in the building
        KJ_by_k = [[(k, j) for (k, j) in KJ_feasible if k == k_target] for k_target in K]  # Nested array grouping KJ_feasible by apartment type: KJ_by_k[k] contains all (k,j) pairs for apartment type k
        for k in K
            sum_expr = @expression(model, sum(sum(x[t,s,kj] for t in T) for s in S, kj in KJ_by_k[k]))
            @constraint(model, z[k] <= sum_expr)
            @constraint(model, sum_expr <= length(S) * length(KJ_by_k[k]) * z[k])
        end

        # Prevent mixing apartment types with very different sizes (>2.5x ratio) to maintain market consistency
        for k1 in K, k2 in K
            if vec_area_i[k1] < vec_area_i[k2] && vec_area_i[k2] > vec_area_i[k1] * 2.5
                @constraint(model, z[k1] + z[k2] <= 1)
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

        ancho_depto_pp = Dict{Tuple{Int,Symbol,Int,Int},Float64}()
        ancho_depto_ps = Dict{Tuple{Int,Symbol,Int,Int},Float64}()
        profundidad_depto_ipn_ps = Dict{Tuple{Int,Symbol,Int,Int},Float64}()
        profundidad_depto_ipn_pp = Dict{Tuple{Int,Symbol,Int,Int},Float64}()
        profundidad_depto_i_ps = Dict{Tuple{Int,Symbol,Int,Int},Float64}()
        profundidad_depto_i_pp = Dict{Tuple{Int,Symbol,Int,Int},Float64}()
        if has_values(model)
            for s in S
                for t in T, (k, j) in KJ_feasible
                    if value(num_deptos_por_piso_superior[t,s,(k,j)]) > 0.01
                        ancho_depto_ps[(s,t,k,j)] = vec_w_i[j]
                        profundidad_depto_ipn_ps[(s,t,k,j)] = mat_h_ipn_by_type[t](k,j)
                        profundidad_depto_i_ps[(s,t,k,j)] = mat_h_i[k,j]
                    end
                    if value(num_deptos_primer_piso[t,s,(k,j)]) > 0.01
                        ancho_depto_pp[(s,t,k,j)] = vec_w_i[j]
                        profundidad_depto_ipn_pp[(s,t,k,j)] = mat_h_ipn_by_type[t](k,j)
                        profundidad_depto_i_pp[(s,t,k,j)] = mat_h_i[k,j]
                    end
                end
            end
        end

        # Block to adjust apartment widths if total width per strip is less than building width W
        ancho_depto_ajustado_pp = Dict{Tuple{Int,Symbol,Int,Int},Float64}()
        ancho_depto_ajustado_ps = Dict{Tuple{Int,Symbol,Int,Int},Float64}()
        if has_values(model)
            for s in S, t in T, (k, j) in KJ_feasible
                ancho_depto_ajustado_ps[(s,t,k,j)] = get(ancho_depto_ps, (s,t,k,j), 0.0)
                ancho_depto_ajustado_pp[(s,t,k,j)] = get(ancho_depto_pp, (s,t,k,j), 0.0)
            end

            for s in S
                total_width_ps = sum(value(num_deptos_por_piso_superior[t,s,(k,j)]) * vec_w_i[j] for t in T, (k, j) in KJ_feasible)

                if total_width_ps > 0.01 && total_width_ps < W - 0.01
                    scale_factor_ps = W / total_width_ps
                    println("Strip $(s) - Pisos Superiores: Total width $(round(total_width_ps, digits=2))m < W $(round(W, digits=2))m. Scaling by factor $(round(scale_factor_ps, digits=4))")

                    for t in T, (k, j) in KJ_feasible
                        ancho_depto_ajustado_ps[(s,t,k,j)] = get(ancho_depto_ps, (s,t,k,j), 0.0) * scale_factor_ps
                        ancho_depto_ajustado_pp[(s,t,k,j)] = get(ancho_depto_pp, (s,t,k,j), 0.0) * scale_factor_ps
                    end
                end
            end
        end

        results = OrderedDict{String,Any}()
        results["status"] = termination_status(model)
        results["solve_time"] = solve_time(model)
        results["deptos"] = OrderedDict{Int,Any}()
        results["strip"] = OrderedDict{Int,Any}()

        if has_values(model)
            results["objective_value"] = objective_value(model)
            results["num_pisos_superiores"] = num_pisos_superiores
            results["num_pisos_total"] = num_pisos
            results["flag_dfl2"] = flag_dfl2
            results["flag_vivienda_economica"] = flag_vivienda_economica
            results["angulo_rotacion"] = angulo_rotacion
            results["cr"] = cr
            results["ps_planta_normalizado"] = ps_planta_normalizado

            for s in S
                perimetro_s_pp = sum(value(num_deptos_primer_piso[t,s,(k,j)]) * mat_exposicion_by_type[t][k,j] for t in T, (k, j) in KJ_feasible)

                interior_area_s_pp = 0.0
                for t in T, (k, j) in KJ_feasible
                    num_apts = value(num_deptos_primer_piso[t,s,(k,j)])
                    if num_apts > 0.001
                        ancho = get(ancho_depto_ajustado_pp, (s,t,k,j), 0.0)
                        profundidad = get(profundidad_depto_ipn_pp, (s,t,k,j), 0.0)
                        area_total_ajustada = ancho * profundidad
                        if t == :regular || t == :regular_nucleo
                            area_target_total = vec_area_i[k] + vec_area_p[j]
                            fraccion_interior = vec_area_i[k] / area_target_total
                            interior_area_s_pp += num_apts * area_total_ajustada * fraccion_interior
                        else
                            interior_area_s_pp += num_apts * area_total_ajustada
                        end
                    end
                end

                terrace_area_s_pp = sum(value(num_deptos_primer_piso[t,s,(k,j)]) * vec_area_t[k] for t in T, (k, j) in KJ_feasible)

                pasillo_area_s_pp = 0.0
                for t in [:regular, :regular_nucleo], (k, j) in KJ_feasible
                    num_apts = value(num_deptos_primer_piso[t,s,(k,j)])
                    if num_apts > 0.001
                        ancho = ancho_depto_ajustado_pp[(s,t,k,j)]
                        profundidad = profundidad_depto_ipn_pp[(s,t,k,j)]
                        area_total_ajustada = ancho * profundidad
                        area_target_total = vec_area_i[k] + vec_area_p[j]
                        fraccion_pasillo = vec_area_p[j] / area_target_total
                        pasillo_area_s_pp += num_apts * area_total_ajustada * fraccion_pasillo
                    end
                end

                perimetro_s_ps = sum(value(num_deptos_por_piso_superior[t,s,(k,j)]) * mat_exposicion_by_type[t][k,j] for t in T, (k, j) in KJ_feasible)

                interior_area_s_ps = 0.0
                for t in T, (k, j) in KJ_feasible
                    num_apts = value(num_deptos_por_piso_superior[t,s,(k,j)])
                    if num_apts > 0.001
                        ancho = ancho_depto_ajustado_ps[(s,t,k,j)]
                        profundidad = profundidad_depto_ipn_ps[(s,t,k,j)]
                        area_total_ajustada = ancho * profundidad
                        if t in [:regular, :regular_nucleo]
                            area_target_total = vec_area_i[k] + vec_area_p[j]
                            fraccion_interior = vec_area_i[k] / area_target_total
                            interior_area_s_ps += num_apts * area_total_ajustada * fraccion_interior
                        else
                            interior_area_s_ps += num_apts * area_total_ajustada
                        end
                    end
                end

                terrace_area_s_ps = sum(value(num_deptos_por_piso_superior[t,s,(k,j)]) * vec_area_t[k] for t in T, (k, j) in KJ_feasible)

                pasillo_area_s_ps = 0.0
                for t in [:regular, :regular_nucleo], (k, j) in KJ_feasible
                    num_apts = value(num_deptos_por_piso_superior[t,s,(k,j)])
                    if num_apts > 0.001
                        ancho = ancho_depto_ajustado_ps[(s,t,k,j)]
                        profundidad = profundidad_depto_ipn_ps[(s,t,k,j)]
                        area_total_ajustada = ancho * profundidad
                        area_target_total = vec_area_i[k] + vec_area_p[j]
                        fraccion_pasillo = vec_area_p[j] / area_target_total
                        pasillo_area_s_ps += num_apts * area_total_ajustada * fraccion_pasillo
                    end
                end

                results["strip"][s] = OrderedDict{String,Any}()
                results["strip"][s]["strip"] = s
                results["strip"][s]["H_s"] = value(H_s[s])
                results["strip"][s]["perimetro_expuesto"] = OrderedDict{String,Float64}()
                results["strip"][s]["perimetro_expuesto"]["primer_piso"] = perimetro_s_pp
                results["strip"][s]["perimetro_expuesto"]["pisos_superiores"] = perimetro_s_ps
                results["strip"][s]["superficie_interior"] = OrderedDict{String,Float64}()
                results["strip"][s]["superficie_interior"]["primer_piso"] = interior_area_s_pp
                results["strip"][s]["superficie_interior"]["pisos_superiores"] = interior_area_s_ps
                results["strip"][s]["superficie_terraza"] = OrderedDict{String,Float64}()
                results["strip"][s]["superficie_terraza"]["primer_piso"] = terrace_area_s_pp
                results["strip"][s]["superficie_terraza"]["pisos_superiores"] = terrace_area_s_ps
                results["strip"][s]["superficie_pasillo"] = OrderedDict{String,Float64}()
                results["strip"][s]["superficie_pasillo"]["primer_piso"] = pasillo_area_s_pp
                results["strip"][s]["superficie_pasillo"]["pisos_superiores"] = pasillo_area_s_ps

                depto_index = 1
                for t in T, (k, j) in KJ_feasible
                    threshold = 0.001

                    num_unidades_pp = value(num_deptos_primer_piso[t,s,(k,j)])
                    num_unidades_ps = value(num_deptos_por_piso_superior[t,s,(k,j)])

                    if num_unidades_pp > threshold || num_unidades_ps > threshold
                        depto_index = length(results["deptos"]) + 1
                        results["deptos"][depto_index] = OrderedDict{String,Any}()

                        tipo = string(t)

                        results["deptos"][depto_index]["strip"] = s
                        results["deptos"][depto_index]["k"] = k
                        results["deptos"][depto_index]["j"] = j
                        results["deptos"][depto_index]["tipo"] = tipo
                        results["deptos"][depto_index]["ancho_interior"] = ancho_depto_ajustado_ps[(s,t,k,j)]
                        results["deptos"][depto_index]["profundidad_interior"] = profundidad_depto_i_ps[(s,t,k,j)]
                        results["deptos"][depto_index]["ancho_terraza"] = vec_area_t[k] / mat_h_t[k,j]
                        results["deptos"][depto_index]["profundidad_terraza"] = mat_h_t[k,j]
                        results["deptos"][depto_index]["num_unidades_primer_piso"] = num_unidades_pp
                        results["deptos"][depto_index]["num_unidades_por_piso_superior"] = num_unidades_ps
                        results["deptos"][depto_index]["num_unidades_edificio"] = num_unidades_pp + num_unidades_ps * num_pisos_superiores

                        ancho = get(ancho_depto_ajustado_ps, (s,t,k,j), 0.0)
                        profundidad = get(profundidad_depto_ipn_ps, (s,t,k,j), 0.0)
                        area_total_ajustada = ancho * profundidad

                        if t == :regular || t == :regular_nucleo
                            area_target_total = vec_area_i[k] + vec_area_p[j]
                            fraccion_interior = vec_area_i[k] / area_target_total
                            fraccion_pasillo = vec_area_p[j] / area_target_total
                            results["deptos"][depto_index]["sup_interior"] = area_total_ajustada * fraccion_interior
                            results["deptos"][depto_index]["sup_pasillo"] = area_total_ajustada * fraccion_pasillo
                        else
                            results["deptos"][depto_index]["sup_interior"] = area_total_ajustada
                            results["deptos"][depto_index]["sup_pasillo"] = 0.0
                        end

                        results["deptos"][depto_index]["sup_terraza"] = vec_area_t[k]

                        if t == :regular_nucleo || t == :corner_nucleo
                            results["deptos"][depto_index]["sup_nucleo"] = area_nucleo_depto
                        elseif t == :d_corner_nucleo
                            results["deptos"][depto_index]["sup_nucleo"] = area_nucleo_depto_d_corner
                        end
                    end
                end
            end

            deptos_primer_piso = 0.0
            deptos_pisos_superiores = 0.0
            for depto_data in values(results["deptos"])
                deptos_primer_piso += depto_data["num_unidades_primer_piso"]
                deptos_pisos_superiores += depto_data["num_unidades_por_piso_superior"]
            end

            sup_int_pp = sum(results["strip"][s]["superficie_interior"]["primer_piso"] for s in S)
            sup_terr_pp = sum(results["strip"][s]["superficie_terraza"]["primer_piso"] for s in S)
            sup_pas_pp = sum(results["strip"][s]["superficie_pasillo"]["primer_piso"] for s in S)

            sup_int_ps = sum(results["strip"][s]["superficie_interior"]["pisos_superiores"] for s in S)
            sup_terr_ps = sum(results["strip"][s]["superficie_terraza"]["pisos_superiores"] for s in S)
            sup_pas_ps = sum(results["strip"][s]["superficie_pasillo"]["pisos_superiores"] for s in S)

            results["totals"] = OrderedDict{String,Any}()
            results["totals"]["deptos"] = OrderedDict{String,Float64}()
            results["totals"]["deptos"]["primer_piso"] = deptos_primer_piso
            results["totals"]["deptos"]["pisos_superiores"] = deptos_pisos_superiores
            results["totals"]["deptos"]["edificio"] = deptos_primer_piso + deptos_pisos_superiores * num_pisos_superiores

            results["totals"]["superficie_interior"] = OrderedDict{String,Float64}()
            results["totals"]["superficie_interior"]["primer_piso"] = sup_int_pp
            results["totals"]["superficie_interior"]["pisos_superiores"] = sup_int_ps
            results["totals"]["superficie_interior"]["edificio"] = sup_int_pp + sup_int_ps * num_pisos_superiores

            results["totals"]["superficie_terraza"] = OrderedDict{String,Float64}()
            results["totals"]["superficie_terraza"]["primer_piso"] = sup_terr_pp
            results["totals"]["superficie_terraza"]["pisos_superiores"] = sup_terr_ps
            results["totals"]["superficie_terraza"]["edificio"] = sup_terr_pp + sup_terr_ps * num_pisos_superiores

            area_nucleo_pp = 0.0
            area_nucleo_ps = 0.0
            for depto_data in values(results["deptos"])
                tipo = depto_data["tipo"]
                if tipo == "regular_nucleo" || tipo == "corner_nucleo"
                    area_nucleo_pp += depto_data["num_unidades_primer_piso"] * area_nucleo_depto
                    area_nucleo_ps += depto_data["num_unidades_por_piso_superior"] * area_nucleo_depto
                elseif tipo == "d_corner_nucleo"
                    area_nucleo_pp += depto_data["num_unidades_primer_piso"] * area_nucleo_depto_d_corner
                    area_nucleo_ps += depto_data["num_unidades_por_piso_superior"] * area_nucleo_depto_d_corner
                end
            end

            results["totals"]["superficie_nucleo"] = OrderedDict{String,Float64}()
            results["totals"]["superficie_nucleo"]["primer_piso"] = area_nucleo_pp
            results["totals"]["superficie_nucleo"]["pisos_superiores"] = area_nucleo_ps
            results["totals"]["superficie_nucleo"]["edificio"] = area_nucleo_pp + area_nucleo_ps * num_pisos_superiores

            results["totals"]["superficie_pasillo"] = OrderedDict{String,Float64}()
            results["totals"]["superficie_pasillo"]["primer_piso"] = sup_pas_pp
            results["totals"]["superficie_pasillo"]["pisos_superiores"] = sup_pas_ps
            results["totals"]["superficie_pasillo"]["edificio"] = sup_pas_pp + sup_pas_ps * num_pisos_superiores

            area_comun_pp_ajustada = sup_pas_pp + area_nucleo_pp + (sup_int_ps - sup_int_pp)
            area_comun_ps_ajustada = sup_pas_ps + area_nucleo_ps

            results["totals"]["superficie_comun"] = OrderedDict{String,Float64}()
            results["totals"]["superficie_comun"]["primer_piso"] = area_comun_pp_ajustada
            results["totals"]["superficie_comun"]["pisos_superiores"] = area_comun_ps_ajustada
            results["totals"]["superficie_comun"]["edificio"] = area_comun_pp_ajustada + area_comun_ps_ajustada * num_pisos_superiores

            results["totals"]["superficie_otros_espacios"] = OrderedDict{String,Float64}()
            results["totals"]["superficie_otros_espacios"]["primer_piso"] = area_comun_pp_ajustada - sup_pas_pp - area_nucleo_pp
            results["totals"]["superficie_otros_espacios"]["pisos_superiores"] = area_comun_ps_ajustada - sup_pas_ps - area_nucleo_ps
            results["totals"]["superficie_otros_espacios"]["edificio"] = (area_comun_pp_ajustada - sup_pas_pp - area_nucleo_pp) + (area_comun_ps_ajustada - sup_pas_ps - area_nucleo_ps) * num_pisos_superiores

            area_emplazamiento_por_piso = W * H
            area_no_utilizada_pp_calc = area_emplazamiento_por_piso - (sup_int_pp + sup_terr_pp + area_comun_pp_ajustada)
            area_no_utilizada_ps_calc = area_emplazamiento_por_piso - (sup_int_ps + sup_terr_ps + area_comun_ps_ajustada)

            results["totals"]["superficie_no_utilizada"] = OrderedDict{String,Float64}()
            results["totals"]["superficie_no_utilizada"]["primer_piso"] = area_no_utilizada_pp_calc
            results["totals"]["superficie_no_utilizada"]["pisos_superiores"] = area_no_utilizada_ps_calc
            results["totals"]["superficie_no_utilizada"]["edificio"] = area_no_utilizada_pp_calc + area_no_utilizada_ps_calc * num_pisos_superiores

            results["superficie_interior_edificio"] = results["totals"]["superficie_interior"]["edificio"]
            results["superficie_terraza_edificio"] = results["totals"]["superficie_terraza"]["edificio"]

       else
            results["objective_value"] = nothing
            results["total_deptos"] = 0.0
            results["superficie_interior_edificio"] = 0.0
            results["superficie_terraza_edificio"] = 0.0
            println("\n⚠️  WARNING: No feasible solution found!")
            println("Status: $(results["status"])")
        end
        return results, W, H, angulo_rotacion
    end


    vec_area_i, vec_area_t, vec_area_p, mat_h_t,
    vec_w_i, mat_h_ip, mat_h_ipn, mat_h_in, mat_h_in_d_corner,
    area_nucleo_depto, area_nucleo_depto_d_corner = compute_arquitectura_params(dict_arquitectura)

    total_threads = Threads.nthreads()

    println("Running layouts SEQUENTIALLY ($(total_threads) threads for HiGHS solver)")

    results_1, W_1, H_1, angulo_1 = opti_planta_edificio_layout(vec_area_i, vec_area_t, vec_area_p, mat_h_t, vec_w_i,
                                mat_h_ip, mat_h_ipn, mat_h_in, mat_h_in_d_corner,
                                area_nucleo_depto, area_nucleo_depto_d_corner,
                                max_constructibilidad, max_deptos,
                                vec_ps_opt, vec_np_opt, flag_dfl2, flag_vivienda_economica,
                                1, total_threads)

    results_2, W_2, H_2, angulo_2 = opti_planta_edificio_layout(vec_area_i, vec_area_t, vec_area_p, mat_h_t, vec_w_i,
                                mat_h_ip, mat_h_ipn, mat_h_in, mat_h_in_d_corner,
                                area_nucleo_depto, area_nucleo_depto_d_corner,
                                max_constructibilidad, max_deptos,
                                vec_ps_opt, vec_np_opt, flag_dfl2, flag_vivienda_economica,
                                2, total_threads)

    area_util_1 = results_1["superficie_interior_edificio"] + results_1["superficie_terraza_edificio"] * 0.5
    area_util_2 = results_2["superficie_interior_edificio"] + results_2["superficie_terraza_edificio"] * 0.5

    println("\n" * "="^60)
    println("LAYOUT COMPARISON")
    println("="^60)
    println("Layout 1 (norte/sur): W=$(round(W_1, digits=2))m × H=$(round(H_1, digits=2))m, Angle=$(round(rad2deg(angulo_1), digits=1))° → Área Útil = $(round(area_util_1, digits=2)) m²")
    println("Layout 2 (oriente/poniente):   W=$(round(W_2, digits=2))m × H=$(round(H_2, digits=2))m, Angle=$(round(rad2deg(angulo_2), digits=1))° → Área Útil = $(round(area_util_2, digits=2)) m²")

    if area_util_2 > area_util_1
        results = results_2
        W = W_2
        H = H_2
        best_layout = 2
        println("\n✓ Best layout: Layout 2 (oriente/poniente) - $(round(area_util_2 - area_util_1, digits=2)) m² better")
        results["best_layout"] = 2
    else
        results = results_1
        W = W_1
        H = H_1
        best_layout = 1
        println("\n✓ Best layout: Layout 1 (norte/sur) - $(round(area_util_1 - area_util_2, digits=2)) m² better")
        results["best_layout"] = 1
    end

    results["W"] = W
    results["H"] = H

    # Convert to DataFrame
    df_deptos = DataFrame()
    for (depto_id, depto_data) in results["deptos"]
        row = Dict{Symbol, Any}()
        row[:depto_id] = depto_id
        for (key, value) in depto_data
            row[Symbol(key)] = value
        end        
        push!(df_deptos, row, cols=:union)
    end
    results["df_deptos"] = df_deptos

    results["ps_planta"] = vec_ps_opt[1]

    println("="^60)

    return results
end
