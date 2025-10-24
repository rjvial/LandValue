# Main floor plan optimization function: distributes apartments in two strips with corridor and terraces
function opti_floor_plan(ps_planta::PolyShape, vec_sup_deptos::Vector{Float64}, vec_num_deptos::Vector{Int};
                        layout::Symbol = :ns,
                        ancho_pasillo::Float64 = 2.0,
                        vec_sup_terraza::Vector{Float64} = Float64[],
                        area_escala::Float64 = 25.0,
                        vec_min_dimensiones::Vector{Float64} = Float64[],
                        min_dimension_escala::Float64 = 0.0,
                        balance_mode::Symbol = :heuristic,
                        min_largo_pasillo::Float64 = 0.0,
                        pasillo_centrado::Bool = false)

    is_vertical = (layout == :oe)

    # Generates apartment geometries along one strip, adjusting dimensions iteratively to fit available space
    function genera_deptos_franja(vec_orden_deptos::Vector{Tuple{Float64, Int}}, coord_min_planta::Float64, dimension_franja::Float64, vec_min_dimensiones::Vector{Float64}, dimension_disponible::Float64, min_dimension_escala::Float64, is_vertical::Bool)
        vec_coord_ini = Float64[]
        vec_coord_fin = Float64[]
        vec_dimension1_deptos = Float64[]
        vec_dimension2_deptos = Float64[]
        vec_tipo_deptos = Int[]

        dimension_franja_adjusted = dimension_franja
        max_iterations = 10

        for _ in 1:max_iterations
            empty!(vec_coord_ini)
            empty!(vec_coord_fin)
            empty!(vec_dimension1_deptos)
            empty!(vec_dimension2_deptos)
            empty!(vec_tipo_deptos)

            coord_current = coord_min_planta
            total_dimension = 0.0

            for (sup_depto, tipo_depto) in vec_orden_deptos
                if tipo_depto == -1
                    dim2 = sup_depto / dimension_franja_adjusted
                    if dim2 < min_dimension_escala
                        dim2 = min_dimension_escala
                        dim1 = sup_depto / dim2
                    else
                        dim1 = dimension_franja_adjusted
                    end
                else
                    dim2 = sup_depto / dimension_franja_adjusted
                    if dim2 < vec_min_dimensiones[tipo_depto]
                        dim2 = vec_min_dimensiones[tipo_depto]
                        dim1 = sup_depto / dim2
                    else
                        dim1 = dimension_franja_adjusted
                    end
                end

                push!(vec_coord_ini, coord_current)
                push!(vec_coord_fin, coord_current + dim2)
                push!(vec_dimension1_deptos, dim1)
                push!(vec_dimension2_deptos, dim2)
                push!(vec_tipo_deptos, tipo_depto)
                coord_current += dim2
                total_dimension += dim2
            end

            if abs(total_dimension - dimension_disponible) / dimension_disponible < 0.005
                break
            end

            dimension_franja_adjusted = dimension_franja_adjusted * (total_dimension / dimension_disponible)
        end

        return vec_coord_ini, vec_coord_fin, vec_dimension1_deptos, vec_dimension2_deptos, vec_tipo_deptos
    end

    # Extends apartments into corridor space where they overlap, then subtracts corridor geometry
    function extiende_deptos_interseccion_pasillo(vec_coord_ini::Vector{Float64}, vec_coord_fin::Vector{Float64}, vec_dimension1_deptos::Vector{Float64}, vec_dimension2_deptos::Vector{Float64}, coord_base::Float64, coord_ini_pasillo::Float64, coord_fin_pasillo::Float64, ancho_pasillo::Float64, ps_pasillo::PolyShape, extend_direction::Symbol, is_vertical::Bool)
        vec_extension_dimension1 = Float64[]
        ps_deptos_extendidos = PolyShape[]

        for i in eachindex(vec_coord_ini)
            coord_overlap_start = max(vec_coord_ini[i], coord_ini_pasillo)
            coord_overlap_end = min(vec_coord_fin[i], coord_fin_pasillo)

            if coord_overlap_start < coord_overlap_end
                overlap_dimension = coord_overlap_end - coord_overlap_start
                intersection_area = overlap_dimension * ancho_pasillo
                extension_dimension = intersection_area / vec_dimension2_deptos[i]
            else
                extension_dimension = 0.0
            end

            push!(vec_extension_dimension1, extension_dimension)

            dimension1_total = vec_dimension1_deptos[i] + extension_dimension
            dimension2 = vec_coord_fin[i] - vec_coord_ini[i]

            if is_vertical
                if extend_direction == :este
                    coord_ini_depto = coord_base
                else
                    coord_ini_depto = coord_base - dimension1_total
                end
                extended_local_poly = polyShape.polyBox(coord_ini_depto, vec_coord_ini[i], dimension1_total, dimension2, 0.0)
            else
                if extend_direction == :norte
                    coord_ini_depto = coord_base
                else
                    coord_ini_depto = coord_base - dimension1_total
                end
                extended_local_poly = polyShape.polyBox(vec_coord_ini[i], coord_ini_depto, dimension2, dimension1_total, 0.0)
            end

            extended_poly_final = polyShape.polyDifference(extended_local_poly, ps_pasillo)
            push!(ps_deptos_extendidos, extended_poly_final)
        end

        return ps_deptos_extendidos, vec_extension_dimension1
    end

    # Creates terrace geometries for each apartment based on required areas and available dimensions
    function genera_terrazas_franja(vec_orden_deptos::Vector{Tuple{Float64, Int}}, vec_sup_terraza::Vector{Float64}, vec_dimension2_deptos::Vector{Float64}, vec_coord_ini::Vector{Float64}, coord_terrace_base::Vector{Float64}, terrace_direction::Symbol, max_dimension_terraza::Float64, is_vertical::Bool)
        vec_terrazas = PolyShape[]

        for (i, (_, tipo_depto)) in enumerate(vec_orden_deptos)
            if tipo_depto == -1
                push!(vec_terrazas, PolyShape([zeros(0, 2)], 0))
            else
                area_terraza = vec_sup_terraza[tipo_depto]
                if area_terraza > 0.0
                    dimension2_depto = vec_dimension2_deptos[i]

                    if is_vertical
                        ancho_terraza = 1.75
                        alto_terraza = area_terraza / ancho_terraza

                        if alto_terraza > dimension2_depto
                            alto_terraza = dimension2_depto
                            ancho_terraza = min(area_terraza / alto_terraza, max_dimension_terraza)
                            if ancho_terraza < area_terraza / alto_terraza
                                alto_terraza = area_terraza / ancho_terraza
                            end
                        end

                        coord_depto_ini = vec_coord_ini[i]
                        coord_terraza_ini = coord_depto_ini + (dimension2_depto - alto_terraza) / 2

                        if terrace_direction == :este
                            coord_terrace_perpendicular = coord_terrace_base[i]
                        else
                            coord_terrace_perpendicular = coord_terrace_base[i] - ancho_terraza
                        end

                        terrace_poly = polyShape.polyBox(coord_terrace_perpendicular, coord_terraza_ini, ancho_terraza, alto_terraza, 0.0)
                    else
                        alto_terraza = 1.75
                        ancho_terraza = area_terraza / alto_terraza

                        if ancho_terraza > dimension2_depto
                            ancho_terraza = dimension2_depto
                            alto_terraza = min(area_terraza / ancho_terraza, max_dimension_terraza)
                            if alto_terraza < area_terraza / ancho_terraza
                                ancho_terraza = area_terraza / alto_terraza
                            end
                        end

                        coord_depto_ini = vec_coord_ini[i]
                        coord_terraza_ini = coord_depto_ini + (dimension2_depto - ancho_terraza) / 2

                        if terrace_direction == :norte
                            coord_terrace_perpendicular = coord_terrace_base[i]
                        else
                            coord_terrace_perpendicular = coord_terrace_base[i] - alto_terraza
                        end

                        terrace_poly = polyShape.polyBox(coord_terraza_ini, coord_terrace_perpendicular, ancho_terraza, alto_terraza, 0.0)
                    end

                    push!(vec_terrazas, terrace_poly)
                else
                    push!(vec_terrazas, PolyShape([zeros(0, 2)], 0))
                end
            end
        end

        return vec_terrazas
    end

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

    # Distributes apartments between two strips balancing total area, adds staircase to strip 2
    function distribuye_deptos_entre_franjas(vec_sup_deptos::Vector{Float64}, vec_num_deptos::Vector{Int}, area_escala::Float64)
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

        for depto in deptos_individuales
            sup_depto = depto[1]
            if area_franja1 <= area_franja2 + area_escala
                push!(deptos_franja1, depto)
                area_franja1 += sup_depto
            else
                push!(deptos_franja2, depto)
                area_franja2 += sup_depto
            end
        end

        push!(deptos_franja2, (area_escala, -1, 1))
        area_franja2 += area_escala

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

    # Orders apartments within each strip, placing staircase centrally and balancing layout
    function ordena_deptos_en_franja(deptos_franja1::Vector{Tuple{Float64, Int, Int}}, deptos_franja2::Vector{Tuple{Float64, Int, Int}}, deptos_total::Int; balance_mode::Symbol = :heuristic)
        deptos_ordenados1 = Tuple{Float64, Int}[]
        deptos_ordenados2 = Tuple{Float64, Int}[]

        num_deptos1 = length(deptos_franja1)
        num_deptos2 = length(deptos_franja2) - 1

        area_escala = deptos_franja2[end][1]

        if balance_mode == :area
            for i in 1:num_deptos1
                push!(deptos_ordenados1, (deptos_franja1[i][1], deptos_franja1[i][2]))
            end

            num_deptos2_half = div(num_deptos2, 2)
            for i in 1:num_deptos2_half
                push!(deptos_ordenados2, (deptos_franja2[i][1], deptos_franja2[i][2]))
            end
            push!(deptos_ordenados2, (area_escala, -1))
            for i in (num_deptos2_half + 1):num_deptos2
                push!(deptos_ordenados2, (deptos_franja2[i][1], deptos_franja2[i][2]))
            end
        else
            if deptos_total >= 4
                push!(deptos_ordenados1, (deptos_franja1[2][1], deptos_franja1[2][2]))
                if num_deptos1 > 2
                    for i in 3:num_deptos1
                        push!(deptos_ordenados1, (deptos_franja1[i][1], deptos_franja1[i][2]))
                    end
                end
                push!(deptos_ordenados1, (deptos_franja1[1][1], deptos_franja1[1][2]))

                num_deptos2_half = div(num_deptos2, 2)
                for i in 1:num_deptos2_half
                    push!(deptos_ordenados2, (deptos_franja2[i][1], deptos_franja2[i][2]))
                end
                push!(deptos_ordenados2, (area_escala, -1))
                for i in (num_deptos2_half + 1):num_deptos2
                    push!(deptos_ordenados2, (deptos_franja2[i][1], deptos_franja2[i][2]))
                end
            else
                for depto in deptos_franja1
                    push!(deptos_ordenados1, (depto[1], depto[2]))
                end
                num_deptos2_half = div(num_deptos2, 2)
                for i in 1:num_deptos2_half
                    push!(deptos_ordenados2, (deptos_franja2[i][1], deptos_franja2[i][2]))
                end
                push!(deptos_ordenados2, (area_escala, -1))
                for i in (num_deptos2_half + 1):num_deptos2
                    push!(deptos_ordenados2, (deptos_franja2[i][1], deptos_franja2[i][2]))
                end
            end
        end

        return deptos_ordenados1, deptos_ordenados2
    end

    # Computes corridor geometry spanning both strips based on apartment coordinates
    function calcula_geometria_pasillo(vec_coord_fin1::Vector{Float64}, vec_coord_fin2::Vector{Float64}, vec_coord_ini1::Vector{Float64}, vec_coord_ini2::Vector{Float64}, coord_base::Float64, ancho_pasillo::Float64, is_vertical::Bool, W::Float64, H::Float64, coord_min::Float64, min_largo_pasillo::Float64, pasillo_centrado::Bool, vec_tipo_deptos1::Vector{Int}, vec_tipo_deptos2::Vector{Int})
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
            if is_vertical
                centro_planta = coord_min + H / 2
            else
                centro_planta = coord_min + W / 2
            end

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
        else
            ps_pasillo = polyShape.polyBox(coord_ini_pasillo, coord_pasillo, largo_pasillo, ancho_pasillo, 0.0)
        end

        return coord_ini_pasillo, coord_fin_pasillo, largo_pasillo, ps_pasillo
    end

    # Packages all computed geometries and parameters into results dictionary
    function empaqueta_resultados(num_deptos1::Int, num_deptos2::Int, deptos_ordenados1::Vector{Tuple{Float64, Int}}, deptos_ordenados2::Vector{Tuple{Float64, Int}}, dimension1::Float64, dimension2::Float64, W::Float64, H::Float64, ancho_pasillo::Float64, largo_pasillo::Float64, ps_pasillo::PolyShape, vec_ps_deptos1::Vector{PolyShape}, vec_ps_deptos2::Vector{PolyShape}, vec_dimension_deptos2::Vector{Float64}, vec_tipo_deptos2::Vector{Int}, area_escala::Float64, vec_terrazas1::Vector{PolyShape}, vec_terrazas2::Vector{PolyShape}, is_vertical::Bool)
        id_escala = findfirst(==(- 1), vec_tipo_deptos2)
        if id_escala === nothing
            error("No staircase found in strip 2 (tipo_depto == -1)")
        end

        num_escalas = count(==(- 1), vec_tipo_deptos2)
        if num_escalas > 1
            @warn "Multiple staircases found in strip 2 (count=$num_escalas). Using first occurrence at index $id_escala"
        end

        ps_escala = vec_ps_deptos2[id_escala]
        dimension_escala = vec_dimension_deptos2[id_escala]

        vec_ps_deptos2_sin_escala = [vec_ps_deptos2[i] for i in eachindex(vec_ps_deptos2) if i != id_escala]
        vec_terrazas2_sin_escala = [vec_terrazas2[i] for i in eachindex(vec_terrazas2) if i != id_escala]

        if is_vertical
            results = Dict(
                "feasible" => true,
                "status" => "LOCALLY_SOLVED",
                "n_apts_este" => num_deptos1,
                "n_apts_oeste" => num_deptos2,
                "vec_sup_deptos_este" => [apt[1] for apt in deptos_ordenados1],
                "vec_sup_deptos_oeste" => [apt[1] for apt in deptos_ordenados2 if apt[2] != -1],
                "width_este" => round(dimension1, digits=2),
                "width_oeste" => round(dimension2, digits=2),
                "floor_width" => W,
                "floor_height" => H,
                "ancho_pasillo" => ancho_pasillo,
                "largo_pasillo" => largo_pasillo,
                "ps_pasillo" => ps_pasillo,
                "ps_escala" => ps_escala,
                "ancho_escala" => round(dimension2, digits=2),
                "alto_escala" => round(dimension_escala, digits=2),
                "area_escala" => round(area_escala, digits=2),
                "vec_polyshapes_all" => vcat(vec_ps_deptos1, vec_ps_deptos2_sin_escala),
                "vec_terrazas_all" => vcat(vec_terrazas1, vec_terrazas2_sin_escala)
            )
        else
            results = Dict(
                "feasible" => true,
                "status" => "LOCALLY_SOLVED",
                "n_apts_norte" => num_deptos1,
                "n_apts_sur" => num_deptos2,
                "vec_sup_deptos_norte" => [apt[1] for apt in deptos_ordenados1],
                "vec_sup_deptos_sur" => [apt[1] for apt in deptos_ordenados2 if apt[2] != -1],
                "height_norte" => round(dimension1, digits=2),
                "height_sur" => round(dimension2, digits=2),
                "floor_width" => W,
                "floor_height" => H,
                "ancho_pasillo" => ancho_pasillo,
                "largo_pasillo" => largo_pasillo,
                "ps_pasillo" => ps_pasillo,
                "ps_escala" => ps_escala,
                "ancho_escala" => round(dimension_escala, digits=2),
                "alto_escala" => round(dimension2, digits=2),
                "area_escala" => round(area_escala, digits=2),
                "vec_polyshapes_all" => vcat(vec_ps_deptos1, vec_ps_deptos2_sin_escala),
                "vec_terrazas_all" => vcat(vec_terrazas1, vec_terrazas2_sin_escala)
            )
        end

        return results
    end

    # Checks if all terraces are fully contained within floor plan boundaries
    function verifica_inscripcion_terrazas(ps_planta::PolyShape, vec_terrazas::Vector{PolyShape})
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

    # Prepares normalized floor plan, distributes apartments, and calculates strip dimensions
    function prepare_floor_inputs(ps_planta::PolyShape, vec_sup_deptos::Vector{Float64}, vec_num_deptos::Vector{Int}, area_escala::Float64, ancho_pasillo::Float64, vec_min_dimensiones::Vector{Float64}, balance_mode::Symbol, is_vertical::Bool)
        if isempty(vec_min_dimensiones)
            vec_min_dimensiones = zeros(Float64, length(vec_sup_deptos))
        end

        W, H, vec_x_planta, vec_y_planta, angulo_rotacion, cr, ps_planta_normalizado = normaliza_planta_rectangular(ps_planta)

        deptos_total = sum(vec_num_deptos)
        deptos_franja1, deptos_franja2, area_franja1, area_franja2 = distribuye_deptos_entre_franjas(vec_sup_deptos, vec_num_deptos, area_escala)

        dimension_terraza_max = 2.0
        dimension_depto1, dimension_depto2 = calcula_dimensiones_franjas(area_franja1, area_franja2, W, H, ancho_pasillo, dimension_terraza_max, is_vertical)

        coord_min_x = minimum(vec_x_planta)
        coord_min_y = minimum(vec_y_planta)

        if is_vertical
            total_dimension1_utilizada = dimension_terraza_max + dimension_depto1 + ancho_pasillo / 2
            total_dimension2_utilizada = dimension_terraza_max + dimension_depto2 + ancho_pasillo / 2
            total_dimension_utilizada = total_dimension1_utilizada + total_dimension2_utilizada
            holgura = W - total_dimension_utilizada
            coord_min_x += dimension_terraza_max + holgura/2
        else
            total_dimension1_utilizada = dimension_terraza_max + dimension_depto1 + ancho_pasillo / 2
            total_dimension2_utilizada = dimension_terraza_max + dimension_depto2 + ancho_pasillo / 2
            total_dimension_utilizada = total_dimension1_utilizada + total_dimension2_utilizada
            holgura = H - total_dimension_utilizada
            coord_min_y += dimension_terraza_max + holgura/2
        end

        deptos_ordenados1, deptos_ordenados2 = ordena_deptos_en_franja(deptos_franja1, deptos_franja2, deptos_total, balance_mode=balance_mode)

        return (W=W, H=H, vec_x_planta=vec_x_planta, vec_y_planta=vec_y_planta, angulo_rotacion=angulo_rotacion,
                cr=cr, ps_planta_normalizado=ps_planta_normalizado, deptos_ordenados1=deptos_ordenados1,
                deptos_ordenados2=deptos_ordenados2, dimension_depto1=dimension_depto1, dimension_depto2=dimension_depto2,
                coord_min_x=coord_min_x, coord_min_y=coord_min_y, dimension_terraza_max=dimension_terraza_max,
                total_dimension1_utilizada=total_dimension1_utilizada, total_dimension2_utilizada=total_dimension2_utilizada,
                vec_min_dimensiones=vec_min_dimensiones)
    end

    # Computes all strip geometries including apartments, corridor, terraces, and adjusts for fit
    function compute_strip_geometries(inputs, ancho_pasillo::Float64, vec_sup_terraza::Vector{Float64}, min_dimension_escala::Float64, is_vertical::Bool, min_largo_pasillo::Float64, pasillo_centrado::Bool)
        if is_vertical
            coord_base = inputs.coord_min_x + inputs.dimension_depto2
            coord_disponible = inputs.H
            coord_min = inputs.coord_min_y
            direction1 = :este
            direction2 = :oeste
        else
            coord_base = inputs.coord_min_y + inputs.dimension_depto2
            coord_disponible = inputs.W
            coord_min = inputs.coord_min_x
            direction1 = :norte
            direction2 = :sur
        end

        vec_coord_ini1, vec_coord_fin1, vec_dimension1_deptos1, vec_dimension2_deptos1, vec_tipo_deptos1 = genera_deptos_franja(inputs.deptos_ordenados1, coord_min, inputs.dimension_depto1, inputs.vec_min_dimensiones, coord_disponible, min_dimension_escala, is_vertical)
        vec_coord_ini2, vec_coord_fin2, vec_dimension1_deptos2, vec_dimension2_deptos2, vec_tipo_deptos2 = genera_deptos_franja(inputs.deptos_ordenados2, coord_min, inputs.dimension_depto2, inputs.vec_min_dimensiones, coord_disponible, min_dimension_escala, is_vertical)

        coord_ini_pasillo, coord_fin_pasillo, largo_pasillo, ps_pasillo_normalizado = calcula_geometria_pasillo(vec_coord_fin1, vec_coord_fin2, vec_coord_ini1, vec_coord_ini2, coord_base, ancho_pasillo, is_vertical, inputs.W, inputs.H, coord_min, min_largo_pasillo, pasillo_centrado, vec_tipo_deptos1, vec_tipo_deptos2)

        vec_ps_deptos1_normalizado, vec_extension_dimension1_1 = extiende_deptos_interseccion_pasillo(vec_coord_ini1, vec_coord_fin1, vec_dimension1_deptos1, vec_dimension2_deptos1, coord_base, coord_ini_pasillo, coord_fin_pasillo, ancho_pasillo, ps_pasillo_normalizado, direction1, is_vertical)
        vec_ps_deptos2_normalizado, vec_extension_dimension1_2 = extiende_deptos_interseccion_pasillo(vec_coord_ini2, vec_coord_fin2, vec_dimension1_deptos2, vec_dimension2_deptos2, coord_base, coord_ini_pasillo, coord_fin_pasillo, ancho_pasillo, ps_pasillo_normalizado, direction2, is_vertical)

        vec_terrazas1_normalizado = PolyShape[]
        vec_terrazas2_normalizado = PolyShape[]

        if !isempty(vec_sup_terraza)
            if is_vertical
                coord_terrace_base1 = [coord_base + vec_dimension1_deptos1[i] + vec_extension_dimension1_1[i] for i in eachindex(inputs.deptos_ordenados1)]
                vec_terrazas1_normalizado = genera_terrazas_franja(inputs.deptos_ordenados1, vec_sup_terraza, vec_dimension2_deptos1, vec_coord_ini1, coord_terrace_base1, direction1, inputs.dimension_terraza_max, is_vertical)

                coord_terrace_base2 = [coord_base - vec_dimension1_deptos2[i] - vec_extension_dimension1_2[i] for i in eachindex(inputs.deptos_ordenados2)]
                vec_terrazas2_normalizado = genera_terrazas_franja(inputs.deptos_ordenados2, vec_sup_terraza, vec_dimension2_deptos2, vec_coord_ini2, coord_terrace_base2, direction2, inputs.dimension_terraza_max, is_vertical)

                flag_inscripcion1 = verifica_inscripcion_terrazas(inputs.ps_planta_normalizado, vec_terrazas1_normalizado)
                flag_inscripcion2 = verifica_inscripcion_terrazas(inputs.ps_planta_normalizado, vec_terrazas2_normalizado)

                if !flag_inscripcion1
                    coord_max = maximum(inputs.vec_x_planta)
                    terrazas_con_area = [t for t in vec_terrazas1_normalizado if polyShape.polyArea(t) > 0.0]

                    if !isempty(terrazas_con_area)
                        max_coord_terrazas = maximum([maximum(t.Vertices[1][:, 1]) for t in terrazas_con_area])
                        delta = max_coord_terrazas - coord_max

                        terrazas2_con_area = [t for t in vec_terrazas2_normalizado if polyShape.polyArea(t) > 0.0]
                        if !isempty(terrazas2_con_area)
                            min_coord_terrazas2 = minimum([minimum(t.Vertices[1][:, 1]) for t in terrazas2_con_area])
                            coord_min_local = minimum(inputs.vec_x_planta)

                            max_safe_delta = min_coord_terrazas2 - coord_min_local
                            if delta > max_safe_delta
                                delta = max_safe_delta
                            end
                        end

                        if delta > 0.0
                            vec_ps_deptos1_normalizado = [safe_translate(p, -delta, 0.0) for p in vec_ps_deptos1_normalizado]
                            vec_ps_deptos2_normalizado = [safe_translate(p, -delta, 0.0) for p in vec_ps_deptos2_normalizado]
                            vec_terrazas1_normalizado = [safe_translate(t, -delta, 0.0) for t in vec_terrazas1_normalizado]
                            vec_terrazas2_normalizado = [safe_translate(t, -delta, 0.0) for t in vec_terrazas2_normalizado]
                            ps_pasillo_normalizado = safe_translate(ps_pasillo_normalizado, -delta, 0.0)

                            println("Translated all elements west by $(round(delta, digits=2)) to fit este terraces")
                        end
                    end
                elseif !flag_inscripcion2
                    coord_min_local = minimum(inputs.vec_x_planta)
                    terrazas_con_area = [t for t in vec_terrazas2_normalizado if polyShape.polyArea(t) > 0.0]

                    if !isempty(terrazas_con_area)
                        min_coord_terrazas = minimum([minimum(t.Vertices[1][:, 1]) for t in terrazas_con_area])
                        delta = coord_min_local - min_coord_terrazas

                        terrazas1_con_area = [t for t in vec_terrazas1_normalizado if polyShape.polyArea(t) > 0.0]
                        if !isempty(terrazas1_con_area)
                            max_coord_terrazas1 = maximum([maximum(t.Vertices[1][:, 1]) for t in terrazas1_con_area])
                            coord_max = maximum(inputs.vec_x_planta)

                            max_safe_delta = coord_max - max_coord_terrazas1
                            if delta > max_safe_delta
                                delta = max_safe_delta
                            end
                        end

                        if delta > 0.0
                            vec_ps_deptos1_normalizado = [safe_translate(p, delta, 0.0) for p in vec_ps_deptos1_normalizado]
                            vec_ps_deptos2_normalizado = [safe_translate(p, delta, 0.0) for p in vec_ps_deptos2_normalizado]
                            vec_terrazas1_normalizado = [safe_translate(t, delta, 0.0) for t in vec_terrazas1_normalizado]
                            vec_terrazas2_normalizado = [safe_translate(t, delta, 0.0) for t in vec_terrazas2_normalizado]
                            ps_pasillo_normalizado = safe_translate(ps_pasillo_normalizado, delta, 0.0)

                            println("Translated all elements east by $(round(delta, digits=2)) to fit oeste terraces")
                        end
                    end
                end
            else
                coord_terrace_base1 = [coord_base + vec_dimension1_deptos1[i] + vec_extension_dimension1_1[i] for i in eachindex(inputs.deptos_ordenados1)]
                vec_terrazas1_normalizado = genera_terrazas_franja(inputs.deptos_ordenados1, vec_sup_terraza, vec_dimension2_deptos1, vec_coord_ini1, coord_terrace_base1, direction1, inputs.dimension_terraza_max, is_vertical)

                coord_terrace_base2 = [coord_base - vec_dimension1_deptos2[i] - vec_extension_dimension1_2[i] for i in eachindex(inputs.deptos_ordenados2)]
                vec_terrazas2_normalizado = genera_terrazas_franja(inputs.deptos_ordenados2, vec_sup_terraza, vec_dimension2_deptos2, vec_coord_ini2, coord_terrace_base2, direction2, inputs.dimension_terraza_max, is_vertical)

                flag_inscripcion1 = verifica_inscripcion_terrazas(inputs.ps_planta_normalizado, vec_terrazas1_normalizado)
                flag_inscripcion2 = verifica_inscripcion_terrazas(inputs.ps_planta_normalizado, vec_terrazas2_normalizado)

                println("Horizontal layout - flag_inscripcion1 (NORTE): $flag_inscripcion1, flag_inscripcion2 (SUR): $flag_inscripcion2")

                if !flag_inscripcion1
                    coord_max = maximum(inputs.vec_y_planta)
                    terrazas_con_area = [t for t in vec_terrazas1_normalizado if polyShape.polyArea(t) > 0.0]

                    if !isempty(terrazas_con_area)
                        max_coord_terrazas = maximum([maximum(t.Vertices[1][:, 2]) for t in terrazas_con_area])
                        delta = max_coord_terrazas - coord_max

                        terrazas2_con_area = [t for t in vec_terrazas2_normalizado if polyShape.polyArea(t) > 0.0]
                        if !isempty(terrazas2_con_area)
                            min_coord_terrazas2 = minimum([minimum(t.Vertices[1][:, 2]) for t in terrazas2_con_area])
                            coord_min_local = minimum(inputs.vec_y_planta)

                            max_safe_delta = min_coord_terrazas2 - coord_min_local
                            if delta > max_safe_delta
                                delta = max_safe_delta
                            end
                        end

                        if delta > 0.0
                            vec_ps_deptos1_normalizado = [safe_translate(p, 0.0, -delta) for p in vec_ps_deptos1_normalizado]
                            vec_ps_deptos2_normalizado = [safe_translate(p, 0.0, -delta) for p in vec_ps_deptos2_normalizado]
                            vec_terrazas1_normalizado = [safe_translate(t, 0.0, -delta) for t in vec_terrazas1_normalizado]
                            vec_terrazas2_normalizado = [safe_translate(t, 0.0, -delta) for t in vec_terrazas2_normalizado]
                            ps_pasillo_normalizado = safe_translate(ps_pasillo_normalizado, 0.0, -delta)

                            println("Translated all elements south by $(round(delta, digits=2)) to fit north terraces")
                        end
                    end
                elseif !flag_inscripcion2
                    println("SUR terraces are outbound, attempting correction...")
                    coord_min_local = minimum(inputs.vec_y_planta)
                    terrazas_con_area = [t for t in vec_terrazas2_normalizado if polyShape.polyArea(t) > 0.0]

                    if !isempty(terrazas_con_area)
                        min_coord_terrazas = minimum([minimum(t.Vertices[1][:, 2]) for t in terrazas_con_area])
                        delta = coord_min_local - min_coord_terrazas
                        println("  Delta needed to move north: $(round(delta, digits=2))")
                        println("  Floor min Y: $(round(coord_min_local, digits=2)), SUR terraces min Y: $(round(min_coord_terrazas, digits=2))")

                        terrazas1_con_area = [t for t in vec_terrazas1_normalizado if polyShape.polyArea(t) > 0.0]
                        if !isempty(terrazas1_con_area)
                            max_coord_terrazas1 = maximum([maximum(t.Vertices[1][:, 2]) for t in terrazas1_con_area])
                            coord_max = maximum(inputs.vec_y_planta)
                            println("  Floor max Y: $(round(coord_max, digits=2)), NORTE terraces max Y: $(round(max_coord_terrazas1, digits=2))")
                            println("  After full shift, NORTE max Y would be: $(round(max_coord_terrazas1 + delta, digits=2))")

                            max_safe_delta = coord_max - max_coord_terrazas1
                            if delta > max_safe_delta
                                delta = max_safe_delta
                                println("  Limiting delta to max safe value: $(round(delta, digits=2))")
                            end
                        end

                        if delta > 0.0
                            println("  Applying translation of $(round(delta, digits=2))...")
                            vec_ps_deptos1_normalizado = [safe_translate(p, 0.0, delta) for p in vec_ps_deptos1_normalizado]
                            vec_ps_deptos2_normalizado = [safe_translate(p, 0.0, delta) for p in vec_ps_deptos2_normalizado]
                            vec_terrazas1_normalizado = [safe_translate(t, 0.0, delta) for t in vec_terrazas1_normalizado]
                            vec_terrazas2_normalizado = [safe_translate(t, 0.0, delta) for t in vec_terrazas2_normalizado]
                            ps_pasillo_normalizado = safe_translate(ps_pasillo_normalizado, 0.0, delta)

                            println("Translated all elements north by $(round(delta, digits=2)) to fit south terraces")
                        end
                    end
                end
            end
        end

        return (vec_ps_deptos1_normalizado=vec_ps_deptos1_normalizado, vec_ps_deptos2_normalizado=vec_ps_deptos2_normalizado,
                vec_terrazas1_normalizado=vec_terrazas1_normalizado, vec_terrazas2_normalizado=vec_terrazas2_normalizado,
                ps_pasillo_normalizado=ps_pasillo_normalizado, largo_pasillo=largo_pasillo,
                vec_dimension_deptos2=vec_dimension2_deptos2, vec_tipo_deptos2=vec_tipo_deptos2)
    end

    inputs = prepare_floor_inputs(ps_planta, vec_sup_deptos, vec_num_deptos, area_escala, ancho_pasillo, vec_min_dimensiones, balance_mode, is_vertical)

    geometries = compute_strip_geometries(inputs, ancho_pasillo, vec_sup_terraza, min_dimension_escala, is_vertical, min_largo_pasillo, pasillo_centrado)

    vec_ps_deptos1 = rota_polyshapes(geometries.vec_ps_deptos1_normalizado, inputs.angulo_rotacion, inputs.cr)
    vec_ps_deptos2 = rota_polyshapes(geometries.vec_ps_deptos2_normalizado, inputs.angulo_rotacion, inputs.cr)
    vec_terrazas1 = rota_polyshapes(geometries.vec_terrazas1_normalizado, inputs.angulo_rotacion, inputs.cr)
    vec_terrazas2 = rota_polyshapes(geometries.vec_terrazas2_normalizado, inputs.angulo_rotacion, inputs.cr)
    ps_pasillo = polyShape.polyRotate(geometries.ps_pasillo_normalizado, -inputs.angulo_rotacion, inputs.cr)

    num_deptos1 = length(inputs.deptos_ordenados1)
    num_deptos2 = length(inputs.deptos_ordenados2) - 1

    results = empaqueta_resultados(num_deptos1, num_deptos2, inputs.deptos_ordenados1, inputs.deptos_ordenados2,
                                    inputs.dimension_depto1, inputs.dimension_depto2, inputs.W, inputs.H, ancho_pasillo, geometries.largo_pasillo, ps_pasillo,
                                    vec_ps_deptos1, vec_ps_deptos2, geometries.vec_dimension_deptos2, geometries.vec_tipo_deptos2,
                                    area_escala, vec_terrazas1, vec_terrazas2, is_vertical)

    return results
end