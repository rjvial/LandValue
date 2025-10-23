function opti_floor_plan_oe(ps_planta::PolyShape, vec_sup_deptos::Vector{Float64}, vec_num_deptos::Vector{Int};
                        ancho_pasillo::Float64 = 2.0, vec_sup_terraza::Vector{Float64} = Float64[],
                        area_escala::Float64 = 25.0, vec_min_alto_deptos::Vector{Float64} = Float64[],
                        min_alto_escala::Float64 = 0.0, balance_mode::Symbol = :heuristic)
    # Optimize floor plan layout by distributing apartments in two vertical strips (oeste/este)
    # Normalizes floor, balances apartments between strips, generates geometries with minimum height constraints
    # balance_mode: :heuristic (default, aesthetic ordering) or :area (strict size-based balance)
    # Returns: Dictionary with apartment polygons, vertical hallway, terraces, staircase, and metrics

    function genera_deptos_franja(vec_orden_deptos::Vector{Tuple{Float64, Int}}, y_min_planta::Float64, x_base::Float64, ancho_franja::Float64, direction::Symbol, vec_min_alto_deptos::Vector{Float64}, alto_disponible::Float64, min_alto_escala::Float64)
        # Generate apartment geometries for vertical strip with minimum height constraints
        # Iteratively adjusts strip width until apartments fill available height while respecting min heights
        # Returns: (vec_y_ini, vec_y_fin, vec_ancho_deptos, vec_alto_deptos, vec_tipo_deptos)
        vec_y_ini = Float64[]
        vec_y_fin = Float64[]
        vec_ancho_deptos = Float64[]
        vec_alto_deptos = Float64[]
        vec_tipo_deptos = Int[]

        ancho_franja_adjusted = ancho_franja
        max_iterations = 10

        for _ in 1:max_iterations
            empty!(vec_y_ini)
            empty!(vec_y_fin)
            empty!(vec_ancho_deptos)
            empty!(vec_alto_deptos)
            empty!(vec_tipo_deptos)

            y_current = y_min_planta
            total_height = 0.0

            for (sup_depto, tipo_depto) in vec_orden_deptos
                if tipo_depto == -1
                    alto_depto = sup_depto / ancho_franja_adjusted
                    if alto_depto < min_alto_escala
                        alto_depto = min_alto_escala
                        ancho_depto = sup_depto / alto_depto
                    else
                        ancho_depto = ancho_franja_adjusted
                    end
                else
                    alto_depto = sup_depto / ancho_franja_adjusted
                    if alto_depto < vec_min_alto_deptos[tipo_depto]
                        alto_depto = vec_min_alto_deptos[tipo_depto]
                        ancho_depto = sup_depto / alto_depto
                    else
                        ancho_depto = ancho_franja_adjusted
                    end
                end

                push!(vec_y_ini, y_current)
                push!(vec_y_fin, y_current + alto_depto)
                push!(vec_ancho_deptos, ancho_depto)
                push!(vec_alto_deptos, alto_depto)
                push!(vec_tipo_deptos, tipo_depto)
                y_current += alto_depto
                total_height += alto_depto
            end

            if abs(total_height - alto_disponible) / alto_disponible < 0.005
                break
            end

            ancho_franja_adjusted = ancho_franja_adjusted * (total_height / alto_disponible)
        end

        return vec_y_ini, vec_y_fin, vec_ancho_deptos, vec_alto_deptos, vec_tipo_deptos
    end

    function extiende_deptos_interseccion_pasillo(vec_y_ini::Vector{Float64}, vec_y_fin::Vector{Float64}, vec_ancho_deptos::Vector{Float64}, vec_alto_deptos::Vector{Float64}, x_base::Float64, y_ini_pasillo::Float64, y_fin_pasillo::Float64, ancho_pasillo::Float64, ps_pasillo::PolyShape, extend_direction::Symbol)
        # Extend apartments into vertical hallway area to maintain required area, then subtract hallway overlap
        # Calculates extension width based on hallway intersection, positions relative to x_base
        # Works in normalized (unrotated) coordinate system
        # Returns: (vec_ps_deptos, vec_extension_widths)
        vec_extension_ancho_deptos = Float64[]
        ps_deptos_extendidos = PolyShape[]

        for i in eachindex(vec_y_ini)
            y_overlap_start = max(vec_y_ini[i], y_ini_pasillo)
            y_overlap_end = min(vec_y_fin[i], y_fin_pasillo)

            if y_overlap_start < y_overlap_end
                overlap_height = y_overlap_end - y_overlap_start
                intersection_area = overlap_height * ancho_pasillo
                extension_width = intersection_area / vec_alto_deptos[i]
            else
                extension_width = 0.0
            end

            push!(vec_extension_ancho_deptos, extension_width)

            ancho_total_depto = vec_ancho_deptos[i] + extension_width
            alto_depto = vec_y_fin[i] - vec_y_ini[i]

            if extend_direction == :este
                x_ini_depto = x_base
            else
                x_ini_depto = x_base - ancho_total_depto
            end

            extended_local_poly = polyShape.polyBox(x_ini_depto, vec_y_ini[i], ancho_total_depto, alto_depto, 0.0)
            extended_poly_final = polyShape.polyDifference(extended_local_poly, ps_pasillo)
            push!(ps_deptos_extendidos, extended_poly_final)
        end

        return ps_deptos_extendidos, vec_extension_ancho_deptos
    end

    function genera_terrazas_franja(vec_orden_deptos::Vector{Tuple{Float64, Int}}, vec_sup_terraza::Vector{Float64}, vec_alto_deptos::Vector{Float64}, vec_y_ini::Vector{Float64}, x_terrace_base::Vector{Float64}, terrace_direction::Symbol, max_ancho_terraza::Float64)
        # Generate terrace geometries for apartments in vertical strips, constrained by max width and apartment height
        # Adjusts dimensions to maintain required area, centers terraces on apartments
        # Returns: Vector of terrace PolyShapes

        vec_terrazas = PolyShape[]

        for (i, (_, tipo_depto)) in enumerate(vec_orden_deptos)
            if tipo_depto == -1
                push!(vec_terrazas, PolyShape([zeros(0, 2)], 0))
            else
                area_terraza = vec_sup_terraza[tipo_depto]
                if area_terraza > 0.0
                    alto_depto = vec_alto_deptos[i]
                    ancho_terraza = 1.75

                    alto_terraza = area_terraza / ancho_terraza

                    if alto_terraza > alto_depto
                        alto_terraza = alto_depto
                        ancho_terraza = min(area_terraza / alto_terraza, max_ancho_terraza)
                        if ancho_terraza < area_terraza / alto_terraza
                            alto_terraza = area_terraza / ancho_terraza
                        end
                    end

                    y_depto_ini = vec_y_ini[i]
                    y_terraza_ini = y_depto_ini + (alto_depto - alto_terraza) / 2

                    if terrace_direction == :este
                        x_terraza_ini = x_terrace_base[i]
                    else
                        x_terraza_ini = x_terrace_base[i] - ancho_terraza
                    end

                    terrace_poly = polyShape.polyBox(x_terraza_ini, y_terraza_ini, ancho_terraza, alto_terraza, 0.0)
                    push!(vec_terrazas, terrace_poly)
                else
                    push!(vec_terrazas, PolyShape([zeros(0, 2)], 0))
                end
            end
        end

        return vec_terrazas
    end

    function rota_polyshapes(vec_polyshapes::Vector{PolyShape}, angulo_rotacion::Float64, cr::Vector{Float64})
        # Rotate PolyShape geometries to original coordinates
        # Returns: Vector of rotated PolyShapes

        vec_polyshapes_rotados = PolyShape[]

        for polyshape in vec_polyshapes
            if polyShape.polyArea(polyshape) > 0.0
                polyshape_rotado = polyShape.polyRotate(polyshape, -angulo_rotacion, cr)
                push!(vec_polyshapes_rotados, polyshape_rotado)
            else
                push!(vec_polyshapes_rotados, polyshape)
            end
        end

        return vec_polyshapes_rotados
    end

    function normaliza_planta_rectangular(ps_planta::PolyShape)
        # Normalize floor polygon to axis-aligned rectangle with width > height
        # Rotates floor so longest dimension is horizontal (W > H)
        # Returns: W, H, vec_x_planta, vec_y_planta, angulo_rotacion, cr, ps_planta_normalizado

        V_planta = ps_planta.Vertices[1]
        x_cr = sum(V_planta[1:end-1, 1]) / (size(V_planta, 1) - 1)
        y_cr = sum(V_planta[1:end-1, 2]) / (size(V_planta, 1) - 1)
        cr = [x_cr, y_cr]

        edge1 = V_planta[2, :] - V_planta[1, :]
        angulo_rotacion = -atan(edge1[2], edge1[1])

        ps_planta_normalizado = polyShape.polyRotate(ps_planta, angulo_rotacion, cr)
        V_planta_normalizado = ps_planta_normalizado.Vertices[1]

        vec_x_planta = V_planta_normalizado[:, 1]
        vec_y_planta = V_planta_normalizado[:, 2]
        W = maximum(vec_x_planta) - minimum(vec_x_planta)
        H = maximum(vec_y_planta) - minimum(vec_y_planta)

        if H > W
            angulo_rotacion += π/2
            ps_planta_normalizado = polyShape.polyRotate(ps_planta, angulo_rotacion, cr)
            V_planta_normalizado = ps_planta_normalizado.Vertices[1]
            vec_x_planta = V_planta_normalizado[:, 1]
            vec_y_planta = V_planta_normalizado[:, 2]
            W, H = H, W
        end

        return W, H, vec_x_planta, vec_y_planta, angulo_rotacion, cr, ps_planta_normalizado
    end

    function distribuye_deptos_entre_franjas(vec_sup_deptos::Vector{Float64}, vec_num_deptos::Vector{Int}, area_escala::Float64)
        # Distribute apartments individually between oeste and este strips by size
        # Each apartment assigned independently (largest to smallest) to balance areas
        # Staircase assigned to oeste strip
        # Returns: deptos_franja_oeste, deptos_franja_este, area_oeste, area_este

        deptos_individuales = Tuple{Float64, Int, Int}[]
        for tipo_depto in 1:length(vec_sup_deptos)
            sup_depto = vec_sup_deptos[tipo_depto]
            for j in 1:vec_num_deptos[tipo_depto]
                push!(deptos_individuales, (sup_depto, tipo_depto, j))
            end
        end

        sort!(deptos_individuales, by = x -> x[1], rev = true)

        deptos_franja_este = Tuple{Float64, Int, Int}[]
        deptos_franja_oeste = Tuple{Float64, Int, Int}[]
        area_este = 0.0
        area_oeste = 0.0

        for depto in deptos_individuales
            sup_depto = depto[1]
            if area_este <= area_oeste + area_escala
                push!(deptos_franja_este, depto)
                area_este += sup_depto
            else
                push!(deptos_franja_oeste, depto)
                area_oeste += sup_depto
            end
        end

        push!(deptos_franja_oeste, (area_escala, -1, 1))
        area_oeste += area_escala

        return deptos_franja_este, deptos_franja_oeste, area_este, area_oeste
    end

    function calcula_anchos_franjas(area_este::Float64, area_oeste::Float64, W::Float64, H::Float64, ancho_pasillo::Float64, ancho_terraza_max::Float64)
        # Calculate strip widths based on apartment areas and available floor space
        # Reserves space for terraces and vertical hallway, scales down if total exceeds available width
        # Returns: ancho_este, ancho_oeste

        ancho_disponible_franja = W - 2 * ancho_terraza_max - ancho_pasillo

        ancho_este_requerido = area_este / H
        ancho_oeste_requerido = area_oeste / H

        if ancho_este_requerido + ancho_oeste_requerido > ancho_disponible_franja
            scale_factor = ancho_disponible_franja / (ancho_este_requerido + ancho_oeste_requerido)
            ancho_este = ancho_este_requerido * scale_factor
            ancho_oeste = ancho_oeste_requerido * scale_factor
        else
            ancho_este = ancho_este_requerido
            ancho_oeste = ancho_oeste_requerido
        end

        return ancho_este, ancho_oeste
    end

    function ordena_deptos_en_franja(deptos_franja_este::Vector{Tuple{Float64, Int, Int}}, deptos_franja_oeste::Vector{Tuple{Float64, Int, Int}}, area_escala::Float64, deptos_total::Int; balance_mode::Symbol = :heuristic)
        # Arrange apartments vertically within each strip for visual balance
        # balance_mode options:
        #   :heuristic - Este: 2nd largest, middle units, largest (ends). Oeste: first half, staircase, second half
        #   :area - Alternating large-small pattern for better balance
        # Returns: deptos_ordenados_este, deptos_ordenados_oeste

        deptos_ordenados_este = Tuple{Float64, Int}[]
        deptos_ordenados_oeste = Tuple{Float64, Int}[]

        num_deptos_este = length(deptos_franja_este)
        num_deptos_oeste = length(deptos_franja_oeste) - 1

        if balance_mode == :area
            for i in 1:num_deptos_este
                push!(deptos_ordenados_este, (deptos_franja_este[i][1], deptos_franja_este[i][2]))
            end

            num_deptos_oeste_half = div(num_deptos_oeste, 2)
            for i in 1:num_deptos_oeste_half
                push!(deptos_ordenados_oeste, (deptos_franja_oeste[i][1], deptos_franja_oeste[i][2]))
            end
            push!(deptos_ordenados_oeste, (area_escala, -1))
            for i in (num_deptos_oeste_half + 1):num_deptos_oeste
                push!(deptos_ordenados_oeste, (deptos_franja_oeste[i][1], deptos_franja_oeste[i][2]))
            end
        else
            if deptos_total >= 4
                push!(deptos_ordenados_este, (deptos_franja_este[2][1], deptos_franja_este[2][2]))
                if num_deptos_este > 2
                    for i in 3:num_deptos_este
                        push!(deptos_ordenados_este, (deptos_franja_este[i][1], deptos_franja_este[i][2]))
                    end
                end
                push!(deptos_ordenados_este, (deptos_franja_este[1][1], deptos_franja_este[1][2]))

                num_deptos_oeste_half = div(num_deptos_oeste, 2)
                for i in 1:num_deptos_oeste_half
                    push!(deptos_ordenados_oeste, (deptos_franja_oeste[i][1], deptos_franja_oeste[i][2]))
                end
                push!(deptos_ordenados_oeste, (area_escala, -1))
                for i in (num_deptos_oeste_half + 1):num_deptos_oeste
                    push!(deptos_ordenados_oeste, (deptos_franja_oeste[i][1], deptos_franja_oeste[i][2]))
                end
            else
                for depto in deptos_franja_este
                    push!(deptos_ordenados_este, (depto[1], depto[2]))
                end
                num_deptos_oeste_half = div(num_deptos_oeste, 2)
                for i in 1:num_deptos_oeste_half
                    push!(deptos_ordenados_oeste, (deptos_franja_oeste[i][1], deptos_franja_oeste[i][2]))
                end
                push!(deptos_ordenados_oeste, (area_escala, -1))
                for i in (num_deptos_oeste_half + 1):num_deptos_oeste
                    push!(deptos_ordenados_oeste, (deptos_franja_oeste[i][1], deptos_franja_oeste[i][2]))
                end
            end
        end

        return deptos_ordenados_este, deptos_ordenados_oeste
    end

    function calcula_geometria_pasillo(vec_y_fin_este::Vector{Float64}, vec_y_fin_oeste::Vector{Float64}, vec_y_ini_este::Vector{Float64}, vec_y_ini_oeste::Vector{Float64}, x_base::Float64, ancho_pasillo::Float64)
        # Calculate vertical hallway geometry at boundary between oeste and este strips
        # Hallway spans from first apartment end to last apartment start in normalized coordinates
        # Returns: y_ini_pasillo, y_fin_pasillo, largo_pasillo, ps_pasillo

        y_ini_pasillo = min(vec_y_fin_este[1], vec_y_fin_oeste[1])
        y_fin_pasillo = max(vec_y_ini_este[end], vec_y_ini_oeste[end])
        largo_pasillo = y_fin_pasillo - y_ini_pasillo
        x_pasillo = x_base - ancho_pasillo / 2

        ps_pasillo = polyShape.polyBox(x_pasillo, y_ini_pasillo, ancho_pasillo, largo_pasillo, 0.0)

        return y_ini_pasillo, y_fin_pasillo, largo_pasillo, ps_pasillo
    end

    function empaqueta_resultados(num_deptos_este::Int, num_deptos_oeste::Int, deptos_ordenados_este::Vector{Tuple{Float64, Int}}, deptos_ordenados_oeste::Vector{Tuple{Float64, Int}}, ancho_este::Float64, ancho_oeste::Float64, W::Float64, H::Float64, ancho_pasillo::Float64, largo_pasillo::Float64, ps_pasillo::PolyShape, vec_ps_deptos_este::Vector{PolyShape}, vec_ps_deptos_oeste::Vector{PolyShape}, vec_alto_deptos_oeste::Vector{Float64}, vec_tipo_deptos_oeste::Vector{Int}, area_escala::Float64, vec_terrazas_este::Vector{PolyShape}, vec_terrazas_oeste::Vector{PolyShape})
        # Package all optimization results into dictionary format for vertical strips
        # Extracts staircase info and combines apartment/terrace geometries
        # Returns: Dictionary with all floor plan data and metrics

        id_escala = findfirst(==(- 1), vec_tipo_deptos_oeste)
        if id_escala === nothing
            error("No staircase found in oeste strip (tipo_depto == -1)")
        end

        num_escalas = count(==(- 1), vec_tipo_deptos_oeste)
        if num_escalas > 1
            @warn "Multiple staircases found in oeste strip (count=$num_escalas). Using first occurrence at index $id_escala"
        end

        ps_escala = vec_ps_deptos_oeste[id_escala]
        alto_escala = vec_alto_deptos_oeste[id_escala]

        vec_ps_deptos_oeste_sin_escala = [vec_ps_deptos_oeste[i] for i in eachindex(vec_ps_deptos_oeste) if i != id_escala]
        vec_terrazas_oeste_sin_escala = [vec_terrazas_oeste[i] for i in eachindex(vec_terrazas_oeste) if i != id_escala]

        results = Dict(
            "feasible" => true,
            "status" => "LOCALLY_SOLVED",
            "n_apts_este" => num_deptos_este,
            "n_apts_oeste" => num_deptos_oeste,
            "vec_sup_deptos_este" => [apt[1] for apt in deptos_ordenados_este],
            "vec_sup_deptos_oeste" => [apt[1] for apt in deptos_ordenados_oeste if apt[2] != -1],
            "width_este" => round(ancho_este, digits=2),
            "width_oeste" => round(ancho_oeste, digits=2),
            "floor_width" => W,
            "floor_height" => H,
            "ancho_pasillo" => ancho_pasillo,
            "largo_pasillo" => largo_pasillo,
            "ps_pasillo" => ps_pasillo,
            "ps_escala" => ps_escala,
            "ancho_escala" => round(ancho_oeste, digits=2),
            "alto_escala" => round(alto_escala, digits=2),
            "area_escala" => round(area_escala, digits=2),
            "vec_polyshapes_all" => vcat(vec_ps_deptos_este, vec_ps_deptos_oeste_sin_escala),
            "vec_terrazas_all" => vcat(vec_terrazas_este, vec_terrazas_oeste_sin_escala)
        )

        return results
    end

    function verifica_inscripcion_terrazas(ps_planta::PolyShape, vec_terrazas::Vector{PolyShape})
        # Verify that all terrace geometries are inscribed within the floor polygon
        # Returns: true if all terraces fit within floor, false otherwise

        for terraza in vec_terrazas
            inters = polyShape.polyIntersection(ps_planta, terraza)
            area_inters = polyShape.polyArea(inters)
            area_terraza = polyShape.polyArea(terraza)
            if abs(area_inters - area_terraza) > .1
                return false
            end
        end

        return true

    end

    function prepare_floor_inputs(ps_planta::PolyShape, vec_sup_deptos::Vector{Float64}, vec_num_deptos::Vector{Int}, area_escala::Float64, ancho_pasillo::Float64, vec_min_alto_deptos::Vector{Float64}, balance_mode::Symbol)
        # Normalizes floor plan, distributes and orders apartments between oeste/este vertical strips
        # Returns: NamedTuple with normalized geometry, ordered apartments, dimensions, and constraints
        if isempty(vec_min_alto_deptos)
            vec_min_alto_deptos = zeros(Float64, length(vec_sup_deptos))
        end

        W, H, vec_x_planta, vec_y_planta, angulo_rotacion, cr, ps_planta_normalizado = normaliza_planta_rectangular(ps_planta)

        deptos_total = sum(vec_num_deptos)
        deptos_franja_este, deptos_franja_oeste, area_este, area_oeste = distribuye_deptos_entre_franjas(vec_sup_deptos, vec_num_deptos, area_escala)

        ancho_terraza_max = 2.0
        ancho_depto_este, ancho_depto_oeste = calcula_anchos_franjas(area_este, area_oeste, W, H, ancho_pasillo, ancho_terraza_max)

        x_min_planta = minimum(vec_x_planta)
        y_min_planta = minimum(vec_y_planta)

        total_ancho_este_utilizado = ancho_terraza_max + ancho_depto_este + ancho_pasillo / 2
        total_ancho_oeste_utilizado = ancho_terraza_max + ancho_depto_oeste + ancho_pasillo / 2
        total_ancho_utilizado = total_ancho_este_utilizado + total_ancho_oeste_utilizado
        holgura_ancho = W - total_ancho_utilizado
        x_min_planta += ancho_terraza_max + holgura_ancho/2

        deptos_ordenados_este, deptos_ordenados_oeste = ordena_deptos_en_franja(deptos_franja_este, deptos_franja_oeste, area_escala, deptos_total, balance_mode=balance_mode)

        return (W=W, H=H, vec_x_planta=vec_x_planta, vec_y_planta=vec_y_planta, angulo_rotacion=angulo_rotacion,
                cr=cr, ps_planta_normalizado=ps_planta_normalizado, deptos_ordenados_este=deptos_ordenados_este,
                deptos_ordenados_oeste=deptos_ordenados_oeste, ancho_depto_este=ancho_depto_este, ancho_depto_oeste=ancho_depto_oeste,
                x_min_planta=x_min_planta, y_min_planta=y_min_planta, ancho_terraza_max=ancho_terraza_max,
                total_ancho_este_utilizado=total_ancho_este_utilizado, total_ancho_oeste_utilizado=total_ancho_oeste_utilizado,
                vec_min_alto_deptos=vec_min_alto_deptos)
    end

    function compute_strip_geometries(inputs, ancho_pasillo::Float64, vec_sup_terraza::Vector{Float64}, min_alto_escala::Float64)
        # Generates apartment and terrace geometries in normalized space for vertical strips, creates vertical hallway, handles terrace translation
        # Returns: NamedTuple with normalized apartment/terrace polygons, hallway geometry, and metadata
        x_base = inputs.x_min_planta + inputs.ancho_depto_oeste
        vec_y_ini_este, vec_y_fin_este, vec_ancho_deptos_este, vec_alto_deptos_este, _ = genera_deptos_franja(inputs.deptos_ordenados_este, inputs.y_min_planta, x_base, inputs.ancho_depto_este, :este, inputs.vec_min_alto_deptos, inputs.H, min_alto_escala)
        vec_y_ini_oeste, vec_y_fin_oeste, vec_ancho_deptos_oeste, vec_alto_deptos_oeste, vec_tipo_deptos_oeste = genera_deptos_franja(inputs.deptos_ordenados_oeste, inputs.y_min_planta, x_base, inputs.ancho_depto_oeste, :oeste, inputs.vec_min_alto_deptos, inputs.H, min_alto_escala)

        y_ini_pasillo, y_fin_pasillo, largo_pasillo, ps_pasillo_normalizado = calcula_geometria_pasillo(vec_y_fin_este, vec_y_fin_oeste, vec_y_ini_este, vec_y_ini_oeste, x_base, ancho_pasillo)

        vec_ps_deptos_este_normalizado, vec_extension_ancho_deptos_este = extiende_deptos_interseccion_pasillo(vec_y_ini_este, vec_y_fin_este, vec_ancho_deptos_este, vec_alto_deptos_este, x_base, y_ini_pasillo, y_fin_pasillo, ancho_pasillo, ps_pasillo_normalizado, :este)
        vec_ps_deptos_oeste_normalizado, vec_extension_ancho_deptos_oeste = extiende_deptos_interseccion_pasillo(vec_y_ini_oeste, vec_y_fin_oeste, vec_ancho_deptos_oeste, vec_alto_deptos_oeste, x_base, y_ini_pasillo, y_fin_pasillo, ancho_pasillo, ps_pasillo_normalizado, :oeste)

        vec_terrazas_este_normalizado = PolyShape[]
        vec_terrazas_oeste_normalizado = PolyShape[]

        if !isempty(vec_sup_terraza)
            x_terrace_base_este = [x_base + vec_ancho_deptos_este[i] + vec_extension_ancho_deptos_este[i] for i in eachindex(inputs.deptos_ordenados_este)]
            vec_terrazas_este_normalizado = genera_terrazas_franja(inputs.deptos_ordenados_este, vec_sup_terraza, vec_alto_deptos_este, vec_y_ini_este, x_terrace_base_este, :este, inputs.ancho_terraza_max)

            x_terrace_base_oeste = [x_base - vec_ancho_deptos_oeste[i] - vec_extension_ancho_deptos_oeste[i] for i in eachindex(inputs.deptos_ordenados_oeste)]
            vec_terrazas_oeste_normalizado = genera_terrazas_franja(inputs.deptos_ordenados_oeste, vec_sup_terraza, vec_alto_deptos_oeste, vec_y_ini_oeste, x_terrace_base_oeste, :oeste, inputs.ancho_terraza_max)

            flag_inscripcion_este = verifica_inscripcion_terrazas(inputs.ps_planta_normalizado, vec_terrazas_este_normalizado)
            flag_inscripcion_oeste = verifica_inscripcion_terrazas(inputs.ps_planta_normalizado, vec_terrazas_oeste_normalizado)

            if !flag_inscripcion_este && inputs.total_ancho_oeste_utilizado < inputs.W/2
                x_max_planta = maximum(inputs.vec_x_planta)
                terrazas_este_con_area = [t for t in vec_terrazas_este_normalizado if polyShape.polyArea(t) > 0.0]

                if !isempty(terrazas_este_con_area)
                    max_x_terrazas_este = maximum([maximum(t.Vertices[1][:, 1]) for t in terrazas_este_con_area])
                    delta_x = max_x_terrazas_este - x_max_planta

                    vec_ps_deptos_este_normalizado = [polyShape.polyTranslate(p, -delta_x, 0.0) for p in vec_ps_deptos_este_normalizado]
                    vec_ps_deptos_oeste_normalizado = [polyShape.polyTranslate(p, -delta_x, 0.0) for p in vec_ps_deptos_oeste_normalizado]
                    vec_terrazas_este_normalizado = [polyShape.polyTranslate(t, -delta_x, 0.0) for t in vec_terrazas_este_normalizado]
                    vec_terrazas_oeste_normalizado = [polyShape.polyTranslate(t, -delta_x, 0.0) for t in vec_terrazas_oeste_normalizado]
                    ps_pasillo_normalizado = polyShape.polyTranslate(ps_pasillo_normalizado, -delta_x, 0.0)

                    println("Translated all elements west by $(round(delta_x, digits=2)) to fit este terraces")
                end
            elseif !flag_inscripcion_oeste && inputs.total_ancho_este_utilizado < inputs.W/2
                x_min_planta = minimum(inputs.vec_x_planta)
                terrazas_oeste_con_area = [t for t in vec_terrazas_oeste_normalizado if polyShape.polyArea(t) > 0.0]

                if !isempty(terrazas_oeste_con_area)
                    min_x_terrazas_oeste = minimum([minimum(t.Vertices[1][:, 1]) for t in terrazas_oeste_con_area])
                    delta_x = x_min_planta - min_x_terrazas_oeste

                    vec_ps_deptos_este_normalizado = [polyShape.polyTranslate(p, delta_x, 0.0) for p in vec_ps_deptos_este_normalizado]
                    vec_ps_deptos_oeste_normalizado = [polyShape.polyTranslate(p, delta_x, 0.0) for p in vec_ps_deptos_oeste_normalizado]
                    vec_terrazas_este_normalizado = [polyShape.polyTranslate(t, delta_x, 0.0) for t in vec_terrazas_este_normalizado]
                    vec_terrazas_oeste_normalizado = [polyShape.polyTranslate(t, delta_x, 0.0) for t in vec_terrazas_oeste_normalizado]
                    ps_pasillo_normalizado = polyShape.polyTranslate(ps_pasillo_normalizado, delta_x, 0.0)

                    println("Translated all elements east by $(round(delta_x, digits=2)) to fit oeste terraces")
                end
            end
        end

        return (vec_ps_deptos_este_normalizado=vec_ps_deptos_este_normalizado, vec_ps_deptos_oeste_normalizado=vec_ps_deptos_oeste_normalizado,
                vec_terrazas_este_normalizado=vec_terrazas_este_normalizado, vec_terrazas_oeste_normalizado=vec_terrazas_oeste_normalizado,
                ps_pasillo_normalizado=ps_pasillo_normalizado, largo_pasillo=largo_pasillo,
                vec_alto_deptos_oeste=vec_alto_deptos_oeste, vec_tipo_deptos_oeste=vec_tipo_deptos_oeste)
    end




    inputs = prepare_floor_inputs(ps_planta, vec_sup_deptos, vec_num_deptos, area_escala, ancho_pasillo, vec_min_alto_deptos, balance_mode)

    geometries = compute_strip_geometries(inputs, ancho_pasillo, vec_sup_terraza, min_alto_escala)

    vec_ps_deptos_este = rota_polyshapes(geometries.vec_ps_deptos_este_normalizado, inputs.angulo_rotacion, inputs.cr)
    vec_ps_deptos_oeste = rota_polyshapes(geometries.vec_ps_deptos_oeste_normalizado, inputs.angulo_rotacion, inputs.cr)
    vec_terrazas_este = rota_polyshapes(geometries.vec_terrazas_este_normalizado, inputs.angulo_rotacion, inputs.cr)
    vec_terrazas_oeste = rota_polyshapes(geometries.vec_terrazas_oeste_normalizado, inputs.angulo_rotacion, inputs.cr)
    ps_pasillo = polyShape.polyRotate(geometries.ps_pasillo_normalizado, -inputs.angulo_rotacion, inputs.cr)

    num_deptos_este = length(inputs.deptos_ordenados_este)
    num_deptos_oeste = length(inputs.deptos_ordenados_oeste) - 1

    results = empaqueta_resultados(num_deptos_este, num_deptos_oeste, inputs.deptos_ordenados_este, inputs.deptos_ordenados_oeste,
                                    inputs.ancho_depto_este, inputs.ancho_depto_oeste, inputs.W, inputs.H, ancho_pasillo, geometries.largo_pasillo, ps_pasillo,
                                    vec_ps_deptos_este, vec_ps_deptos_oeste, geometries.vec_alto_deptos_oeste, geometries.vec_tipo_deptos_oeste,
                                    area_escala, vec_terrazas_este, vec_terrazas_oeste)

    return results
end
