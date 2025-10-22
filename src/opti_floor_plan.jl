function genera_deptos_franja(apt_order::Vector{Tuple{Float64, Int}}, x_min_planta::Float64, y_base::Float64, alto_franja::Float64)
    vec_x_ini = Float64[]
    vec_x_fin = Float64[]
    vec_ancho_deptos = Float64[]
    vec_tipo_deptos = Int[]

    x_current = x_min_planta

    for (sup_depto, tipo_depto) in apt_order
        ancho_depto = sup_depto / alto_franja

        push!(vec_x_ini, x_current)
        push!(vec_x_fin, x_current + ancho_depto)
        push!(vec_ancho_deptos, ancho_depto)
        push!(vec_tipo_deptos, tipo_depto)
        x_current += ancho_depto
    end

    return vec_x_ini, vec_x_fin, vec_ancho_deptos, vec_tipo_deptos
end

function extiende_deptos_interseccion_pasillo(vec_x_ini::Vector{Float64}, vec_x_fin::Vector{Float64}, vec_ancho_deptos::Vector{Float64}, y_base::Float64, alto_franja::Float64, x_ini_pasillo::Float64, x_fin_pasillo::Float64, y_pasillo::Float64, ancho_pasillo::Float64, angulo_rotacion::Float64, cr::Vector{Float64}, extend_direction::Symbol)
    vec_extension_alto_deptos = Float64[]
    ps_deptos_extendidos = PolyShape[]

    largo_pasillo = x_fin_pasillo - x_ini_pasillo
    ps_pasillo_aux = polyShape.polyBox(x_ini_pasillo, y_pasillo, largo_pasillo, ancho_pasillo, 0.0)
    ps_pasillo = polyShape.polyRotate(ps_pasillo_aux, -angulo_rotacion, cr)

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

        alto_total_depto = alto_franja + extension_height
        ancho_depto = vec_x_fin[i] - vec_x_ini[i]

        if extend_direction == :norte
            y_ini_depto = y_base
        else
            y_ini_depto = y_base - extension_height
        end

        extended_local_poly = polyShape.polyBox(vec_x_ini[i], y_ini_depto, ancho_depto, alto_total_depto, 0.0)
        extended_poly_rotated = polyShape.polyRotate(extended_local_poly, -angulo_rotacion, cr)

        extended_poly = polyShape.polyDifference(extended_poly_rotated, ps_pasillo)
        push!(ps_deptos_extendidos, extended_poly)
    end

    return ps_deptos_extendidos, vec_extension_alto_deptos
end

function genera_terrazas_franja(apt_order::Vector{Tuple{Float64, Int}}, vec_sup_terraza::Vector{Float64}, vec_ancho_deptos::Vector{Float64}, vec_x_ini::Vector{Float64}, y_terrace_base::Vector{Float64}, angulo_rotacion::Float64, cr::Vector{Float64}, terrace_direction::Symbol)
    vec_terrazas = PolyShape[]

    for (i, (_, tipo_depto)) in enumerate(apt_order)
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
                    alto_terraza = area_terraza / ancho_terraza
                end

                y_depto_ini = vec_x_ini[i]
                x_terraza_ini = y_depto_ini + (ancho_depto - ancho_terraza) / 2

                if terrace_direction == :norte
                    y_terraza_ini = y_terrace_base[i]
                else
                    y_terraza_ini = y_terrace_base[i] - alto_terraza
                end

                terrace_poly = polyShape.polyBox(x_terraza_ini, y_terraza_ini, ancho_terraza, alto_terraza, 0.0)
                terrace_rotated = polyShape.polyRotate(terrace_poly, -angulo_rotacion, cr)
                push!(vec_terrazas, terrace_rotated)
            else
                push!(vec_terrazas, PolyShape([zeros(0, 2)], 0))
            end
        end
    end

    return vec_terrazas
end

function opti_floor_plan(ps_planta::PolyShape, vec_sup_deptos::Vector{Float64}, vec_num_deptos::Vector{Int}; ancho_pasillo::Float64 = 2.0, vec_sup_terraza::Vector{Float64} = Float64[], area_escala::Float64 = 25.0, min_ancho_escala::Float64 = 5.0)

    # Optimize floor plan layout by distributing apartments in two horizontal strips
    # Algorithm:
    # 1. Normalize floor polygon to axis-aligned rectangle (W x H, where W > H)
    # 2. Distribute apartments to north and south strips, balancing total areas
    # 3. Calculate strip heights based on area requirements
    # 4. Arrange apartments horizontally within each strip
    # 5. Create core (circulation hallway) at boundary between strips
    # 6. Extend apartments into core area and subtract overlap
    # 7. Create terrace geometries (if specified)
    # 8. Rotate all geometries back to original coordinate system
    #
    # Parameters:
    # - ps_planta: Floor polygon (must be rectangular, single region)
    # - vec_sup_deptos: Area for each apartment type
    # - vec_num_deptos: Count for each apartment type
    # - ancho_pasillo: Core hallway width (default 2.0m)
    # - vec_sup_terraza: Terrace area for each apartment type (optional)
    # - area_escala: Staircase area (default 25.0m²)
    # - min_ancho_escala: Minimum staircase width (default 5.0m)
    #
    # Returns: Dictionary with apartment polygons, core, terraces, and metrics


    # Normalize coordinate system: rotate floor polygon to align with axes
    # Goal: make floor rectangle axis-aligned with width (W) > height (H)
    V_planta = ps_planta.Vertices[1]

    x_cr = sum(V_planta[1:end-1, 1]) / (size(V_planta, 1) - 1)
    y_cr = sum(V_planta[1:end-1, 2]) / (size(V_planta, 1) - 1)

    edge1 = V_planta[2, :] - V_planta[1, :]
    angulo_planta = atan(edge1[2], edge1[1])

    angulo_rotacion = -angulo_planta
    cr = [x_cr, y_cr]

    ps_planta_rotada = polyShape.polyRotate(ps_planta, angulo_rotacion, cr)
    V_planta_rotada = ps_planta_rotada.Vertices[1]

    vec_x_planta = V_planta_rotada[:, 1]
    vec_y_planta = V_planta_rotada[:, 2]
    W_aux = maximum(vec_x_planta) - minimum(vec_x_planta)
    H_aux = maximum(vec_y_planta) - minimum(vec_y_planta)

    if H_aux > W_aux
        angulo_rotacion += π/2
        ps_planta_rotada = polyShape.polyRotate(ps_planta, angulo_rotacion, cr)
        V_planta_rotada = ps_planta_rotada.Vertices[1]

        vec_x_planta = V_planta_rotada[:, 1]
        vec_y_planta = V_planta_rotada[:, 2]
        W = maximum(vec_x_planta) - minimum(vec_x_planta)
        H = maximum(vec_y_planta) - minimum(vec_y_planta)
    else
        W = W_aux
        H = H_aux
    end

    num_tipo_deptos = length(vec_sup_deptos)
    deptos_total = sum(vec_num_deptos)

    # Distribute apartments to north and south strips
    # Strategy: balance areas between strips, sort by size (largest first)
    # All apartments of same type go to same strip when possible
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

    # Calculate strip heights
    # Each strip height = total area in strip / floor width
    # Scale down if combined height exceeds floor height
    alto_norte_requerido = area_norte / W
    alto_sur_requerido = area_sur / W

    if alto_norte_requerido + alto_sur_requerido > H
        scale_factor = H / (alto_norte_requerido + alto_sur_requerido)
        alto_norte = alto_norte_requerido * scale_factor
        alto_sur = alto_sur_requerido * scale_factor
    else
        alto_norte = alto_norte_requerido
        alto_sur = alto_sur_requerido
    end

    ancho_total_norte = sum(apt[1] for apt in deptos_franja_norte) / alto_norte
    ancho_total_sur = sum(apt[1] for apt in deptos_franja_sur) / alto_sur

    holgura_ancho_norte = W - ancho_total_norte
    holgura_ancho_sur = W - ancho_total_sur
    holgura_total = holgura_ancho_norte * alto_norte + holgura_ancho_sur * alto_sur

    x_min_planta = minimum(vec_x_planta)
    y_min_planta = minimum(vec_y_planta)

    holgura_alto = H - (alto_norte + alto_sur)
    y_min_planta += holgura_alto/2

    # Arrange apartments horizontally within each strip
    # North: 2nd largest, middle units, largest (for balance)
    # South: first half, stair (center), second half
    deptos_ordenados_norte = Tuple{Float64, Int}[]
    deptos_ordenados_sur = Tuple{Float64, Int}[]

    num_deptos_norte = length(deptos_franja_norte)
    num_deptos_sur_con_escala = length(deptos_franja_sur)
    num_deptos_sur = num_deptos_sur_con_escala - 1

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
            push!(depto_order_norte, (depto[1], depto[2]))
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

    # Create apartment geometries
    # Apartments are created in normalized coordinate system, then rotated back
    y_norte_base = y_min_planta + alto_sur
    vec_x_ini_norte, vec_x_fin_norte, vec_ancho_deptos_norte, _ = genera_deptos_franja(deptos_ordenados_norte, x_min_planta, y_norte_base, alto_norte)
    vec_x_ini_sur, vec_x_fin_sur, vec_ancho_deptos_sur, vec_tipo_deptos_sur = genera_deptos_franja(deptos_ordenados_sur, x_min_planta, y_min_planta, alto_sur)

    # Define core (circulation hallway) position
    # Core runs horizontally between the two strips at their boundary
    # Starts at min of first apartment east walls, ends at max of last apartment west walls
    x_east_wall_first_norte = vec_x_fin_norte[1]
    x_east_wall_first_sur = vec_x_fin_sur[1]
    x_ini_pasillo = min(x_east_wall_first_norte, x_east_wall_first_sur)

    x_west_wall_last_norte = vec_x_ini_norte[end]
    x_west_wall_last_sur = vec_x_ini_sur[end]
    x_fin_pasillo = max(x_west_wall_last_norte, x_west_wall_last_sur)

    largo_pasillo = x_fin_pasillo - x_ini_pasillo
    y_pasillo = y_min_planta + alto_sur - ancho_pasillo / 2

    ps_pasillo_aux = polyShape.polyBox(x_ini_pasillo, y_pasillo, largo_pasillo, ancho_pasillo, 0.0)
    ps_pasillo = polyShape.polyRotate(ps_pasillo_aux, -angulo_rotacion, cr)

    # Extend apartments into core area and subtract core overlap
    vec_ps_deptos_norte, vec_extension_alto_deptos_norte = extiende_deptos_interseccion_pasillo(vec_x_ini_norte, vec_x_fin_norte, vec_ancho_deptos_norte, y_norte_base, alto_norte, x_ini_pasillo, x_fin_pasillo, y_pasillo, ancho_pasillo, angulo_rotacion, cr, :norte)

    vec_ps_deptos_sur, vec_extension_alto_deptos_sur = extiende_deptos_interseccion_pasillo(vec_x_ini_sur, vec_x_fin_sur, vec_ancho_deptos_sur, y_min_planta, alto_sur, x_ini_pasillo, x_fin_pasillo, y_pasillo, ancho_pasillo, angulo_rotacion, cr, :sur)

    # Create terrace geometries (if specified)
    vec_terrazas_norte = PolyShape[]
    vec_terrazas_sur = PolyShape[]

    if !isempty(vec_sup_terraza)
        y_terrace_base_norte = [y_norte_base + alto_norte + vec_extension_alto_deptos_norte[i] for i in eachindex(deptos_ordenados_norte)]
        vec_terrazas_norte = genera_terrazas_franja(deptos_ordenados_norte, vec_sup_terraza, vec_ancho_deptos_norte, vec_x_ini_norte, y_terrace_base_norte, angulo_rotacion, cr, :norte)

        y_terrace_base_sur = [y_min_planta - vec_extension_alto_deptos_sur[i] for i in eachindex(deptos_ordenados_sur)]
        vec_terrazas_sur = genera_terrazas_franja(deptos_ordenados_sur, vec_sup_terraza, vec_ancho_deptos_sur, vec_x_ini_sur, y_terrace_base_sur, angulo_rotacion, cr, :sur)
    end

    # Extract staircase information
    id_escala = findfirst(t -> t == -1, vec_tipo_deptos_sur)
    ps_escala = vec_ps_deptos_sur[id_escala]
    ancho_escala = vec_ancho_deptos_sur[id_escala]

    # Package results
    results = Dict(
        "feasible" => true,
        "status" => "LOCALLY_SOLVED",
        "n_apts_norte" => num_deptos_norte,
        "n_apts_sur" => num_deptos_sur,
        "vec_sup_deptos_norte" => [apt[1] for apt in deptos_ordenados_norte],
        "vec_sup_deptos_sur" => [apt[1] for apt in deptos_ordenados_sur if apt[2] != -1],
        "height_norte" => round(alto_norte, digits=2),
        "height_sur" => round(alto_sur, digits=2),
        "holgura_ancho_norte" => round(holgura_ancho_norte, digits=2),
        "holgura_ancho_sur" => round(holgura_ancho_sur, digits=2),
        "holgura_total" => round(holgura_total, digits=2),
        "floor_width" => W,
        "floor_height" => H,
        "ancho_pasillo" => ancho_pasillo,
        "largo_pasillo" => largo_pasillo,
        "ps_pasillo" => ps_pasillo,
        "ps_escala" => ps_escala,
        "ancho_escala" => round(ancho_escala, digits=2),
        "alto_escala" => round(alto_sur, digits=2),
        "area_escala" => round(area_escala, digits=2),
        "vec_polyshapes_all" => vcat(vec_ps_deptos_norte, vec_ps_deptos_sur),
        "vec_terrazas_all" => vcat(vec_terrazas_norte, vec_terrazas_sur)
    )


    return results
end
