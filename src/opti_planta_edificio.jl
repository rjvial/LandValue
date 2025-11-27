
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


    function print_results(results::AbstractDict, vec_area_i, vec_area_t, vec_area_p, mat_h_t, vec_w_i,
                          mat_h_ip, mat_h_ipn, mat_h_in, mat_h_in_d_corner,
                          area_nucleo_depto, area_nucleo_depto_d_corner, W, H)

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
            totals = get(results, "totals", nothing)
            num_pisos_sup = get(results, "num_pisos_superiores", 1)

            if !isnothing(totals)
                println("Total departamentos edificio: $(round(totals["deptos"]["edificio"], digits=0))")
                println("  - Primer piso: $(round(totals["deptos"]["primer_piso"], digits=0)) deptos")
                println("  - Pisos superiores: $(round(totals["deptos"]["pisos_superiores"], digits=0)) deptos/piso × $(num_pisos_sup) pisos = $(round(totals["deptos"]["pisos_superiores"] * num_pisos_sup, digits=0)) deptos")
            end
        else
            println("Total departamentos: 0")
        end

        if !isnothing(results["objective_value"])
            totals = get(results, "totals", nothing)

            if !isnothing(totals)
                area_interior_pp = totals["superficie_interior"]["primer_piso"]
                area_terraza_pp = totals["superficie_terraza"]["primer_piso"]
                area_pasillo_pp = totals["superficie_pasillo"]["primer_piso"]
                area_comun_pp = totals["superficie_comun"]["primer_piso"]
                area_util_pp = area_interior_pp + area_terraza_pp / 2

                area_interior_ps = totals["superficie_interior"]["pisos_superiores"]
                area_terraza_ps = totals["superficie_terraza"]["pisos_superiores"]
                area_pasillo_ps = totals["superficie_pasillo"]["pisos_superiores"]
                area_comun_ps = totals["superficie_comun"]["pisos_superiores"]
                area_util_ps = area_interior_ps + area_terraza_ps / 2
            else
                area_interior_pp = area_terraza_pp = area_pasillo_pp = area_comun_pp = area_util_pp = 0.0
                area_interior_ps = area_terraza_ps = area_pasillo_ps = area_comun_ps = area_util_ps = 0.0
            end

            num_pisos_sup = get(results, "num_pisos_superiores", 1)
            num_pisos_total = get(results, "num_pisos_total", 1)

            area_total_losa_pp = area_interior_pp + area_terraza_pp + area_comun_pp
            area_total_losa_ps = area_interior_ps + area_terraza_ps + area_comun_ps
            area_total_losa_edificio = area_total_losa_pp + area_total_losa_ps * num_pisos_sup

            println("\n" * "="^80)
            println("RESUMEN DE ÁREAS POR PISO")
            println("="^80)
            println("")

            W_building = W
            H_building = H
            area_emplazamiento_por_piso = W_building * H_building
            area_emplazamiento_total = area_emplazamiento_por_piso * num_pisos_total

            area_no_utilizada_pp = area_emplazamiento_por_piso - (area_interior_pp + area_terraza_pp + area_comun_pp)
            area_no_utilizada_ps = area_emplazamiento_por_piso - (area_interior_ps + area_terraza_ps + area_comun_ps)
            area_no_utilizada_total = area_no_utilizada_pp + area_no_utilizada_ps * num_pisos_sup

            area_nucleo_depto_local = area_nucleo_depto
            area_nucleo_depto_d_corner_local = area_nucleo_depto_d_corner

            deptos_dict = get(results, "deptos", Dict())

            area_nucleo_pp = 0.0
            area_nucleo_ps = 0.0
            for depto_data in values(deptos_dict)
                tipo = depto_data["tipo"]
                if tipo == "regular_nucleo" || tipo == "corner_nucleo"
                    area_nucleo_pp += depto_data["num_unidades_primer_piso"] * area_nucleo_depto_local
                    area_nucleo_ps += depto_data["num_unidades_por_piso_superior"] * area_nucleo_depto_local
                elseif tipo == "d_corner_nucleo"
                    area_nucleo_pp += depto_data["num_unidades_primer_piso"] * area_nucleo_depto_d_corner_local
                    area_nucleo_ps += depto_data["num_unidades_por_piso_superior"] * area_nucleo_depto_d_corner_local
                end
            end
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
            println("    - Área Núcleo: espacio adicional ($(area_nucleo_depto_local) m² regular/corner, $(area_nucleo_depto_d_corner_local) m² double corner) por cada departamento tipo núcleo")
            println("    - Otros espacios: áreas comunes adicionales (lobbies, salas, etc.)")
            println("  • Área No Utilizada = espacio del emplazamiento no ocupado por deptos ni áreas comunes")
        end

        println("\n" * "="^180)
        println("ASIGNACIÓN DE DEPARTAMENTOS")
        println("="^180)

        all_deptos_global = []

        strip_data = get(results, "strip", Dict())
        tipo_map = Dict("regular"=>"Regular", "regular_nucleo"=>"Núcleo", "corner"=>"Corner", "corner_nucleo"=>"Corner Núcleo", "d_corner_nucleo"=>"D-Corner Núc.")
        tipo_piso_label_map = Dict("primer_piso"=>"1° Piso", "pisos_superiores"=>"Pisos Sup.")

        deptos_dict = get(results, "deptos", Dict())
        for depto_data in values(deptos_dict)
            strip = depto_data["strip"]
            k = depto_data["k"]
            j = depto_data["j"]
            tipo = depto_data["tipo"]
            tipo_label = tipo_map[tipo]

            strip_info = strip_data[strip]
            profundidad = strip_info["H_s"]
            perimetro_pp = strip_info["perimetro_expuesto"]["primer_piso"]
            perimetro_ps = strip_info["perimetro_expuesto"]["pisos_superiores"]

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
            else
                alto = mat_h_in_d_corner[k,j]
                area_pasillo = 0.0
                area_nucleo = area_nucleo_depto_d_corner_local
                area_total = area_interior + area_nucleo
            end

            count_pp = depto_data["num_unidades_primer_piso"]
            count_ps = depto_data["num_unidades_por_piso_superior"]

            if count_pp > 0.001
                piso_label = tipo_piso_label_map["primer_piso"]
                perimetro = perimetro_pp
                push!(all_deptos_global, (strip, piso_label, tipo_label, k, j, count_pp, area_interior, area_pasillo, area_nucleo, area_terraza, area_total, ancho, alto, perimetro, profundidad))
            end
            if count_ps > 0.001
                piso_label = tipo_piso_label_map["pisos_superiores"]
                perimetro = perimetro_ps
                push!(all_deptos_global, (strip, piso_label, tipo_label, k, j, count_ps, area_interior, area_pasillo, area_nucleo, area_terraza, area_total, ancho, alto, perimetro, profundidad))
            end
        end

        if !isempty(all_deptos_global)
            println("\n┌──────┬────────────┬──────────────┬──────┬────────┬───────┬──────────┬──────────┬──────────┬─────────┬──────────┬─────────┐")
            println("│Strip │ Piso       │ Tipo         │ (k,j)│ Unid.  │ Ancho │ Prof.    │ Interior │ Pasillo  │ Núcleo  │ Total    │ Terraza │")
            println("│      │            │              │      │        │ (m)   │ (m)      │ (m²)     │ (m²)     │ (m²)    │ (m²)     │ (m²)    │")
            println("├──────┼────────────┼──────────────┼──────┼────────┼───────┼──────────┼──────────┼──────────┼─────────┼──────────┼─────────┤")

            current_strip = nothing
            for (strip, piso, tipo, k, j, count, area_int, area_pas, area_nuc, area_terr, area_tot, ancho, alto, _, _) in all_deptos_global
                if current_strip !== nothing && strip != current_strip
                    println("├──────┼────────────┼──────────────┼──────┼────────┼───────┼──────────┼──────────┼──────────┼─────────┼──────────┼─────────┤")
                end
                current_strip = strip

                println("│  $(lpad(strip, 2))  │ $(rpad(piso, 10)) │ $(rpad(tipo, 12)) │ $(lpad("($k,$j)", 4)) │ $(lpad(round(Int, count), 4))   │ $(lpad(round(ancho, digits=1), 5)) │ $(lpad(round(alto, digits=1), 8)) │ $(lpad(round(area_int, digits=1), 8)) │ $(lpad(round(area_pas, digits=1), 8)) │ $(lpad(round(area_nuc, digits=1), 7)) │ $(lpad(round(area_tot, digits=1), 8)) │ $(lpad(round(area_terr, digits=1), 7)) │")
            end

            println("└──────┴────────────┴──────────────┴──────┴────────┴───────┴──────────┴──────────┴──────────┴─────────┴──────────┴─────────┘")
            println("\nNotas:")
            println("  • Total = área del rectángulo principal (Ancho × Profundidad para Regular/Núcleo, solo Interior para Corner)")
            println("  • Terraza está fuera del rectángulo principal")
        end
        println("\n" * "="^180)
    end

    function compute_arquitectura_params(dict_arquitectura)
        vec_area_i_original = dict_arquitectura["arq_vecSupInterior"]
        vec_area_i = Float64[]
        for i in eachindex(vec_area_i_original)
            push!(vec_area_i, vec_area_i_original[i])
            if i < lastindex(vec_area_i_original)
                step = (vec_area_i_original[i+1] - vec_area_i_original[i]) / 5
                push!(vec_area_i, vec_area_i_original[i] + step)
                push!(vec_area_i, vec_area_i_original[i] + 2*step)
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
                step = (vec_area_t_original[i+1] - vec_area_t_original[i]) / 5
                push!(vec_area_t_temp, vec_area_t_original[i] + step)
                push!(vec_area_t_temp, vec_area_t_original[i] + 2*step)
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

        vec_area_in = vec_area_i .+ area_nucleo_depto
        vec_area_in_d_corner = vec_area_i .+ area_nucleo_depto_d_corner
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

        KJ_feasible = [(k, j) for k in K, j in J if mat_flag_feasible[k, j] > 0]

        model = Model(HiGHS.Optimizer)
        set_silent(model)
        set_time_limit_sec(model, 300.0)
        set_optimizer_attribute(model, "mip_rel_gap", 0.001)
        set_optimizer_attribute(model, "presolve", "on")
        set_optimizer_attribute(model, "mip_detect_symmetry", true)
        set_optimizer_attribute(model, "mip_heuristic_effort", 0.3)
        set_optimizer_attribute(model, "parallel", "on")
        set_optimizer_attribute(model, "threads", num_threads_highs)
        set_optimizer_attribute(model, "mip_feasibility_tolerance", 1e-6)

        S = 1:num_strips

        min_width = minimum(vec_w_i)
        max_width = maximum(vec_w_i)
        min_height = minimum(mat_h_ip)

        max_apts_per_strip = floor(Int, W / min_width)
        max_apts_per_strip_tight = min(max_apts_per_strip, ceil(Int, (W * H) / (min_width * min_height)))

        max_corner_apts = 2
        max_d_corner_apts = 1

        """
        Decision Variables:
        - H_s: Depth of each strip s (continuous, non-negative)
        - num_deptos_regular_primer_piso: Number of regular apartments in first floor strip s, type i, height j (integer)
        - num_deptos_corner_primer_piso: Number of corner apartments in first floor strip s, type i, height j (integer)
        - num_deptos_d_corner_primer_piso: Number of double corner apartments in first floor strip s, type i, height j (integer)
        - area_comun_primer_piso: Common area for first floor (continuous, non-negative)
        - num_deptos_regular_por_piso_superior: Number of regular apartments in upper floor strip s, type i, height j (integer)
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

            0 <= num_deptos_regular_primer_piso[s in S, (k, j) in KJ_feasible] <= max_deptos, Int
            0 <= num_deptos_regular_nucleo_primer_piso[s in S, (k, j) in KJ_feasible] <= 2, Int
            0 <= num_deptos_corner_primer_piso[s in S, (k, j) in KJ_feasible] <= 2, Int
            0 <= num_deptos_corner_nucleo_primer_piso[s in S, (k, j) in KJ_feasible] <= 2, Int
            0 <= num_deptos_d_corner_nucleo_primer_piso[s in S, (k, j) in KJ_feasible] <= 1, Int
            area_comun_primer_piso >= 0

            0 <= num_deptos_regular_por_piso_superior[s in S, (k, j) in KJ_feasible] <= max_deptos, Int
            0 <= num_deptos_regular_nucleo_por_piso_superior[s in S, (k, j) in KJ_feasible] <= 2, Int
            0 <= num_deptos_corner_por_piso_superior[s in S, (k, j) in KJ_feasible] <= 2, Int
            0 <= num_deptos_corner_nucleo_por_piso_superior[s in S, (k, j) in KJ_feasible] <= 2, Int
            0 <= num_deptos_d_corner_nucleo_por_piso_superior[s in S, (k, j) in KJ_feasible] <= 1, Int
            area_comun_por_piso_superior >= 0

            x[s in S, (k, j) in KJ_feasible], Bin
            x_n[s in S, (k, j) in KJ_feasible], Bin
            x_c[s in S, (k, j) in KJ_feasible], Bin
            x_cn[s in S, (k, j) in KJ_feasible], Bin
            x_ccn[s in S, (k, j) in KJ_feasible], Bin

            y[s in S], Bin        # Binary indicator: strip s uses regular configuration
            y_c[s in S], Bin      # Binary indicator: strip s uses corner configuration
            y_cn[s in S], Bin     # Binary indicator: strip s uses corner nucleo configuration
            y_cn2[s in S], Bin    # Binary indicator: strip s has exactly 2 corner nucleo apartments
            y_ccn[s in S], Bin    # Binary indicator: strip s uses double corner nucleo configuration
            y_n[s in S], Bin      # Binary indicator: strip s uses regular nucleo configuration
            y_active[s in S], Bin # Binary indicator: strip s has any apartments (active)

            descuento_dfl2 >= 0  # DFL2 discount for social housing (up to 20% of useful area or total common area)
            area_no_utilizada_primer_piso >= 0          # Unused footprint area on first floor (m²)
            area_no_utilizada_por_piso_superior >= 0    # Unused footprint area per upper floor (m²)

            max_height[s in S] >= 0  # Maximum apartment height in strip s (for perimeter constraint)
        end)

        
        @expressions(model, begin
            # Total number of apartments on first floor
            num_deptos_primer_piso, sum(num_deptos_regular_primer_piso[s,(k,j)] +
                num_deptos_regular_nucleo_primer_piso[s,(k,j)] +
                num_deptos_corner_primer_piso[s,(k,j)] +
                num_deptos_corner_nucleo_primer_piso[s,(k,j)] +
                num_deptos_d_corner_nucleo_primer_piso[s,(k,j)] for s in S, (k, j) in KJ_feasible)

            # Total number of apartments per upper floor
            num_deptos_por_piso_superior, sum(num_deptos_regular_por_piso_superior[s,(k,j)] +
                num_deptos_regular_nucleo_por_piso_superior[s,(k,j)] +
                num_deptos_corner_por_piso_superior[s,(k,j)] +
                num_deptos_corner_nucleo_por_piso_superior[s,(k,j)] +
                num_deptos_d_corner_nucleo_por_piso_superior[s,(k,j)] for s in S, (k, j) in KJ_feasible)

            # Total common area across all floors
            area_comun_total, area_comun_primer_piso + area_comun_por_piso_superior * num_pisos_superiores

            # Total unused footprint area across all floors
            area_no_utilizada, area_no_utilizada_primer_piso + area_no_utilizada_por_piso_superior * num_pisos_superiores

            # Total interior area for first floor apartments
            area_interior_primer_piso, sum((num_deptos_regular_primer_piso[s,(k,j)] +
                num_deptos_regular_nucleo_primer_piso[s,(k,j)] +
                num_deptos_corner_primer_piso[s,(k,j)] +
                num_deptos_corner_nucleo_primer_piso[s,(k,j)] +
                num_deptos_d_corner_nucleo_primer_piso[s,(k,j)]
                ) * vec_area_i[k] for s in S, (k, j) in KJ_feasible)

            # Interior area per upper floor
            area_interior_por_piso_superior, sum((num_deptos_regular_por_piso_superior[s,(k,j)] +
                num_deptos_regular_nucleo_por_piso_superior[s,(k,j)] +
                num_deptos_corner_por_piso_superior[s,(k,j)] +
                num_deptos_corner_nucleo_por_piso_superior[s,(k,j)] +
                num_deptos_d_corner_nucleo_por_piso_superior[s,(k,j)]
                ) * vec_area_i[k] for s in S, (k, j) in KJ_feasible)

            # Total interior area for entire building
            area_interior_total, area_interior_primer_piso + area_interior_por_piso_superior * num_pisos_superiores

            # Total terrace area for first floor apartments
            area_terraza_primer_piso, sum((num_deptos_regular_primer_piso[s,(k,j)] +
                num_deptos_regular_nucleo_primer_piso[s,(k,j)] +
                num_deptos_corner_primer_piso[s,(k,j)] +
                num_deptos_corner_nucleo_primer_piso[s,(k,j)] +
                num_deptos_d_corner_nucleo_primer_piso[s,(k,j)]
                ) * vec_area_t[k] for s in S, (k, j) in KJ_feasible)

            # Terrace area per upper floor
            area_terraza_por_piso_superior, sum((num_deptos_regular_por_piso_superior[s,(k,j)] +
                num_deptos_regular_nucleo_por_piso_superior[s,(k,j)] +
                num_deptos_corner_por_piso_superior[s,(k,j)] +
                num_deptos_corner_nucleo_por_piso_superior[s,(k,j)] +
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
            area_pasillo_primer_piso, sum((num_deptos_regular_primer_piso[s,(k,j)] + num_deptos_regular_nucleo_primer_piso[s,(k,j)]) * vec_area_p[j] for s in S, (k, j) in KJ_feasible)

            # Hallway area per upper floor
            area_pasillo_por_piso_superior, sum((num_deptos_regular_por_piso_superior[s,(k,j)] + num_deptos_regular_nucleo_por_piso_superior[s,(k,j)]) * vec_area_p[j] for s in S, (k, j) in KJ_feasible)

            # Total hallway area for entire building
            area_pasillo_total, area_pasillo_primer_piso + area_pasillo_por_piso_superior * num_pisos_superiores

            # Nucleo area for first floor (additional area per nucleo apartment)
            area_nucleo_primer_piso, sum((num_deptos_regular_nucleo_primer_piso[s,(k,j)] +
                                        num_deptos_corner_nucleo_primer_piso[s,(k,j)]) * area_nucleo_depto +
                                        num_deptos_d_corner_nucleo_primer_piso[s,(k,j)] * area_nucleo_depto_d_corner for s in S, (k, j) in KJ_feasible)

            # Nucleo area per upper floor
            area_nucleo_por_piso_superior, sum((num_deptos_regular_nucleo_por_piso_superior[s,(k,j)] +
                                                num_deptos_corner_nucleo_por_piso_superior[s,(k,j)]) * area_nucleo_depto +
                                                num_deptos_d_corner_nucleo_por_piso_superior[s,(k,j)] * area_nucleo_depto_d_corner for s in S, (k, j) in KJ_feasible)

            # Total nucleo area for entire building
            area_nucleo_total, area_nucleo_primer_piso + area_nucleo_por_piso_superior * num_pisos_superiores

            # Total SNT area (interior + terrace + common areas)
            area_snt, area_interior_total + area_terraza_total + area_comun_total

            # Total count of all apartment types across all strips and floors
            deptos_total, (sum(num_deptos_regular_primer_piso[s,(k,j)] for s in S, (k, j) in KJ_feasible) +
                sum(num_deptos_regular_nucleo_primer_piso[s,(k,j)] for s in S, (k, j) in KJ_feasible) +
                sum(num_deptos_corner_primer_piso[s,(k,j)] for s in S, (k, j) in KJ_feasible) +
                sum(num_deptos_corner_nucleo_primer_piso[s,(k,j)] for s in S, (k, j) in KJ_feasible) +
                sum(num_deptos_d_corner_nucleo_primer_piso[s,(k,j)] for s in S, (k, j) in KJ_feasible)) +
                (sum(num_deptos_regular_por_piso_superior[s,(k,j)] for s in S, (k, j) in KJ_feasible) +
                sum(num_deptos_regular_nucleo_por_piso_superior[s,(k,j)] for s in S, (k, j) in KJ_feasible) +
                sum(num_deptos_corner_por_piso_superior[s,(k,j)] for s in S, (k, j) in KJ_feasible) +
                sum(num_deptos_corner_nucleo_por_piso_superior[s,(k,j)] for s in S, (k, j) in KJ_feasible) +
                sum(num_deptos_d_corner_nucleo_por_piso_superior[s,(k,j)] for s in S, (k, j) in KJ_feasible)
                ) * num_pisos_superiores

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

            # Buildability constraint: useful area + common area - DFL2 discount must not exceed maximum buildability
            constraint_6, area_util_total + area_comun_total - descuento_dfl2 <= max_constructibilidad

            # DFL2 discount cannot exceed 20% of useful area nor total common area
            constraint_7, descuento_dfl2 <= flag_dfl2 * 0.2 * area_util_total
            constraint_8, descuento_dfl2 <= flag_dfl2 * area_comun_total

            # Link regular apartments to y indicator (if any regular apartments exist, y = 1)
            constraint_9[s in S], sum(num_deptos_regular_por_piso_superior[s,(k,j)] for (k, j) in KJ_feasible) <= max_apts_per_strip_tight * y[s]
            constraint_10[s in S], sum(num_deptos_regular_por_piso_superior[s,(k,j)] for (k, j) in KJ_feasible) >= y[s]

            # Exactly 2 corner or 2 corner nucleo apartments per strip if corner type is used
            constraint_11a[s in S], sum(num_deptos_corner_por_piso_superior[s,(k,j)] for (k, j) in KJ_feasible) == max_corner_apts * y_c[s]
            constraint_11b[s in S], sum(num_deptos_corner_nucleo_por_piso_superior[s,(k,j)] for (k, j) in KJ_feasible) <= max_corner_apts * y_cn[s]
            constraint_11c[s in S], sum(num_deptos_corner_nucleo_por_piso_superior[s,(k,j)] for (k, j) in KJ_feasible) >= y_cn[s]
            constraint_11d[s in S], sum(num_deptos_corner_nucleo_por_piso_superior[s,(k,j)] for (k, j) in KJ_feasible) == max_corner_apts * y_cn2[s]
            constraint_11e[s in S], y_cn2[s] <= y_cn[s]

            # Link regular nucleo apartments to y_n indicator (if any nucleo apartments exist, y_n = 1)
            constraint_12a[s in S], sum(num_deptos_regular_nucleo_por_piso_superior[s,(k,j)] for (k, j) in KJ_feasible) <= max_apts_per_strip_tight * y_n[s]
            constraint_12b[s in S], sum(num_deptos_regular_nucleo_por_piso_superior[s,(k,j)] for (k, j) in KJ_feasible) >= y_n[s]

            # Exactly 1 double corner nucleo apartment per strip if double corner nucleo type is used
            constraint_13[s in S], sum(num_deptos_d_corner_nucleo_por_piso_superior[s,(k,j)] for (k, j) in KJ_feasible) == max_d_corner_apts * y_ccn[s]

            # Link y_active to configuration indicators (strip is active if any configuration is used)
            constraint_14a[s in S], y_active[s] >= y[s]
            constraint_14b[s in S], y_active[s] >= y_c[s]
            constraint_14c[s in S], y_active[s] >= y_cn[s]
            constraint_14d[s in S], y_active[s] >= y_ccn[s]
            constraint_14e[s in S], y_active[s] >= y_n[s]
            constraint_14f[s in S], y_active[s] <= y[s] + y_c[s] + y_cn[s] + y_ccn[s] + y_n[s]

            # Each strip can have at most one configuration type from incompatible groups
            constraint_15a[s in S], y_n[s] + y_ccn[s] <= 1  # Regular núcleo incompatible with double corner nucleo
            constraint_15b[s in S], y_c[s] + y_ccn[s] <= 1  # At most one corner/double-corner type
            constraint_15c[s in S], y_cn2[s] + y_ccn[s] <= 1 # At most one corner/double-corner type
            constraint_15d[s in S], y[s] + y_ccn[s] <= 1    # Regular incompatible with double corner nucleo
            constraint_15e[s in S], y[s] + y_cn2[s] <= 1    # Regular incompatible with 2 corner nucleo
            constraint_15f[s in S], y_n[s] + y_cn2[s] <= 1  # Regular nucleo incompatible with 2 corner nucleo
            constraint_15g[s in S], y_c[s] + y_cn2[s] <= 1  # Corner incompatible with 2 corner nucleo

            # Total apartment count must be within specified bounds
            constraint_16a, deptos_total >= min_deptos
            constraint_16b, deptos_total <= max_deptos

            # Sum of all strip depths cannot exceed building depth
            constraint_17, sum(H_s[s] for s in S) <= H

            # Each strip must have minimum depth
            constraint_18[s in S], H_s[s] >= (H - 3) / 2

            # Apartment height (interior + terrace) must fit within strip depth for each apartment type
            constraint_19[s in S, (k, j) in KJ_feasible], x[s,(k,j)] * (mat_h_ip[k,j] + mat_h_t[k,j]) <= H_s[s]        # Regular apartments
            constraint_20[s in S, (k, j) in KJ_feasible], x_n[s,(k,j)] * (mat_h_ipn[k,j] + mat_h_t[k,j]) <= H_s[s]      # Nucleo apartments
            constraint_21[s in S, (k, j) in KJ_feasible], x_c[s,(k,j)] * (mat_h_in[k,j] + mat_h_t[k,j]) <= H_s[s]   # Corner apartments
            constraint_22[s in S, (k, j) in KJ_feasible], x_cn[s,(k,j)] * (mat_h_in[k,j] + mat_h_t[k,j]) <= H_s[s]   # Corner nucleo apartments
            constraint_24[s in S, (k, j) in KJ_feasible], x_ccn[s,(k,j)] * (mat_h_in_d_corner[k,j] + mat_h_t[k,j]) <= H_s[s] # Double corner nucleo apartments
            # Total apartment area per strip cannot exceed strip footprint (W x H_s)
            constraint_25[s in S], sum(num_deptos_regular_por_piso_superior[s,(k,j)] * (mat_area_ip[k,j] + vec_area_t[k]) +
                num_deptos_regular_nucleo_por_piso_superior[s,(k,j)] * (mat_area_ipn[k,j] + vec_area_t[k]) +
                num_deptos_corner_por_piso_superior[s,(k,j)] * (vec_area_i[k] + vec_area_t[k]) +
                num_deptos_corner_nucleo_por_piso_superior[s,(k,j)] * (vec_area_in[k] + vec_area_t[k]) +
                num_deptos_d_corner_nucleo_por_piso_superior[s,(k,j)] * (vec_area_in_d_corner[k] + vec_area_t[k])
                for (k, j) in KJ_feasible) <= W * H_s[s]

            # Apartment count is positive only if apartment type is selected (Big-M constraint linking binary and integer variables)
            constraint_26[s in S, (k, j) in KJ_feasible], num_deptos_regular_por_piso_superior[s,(k,j)] <= max_apts_per_strip_tight * x[s,(k,j)]           # Regular apartments
            constraint_27[s in S, (k, j) in KJ_feasible], num_deptos_regular_nucleo_por_piso_superior[s,(k,j)] <= max_apts_per_strip_tight * x_n[s,(k,j)]  # Nucleo apartments
            constraint_28[s in S, (k, j) in KJ_feasible], num_deptos_corner_por_piso_superior[s,(k,j)] <= max_corner_apts * x_c[s,(k,j)]  # Corner apartments (max 2)
            constraint_29[s in S, (k, j) in KJ_feasible], num_deptos_corner_nucleo_por_piso_superior[s,(k,j)] <= max_corner_apts * x_cn[s,(k,j)]  # Corner nucleo apartments (max 2)
            constraint_31[s in S, (k, j) in KJ_feasible], num_deptos_d_corner_nucleo_por_piso_superior[s,(k,j)] <= max_d_corner_apts * x_ccn[s,(k,j)] # Double corner nucleo apartments (max 1)



            # Total apartment widths per strip cannot exceed building width W
            constraint_38[s in S], sum((num_deptos_regular_por_piso_superior[s,(k,j)] +
                num_deptos_regular_nucleo_por_piso_superior[s,(k,j)] +
                num_deptos_corner_por_piso_superior[s,(k,j)] +
                num_deptos_corner_nucleo_por_piso_superior[s,(k,j)] +
                num_deptos_d_corner_nucleo_por_piso_superior[s,(k,j)]
                ) * vec_w_i[j] for (k, j) in KJ_feasible) <= W

            # Maximum height tracking: use a single aggregated constraint per (s,k,j)
            constraint_39_height[s in S, (k, j) in KJ_feasible],
                max_height[s] >= mat_h_ip[k,j] * x[s,(k,j)] + 
                                mat_h_ipn[k,j] * x_n[s,(k,j)] +
                                mat_h_in[k,j] * (x_c[s,(k,j)] + x_cn[s,(k,j)]) +
                                mat_h_in_d_corner[k,j] * x_ccn[s,(k,j)]

            # Sum of apartment perimeters must cover strip perimeter (2*max_height + W - tolerance)
            # constraint_39[s in S],
            #     sum(num_deptos_regular_por_piso_superior[s,(k,j)] * mat_exposicion[k,j] for (k, j) in KJ_feasible) +
            #     sum(num_deptos_regular_nucleo_por_piso_superior[s,(k,j)] * mat_exposicion[k,j] for (k, j) in KJ_feasible) +
            #     sum(num_deptos_corner_por_piso_superior[s,(k,j)] * mat_exposicion_corner[k,j] for (k, j) in KJ_feasible) +
            #     sum(num_deptos_corner_nucleo_por_piso_superior[s,(k,j)] * mat_exposicion_corner[k,j] for (k, j) in KJ_feasible) +
            #     sum(num_deptos_d_corner_nucleo_por_piso_superior[s,(k,j)] * mat_exposicion_d_corner[k,j] for (k, j) in KJ_feasible) >= 0 # 2*max_height[s] + W - 5

            # First floor apartment counts cannot exceed upper floor counts (first floor is subset of upper floors)
            constraint_40[s in S, (k, j) in KJ_feasible], num_deptos_regular_primer_piso[s,(k,j)] <= num_deptos_regular_por_piso_superior[s,(k,j)]             # Regular apartments
            constraint_41[s in S, (k, j) in KJ_feasible], num_deptos_regular_nucleo_primer_piso[s,(k,j)] <= num_deptos_regular_nucleo_por_piso_superior[s,(k,j)]  # Nucleo apartments
            constraint_42[s in S, (k, j) in KJ_feasible], num_deptos_corner_primer_piso[s,(k,j)] <= num_deptos_corner_por_piso_superior[s,(k,j)]  # Corner apartments
            constraint_43[s in S, (k, j) in KJ_feasible], num_deptos_corner_nucleo_primer_piso[s,(k,j)] <= num_deptos_corner_nucleo_por_piso_superior[s,(k,j)]  # Corner nucleo apartments
            constraint_45[s in S, (k, j) in KJ_feasible], num_deptos_d_corner_nucleo_primer_piso[s,(k,j)] <= num_deptos_d_corner_nucleo_por_piso_superior[s,(k,j)] # Double corner nucleo apartments

            # First floor must have at least one fewer apartment than upper floors
            constraint_48, num_deptos_primer_piso <= num_deptos_por_piso_superior - 1
        end)

        @constraints(model, begin
            constraint_47[s in S], sum(num_deptos_regular_nucleo_por_piso_superior[s,(k,j)] for (k, j) in KJ_feasible) +
                                   sum(num_deptos_corner_nucleo_por_piso_superior[s,(k,j)] for (k, j) in KJ_feasible) +
                                   sum(num_deptos_d_corner_nucleo_por_piso_superior[s,(k,j)] for (k, j) in KJ_feasible) ==
                                   2 * y_active[s] - y_ccn[s]
        end)

        # Symmetry breaking: order strips by total apartments to reduce search space
        @constraint(model, sum(num_deptos_regular_por_piso_superior[1,(k,j)] + num_deptos_regular_nucleo_por_piso_superior[1,(k,j)] +
                               num_deptos_corner_por_piso_superior[1,(k,j)] + num_deptos_corner_nucleo_por_piso_superior[1,(k,j)] +
                               num_deptos_d_corner_nucleo_por_piso_superior[1,(k,j)] for (k, j) in KJ_feasible) >=
                        sum(num_deptos_regular_por_piso_superior[2,(k,j)] + num_deptos_regular_nucleo_por_piso_superior[2,(k,j)] +
                            num_deptos_corner_por_piso_superior[2,(k,j)] + num_deptos_corner_nucleo_por_piso_superior[2,(k,j)] +
                            num_deptos_d_corner_nucleo_por_piso_superior[2,(k,j)] for (k, j) in KJ_feasible))

        conflicting_pairs = Tuple{Int,Int}[]
        for k1 in K, k2 in K
            if k1 < k2 && vec_area_i[k2] > vec_area_i[k1] * 2.0
                push!(conflicting_pairs, (k1, k2))
            end
        end
        KJ_by_k = [[(k, j) for (k, j) in KJ_feasible if k == k_target] for k_target in K]
        for (k1, k2) in conflicting_pairs
            @constraints(model, begin
                sum(x[s,kj] for s in S, kj in KJ_by_k[k1]) + sum(x[s,kj] for s in S, kj in KJ_by_k[k2]) <= 1
                sum(x_n[s,kj] for s in S, kj in KJ_by_k[k1]) + sum(x_n[s,kj] for s in S, kj in KJ_by_k[k2]) <= 1
                sum(x_c[s,kj] for s in S, kj in KJ_by_k[k1]) + sum(x_c[s,kj] for s in S, kj in KJ_by_k[k2]) <= 1
                sum(x_cn[s,kj] for s in S, kj in KJ_by_k[k1]) + sum(x_cn[s,kj] for s in S, kj in KJ_by_k[k2]) <= 1
                sum(x_ccn[s,kj] for s in S, kj in KJ_by_k[k1]) + sum(x_ccn[s,kj] for s in S, kj in KJ_by_k[k2]) <= 1
            end)
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

        results = OrderedDict{String,Any}()
        results["status"] = termination_status(model)
        results["solve_time"] = solve_time(model)
        results["deptos"] = OrderedDict{Int,Any}()
        results["strip"] = OrderedDict{Int,Any}()

        if has_values(model)
            results["objective_value"] = objective_value(model)

            for s in S
                perimetro_s_pp = sum(value(num_deptos_regular_primer_piso[s,(k,j)]) * mat_exposicion[k,j] for (k, j) in KJ_feasible) +
                            sum(value(num_deptos_regular_nucleo_primer_piso[s,(k,j)]) * mat_exposicion[k,j] for (k, j) in KJ_feasible) +
                            sum(value(num_deptos_corner_primer_piso[s,(k,j)]) * mat_exposicion_corner[k,j] for (k, j) in KJ_feasible) +
                            sum(value(num_deptos_corner_nucleo_primer_piso[s,(k,j)]) * mat_exposicion_corner[k,j] for (k, j) in KJ_feasible) +
                            sum(value(num_deptos_d_corner_nucleo_primer_piso[s,(k,j)]) * mat_exposicion_d_corner[k,j] for (k, j) in KJ_feasible)

                apartment_area_s_pp = sum(value(num_deptos_regular_primer_piso[s,(k,j)]) * vec_area_i[k] for (k, j) in KJ_feasible) +
                                sum(value(num_deptos_regular_nucleo_primer_piso[s,(k,j)]) * vec_area_i[k] for (k, j) in KJ_feasible) +
                                sum(value(num_deptos_corner_primer_piso[s,(k,j)]) * vec_area_i[k] for (k, j) in KJ_feasible) +
                                sum(value(num_deptos_corner_nucleo_primer_piso[s,(k,j)]) * vec_area_i[k] for (k, j) in KJ_feasible) +
                                sum(value(num_deptos_d_corner_nucleo_primer_piso[s,(k,j)]) * vec_area_i[k] for (k, j) in KJ_feasible)

                terrace_area_s_pp = sum(value(num_deptos_regular_primer_piso[s,(k,j)]) * vec_area_t[k] for (k, j) in KJ_feasible) +
                                sum(value(num_deptos_regular_nucleo_primer_piso[s,(k,j)]) * vec_area_t[k] for (k, j) in KJ_feasible) +
                                sum(value(num_deptos_corner_primer_piso[s,(k,j)]) * vec_area_t[k] for (k, j) in KJ_feasible) +
                                sum(value(num_deptos_corner_nucleo_primer_piso[s,(k,j)]) * vec_area_t[k] for (k, j) in KJ_feasible) +
                                sum(value(num_deptos_d_corner_nucleo_primer_piso[s,(k,j)]) * vec_area_t[k] for (k, j) in KJ_feasible)

                pasillo_area_s_pp = sum(value(num_deptos_regular_primer_piso[s,(k,j)]) * vec_area_p[j] for (k, j) in KJ_feasible) +
                                sum(value(num_deptos_regular_nucleo_primer_piso[s,(k,j)]) * vec_area_p[j] for (k, j) in KJ_feasible)

                perimetro_s_ps = sum(value(num_deptos_regular_por_piso_superior[s,(k,j)]) * mat_exposicion[k,j] for (k, j) in KJ_feasible) +
                            sum(value(num_deptos_regular_nucleo_por_piso_superior[s,(k,j)]) * mat_exposicion[k,j] for (k, j) in KJ_feasible) +
                            sum(value(num_deptos_corner_por_piso_superior[s,(k,j)]) * mat_exposicion_corner[k,j] for (k, j) in KJ_feasible) +
                            sum(value(num_deptos_corner_nucleo_por_piso_superior[s,(k,j)]) * mat_exposicion_corner[k,j] for (k, j) in KJ_feasible) +
                            sum(value(num_deptos_d_corner_nucleo_por_piso_superior[s,(k,j)]) * mat_exposicion_d_corner[k,j] for (k, j) in KJ_feasible)

                apartment_area_s_ps = sum(value(num_deptos_regular_por_piso_superior[s,(k,j)]) * vec_area_i[k] for (k, j) in KJ_feasible) +
                                sum(value(num_deptos_regular_nucleo_por_piso_superior[s,(k,j)]) * vec_area_i[k] for (k, j) in KJ_feasible) +
                                sum(value(num_deptos_corner_por_piso_superior[s,(k,j)]) * vec_area_i[k] for (k, j) in KJ_feasible) +
                                sum(value(num_deptos_corner_nucleo_por_piso_superior[s,(k,j)]) * vec_area_i[k] for (k, j) in KJ_feasible) +
                                sum(value(num_deptos_d_corner_nucleo_por_piso_superior[s,(k,j)]) * vec_area_i[k] for (k, j) in KJ_feasible)

                terrace_area_s_ps = sum(value(num_deptos_regular_por_piso_superior[s,(k,j)]) * vec_area_t[k] for (k, j) in KJ_feasible) +
                                sum(value(num_deptos_regular_nucleo_por_piso_superior[s,(k,j)]) * vec_area_t[k] for (k, j) in KJ_feasible) +
                                sum(value(num_deptos_corner_por_piso_superior[s,(k,j)]) * vec_area_t[k] for (k, j) in KJ_feasible) +
                                sum(value(num_deptos_corner_nucleo_por_piso_superior[s,(k,j)]) * vec_area_t[k] for (k, j) in KJ_feasible) +
                                sum(value(num_deptos_d_corner_nucleo_por_piso_superior[s,(k,j)]) * vec_area_t[k] for (k, j) in KJ_feasible)

                pasillo_area_s_ps = sum(value(num_deptos_regular_por_piso_superior[s,(k,j)]) * vec_area_p[j] for (k, j) in KJ_feasible) +
                                sum(value(num_deptos_regular_nucleo_por_piso_superior[s,(k,j)]) * vec_area_p[j] for (k, j) in KJ_feasible)

                results["strip"][s] = OrderedDict{String,Any}()
                results["strip"][s]["strip"] = s
                results["strip"][s]["H_s"] = value(H_s[s])
                results["strip"][s]["perimetro_expuesto"] = OrderedDict{String,Float64}()
                results["strip"][s]["perimetro_expuesto"]["primer_piso"] = perimetro_s_pp
                results["strip"][s]["perimetro_expuesto"]["pisos_superiores"] = perimetro_s_ps
                results["strip"][s]["superficie_deptos"] = OrderedDict{String,Float64}()
                results["strip"][s]["superficie_deptos"]["primer_piso"] = apartment_area_s_pp
                results["strip"][s]["superficie_deptos"]["pisos_superiores"] = apartment_area_s_ps
                results["strip"][s]["superficie_terraza"] = OrderedDict{String,Float64}()
                results["strip"][s]["superficie_terraza"]["primer_piso"] = terrace_area_s_pp
                results["strip"][s]["superficie_terraza"]["pisos_superiores"] = terrace_area_s_ps
                results["strip"][s]["superficie_pasillo"] = OrderedDict{String,Float64}()
                results["strip"][s]["superficie_pasillo"]["primer_piso"] = pasillo_area_s_pp
                results["strip"][s]["superficie_pasillo"]["pisos_superiores"] = pasillo_area_s_ps

                depto_index = 1
                for (k, j) in KJ_feasible
                    for (var_pp, var_ps, tipo, threshold) in [
                        (num_deptos_regular_primer_piso[s,(k,j)], num_deptos_regular_por_piso_superior[s,(k,j)], "regular", 0.001),
                        (num_deptos_regular_nucleo_primer_piso[s,(k,j)], num_deptos_regular_nucleo_por_piso_superior[s,(k,j)], "regular_nucleo", 0.001),
                        (num_deptos_corner_primer_piso[s,(k,j)], num_deptos_corner_por_piso_superior[s,(k,j)], "corner", 0.001),
                        (num_deptos_corner_nucleo_primer_piso[s,(k,j)], num_deptos_corner_nucleo_por_piso_superior[s,(k,j)], "corner_nucleo", 0.001),
                        (num_deptos_d_corner_nucleo_primer_piso[s,(k,j)], num_deptos_d_corner_nucleo_por_piso_superior[s,(k,j)], "d_corner_nucleo", 0.001)]

                        val_pp = value(var_pp)
                        val_ps = value(var_ps)

                        if val_pp > threshold || val_ps > threshold
                            depto_index = length(results["deptos"]) + 1
                            results["deptos"][depto_index] = OrderedDict{String,Any}()

                            results["deptos"][depto_index]["strip"] = s
                            results["deptos"][depto_index]["k"] = k
                            results["deptos"][depto_index]["j"] = j
                            results["deptos"][depto_index]["tipo"] = tipo
                            results["deptos"][depto_index]["ancho"] = vec_w_i[j]
                            results["deptos"][depto_index]["profundidad"] = 0.0

                            ancho_terraza_calc = mat_h_t[k,j]
                            profundidad_terraza_calc = vec_area_t[k] / ancho_terraza_calc
                            results["deptos"][depto_index]["ancho_terraza"] = ancho_terraza_calc
                            results["deptos"][depto_index]["profundidad_terraza"] = profundidad_terraza_calc
                            results["deptos"][depto_index]["num_unidades_primer_piso"] = val_pp
                            results["deptos"][depto_index]["num_unidades_por_piso_superior"] = val_ps
                            results["deptos"][depto_index]["num_unidades_edificio"] = val_pp + val_ps * num_pisos_superiores
                            results["deptos"][depto_index]["sup_interior"] = vec_area_i[k]
                            results["deptos"][depto_index]["sup_terraza"] = vec_area_t[k]
                            results["deptos"][depto_index]["sup_pasillo"] = 0.0
                            results["deptos"][depto_index]["sup_nucleo"] = 0.0

                            if tipo == "regular"
                                results["deptos"][depto_index]["profundidad"] = mat_h_ip[k,j]
                                results["deptos"][depto_index]["sup_pasillo"] = vec_area_p[j]
                                results["deptos"][depto_index]["ancho_interior"] = vec_w_i[j]
                                results["deptos"][depto_index]["profundidad_interior"] = vec_area_i[k] / vec_w_i[j]
                            elseif tipo == "regular_nucleo"
                                results["deptos"][depto_index]["profundidad"] = mat_h_ipn[k,j]
                                results["deptos"][depto_index]["sup_pasillo"] = vec_area_p[j]
                                results["deptos"][depto_index]["sup_nucleo"] = area_nucleo_depto
                                results["deptos"][depto_index]["ancho_interior"] = vec_w_i[j]
                                results["deptos"][depto_index]["profundidad_interior"] = vec_area_i[k] / vec_w_i[j]
                            elseif tipo == "corner"
                                results["deptos"][depto_index]["profundidad"] = mat_h_in[k,j]
                                results["deptos"][depto_index]["ancho_interior"] = vec_w_i[j]
                                results["deptos"][depto_index]["profundidad_interior"] = vec_area_i[k] / vec_w_i[j]
                            elseif tipo == "corner_nucleo"
                                results["deptos"][depto_index]["profundidad"] = mat_h_in[k,j]
                                results["deptos"][depto_index]["sup_nucleo"] = area_nucleo_depto
                                results["deptos"][depto_index]["ancho_interior"] = vec_w_i[j]
                                results["deptos"][depto_index]["profundidad_interior"] = vec_area_i[k] / vec_w_i[j]
                            else
                                results["deptos"][depto_index]["profundidad"] = mat_h_in_d_corner[k,j]
                                results["deptos"][depto_index]["sup_nucleo"] = area_nucleo_depto_d_corner
                                results["deptos"][depto_index]["ancho_interior"] = vec_w_i[j]
                                results["deptos"][depto_index]["profundidad_interior"] = vec_area_i[k] / vec_w_i[j]
                            end
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

            sup_int_pp = sum(results["strip"][s]["superficie_deptos"]["primer_piso"] for s in S)
            sup_terr_pp = sum(results["strip"][s]["superficie_terraza"]["primer_piso"] for s in S)
            sup_pas_pp = sum(results["strip"][s]["superficie_pasillo"]["primer_piso"] for s in S)

            sup_int_ps = sum(results["strip"][s]["superficie_deptos"]["pisos_superiores"] for s in S)
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

            results["totals"]["superficie_comun"] = OrderedDict{String,Float64}()
            results["totals"]["superficie_comun"]["primer_piso"] = value(area_comun_primer_piso)
            results["totals"]["superficie_comun"]["pisos_superiores"] = value(area_comun_por_piso_superior)
            results["totals"]["superficie_comun"]["edificio"] = value(area_comun_primer_piso) + value(area_comun_por_piso_superior) * num_pisos_superiores

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

            results["totals"]["superficie_otros_espacios"] = OrderedDict{String,Float64}()
            results["totals"]["superficie_otros_espacios"]["primer_piso"] = value(area_comun_primer_piso) - sup_pas_pp - area_nucleo_pp
            results["totals"]["superficie_otros_espacios"]["pisos_superiores"] = value(area_comun_por_piso_superior) - sup_pas_ps - area_nucleo_ps
            results["totals"]["superficie_otros_espacios"]["edificio"] = (value(area_comun_primer_piso) - sup_pas_pp - area_nucleo_pp) + (value(area_comun_por_piso_superior) - sup_pas_ps - area_nucleo_ps) * num_pisos_superiores

            area_emplazamiento_por_piso = W * H
            area_no_utilizada_pp_calc = area_emplazamiento_por_piso - (sup_int_pp + sup_terr_pp + value(area_comun_primer_piso))
            area_no_utilizada_ps_calc = area_emplazamiento_por_piso - (sup_int_ps + sup_terr_ps + value(area_comun_por_piso_superior))

            results["totals"]["superficie_no_utilizada"] = OrderedDict{String,Float64}()
            results["totals"]["superficie_no_utilizada"]["primer_piso"] = area_no_utilizada_pp_calc
            results["totals"]["superficie_no_utilizada"]["pisos_superiores"] = area_no_utilizada_ps_calc
            results["totals"]["superficie_no_utilizada"]["edificio"] = area_no_utilizada_pp_calc + area_no_utilizada_ps_calc * num_pisos_superiores

            results["superficie_losa_primer_piso"] = sup_int_pp + sup_terr_pp + sup_pas_pp
            results["superficie_losa_pisos_superiores"] = (sup_int_ps + sup_terr_ps + sup_pas_ps) * num_pisos_superiores
            results["superficie_losa_total"] = results["superficie_losa_primer_piso"] + results["superficie_losa_pisos_superiores"]
            results["superficie_interior_edificio"] = results["totals"]["superficie_interior"]["edificio"]
            results["superficie_terraza_edificio"] = results["totals"]["superficie_terraza"]["edificio"]
            results["superficie_pasillo_edificio"] = results["totals"]["superficie_pasillo"]["edificio"]
            results["superficie_total_edificio"] = results["superficie_interior_edificio"] + results["superficie_terraza_edificio"] + results["superficie_pasillo_edificio"]

            results["num_pisos_superiores"] = num_pisos_superiores
            results["num_pisos_total"] = num_pisos
            results["flag_dfl2"] = flag_dfl2
            results["flag_vivienda_economica"] = flag_vivienda_economica
            results["angulo_rotacion"] = angulo_rotacion
            results["cr"] = cr
            results["ps_planta_normalizado"] = ps_planta_normalizado

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
        results["best_layout_area_util"] = area_util_2
        results["alternative_layout_area_util"] = area_util_1
    else
        results = results_1
        W = W_1
        H = H_1
        best_layout = 1
        println("\n✓ Best layout: Layout 1 (norte/sur) - $(round(area_util_1 - area_util_2, digits=2)) m² better")
        results["best_layout"] = 1
        results["best_layout_area_util"] = area_util_1
        results["alternative_layout_area_util"] = area_util_2
    end

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

    print_results(results, vec_area_i, vec_area_t, vec_area_p, mat_h_t, vec_w_i,
                  mat_h_ip, mat_h_ipn, mat_h_in, mat_h_in_d_corner,
                  area_nucleo_depto, area_nucleo_depto_d_corner, W, H)

    return results
end
