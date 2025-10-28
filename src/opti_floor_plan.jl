const CONVERGENCE_TOLERANCE = 0.005
const INTERSECTION_TOLERANCE = 0.1
const TERRACE_ASPECT_RATIO = 1.75
const MAX_ADJUSTMENT_ITERATIONS = 10

struct CorridorConfig
    ancho_pasillo::Float64
    min_largo_pasillo::Float64
    pasillo_centrado::Bool
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

# Main floor plan optimization function: distributes apartments in two strips with corridor and terraces
function opti_floor_plan(ps_planta::PolyShape, vec_sup_deptos::Vector{Float64}, vec_num_deptos::Vector{Int};
                        vec_sup_terraza::Vector{Float64} = Float64[],
                        ancho_pasillo::Float64 = 2.0,
                        min_largo_pasillo::Float64 = 0.0,
                        pasillo_centrado::Bool = false,
                        area_escala::Float64 = 25.0,
                        min_ancho_escala::Float64 = 0.0,
                        max_ancho_terraza::Float64 = 2.0,
                        tipo_escala::Symbol = :exterior,
                        layout::Symbol = :ns,
                        balance_mode::Symbol = :heuristic)

    is_vertical = (layout == :oe)

    tipo_escala in [:exterior, :interior, :none] || error("tipo_escala must be :exterior, :interior, or :none")

    corridor_cfg = CorridorConfig(ancho_pasillo, min_largo_pasillo, pasillo_centrado)
    stair_cfg = StairConfig(area_escala, min_ancho_escala, tipo_escala)
    terrace_cfg = TerraceConfig(vec_sup_terraza, max_ancho_terraza)

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

    # Generates apartment geometries along one strip, adjusting dimensions iteratively to fit available space
    function genera_deptos_franja(vec_orden_deptos::Vector{Tuple{Float64, Int}}, coord_min_planta::Float64, dimension_franja::Float64, dimension_disponible::Float64, min_ancho_escala::Float64, is_vertical::Bool, coord_base::Float64, franja::Symbol)
        vec_coord_ini = Float64[]
        vec_coord_fin = Float64[]
        vec_dimension1_deptos = Float64[]
        vec_dimension2_deptos = Float64[]
        vec_tipo_deptos = Int[]

        dimension_franja_adjusted = dimension_franja

        for _ in 1:MAX_ADJUSTMENT_ITERATIONS
            empty!(vec_coord_ini)
            empty!(vec_coord_fin)
            empty!(vec_dimension1_deptos)
            empty!(vec_dimension2_deptos)
            empty!(vec_tipo_deptos)

            coord_current = coord_min_planta
            total_dimension = 0.0

            for depto in vec_orden_deptos
                sup_depto = get_area(depto)
                tipo_depto = get_tipo(depto)
                if tipo_depto == -1
                    dim2 = sup_depto / dimension_franja_adjusted
                    if dim2 < min_ancho_escala
                        dim2 = min_ancho_escala
                        dim1 = sup_depto / dim2
                    else
                        dim1 = dimension_franja_adjusted
                    end
                else
                    dim2 = sup_depto / dimension_franja_adjusted
                    dim1 = dimension_franja_adjusted
                end

                push!(vec_coord_ini, coord_current)
                push!(vec_coord_fin, coord_current + dim2)
                push!(vec_dimension1_deptos, dim1)
                push!(vec_dimension2_deptos, dim2)
                push!(vec_tipo_deptos, tipo_depto)
                coord_current += dim2
                total_dimension += dim2
            end

            if abs(total_dimension - dimension_disponible) / dimension_disponible < CONVERGENCE_TOLERANCE
                break
            end

            dimension_franja_adjusted = dimension_franja_adjusted * (total_dimension / dimension_disponible)
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

        for i in eachindex(vec_coord_ini)
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
                area_terraza = vec_sup_terraza[tipo_depto]
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

    # Safely translates a polyshape, handling empty polyshapes
    function safe_translate(ps::PolyShape, dx::Float64, dy::Float64)
        if isempty(ps.Vertices) || polyShape.polyArea(ps) == 0.0
            return ps
        else
            return polyShape.polyTranslate(ps, dx, dy)
        end
    end

    # Creates axis-aligned box with franja-aware positioning (vertical: X-axis, horizontal: Y-axis)
    function polyBoxAligned(base1::Float64, base2::Float64, dim1::Float64, dim2::Float64, franja::Symbol, is_vertical::Bool)
        if is_vertical
            is_positive_franja = (franja == :este)
            offset = is_positive_franja ? base1 : base1 - dim1
            return polyShape.polyBox(offset, base2, dim1, dim2, 0.0)
        else
            is_positive_franja = (franja == :norte)
            offset = is_positive_franja ? base1 : base1 - dim1
            return polyShape.polyBox(base2, offset, dim2, dim1, 0.0)
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
    function apply_terrace_correction(vec_ps_deptos1::Vector{PolyShape}, vec_ps_deptos2::Vector{PolyShape},
                                     vec_terrazas1::Vector{PolyShape}, vec_terrazas2::Vector{PolyShape},
                                     ps_pasillo::PolyShape, delta::Float64, is_vertical::Bool, franja::Symbol)
        if is_vertical
            delta_x = (franja == :este) ? delta : -delta
            dx, dy = delta_x, 0.0
        else
            delta_y = (franja == :norte) ? delta : -delta
            dx, dy = 0.0, delta_y
        end

        return ([safe_translate(p, dx, dy) for p in vec_ps_deptos1],
                [safe_translate(p, dx, dy) for p in vec_ps_deptos2],
                [safe_translate(t, dx, dy) for t in vec_terrazas1],
                [safe_translate(t, dx, dy) for t in vec_terrazas2],
                safe_translate(ps_pasillo, dx, dy))
    end

    # Processes terraces for both strips including generation, verification, and correction
    function procesa_terrazas_ambas_franjas(vec_sup_terraza::Vector{Float64}, planta_normalizada,
                                             vec_dimension1_deptos1::Vector{Float64}, vec_dimension1_deptos2::Vector{Float64},
                                             vec_dimension2_deptos1::Vector{Float64}, vec_dimension2_deptos2::Vector{Float64},
                                             vec_coord_ini1::Vector{Float64}, vec_coord_ini2::Vector{Float64},
                                             vec_extension_dimension1_1::Vector{Float64}, vec_extension_dimension1_2::Vector{Float64},
                                             coord_base::Float64, franja1::Symbol, franja2::Symbol,
                                             is_vertical::Bool, vec_ps_deptos1_normalizado::Vector{PolyShape},
                                             vec_ps_deptos2_normalizado::Vector{PolyShape}, ps_pasillo_normalizado::PolyShape)

        coord_terrace_base1 = [coord_base + vec_dimension1_deptos1[i] + vec_extension_dimension1_1[i] for i in eachindex(planta_normalizada.deptos_ordenados1)]
        vec_terrazas1_normalizado = genera_terrazas_franja(planta_normalizada.deptos_ordenados1, vec_sup_terraza, vec_dimension2_deptos1, vec_coord_ini1, coord_terrace_base1, franja1, planta_normalizada.dimension_terraza_max, is_vertical)

        coord_terrace_base2 = [coord_base - vec_dimension1_deptos2[i] - vec_extension_dimension1_2[i] for i in eachindex(planta_normalizada.deptos_ordenados2)]
        vec_terrazas2_normalizado = genera_terrazas_franja(planta_normalizada.deptos_ordenados2, vec_sup_terraza, vec_dimension2_deptos2, vec_coord_ini2, coord_terrace_base2, franja2, planta_normalizada.dimension_terraza_max, is_vertical)

        flag_inscripcion1 = verifica_inscripcion_terrazas(planta_normalizada.ps_planta_normalizado, vec_terrazas1_normalizado)
        flag_inscripcion2 = verifica_inscripcion_terrazas(planta_normalizada.ps_planta_normalizado, vec_terrazas2_normalizado)

        if !flag_inscripcion1 && !flag_inscripcion2
            @warn "Both strips have outbound terraces - layout may not fit properly"
        end

        vec_floor_coords = is_vertical ? planta_normalizada.vec_x_planta : planta_normalizada.vec_y_planta

        if !flag_inscripcion1
            vec_ps_deptos1_normalizado, vec_ps_deptos2_normalizado, vec_terrazas1_normalizado, vec_terrazas2_normalizado, ps_pasillo_normalizado =
                correct_outbound_terraces(vec_terrazas1_normalizado, vec_terrazas2_normalizado,
                                            vec_ps_deptos1_normalizado, vec_ps_deptos2_normalizado,
                                            ps_pasillo_normalizado, vec_floor_coords, is_vertical, true, true)
        end
        if !flag_inscripcion2
            vec_ps_deptos1_normalizado, vec_ps_deptos2_normalizado, vec_terrazas1_normalizado, vec_terrazas2_normalizado, ps_pasillo_normalizado =
                correct_outbound_terraces(vec_terrazas1_normalizado, vec_terrazas2_normalizado,
                                            vec_ps_deptos1_normalizado, vec_ps_deptos2_normalizado,
                                            ps_pasillo_normalizado, vec_floor_coords, is_vertical, false, false)
        end

        return vec_terrazas1_normalizado, vec_terrazas2_normalizado, vec_ps_deptos1_normalizado, vec_ps_deptos2_normalizado, ps_pasillo_normalizado
    end

    # Corrects outbound terraces by shifting geometries; limits shift to prevent opposite side outbound
    function correct_outbound_terraces(vec_terrazas1::Vector{PolyShape}, vec_terrazas2::Vector{PolyShape},
                                       vec_ps_deptos1::Vector{PolyShape}, vec_ps_deptos2::Vector{PolyShape},
                                       ps_pasillo::PolyShape, vec_floor_coords::Vector{Float64},
                                       is_vertical::Bool, franja1_outbound::Bool, get_max_outbound::Bool)

        outbound_terraces = franja1_outbound ? vec_terrazas1 : vec_terrazas2
        inbound_terraces = franja1_outbound ? vec_terrazas2 : vec_terrazas1
        inbound_deptos = franja1_outbound ? vec_ps_deptos2 : vec_ps_deptos1

        outbound_coord = get_terrace_bounds(outbound_terraces, is_vertical, get_max_outbound)
        outbound_coord === nothing && return vec_ps_deptos1, vec_ps_deptos2, vec_terrazas1, vec_terrazas2, ps_pasillo

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
            return apply_terrace_correction(vec_ps_deptos1, vec_ps_deptos2, vec_terrazas1, vec_terrazas2,
                                       ps_pasillo, delta, is_vertical, shift_franja)
        end

        return vec_ps_deptos1, vec_ps_deptos2, vec_terrazas1, vec_terrazas2, ps_pasillo
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

    # Distributes apartments between two strips balancing total area, adds staircase to strip 2 if tipo_escala is :exterior
    function distribuye_deptos_entre_franjas(vec_sup_deptos::Vector{Float64}, vec_num_deptos::Vector{Int}, area_escala::Float64, tipo_escala::Symbol)
        deptos_individuales = Tuple{Float64, Int, Int}[]
        for tipo_depto in 1:length(vec_sup_deptos)
            sup_depto = vec_sup_deptos[tipo_depto]
            for j in 1:vec_num_deptos[tipo_depto]
                push!(deptos_individuales, (sup_depto, tipo_depto, j))
            end
        end

        sort!(deptos_individuales, by = x -> x[1], rev = true)

        deptos_franja1 = Tuple{Float64, Int, Int}[]
        deptos_franja2 = Tuple{Float64, Int, Int}[]
        area_franja1 = 0.0
        area_franja2 = 0.0

        escala_offset = (tipo_escala == :exterior) ? area_escala : 0.0

        for depto in deptos_individuales
            sup_depto = get_area(depto)
            if area_franja1 <= area_franja2 + escala_offset
                push!(deptos_franja1, depto)
                area_franja1 += sup_depto
            else
                push!(deptos_franja2, depto)
                area_franja2 += sup_depto
            end
        end

        if tipo_escala == :exterior
            push!(deptos_franja2, (area_escala, -1, 1))
            area_franja2 += area_escala
        end

        return deptos_franja1, deptos_franja2, area_franja1, area_franja2
    end

    # Calculates strip widths from areas and floor dimensions, scales if exceeding available space
    function calcula_dimensiones_franjas(area_franja1::Float64, area_franja2::Float64, W::Float64, H::Float64, ancho_pasillo::Float64, dimension_terraza_max::Float64, is_vertical::Bool)
        if is_vertical
            dimension_disponible_franja = W - 2 * dimension_terraza_max - ancho_pasillo
            dimension_franja1_requerida = area_franja1 / H
            dimension_franja2_requerida = area_franja2 / H
        else
            dimension_disponible_franja = H - 2 * dimension_terraza_max - ancho_pasillo
            dimension_franja1_requerida = area_franja1 / W
            dimension_franja2_requerida = area_franja2 / W
        end

        if dimension_franja1_requerida + dimension_franja2_requerida > dimension_disponible_franja
            scale_factor = dimension_disponible_franja / (dimension_franja1_requerida + dimension_franja2_requerida)
            dimension_franja1 = dimension_franja1_requerida * scale_factor
            dimension_franja2 = dimension_franja2_requerida * scale_factor
        else
            dimension_franja1 = dimension_franja1_requerida
            dimension_franja2 = dimension_franja2_requerida
        end

        return dimension_franja1, dimension_franja2
    end

    # Orders apartments within each strip, placing staircase centrally if present and balancing layout
    function ordena_deptos_en_franja(deptos_franja1::Vector{Tuple{Float64, Int, Int}}, deptos_franja2::Vector{Tuple{Float64, Int, Int}}, deptos_total::Int, tipo_escala::Symbol; balance_mode::Symbol = :heuristic)
        deptos_ordenados1 = Tuple{Float64, Int}[]
        deptos_ordenados2 = Tuple{Float64, Int}[]

        num_deptos1 = length(deptos_franja1)
        num_deptos2 = (tipo_escala == :exterior) ? length(deptos_franja2) - 1 : length(deptos_franja2)

        area_escala_local = (tipo_escala == :exterior) ? get_area(deptos_franja2[end]) : 0.0

        if balance_mode == :area
            for i in 1:num_deptos1
                push!(deptos_ordenados1, (get_area(deptos_franja1[i]), get_tipo(deptos_franja1[i])))
            end

            num_deptos2_half = div(num_deptos2, 2)
            for i in 1:num_deptos2_half
                push!(deptos_ordenados2, (get_area(deptos_franja2[i]), get_tipo(deptos_franja2[i])))
            end
            if tipo_escala == :exterior
                push!(deptos_ordenados2, (area_escala_local, -1))
            end
            for i in (num_deptos2_half + 1):num_deptos2
                push!(deptos_ordenados2, (get_area(deptos_franja2[i]), get_tipo(deptos_franja2[i])))
            end
        else
            if deptos_total >= 4
                push!(deptos_ordenados1, (get_area(deptos_franja1[2]), get_tipo(deptos_franja1[2])))
                if num_deptos1 > 2
                    for i in 3:num_deptos1
                        push!(deptos_ordenados1, (get_area(deptos_franja1[i]), get_tipo(deptos_franja1[i])))
                    end
                end
                push!(deptos_ordenados1, (get_area(deptos_franja1[1]), get_tipo(deptos_franja1[1])))

                num_deptos2_half = div(num_deptos2, 2)
                for i in 1:num_deptos2_half
                    push!(deptos_ordenados2, (get_area(deptos_franja2[i]), get_tipo(deptos_franja2[i])))
                end
                if tipo_escala == :exterior
                    push!(deptos_ordenados2, (area_escala_local, -1))
                end
                for i in (num_deptos2_half + 1):num_deptos2
                    push!(deptos_ordenados2, (get_area(deptos_franja2[i]), get_tipo(deptos_franja2[i])))
                end
            else
                for depto in deptos_franja1
                    push!(deptos_ordenados1, (get_area(depto), get_tipo(depto)))
                end
                num_deptos2_half = div(num_deptos2, 2)
                for i in 1:num_deptos2_half
                    push!(deptos_ordenados2, (get_area(deptos_franja2[i]), get_tipo(deptos_franja2[i])))
                end
                if tipo_escala == :exterior
                    push!(deptos_ordenados2, (area_escala_local, -1))
                end
                for i in (num_deptos2_half + 1):num_deptos2
                    push!(deptos_ordenados2, (get_area(deptos_franja2[i]), get_tipo(deptos_franja2[i])))
                end
            end
        end

        return deptos_ordenados1, deptos_ordenados2
    end

    # ──────────────────────────────────────────────────────────────────────────────────
    # Corridor and results packaging helpers
    # ──────────────────────────────────────────────────────────────────────────────────

    # Computes corridor geometry spanning both strips based on apartment coordinates
    function calcula_geometria_pasillo(vec_coord_fin1::Vector{Float64}, vec_coord_fin2::Vector{Float64}, 
                        vec_coord_ini1::Vector{Float64}, vec_coord_ini2::Vector{Float64}, coord_base::Float64, 
                        ancho_pasillo::Float64, is_vertical::Bool, W::Float64, H::Float64, coord_min::Float64, 
                        min_largo_pasillo::Float64, pasillo_centrado::Bool, vec_tipo_deptos1::Vector{Int}, 
                        vec_tipo_deptos2::Vector{Int}, tipo_escala::Symbol, ancho_escala, area_escala)

        num_deptos_franja1 = count(t -> t != -1, vec_tipo_deptos1)
        num_deptos_franja2 = count(t -> t != -1, vec_tipo_deptos2)
        num_deptos_total = num_deptos_franja1 + num_deptos_franja2

        coord_ini_pasillo = min(vec_coord_fin1[1], vec_coord_fin2[1])
        coord_fin_pasillo = max(vec_coord_ini1[end], vec_coord_ini2[end])
        largo_pasillo = coord_fin_pasillo - coord_ini_pasillo

        if largo_pasillo < min_largo_pasillo
            centro_pasillo = (coord_ini_pasillo + coord_fin_pasillo) / 2
            coord_ini_pasillo = centro_pasillo - min_largo_pasillo / 2
            coord_fin_pasillo = centro_pasillo + min_largo_pasillo / 2
            largo_pasillo = min_largo_pasillo
        end

        if pasillo_centrado || num_deptos_total == 2
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
        end

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


        if tipo_escala == :interior
            if is_vertical
                ps_escala = polyShape.polyBox(x_centroide - (largo_escala + ancho_pasillo) / 2, y_centroide - ancho_escala / 2, largo_escala + ancho_pasillo, ancho_escala, 0.0)
            else
                ps_escala = polyShape.polyBox(x_centroide - ancho_escala / 2, y_centroide - (largo_escala + ancho_pasillo) / 2, ancho_escala, largo_escala + ancho_pasillo, 0.0)
            end
            ps_pasillo = polyShape.polyUnion(ps_pasillo, ps_escala)            
        end

        return coord_ini_pasillo, coord_fin_pasillo, largo_pasillo, ps_pasillo
    end

    # Packages all computed geometries and parameters into results dictionary
    function empaqueta_resultados(num_deptos1::Int, num_deptos2::Int, deptos_ordenados1::Vector{Tuple{Float64, Int}},
                        deptos_ordenados2::Vector{Tuple{Float64, Int}}, dimension1::Float64, dimension2::Float64,
                        W::Float64, H::Float64, ancho_pasillo::Float64, largo_pasillo::Float64, ps_pasillo::PolyShape,
                        vec_ps_deptos1::Vector{PolyShape}, vec_ps_deptos2::Vector{PolyShape},
                        vec_dimension_deptos2::Vector{Float64}, vec_tipo_deptos2::Vector{Int}, area_escala::Float64,
                        vec_terrazas1::Vector{PolyShape}, vec_terrazas2::Vector{PolyShape}, is_vertical::Bool,
                        tipo_escala::Symbol)
        if is_vertical
            prefix1, prefix2 = "este", "oeste"
            dim_key = "width"
        else
            prefix1, prefix2 = "norte", "sur"
            dim_key = "height"
        end

        result = Dict(
            "feasible" => true,
            "status" => "LOCALLY_SOLVED",
            "n_apts_$prefix1" => num_deptos1,
            "n_apts_$prefix2" => num_deptos2,
            "vec_sup_deptos_$prefix1" => [get_area(apt) for apt in deptos_ordenados1],
            "vec_sup_deptos_$prefix2" => [get_area(apt) for apt in deptos_ordenados2 if get_tipo(apt) != -1],
            "$(dim_key)_$prefix1" => round(dimension1, digits=2),
            "$(dim_key)_$prefix2" => round(dimension2, digits=2),
            "floor_width" => W,
            "floor_height" => H,
            "ancho_pasillo" => ancho_pasillo,
            "largo_pasillo" => largo_pasillo,
            "ps_pasillo" => ps_pasillo
        )

        if tipo_escala == :exterior
            id_escala = findfirst(==(- 1), vec_tipo_deptos2)
            id_escala === nothing && error("No staircase found in strip 2 (tipo_depto == -1)")

            num_escalas = count(==(- 1), vec_tipo_deptos2)
            num_escalas > 1 && @warn "Multiple staircases found in strip 2 (count=$num_escalas). Using first occurrence at index $id_escala"

            ps_escala = vec_ps_deptos2[id_escala]
            dimension_escala = vec_dimension_deptos2[id_escala]

            vec_ps_deptos2_sin_escala = [vec_ps_deptos2[i] for i in eachindex(vec_ps_deptos2) if i != id_escala]
            vec_terrazas2_sin_escala = [vec_terrazas2[i] for i in eachindex(vec_terrazas2) if i != id_escala]

            result["ps_escala"] = ps_escala
            result["ancho_escala"] = round(dimension2, digits=2)
            result["alto_escala"] = round(dimension_escala, digits=2)
            result["area_escala"] = round(area_escala, digits=2)
            result["vec_polyshapes_all"] = vcat(vec_ps_deptos1, vec_ps_deptos2_sin_escala)
            result["vec_terrazas_all"] = vcat(vec_terrazas1, vec_terrazas2_sin_escala)
        elseif tipo_escala == :interior || tipo_escala == :none
            result["ps_escala"] = nothing
            result["ancho_escala"] = nothing
            result["alto_escala"] = nothing
            result["area_escala"] = nothing
            result["vec_polyshapes_all"] = vcat(vec_ps_deptos1, vec_ps_deptos2)
            result["vec_terrazas_all"] = vcat(vec_terrazas1, vec_terrazas2)
        end

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
    function prepare_floor_inputs(ps_planta::PolyShape, vec_sup_deptos::Vector{Float64}, vec_num_deptos::Vector{Int}, stair_cfg::StairConfig, corridor_cfg::CorridorConfig, balance_mode::Symbol, is_vertical::Bool, terrace_cfg::TerraceConfig)

        W, H, vec_x_planta, vec_y_planta, angulo_rotacion, cr, ps_planta_normalizado = normaliza_planta_rectangular(ps_planta)

        deptos_total = sum(vec_num_deptos)
        deptos_franja1, deptos_franja2, area_franja1, area_franja2 = distribuye_deptos_entre_franjas(vec_sup_deptos, vec_num_deptos, stair_cfg.area_escala, stair_cfg.tipo_escala)

        dimension_depto1, dimension_depto2 = calcula_dimensiones_franjas(area_franja1, area_franja2, W, H, corridor_cfg.ancho_pasillo, terrace_cfg.max_ancho_terraza, is_vertical)

        coord_min_x = minimum(vec_x_planta)
        coord_min_y = minimum(vec_y_planta)

        if is_vertical
            total_dimension1_utilizada = terrace_cfg.max_ancho_terraza + dimension_depto1 + corridor_cfg.ancho_pasillo / 2
            total_dimension2_utilizada = terrace_cfg.max_ancho_terraza + dimension_depto2 + corridor_cfg.ancho_pasillo / 2
            total_dimension_utilizada = total_dimension1_utilizada + total_dimension2_utilizada
            holgura = W - total_dimension_utilizada
            coord_min_x += terrace_cfg.max_ancho_terraza + holgura/2
        else
            total_dimension1_utilizada = terrace_cfg.max_ancho_terraza + dimension_depto1 + corridor_cfg.ancho_pasillo / 2
            total_dimension2_utilizada = terrace_cfg.max_ancho_terraza + dimension_depto2 + corridor_cfg.ancho_pasillo / 2
            total_dimension_utilizada = total_dimension1_utilizada + total_dimension2_utilizada
            holgura = H - total_dimension_utilizada
            coord_min_y += terrace_cfg.max_ancho_terraza + holgura/2
        end

        deptos_ordenados1, deptos_ordenados2 = ordena_deptos_en_franja(deptos_franja1, deptos_franja2, deptos_total, stair_cfg.tipo_escala, balance_mode=balance_mode)

        return (W=W, H=H, vec_x_planta=vec_x_planta, vec_y_planta=vec_y_planta, angulo_rotacion=angulo_rotacion,
                cr=cr, ps_planta_normalizado=ps_planta_normalizado, deptos_ordenados1=deptos_ordenados1,
                deptos_ordenados2=deptos_ordenados2, dimension_depto1=dimension_depto1, dimension_depto2=dimension_depto2,
                coord_min_x=coord_min_x, coord_min_y=coord_min_y, dimension_terraza_max=terrace_cfg.max_ancho_terraza,
                total_dimension1_utilizada=total_dimension1_utilizada, total_dimension2_utilizada=total_dimension2_utilizada)
    end


    # ══════════════════════════════════════════════════════════════════════════════════
    # MAIN EXECUTION LOGIC
    # ══════════════════════════════════════════════════════════════════════════════════

    # ──────────────────────────────────────────────────────────────────────────────────
    # Stage 1: Input preparation and normalization
    # ──────────────────────────────────────────────────────────────────────────────────
    planta_normalizada = prepare_floor_inputs(ps_planta, vec_sup_deptos, vec_num_deptos,
                                        stair_cfg, corridor_cfg,
                                        balance_mode, is_vertical, terrace_cfg)

    # ──────────────────────────────────────────────────────────────────────────────────
    # Stage 2: Strip geometry computation
    # ──────────────────────────────────────────────────────────────────────────────────
    if is_vertical
        coord_base = planta_normalizada.coord_min_x + planta_normalizada.dimension_depto2
        coord_disponible = planta_normalizada.H
        coord_min = planta_normalizada.coord_min_y
        franja1 = :este
        franja2 = :oeste
    else
        coord_base = planta_normalizada.coord_min_y + planta_normalizada.dimension_depto2
        coord_disponible = planta_normalizada.W
        coord_min = planta_normalizada.coord_min_x
        franja1 = :norte
        franja2 = :sur
    end

    
    vec_coord_ini1, vec_coord_fin1, vec_dimension1_deptos1, vec_dimension2_deptos1, vec_tipo_deptos1, 
            vec_ps_deptos1_normalizado = genera_deptos_franja(planta_normalizada.deptos_ordenados1, coord_min, 
                                            planta_normalizada.dimension_depto1, coord_disponible, min_ancho_escala, 
                                            is_vertical, coord_base, franja1)
    vec_coord_ini2, vec_coord_fin2, vec_dimension1_deptos2, vec_dimension2_deptos2, vec_tipo_deptos2, 
            vec_ps_deptos2_normalizado = genera_deptos_franja(planta_normalizada.deptos_ordenados2, coord_min, 
                                            planta_normalizada.dimension_depto2, coord_disponible, min_ancho_escala, 
                                            is_vertical, coord_base, franja2)

    coord_ini_pasillo, coord_fin_pasillo, largo_pasillo, ps_pasillo_normalizado = calcula_geometria_pasillo(
                                            vec_coord_fin1, vec_coord_fin2, vec_coord_ini1, vec_coord_ini2, 
                                            coord_base, ancho_pasillo, is_vertical, 
                                            planta_normalizada.W, planta_normalizada.H, 
                                            coord_min, min_largo_pasillo, pasillo_centrado, 
                                            vec_tipo_deptos1, vec_tipo_deptos2, 
                                            tipo_escala, min_ancho_escala, area_escala)

    vec_ps_deptos1_normalizado, vec_extension_dimension1_1 = extiende_deptos_con_interseccion_pasillo(vec_coord_ini1, vec_coord_fin1, vec_dimension1_deptos1, vec_dimension2_deptos1, coord_base, ps_pasillo_normalizado, franja1, is_vertical, vec_ps_deptos1_normalizado, ps_pasillo_normalizado)
    vec_ps_deptos2_normalizado, vec_extension_dimension1_2 = extiende_deptos_con_interseccion_pasillo(vec_coord_ini2, vec_coord_fin2, vec_dimension1_deptos2, vec_dimension2_deptos2, coord_base, ps_pasillo_normalizado, franja2, is_vertical, vec_ps_deptos2_normalizado, ps_pasillo_normalizado)

    vec_terrazas1_normalizado = PolyShape[]
    vec_terrazas2_normalizado = PolyShape[]

    if !isempty(vec_sup_terraza)
        vec_terrazas1_normalizado, vec_terrazas2_normalizado, vec_ps_deptos1_normalizado, vec_ps_deptos2_normalizado, ps_pasillo_normalizado =
            procesa_terrazas_ambas_franjas(vec_sup_terraza, planta_normalizada,
                                            vec_dimension1_deptos1, vec_dimension1_deptos2,
                                            vec_dimension2_deptos1, vec_dimension2_deptos2,
                                            vec_coord_ini1, vec_coord_ini2,
                                            vec_extension_dimension1_1, vec_extension_dimension1_2,
                                            coord_base, franja1, franja2,
                                            is_vertical, vec_ps_deptos1_normalizado,
                                            vec_ps_deptos2_normalizado, ps_pasillo_normalizado)
    end

    franjas_computadas = (vec_ps_deptos1_normalizado=vec_ps_deptos1_normalizado, vec_ps_deptos2_normalizado=vec_ps_deptos2_normalizado,
            vec_terrazas1_normalizado=vec_terrazas1_normalizado, vec_terrazas2_normalizado=vec_terrazas2_normalizado,
            ps_pasillo_normalizado=ps_pasillo_normalizado, largo_pasillo=largo_pasillo,
            vec_dimension_deptos2=vec_dimension2_deptos2, vec_tipo_deptos2=vec_tipo_deptos2)

    # ──────────────────────────────────────────────────────────────────────────────────
    # Stage 3: Rotation back to original coordinates
    # ──────────────────────────────────────────────────────────────────────────────────
    vec_ps_deptos1 = rota_polyshapes(franjas_computadas.vec_ps_deptos1_normalizado, planta_normalizada.angulo_rotacion, planta_normalizada.cr)
    vec_ps_deptos2 = rota_polyshapes(franjas_computadas.vec_ps_deptos2_normalizado, planta_normalizada.angulo_rotacion, planta_normalizada.cr)
    vec_terrazas1 = rota_polyshapes(franjas_computadas.vec_terrazas1_normalizado, planta_normalizada.angulo_rotacion, planta_normalizada.cr)
    vec_terrazas2 = rota_polyshapes(franjas_computadas.vec_terrazas2_normalizado, planta_normalizada.angulo_rotacion, planta_normalizada.cr)
    ps_pasillo = polyShape.polyRotate(franjas_computadas.ps_pasillo_normalizado, -planta_normalizada.angulo_rotacion, planta_normalizada.cr)

    # ──────────────────────────────────────────────────────────────────────────────────
    # Stage 4: Results packaging
    # ──────────────────────────────────────────────────────────────────────────────────

    num_deptos1 = length(planta_normalizada.deptos_ordenados1)
    num_deptos2 = (tipo_escala == :exterior) ? length(planta_normalizada.deptos_ordenados2) - 1 : length(planta_normalizada.deptos_ordenados2)

    results = empaqueta_resultados(num_deptos1, num_deptos2, planta_normalizada.deptos_ordenados1, planta_normalizada.deptos_ordenados2,
                                    planta_normalizada.dimension_depto1, planta_normalizada.dimension_depto2, planta_normalizada.W, planta_normalizada.H, ancho_pasillo, franjas_computadas.largo_pasillo, ps_pasillo,
                                    vec_ps_deptos1, vec_ps_deptos2, franjas_computadas.vec_dimension_deptos2, franjas_computadas.vec_tipo_deptos2,
                                    area_escala, vec_terrazas1, vec_terrazas2, is_vertical, tipo_escala)

    return results
end