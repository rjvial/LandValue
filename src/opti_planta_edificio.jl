# ============================================================================
# STREET PARALLEL EVALUATION
# Determines which building strip faces the street for terrace placement
# ============================================================================

function evalua_strip_paralelo_calle(ps_calles, angulo_rotacion, cr, best_layout, ps_planta_normalizado)
    ps_calle_paralela_empty = PolyShape(Vector{Matrix{Float64}}(), 0)

    if isnothing(ps_calles) || isempty(ps_calles.Vertices)
        return false, false, ps_calle_paralela_empty
    end

    vec_edges_calle, _ = polyShape.shape2vector(ps_calles)

    if isempty(vec_edges_calle)
        return false, false, ps_calle_paralela_empty
    end

    # Calculate center of normalized floor plan in original coordinates
    V_planta_norm = ps_planta_normalizado.Vertices[1]
    centro_x_norm = (maximum(V_planta_norm[:, 1]) + minimum(V_planta_norm[:, 1])) / 2
    centro_y_norm = (maximum(V_planta_norm[:, 2]) + minimum(V_planta_norm[:, 2])) / 2

    centro_original = polyShape.polyRotate(
        PolyShape([Float64[centro_x_norm centro_y_norm; centro_x_norm centro_y_norm]], 1),
        -angulo_rotacion,
        cr
    ).Vertices[1][1, :]

    tolerancia_angulo = deg2rad(20.0)

    # Reference angle depends on layout orientation
    if best_layout == 1
        angulo_strip_ref_norm = pi/2
    else
        angulo_strip_ref_norm = 0.0
    end
    angulo_strip_ref = angulo_strip_ref_norm - angulo_rotacion

    # Helper: check if two angles are parallel (within tolerance)
    function angulo_paralelo(ang1, ang2, tol)
        diff = abs(ang1 - ang2)
        diff = min(diff, 2*pi - diff)
        diff_180 = abs(diff - pi)
        return diff < tol || diff_180 < tol
    end

    # Helper: calculate centroid of edge
    function centroide_edge(edge)
        V = edge.Vertices[1]
        cx = sum(V[:, 1]) / size(V, 1)
        cy = sum(V[:, 2]) / size(V, 1)
        return cx, cy
    end

    # Helper: signed distance from point to strip direction
    function signed_distance_to_strip(cx, cy, centro, angulo_normal)
        dx = cx - centro[1]
        dy = cy - centro[2]
        return dx * cos(angulo_normal) + dy * sin(angulo_normal)
    end

    # Normal angles for each strip depend on layout
    if best_layout == 1
        angulo_normal_strip1 = pi/2 - angulo_rotacion
        angulo_normal_strip2 = -pi/2 - angulo_rotacion
    else
        angulo_normal_strip1 = 0.0 - angulo_rotacion
        angulo_normal_strip2 = pi - angulo_rotacion
    end

    dist_min_strip1 = Inf
    dist_min_strip2 = Inf
    found_parallel_strip1 = false
    found_parallel_strip2 = false

    # Find closest parallel street edge to each strip
    for edge in vec_edges_calle
        angulo = polyShape.lineAngle(edge)
        largo = polyShape.lineLength(edge)

        if largo <= 2.0
            continue
        end

        if !angulo_paralelo(angulo, angulo_strip_ref, tolerancia_angulo)
            continue
        end

        cx, cy = centroide_edge(edge)

        dist_to_strip1 = signed_distance_to_strip(cx, cy, centro_original, angulo_normal_strip1)
        dist_to_strip2 = signed_distance_to_strip(cx, cy, centro_original, angulo_normal_strip2)

        if dist_to_strip1 > 0 && dist_to_strip1 < dist_min_strip1
            dist_min_strip1 = dist_to_strip1
            found_parallel_strip1 = true
        end
        if dist_to_strip2 > 0 && dist_to_strip2 < dist_min_strip2
            dist_min_strip2 = dist_to_strip2
            found_parallel_strip2 = true
        end
    end

    # Assign street to closest strip
    strip1_paralelo = false
    strip2_paralelo = false
    ps_calle_paralela_strip1 = ps_calle_paralela_empty
    ps_calle_paralela_strip2 = ps_calle_paralela_empty

    if found_parallel_strip1 && !found_parallel_strip2
        strip1_paralelo = true
        ps_calle_paralela_strip1 = ps_calles
    elseif found_parallel_strip2 && !found_parallel_strip1
        strip2_paralelo = true
        ps_calle_paralela_strip2 = ps_calles
    elseif found_parallel_strip1 && found_parallel_strip2
        if dist_min_strip1 <= dist_min_strip2
            strip1_paralelo = true
            ps_calle_paralela_strip1 = ps_calles
        else
            strip2_paralelo = true
            ps_calle_paralela_strip2 = ps_calles
        end
    end

    return strip1_paralelo, strip2_paralelo, ps_calle_paralela_strip1, ps_calle_paralela_strip2
end

# ============================================================================
# BUILDING FLOOR PLAN OPTIMIZATION
# Main function that optimizes apartment distribution across building floors
# Uses MIP optimization to maximize usable area while respecting constraints
# ============================================================================

function opti_planta_edificio(dict_arquitectura, max_constructibilidad, max_deptos, ps_opt, np_opt, ps_calles=nothing)

    # -------------------------------------------------------------------------
    # HELPER: Normalize floor plan to axis-aligned rectangle
    # -------------------------------------------------------------------------
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

    # -------------------------------------------------------------------------
    # HELPER: Generate all feasible apartment configurations (width x height)
    # -------------------------------------------------------------------------
    function compute_depto_configs(vec_area_depto, vec_area_t, dict_arquitectura, flag_especial=false)
        vec_w = collect(6.0:0.5:25.0) #width interior deptos
        vec_h = collect(5.0:0.5:14.0) #height interior deptos
        min_h_terraza = 1.5
        max_h_terraza = 2.0

        depto_configs = Vector{NamedTuple{(:w, :h, :area, :h_t, :area_t), Tuple{Float64, Float64, Float64, Float64, Float64}}}()

        for w in vec_w
            for h in vec_h
                aspect_ratio = h / w
                area = w * h
                if aspect_ratio >= 0.4 && aspect_ratio <= 2.5 && area >= 24.0
                    area_t_target = interpolate_terrace_area(area, vec_area_depto, vec_area_t)
                    h_t = clamp(area_t_target / w, min_h_terraza, max_h_terraza)
                    area_t = w * h_t
                    area_util = area + 0.5 * area_t
                    if area_util <= 140.0 * flag_especial + maximum(dict_arquitectura["arq_vecSupUtil"]) * (!flag_especial)
                        push!(depto_configs, (w=w, h=h, area=area, h_t=h_t, area_t=area_t))
                    end
                end
            end
        end

        return depto_configs
    end

    # -------------------------------------------------------------------------
    # HELPER: Interpolate terrace area based on apartment interior area
    # -------------------------------------------------------------------------
    function interpolate_terrace_area(area::Float64, vec_area_depto::Vector{Float64}, vec_area_t::Vector{Float64})
        if area <= vec_area_depto[1]
            return vec_area_t[1]
        elseif area >= vec_area_depto[end]
            return vec_area_t[end]
        end

        for i in 1:(length(vec_area_depto)-1)
            if area >= vec_area_depto[i] && area <= vec_area_depto[i+1]
                t = (area - vec_area_depto[i]) / (vec_area_depto[i+1] - vec_area_depto[i])
                return vec_area_t[i] + t * (vec_area_t[i+1] - vec_area_t[i])
            end
        end

        return vec_area_t[end]
    end

    # -------------------------------------------------------------------------
    # HELPER: Generate sequences of similar-sized apartments (max_ratio constraint)
    # -------------------------------------------------------------------------
    function generate_area_sequences(I_dim_feasible, depto_configs, max_ratio)
        areas = [(i, depto_configs[i].area) for i in I_dim_feasible]
        sort!(areas, by=x->x[2])

        sequences = Vector{Vector{Int}}()
        for start_idx in eachindex(areas)
            min_area = areas[start_idx][2]
            seq = [areas[start_idx][1]]
            for j in (start_idx+1):lastindex(areas)
                if areas[j][2] / min_area <= max_ratio
                    push!(seq, areas[j][1])
                else
                    break
                end
            end
            push!(sequences, seq)
        end
        return sequences
    end

    # =========================================================================
    # CORE: MIP optimization for a single layout orientation
    # =========================================================================
    function opti_planta_edificio_layout(depto_configs, max_constructibilidad, max_deptos,
                                ps_opt, np_opt, layout, num_threads_highs, flag_especial)

        W, H, angulo_rotacion, cr, ps_planta_normalizado = normaliza_planta_rectangular(ps_opt, layout)

        min_deptos = 4
        num_pisos = np_opt
        num_strips = 2

        # Filter configs that fit within floor dimensions
        I = 1:length(depto_configs)
        S = 1:num_strips

        I_dim_feasible = [i for i in I if depto_configs[i].h <= H/2 + 1 && depto_configs[i].w <= W]
        sequences = generate_area_sequences(I_dim_feasible, depto_configs, 2.0)
        K = 1:length(sequences)
        I_feasible = I_dim_feasible

        # Setup HiGHS MIP solver
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

        min_width = minimum(cfg.w for cfg in depto_configs)
        max_apts_per_strip = floor(Int, W / min_width)

        # Decision variables
        @variables(model, begin
            H_s[s in S] >= 0
            0 <= n[i in I_feasible, s in S] <= max_apts_per_strip, Int
            x[i in I_feasible, s in S], Bin
            0 <= n_primer[i in I_feasible, s in S] <= max_apts_per_strip, Int
            area_util_no_utilizada >= 0
            z[k in K], Bin
        end)

        # Computed expressions for areas and counts
        @expressions(model, begin
            total_num_deptos_por_piso, sum(n[i,s] for i in I_feasible, s in S)
            area_interior_bruta_por_piso, sum(n[i,s] * depto_configs[i].area for i in I_feasible, s in S)
            area_terraza_por_piso, sum(n[i,s] * depto_configs[i].area_t for i in I_feasible, s in S)
            total_num_deptos_primer_piso, sum(n_primer[i,s] for i in I_feasible, s in S)
            area_interior_bruta_primer_piso, sum(n_primer[i,s] * depto_configs[i].area for i in I_feasible, s in S)
            area_terraza_primer_piso, sum(n_primer[i,s] * depto_configs[i].area_t for i in I_feasible, s in S)
            area_interior_bruta_total, area_interior_bruta_primer_piso + area_interior_bruta_por_piso * (num_pisos - 1)
            area_terraza_total, area_terraza_primer_piso + area_terraza_por_piso * (num_pisos - 1)
            area_interior_total, area_interior_bruta_total * OPTI_CONFIG["interior_factor"] / (OPTI_CONFIG["interior_factor"] + flag_especial * OPTI_CONFIG["common_areas_factor"])
            area_util_total, area_interior_total + 0.5 * area_terraza_total
            deptos_total, total_num_deptos_primer_piso + total_num_deptos_por_piso * (num_pisos - 1)
        end)

        # Building and geometric constraints
        @constraints(model, begin
            constraint_buildability, area_util_total <= max_constructibilidad
            constraint_min_deptos, deptos_total >= min_deptos
            constraint_max_deptos, deptos_total <= max_deptos
            constraint_strip_depth_sum, sum(H_s[s] for s in S) == H
            constraint_strip_min_depth[s in S], H_s[s] >= H / 2 - 1 
            constraint_depto_height[i in I_feasible, s in S], x[i,s] * (depto_configs[i].h + depto_configs[i].h_t) <= H_s[s]
            constraint_strip_area[s in S], sum(n[i,s] * (depto_configs[i].area + depto_configs[i].area_t) for i in I_feasible) <= W * H_s[s]
            constraint_strip_width[s in S], sum(n[i,s] * depto_configs[i].w for i in I_feasible) <= W
            constraint_link_n_x[i in I_feasible, s in S], n[i,s] <= max_apts_per_strip * x[i,s]
            constraint_primer_subset[i in I_feasible, s in S], n_primer[i,s] <= n[i,s]
            constraint_primer_fewer_deptos, total_num_deptos_primer_piso <= total_num_deptos_por_piso - 1
        end)

        # Sequence constraint: only one apartment size sequence allowed
        @constraint(model, constraint_one_sequence, sum(z[k] for k in K) == 1)

        # Link apartment types to selected sequence
        for i in I_feasible
            sequences_with_i = [k for k in K if i in sequences[k]]
            if length(sequences_with_i) < length(K)
                @constraint(model, [s in S], n[i,s] <= max_apts_per_strip * sum(z[k] for k in sequences_with_i))
            end
        end

        # Symmetry breaking: strip 1 has at least as many apartments as strip 2
        @constraint(model, sum(n[i,1] for i in I_feasible) >= sum(n[i,2] for i in I_feasible))

        # Objective: maximize total usable area
        @objective(model, Max, area_util_total)

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

        # Process optimization results
        results = OrderedDict{String,Any}()
        df_deptos_data = []

        if has_values(model)
            results["angulo_rotacion"] = angulo_rotacion
            results["cr"] = cr
            results["ps_planta_normalizado"] = ps_planta_normalizado

            for s in S
                results["strip_$(s)_H_s"] = value(H_s[s])

                total_width = sum(value(n[i,s]) * depto_configs[i].w for i in I_feasible)
                scale_factor = (total_width > 0.01 && total_width < W - 0.01) ? W / total_width : 1.0

                for i in I_feasible
                    num_unidades_superior = round(Int, value(n[i,s]))
                    num_unidades_primer = round(Int, value(n_primer[i,s]))
                    if num_unidades_superior > 0.001 || num_unidades_primer > 0.001
                        cfg = depto_configs[i]
                        ancho_ajustado = cfg.w * scale_factor
                        profundidad_ajustada = cfg.h / scale_factor
                        profundidad_terraza_ajustada = cfg.h_t / scale_factor

                        # sup_interior_bruta = sup_interior + area_comun (prorrateo)
                        push!(df_deptos_data, (
                            strip = s,
                            sup_interior_bruta = ancho_ajustado * profundidad_ajustada,
                            sup_terraza = ancho_ajustado * profundidad_terraza_ajustada,
                            ancho_interior = ancho_ajustado,
                            profundidad_interior = profundidad_ajustada,
                            num_unidades_por_piso_superior = num_unidades_superior,
                            num_unidades_primer_piso = num_unidades_primer,
                            num_unidades_edificio = num_unidades_primer + num_unidades_superior * (num_pisos - 1),
                            sup_pasillo = 0.0,
                            sup_nucleo = 0.0
                        ))
                    end
                end
            end

            deptos_por_piso_superior = sum(value(n[i,s]) for i in I_feasible, s in S)
            deptos_primer_piso = sum(value(n_primer[i,s]) for i in I_feasible, s in S)

            sup_int_bruta_superior = 0.0
            sup_terr_superior = 0.0
            sup_int_bruta_primer = 0.0
            sup_terr_primer = 0.0
            for depto_data in df_deptos_data
                sup_int_bruta_superior += depto_data.num_unidades_por_piso_superior * depto_data.sup_interior_bruta
                sup_terr_superior += depto_data.num_unidades_por_piso_superior * depto_data.sup_terraza
                sup_int_bruta_primer += depto_data.num_unidades_primer_piso * depto_data.sup_interior_bruta
                sup_terr_primer += depto_data.num_unidades_primer_piso * depto_data.sup_terraza
            end

            results["num_deptos_edificio"] = deptos_primer_piso + deptos_por_piso_superior * (num_pisos - 1)
            results["sup_interior_bruta_primer_piso"] = sup_int_bruta_primer
            results["sup_interior_bruta_pisos_superiores"] = sup_int_bruta_superior
            results["sup_interior_bruta_edificio"] = sup_int_bruta_primer + sup_int_bruta_superior * (num_pisos - 1)
            results["sup_terraza_primer_piso"] = sup_terr_primer
            results["sup_terraza_pisos_superiores"] = sup_terr_superior
            results["sup_terraza_edificio"] = sup_terr_primer + sup_terr_superior * (num_pisos - 1)
            results["df_deptos"] = DataFrame(df_deptos_data)

        else
            results["sup_interior_bruta_edificio"] = 0.0
            results["sup_terraza_edificio"] = 0.0
            results["num_deptos_edificio"] = 0.0
            results["sup_interior_bruta_primer_piso"] = 0.0
            results["sup_interior_bruta_pisos_superiores"] = 0.0
            results["sup_terraza_primer_piso"] = 0.0
            results["sup_terraza_pisos_superiores"] = 0.0
            results["df_deptos"] = DataFrame()
            println("\n⚠️  WARNING: No feasible solution found!")
        end
        return results, W, H, angulo_rotacion
    end

    # =========================================================================
    # MAIN EXECUTION: Run optimization for both layout orientations
    # =========================================================================

    vec_area_t = dict_arquitectura["arq_vecSupTerraza"]
    vec_area_depto = dict_arquitectura["arq_vecSupInterior"]

    flag_especial = dict_arquitectura["arq_variante_normativa"] in ["vivienda_economica", "dfl2"]
    depto_configs = compute_depto_configs(vec_area_depto, vec_area_t, dict_arquitectura, flag_especial)

    # Run both layout orientations and compare
    total_threads = Threads.nthreads()
    println("Running layouts SEQUENTIALLY ($(total_threads) threads for HiGHS solver)")
    results_1, W_1, H_1, angulo_1 = opti_planta_edificio_layout(depto_configs, max_constructibilidad, max_deptos,
                                ps_opt, np_opt, 1, total_threads, flag_especial)
    results_2, W_2, H_2, angulo_2 = opti_planta_edificio_layout(depto_configs, max_constructibilidad, max_deptos,
                                ps_opt, np_opt, 2, total_threads, flag_especial)

    # Select best layout based on usable area
    area_util_1 = results_1["sup_interior_bruta_edificio"] + results_1["sup_terraza_edificio"] * 0.5
    area_util_2 = results_2["sup_interior_bruta_edificio"] + results_2["sup_terraza_edificio"] * 0.5

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
    results["ps_planta"] = ps_opt
    results["flag_dfl2"] = false
    results["flag_vivienda_economica"] = false

    # Determine which strip faces the street (for terrace orientation)
    strip1_paralelo, strip2_paralelo, ps_calle_paralela_strip1, ps_calle_paralela_strip2 = evalua_strip_paralelo_calle(
        ps_calles,
        results["angulo_rotacion"],
        results["cr"],
        best_layout,
        results["ps_planta_normalizado"]
    )
    results["strip_1_paralelo_calle"] = strip1_paralelo
    results["strip_2_paralelo_calle"] = strip2_paralelo
    results["ps_calle_paralela_strip_1"] = ps_calle_paralela_strip1
    results["ps_calle_paralela_strip_2"] = ps_calle_paralela_strip2

    println("="^60)

    return results
end
