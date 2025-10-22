function genera_deptos_franja(vec_orden_deptos::Vector{Tuple{Float64, Int}}, x_min_planta::Float64, y_base::Float64, alto_franja::Float64, direction::Symbol, vec_min_ancho_deptos::Vector{Float64}, ancho_disponible::Float64, min_ancho_escala::Float64)
    # Generate apartment geometries for strip with minimum width constraints
    # Iteratively adjusts strip height until apartments fill available width while respecting min widths
    # Returns: (vec_x_ini, vec_x_fin, vec_ancho_deptos, vec_alto_deptos, vec_tipo_deptos)
    vec_x_ini = Float64[]
    vec_x_fin = Float64[]
    vec_ancho_deptos = Float64[]
    vec_alto_deptos = Float64[]
    vec_tipo_deptos = Int[]

    alto_franja_adjusted = alto_franja
    max_iterations = 10

    for _ in 1:max_iterations
        empty!(vec_x_ini)
        empty!(vec_x_fin)
        empty!(vec_ancho_deptos)
        empty!(vec_alto_deptos)
        empty!(vec_tipo_deptos)

        x_current = x_min_planta
        total_width = 0.0

        for (sup_depto, tipo_depto) in vec_orden_deptos
            if tipo_depto == -1
                ancho_depto = sup_depto / alto_franja_adjusted
                if ancho_depto < min_ancho_escala
                    ancho_depto = min_ancho_escala
                    alto_depto = sup_depto / ancho_depto
                else
                    alto_depto = alto_franja_adjusted
                end
            else
                ancho_depto = sup_depto / alto_franja_adjusted
                if ancho_depto < vec_min_ancho_deptos[tipo_depto]
                    ancho_depto = vec_min_ancho_deptos[tipo_depto]
                    alto_depto = sup_depto / ancho_depto
                else
                    alto_depto = alto_franja_adjusted
                end
            end

            push!(vec_x_ini, x_current)
            push!(vec_x_fin, x_current + ancho_depto)
            push!(vec_ancho_deptos, ancho_depto)
            push!(vec_alto_deptos, alto_depto)
            push!(vec_tipo_deptos, tipo_depto)
            x_current += ancho_depto
            total_width += ancho_depto
        end

        if abs(total_width - ancho_disponible) / ancho_disponible < 0.005
            break
        end

        alto_franja_adjusted = alto_franja_adjusted * (total_width / ancho_disponible)
    end

    return vec_x_ini, vec_x_fin, vec_ancho_deptos, vec_alto_deptos, vec_tipo_deptos
end

function extiende_deptos_interseccion_pasillo(vec_x_ini::Vector{Float64}, vec_x_fin::Vector{Float64}, vec_ancho_deptos::Vector{Float64}, vec_alto_deptos::Vector{Float64}, y_base::Float64, x_ini_pasillo::Float64, x_fin_pasillo::Float64, ancho_pasillo::Float64, ps_pasillo::PolyShape, extend_direction::Symbol)
    # Extend apartments into hallway area to maintain required area, then subtract hallway overlap
    # Calculates extension height based on hallway intersection, positions relative to y_base
    # Works in normalized (unrotated) coordinate system
    # Returns: (vec_ps_deptos, vec_extension_heights)
    vec_extension_alto_deptos = Float64[]
    ps_deptos_extendidos = PolyShape[]

    for i in eachindex(vec_x_ini)
        x_overlap_start = max(vec_x_ini[i], x_ini_pasillo)
        x_overlap_end = min(vec_x_fin[i], x_fin_pasillo)

        if x_overlap_start < x_overlap_end
            overlap_width = x_overlap_end - x_overlap_start
            intersection_area = overlap_width * ancho_pasillo
            extension_height = intersection_area / vec_ancho_deptos[i]
        else
            extension_height = 0.0
        end

        push!(vec_extension_alto_deptos, extension_height)

        alto_total_depto = vec_alto_deptos[i] + extension_height
        ancho_depto = vec_x_fin[i] - vec_x_ini[i]

        if extend_direction == :norte
            y_ini_depto = y_base
        else
            y_ini_depto = y_base - alto_total_depto
        end

        extended_local_poly = polyShape.polyBox(vec_x_ini[i], y_ini_depto, ancho_depto, alto_total_depto, 0.0)
        extended_poly_final = polyShape.polyDifference(extended_local_poly, ps_pasillo)
        push!(ps_deptos_extendidos, extended_poly_final)
    end

    return ps_deptos_extendidos, vec_extension_alto_deptos
end

function genera_terrazas_franja(vec_orden_deptos::Vector{Tuple{Float64, Int}}, vec_sup_terraza::Vector{Float64}, vec_ancho_deptos::Vector{Float64}, vec_x_ini::Vector{Float64}, y_terrace_base::Vector{Float64}, terrace_direction::Symbol, max_alto_terraza::Float64)
    # Generate terrace geometries for apartments, constrained by max depth and apartment width
    # Adjusts dimensions to maintain required area, centers terraces on apartments
    # Returns: Vector of terrace PolyShapes

    vec_terrazas = PolyShape[]

    for (i, (_, tipo_depto)) in enumerate(vec_orden_deptos)
        if tipo_depto == -1
            push!(vec_terrazas, PolyShape([zeros(0, 2)], 0))
        else
            area_terraza = vec_sup_terraza[tipo_depto]
            if area_terraza > 0.0
                ancho_depto = vec_ancho_deptos[i]
                alto_terraza = 1.75

                ancho_terraza = area_terraza / alto_terraza

                if ancho_terraza > ancho_depto
                    ancho_terraza = ancho_depto
                    alto_terraza = min(area_terraza / ancho_terraza, max_alto_terraza)
                    if alto_terraza < area_terraza / ancho_terraza
                        ancho_terraza = area_terraza / alto_terraza
                    end
                end

                x_depto_ini = vec_x_ini[i]
                x_terraza_ini = x_depto_ini + (ancho_depto - ancho_terraza) / 2

                if terrace_direction == :norte
                    y_terraza_ini = y_terrace_base[i]
                else
                    y_terraza_ini = y_terrace_base[i] - alto_terraza
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
    # Distribute apartments between north and south strips, balancing total areas
    # Staircase assigned to south strip, apartments sorted by size (largest first)
    # Returns: deptos_franja_norte, deptos_franja_sur, area_norte, area_sur

    num_tipo_deptos = length(vec_sup_deptos)
    vec_ordenado_tipo_deptos = sort(collect(1:num_tipo_deptos), by = i -> vec_sup_deptos[i], rev = true)

    deptos_franja_norte = Tuple{Float64, Int, Int}[]
    deptos_franja_sur = Tuple{Float64, Int, Int}[]
    area_norte = 0.0
    area_sur = 0.0

    for tipo_depto in vec_ordenado_tipo_deptos
        sup_depto = vec_sup_deptos[tipo_depto]
        num_deptos = vec_num_deptos[tipo_depto]
        total_type_area = sup_depto * num_deptos

        if area_norte <= area_sur + area_escala
            for j in 1:num_deptos
                push!(deptos_franja_norte, (sup_depto, tipo_depto, j))
            end
            area_norte += total_type_area
        else
            for j in 1:num_deptos
                push!(deptos_franja_sur, (sup_depto, tipo_depto, j))
            end
            area_sur += total_type_area
        end
    end

    push!(deptos_franja_sur, (area_escala, -1, 1))
    area_sur += area_escala

    return deptos_franja_norte, deptos_franja_sur, area_norte, area_sur
end

function calcula_alturas_franjas(area_norte::Float64, area_sur::Float64, W::Float64, H::Float64, ancho_pasillo::Float64, alto_terraza_max::Float64)
    # Calculate strip heights based on apartment areas and available floor space
    # Reserves space for terraces and hallway, scales down if total exceeds available height
    # Returns: alto_norte, alto_sur

    alto_disponible_franja = H - 2 * alto_terraza_max - ancho_pasillo

    alto_norte_requerido = area_norte / W
    alto_sur_requerido = area_sur / W

    if alto_norte_requerido + alto_sur_requerido > alto_disponible_franja
        scale_factor = alto_disponible_franja / (alto_norte_requerido + alto_sur_requerido)
        alto_norte = alto_norte_requerido * scale_factor
        alto_sur = alto_sur_requerido * scale_factor
    else
        alto_norte = alto_norte_requerido
        alto_sur = alto_sur_requerido
    end

    return alto_norte, alto_sur
end

function ordena_deptos_en_franja(deptos_franja_norte::Vector{Tuple{Float64, Int, Int}}, deptos_franja_sur::Vector{Tuple{Float64, Int, Int}}, area_escala::Float64, deptos_total::Int)
    # Arrange apartments horizontally within each strip for visual balance
    # North: 2nd largest, middle units, largest (ends). South: first half, staircase (center), second half
    # Returns: deptos_ordenados_norte, deptos_ordenados_sur

    deptos_ordenados_norte = Tuple{Float64, Int}[]
    deptos_ordenados_sur = Tuple{Float64, Int}[]

    num_deptos_norte = length(deptos_franja_norte)
    num_deptos_sur = length(deptos_franja_sur) - 1

    if deptos_total >= 4
        push!(deptos_ordenados_norte, (deptos_franja_norte[2][1], deptos_franja_norte[2][2]))
        if num_deptos_norte > 2
            for i in 3:num_deptos_norte
                push!(deptos_ordenados_norte, (deptos_franja_norte[i][1], deptos_franja_norte[i][2]))
            end
        end
        push!(deptos_ordenados_norte, (deptos_franja_norte[1][1], deptos_franja_norte[1][2]))

        num_deptos_sur_half = div(num_deptos_sur, 2)
        for i in 1:num_deptos_sur_half
            push!(deptos_ordenados_sur, (deptos_franja_sur[i][1], deptos_franja_sur[i][2]))
        end
        push!(deptos_ordenados_sur, (area_escala, -1))
        for i in (num_deptos_sur_half + 1):num_deptos_sur
            push!(deptos_ordenados_sur, (deptos_franja_sur[i][1], deptos_franja_sur[i][2]))
        end
    else
        for depto in deptos_franja_norte
            push!(deptos_ordenados_norte, (depto[1], depto[2]))
        end
        num_deptos_sur_half = div(num_deptos_sur, 2)
        for i in 1:num_deptos_sur_half
            push!(deptos_ordenados_sur, (deptos_franja_sur[i][1], deptos_franja_sur[i][2]))
        end
        push!(deptos_ordenados_sur, (area_escala, -1))
        for i in (num_deptos_sur_half + 1):num_deptos_sur
            push!(deptos_ordenados_sur, (deptos_franja_sur[i][1], deptos_franja_sur[i][2]))
        end
    end

    return deptos_ordenados_norte, deptos_ordenados_sur
end

function calcula_geometria_pasillo(vec_x_fin_norte::Vector{Float64}, vec_x_fin_sur::Vector{Float64}, vec_x_ini_norte::Vector{Float64}, vec_x_ini_sur::Vector{Float64}, y_base::Float64, ancho_pasillo::Float64)
    # Calculate hallway geometry at boundary between north and south strips
    # Hallway spans from first apartment end to last apartment start in normalized coordinates
    # Returns: x_ini_pasillo, x_fin_pasillo, largo_pasillo, ps_pasillo

    x_ini_pasillo = min(vec_x_fin_norte[1], vec_x_fin_sur[1])
    x_fin_pasillo = max(vec_x_ini_norte[end], vec_x_ini_sur[end])
    largo_pasillo = x_fin_pasillo - x_ini_pasillo
    y_pasillo = y_base - ancho_pasillo / 2

    ps_pasillo = polyShape.polyBox(x_ini_pasillo, y_pasillo, largo_pasillo, ancho_pasillo, 0.0)

    return x_ini_pasillo, x_fin_pasillo, largo_pasillo, ps_pasillo
end

function empaqueta_resultados(num_deptos_norte::Int, num_deptos_sur::Int, deptos_ordenados_norte::Vector{Tuple{Float64, Int}}, deptos_ordenados_sur::Vector{Tuple{Float64, Int}}, alto_norte::Float64, alto_sur::Float64, W::Float64, H::Float64, ancho_pasillo::Float64, largo_pasillo::Float64, ps_pasillo::PolyShape, vec_ps_deptos_norte::Vector{PolyShape}, vec_ps_deptos_sur::Vector{PolyShape}, vec_ancho_deptos_sur::Vector{Float64}, vec_tipo_deptos_sur::Vector{Int}, area_escala::Float64, vec_terrazas_norte::Vector{PolyShape}, vec_terrazas_sur::Vector{PolyShape})
    # Package all optimization results into dictionary format
    # Extracts staircase info and combines apartment/terrace geometries
    # Returns: Dictionary with all floor plan data and metrics

    id_escala = findfirst(t -> t == -1, vec_tipo_deptos_sur)
    ps_escala = vec_ps_deptos_sur[id_escala]
    ancho_escala = vec_ancho_deptos_sur[id_escala]

    vec_ps_deptos_sur_sin_escala = [vec_ps_deptos_sur[i] for i in eachindex(vec_ps_deptos_sur) if i != id_escala]
    vec_terrazas_sur_sin_escala = [vec_terrazas_sur[i] for i in eachindex(vec_terrazas_sur) if i != id_escala]

    results = Dict(
        "feasible" => true,
        "status" => "LOCALLY_SOLVED",
        "n_apts_norte" => num_deptos_norte,
        "n_apts_sur" => num_deptos_sur,
        "vec_sup_deptos_norte" => [apt[1] for apt in deptos_ordenados_norte],
        "vec_sup_deptos_sur" => [apt[1] for apt in deptos_ordenados_sur if apt[2] != -1],
        "height_norte" => round(alto_norte, digits=2),
        "height_sur" => round(alto_sur, digits=2),
        "floor_width" => W,
        "floor_height" => H,
        "ancho_pasillo" => ancho_pasillo,
        "largo_pasillo" => largo_pasillo,
        "ps_pasillo" => ps_pasillo,
        "ps_escala" => ps_escala,
        "ancho_escala" => round(ancho_escala, digits=2),
        "alto_escala" => round(alto_sur, digits=2),
        "area_escala" => round(area_escala, digits=2),
        "vec_polyshapes_all" => vcat(vec_ps_deptos_norte, vec_ps_deptos_sur_sin_escala),
        "vec_terrazas_all" => vcat(vec_terrazas_norte, vec_terrazas_sur_sin_escala)
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

function opti_floor_plan(ps_planta::PolyShape, vec_sup_deptos::Vector{Float64}, vec_num_deptos::Vector{Int}; ancho_pasillo::Float64 = 2.0, vec_sup_terraza::Vector{Float64} = Float64[], area_escala::Float64 = 25.0, vec_min_ancho_deptos::Vector{Float64} = Float64[], min_ancho_escala::Float64 = 0.0)
    # Optimize floor plan layout by distributing apartments in two horizontal strips
    # Normalizes floor, balances apartments between strips, generates geometries with minimum width constraints
    # Returns: Dictionary with apartment polygons, hallway, terraces, staircase, and metrics

    if isempty(vec_min_ancho_deptos)
        vec_min_ancho_deptos = zeros(Float64, length(vec_sup_deptos))
    end

    W, H, vec_x_planta, vec_y_planta, angulo_rotacion, cr, ps_planta_normalizado = normaliza_planta_rectangular(ps_planta)

    deptos_total = sum(vec_num_deptos)
    deptos_franja_norte, deptos_franja_sur, area_norte, area_sur = distribuye_deptos_entre_franjas(vec_sup_deptos, vec_num_deptos, area_escala)

    alto_terraza_max = 1.75
    alto_depto_norte, alto_depto_sur = calcula_alturas_franjas(area_norte, area_sur, W, H, ancho_pasillo, alto_terraza_max)

    x_min_planta = minimum(vec_x_planta)
    y_min_planta = minimum(vec_y_planta)

    total_altura_norte_utilizada = alto_terraza_max + alto_depto_norte + ancho_pasillo / 2
    total_altura_sur_utilizada = alto_terraza_max + alto_depto_sur + ancho_pasillo / 2
    total_altura_utilizada = total_altura_norte_utilizada + total_altura_sur_utilizada
    holgura_alto = H - total_altura_utilizada
    y_min_planta += alto_terraza_max + holgura_alto/2

    deptos_ordenados_norte, deptos_ordenados_sur = ordena_deptos_en_franja(deptos_franja_norte, deptos_franja_sur, area_escala, deptos_total)

    y_base = y_min_planta + alto_depto_sur
    vec_x_ini_norte, vec_x_fin_norte, vec_ancho_deptos_norte, vec_alto_deptos_norte, _ = genera_deptos_franja(deptos_ordenados_norte, x_min_planta, y_base, alto_depto_norte, :norte, vec_min_ancho_deptos, W, min_ancho_escala)
    vec_x_ini_sur, vec_x_fin_sur, vec_ancho_deptos_sur, vec_alto_deptos_sur, vec_tipo_deptos_sur = genera_deptos_franja(deptos_ordenados_sur, x_min_planta, y_base, alto_depto_sur, :sur, vec_min_ancho_deptos, W, min_ancho_escala)

    x_ini_pasillo, x_fin_pasillo, largo_pasillo, ps_pasillo_normalizado = calcula_geometria_pasillo(vec_x_fin_norte, vec_x_fin_sur, vec_x_ini_norte, vec_x_ini_sur, y_base, ancho_pasillo)

    vec_ps_deptos_norte_normalizado, vec_extension_alto_deptos_norte = extiende_deptos_interseccion_pasillo(vec_x_ini_norte, vec_x_fin_norte, vec_ancho_deptos_norte, vec_alto_deptos_norte, y_base, x_ini_pasillo, x_fin_pasillo, ancho_pasillo, ps_pasillo_normalizado, :norte)
    vec_ps_deptos_sur_normalizado, vec_extension_alto_deptos_sur = extiende_deptos_interseccion_pasillo(vec_x_ini_sur, vec_x_fin_sur, vec_ancho_deptos_sur, vec_alto_deptos_sur, y_base, x_ini_pasillo, x_fin_pasillo, ancho_pasillo, ps_pasillo_normalizado, :sur)

    vec_terrazas_norte_normalizado = PolyShape[]
    vec_terrazas_sur_normalizado = PolyShape[]

    if !isempty(vec_sup_terraza)
        y_terrace_base_norte = [y_base + vec_alto_deptos_norte[i] + vec_extension_alto_deptos_norte[i] for i in eachindex(deptos_ordenados_norte)]
        vec_terrazas_norte_normalizado = genera_terrazas_franja(deptos_ordenados_norte, vec_sup_terraza, vec_ancho_deptos_norte, vec_x_ini_norte, y_terrace_base_norte, :norte, alto_terraza_max)

        y_terrace_base_sur = [y_base - vec_alto_deptos_sur[i] - vec_extension_alto_deptos_sur[i] for i in eachindex(deptos_ordenados_sur)]
        vec_terrazas_sur_normalizado = genera_terrazas_franja(deptos_ordenados_sur, vec_sup_terraza, vec_ancho_deptos_sur, vec_x_ini_sur, y_terrace_base_sur, :sur, alto_terraza_max)

        flag_inscripcion_norte = verifica_inscripcion_terrazas(ps_planta_normalizado, vec_terrazas_norte_normalizado)
        flag_inscripcion_sur = verifica_inscripcion_terrazas(ps_planta_normalizado, vec_terrazas_sur_normalizado)

        if !flag_inscripcion_norte && total_altura_sur_utilizada < H/2
            y_max_planta = maximum(vec_y_planta)
            terrazas_norte_con_area = [t for t in vec_terrazas_norte_normalizado if polyShape.polyArea(t) > 0.0]

            if !isempty(terrazas_norte_con_area)
                max_y_terrazas_norte = maximum([maximum(t.Vertices[1][:, 2]) for t in terrazas_norte_con_area])
                delta_y = max_y_terrazas_norte - y_max_planta

                vec_ps_deptos_norte_normalizado = [polyShape.polyTranslate(p, 0.0, -delta_y) for p in vec_ps_deptos_norte_normalizado]
                vec_ps_deptos_sur_normalizado = [polyShape.polyTranslate(p, 0.0, -delta_y) for p in vec_ps_deptos_sur_normalizado]
                vec_terrazas_norte_normalizado = [polyShape.polyTranslate(t, 0.0, -delta_y) for t in vec_terrazas_norte_normalizado]
                vec_terrazas_sur_normalizado = [polyShape.polyTranslate(t, 0.0, -delta_y) for t in vec_terrazas_sur_normalizado]
                ps_pasillo_normalizado = polyShape.polyTranslate(ps_pasillo_normalizado, 0.0, -delta_y)

                println("Translated all elements south by $(round(delta_y, digits=2)) to fit north terraces")
            end
        elseif !flag_inscripcion_sur && total_altura_norte_utilizada < H/2
            y_min_planta = minimum(vec_y_planta)
            terrazas_sur_con_area = [t for t in vec_terrazas_sur_normalizado if polyShape.polyArea(t) > 0.0]

            if !isempty(terrazas_sur_con_area)
                min_y_terrazas_sur = minimum([minimum(t.Vertices[1][:, 2]) for t in terrazas_sur_con_area])
                delta_y = y_min_planta - min_y_terrazas_sur

                vec_ps_deptos_norte_normalizado = [polyShape.polyTranslate(p, 0.0, delta_y) for p in vec_ps_deptos_norte_normalizado]
                vec_ps_deptos_sur_normalizado = [polyShape.polyTranslate(p, 0.0, delta_y) for p in vec_ps_deptos_sur_normalizado]
                vec_terrazas_norte_normalizado = [polyShape.polyTranslate(t, 0.0, delta_y) for t in vec_terrazas_norte_normalizado]
                vec_terrazas_sur_normalizado = [polyShape.polyTranslate(t, 0.0, delta_y) for t in vec_terrazas_sur_normalizado]
                ps_pasillo_normalizado = polyShape.polyTranslate(ps_pasillo_normalizado, 0.0, delta_y)

                println("Translated all elements north by $(round(delta_y, digits=2)) to fit south terraces")
            end
        end
    end

    vec_ps_deptos_norte = rota_polyshapes(vec_ps_deptos_norte_normalizado, angulo_rotacion, cr)
    vec_ps_deptos_sur = rota_polyshapes(vec_ps_deptos_sur_normalizado, angulo_rotacion, cr)
    vec_terrazas_norte = rota_polyshapes(vec_terrazas_norte_normalizado, angulo_rotacion, cr)
    vec_terrazas_sur = rota_polyshapes(vec_terrazas_sur_normalizado, angulo_rotacion, cr)
    ps_pasillo = polyShape.polyRotate(ps_pasillo_normalizado, -angulo_rotacion, cr)

    num_deptos_norte = length(deptos_ordenados_norte)
    num_deptos_sur = length(deptos_ordenados_sur) - 1

    results = empaqueta_resultados(num_deptos_norte, num_deptos_sur, deptos_ordenados_norte, deptos_ordenados_sur,
                                    alto_depto_norte, alto_depto_sur, W, H, ancho_pasillo, largo_pasillo, ps_pasillo,
                                    vec_ps_deptos_norte, vec_ps_deptos_sur, vec_ancho_deptos_sur, vec_tipo_deptos_sur,
                                    area_escala, vec_terrazas_norte, vec_terrazas_sur)

    return results
end
