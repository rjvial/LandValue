"""
Optimiza la asignación de departamentos en strips para maximizar área útil.

Selecciona entre configuraciones de departamentos con anchos y alturas predefinidos.

# Argumentos
- `max_constructibilidad`: Constructibilidad máxima permitida (m²)
- `max_deptos::Int`: Número máximo de departamentos totales
- `vec_ps_opt`: Vector de PolyShape con plantas optimizadas
- `vec_np_opt`: Vector de número de pisos por planta
"""
function opti_planta_edificio(max_constructibilidad, max_deptos, vec_ps_opt, vec_np_opt)

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

    function compute_depto_configs()
        vec_w = collect(6.0:0.5:14.0)
        vec_h = collect(4.0:0.5:12.0)
        h_terraza = 2.0

        depto_configs = Vector{NamedTuple{(:w, :h, :area, :h_t, :area_t), Tuple{Float64, Float64, Float64, Float64, Float64}}}()

        for w in vec_w
            for h in vec_h
                aspect_ratio = h / w
                area = w * h
                area_t = w * h_terraza
                if aspect_ratio >= 0.4 && aspect_ratio <= 2.5 && area >= 24.0 && area <= 140.0
                    push!(depto_configs, (w=w, h=h, area=area, h_t=h_terraza, area_t=area_t))
                end
            end
        end

        return depto_configs
    end

    function opti_planta_edificio_layout(depto_configs, max_constructibilidad, max_deptos,
                                vec_ps_opt, vec_np_opt, layout, num_threads_highs)

        ps_planta = vec_ps_opt[1]
        W, H, angulo_rotacion, cr, ps_planta_normalizado = normaliza_planta_rectangular(ps_planta, layout)

        min_deptos = 4
        num_pisos = vec_np_opt[1]
        num_strips = 2

        I = 1:length(depto_configs)
        S = 1:num_strips

        I_feasible = [i for i in I if depto_configs[i].h <= H/2 + 1 && depto_configs[i].w <= W]

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


        @variables(model, begin
            H_s[s in S] >= 0
            0 <= n[i in I_feasible, s in S] <= max_apts_per_strip, Int
            x[i in I_feasible, s in S], Bin
            area_util_no_utilizada >= 0
        end)

        @expressions(model, begin
            total_num_deptos_por_piso, sum(n[i,s] for i in I_feasible, s in S)
            area_interior_por_piso, sum(n[i,s] * depto_configs[i].area for i in I_feasible, s in S)
            area_terraza_por_piso, sum(n[i,s] * depto_configs[i].area_t for i in I_feasible, s in S)
            area_interior_total, area_interior_por_piso * num_pisos
            area_terraza_total, area_terraza_por_piso * num_pisos
            area_util_total, area_interior_total + 0.5 * area_terraza_total
            deptos_total, total_num_deptos_por_piso * num_pisos
            area_no_utilizada_por_piso, W * H - area_interior_por_piso - area_terraza_por_piso
        end)

        @constraints(model, begin
            constraint_buildability, area_util_total + area_util_no_utilizada == max_constructibilidad
            constraint_min_deptos, deptos_total >= min_deptos
            constraint_max_deptos, deptos_total <= max_deptos
            constraint_strip_depth_sum, sum(H_s[s] for s in S) == H
            constraint_strip_min_depth[s in S], H_s[s] >= (H - 2) / 2
            constraint_depto_height[i in I_feasible, s in S], x[i,s] * (depto_configs[i].h + depto_configs[i].h_t) <= H_s[s]
            constraint_strip_area[s in S], sum(n[i,s] * (depto_configs[i].area + depto_configs[i].area_t) for i in I_feasible) <= W * H_s[s]
            constraint_strip_width[s in S], sum(n[i,s] * depto_configs[i].w for i in I_feasible) <= W
            constraint_link_n_x[i in I_feasible, s in S], n[i,s] <= max_apts_per_strip * x[i,s]
        end)

        @constraint(model, sum(n[i,1] for i in I_feasible) >= sum(n[i,2] for i in I_feasible))

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
                    num_unidades = value(n[i,s])
                    if num_unidades > 0.001
                        cfg = depto_configs[i]
                        ancho_ajustado = cfg.w * scale_factor
                        profundidad_ajustada = cfg.h / scale_factor
                        profundidad_terraza_ajustada = cfg.h_t / scale_factor

                        push!(df_deptos_data, (
                            strip = s,
                            tipo = "simple",
                            sup_interior = ancho_ajustado * profundidad_ajustada,
                            sup_terraza = ancho_ajustado * profundidad_terraza_ajustada,
                            ancho_interior = ancho_ajustado,
                            profundidad_interior = profundidad_ajustada,
                            num_unidades_por_piso_superior = num_unidades,
                            num_unidades_primer_piso = num_unidades,
                            num_unidades_edificio = num_unidades * num_pisos,
                            sup_pasillo = 0.0,
                            sup_nucleo = 0.0
                        ))
                    end
                end
            end

            deptos_por_piso = sum(value(n[i,s]) for i in I_feasible, s in S)

            sup_int = 0.0
            sup_terr = 0.0
            for depto_data in df_deptos_data
                sup_int += depto_data.num_unidades_por_piso_superior * depto_data.sup_interior
                sup_terr += depto_data.num_unidades_por_piso_superior * depto_data.sup_terraza
            end

            results["num_deptos_edificio"] = deptos_por_piso * num_pisos
            results["sup_interior_primer_piso"] = sup_int
            results["sup_interior_pisos_superiores"] = sup_int
            results["sup_interior_edificio"] = sup_int * num_pisos
            results["sup_terraza_primer_piso"] = sup_terr
            results["sup_terraza_pisos_superiores"] = sup_terr
            results["sup_terraza_edificio"] = sup_terr * num_pisos
            results["sup_comun_primer_piso"] = 0.0
            results["sup_comun_pisos_superiores"] = 0.0
            results["sup_comun_edificio"] = 0.0
            results["sup_no_utilizada_edificio"] = value(area_no_utilizada_por_piso) * num_pisos
            results["df_deptos"] = DataFrame(df_deptos_data)

        else
            results["sup_interior_edificio"] = 0.0
            results["sup_terraza_edificio"] = 0.0
            results["num_deptos_edificio"] = 0.0
            results["sup_interior_primer_piso"] = 0.0
            results["sup_interior_pisos_superiores"] = 0.0
            results["sup_terraza_primer_piso"] = 0.0
            results["sup_terraza_pisos_superiores"] = 0.0
            results["sup_comun_primer_piso"] = 0.0
            results["sup_comun_pisos_superiores"] = 0.0
            results["sup_comun_edificio"] = 0.0
            results["sup_no_utilizada_edificio"] = 0.0
            results["df_deptos"] = DataFrame()
            println("\n⚠️  WARNING: No feasible solution found!")
        end
        return results, W, H, angulo_rotacion
    end


    depto_configs = compute_depto_configs()

    total_threads = Threads.nthreads()

    println("Running layouts SEQUENTIALLY ($(total_threads) threads for HiGHS solver)")

    results_1, W_1, H_1, angulo_1 = opti_planta_edificio_layout(depto_configs, max_constructibilidad, max_deptos,
                                vec_ps_opt, vec_np_opt, 1, total_threads)

    results_2, W_2, H_2, angulo_2 = opti_planta_edificio_layout(depto_configs, max_constructibilidad, max_deptos,
                                vec_ps_opt, vec_np_opt, 2, total_threads)

    area_util_1 = results_1["sup_interior_edificio"] + results_1["sup_terraza_edificio"] * 0.5
    area_util_2 = results_2["sup_interior_edificio"] + results_2["sup_terraza_edificio"] * 0.5

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
    results["ps_planta"] = vec_ps_opt[1]
    results["flag_dfl2"] = false
    results["flag_vivienda_economica"] = false

    println("="^60)

    return results
end
