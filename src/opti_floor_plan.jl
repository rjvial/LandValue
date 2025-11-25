const CONVERGENCE_TOLERANCE = 0.005
const INTERSECTION_TOLERANCE = 0.1
const TERRACE_ASPECT_RATIO = 1.75
const MAX_ADJUSTMENT_ITERATIONS = 10

struct CorridorConfig
    ancho_pasillo::Float64
    min_largo_pasillo::Float64
end

struct StairConfig
    area_escala::Float64
    min_ancho_escala::Float64
    tipo_escala::Symbol
end

struct TerraceConfig
    vec_sup_terraza::Vector{Float64}
    max_ancho_terraza::Float64
end


get_area(t::Tuple{Float64, Int}) = t[1]
get_tipo(t::Tuple{Float64, Int}) = t[2]

get_area(t::Tuple{Float64, Int, Int}) = t[1]
get_tipo(t::Tuple{Float64, Int, Int}) = t[2]
get_index(t::Tuple{Float64, Int, Int}) = t[3]

# ══════════════════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ══════════════════════════════════════════════════════════════════════════════════

# ──────────────────────────────────────────────────────────────────────────────────
# Geometry generation helpers
# ──────────────────────────────────────────────────────────────────────────────────

# Generates apartment geometries along one strip using pre-calculated dimensions
function genera_deptos_franja(mat_deptos::Matrix{Float64}, coord_min_planta::Float64,
            profundidad_franja::Float64, ancho_franja::Float64, min_ancho_escala::Float64,
            min_ancho_depto::Float64, is_vertical::Bool, coord_base::Float64, franja::Symbol)

    vec_coord_ini = Float64[]
    vec_coord_fin = Float64[]
    vec_dimension1_deptos = Float64[]
    vec_dimension2_deptos = Float64[]
    vec_tipo_deptos = Int[]

    if isempty(mat_deptos) || profundidad_franja <= 0.0
        return vec_coord_ini, vec_coord_fin, vec_dimension1_deptos, vec_dimension2_deptos, vec_tipo_deptos, PolyShape[]
    end

    if !isfinite(profundidad_franja)
        error("Invalid profundidad_franja: $profundidad_franja")
    end
    if ancho_franja <= 0.0 || !isfinite(ancho_franja)
        error("Invalid ancho_franja: $ancho_franja")
    end

    coord_current = coord_min_planta

    for i in 1:size(mat_deptos, 1)
        sup_interior = mat_deptos[i, 1]
        ancho_interior = mat_deptos[i, 2]
        profundidad_interior = mat_deptos[i, 3]

        push!(vec_coord_ini, coord_current)
        push!(vec_coord_fin, coord_current + ancho_interior)
        push!(vec_dimension1_deptos, profundidad_interior)
        push!(vec_dimension2_deptos, ancho_interior)
        push!(vec_tipo_deptos, 0)
        coord_current += ancho_interior
    end

    vec_ps_deptos_normalizado = PolyShape[]
    for i in eachindex(vec_coord_ini)
        ps_depto = polyBoxAligned(coord_base, vec_coord_ini[i], vec_dimension1_deptos[i], vec_dimension2_deptos[i], franja, is_vertical)
        push!(vec_ps_deptos_normalizado, ps_depto)
    end

    return vec_coord_ini, vec_coord_fin, vec_dimension1_deptos, vec_dimension2_deptos, vec_tipo_deptos, vec_ps_deptos_normalizado
end

# Extends apartments with corridor space overlap, then subtracts corridor geometry
function extiende_deptos_con_interseccion_pasillo(vec_coord_ini::Vector{Float64}, vec_coord_fin::Vector{Float64},
            vec_dimension1_deptos::Vector{Float64}, vec_dimension2_deptos::Vector{Float64}, coord_base::Float64,
            ps_pasillo::PolyShape, extend_franja::Symbol, is_vertical::Bool, vec_ps_deptos_normalizado::Vector{PolyShape},
            ps_pasillo_normalizado::PolyShape)

    vec_extension_dimension1 = Float64[]
    ps_deptos_extendidos = PolyShape[]

    if isempty(vec_coord_ini)
        return ps_deptos_extendidos, vec_extension_dimension1
    end

    for i in eachindex(vec_coord_ini)
        if !isfinite(vec_coord_ini[i]) || !isfinite(vec_coord_fin[i])
            error("Invalid coordinates at index $i: coord_ini=$(vec_coord_ini[i]), coord_fin=$(vec_coord_fin[i])")
        end
        if !isfinite(vec_dimension1_deptos[i]) || !isfinite(vec_dimension2_deptos[i])
            error("Invalid dimensions at index $i: profundidad_depto=$(vec_dimension1_deptos[i]), ancho_depto=$(vec_dimension2_deptos[i])")
        end

        ps_depto_normalizado = vec_ps_deptos_normalizado[i]
        ps_intersection = polyShape.polyIntersection(ps_depto_normalizado, ps_pasillo_normalizado)
        intersection_area = polyShape.polyArea(ps_intersection)

        if intersection_area > 0.0
            extension_dimension = intersection_area / vec_dimension2_deptos[i]
        else
            extension_dimension = 0.0
        end

        push!(vec_extension_dimension1, extension_dimension)

        dimension1_total = vec_dimension1_deptos[i] + extension_dimension
        dimension2 = vec_coord_fin[i] - vec_coord_ini[i]

        if !isfinite(dimension1_total) || !isfinite(dimension2) || dimension1_total <= 0.0 || dimension2 <= 0.0
            error("Invalid extended dimensions at index $i: dimension1_total=$dimension1_total, dimension2=$dimension2")
        end

        extended_local_poly = polyBoxAligned(coord_base, vec_coord_ini[i], dimension1_total, dimension2, extend_franja, is_vertical)
        extended_poly_final = polyShape.polyDifference(extended_local_poly, ps_pasillo)
        push!(ps_deptos_extendidos, extended_poly_final)
    end

    return ps_deptos_extendidos, vec_extension_dimension1
end

# Creates terrace geometries for each apartment based on required areas and available dimensions
function genera_terrazas_franja(vec_orden_deptos::Vector{Tuple{Float64, Int}}, vec_sup_terraza::Vector{Float64},
                    vec_dimension2_deptos::Vector{Float64}, vec_coord_ini::Vector{Float64},
                    coord_terrace_base::Vector{Float64}, terrace_franja::Symbol, max_ancho_terraza::Float64,
                    is_vertical::Bool)

    vec_terrazas = PolyShape[]

    for (i, depto) in enumerate(vec_orden_deptos)
        tipo_depto = get_tipo(depto)
        if tipo_depto == -1
            push!(vec_terrazas, PolyShape([zeros(0, 2)], 0))
        else
            area_terraza = vec_sup_terraza[i]
            if area_terraza > 0.0
                dimension2_depto = vec_dimension2_deptos[i]

                dim_parallel = min(dimension2_depto, area_terraza / TERRACE_ASPECT_RATIO)
                dim_perpendicular = area_terraza / dim_parallel

                if dim_perpendicular > max_ancho_terraza
                    dim_perpendicular = max_ancho_terraza
                end

                coord_depto_ini = vec_coord_ini[i]
                coord_terraza_ini = coord_depto_ini + (dimension2_depto - dim_parallel) / 2

                terrace_poly = polyBoxAligned(coord_terrace_base[i], coord_terraza_ini, dim_perpendicular, dim_parallel, terrace_franja, is_vertical)
                push!(vec_terrazas, terrace_poly)
            else
                push!(vec_terrazas, PolyShape([zeros(0, 2)], 0))
            end
        end
    end

    return vec_terrazas
end

# ──────────────────────────────────────────────────────────────────────────────────
# Geometric transformation helpers
# ──────────────────────────────────────────────────────────────────────────────────

# Rotates vector of polyshapes back to original orientation around center point
function rota_polyshapes(vec_polyshapes::Vector{PolyShape}, angulo_rotacion::Float64, cr::Vector{Float64})
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

# Creates axis-aligned box with franja-aware positioning (vertical: X-axis, horizontal: Y-axis)
function polyBoxAligned(base1::Float64, base2::Float64, profundidad_depto::Float64, ancho_depto::Float64, franja::Symbol, is_vertical::Bool)
    if is_vertical
        is_positive_franja = (franja == :este)
        offset = is_positive_franja ? base1 : base1 - profundidad_depto
        return polyShape.polyBox(offset, base2, profundidad_depto, ancho_depto, 0.0)
    else
        is_positive_franja = (franja == :norte)
        offset = is_positive_franja ? base1 : base1 - profundidad_depto
        return polyShape.polyBox(base2, offset, ancho_depto, profundidad_depto, 0.0)
    end
end

# ──────────────────────────────────────────────────────────────────────────────────
# Coordinate and bounds helpers
# ──────────────────────────────────────────────────────────────────────────────────

# Returns coordinate index for axis (1 for X, 2 for Y)
function get_coord_index(is_vertical::Bool)
    return is_vertical ? 1 : 2
end

# Returns floor plan min and max coordinates
function get_floor_bounds(vec_planta::Vector{Float64})
    return minimum(vec_planta), maximum(vec_planta)
end

# Returns min or max coordinate from non-empty terraces along axis
function get_terrace_bounds(vec_terrazas::Vector{PolyShape}, is_vertical::Bool, get_max::Bool)
    terrazas_con_area = [t for t in vec_terrazas if polyShape.polyArea(t) > 0.0]
    isempty(terrazas_con_area) && return nothing

    coord_idx = get_coord_index(is_vertical)
    return get_max ? maximum([maximum(t.Vertices[1][:, coord_idx]) for t in terrazas_con_area]) :
                        minimum([minimum(t.Vertices[1][:, coord_idx]) for t in terrazas_con_area])
end

# Returns outermost extent of apartments and terraces along axis
function get_strip_outermost_extent(vec_ps_deptos::Vector{PolyShape}, vec_terrazas::Vector{PolyShape}, is_vertical::Bool, get_max::Bool)
    coord_idx = get_coord_index(is_vertical)
    all_coords = Float64[]

    for apt in vec_ps_deptos
        if polyShape.polyArea(apt) > 0.0
            append!(all_coords, apt.Vertices[1][:, coord_idx])
        end
    end

    for terrace in vec_terrazas
        if polyShape.polyArea(terrace) > 0.0
            append!(all_coords, terrace.Vertices[1][:, coord_idx])
        end
    end

    isempty(all_coords) && return nothing
    return get_max ? maximum(all_coords) : minimum(all_coords)
end

# Translates all geometries by delta in specified franja
function apply_terrace_correction(vec_ps_deptos_franja_1::Vector{PolyShape}, vec_ps_deptos_franja_2::Vector{PolyShape},
                                    vec_terrazas1::Vector{PolyShape}, vec_terrazas2::Vector{PolyShape},
                                    ps_pasillo::PolyShape, delta::Float64, is_vertical::Bool, franja::Symbol)
    if is_vertical
        delta_x = (franja == :este) ? delta : -delta
        dx, dy = delta_x, 0.0
    else
        delta_y = (franja == :norte) ? delta : -delta
        dx, dy = 0.0, delta_y
    end

    return ([polyShape.polyTranslate(p, dx, dy) for p in vec_ps_deptos_franja_1],
            [polyShape.polyTranslate(p, dx, dy) for p in vec_ps_deptos_franja_2],
            [polyShape.polyTranslate(t, dx, dy) for t in vec_terrazas1],
            [polyShape.polyTranslate(t, dx, dy) for t in vec_terrazas2],
            polyShape.polyTranslate(ps_pasillo, dx, dy))
end

# Processes terraces for both strips including generation, verification, and correction
function procesa_terrazas_ambas_franjas(vec_terrazas_areas_strip1::Vector{Float64}, vec_terrazas_areas_strip2::Vector{Float64}, planta_normalizada,
                                            vec_dimension1_deptos1::Vector{Float64}, vec_dimension1_deptos2::Vector{Float64},
                                            vec_dimension2_deptos1::Vector{Float64}, vec_dimension2_deptos2::Vector{Float64},
                                            vec_coord_ini1::Vector{Float64}, vec_coord_ini2::Vector{Float64},
                                            vec_extension_dimension1_1::Vector{Float64}, vec_extension_dimension1_2::Vector{Float64},
                                            coord_base::Float64, franja1::Symbol, franja2::Symbol,
                                            is_vertical::Bool, vec_ps_deptos_franja_1_normalizado::Vector{PolyShape},
                                            vec_ps_deptos_franja_2_normalizado::Vector{PolyShape}, ps_pasillo_normalizado::PolyShape)

    vec_terrazas_strip1 = PolyShape[]
    vec_terrazas_strip2 = PolyShape[]

    if !isempty(vec_dimension1_deptos1) && length(vec_dimension1_deptos1) == length(planta_normalizada.deptos_ordenados1)
        coord_terrace_base1 = [coord_base + vec_dimension1_deptos1[i] + vec_extension_dimension1_1[i] for i in eachindex(vec_dimension1_deptos1)]
        vec_terrazas_strip1 = genera_terrazas_franja(planta_normalizada.deptos_ordenados1, vec_terrazas_areas_strip1, vec_dimension2_deptos1, vec_coord_ini1, coord_terrace_base1, franja1, planta_normalizada.dimension_terraza_max, is_vertical)
    end

    if !isempty(vec_dimension1_deptos2) && length(vec_dimension1_deptos2) == length(planta_normalizada.deptos_ordenados2)
        coord_terrace_base2 = [coord_base - vec_dimension1_deptos2[i] - vec_extension_dimension1_2[i] for i in eachindex(vec_dimension1_deptos2)]
        vec_terrazas_strip2 = genera_terrazas_franja(planta_normalizada.deptos_ordenados2, vec_terrazas_areas_strip2, vec_dimension2_deptos2, vec_coord_ini2, coord_terrace_base2, franja2, planta_normalizada.dimension_terraza_max, is_vertical)
    end

    flag_inscripcion1 = verifica_inscripcion_terrazas(planta_normalizada.ps_planta_normalizado, vec_terrazas_strip1)
    flag_inscripcion2 = verifica_inscripcion_terrazas(planta_normalizada.ps_planta_normalizado, vec_terrazas_strip2)

    if !flag_inscripcion1 && !flag_inscripcion2
        @warn "Both strips have outbound terraces - layout may not fit properly"
    end

    vec_floor_coords = is_vertical ? planta_normalizada.vec_x_planta : planta_normalizada.vec_y_planta

    if !flag_inscripcion1
        vec_ps_deptos_franja_1_normalizado, vec_ps_deptos_franja_2_normalizado, vec_terrazas_strip1, vec_terrazas_strip2, ps_pasillo_normalizado =
            correct_outbound_terraces(vec_terrazas_strip1, vec_terrazas_strip2,
                                        vec_ps_deptos_franja_1_normalizado, vec_ps_deptos_franja_2_normalizado,
                                        ps_pasillo_normalizado, vec_floor_coords, is_vertical, true, true)
    end
    if !flag_inscripcion2
        vec_ps_deptos_franja_1_normalizado, vec_ps_deptos_franja_2_normalizado, vec_terrazas_strip1, vec_terrazas_strip2, ps_pasillo_normalizado =
            correct_outbound_terraces(vec_terrazas_strip1, vec_terrazas_strip2,
                                        vec_ps_deptos_franja_1_normalizado, vec_ps_deptos_franja_2_normalizado,
                                        ps_pasillo_normalizado, vec_floor_coords, is_vertical, false, false)
    end

    return vec_terrazas_strip1, vec_terrazas_strip2, vec_ps_deptos_franja_1_normalizado, vec_ps_deptos_franja_2_normalizado, ps_pasillo_normalizado
end

# Corrects outbound terraces by shifting geometries; limits shift to prevent opposite side outbound
function correct_outbound_terraces(vec_terrazas1::Vector{PolyShape}, vec_terrazas2::Vector{PolyShape},
                                    vec_ps_deptos_franja_1::Vector{PolyShape}, vec_ps_deptos_franja_2::Vector{PolyShape},
                                    ps_pasillo::PolyShape, vec_floor_coords::Vector{Float64},
                                    is_vertical::Bool, franja1_outbound::Bool, get_max_outbound::Bool)

    outbound_terraces = franja1_outbound ? vec_terrazas1 : vec_terrazas2
    inbound_terraces = franja1_outbound ? vec_terrazas2 : vec_terrazas1
    inbound_deptos = franja1_outbound ? vec_ps_deptos_franja_2 : vec_ps_deptos_franja_1

    outbound_coord = get_terrace_bounds(outbound_terraces, is_vertical, get_max_outbound)
    outbound_coord === nothing && return vec_ps_deptos_franja_1, vec_ps_deptos_franja_2, vec_terrazas1, vec_terrazas2, ps_pasillo

    floor_min, floor_max = get_floor_bounds(vec_floor_coords)
    target_coord = get_max_outbound ? floor_max : floor_min
    delta = abs(outbound_coord - target_coord)

    inbound_outermost = get_strip_outermost_extent(inbound_deptos, inbound_terraces, is_vertical, !get_max_outbound)
    if inbound_outermost !== nothing
        inbound_limit = get_max_outbound ? floor_min : floor_max
        max_safe_delta = abs(inbound_outermost - inbound_limit)
        delta = min(delta, max_safe_delta)
    end

    if delta > 0.0
        shift_franja = get_max_outbound ? (is_vertical ? :oeste : :sur) : (is_vertical ? :este : :norte)
        return apply_terrace_correction(vec_ps_deptos_franja_1, vec_ps_deptos_franja_2, vec_terrazas1, vec_terrazas2,
                                    ps_pasillo, delta, is_vertical, shift_franja)
    end

    return vec_ps_deptos_franja_1, vec_ps_deptos_franja_2, vec_terrazas1, vec_terrazas2, ps_pasillo
end

# ──────────────────────────────────────────────────────────────────────────────────
# Floor normalization and distribution helpers
# ──────────────────────────────────────────────────────────────────────────────────

# Rotates floor plan to axis-aligned rectangle with width > height, returns dimensions and transformation
function normaliza_planta_rectangular(ps_planta::PolyShape)
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

# Calculates strip widths from areas and floor dimensions, scales if exceeding available space
function calcula_dimensiones_franjas(area_franja1::Float64, area_franja2::Float64, W::Float64, H::Float64, 
                                    ancho_pasillo::Float64, dimension_terraza_max::Float64, is_vertical::Bool)
    MIN_PROFUNDIDAD_FRANJA = 1.0

    if is_vertical
        ancho_franja = W - 2 * dimension_terraza_max - ancho_pasillo
        profundidad_franja1_requerida = area_franja1 / H
        profundidad_franja2_requerida = area_franja2 / H
    else
        ancho_franja = H - 2 * dimension_terraza_max - ancho_pasillo
        profundidad_franja1_requerida = area_franja1 / W
        profundidad_franja2_requerida = area_franja2 / W
    end

    if area_franja1 <= 0.0 && area_franja2 <= 0.0
        return 0.0, 0.0
    end

    if area_franja1 <= 0.0
        profundidad_franja1 = 0.0
        profundidad_franja2 = min(profundidad_franja2_requerida, ancho_franja)
    elseif area_franja2 <= 0.0
        profundidad_franja2 = 0.0
        profundidad_franja1 = min(profundidad_franja1_requerida, ancho_franja)
    else
        if profundidad_franja1_requerida + profundidad_franja2_requerida > ancho_franja
            scale_factor = ancho_franja / (profundidad_franja1_requerida + profundidad_franja2_requerida)

        else
            scale_factor = 1.0
        end
        profundidad_franja1 = profundidad_franja1_requerida * scale_factor
        profundidad_franja2 = profundidad_franja2_requerida * scale_factor
    end

    if profundidad_franja1 > 0.0 && profundidad_franja1 < MIN_PROFUNDIDAD_FRANJA
        profundidad_franja1 = MIN_PROFUNDIDAD_FRANJA
    end
    if profundidad_franja2 > 0.0 && profundidad_franja2 < MIN_PROFUNDIDAD_FRANJA
        profundidad_franja2 = MIN_PROFUNDIDAD_FRANJA
    end

    return profundidad_franja1, profundidad_franja2
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
                    ancho_pasillo::Float64, is_vertical::Bool, W::Float64, H::Float64, coord_min::Float64,
                    min_largo_pasillo::Float64, vec_tipo_deptos1::Vector{Int},
                    vec_tipo_deptos2::Vector{Int}, ancho_escala, area_escala)

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
    largo_pasillo = coord_fin_pasillo - coord_ini_pasillo

    if largo_pasillo < min_largo_pasillo
        centro_pasillo = (coord_ini_pasillo + coord_fin_pasillo) / 2
        coord_ini_pasillo = centro_pasillo - min_largo_pasillo / 2
        coord_fin_pasillo = centro_pasillo + min_largo_pasillo / 2
        largo_pasillo = min_largo_pasillo
    end

    dimension_planta = is_vertical ? H : W
    centro_planta = coord_min + dimension_planta / 2

    if num_deptos_total == 2
        coord_ini_pasillo = centro_planta - largo_pasillo / 2
        coord_fin_pasillo = centro_planta + largo_pasillo / 2
    else
        if centro_planta < coord_ini_pasillo
            coord_ini_pasillo = centro_planta
        elseif centro_planta > coord_fin_pasillo
            coord_fin_pasillo = centro_planta
        end
    end

    largo_pasillo = coord_fin_pasillo - coord_ini_pasillo

    coord_pasillo = coord_base - ancho_pasillo / 2

    if is_vertical
        ps_pasillo = polyShape.polyBox(coord_pasillo, coord_ini_pasillo, ancho_pasillo, largo_pasillo, 0.0)
        x_centroide = coord_base
        y_centroide = (coord_ini_pasillo + coord_fin_pasillo) / 2
    else
        ps_pasillo = polyShape.polyBox(coord_ini_pasillo, coord_pasillo, largo_pasillo, ancho_pasillo, 0.0)
        x_centroide = (coord_ini_pasillo + coord_fin_pasillo) / 2
        y_centroide = coord_base
    end

    largo_escala = area_escala / ancho_escala

    if is_vertical
        ps_escala = polyShape.polyBox(x_centroide - (largo_escala + ancho_pasillo) / 2, y_centroide - ancho_escala / 2, largo_escala + ancho_pasillo, ancho_escala, 0.0)
    else
        ps_escala = polyShape.polyBox(x_centroide - ancho_escala / 2, y_centroide - (largo_escala + ancho_pasillo) / 2, ancho_escala, largo_escala + ancho_pasillo, 0.0)
    end
    ps_pasillo = polyShape.polyUnion(ps_pasillo, ps_escala)            

    return coord_ini_pasillo, coord_fin_pasillo, largo_pasillo, ps_pasillo
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
                    W::Float64, H::Float64, ancho_pasillo::Float64, largo_pasillo::Float64, ps_pasillo::PolyShape,
                    vec_ps_deptos_franja_1::Vector{PolyShape}, vec_ps_deptos_franja_2::Vector{PolyShape},
                    vec_tipo_deptos1::Vector{Int}, vec_dimension_deptos2::Vector{Float64}, vec_tipo_deptos2::Vector{Int},
                    vec_terrazas1::Vector{PolyShape}, vec_terrazas2::Vector{PolyShape}, is_vertical::Bool,
                    ps_planta::PolyShape)
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
        "ancho_pasillo" => ancho_pasillo,
        "largo_pasillo" => largo_pasillo,
        "ps_pasillo" => ps_pasillo
    )

    vec_orientaciones1 = fill(1, length(vec_ps_deptos_franja_1))
    vec_orientaciones2 = fill(2, length(vec_ps_deptos_franja_2))

    result["vec_ps_deptos_all"] = vcat(vec_ps_deptos_franja_1, vec_ps_deptos_franja_2)
    result["vec_ps_terrazas_all"] = vcat(vec_terrazas1, vec_terrazas2)
    result["vec_orientaciones_all"] = vcat(vec_orientaciones1, vec_orientaciones2)

    shape_analysis = analiza_forma_apartamentos(vec_ps_deptos_franja_1, vec_ps_deptos_franja_2)

    result["max_depto_square_deviation"] = round(shape_analysis, digits=3)

    ps_union_all = polyShape.polyUnion(ps_pasillo)
    for ps_apt in result["vec_ps_deptos_all"]
        ps_union_all = polyShape.polyUnion(ps_union_all, ps_apt)
    end
    for ps_terr in result["vec_ps_terrazas_all"]
        if polyShape.polyArea(ps_terr) > 0.0
            ps_union_all = polyShape.polyUnion(ps_union_all, ps_terr)
        end
    end

    ps_outbound = polyShape.polyDifference(ps_union_all, ps_planta)
    area_outbound = polyShape.polyArea(ps_outbound)
    result["area_outbound"] = round(area_outbound, digits=2)

    return result
end

# Checks if all terraces are fully contained within floor plan boundaries
function verifica_inscripcion_terrazas(ps_planta::PolyShape, vec_terrazas::Vector{PolyShape})
    for terraza in vec_terrazas
        inters = polyShape.polyIntersection(ps_planta, terraza)
        area_inters = polyShape.polyArea(inters)
        area_terraza = polyShape.polyArea(terraza)
        if abs(area_inters - area_terraza) > INTERSECTION_TOLERANCE
            return false
        end
    end

    return true
end

# ──────────────────────────────────────────────────────────────────────────────────
# High-level computation functions
# ──────────────────────────────────────────────────────────────────────────────────

# Prepares normalized floor plan, distributes apartments, and calculates strip dimensions
# function prepare_floor_inputs(ps_planta::PolyShape, vec_sup_deptos::Vector{Float64}, vec_num_deptos::Vector{Int}, stair_cfg::StairConfig, corridor_cfg::CorridorConfig, is_vertical::Bool, terrace_cfg::TerraceConfig, vec_tipo_original_indices::Vector{Int})
function prepare_floor_inputs(dict_edificio_deptos, ps_planta)

end




# Main floor plan optimization function: distributes apartments in two strips with corridor and terraces
function genera_layout_pisos_superiores(ps_planta::PolyShape, dict_edificio_deptos;
                        ancho_pasillo::Float64 = 2.0,
                        min_largo_pasillo::Float64 = 0.0,
                        area_escala::Float64 = 25.0,
                        min_ancho_escala::Float64 = 0.0,
                        min_ancho_depto::Float64 = 4.0,
                        max_ancho_terraza::Float64 = 2.0,
                        layout::Symbol = :ns)

    best_layout = dict_edificio_deptos["best_layout"]
    is_vertical = (best_layout == 2)

    ps_planta_normalizado = dict_edificio_deptos["ps_planta_normalizado"]
    angulo_rotacion = dict_edificio_deptos["angulo_rotacion"]
    cr = dict_edificio_deptos["cr"]

    V_planta_normalizado = ps_planta_normalizado.Vertices[1]
    vec_x_planta = V_planta_normalizado[:, 1]
    vec_y_planta = V_planta_normalizado[:, 2]
    W = maximum(vec_x_planta) - minimum(vec_x_planta)
    H = maximum(vec_y_planta) - minimum(vec_y_planta)

    # ══════════════════════════════════════════════════════════════════════════════════
    # MAIN EXECUTION LOGIC
    # ══════════════════════════════════════════════════════════════════════════════════

    df_deptos_resumen = combine(
        groupby(dict_edificio_deptos["df_deptos"], [:strip, :sup_interior, :sup_terraza, :ancho_interior, :profundidad_interior, :num_unidades_por_piso_superior, :num_unidades_primer_piso]),
        :num_unidades_edificio => sum => :num_unidades_edificio)

    # ──────────────────────────────────────────────────────────────────────────────────
    # Stage 2: Strip geometry computation
    # ──────────────────────────────────────────────────────────────────────────────────
    coord_min_x = minimum(vec_x_planta)
    coord_min_y = minimum(vec_y_planta)

    H_s_strip1 = dict_edificio_deptos["strip"][1]["H_s"]
    H_s_strip2 = dict_edificio_deptos["strip"][2]["H_s"]

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

    df_deptos_strip1 = filter(row -> row.strip == 1, df_deptos_resumen)
    mat_deptos_strip1 = Matrix{Float64}(undef, 0, 3)
    for row in eachrow(df_deptos_strip1)
        n_repeat = Int(round(row.num_unidades_por_piso_superior))
        for _ in 1:n_repeat
            mat_deptos_strip1 = vcat(mat_deptos_strip1, [row.sup_interior row.ancho_interior row.profundidad_interior])
        end
    end

    df_deptos_strip2 = filter(row -> row.strip == 2, df_deptos_resumen)
    mat_deptos_strip2 = Matrix{Float64}(undef, 0, 3)
    for row in eachrow(df_deptos_strip2)
        n_repeat = Int(round(row.num_unidades_por_piso_superior))
        for _ in 1:n_repeat
            mat_deptos_strip2 = vcat(mat_deptos_strip2, [row.sup_interior row.ancho_interior row.profundidad_interior])
        end
    end

    vec_coord_ini1, vec_coord_fin1, vec_dimension1_deptos1, vec_dimension2_deptos1, vec_tipo_deptos1,
            vec_ps_deptos_franja_1_normalizado = genera_deptos_franja(mat_deptos_strip1, coord_min,
                                            dimension_depto1, coord_disponible, min_ancho_escala,
                                            min_ancho_depto, is_vertical, coord_base, franja1)

    vec_coord_ini2, vec_coord_fin2, vec_dimension1_deptos2, vec_dimension2_deptos2, vec_tipo_deptos2,
            vec_ps_deptos_franja_2_normalizado = genera_deptos_franja(mat_deptos_strip2, coord_min,
                                            dimension_depto2, coord_disponible, min_ancho_escala,
                                            min_ancho_depto, is_vertical, coord_base, franja2)

    coord_ini_pasillo, coord_fin_pasillo, largo_pasillo, ps_pasillo_normalizado = calcula_geometria_pasillo(
                                            vec_coord_fin1, vec_coord_fin2, vec_coord_ini1, vec_coord_ini2,
                                            coord_base, ancho_pasillo, is_vertical,
                                            W, H,
                                            coord_min, min_largo_pasillo,
                                            vec_tipo_deptos1, vec_tipo_deptos2,
                                            min_ancho_escala, area_escala)

    vec_ps_deptos_franja_1_normalizado, vec_extension_dimension1_1 = extiende_deptos_con_interseccion_pasillo(vec_coord_ini1, vec_coord_fin1, vec_dimension1_deptos1, vec_dimension2_deptos1, coord_base, ps_pasillo_normalizado, franja1, is_vertical, vec_ps_deptos_franja_1_normalizado, ps_pasillo_normalizado)
    vec_ps_deptos_franja_2_normalizado, vec_extension_dimension1_2 = extiende_deptos_con_interseccion_pasillo(vec_coord_ini2, vec_coord_fin2, vec_dimension1_deptos2, vec_dimension2_deptos2, coord_base, ps_pasillo_normalizado, franja2, is_vertical, vec_ps_deptos_franja_2_normalizado, ps_pasillo_normalizado)

    deptos_ordenados1 = [(mat_deptos_strip1[i, 1], 0) for i in 1:size(mat_deptos_strip1, 1)]
    deptos_ordenados2 = [(mat_deptos_strip2[i, 1], 0) for i in 1:size(mat_deptos_strip2, 1)]

    planta_normalizada = (
        deptos_ordenados1 = deptos_ordenados1,
        deptos_ordenados2 = deptos_ordenados2,
        dimension_terraza_max = max_ancho_terraza,
        ps_planta_normalizado = ps_planta_normalizado,
        vec_x_planta = vec_x_planta,
        vec_y_planta = vec_y_planta,
        W = W,
        H = H
    )

    vec_terrazas_areas_strip1 = Float64[]
    for row in eachrow(df_deptos_strip1)
        n_repeat = Int(round(row.num_unidades_por_piso_superior))
        for _ in 1:n_repeat
            push!(vec_terrazas_areas_strip1, row.sup_terraza)
        end
    end

    vec_terrazas_areas_strip2 = Float64[]
    for row in eachrow(df_deptos_strip2)
        n_repeat = Int(round(row.num_unidades_por_piso_superior))
        for _ in 1:n_repeat
            push!(vec_terrazas_areas_strip2, row.sup_terraza)
        end
    end

    vec_terrazas_strip1, vec_terrazas_strip2, vec_ps_deptos_franja_1_normalizado, vec_ps_deptos_franja_2_normalizado, ps_pasillo_normalizado =
            procesa_terrazas_ambas_franjas(vec_terrazas_areas_strip1, vec_terrazas_areas_strip2, planta_normalizada,
                                        vec_dimension1_deptos1, vec_dimension1_deptos2,
                                        vec_dimension2_deptos1, vec_dimension2_deptos2,
                                        vec_coord_ini1, vec_coord_ini2,
                                        vec_extension_dimension1_1, vec_extension_dimension1_2,
                                        coord_base, franja1, franja2,
                                        is_vertical, vec_ps_deptos_franja_1_normalizado,
                                        vec_ps_deptos_franja_2_normalizado, ps_pasillo_normalizado)

    franjas_computadas = (vec_ps_deptos_strip1_normalizado=vec_ps_deptos_franja_1_normalizado, vec_ps_deptos_strip2_normalizado=vec_ps_deptos_franja_2_normalizado,
            vec_terrazas_strip1=vec_terrazas_strip1, vec_terrazas_strip2=vec_terrazas_strip2,
            ps_pasillo_normalizado=ps_pasillo_normalizado, largo_pasillo=largo_pasillo,
            vec_dimension2_deptos_strip2=vec_dimension2_deptos2, vec_tipo_deptos_strip2=vec_tipo_deptos2)

    # ──────────────────────────────────────────────────────────────────────────────────
    # Stage 3: Rotation back to original coordinates
    # ──────────────────────────────────────────────────────────────────────────────────
    vec_ps_deptos_strip1 = rota_polyshapes(franjas_computadas.vec_ps_deptos_strip1_normalizado, angulo_rotacion, cr)
    vec_ps_deptos_strip2 = rota_polyshapes(franjas_computadas.vec_ps_deptos_strip2_normalizado, angulo_rotacion, cr)
    vec_terrazas_strip1 = rota_polyshapes(franjas_computadas.vec_terrazas_strip1, angulo_rotacion, cr)
    vec_terrazas_strip2 = rota_polyshapes(franjas_computadas.vec_terrazas_strip2, angulo_rotacion, cr)
    ps_pasillo = polyShape.polyRotate(franjas_computadas.ps_pasillo_normalizado, -angulo_rotacion, cr)

    # ──────────────────────────────────────────────────────────────────────────────────
    # Stage 4: Results packaging
    # ──────────────────────────────────────────────────────────────────────────────────
    ps_planta = dict_edificio_deptos["ps_planta"]

    results = empaqueta_resultados(dimension_depto1, dimension_depto2, W, H, ancho_pasillo, franjas_computadas.largo_pasillo, ps_pasillo,
                                    vec_ps_deptos_strip1, vec_ps_deptos_strip2, vec_tipo_deptos1, franjas_computadas.vec_dimension2_deptos_strip2, franjas_computadas.vec_tipo_deptos_strip2,
                                    vec_terrazas_strip1, vec_terrazas_strip2, is_vertical, ps_planta)

    vec_ps_deptos_all = results["vec_ps_deptos_all"]
    ps_union_deptos = PolyShape[]
    if !isempty(vec_ps_deptos_all)
        buffer_deptos = 0.2
        buffered_apts = [polyClipper.polyOffset(ps, buffer_deptos) for ps in vec_ps_deptos_all]
        ps_union_deptos = buffered_apts[1]
        for i in eachindex(buffered_apts)[2:end]
            ps_union_deptos = polyShape.polyUnion(ps_union_deptos, buffered_apts[i])
        end
        delta = 0.02
        ps_union_deptos = polyClipper.polyOffset(ps_union_deptos, delta)
        ps_union_deptos = polyClipper.polyOffset(ps_union_deptos, -buffer_deptos - delta)
    end
    results["ps_union_deptos"] = ps_union_deptos

    vec_ps_terrazas_all = results["vec_ps_terrazas_all"]
    ps_union_terrazas = PolyShape[]
    if !isempty(vec_ps_terrazas_all)
        valid_terrazas = [ps for ps in vec_ps_terrazas_all if polyShape.polyArea(ps) > 0.0]
        if !isempty(valid_terrazas)
            buffer_terrazas = 0.2
            buffered_terrazas = [polyClipper.polyOffset(ps, buffer_terrazas) for ps in valid_terrazas]
            ps_union_terrazas = buffered_terrazas[1]
            for i in eachindex(buffered_terrazas)[2:end]
                ps_union_terrazas = polyShape.polyUnion(ps_union_terrazas, buffered_terrazas[i])
            end
            delta = 0.02
            ps_union_terrazas = polyClipper.polyOffset(ps_union_terrazas, delta)
            ps_union_terrazas = polyClipper.polyOffset(ps_union_terrazas, -buffer_terrazas - delta)
        end
    end
    results["ps_union_terrazas"] = ps_union_terrazas

    ps_area_comun_total = ps_pasillo
    delta = 0.02
    ps_area_comun_total = polyClipper.polyOffset(ps_area_comun_total, delta)
    ps_area_comun_total = polyClipper.polyOffset(ps_area_comun_total, -delta)
    results["ps_area_comun_total"] = ps_area_comun_total

    if !isempty(vec_ps_deptos_all) && polyShape.polyArea(ps_union_deptos) > 0.0
        vec_apartamentos_orientaciones = calcula_orientaciones_apartamentos(vec_ps_deptos_all, ps_union_deptos, ps_area_comun_total)
        results["vec_apartamentos_orientaciones"] = vec_apartamentos_orientaciones
    else
        results["vec_apartamentos_orientaciones"] = Vector{Dict}()
    end

    return results
end


function genera_layout_primer_piso(dict_edificio_deptos, ps_planta::PolyShape;
                        ancho_pasillo::Float64 = 2.0,
                        min_largo_pasillo::Float64 = 0.0,
                        area_escala::Float64 = 25.0,
                        min_ancho_escala::Float64 = 0.0,
                        min_ancho_depto::Float64 = 4.0,
                        max_ancho_terraza::Float64 = 2.0)

    best_layout = dict_edificio_deptos["best_layout"]
    is_vertical = (best_layout == 2)

    ps_planta_normalizado = dict_edificio_deptos["ps_planta_normalizado"]
    angulo_rotacion = dict_edificio_deptos["angulo_rotacion"]
    cr = dict_edificio_deptos["cr"]

    V_planta_normalizado = ps_planta_normalizado.Vertices[1]
    vec_x_planta = V_planta_normalizado[:, 1]
    vec_y_planta = V_planta_normalizado[:, 2]
    W = maximum(vec_x_planta) - minimum(vec_x_planta)
    H = maximum(vec_y_planta) - minimum(vec_y_planta)

    df_deptos = dict_edificio_deptos["df_deptos"]

    df_deptos_resumen = combine(
        groupby(df_deptos, [:strip, :sup_interior, :sup_terraza, :ancho_interior, :profundidad_interior, :num_unidades_por_piso_superior, :num_unidades_primer_piso]),
        :num_unidades_edificio => sum => :num_unidades_edificio)

    coord_min_x = minimum(vec_x_planta)
    coord_min_y = minimum(vec_y_planta)

    H_s_strip1 = dict_edificio_deptos["strip"][1]["H_s"]
    H_s_strip2 = dict_edificio_deptos["strip"][2]["H_s"]

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

    df_deptos_strip1 = filter(row -> row.strip == 1, df_deptos_resumen)
    mat_deptos_strip1 = Matrix{Float64}(undef, 0, 3)
    for row in eachrow(df_deptos_strip1)
        n_repeat = Int(round(row.num_unidades_primer_piso))
        for _ in 1:n_repeat
            mat_deptos_strip1 = vcat(mat_deptos_strip1, [row.sup_interior row.ancho_interior row.profundidad_interior])
        end
    end

    df_deptos_strip2 = filter(row -> row.strip == 2, df_deptos_resumen)
    mat_deptos_strip2 = Matrix{Float64}(undef, 0, 3)
    for row in eachrow(df_deptos_strip2)
        n_repeat = Int(round(row.num_unidades_primer_piso))
        for _ in 1:n_repeat
            mat_deptos_strip2 = vcat(mat_deptos_strip2, [row.sup_interior row.ancho_interior row.profundidad_interior])
        end
    end

    vec_coord_ini1, vec_coord_fin1, vec_dimension1_deptos1, vec_dimension2_deptos1, vec_tipo_deptos1,
            vec_ps_deptos_franja_1_normalizado = genera_deptos_franja(mat_deptos_strip1, coord_min,
                                            dimension_depto1, coord_disponible, min_ancho_escala,
                                            min_ancho_depto, is_vertical, coord_base, franja1)

    vec_coord_ini2, vec_coord_fin2, vec_dimension1_deptos2, vec_dimension2_deptos2, vec_tipo_deptos2,
            vec_ps_deptos_franja_2_normalizado = genera_deptos_franja(mat_deptos_strip2, coord_min,
                                            dimension_depto2, coord_disponible, min_ancho_escala,
                                            min_ancho_depto, is_vertical, coord_base, franja2)

    coord_ini_pasillo, coord_fin_pasillo, largo_pasillo, ps_pasillo_normalizado = calcula_geometria_pasillo(
                                            vec_coord_fin1, vec_coord_fin2, vec_coord_ini1, vec_coord_ini2,
                                            coord_base, ancho_pasillo, is_vertical,
                                            W, H,
                                            coord_min, min_largo_pasillo,
                                            vec_tipo_deptos1, vec_tipo_deptos2,
                                            min_ancho_escala, area_escala)

    vec_ps_deptos_franja_1_normalizado, vec_extension_dimension1_1 = extiende_deptos_con_interseccion_pasillo(vec_coord_ini1, vec_coord_fin1, vec_dimension1_deptos1, vec_dimension2_deptos1, coord_base, ps_pasillo_normalizado, franja1, is_vertical, vec_ps_deptos_franja_1_normalizado, ps_pasillo_normalizado)
    vec_ps_deptos_franja_2_normalizado, vec_extension_dimension1_2 = extiende_deptos_con_interseccion_pasillo(vec_coord_ini2, vec_coord_fin2, vec_dimension1_deptos2, vec_dimension2_deptos2, coord_base, ps_pasillo_normalizado, franja2, is_vertical, vec_ps_deptos_franja_2_normalizado, ps_pasillo_normalizado)

    deptos_ordenados1 = [(mat_deptos_strip1[i, 1], 0) for i in 1:size(mat_deptos_strip1, 1)]
    deptos_ordenados2 = [(mat_deptos_strip2[i, 1], 0) for i in 1:size(mat_deptos_strip2, 1)]

    planta_normalizada = (
        deptos_ordenados1 = deptos_ordenados1,
        deptos_ordenados2 = deptos_ordenados2,
        dimension_terraza_max = max_ancho_terraza,
        ps_planta_normalizado = ps_planta_normalizado,
        vec_x_planta = vec_x_planta,
        vec_y_planta = vec_y_planta,
        W = W,
        H = H
    )

    vec_terrazas_areas_strip1 = Float64[]
    for row in eachrow(df_deptos_strip1)
        n_repeat = Int(round(row.num_unidades_primer_piso))
        for _ in 1:n_repeat
            push!(vec_terrazas_areas_strip1, row.sup_terraza)
        end
    end

    vec_terrazas_areas_strip2 = Float64[]
    for row in eachrow(df_deptos_strip2)
        n_repeat = Int(round(row.num_unidades_primer_piso))
        for _ in 1:n_repeat
            push!(vec_terrazas_areas_strip2, row.sup_terraza)
        end
    end

    vec_terrazas_strip1, vec_terrazas_strip2, vec_ps_deptos_franja_1_normalizado, vec_ps_deptos_franja_2_normalizado, ps_pasillo_normalizado =
            procesa_terrazas_ambas_franjas(vec_terrazas_areas_strip1, vec_terrazas_areas_strip2, planta_normalizada,
                                        vec_dimension1_deptos1, vec_dimension1_deptos2,
                                        vec_dimension2_deptos1, vec_dimension2_deptos2,
                                        vec_coord_ini1, vec_coord_ini2,
                                        vec_extension_dimension1_1, vec_extension_dimension1_2,
                                        coord_base, franja1, franja2,
                                        is_vertical, vec_ps_deptos_franja_1_normalizado,
                                        vec_ps_deptos_franja_2_normalizado, ps_pasillo_normalizado)

    vec_ps_deptos_strip1 = rota_polyshapes(vec_ps_deptos_franja_1_normalizado, angulo_rotacion, cr)
    vec_ps_deptos_strip2 = rota_polyshapes(vec_ps_deptos_franja_2_normalizado, angulo_rotacion, cr)
    vec_terrazas_strip1 = rota_polyshapes(vec_terrazas_strip1, angulo_rotacion, cr)
    vec_terrazas_strip2 = rota_polyshapes(vec_terrazas_strip2, angulo_rotacion, cr)
    ps_pasillo = polyShape.polyRotate(ps_pasillo_normalizado, -angulo_rotacion, cr)

    vec_orientaciones1 = fill(1, length(vec_ps_deptos_strip1))
    vec_orientaciones2 = fill(2, length(vec_ps_deptos_strip2))

    vec_ps_deptos_all = vcat(vec_ps_deptos_strip1, vec_ps_deptos_strip2)
    vec_ps_terrazas_all = vcat(vec_terrazas_strip1, vec_terrazas_strip2)
    vec_orientaciones_all = vcat(vec_orientaciones1, vec_orientaciones2)

    delta = 0.02

    ps_union_deptos = PolyShape[]
    if !isempty(vec_ps_deptos_all)
        buffer_deptos = 0.2
        buffered_apts = [polyClipper.polyOffset(ps, buffer_deptos) for ps in vec_ps_deptos_all]
        ps_union_deptos = buffered_apts[1]
        for i in eachindex(buffered_apts)[2:end]
            ps_union_deptos = polyShape.polyUnion(ps_union_deptos, buffered_apts[i])
        end
        ps_union_deptos = polyClipper.polyOffset(ps_union_deptos, delta)
        ps_union_deptos = polyClipper.polyOffset(ps_union_deptos, -buffer_deptos - delta)
    end

    ps_union_terrazas = PolyShape[]
    if !isempty(vec_ps_terrazas_all)
        valid_terrazas = [ps for ps in vec_ps_terrazas_all if polyShape.polyArea(ps) > 0.0]
        if !isempty(valid_terrazas)
            buffer_terrazas = 0.2
            buffered_terrazas = [polyClipper.polyOffset(ps, buffer_terrazas) for ps in valid_terrazas]
            ps_union_terrazas = buffered_terrazas[1]
            for i in eachindex(buffered_terrazas)[2:end]
                ps_union_terrazas = polyShape.polyUnion(ps_union_terrazas, buffered_terrazas[i])
            end
            ps_union_terrazas = polyClipper.polyOffset(ps_union_terrazas, delta)
            ps_union_terrazas = polyClipper.polyOffset(ps_union_terrazas, -buffer_terrazas - delta)
        end
    end

    ps_planta_primer_piso = polyShape.polyUnion(ps_pasillo)
    for ps_apt in vec_ps_deptos_all
        ps_planta_primer_piso = polyShape.polyUnion(ps_planta_primer_piso, ps_apt)
    end
    ps_planta_primer_piso = polyClipper.polyOffset(ps_planta_primer_piso, delta)
    ps_planta_primer_piso = polyClipper.polyOffset(ps_planta_primer_piso, -delta)

    ps_union_ocupado = polyShape.polyUnion(ps_pasillo)
    for ps_apt in vec_ps_deptos_all
        ps_union_ocupado = polyShape.polyUnion(ps_union_ocupado, ps_apt)
    end
    for ps_terr in vec_ps_terrazas_all
        if polyShape.polyArea(ps_terr) > 0.0
            ps_union_ocupado = polyShape.polyUnion(ps_union_ocupado, ps_terr)
        end
    end
    ps_union_ocupado = polyClipper.polyOffset(ps_union_ocupado, delta)
    ps_union_ocupado = polyClipper.polyOffset(ps_union_ocupado, -delta)

    ps_area_comun = polyShape.polyDifference(ps_planta_primer_piso, ps_union_ocupado)
    area_comun = polyShape.polyArea(ps_area_comun)

    ps_area_comun_total = ps_pasillo
    if polyShape.polyArea(ps_area_comun) > 0.0
        ps_area_comun_total = polyShape.polyUnion(ps_area_comun_total, ps_area_comun)
    end
    ps_area_comun_total = polyClipper.polyOffset(ps_area_comun_total, delta)
    ps_area_comun_total = polyClipper.polyOffset(ps_area_comun_total, -delta)

    return Dict(
        "vec_ps_deptos_all" => vec_ps_deptos_all,
        "vec_ps_terrazas_all" => vec_ps_terrazas_all,
        "vec_orientaciones_all" => vec_orientaciones_all,
        "ps_area_comun" => ps_area_comun,
        "area_comun" => round(area_comun, digits=2),
        "ps_pasillo" => ps_pasillo,
        "ps_planta" => ps_planta_primer_piso,
        "ps_area_comun_total" => ps_area_comun_total,
        "ps_union_deptos" => ps_union_deptos,
        "ps_union_terrazas" => ps_union_terrazas
    )
end

function opti_floor_plan(dict_arquitectura, ps_planta, dict_edificio_deptos;
                        ancho_pasillo::Float64 = 2.0,
                        min_largo_pasillo::Float64 = 0.0,
                        area_escala::Float64 = 25.0,
                        min_ancho_escala::Float64 = 0.0,
                        min_ancho_depto::Float64 = 4.0,
                        max_ancho_terraza::Float64 = 2.0)

    if dict_edificio_deptos["best_layout"] == 1
        layout = :ns
    else
        layout = :oe
    end

    results_ = genera_layout_pisos_superiores(ps_planta, dict_edificio_deptos,
                ancho_pasillo=ancho_pasillo,
                min_largo_pasillo=min_largo_pasillo,
                area_escala=area_escala,
                min_ancho_escala=min_ancho_escala,
                min_ancho_depto=min_ancho_depto,
                max_ancho_terraza=max_ancho_terraza,
                layout=layout)

    results_pisos_superiores = results_

    if isnothing(results_pisos_superiores)
        error("No feasible floor plan configuration found")
    end

    df_deptos = dict_edificio_deptos["df_deptos"]

    df_deptos_con_primer_piso = filter(row -> row.num_unidades_primer_piso > 0, df_deptos)

    if nrow(df_deptos_con_primer_piso) > 0
        results_primer_piso = genera_layout_primer_piso(dict_edificio_deptos, ps_planta,
                                ancho_pasillo=ancho_pasillo,
                                min_largo_pasillo=min_largo_pasillo,
                                area_escala=area_escala,
                                min_ancho_escala=min_ancho_escala,
                                min_ancho_depto=min_ancho_depto,
                                max_ancho_terraza=max_ancho_terraza)
    else
        results_primer_piso = nothing
    end

    return Dict(
        "pisos_superiores" => results_pisos_superiores,
        "primer_piso" => results_primer_piso
    )
end
