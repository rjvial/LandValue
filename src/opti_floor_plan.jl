# Reordena departamentos: grandes en extremos, pequeños al centro
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

# Genera geometrías de departamentos a lo largo de una franja
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

# Extiende departamentos hacia el pasillo y resta geometría del corredor
function extiende_deptos_con_interseccion_pasillo(vec_profundidad_terraza_strip1, vec_profundidad_terraza_strip2,
            vec_coord_ini1::Vector{Float64}, vec_coord_fin1::Vector{Float64},
            vec_coord_ini2::Vector{Float64}, vec_coord_fin2::Vector{Float64},
            coord_base::Float64, ps_pasillo::PolyShape, ps_escalera::PolyShape, ps_ascensor::PolyShape,
            franja1::Symbol, franja2::Symbol, is_vertical::Bool,
            H_s_strip1, H_s_strip2,
            vec_terrazas_areas_strip1, vec_terrazas_areas_strip2,
            vec_terrazas_areas_pp_strip1, vec_terrazas_areas_pp_strip2,
            vec_en_primer_piso_strip1::Vector{Bool}, vec_en_primer_piso_strip2::Vector{Bool},
            num_pisos_superiores::Int,
            max_constructibilidad::Float64,
            flag_dfl2::Bool = false,
            flag_vivienda_economica::Bool = false)

    # Calcular dimensiones de departamentos
    vec_dimension2_strip1 = [vec_coord_fin1[i] - vec_coord_ini1[i] for i in eachindex(vec_coord_ini1)]
    vec_dimension2_strip2 = [vec_coord_fin2[i] - vec_coord_ini2[i] for i in eachindex(vec_coord_ini2)]
    vec_dimension1_strip1 = [H_s_strip1 - vec_profundidad_terraza_strip1[i] for i in eachindex(vec_coord_ini1)]
    vec_dimension1_strip2 = [H_s_strip2 - vec_profundidad_terraza_strip2[i] for i in eachindex(vec_coord_ini2)]

    # Extender departamentos y limitar profundidad promedio individual
    max_profundidad_interior = 7.0
    n1 = length(vec_dimension1_strip1)
    n2 = length(vec_dimension1_strip2)
    ps_deptos_extendidos_strip1 = PolyShape[]
    ps_deptos_extendidos_strip2 = PolyShape[]

    # Extender departamentos strip 1 y ajustar profundidad promedio
    for i in eachindex(vec_coord_ini1)
        extended_local_poly = polyBoxAligned(coord_base, vec_coord_ini1[i], vec_dimension1_strip1[i], vec_dimension2_strip1[i], franja1, is_vertical)
        extended_poly_final = polyShape.polyDifference(extended_local_poly, ps_pasillo)
        extended_poly_final = polyShape.polyDifference(extended_poly_final, ps_escalera)
        extended_poly_final = polyShape.polyDifference(extended_poly_final, ps_ascensor)
        if i in 2:(n1-1)
            area_depto = polyShape.polyArea(extended_poly_final)
            profundidad_promedio = area_depto / vec_dimension2_strip1[i]
            diferencia = profundidad_promedio - max_profundidad_interior
            if abs(diferencia) > 0.01
                vec_dimension1_strip1[i] = vec_dimension1_strip1[i] - diferencia
                extended_local_poly = polyBoxAligned(coord_base, vec_coord_ini1[i], vec_dimension1_strip1[i], vec_dimension2_strip1[i], franja1, is_vertical)
                extended_poly_final = polyShape.polyDifference(extended_local_poly, ps_pasillo)
                extended_poly_final = polyShape.polyDifference(extended_poly_final, ps_escalera)
                extended_poly_final = polyShape.polyDifference(extended_poly_final, ps_ascensor)
            end
        end
        push!(ps_deptos_extendidos_strip1, extended_poly_final)
    end

    # Extender departamentos strip 2 y ajustar profundidad promedio
    for i in eachindex(vec_coord_ini2)
        extended_local_poly = polyBoxAligned(coord_base, vec_coord_ini2[i], vec_dimension1_strip2[i], vec_dimension2_strip2[i], franja2, is_vertical)
        extended_poly_final = polyShape.polyDifference(extended_local_poly, ps_pasillo)
        extended_poly_final = polyShape.polyDifference(extended_poly_final, ps_escalera)
        extended_poly_final = polyShape.polyDifference(extended_poly_final, ps_ascensor)
        if i in 2:(n2-1)
            area_depto = polyShape.polyArea(extended_poly_final)
            profundidad_promedio = area_depto / vec_dimension2_strip2[i]
            diferencia = profundidad_promedio - max_profundidad_interior
            if abs(diferencia) > 0.01
                vec_dimension1_strip2[i] = vec_dimension1_strip2[i] - diferencia
                extended_local_poly = polyBoxAligned(coord_base, vec_coord_ini2[i], vec_dimension1_strip2[i], vec_dimension2_strip2[i], franja2, is_vertical)
                extended_poly_final = polyShape.polyDifference(extended_local_poly, ps_pasillo)
                extended_poly_final = polyShape.polyDifference(extended_poly_final, ps_escalera)
                extended_poly_final = polyShape.polyDifference(extended_poly_final, ps_ascensor)
            end
        end
        push!(ps_deptos_extendidos_strip2, extended_poly_final)
    end

    # Iteración para ajustar constructibilidad
    cond = true
    cont = 0
    while cond
        cont += 1

        # Calcular áreas y constructibilidad
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

        # Reducir dimensiones si excede constructibilidad máxima
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

        # Aplicar límite 140m² para DFL2/vivienda económica
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

        # Regenerar geometrías con dimensiones ajustadas
        ps_deptos_extendidos_strip1 = PolyShape[]
        ps_deptos_extendidos_strip2 = PolyShape[]
        for i in eachindex(vec_coord_ini1)
            extended_local_poly = polyBoxAligned(coord_base, vec_coord_ini1[i], vec_dimension1_strip1[i], vec_dimension2_strip1[i], franja1, is_vertical)
            extended_poly_final = polyShape.polyDifference(extended_local_poly, ps_pasillo)
            extended_poly_final = polyShape.polyDifference(extended_poly_final, ps_escalera)
            extended_poly_final = polyShape.polyDifference(extended_poly_final, ps_ascensor)
            push!(ps_deptos_extendidos_strip1, extended_poly_final)
        end
        for i in eachindex(vec_coord_ini2)
            extended_local_poly = polyBoxAligned(coord_base, vec_coord_ini2[i], vec_dimension1_strip2[i], vec_dimension2_strip2[i], franja2, is_vertical)
            extended_poly_final = polyShape.polyDifference(extended_local_poly, ps_pasillo)
            extended_poly_final = polyShape.polyDifference(extended_poly_final, ps_escalera)
            extended_poly_final = polyShape.polyDifference(extended_poly_final, ps_ascensor)
            push!(ps_deptos_extendidos_strip2, extended_poly_final)
        end

        if cont >= 2
            cond = false
        end
    end

    return ps_deptos_extendidos_strip1, vec_dimension1_strip1, ps_deptos_extendidos_strip2, vec_dimension1_strip2
end

# Rota vector de PolyShapes a orientación original
function rota_polyshapes(vec_polyshapes::Vector{PolyShape}, angulo_rotacion::Float64, cr::Vector{Float64})
    return [polyShape.polyArea(ps) > 0.0 ? polyShape.polyRotate(ps, -angulo_rotacion, cr) : ps for ps in vec_polyshapes]
end

# Crea caja alineada según orientación de franja
function polyBoxAligned(base1::Float64, base2::Float64, profundidad_depto::Float64, ancho_depto::Float64, franja::Symbol, is_vertical::Bool)
    if is_vertical
        offset = (franja == :este) ? base1 : base1 - profundidad_depto
        return polyShape.polyBox(offset, base2, profundidad_depto, ancho_depto, 0.0)
    else
        offset = (franja == :norte) ? base1 : base1 - profundidad_depto
        return polyShape.polyBox(base2, offset, ancho_depto, profundidad_depto, 0.0)
    end
end

# Genera terrazas para ambas franjas
function genera_terrazas_ambas_franjas(vec_terrazas_areas_strip1, vec_terrazas_areas_strip2,
                                        vec_dimension1_franja1_deptos, vec_dimension1_franja2_deptos,
                                        vec_dimension2_franja1_deptos, vec_dimension2_franja2_deptos,
                                        vec_coord_ini1, vec_coord_ini2,
                                        coord_base, franja1, franja2,
                                        is_vertical)

    vec_terrazas_strip1 = PolyShape[]
    vec_terrazas_strip2 = PolyShape[]
    min_profundidad_terraza = 1.5

    # Generar terrazas según orientación vertical u horizontal
    if is_vertical
        # Terrazas strip 1 (este)
        for i in eachindex(vec_terrazas_areas_strip1)
            profundidad_terrazas_areas_strip1 = max(min_profundidad_terraza, vec_terrazas_areas_strip1[i] / vec_dimension2_franja1_deptos[i])
            ancho_terrazas_areas_strip1 = vec_terrazas_areas_strip1[i] / profundidad_terrazas_areas_strip1
            base1 = coord_base + vec_dimension1_franja1_deptos[i]
            base2 = vec_coord_ini1[i] + vec_dimension2_franja1_deptos[i] / 2 - ancho_terrazas_areas_strip1 / 2
            ps_terrace_franja1 = polyShape.polyBox(base1, base2, profundidad_terrazas_areas_strip1, ancho_terrazas_areas_strip1, 0.0)
            push!(vec_terrazas_strip1, ps_terrace_franja1)
        end
        # Terrazas strip 2 (oeste)
        for i in eachindex(vec_terrazas_areas_strip2)
            profundidad_terrazas_areas_strip2 = max(min_profundidad_terraza, vec_terrazas_areas_strip2[i] / vec_dimension2_franja2_deptos[i])
            ancho_terrazas_areas_strip2 = vec_terrazas_areas_strip2[i] / profundidad_terrazas_areas_strip2
            base1 = coord_base - vec_dimension1_franja2_deptos[i]
            base2 = vec_coord_ini2[i] + vec_dimension2_franja2_deptos[i] / 2 - ancho_terrazas_areas_strip2 / 2
            ps_terrace_franja2 = polyShape.polyBox(base1 - profundidad_terrazas_areas_strip2, base2, profundidad_terrazas_areas_strip2, ancho_terrazas_areas_strip2, 0.0)
            push!(vec_terrazas_strip2, ps_terrace_franja2)
        end
    else
        # Terrazas strip 1 (norte)
        for i in eachindex(vec_terrazas_areas_strip1)
            profundidad_terrazas_areas_strip1 = max(min_profundidad_terraza, vec_terrazas_areas_strip1[i] / vec_dimension2_franja1_deptos[i])
            ancho_terrazas_areas_strip1 = vec_terrazas_areas_strip1[i] / profundidad_terrazas_areas_strip1
            base1 = coord_base + vec_dimension1_franja1_deptos[i]
            base2 = vec_coord_ini1[i] + vec_dimension2_franja1_deptos[i] / 2 - ancho_terrazas_areas_strip1 / 2
            ps_terrace_franja1 = polyShape.polyBox(base2, base1, ancho_terrazas_areas_strip1, profundidad_terrazas_areas_strip1, 0.0)
            push!(vec_terrazas_strip1, ps_terrace_franja1)
        end
        # Terrazas strip 2 (sur)
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

# Ajusta terraza para no exceder ratio máximo respecto a área interior
function ajusta_terraza_max_ratio(ps_depto::PolyShape, ps_terraza::PolyShape, max_ratio::Float64)
    area_interior = polyShape.polyArea(ps_depto)
    area_terraza = polyShape.polyArea(ps_terraza)

    # Retornar sin cambios si cumple ratio
    if area_terraza <= max_ratio * area_interior || area_terraza <= 0.0
        return ps_terraza
    end

    # Calcular factor de reducción
    area_terraza_max = max_ratio * area_interior
    factor = area_terraza_max / area_terraza

    # Obtener dimensiones actuales
    V = ps_terraza.Vertices[1]
    min_x = minimum(V[:, 1])
    max_x = maximum(V[:, 1])
    min_y = minimum(V[:, 2])
    max_y = maximum(V[:, 2])
    ancho = max_x - min_x
    profundidad = max_y - min_y

    # Reducir dimensión mayor manteniendo centrado
    if ancho >= profundidad
        nuevo_ancho = ancho * factor
        centro_x = (min_x + max_x) / 2
        nuevo_min_x = centro_x - nuevo_ancho / 2
        return polyShape.polyBox(nuevo_min_x, min_y, nuevo_ancho, profundidad, 0.0)
    else
        nueva_profundidad = profundidad * factor
        centro_y = (min_y + max_y) / 2
        nuevo_min_y = centro_y - nueva_profundidad / 2
        return polyShape.polyBox(min_x, nuevo_min_y, ancho, nueva_profundidad, 0.0)
    end
end

# Aplica límite de tamaño de terraza a todos los departamentos
function ajusta_terrazas_max_ratio(vec_ps_deptos::Vector{PolyShape}, vec_ps_terrazas::Vector{PolyShape}, max_ratio::Float64)
    vec_ps_terrazas_ajustadas = PolyShape[]
    for i in eachindex(vec_ps_terrazas)
        ps_terraza_ajustada = ajusta_terraza_max_ratio(vec_ps_deptos[i], vec_ps_terrazas[i], max_ratio)
        push!(vec_ps_terrazas_ajustadas, ps_terraza_ajustada)
    end
    return vec_ps_terrazas_ajustadas
end

# Analiza desviación de forma cuadrada en departamentos
function analiza_forma_apartamentos(vec_apartamentos1::Vector{PolyShape}, vec_apartamentos2::Vector{PolyShape})
    max_deviation = 0.0

    # Revisar todos los departamentos de ambas franjas
    for vec_apts in [vec_apartamentos1, vec_apartamentos2]
        for ps in vec_apts
            # Calcular bounding box
            min_x = minimum([minimum(region[:, 1]) for region in ps.Vertices])
            max_x = maximum([maximum(region[:, 1]) for region in ps.Vertices])
            min_y = minimum([minimum(region[:, 2]) for region in ps.Vertices])
            max_y = maximum([maximum(region[:, 2]) for region in ps.Vertices])

            # Calcular ratio y desviación respecto a cuadrado
            width = max_x - min_x
            height = max_y - min_y
            ratio = width > 0.0 ? height / width : 0.0
            deviation = abs(1.0 - ratio)
            max_deviation = max(max_deviation, deviation)
        end
    end

    return max_deviation
end

# Calcula geometría del pasillo y núcleo de circulación
function calcula_geometria_pasillo(vec_coord_fin1::Vector{Float64}, vec_coord_fin2::Vector{Float64},
                    vec_coord_ini1::Vector{Float64}, vec_coord_ini2::Vector{Float64}, coord_base::Float64,
                    profundidad_pasillo::Float64, is_vertical::Bool, W::Float64, H::Float64, coord_min::Float64,
                    min_ancho_pasillo::Float64, vec_tipo_deptos1::Vector{Int},
                    vec_tipo_deptos2::Vector{Int},
                    num_escaleras, ancho_escaleras)

    # Contar departamentos por franja
    num_deptos_franja1 = count(t -> t != -1, vec_tipo_deptos1)
    num_deptos_franja2 = count(t -> t != -1, vec_tipo_deptos2)
    num_deptos_total = num_deptos_franja1 + num_deptos_franja2

    if (isempty(vec_coord_fin1) || isempty(vec_coord_ini1)) && (isempty(vec_coord_fin2) || isempty(vec_coord_ini2))
        ps_pasillo = polyShape.polyBox(0.0, 0.0, 0.0, 0.0, 0.0)
        return 0.0, 0.0, 0.0, ps_pasillo
    end

    # Determinar coordenadas inicio/fin del pasillo
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
    if ancho_pasillo < 0
        ancho_pasillo = 0.0
    end

    # Aplicar ancho mínimo si es necesario
    if ancho_pasillo < min_ancho_pasillo
        centro_pasillo = (coord_ini_pasillo + coord_fin_pasillo) / 2
        coord_ini_pasillo = centro_pasillo - min_ancho_pasillo / 2
        coord_fin_pasillo = centro_pasillo + min_ancho_pasillo / 2
        ancho_pasillo = min_ancho_pasillo
    end

    # Centrar pasillo si hay solo 2 departamentos
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

    # Crear geometría del pasillo
    if is_vertical
        ps_pasillo = polyShape.polyBox(coord_pasillo, coord_ini_pasillo, profundidad_pasillo, ancho_pasillo, 0.0)
        x_centroide = coord_base
        y_centroide = (coord_ini_pasillo + coord_fin_pasillo) / 2
    else
        ps_pasillo = polyShape.polyBox(coord_ini_pasillo, coord_pasillo, ancho_pasillo, profundidad_pasillo, 0.0)
        x_centroide = (coord_ini_pasillo + coord_fin_pasillo) / 2
        y_centroide = coord_base
    end

    # Dimensiones del núcleo según ancho de escaleras
    if ancho_escaleras == 1.1
        profundidad_escalera = 2.8 
        profundidad_ascensor = 2.5 
        ancho_nucleo_box = 5.58
    elseif ancho_escaleras == 1.2
        profundidad_escalera = 3.0 
        profundidad_ascensor = 2.5 
        ancho_nucleo_box = 5.78
    elseif ancho_escaleras == 1.3
        profundidad_escalera = 3.2 
        profundidad_ascensor = 2.5 
        ancho_nucleo_box = 5.98
    elseif ancho_escaleras == 1.4
        profundidad_escalera = 3.4 
        profundidad_ascensor = 2.5 
        ancho_nucleo_box = 6.18
    elseif ancho_escaleras == 1.5
        profundidad_escalera = 3.6 
        profundidad_ascensor = 2.5 
        ancho_nucleo_box = 6.38
    end
    profundidad_nucleo = profundidad_escalera + profundidad_ascensor + 1.5
    ancho_escalera = ancho_nucleo_box
    ancho_ascensor = ancho_nucleo_box

    # Inicializar geometrías del núcleo
    area_escalera = 0.0
    area_ascensor = 0.0
    area_nucleo = 0.0
    ps_escalera = polyShape.polyBox(0.0, 0.0, 0.0, 0.0, 0.0)
    ps_ascensor = polyShape.polyBox(0.0, 0.0, 0.0, 0.0, 0.0)
    ps_nucleo = polyShape.polyBox(0.0, 0.0, 0.0, 0.0, 0.0)

    # Crear geometría de escalera en strip 1
    if !isempty(vec_coord_ini1) && !isempty(vec_coord_fin1)
        coord_centro_strip1 = (vec_coord_ini1[1] + vec_coord_fin1[end]) / 2

        if is_vertical
            ps_escalera = polyShape.polyBox(coord_base + 0.75, coord_centro_strip1 - ancho_nucleo_box / 2, profundidad_escalera, ancho_escalera, 0.0)
        else
            ps_escalera = polyShape.polyBox(coord_centro_strip1 - ancho_nucleo_box / 2, coord_base + 0.75, ancho_escalera, profundidad_escalera, 0.0)
        end
        area_escalera = polyShape.polyArea(ps_escalera)
    end

    # Crear geometría de ascensor en strip 2
    if !isempty(vec_coord_ini2) && !isempty(vec_coord_fin2)
        coord_centro_strip2 = (vec_coord_ini2[1] + vec_coord_fin2[end]) / 2

        if is_vertical
            ps_ascensor = polyShape.polyBox(coord_base - 0.75 - profundidad_ascensor, coord_centro_strip2 - ancho_nucleo_box / 2, profundidad_ascensor, ancho_ascensor, 0.0)
        else
            ps_ascensor = polyShape.polyBox(coord_centro_strip2 - ancho_nucleo_box / 2, coord_base - 0.75 - profundidad_ascensor, ancho_ascensor, profundidad_ascensor, 0.0)
        end
        area_ascensor = polyShape.polyArea(ps_ascensor)
    end

    # Crear núcleo completo y unir con pasillo
    coord_centro_strip2 = (vec_coord_ini2[1] + vec_coord_fin2[end]) / 2
    if is_vertical
        ps_nucleo = polyShape.polyBox(coord_base - 0.75 - profundidad_ascensor, coord_centro_strip2 - ancho_nucleo_box / 2, profundidad_nucleo, ancho_nucleo_box, 0.0)
    else
        ps_nucleo = polyShape.polyBox(coord_centro_strip2 - ancho_nucleo_box / 2, coord_base - 0.75 - profundidad_ascensor, ancho_nucleo_box, profundidad_nucleo, 0.0)
    end
    ps_dif = polyShape.polyDifference(ps_nucleo, ps_escalera)
    ps_dif = polyShape.polyDifference(ps_dif, ps_ascensor)
    ps_pasillo = polyShape.polyUnion(ps_pasillo, ps_dif)

    return ancho_pasillo, ps_pasillo, area_escalera, area_ascensor, ps_nucleo, ps_escalera, ps_ascensor
end

# Calcula orientación cardinal de cada departamento
function calcula_orientaciones_apartamentos(vec_ps_deptos_interior_all::Vector{PolyShape},
                                           ps_pasillo::PolyShape)

    # Crear envolvente reducida para detectar bordes exteriores
    ps_union_deptos = reduce((acc, ps) -> polyShape.polyUnion(acc, ps), vec_ps_deptos_interior_all)
    ps_union_all = polyShape.polyUnion(ps_union_deptos, ps_pasillo)
    ps_shrinked = polyClipper.polyOffset(ps_union_all, -0.1)

    vec_apartamentos_orientaciones = Vector{Dict}(undef, length(vec_ps_deptos_interior_all))

    # Procesar cada departamento
    for (idx_apt, ps_apt) in enumerate(vec_ps_deptos_interior_all)
        vec_edges, _ = polyShape.shape2vector(ps_apt)
        num_edges = length(vec_edges)

        orientation = polyShape.polyOrientation(ps_apt)

        vec_edge_angles = Vector{Float64}(undef, num_edges)
        vec_edge_exposure_angles = Vector{Float64}(undef, num_edges)
        vec_edge_total_lengths = Vector{Float64}(undef, num_edges)
        vec_edge_exterior_lengths = Vector{Float64}(undef, num_edges)

        # Calcular ángulo y exposición exterior de cada borde
        for (idx_edge, edge) in enumerate(vec_edges)
            edge_angle = polyShape.lineAngle(edge)
            total_length = polyShape.lineLength(edge)

            exterior_segment = polyShape.polyDifference(edge, ps_shrinked)
            exterior_length_result = polyShape.lineLength(exterior_segment)
            exterior_length = isa(exterior_length_result, Number) ? Float64(exterior_length_result) : 0.0

            # Calcular ángulo de exposición según orientación del polígono
            if orientation == 1
                exposure_angle = edge_angle - pi / 2
            else
                exposure_angle = edge_angle + pi / 2
            end

            # Normalizar ángulo a rango [0, 2π)
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

        # Calcular orientación media ponderada por largo exterior
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

        # Convertir ángulo a dirección cardinal
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
            "vec_angulo_exposicion_exterior" => vec_edge_exposure_angles,
            "vec_edge_total_lengths" => vec_edge_total_lengths,
            "vec_largo_exposicion_segmento" => vec_edge_exterior_lengths,
            "orientacion_media" => mean_orientation,
            "orientacion" => cardinal_direction
        )
    end

    return vec_apartamentos_orientaciones
end

# Empaqueta geometrías y métricas en diccionario de resultados
function empaqueta_resultados(dimension1::Float64, dimension2::Float64,
                    W::Float64, H::Float64, profundidad_pasillo::Float64, ancho_pasillo::Float64, ps_pasillo::PolyShape,
                    vec_ps_deptos_franja_1::Vector{PolyShape}, vec_ps_deptos_franja_2::Vector{PolyShape},
                    vec_terrazas1::Vector{PolyShape}, vec_terrazas2::Vector{PolyShape},
                    ps_planta::PolyShape, vec_tipo_strings1::Vector{String}=String[], vec_tipo_strings2::Vector{String}=String[];
                    area_escalera::Float64=0.0, area_ascensor::Float64=0.0,
                    ps_nucleo::PolyShape=polyShape.polyBox(0.0, 0.0, 0.0, 0.0, 0.0),
                    ps_escalera::PolyShape=polyShape.polyBox(0.0, 0.0, 0.0, 0.0, 0.0),
                    ps_ascensor::PolyShape=polyShape.polyBox(0.0, 0.0, 0.0, 0.0, 0.0))

    # Crear diccionario con dimensiones y áreas
    area_pasillo = polyShape.polyArea(ps_pasillo)
    result = Dict(
        "feasible" => true,
        "status" => "LOCALLY_SOLVED",
        "profundidad_franja_1" => round(dimension1, digits=2),
        "profundidad_franja_2" => round(dimension2, digits=2),
        "ancho_total" => W,
        "profundidad_total" => H,
        "profundidad_pasillo" => profundidad_pasillo,
        "ancho_pasillo" => ancho_pasillo,
        "area_escalera" => round(area_escalera, digits=2),
        "area_ascensor" => round(area_ascensor, digits=2),
        "area_pasillo" => round(area_pasillo, digits=2),
        "ps_pasillo" => ps_pasillo,
        "ps_nucleo" => ps_nucleo,
        "ps_escalera" => ps_escalera,
        "ps_ascensor" => ps_ascensor
    )

    # Combinar departamentos y terrazas de ambas franjas
    result["vec_ps_deptos_interior_all"] = vcat(vec_ps_deptos_franja_1, vec_ps_deptos_franja_2)
    result["vec_ps_terrazas_all"] = vcat(vec_terrazas1, vec_terrazas2)
    result["vec_strips"] = vcat(fill(1, length(vec_tipo_strings1)), fill(2, length(vec_tipo_strings2)))

    # Analizar forma de departamentos
    shape_analysis = analiza_forma_apartamentos(vec_ps_deptos_franja_1, vec_ps_deptos_franja_2)
    result["max_depto_square_deviation"] = round(shape_analysis, digits=3)

    # Calcular área fuera de planta
    valid_terrazas = [ps for ps in result["vec_ps_terrazas_all"] if polyShape.polyArea(ps) > 0.0]
    all_shapes = vcat([ps_pasillo], result["vec_ps_deptos_interior_all"], valid_terrazas)
    ps_union_all = reduce((acc, ps) -> polyShape.polyUnion(acc, ps), all_shapes)
    ps_outbound = polyShape.polyDifference(ps_union_all, ps_planta)
    area_outbound = polyShape.polyArea(ps_outbound)
    result["area_outbound"] = round(area_outbound, digits=2)

    return result
end

# Genera layout de planta distribuyendo departamentos en dos franjas
function genera_layout(dict_edificio_deptos, max_constructibilidad::Float64, num_pisos_superiores::Int;
                        profundidad_pasillo::Float64 = 1.5,
                        min_ancho_pasillo::Float64 = 0.0,
                        flag_dfl2::Bool = false,
                        flag_vivienda_economica::Bool = false,
                        num_escaleras=1.0, ancho_escaleras=1.1)

    # Extraer configuración del edificio
    best_layout = dict_edificio_deptos["best_layout"]
    is_vertical = (best_layout == 2)
    ps_planta_normalizado = dict_edificio_deptos["ps_planta_normalizado"]
    H_s_strip1 = dict_edificio_deptos["strip_1_H_s"]
    H_s_strip2 = dict_edificio_deptos["strip_2_H_s"]
    strip1_paralelo = get(dict_edificio_deptos, "strip_1_paralelo_calle", false)
    strip2_paralelo = get(dict_edificio_deptos, "strip_2_paralelo_calle", false)

    # Extender planta si hay franjas paralelas a calle
    if strip1_paralelo || strip2_paralelo
        V = ps_planta_normalizado.Vertices[1]
        x_min, x_max = extrema(V[:, 1])
        y_min, y_max = extrema(V[:, 2])
        ext1 = strip1_paralelo ? 1.5 : 0.0
        ext2 = strip2_paralelo ? 1.5 : 0.0
        if is_vertical
            ps_planta_normalizado = polyShape.polyBox(x_min - ext2, y_min, x_max - x_min + ext1 + ext2, y_max - y_min)
        else
            ps_planta_normalizado = polyShape.polyBox(x_min, y_min - ext2, x_max - x_min, y_max - y_min + ext1 + ext2)
        end
    end

    # Calcular dimensiones de planta
    V_planta_normalizado = ps_planta_normalizado.Vertices[1]
    vec_x_planta = V_planta_normalizado[:, 1]
    vec_y_planta = V_planta_normalizado[:, 2]
    W = maximum(vec_x_planta) - minimum(vec_x_planta)
    H = maximum(vec_y_planta) - minimum(vec_y_planta)

    # Agrupar departamentos por tipo
    df_deptos_resumen = combine(
        groupby(dict_edificio_deptos["df_deptos"], [:strip, :tipo, :sup_interior_bruta, :sup_terraza, :ancho_interior, :profundidad_interior, :num_unidades_por_piso_superior, :num_unidades_primer_piso]),
        :num_unidades_edificio => sum => :num_unidades_edificio)

    # Configurar coordenadas según orientación
    coord_min_x = minimum(vec_x_planta)
    coord_min_y = minimum(vec_y_planta)
    H_s_strip1 = dict_edificio_deptos["strip_1_H_s"] + (strip1_paralelo ? 1.5 : 0.0)
    H_s_strip2 = dict_edificio_deptos["strip_2_H_s"] + (strip2_paralelo ? 1.5 : 0.0)
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

    # Ordenar y preparar datos de departamentos
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
                mat_deptos_strip1 = vcat(mat_deptos_strip1, [row.sup_interior_bruta row.ancho_interior row.profundidad_interior])
                push!(vec_tipos_strip1, string(row.tipo))
                push!(vec_terrazas_areas_strip1, row.sup_terraza)
                push!(vec_en_primer_piso_strip1, en_primer_piso)
                if en_primer_piso
                    push!(vec_terrazas_areas_pp_strip1, row.sup_terraza)
                end
            else
                mat_deptos_strip2 = vcat(mat_deptos_strip2, [row.sup_interior_bruta row.ancho_interior row.profundidad_interior])
                push!(vec_tipos_strip2, string(row.tipo))
                push!(vec_terrazas_areas_strip2, row.sup_terraza)
                push!(vec_en_primer_piso_strip2, en_primer_piso)
                if en_primer_piso
                    push!(vec_terrazas_areas_pp_strip2, row.sup_terraza)
                end
            end
        end
    end

    # Reordenar departamentos (grandes en extremos)
    mat_deptos_strip1, vec_tipos_strip1, vec_terrazas_areas_strip1, vec_en_primer_piso_strip1 = reordena_deptos_grandes_en_extremos(
        mat_deptos_strip1, vec_tipos_strip1, vec_terrazas_areas_strip1, vec_en_primer_piso_strip1)
    mat_deptos_strip2, vec_tipos_strip2, vec_terrazas_areas_strip2, vec_en_primer_piso_strip2 = reordena_deptos_grandes_en_extremos(
        mat_deptos_strip2, vec_tipos_strip2, vec_terrazas_areas_strip2, vec_en_primer_piso_strip2)

    # Generar geometrías de departamentos para cada franja
    coord_min_planta = coord_min
    vec_coord_ini1, vec_coord_fin1, vec_dimension1_franja1_deptos, vec_dimension2_franja1_deptos, vec_tipo_deptos1,
            _, vec_tipo_strings1 = genera_deptos_franja(mat_deptos_strip1, coord_min_planta,
                                            is_vertical, coord_base, franja1, vec_tipos_strip1)
    vec_coord_ini2, vec_coord_fin2, vec_dimension1_franja2_deptos, vec_dimension2_franja2_deptos, vec_tipo_deptos2,
            _, vec_tipo_strings2 = genera_deptos_franja(mat_deptos_strip2, coord_min_planta,
                                            is_vertical, coord_base, franja2, vec_tipos_strip2)

    # Calcular geometría del pasillo y núcleo
    ancho_pasillo, ps_pasillo_normalizado, area_escalera, area_ascensor, ps_nucleo, ps_escalera, ps_ascensor = calcula_geometria_pasillo(
                                            vec_coord_fin1, vec_coord_fin2, vec_coord_ini1, vec_coord_ini2,
                                            coord_base, profundidad_pasillo, is_vertical,
                                            W, H,
                                            coord_min, min_ancho_pasillo,
                                            vec_tipo_deptos1, vec_tipo_deptos2,
                                            num_escaleras, ancho_escaleras)

    # Calcular dimensiones de terrazas
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

    # Extender departamentos hacia pasillo y ajustar constructibilidad
    vec_ps_deptos_franja_1_normalizado, vec_dimension1_franja1_deptos_ext,
        vec_ps_deptos_franja_2_normalizado, vec_dimension1_franja2_deptos_ext = extiende_deptos_con_interseccion_pasillo(
                                                                                    vec_profundidad_terraza_strip1, vec_profundidad_terraza_strip2,
                                                                                    vec_coord_ini1, vec_coord_fin1,
                                                                                    vec_coord_ini2, vec_coord_fin2,
                                                                                    coord_base, ps_pasillo_normalizado, ps_escalera, ps_ascensor,
                                                                                    franja1, franja2, is_vertical,
                                                                                    H_s_strip1, H_s_strip2,
                                                                                    vec_terrazas_areas_strip1, vec_terrazas_areas_strip2,
                                                                                    vec_terrazas_areas_pp_strip1, vec_terrazas_areas_pp_strip2,
                                                                                    vec_en_primer_piso_strip1, vec_en_primer_piso_strip2,
                                                                                    num_pisos_superiores,
                                                                                    max_constructibilidad,
                                                                                    flag_dfl2,
                                                                                    flag_vivienda_economica)

    # Generar geometrías de terrazas
    vec_terrazas_strip1, vec_terrazas_strip2 = genera_terrazas_ambas_franjas(vec_terrazas_areas_strip1, vec_terrazas_areas_strip2,
                                        vec_dimension1_franja1_deptos_ext, vec_dimension1_franja2_deptos_ext,
                                        vec_dimension2_franja1_deptos, vec_dimension2_franja2_deptos,
                                        vec_coord_ini1, vec_coord_ini2,
                                        coord_base, franja1, franja2,
                                        is_vertical)

    # Empaquetar resultados en coordenadas normalizadas
    ps_planta = dict_edificio_deptos["ps_planta"]

    results = empaqueta_resultados(dimension_depto1, dimension_depto2, W, H, profundidad_pasillo, ancho_pasillo, ps_pasillo_normalizado,
                                    vec_ps_deptos_franja_1_normalizado, vec_ps_deptos_franja_2_normalizado,
                                    vec_terrazas_strip1, vec_terrazas_strip2, ps_planta_normalizado, vec_tipo_strings1, vec_tipo_strings2,
                                    area_escalera=area_escalera, area_ascensor=area_ascensor, ps_nucleo=ps_nucleo, ps_escalera=ps_escalera, ps_ascensor=ps_ascensor)

    results["ps_planta"] = ps_planta

    # Área común total
    delta = 0.02
    ps_area_comun_total = polyClipper.polyOffset(ps_pasillo_normalizado, delta)
    ps_area_comun_total = polyClipper.polyOffset(ps_area_comun_total, -delta)
    results["ps_area_comun_total"] = ps_area_comun_total

    results_pisos_superiores = results

    # Procesar primer piso (puede tener menos departamentos)
    df_deptos = dict_edificio_deptos["df_deptos"]
    df_deptos_con_primer_piso = filter(row -> row.num_unidades_primer_piso > 0, df_deptos)

    if nrow(df_deptos_con_primer_piso) == 0
        return results_pisos_superiores, nothing
    end

    # Identificar departamentos en primer piso
    vec_en_primer_piso_all = Bool[]
    for row in eachrow(df_deptos_sorted)
        n_repeat_superior = Int(round(row.num_unidades_por_piso_superior))
        n_repeat_primer = Int(round(row.num_unidades_primer_piso))
        for i in 1:n_repeat_superior
            push!(vec_en_primer_piso_all, i <= n_repeat_primer)
        end
    end

    # Extraer geometrías del piso superior
    vec_ps_deptos_interior_all_superior = results_pisos_superiores["vec_ps_deptos_interior_all"]
    vec_ps_terrazas_all_superior = results_pisos_superiores["vec_ps_terrazas_all"]
    vec_strips_all_superior = results_pisos_superiores["vec_strips"]
    ps_pasillo_superior = results_pisos_superiores["ps_pasillo"]

    # Separar departamentos de primer piso y espacios vacíos
    indices_primer_piso = findall(vec_en_primer_piso_all)
    indices_espacios_vacios = findall(.!vec_en_primer_piso_all)

    vec_ps_deptos_interior_all_pp = vec_ps_deptos_interior_all_superior[indices_primer_piso]
    vec_ps_terrazas_all_pp = vec_ps_terrazas_all_superior[indices_primer_piso]
    vec_strips_all_pp = vec_strips_all_superior[indices_primer_piso]

    # Agregar espacios vacíos al área común del primer piso
    vec_ps_espacios_vacios = vec_ps_deptos_interior_all_superior[indices_espacios_vacios]

    valid_espacios_vacios = [ps for ps in vec_ps_espacios_vacios if polyShape.polyArea(ps) > 0.0]
    ps_pasillo_pp = isempty(valid_espacios_vacios) ? ps_pasillo_superior : reduce((acc, ps) -> polyShape.polyUnion(acc, ps), valid_espacios_vacios, init=ps_pasillo_superior)

    area_pasillo_pp = polyShape.polyArea(ps_pasillo_pp)
    ps_planta_original = dict_edificio_deptos["ps_planta"]

    # Empaquetar resultados del primer piso
    results_primer_piso = Dict(
        "vec_ps_deptos_interior_all" => vec_ps_deptos_interior_all_pp,
        "vec_ps_terrazas_all" => vec_ps_terrazas_all_pp,
        "vec_strips" => vec_strips_all_pp,
        "area_pasillo" => round(area_pasillo_pp, digits=2),
        "area_escalera" => round(area_escalera, digits=2),
        "area_ascensor" => round(area_ascensor, digits=2),
        "ps_nucleo" => ps_nucleo,
        "ps_escalera" => ps_escalera,
        "ps_ascensor" => ps_ascensor,
        "ps_pasillo" => ps_pasillo_pp,
        "ps_planta" => ps_planta_original
        )

    return results_pisos_superiores, results_primer_piso
end

# Rota PolyShape de forma segura (ignora geometrías inválidas)
function rota_polyshape_safe(ps, angulo_rotacion, cr)
    if isa(ps, PolyShape) && polyShape.polyArea(ps) > 0.0
        return polyShape.polyRotate(ps, -angulo_rotacion, cr)
    end
    return ps
end

# Rota geometrías a coordenadas reales y aplica límites de terraza
function procesa_resultados_piso!(results, angulo_rotacion, cr, max_ratio_terraza::Float64)
    # Ajustar tamaño de terrazas según ratio máximo
    vec_deptos = results["vec_ps_deptos_interior_all"]
    vec_terrazas = ajusta_terrazas_max_ratio(vec_deptos, results["vec_ps_terrazas_all"], max_ratio_terraza)

    # Rotar departamentos y terrazas
    results["vec_ps_deptos_interior_all"] = rota_polyshapes(vec_deptos, angulo_rotacion, cr)
    results["vec_ps_terrazas_all"] = rota_polyshapes(vec_terrazas, angulo_rotacion, cr)

    # Rotar áreas comunes y núcleo
    results["ps_pasillo"] = polyShape.polyRotate(results["ps_pasillo"], -angulo_rotacion, cr)
    results["ps_nucleo"] = polyShape.polyRotate(results["ps_nucleo"], -angulo_rotacion, cr)
    results["ps_escalera"] = polyShape.polyRotate(results["ps_escalera"], -angulo_rotacion, cr)
    results["ps_ascensor"] = polyShape.polyRotate(results["ps_ascensor"], -angulo_rotacion, cr)
end

# Función principal: optimiza planta de piso para edificio residencial
function opti_floor_plan(dict_edificio_deptos, max_constructibilidad::Float64, num_pisos_superiores::Int;
                        profundidad_pasillo::Float64 = 1.5,
                        min_ancho_pasillo::Float64 = 0.0,
                        num_escaleras=1.0, ancho_escaleras=1.1)

    # Extraer flags de normativa
    flag_dfl2 = get(dict_edificio_deptos, "flag_dfl2", false)
    flag_vivienda_economica = get(dict_edificio_deptos, "flag_vivienda_economica", false)

    # Generar layout en coordenadas normalizadas
    results_pisos_superiores, results_primer_piso = genera_layout(dict_edificio_deptos, max_constructibilidad, num_pisos_superiores,
                profundidad_pasillo=profundidad_pasillo,
                min_ancho_pasillo=min_ancho_pasillo,
                flag_dfl2=flag_dfl2,
                flag_vivienda_economica=flag_vivienda_economica,
                num_escaleras=num_escaleras, ancho_escaleras=ancho_escaleras)

    # Rotar resultados a coordenadas reales
    angulo_rotacion = dict_edificio_deptos["angulo_rotacion"]
    cr = dict_edificio_deptos["cr"]
    max_ratio_terraza = 0.25
    procesa_resultados_piso!(results_pisos_superiores, angulo_rotacion, cr, max_ratio_terraza)

    # Calcular orientaciones de departamentos
    vec_deptos_rotated = results_pisos_superiores["vec_ps_deptos_interior_all"]
    ps_pasillo_rotated = results_pisos_superiores["ps_pasillo"]

    if !isempty(vec_deptos_rotated)
        results_pisos_superiores["vec_orientacion_deptos"] = calcula_orientaciones_apartamentos(vec_deptos_rotated, ps_pasillo_rotated)
    else
        results_pisos_superiores["vec_orientacion_deptos"] = Vector{Dict}()
    end

    # Procesar primer piso si existe
    if !isnothing(results_primer_piso)
        procesa_resultados_piso!(results_primer_piso, angulo_rotacion, cr, 0.25)
    end

    return Dict(
        "pisos_superiores" => results_pisos_superiores,
        "primer_piso" => results_primer_piso
    )
end

