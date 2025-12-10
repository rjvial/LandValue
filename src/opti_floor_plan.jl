get_tipo(t::Tuple{Float64, Int}) = t[2]
get_tipo(t::Tuple{Float64, Int, Int}) = t[2]

function reordena_deptos_grandes_en_extremos(mat_deptos::Matrix{Float64}, vec_tipos::Vector{String},
                                              vec_terrazas_areas::Vector{Float64}, vec_en_primer_piso::Vector{Bool})
    n = size(mat_deptos, 1)
    if n <= 2
        return mat_deptos, vec_tipos, vec_terrazas_areas, vec_en_primer_piso
    end

    areas = mat_deptos[:, 1]
    sorted_indices = sortperm(areas, rev=true)

    new_order = Vector{Int}(undef, n)
    left = 1
    right = n
    for (i, idx) in enumerate(sorted_indices)
        if i % 2 == 1
            new_order[left] = idx
            left += 1
        else
            new_order[right] = idx
            right -= 1
        end
    end

    mat_deptos_reordered = mat_deptos[new_order, :]
    vec_tipos_reordered = vec_tipos[new_order]
    vec_terrazas_areas_reordered = vec_terrazas_areas[new_order]
    vec_en_primer_piso_reordered = vec_en_primer_piso[new_order]

    return mat_deptos_reordered, vec_tipos_reordered, vec_terrazas_areas_reordered, vec_en_primer_piso_reordered
end

# ══════════════════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ══════════════════════════════════════════════════════════════════════════════════

# ──────────────────────────────────────────────────────────────────────────────────
# Geometry generation helpers
# ──────────────────────────────────────────────────────────────────────────────────

# Generates apartment geometries along one strip using pre-calculated dimensions
function genera_deptos_franja(mat_deptos::Matrix{Float64}, coord_min_planta::Float64,
            is_vertical::Bool, coord_base::Float64, franja::Symbol,
            vec_tipos::Vector{String}=String[])

    vec_coord_ini = Float64[]
    vec_coord_fin = Float64[]
    vec_dimension1_deptos = Float64[]
    vec_dimension2_deptos = Float64[]
    vec_tipo_deptos = Int[]
    vec_tipo_strings = String[]

    coord_current = coord_min_planta

    for i in 1:size(mat_deptos, 1)
        ancho_interior = mat_deptos[i, 2]
        profundidad_interior = mat_deptos[i, 3]

        push!(vec_coord_ini, coord_current)
        push!(vec_coord_fin, coord_current + ancho_interior)
        push!(vec_dimension1_deptos, profundidad_interior)
        push!(vec_dimension2_deptos, ancho_interior)
        push!(vec_tipo_deptos, 0)

        if !isempty(vec_tipos) && i <= length(vec_tipos)
            push!(vec_tipo_strings, vec_tipos[i])
        else
            push!(vec_tipo_strings, "unknown")
        end

        coord_current += ancho_interior
    end

    vec_ps_deptos_normalizado = [polyBoxAligned(coord_base, vec_coord_ini[i], vec_dimension1_deptos[i], vec_dimension2_deptos[i], franja, is_vertical) for i in eachindex(vec_coord_ini)]

    return vec_coord_ini, vec_coord_fin, vec_dimension1_deptos, vec_dimension2_deptos, vec_tipo_deptos, vec_ps_deptos_normalizado, vec_tipo_strings
end

# Extends apartments with corridor space overlap for both strips, then subtracts corridor geometry
# Respects max_constructibilidad constraint for entire building: sum(interior_areas) + 0.5 * sum(terrace_areas)
function extiende_deptos_con_interseccion_pasillo(vec_profundidad_terraza_strip1, vec_profundidad_terraza_strip2,
            vec_coord_ini1::Vector{Float64}, vec_coord_fin1::Vector{Float64},
            vec_coord_ini2::Vector{Float64}, vec_coord_fin2::Vector{Float64},
            coord_base::Float64, ps_pasillo::PolyShape, franja1::Symbol, franja2::Symbol, is_vertical::Bool,
            H_s_strip1, H_s_strip2,
            vec_terrazas_areas_strip1, vec_terrazas_areas_strip2,
            vec_terrazas_areas_pp_strip1, vec_terrazas_areas_pp_strip2,
            vec_en_primer_piso_strip1::Vector{Bool}, vec_en_primer_piso_strip2::Vector{Bool},
            num_pisos_superiores::Int,
            max_constructibilidad::Float64,
            flag_dfl2::Bool = false,
            flag_vivienda_economica::Bool = false)

    vec_dimension2_strip1 = [vec_coord_fin1[i] - vec_coord_ini1[i] for i in eachindex(vec_coord_ini1)]
    vec_dimension2_strip2 = [vec_coord_fin2[i] - vec_coord_ini2[i] for i in eachindex(vec_coord_ini2)]

    vec_dimension1_strip1 = [H_s_strip1 - vec_profundidad_terraza_strip1[i] for i in eachindex(vec_coord_ini1)]
    vec_dimension1_strip2 = [H_s_strip2 - vec_profundidad_terraza_strip2[i] for i in eachindex(vec_coord_ini2)]

    max_profundidad_interior = 7.5
    n1 = length(vec_dimension1_strip1)
    for i in 2:(n1-1)
        if vec_dimension1_strip1[i] > max_profundidad_interior
            vec_dimension1_strip1[i] = max_profundidad_interior
        end
    end
    n2 = length(vec_dimension1_strip2)
    for i in 2:(n2-1)
        if vec_dimension1_strip2[i] > max_profundidad_interior
            vec_dimension1_strip2[i] = max_profundidad_interior
        end
    end

    ps_deptos_extendidos_strip1 = PolyShape[]
    ps_deptos_extendidos_strip2 = PolyShape[]
    for i in eachindex(vec_coord_ini1)
        extended_local_poly = polyBoxAligned(coord_base, vec_coord_ini1[i], vec_dimension1_strip1[i], vec_dimension2_strip1[i], franja1, is_vertical)
        extended_poly_final = polyShape.polyDifference(extended_local_poly, ps_pasillo)
        push!(ps_deptos_extendidos_strip1, extended_poly_final)
    end

    for i in eachindex(vec_coord_ini2)
        extended_local_poly = polyBoxAligned(coord_base, vec_coord_ini2[i], vec_dimension1_strip2[i], vec_dimension2_strip2[i], franja2, is_vertical)
        extended_poly_final = polyShape.polyDifference(extended_local_poly, ps_pasillo)
        push!(ps_deptos_extendidos_strip2, extended_poly_final)
    end


    cond = true
    cont = 0
    while cond
        cont += 1

        interior_area_piso_superior = sum(polyShape.polyArea.(ps_deptos_extendidos_strip1)) + sum(polyShape.polyArea.(ps_deptos_extendidos_strip2))
        terrace_area_piso_superior = sum(vec_terrazas_areas_strip1) + sum(vec_terrazas_areas_strip2)

        interior_area_primer_piso = sum(polyShape.polyArea.(ps_deptos_extendidos_strip1) .* vec_en_primer_piso_strip1) +
                                    sum(polyShape.polyArea.(ps_deptos_extendidos_strip2) .* vec_en_primer_piso_strip2)
        terrace_area_primer_piso = sum(vec_terrazas_areas_pp_strip1) + sum(vec_terrazas_areas_pp_strip2)

        constructibilidad_piso_superior = interior_area_piso_superior + 0.5 * terrace_area_piso_superior
        constructibilidad_primer_piso = interior_area_primer_piso + 0.5 * terrace_area_primer_piso
        constructibilidad_edificio_max = num_pisos_superiores * constructibilidad_piso_superior + constructibilidad_primer_piso

        total_interior_area_edificio_max = num_pisos_superiores * interior_area_piso_superior + interior_area_primer_piso

        println("max_constructibilidad: $(round(max_constructibilidad, digits=2))")
        println("constructibilidad_piso_superior: $(round(constructibilidad_piso_superior, digits=2))")
        println("constructibilidad_primer_piso: $(round(constructibilidad_primer_piso, digits=2))")
        println("constructibilidad_edificio_max: $(round(constructibilidad_edificio_max, digits=2)) ($(num_pisos_superiores) pisos sup + 1 primer piso)")

        if (constructibilidad_edificio_max - max_constructibilidad) > 10
            excess = constructibilidad_edificio_max - max_constructibilidad
            reduction_factor = excess / total_interior_area_edificio_max
            vec_dimension1_strip1 = vec_dimension1_strip1 .* (1.0 - reduction_factor)
            vec_dimension1_strip2 = vec_dimension1_strip2 .* (1.0 - reduction_factor)
            ps_deptos_extendidos_strip1 = PolyShape[]
            ps_deptos_extendidos_strip2 = PolyShape[]
        else
            cond = false
        end

        if flag_dfl2 || flag_vivienda_economica
            for i in eachindex(vec_coord_ini1)
                util_area_i = polyShape.polyArea(ps_deptos_extendidos_strip1[i]) + 0.5 * vec_terrazas_areas_strip1[i]
                if util_area_i > 140
                    vec_dimension1_strip1[i] = vec_dimension1_strip1[i] * 140 / util_area_i 
                end
            end

            for i in eachindex(vec_coord_ini2)
                util_area_i = polyShape.polyArea(ps_deptos_extendidos_strip2[i]) + 0.5 * vec_terrazas_areas_strip2[i]
                if util_area_i > 140
                    vec_dimension1_strip2[i] = vec_dimension1_strip2[i] * 140 / util_area_i 
                end
            end
        end

        ps_deptos_extendidos_strip1 = PolyShape[]
        ps_deptos_extendidos_strip2 = PolyShape[]
        for i in eachindex(vec_coord_ini1)
            extended_local_poly = polyBoxAligned(coord_base, vec_coord_ini1[i], vec_dimension1_strip1[i], vec_dimension2_strip1[i], franja1, is_vertical)
            extended_poly_final = polyShape.polyDifference(extended_local_poly, ps_pasillo)
            push!(ps_deptos_extendidos_strip1, extended_poly_final)
        end

        for i in eachindex(vec_coord_ini2)
            extended_local_poly = polyBoxAligned(coord_base, vec_coord_ini2[i], vec_dimension1_strip2[i], vec_dimension2_strip2[i], franja2, is_vertical)
            extended_poly_final = polyShape.polyDifference(extended_local_poly, ps_pasillo)
            push!(ps_deptos_extendidos_strip2, extended_poly_final)
        end

        if cont >= 2
            cond = false
        end
    end

    return ps_deptos_extendidos_strip1, vec_dimension1_strip1, ps_deptos_extendidos_strip2, vec_dimension1_strip2
end

# ──────────────────────────────────────────────────────────────────────────────────
# Geometric transformation helpers
# ──────────────────────────────────────────────────────────────────────────────────

# Rotates vector of polyshapes back to original orientation around center point
function rota_polyshapes(vec_polyshapes::Vector{PolyShape}, angulo_rotacion::Float64, cr::Vector{Float64})
    return [polyShape.polyArea(ps) > 0.0 ? polyShape.polyRotate(ps, -angulo_rotacion, cr) : ps for ps in vec_polyshapes]
end

# Creates axis-aligned box with franja-aware positioning (vertical: X-axis, horizontal: Y-axis)
function polyBoxAligned(base1::Float64, base2::Float64, profundidad_depto::Float64, ancho_depto::Float64, franja::Symbol, is_vertical::Bool)
    if is_vertical
        offset = (franja == :este) ? base1 : base1 - profundidad_depto
        return polyShape.polyBox(offset, base2, profundidad_depto, ancho_depto, 0.0)
    else
        offset = (franja == :norte) ? base1 : base1 - profundidad_depto
        return polyShape.polyBox(base2, offset, ancho_depto, profundidad_depto, 0.0)
    end
end

# Processes terraces for both strips including generation, verification, and correction
function genera_terrazas_ambas_franjas(vec_terrazas_areas_strip1, vec_terrazas_areas_strip2,
                                        vec_dimension1_franja1_deptos, vec_dimension1_franja2_deptos,
                                        vec_dimension2_franja1_deptos, vec_dimension2_franja2_deptos,
                                        vec_coord_ini1, vec_coord_ini2,
                                        coord_base, franja1, franja2,
                                        is_vertical)

    vec_terrazas_strip1 = PolyShape[]
    vec_terrazas_strip2 = PolyShape[]

    min_profundidad_terraza = 1.5

    if is_vertical
        for i in eachindex(vec_terrazas_areas_strip1)
            profundidad_terrazas_areas_strip1 = max(min_profundidad_terraza, vec_terrazas_areas_strip1[i] / vec_dimension2_franja1_deptos[i])
            ancho_terrazas_areas_strip1 = vec_terrazas_areas_strip1[i] / profundidad_terrazas_areas_strip1
            base1 = coord_base + vec_dimension1_franja1_deptos[i]
            base2 = vec_coord_ini1[i] + vec_dimension2_franja1_deptos[i] / 2 - ancho_terrazas_areas_strip1 / 2
            ps_terrace_franja1 = polyShape.polyBox(base1, base2, profundidad_terrazas_areas_strip1, ancho_terrazas_areas_strip1, 0.0)
            push!(vec_terrazas_strip1, ps_terrace_franja1)
        end
        for i in eachindex(vec_terrazas_areas_strip2)
            profundidad_terrazas_areas_strip2 = max(min_profundidad_terraza, vec_terrazas_areas_strip2[i] / vec_dimension2_franja2_deptos[i])
            ancho_terrazas_areas_strip2 = vec_terrazas_areas_strip2[i] / profundidad_terrazas_areas_strip2
            base1 = coord_base - vec_dimension1_franja2_deptos[i]
            base2 = vec_coord_ini2[i] + vec_dimension2_franja2_deptos[i] / 2 - ancho_terrazas_areas_strip2 / 2
            ps_terrace_franja2 = polyShape.polyBox(base1 - profundidad_terrazas_areas_strip2, base2, profundidad_terrazas_areas_strip2, ancho_terrazas_areas_strip2, 0.0)
            push!(vec_terrazas_strip2, ps_terrace_franja2)
        end
    else
        for i in eachindex(vec_terrazas_areas_strip1)
            profundidad_terrazas_areas_strip1 = max(min_profundidad_terraza, vec_terrazas_areas_strip1[i] / vec_dimension2_franja1_deptos[i])
            ancho_terrazas_areas_strip1 = vec_terrazas_areas_strip1[i] / profundidad_terrazas_areas_strip1
            base1 = coord_base + vec_dimension1_franja1_deptos[i]
            base2 = vec_coord_ini1[i] + vec_dimension2_franja1_deptos[i] / 2 - ancho_terrazas_areas_strip1 / 2
            ps_terrace_franja1 = polyShape.polyBox(base2, base1, ancho_terrazas_areas_strip1, profundidad_terrazas_areas_strip1, 0.0)
            push!(vec_terrazas_strip1, ps_terrace_franja1)
        end
        for i in eachindex(vec_terrazas_areas_strip2)
            profundidad_terrazas_areas_strip2 = max(min_profundidad_terraza, vec_terrazas_areas_strip2[i] / vec_dimension2_franja2_deptos[i])
            ancho_terrazas_areas_strip2 = vec_terrazas_areas_strip2[i] / profundidad_terrazas_areas_strip2
            base1 = coord_base - vec_dimension1_franja2_deptos[i]
            base2 = vec_coord_ini2[i] + vec_dimension2_franja2_deptos[i] / 2 - ancho_terrazas_areas_strip2 / 2
            ps_terrace_franja2 = polyShape.polyBox(base2, base1 - profundidad_terrazas_areas_strip2, ancho_terrazas_areas_strip2, profundidad_terrazas_areas_strip2, 0.0)
            push!(vec_terrazas_strip2, ps_terrace_franja2)
        end
    end
    
    return vec_terrazas_strip1, vec_terrazas_strip2
end

# ──────────────────────────────────────────────────────────────────────────────────
# Corridor and results packaging helpers
# ──────────────────────────────────────────────────────────────────────────────────

function analiza_forma_apartamentos(vec_apartamentos1::Vector{PolyShape}, vec_apartamentos2::Vector{PolyShape})
    max_deviation = 0.0

    for vec_apts in [vec_apartamentos1, vec_apartamentos2]
        for ps in vec_apts
            min_x = minimum([minimum(region[:, 1]) for region in ps.Vertices])
            max_x = maximum([maximum(region[:, 1]) for region in ps.Vertices])
            min_y = minimum([minimum(region[:, 2]) for region in ps.Vertices])
            max_y = maximum([maximum(region[:, 2]) for region in ps.Vertices])

            width = max_x - min_x
            height = max_y - min_y
            ratio = width > 0.0 ? height / width : 0.0

            deviation = abs(1.0 - ratio)
            max_deviation = max(max_deviation, deviation)
        end
    end

    return max_deviation
end

# Computes corridor geometry spanning both strips based on apartment coordinates
function calcula_geometria_pasillo(vec_coord_fin1::Vector{Float64}, vec_coord_fin2::Vector{Float64},
                    vec_coord_ini1::Vector{Float64}, vec_coord_ini2::Vector{Float64}, coord_base::Float64,
                    profundidad_pasillo::Float64, is_vertical::Bool, W::Float64, H::Float64, coord_min::Float64,
                    min_ancho_pasillo::Float64, vec_tipo_deptos1::Vector{Int},
                    vec_tipo_deptos2::Vector{Int})

    num_deptos_franja1 = count(t -> t != -1, vec_tipo_deptos1)
    num_deptos_franja2 = count(t -> t != -1, vec_tipo_deptos2)
    num_deptos_total = num_deptos_franja1 + num_deptos_franja2

    if (isempty(vec_coord_fin1) || isempty(vec_coord_ini1)) && (isempty(vec_coord_fin2) || isempty(vec_coord_ini2))
        ps_pasillo = polyShape.polyBox(0.0, 0.0, 0.0, 0.0, 0.0)
        return 0.0, 0.0, 0.0, ps_pasillo
    end

    if !isempty(vec_coord_fin1) && !isempty(vec_coord_fin2) && !isempty(vec_coord_ini1) && !isempty(vec_coord_ini2)
        coord_ini_pasillo = min(vec_coord_fin1[1], vec_coord_fin2[1])
        coord_fin_pasillo = max(vec_coord_ini1[end], vec_coord_ini2[end])
    elseif !isempty(vec_coord_fin1) && !isempty(vec_coord_ini1)
        coord_ini_pasillo = vec_coord_fin1[1]
        coord_fin_pasillo = vec_coord_ini1[end]
    else
        coord_ini_pasillo = vec_coord_fin2[1]
        coord_fin_pasillo = vec_coord_ini2[end]
    end
    ancho_pasillo = coord_fin_pasillo - coord_ini_pasillo

    if ancho_pasillo < min_ancho_pasillo
        centro_pasillo = (coord_ini_pasillo + coord_fin_pasillo) / 2
        coord_ini_pasillo = centro_pasillo - min_ancho_pasillo / 2
        coord_fin_pasillo = centro_pasillo + min_ancho_pasillo / 2
        ancho_pasillo = min_ancho_pasillo
    end

    dimension_planta = is_vertical ? H : W
    centro_planta = coord_min + dimension_planta / 2

    if num_deptos_total == 2
        coord_ini_pasillo = centro_planta - ancho_pasillo / 2
        coord_fin_pasillo = centro_planta + ancho_pasillo / 2
    else
        if centro_planta < coord_ini_pasillo
            coord_ini_pasillo = centro_planta
        elseif centro_planta > coord_fin_pasillo
            coord_fin_pasillo = centro_planta
        end
    end

    ancho_pasillo = coord_fin_pasillo - coord_ini_pasillo

    coord_pasillo = coord_base - profundidad_pasillo / 2

    if is_vertical
        ps_pasillo = polyShape.polyBox(coord_pasillo, coord_ini_pasillo, profundidad_pasillo, ancho_pasillo, 0.0)
        x_centroide = coord_base
        y_centroide = (coord_ini_pasillo + coord_fin_pasillo) / 2
    else
        ps_pasillo = polyShape.polyBox(coord_ini_pasillo, coord_pasillo, ancho_pasillo, profundidad_pasillo, 0.0)
        x_centroide = (coord_ini_pasillo + coord_fin_pasillo) / 2
        y_centroide = coord_base
    end

    profundidad_nucleo = 2.0 + .75
    ancho_nucleo_box = 5.0

    if !isempty(vec_coord_ini1) && !isempty(vec_coord_fin1)
        coord_centro_strip1 = (vec_coord_ini1[1] + vec_coord_fin1[end]) / 2

        if is_vertical
            ps_nucleo1 = polyShape.polyBox(coord_base, coord_centro_strip1 - ancho_nucleo_box / 2, profundidad_nucleo, ancho_nucleo_box, 0.0)
        else
            ps_nucleo1 = polyShape.polyBox(coord_centro_strip1 - ancho_nucleo_box / 2, coord_base, ancho_nucleo_box, profundidad_nucleo, 0.0)
        end
        ps_pasillo = polyShape.polyUnion(ps_pasillo, ps_nucleo1)
    end

    if !isempty(vec_coord_ini2) && !isempty(vec_coord_fin2)
        coord_centro_strip2 = (vec_coord_ini2[1] + vec_coord_fin2[end]) / 2

        if is_vertical
            ps_nucleo2 = polyShape.polyBox(coord_base - profundidad_nucleo, coord_centro_strip2 - ancho_nucleo_box / 2, profundidad_nucleo, ancho_nucleo_box, 0.0)
        else
            ps_nucleo2 = polyShape.polyBox(coord_centro_strip2 - ancho_nucleo_box / 2, coord_base - profundidad_nucleo, ancho_nucleo_box, profundidad_nucleo, 0.0)
        end
        ps_pasillo = polyShape.polyUnion(ps_pasillo, ps_nucleo2)
    end

    return ancho_pasillo, ps_pasillo
end

function calcula_orientaciones_apartamentos(vec_ps_deptos_all::Vector{PolyShape},
                                           ps_union_deptos::PolyShape,
                                           ps_area_comun_total::PolyShape)

    ps_union_all = polyShape.polyUnion(ps_union_deptos, ps_area_comun_total)
    ps_shrinked = polyClipper.polyOffset(ps_union_all, -0.1)

    vec_apartamentos_orientaciones = Vector{Dict}(undef, length(vec_ps_deptos_all))

    for (idx_apt, ps_apt) in enumerate(vec_ps_deptos_all)
        vec_edges, _ = polyShape.shape2vector(ps_apt)
        num_edges = length(vec_edges)

        orientation = polyShape.polyOrientation(ps_apt)

        vec_edge_angles = Vector{Float64}(undef, num_edges)
        vec_edge_exposure_angles = Vector{Float64}(undef, num_edges)
        vec_edge_total_lengths = Vector{Float64}(undef, num_edges)
        vec_edge_exterior_lengths = Vector{Float64}(undef, num_edges)

        for (idx_edge, edge) in enumerate(vec_edges)
            edge_angle = polyShape.lineAngle(edge)
            total_length = polyShape.lineLength(edge)

            exterior_segment = polyShape.polyDifference(edge, ps_shrinked)
            exterior_length_result = polyShape.lineLength(exterior_segment)
            exterior_length = isa(exterior_length_result, Number) ? Float64(exterior_length_result) : 0.0

            if orientation == 1
                exposure_angle = edge_angle - pi / 2
            else
                exposure_angle = edge_angle + pi / 2
            end

            if exposure_angle < 0.0
                exposure_angle += 2 * pi
            elseif exposure_angle >= 2 * pi
                exposure_angle -= 2 * pi
            end

            vec_edge_angles[idx_edge] = edge_angle
            vec_edge_exposure_angles[idx_edge] = exposure_angle
            vec_edge_total_lengths[idx_edge] = total_length
            vec_edge_exterior_lengths[idx_edge] = exterior_length
        end

        mean_orientation = 0.0
        total_exterior_length = sum(vec_edge_exterior_lengths)

        if total_exterior_length > 0.0
            sum_x = 0.0
            sum_y = 0.0
            for i in 1:num_edges
                if vec_edge_exterior_lengths[i] > 0.0
                    weight = vec_edge_exterior_lengths[i] / total_exterior_length
                    sum_x += weight * cos(vec_edge_exposure_angles[i])
                    sum_y += weight * sin(vec_edge_exposure_angles[i])
                end
            end
            mean_orientation = atan(sum_y, sum_x)
            if mean_orientation < 0.0
                mean_orientation += 2 * pi
            end
        end

        cardinal_direction = ""
        if mean_orientation > 0.0
            angle_deg = rad2deg(mean_orientation)
            if angle_deg >= 345.0 || angle_deg < 15.0
                cardinal_direction = "Or"
            elseif angle_deg >= 15.0 && angle_deg < 75.0
                cardinal_direction = "N-Or"
            elseif angle_deg >= 75.0 && angle_deg < 105.0
                cardinal_direction = "N"
            elseif angle_deg >= 105.0 && angle_deg < 165.0
                cardinal_direction = "N-Po"
            elseif angle_deg >= 165.0 && angle_deg < 195.0
                cardinal_direction = "Po"
            elseif angle_deg >= 195.0 && angle_deg < 255.0
                cardinal_direction = "S-Po"
            elseif angle_deg >= 255.0 && angle_deg < 285.0
                cardinal_direction = "S"
            elseif angle_deg >= 285.0 && angle_deg < 345.0
                cardinal_direction = "S-Or"
            end
        end

        vec_apartamentos_orientaciones[idx_apt] = Dict(
            "vec_edges" => vec_edges,
            "vec_edge_angles" => vec_edge_angles,
            "vec_edge_exposure_angles" => vec_edge_exposure_angles,
            "vec_edge_total_lengths" => vec_edge_total_lengths,
            "vec_edge_exterior_lengths" => vec_edge_exterior_lengths,
            "mean_orientation" => mean_orientation,
            "cardinal_direction" => cardinal_direction
        )
    end

    return vec_apartamentos_orientaciones
end

# Packages all computed geometries and parameters into results dictionary
function empaqueta_resultados(dimension1::Float64, dimension2::Float64,
                    W::Float64, H::Float64, profundidad_pasillo::Float64, ancho_pasillo::Float64, ps_pasillo::PolyShape,
                    vec_ps_deptos_franja_1::Vector{PolyShape}, vec_ps_deptos_franja_2::Vector{PolyShape},
                    vec_terrazas1::Vector{PolyShape}, vec_terrazas2::Vector{PolyShape}, is_vertical::Bool,
                    ps_planta::PolyShape, vec_tipo_strings1::Vector{String}=String[], vec_tipo_strings2::Vector{String}=String[])
    if is_vertical
        dim_key = "width"
    else
        dim_key = "height"
    end

    result = Dict(
        "feasible" => true,
        "status" => "LOCALLY_SOLVED",
        "$(dim_key)_1" => round(dimension1, digits=2),
        "$(dim_key)_2" => round(dimension2, digits=2),
        "floor_width" => W,
        "floor_height" => H,
        "profundidad_pasillo" => profundidad_pasillo,
        "ancho_pasillo" => ancho_pasillo,
        "ps_pasillo" => ps_pasillo
    )

    vec_orientaciones1 = fill(1, length(vec_ps_deptos_franja_1))
    vec_orientaciones2 = fill(2, length(vec_ps_deptos_franja_2))

    result["vec_ps_deptos_all"] = vcat(vec_ps_deptos_franja_1, vec_ps_deptos_franja_2)
    result["vec_ps_terrazas_all"] = vcat(vec_terrazas1, vec_terrazas2)
    result["vec_orientaciones_all"] = vcat(vec_orientaciones1, vec_orientaciones2)
    result["vec_tipos_all"] = vcat(vec_tipo_strings1, vec_tipo_strings2)
    result["vec_strips"] = vcat(fill(1, length(vec_tipo_strings1)), fill(2, length(vec_tipo_strings2)))

    shape_analysis = analiza_forma_apartamentos(vec_ps_deptos_franja_1, vec_ps_deptos_franja_2)

    result["max_depto_square_deviation"] = round(shape_analysis, digits=3)

    valid_terrazas = [ps for ps in result["vec_ps_terrazas_all"] if polyShape.polyArea(ps) > 0.0]
    all_shapes = vcat([ps_pasillo], result["vec_ps_deptos_all"], valid_terrazas)
    ps_union_all = reduce((acc, ps) -> polyShape.polyUnion(acc, ps), all_shapes)

    ps_outbound = polyShape.polyDifference(ps_union_all, ps_planta)
    area_outbound = polyShape.polyArea(ps_outbound)
    result["area_outbound"] = round(area_outbound, digits=2)

    return result
end

# ──────────────────────────────────────────────────────────────────────────────────
# High-level computation functions
# ──────────────────────────────────────────────────────────────────────────────────

# Main floor plan optimization function: distributes apartments in two strips with corridor and terraces
function genera_layout(dict_edificio_deptos, max_constructibilidad::Float64, num_pisos_superiores::Int;
                        profundidad_pasillo::Float64 = 1.5,
                        min_ancho_pasillo::Float64 = 0.0,
                        flag_dfl2::Bool = false,
                        flag_vivienda_economica::Bool = false)

    best_layout = dict_edificio_deptos["best_layout"]
    is_vertical = (best_layout == 2)

    ps_planta_normalizado = dict_edificio_deptos["ps_planta_normalizado"]

    V_planta_normalizado = ps_planta_normalizado.Vertices[1]
    vec_x_planta = V_planta_normalizado[:, 1]
    vec_y_planta = V_planta_normalizado[:, 2]
    W = maximum(vec_x_planta) - minimum(vec_x_planta)
    H = maximum(vec_y_planta) - minimum(vec_y_planta)

    # ══════════════════════════════════════════════════════════════════════════════════
    # MAIN EXECUTION LOGIC
    # ══════════════════════════════════════════════════════════════════════════════════

    df_deptos_resumen = combine(
        groupby(dict_edificio_deptos["df_deptos"], [:strip, :tipo, :sup_interior, :sup_terraza, :ancho_interior, :profundidad_interior, :num_unidades_por_piso_superior, :num_unidades_primer_piso]),
        :num_unidades_edificio => sum => :num_unidades_edificio)

    # ──────────────────────────────────────────────────────────────────────────────────
    # Stage 2: Strip geometry computation
    # ──────────────────────────────────────────────────────────────────────────────────
    coord_min_x = minimum(vec_x_planta)
    coord_min_y = minimum(vec_y_planta)

    H_s_strip1 = dict_edificio_deptos["strip_1_H_s"]
    H_s_strip2 = dict_edificio_deptos["strip_2_H_s"]

    if is_vertical
        coord_base = coord_min_x + H_s_strip2
        coord_disponible = H
        coord_min = coord_min_y
        franja1 = :este
        franja2 = :oeste
        dimension_depto1 = H_s_strip1
        dimension_depto2 = H_s_strip2
    else
        coord_base = coord_min_y + H_s_strip2
        coord_disponible = W
        coord_min = coord_min_x
        franja1 = :norte
        franja2 = :sur
        dimension_depto1 = H_s_strip1
        dimension_depto2 = H_s_strip2
    end

    df_deptos_sorted = sort(df_deptos_resumen, [:strip, order(:tipo, by = x -> contains(string(x), "nucleo") ? 0 : 1)])

    mat_deptos_strip1 = Matrix{Float64}(undef, 0, 3)
    mat_deptos_strip2 = Matrix{Float64}(undef, 0, 3)
    vec_tipos_strip1 = String[]
    vec_tipos_strip2 = String[]
    vec_terrazas_areas_strip1 = Float64[]
    vec_terrazas_areas_strip2 = Float64[]
    vec_en_primer_piso_strip1 = Bool[]
    vec_en_primer_piso_strip2 = Bool[]
    vec_terrazas_areas_pp_strip1 = Float64[]
    vec_terrazas_areas_pp_strip2 = Float64[]

    for row in eachrow(df_deptos_sorted)
        n_repeat_superior = Int(round(row.num_unidades_por_piso_superior))
        n_repeat_primer = Int(round(row.num_unidades_primer_piso))
        for i in 1:n_repeat_superior
            en_primer_piso = i <= n_repeat_primer
            if row.strip == 1
                mat_deptos_strip1 = vcat(mat_deptos_strip1, [row.sup_interior row.ancho_interior row.profundidad_interior])
                push!(vec_tipos_strip1, string(row.tipo))
                push!(vec_terrazas_areas_strip1, row.sup_terraza)
                push!(vec_en_primer_piso_strip1, en_primer_piso)
                if en_primer_piso
                    push!(vec_terrazas_areas_pp_strip1, row.sup_terraza)
                end
            else
                mat_deptos_strip2 = vcat(mat_deptos_strip2, [row.sup_interior row.ancho_interior row.profundidad_interior])
                push!(vec_tipos_strip2, string(row.tipo))
                push!(vec_terrazas_areas_strip2, row.sup_terraza)
                push!(vec_en_primer_piso_strip2, en_primer_piso)
                if en_primer_piso
                    push!(vec_terrazas_areas_pp_strip2, row.sup_terraza)
                end
            end
        end
    end

    mat_deptos_strip1, vec_tipos_strip1, vec_terrazas_areas_strip1, vec_en_primer_piso_strip1 = reordena_deptos_grandes_en_extremos(
        mat_deptos_strip1, vec_tipos_strip1, vec_terrazas_areas_strip1, vec_en_primer_piso_strip1)
    mat_deptos_strip2, vec_tipos_strip2, vec_terrazas_areas_strip2, vec_en_primer_piso_strip2 = reordena_deptos_grandes_en_extremos(
        mat_deptos_strip2, vec_tipos_strip2, vec_terrazas_areas_strip2, vec_en_primer_piso_strip2)

    coord_min_planta = coord_min
    is_vertical = is_vertical
    coord_base = coord_base

    mat_deptos = mat_deptos_strip1
    franja = franja1
    vec_tipos = vec_tipos_strip1
    vec_coord_ini1, vec_coord_fin1, vec_dimension1_franja1_deptos, vec_dimension2_franja1_deptos, vec_tipo_deptos1,
            _, vec_tipo_strings1 = genera_deptos_franja(mat_deptos, coord_min_planta,
                                            is_vertical, coord_base, franja, vec_tipos)

    mat_deptos = mat_deptos_strip2
    franja = franja2
    vec_tipos = vec_tipos_strip2
    vec_coord_ini2, vec_coord_fin2, vec_dimension1_franja2_deptos, vec_dimension2_franja2_deptos, vec_tipo_deptos2,
            _, vec_tipo_strings2 = genera_deptos_franja(mat_deptos, coord_min_planta,
                                            is_vertical, coord_base, franja, vec_tipos)

    ancho_pasillo, ps_pasillo_normalizado = calcula_geometria_pasillo(
                                            vec_coord_fin1, vec_coord_fin2, vec_coord_ini1, vec_coord_ini2,
                                            coord_base, profundidad_pasillo, is_vertical,
                                            W, H,
                                            coord_min, min_ancho_pasillo,
                                            vec_tipo_deptos1, vec_tipo_deptos2)

    vec_profundidad_terraza_strip1 = Float64[]
    vec_profundidad_terraza_strip2 = Float64[]
    vec_ancho_terraza_strip1 = Float64[]
    vec_ancho_terraza_strip2 = Float64[]
    min_profundidad_terraza = 1.5
    if is_vertical
        for i in eachindex(vec_terrazas_areas_strip1)
            profundidad_terrazas_areas_strip1 = max(min_profundidad_terraza, vec_terrazas_areas_strip1[i] / vec_dimension2_franja1_deptos[i])
            ancho_terrazas_areas_strip1 = vec_terrazas_areas_strip1[i] / profundidad_terrazas_areas_strip1
            push!(vec_ancho_terraza_strip1, ancho_terrazas_areas_strip1)
            push!(vec_profundidad_terraza_strip1, profundidad_terrazas_areas_strip1)
        end
        for i in eachindex(vec_terrazas_areas_strip2)
            profundidad_terrazas_areas_strip2 = max(min_profundidad_terraza, vec_terrazas_areas_strip2[i] / vec_dimension2_franja2_deptos[i])
            ancho_terrazas_areas_strip2 = vec_terrazas_areas_strip2[i] / profundidad_terrazas_areas_strip2
            push!(vec_ancho_terraza_strip2, ancho_terrazas_areas_strip2)
            push!(vec_profundidad_terraza_strip2, profundidad_terrazas_areas_strip2)
        end
    else
        for i in eachindex(vec_terrazas_areas_strip1)
            profundidad_terrazas_areas_strip1 = max(min_profundidad_terraza, vec_terrazas_areas_strip1[i] / vec_dimension2_franja1_deptos[i])
            ancho_terrazas_areas_strip1 = vec_terrazas_areas_strip1[i] / profundidad_terrazas_areas_strip1
            push!(vec_ancho_terraza_strip1, ancho_terrazas_areas_strip1)
            push!(vec_profundidad_terraza_strip1, profundidad_terrazas_areas_strip1)
        end
        for i in eachindex(vec_terrazas_areas_strip2)
            profundidad_terrazas_areas_strip2 = max(min_profundidad_terraza, vec_terrazas_areas_strip2[i] / vec_dimension2_franja2_deptos[i])
            ancho_terrazas_areas_strip2 = vec_terrazas_areas_strip2[i] / profundidad_terrazas_areas_strip2
            push!(vec_ancho_terraza_strip2, ancho_terrazas_areas_strip2)
            push!(vec_profundidad_terraza_strip2, profundidad_terrazas_areas_strip2)
        end
    end

    vec_ps_deptos_franja_1_normalizado, vec_dimension1_franja1_deptos_ext,
        vec_ps_deptos_franja_2_normalizado, vec_dimension1_franja2_deptos_ext = extiende_deptos_con_interseccion_pasillo(
                                                                                    vec_profundidad_terraza_strip1, vec_profundidad_terraza_strip2,
                                                                                    vec_coord_ini1, vec_coord_fin1,
                                                                                    vec_coord_ini2, vec_coord_fin2,
                                                                                    coord_base, ps_pasillo_normalizado,
                                                                                    franja1, franja2, is_vertical,
                                                                                    H_s_strip1, H_s_strip2,
                                                                                    vec_terrazas_areas_strip1, vec_terrazas_areas_strip2,
                                                                                    vec_terrazas_areas_pp_strip1, vec_terrazas_areas_pp_strip2,
                                                                                    vec_en_primer_piso_strip1, vec_en_primer_piso_strip2,
                                                                                    num_pisos_superiores,
                                                                                    max_constructibilidad,
                                                                                    flag_dfl2,
                                                                                    flag_vivienda_economica)



    vec_terrazas_strip1, vec_terrazas_strip2 = genera_terrazas_ambas_franjas(vec_terrazas_areas_strip1, vec_terrazas_areas_strip2,
                                        vec_dimension1_franja1_deptos_ext, vec_dimension1_franja2_deptos_ext,
                                        vec_dimension2_franja1_deptos, vec_dimension2_franja2_deptos,
                                        vec_coord_ini1, vec_coord_ini2,
                                        coord_base, franja1, franja2,
                                        is_vertical)


    # ──────────────────────────────────────────────────────────────────────────────────
    # Stage 3: Results packaging (normalized coordinates)
    # ──────────────────────────────────────────────────────────────────────────────────

    ps_planta = dict_edificio_deptos["ps_planta"]

    results = empaqueta_resultados(dimension_depto1, dimension_depto2, W, H, profundidad_pasillo, ancho_pasillo, ps_pasillo_normalizado,
                                    vec_ps_deptos_franja_1_normalizado, vec_ps_deptos_franja_2_normalizado,
                                    vec_terrazas_strip1, vec_terrazas_strip2, is_vertical, ps_planta_normalizado, vec_tipo_strings1, vec_tipo_strings2)

    results["ps_planta"] = ps_planta

    delta = 0.02
    buffer_size = 0.2

    vec_ps_deptos_all = results["vec_ps_deptos_all"]
    ps_union_deptos = PolyShape[]
    if !isempty(vec_ps_deptos_all)
        buffered_apts = [polyClipper.polyOffset(ps, buffer_size) for ps in vec_ps_deptos_all]
        ps_union_deptos = reduce((acc, ps) -> polyShape.polyUnion(acc, ps), buffered_apts)
        ps_union_deptos = polyClipper.polyOffset(ps_union_deptos, delta)
        ps_union_deptos = polyClipper.polyOffset(ps_union_deptos, -buffer_size - delta)
    end
    results["ps_union_deptos"] = ps_union_deptos

    vec_ps_terrazas_all = results["vec_ps_terrazas_all"]
    valid_terrazas = [ps for ps in vec_ps_terrazas_all if polyShape.polyArea(ps) > 0.0]
    ps_union_terrazas = PolyShape[]
    if !isempty(valid_terrazas)
        buffered_terrazas = [polyClipper.polyOffset(ps, buffer_size) for ps in valid_terrazas]
        ps_union_terrazas = reduce((acc, ps) -> polyShape.polyUnion(acc, ps), buffered_terrazas)
        ps_union_terrazas = polyClipper.polyOffset(ps_union_terrazas, delta)
        ps_union_terrazas = polyClipper.polyOffset(ps_union_terrazas, -buffer_size - delta)
    end
    results["ps_union_terrazas"] = ps_union_terrazas

    ps_area_comun_total = polyClipper.polyOffset(ps_pasillo_normalizado, delta)
    ps_area_comun_total = polyClipper.polyOffset(ps_area_comun_total, -delta)
    results["ps_area_comun_total"] = ps_area_comun_total

    results_pisos_superiores = results

    df_deptos = dict_edificio_deptos["df_deptos"]
    df_deptos_con_primer_piso = filter(row -> row.num_unidades_primer_piso > 0, df_deptos)

    if nrow(df_deptos_con_primer_piso) == 0
        return results_pisos_superiores, nothing
    end

    vec_en_primer_piso_all = Bool[]
    for row in eachrow(df_deptos_sorted)
        n_repeat_superior = Int(round(row.num_unidades_por_piso_superior))
        n_repeat_primer = Int(round(row.num_unidades_primer_piso))
        for i in 1:n_repeat_superior
            push!(vec_en_primer_piso_all, i <= n_repeat_primer)
        end
    end

    vec_ps_deptos_all_superior = results_pisos_superiores["vec_ps_deptos_all"]
    vec_ps_terrazas_all_superior = results_pisos_superiores["vec_ps_terrazas_all"]
    vec_tipos_all_superior = results_pisos_superiores["vec_tipos_all"]
    vec_orientaciones_all_superior = results_pisos_superiores["vec_orientaciones_all"]
    vec_strips_all_superior = results_pisos_superiores["vec_strips"]
    ps_pasillo_superior = results_pisos_superiores["ps_pasillo"]

    indices_primer_piso = findall(vec_en_primer_piso_all)
    indices_espacios_vacios = findall(.!vec_en_primer_piso_all)

    vec_ps_deptos_all_pp = vec_ps_deptos_all_superior[indices_primer_piso]
    vec_ps_terrazas_all_pp = vec_ps_terrazas_all_superior[indices_primer_piso]
    vec_tipos_all_pp = vec_tipos_all_superior[indices_primer_piso]
    vec_orientaciones_all_pp = vec_orientaciones_all_superior[indices_primer_piso]
    vec_strips_all_pp = vec_strips_all_superior[indices_primer_piso]

    vec_ps_espacios_vacios = vec_ps_deptos_all_superior[indices_espacios_vacios]

    valid_espacios_vacios = [ps for ps in vec_ps_espacios_vacios if polyShape.polyArea(ps) > 0.0]
    ps_pasillo_pp = isempty(valid_espacios_vacios) ? ps_pasillo_superior : reduce((acc, ps) -> polyShape.polyUnion(acc, ps), valid_espacios_vacios, init=ps_pasillo_superior)

    delta_pp = 0.02
    buffer_size_pp = 0.2

    ps_union_deptos_pp = PolyShape[]
    if !isempty(vec_ps_deptos_all_pp)
        buffered_apts = [polyClipper.polyOffset(ps, buffer_size_pp) for ps in vec_ps_deptos_all_pp]
        ps_union_deptos_pp = reduce((acc, ps) -> polyShape.polyUnion(acc, ps), buffered_apts)
        ps_union_deptos_pp = polyClipper.polyOffset(ps_union_deptos_pp, delta_pp)
        ps_union_deptos_pp = polyClipper.polyOffset(ps_union_deptos_pp, -buffer_size_pp - delta_pp)
    end

    ps_union_terrazas_pp = PolyShape[]
    valid_terrazas_pp = [ps for ps in vec_ps_terrazas_all_pp if polyShape.polyArea(ps) > 0.0]
    if !isempty(valid_terrazas_pp)
        buffered_terrazas = [polyClipper.polyOffset(ps, buffer_size_pp) for ps in valid_terrazas_pp]
        ps_union_terrazas_pp = reduce((acc, ps) -> polyShape.polyUnion(acc, ps), buffered_terrazas)
        ps_union_terrazas_pp = polyClipper.polyOffset(ps_union_terrazas_pp, delta_pp)
        ps_union_terrazas_pp = polyClipper.polyOffset(ps_union_terrazas_pp, -buffer_size_pp - delta_pp)
    end

    ps_planta_primer_piso = reduce((acc, ps) -> polyShape.polyUnion(acc, ps), vec_ps_deptos_all_pp, init=ps_pasillo_pp)
    ps_planta_primer_piso = polyClipper.polyOffset(ps_planta_primer_piso, delta_pp)
    ps_planta_primer_piso = polyClipper.polyOffset(ps_planta_primer_piso, -delta_pp)

    all_ocupado = vcat([ps_pasillo_pp], vec_ps_deptos_all_pp, valid_terrazas_pp)
    ps_union_ocupado = reduce((acc, ps) -> polyShape.polyUnion(acc, ps), all_ocupado)
    ps_union_ocupado = polyClipper.polyOffset(ps_union_ocupado, delta_pp)
    ps_union_ocupado = polyClipper.polyOffset(ps_union_ocupado, -delta_pp)

    ps_area_comun = polyShape.polyDifference(ps_planta_primer_piso, ps_union_ocupado)
    area_comun = polyShape.polyArea(ps_area_comun)

    ps_area_comun_total_pp = ps_pasillo_pp
    if polyShape.polyArea(ps_area_comun) > 0.0
        ps_area_comun_total_pp = polyShape.polyUnion(ps_area_comun_total_pp, ps_area_comun)
    end
    ps_area_comun_total_pp = polyClipper.polyOffset(ps_area_comun_total_pp, delta_pp)
    ps_area_comun_total_pp = polyClipper.polyOffset(ps_area_comun_total_pp, -delta_pp)

    ps_planta_original = dict_edificio_deptos["ps_planta"]

    results_primer_piso = Dict(
        "vec_ps_deptos_all" => vec_ps_deptos_all_pp,
        "vec_ps_terrazas_all" => vec_ps_terrazas_all_pp,
        "vec_orientaciones_all" => vec_orientaciones_all_pp,
        "vec_tipos_all" => vec_tipos_all_pp,
        "vec_strips" => vec_strips_all_pp,
        "ps_area_comun" => ps_area_comun,
        "area_comun" => round(area_comun, digits=2),
        "ps_pasillo" => ps_pasillo_pp,
        "ps_planta" => ps_planta_original,
        "ps_planta_primer_piso_computed" => ps_planta_primer_piso,
        "ps_area_comun_total" => ps_area_comun_total_pp,
        "ps_union_deptos" => ps_union_deptos_pp,
        "ps_union_terrazas" => ps_union_terrazas_pp
    )

    return results_pisos_superiores, results_primer_piso
end

function opti_floor_plan(dict_edificio_deptos, max_constructibilidad::Float64, num_pisos_superiores::Int;
                        profundidad_pasillo::Float64 = 1.5,
                        min_ancho_pasillo::Float64 = 0.0)

    flag_dfl2 = get(dict_edificio_deptos, "flag_dfl2", false)
    flag_vivienda_economica = get(dict_edificio_deptos, "flag_vivienda_economica", false)

    results_pisos_superiores, results_primer_piso = genera_layout(dict_edificio_deptos, max_constructibilidad, num_pisos_superiores,
                profundidad_pasillo=profundidad_pasillo,
                min_ancho_pasillo=min_ancho_pasillo,
                flag_dfl2=flag_dfl2,
                flag_vivienda_economica=flag_vivienda_economica)

    angulo_rotacion = dict_edificio_deptos["angulo_rotacion"]
    cr = dict_edificio_deptos["cr"]

    ps_planta = results_pisos_superiores["ps_planta"]

    vec_ps_deptos_all = results_pisos_superiores["vec_ps_deptos_all"]
    vec_ps_terrazas_all = results_pisos_superiores["vec_ps_terrazas_all"]
    ps_pasillo = results_pisos_superiores["ps_pasillo"]
    ps_union_deptos = results_pisos_superiores["ps_union_deptos"]
    ps_area_comun_total = results_pisos_superiores["ps_area_comun_total"]

    vec_ps_deptos_all_rotated = rota_polyshapes(vec_ps_deptos_all, angulo_rotacion, cr)
    vec_ps_terrazas_all_rotated = rota_polyshapes(vec_ps_terrazas_all, angulo_rotacion, cr)
    ps_pasillo_rotated = polyShape.polyRotate(ps_pasillo, -angulo_rotacion, cr)
    ps_union_deptos_rotated = polyShape.polyArea(ps_union_deptos) > 0.0 ? polyShape.polyRotate(ps_union_deptos, -angulo_rotacion, cr) : ps_union_deptos
    ps_area_comun_total_rotated = polyShape.polyRotate(ps_area_comun_total, -angulo_rotacion, cr)

    results_pisos_superiores["vec_ps_deptos_all"] = vec_ps_deptos_all_rotated
    results_pisos_superiores["vec_ps_terrazas_all"] = vec_ps_terrazas_all_rotated
    results_pisos_superiores["ps_pasillo"] = ps_pasillo_rotated
    results_pisos_superiores["ps_union_deptos"] = ps_union_deptos_rotated
    results_pisos_superiores["ps_area_comun_total"] = ps_area_comun_total_rotated

    fig, ax, ax_mat = polyPlot.plotPolyshape2D(ps_planta, "green", 0.2)
    for apt_poly in vec_ps_deptos_all_rotated
        polyPlot.plotPolyshape2D(apt_poly, "red", 0.3, fig=fig, ax=ax, ax_mat=ax_mat)
    end
    polyPlot.plotPolyshape2D(ps_pasillo_rotated, "gray", 0.8, fig=fig, ax=ax, ax_mat=ax_mat)
    for ter_poly in vec_ps_terrazas_all_rotated
        if polyShape.polyArea(ter_poly) > 0.0
            polyPlot.plotPolyshape2D(ter_poly, "blue", 0.4, fig=fig, ax=ax, ax_mat=ax_mat)
        end
    end

    if !isempty(vec_ps_deptos_all_rotated) && polyShape.polyArea(ps_union_deptos_rotated) > 0.0
        vec_apartamentos_orientaciones = calcula_orientaciones_apartamentos(vec_ps_deptos_all_rotated, ps_union_deptos_rotated, ps_area_comun_total_rotated)
        results_pisos_superiores["vec_apartamentos_orientaciones"] = vec_apartamentos_orientaciones
    else
        results_pisos_superiores["vec_apartamentos_orientaciones"] = Vector{Dict}()
    end

    if !isnothing(results_primer_piso)
        vec_ps_deptos_pp = results_primer_piso["vec_ps_deptos_all"]
        vec_ps_terrazas_pp = results_primer_piso["vec_ps_terrazas_all"]
        ps_pasillo_pp = results_primer_piso["ps_pasillo"]
        ps_area_comun_total_pp = results_primer_piso["ps_area_comun_total"]
        ps_union_deptos_pp = results_primer_piso["ps_union_deptos"]

        vec_ps_deptos_pp_rotated = rota_polyshapes(vec_ps_deptos_pp, angulo_rotacion, cr)
        vec_ps_terrazas_pp_rotated = rota_polyshapes(vec_ps_terrazas_pp, angulo_rotacion, cr)
        ps_pasillo_pp_rotated = polyShape.polyRotate(ps_pasillo_pp, -angulo_rotacion, cr)
        ps_area_comun_total_pp_rotated = polyShape.polyRotate(ps_area_comun_total_pp, -angulo_rotacion, cr)
        ps_union_deptos_pp_rotated = polyShape.polyArea(ps_union_deptos_pp) > 0.0 ? polyShape.polyRotate(ps_union_deptos_pp, -angulo_rotacion, cr) : ps_union_deptos_pp

        results_primer_piso["vec_ps_deptos_all"] = vec_ps_deptos_pp_rotated
        results_primer_piso["vec_ps_terrazas_all"] = vec_ps_terrazas_pp_rotated
        results_primer_piso["ps_pasillo"] = ps_pasillo_pp_rotated
        results_primer_piso["ps_area_comun_total"] = ps_area_comun_total_pp_rotated
        results_primer_piso["ps_union_deptos"] = ps_union_deptos_pp_rotated
    end

    return Dict(
        "pisos_superiores" => results_pisos_superiores,
        "primer_piso" => results_primer_piso
    )
end

