########################################################################
#              Private Helpers                                         #
########################################################################


function _pointInTriangle(p::Vector{Float64}, a::Vector{Float64}, b::Vector{Float64}, c::Vector{Float64})::Bool
    d1 = sign((p[1] - b[1]) * (a[2] - b[2]) - (a[1] - b[1]) * (p[2] - b[2]))
    d2 = sign((p[1] - c[1]) * (b[2] - c[2]) - (b[1] - c[1]) * (p[2] - c[2]))
    d3 = sign((p[1] - a[1]) * (c[2] - a[2]) - (c[1] - a[1]) * (p[2] - a[2]))
    has_neg = (d1 < 0) || (d2 < 0) || (d3 < 0)
    has_pos = (d1 > 0) || (d2 > 0) || (d3 > 0)
    return !(has_neg && has_pos)
end

function _triangulatePolygon(V::Matrix{Float64})::Vector{Int}
    n = size(V, 1)
    if n < 3
        return Int[]
    end

    indices = Int[]
    remaining = collect(1:n)

    while length(remaining) >= 3
        n_remaining = length(remaining)
        ear_found = false

        for i in 1:n_remaining
            prev_idx = remaining[i == 1 ? n_remaining : i - 1]
            curr_idx = remaining[i]
            next_idx = remaining[i == n_remaining ? 1 : i + 1]

            p1 = V[prev_idx, :]
            p2 = V[curr_idx, :]
            p3 = V[next_idx, :]

            cross_prod = (p2[1] - p1[1]) * (p3[2] - p1[2]) - (p2[2] - p1[2]) * (p3[1] - p1[1])

            if cross_prod > 0
                is_ear = true
                for j in 1:n_remaining
                    test_idx = remaining[j]
                    if test_idx != prev_idx && test_idx != curr_idx && test_idx != next_idx
                        pt = V[test_idx, :]
                        if _pointInTriangle(pt, p1, p2, p3)
                            is_ear = false
                            break
                        end
                    end
                end

                if is_ear
                    append!(indices, [prev_idx - 1, curr_idx - 1, next_idx - 1])
                    deleteat!(remaining, i)
                    ear_found = true
                    break
                end
            end
        end

        if !ear_found
            break
        end
    end

    return indices
end


########################################################################
#              Serialization Functions                                 #
########################################################################


function threejs2json(threejs_data::Dict{String,Any}; material_color::UInt32=0x888888)::String
    indices = threejs_data["indices"]
    vertices = threejs_data["vertices"]

    indices = [max(0, idx) for idx in indices]

    json_obj = Dict{String,Any}(
        "metadata" => Dict{String,Any}(
            "version" => 4.5,
            "type" => "BufferGeometry",
            "generator" => "LandValue.polyShape"
        ),
        "uuid" => string(Base.UUID(rand(UInt128))),
        "type" => "BufferGeometry",
        "data" => Dict{String,Any}(
            "attributes" => Dict{String,Any}(
                "position" => Dict{String,Any}(
                    "itemSize" => 3,
                    "type" => "Float32Array",
                    "array" => vertices
                )
            ),
            "index" => Dict{String,Any}(
                "type" => "Uint16Array",
                "array" => indices
            )
        )
    )

    return JSON.json(json_obj)
end



function building2json(results_primer_piso::Union{AbstractDict, Nothing}, results_pisos_superiores::AbstractDict, num_pisos_superiores::Int, alturaPiso::Float64)::Dict{String, String}

    function addPolyShapeTo3D(ps::Union{PolyShape, Nothing}, z_low::Float64, z_high::Float64, all_vertices::Vector{Float64}, all_indices::Vector{Int})
        if isnothing(ps)
            return
        end
        if ps.NumRegions == 0
            return
        end

        vertex_count = div(length(all_vertices), 3)

        for region_idx in 1:ps.NumRegions
            V = ps.Vertices[region_idx]
            n_verts = size(V, 1)

            floor_start = vertex_count
            for j in 1:n_verts
                append!(all_vertices, [V[j, 2], z_low, V[j, 1]])
            end
            vertex_count += n_verts

            ceiling_start = vertex_count
            for j in 1:n_verts
                append!(all_vertices, [V[j, 2], z_high, V[j, 1]])
            end
            vertex_count += n_verts

            tri_indices = _triangulatePolygon(V)
            for idx in tri_indices
                append!(all_indices, [floor_start + idx])
            end

            for idx in reverse(tri_indices)
                append!(all_indices, [ceiling_start + idx])
            end

            for j in 0:n_verts-1
                next_j = (j + 1) % n_verts
                bottom_current = floor_start + j
                bottom_next = floor_start + next_j
                ceiling_current = ceiling_start + j
                ceiling_next = ceiling_start + next_j

                append!(all_indices, [bottom_current, bottom_next, ceiling_current])
                append!(all_indices, [ceiling_current, bottom_next, ceiling_next])
            end
        end
    end

    function create_single_element_json(element_name::String)
        all_vertices = Float64[]
        all_indices = Int[]

        if element_name == "deptos"
            if !isnothing(results_primer_piso)
                vec_deptos_primer = get(results_primer_piso, "vec_ps_deptos_interior_all", PolyShape[])
                for ps_depto in vec_deptos_primer
                    if polyArea(ps_depto) > 0.0
                        addPolyShapeTo3D(ps_depto, 0.0, alturaPiso, all_vertices, all_indices)
                    end
                end
            end

            vec_deptos_sup = results_pisos_superiores["vec_ps_deptos_interior_all"]
            for piso in 1:num_pisos_superiores
                z_low = alturaPiso * piso
                z_high = alturaPiso * (piso + 1)
                for ps_depto in vec_deptos_sup
                    if polyArea(ps_depto) > 0.0
                        addPolyShapeTo3D(ps_depto, z_low, z_high, all_vertices, all_indices)
                    end
                end
            end

        elseif element_name == "terrazas"
            if !isnothing(results_primer_piso)
                vec_terrazas_primer = get(results_primer_piso, "vec_ps_terrazas_all", PolyShape[])
                for ps_terraza in vec_terrazas_primer
                    if polyArea(ps_terraza) > 0.0
                        addPolyShapeTo3D(ps_terraza, 0.0, 1.0, all_vertices, all_indices)
                    end
                end
            end

            vec_terrazas_sup = results_pisos_superiores["vec_ps_terrazas_all"]
            for piso in 1:num_pisos_superiores
                z_low = alturaPiso * piso
                for ps_terraza in vec_terrazas_sup
                    if polyArea(ps_terraza) > 0.0
                        addPolyShapeTo3D(ps_terraza, z_low, z_low + 1.0, all_vertices, all_indices)
                    end
                end
            end

        elseif element_name == "area_comun"
            if !isnothing(results_primer_piso)
                addPolyShapeTo3D(get(results_primer_piso, "ps_pasillo", nothing), 0.0, alturaPiso, all_vertices, all_indices)
                addPolyShapeTo3D(get(results_primer_piso, "ps_nucleo", nothing), 0.0, alturaPiso, all_vertices, all_indices)
                addPolyShapeTo3D(get(results_primer_piso, "ps_escalera", nothing), 0.0, alturaPiso, all_vertices, all_indices)
                addPolyShapeTo3D(get(results_primer_piso, "ps_ascensor", nothing), 0.0, alturaPiso, all_vertices, all_indices)
                addPolyShapeTo3D(get(results_primer_piso, "ps_otros_espacios_comunes", nothing), 0.0, alturaPiso, all_vertices, all_indices)
            end

            ps_pasillo_sup = get(results_pisos_superiores, "ps_pasillo", nothing)
            ps_nucleo_sup = get(results_pisos_superiores, "ps_nucleo", nothing)
            ps_escalera_sup = get(results_pisos_superiores, "ps_escalera", nothing)
            ps_ascensor_sup = get(results_pisos_superiores, "ps_ascensor", nothing)
            for piso in 1:num_pisos_superiores
                z_low = alturaPiso * piso
                z_high = alturaPiso * (piso + 1)
                addPolyShapeTo3D(ps_pasillo_sup, z_low, z_high, all_vertices, all_indices)
                addPolyShapeTo3D(ps_nucleo_sup, z_low, z_high, all_vertices, all_indices)
                addPolyShapeTo3D(ps_escalera_sup, z_low, z_high, all_vertices, all_indices)
                addPolyShapeTo3D(ps_ascensor_sup, z_low, z_high, all_vertices, all_indices)
            end
        end

        if isempty(all_indices)
            return ""
        end

        geometry_uuid = string(Base.UUID(rand(UInt128)))

        geometry = Dict{String,Any}(
            "uuid" => geometry_uuid,
            "type" => "BufferGeometry",
            "data" => Dict{String,Any}(
                "attributes" => Dict{String,Any}(
                    "position" => Dict{String,Any}(
                        "itemSize" => 3,
                        "type" => "Float32Array",
                        "array" => all_vertices
                    )
                ),
                "index" => Dict{String,Any}(
                    "type" => "Uint16Array",
                    "array" => [max(0, idx) for idx in all_indices]
                )
            ),
            "metadata" => Dict{String,Any}(
                "version" => 4.5,
                "type" => "BufferGeometry",
                "generator" => "LandValue.polyShape"
            )
        )

        return JSON.json(geometry)
    end

    return Dict{String, String}(
        "json_deptos_opt" => create_single_element_json("deptos"),
        "json_terrazas_opt" => create_single_element_json("terrazas"),
        "json_area_comun_opt" => create_single_element_json("area_comun")
    )
end


function planta2svg(vec_info_deptos::Vector, ps_pasillo::Union{PolyShape, Nothing};
                    ps_nucleo::Union{PolyShape, Nothing}=nothing,
                    ps_escalera::Union{PolyShape, Nothing}=nothing,
                    ps_ascensor::Union{PolyShape, Nothing}=nothing,
                    ps_otros_espacios_comunes::Union{PolyShape, Nothing}=nothing,
                    nombre_area_comun::String="Circulación")::String
    all_shapes = PolyShape[]
    for info in vec_info_deptos
        push!(all_shapes, info["ps_depto"])
        push!(all_shapes, info["ps_terraza"])
    end
    if ps_pasillo !== nothing
        push!(all_shapes, ps_pasillo)
    end
    if ps_nucleo !== nothing && polyArea(ps_nucleo) > 0.0
        push!(all_shapes, ps_nucleo)
    end
    if ps_escalera !== nothing && polyArea(ps_escalera) > 0.0
        push!(all_shapes, ps_escalera)
    end
    if ps_ascensor !== nothing && polyArea(ps_ascensor) > 0.0
        push!(all_shapes, ps_ascensor)
    end
    if ps_otros_espacios_comunes !== nothing && polyArea(ps_otros_espacios_comunes) > 0.0
        push!(all_shapes, ps_otros_espacios_comunes)
    end

    if isempty(all_shapes)
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\"></svg>"
    end

    min_x, max_x = Inf, -Inf
    min_y, max_y = Inf, -Inf
    for ps in all_shapes
        for i in 1:ps.NumRegions
            V = ps.Vertices[i]
            min_x = min(min_x, minimum(V[:, 1]))
            max_x = max(max_x, maximum(V[:, 1]))
            min_y = min(min_y, minimum(V[:, 2]))
            max_y = max(max_y, maximum(V[:, 2]))
        end
    end

    padding = 2.0
    base_width = max_x - min_x + 2 * padding
    base_height = max_y - min_y + 2 * padding

    target_size = 800.0
    scale = target_size / max(base_width, base_height)

    width = base_width * scale
    height_svg = base_height * scale
    stroke_width = max(1.0, scale * 0.1)

    function poly_to_path(ps::PolyShape, offset_x::Float64, offset_y::Float64, h::Float64, s::Float64)::String
        paths = String[]
        for i in 1:ps.NumRegions
            V = ps.Vertices[i]
            n = size(V, 1)
            if n < 3
                continue
            end
            x1 = (V[1,1] - offset_x) * s
            y1 = h - (V[1,2] - offset_y) * s
            d = "M $(x1) $(y1)"
            for j in 2:n
                xj = (V[j,1] - offset_x) * s
                yj = h - (V[j,2] - offset_y) * s
                d *= " L $(xj) $(yj)"
            end
            d *= " Z"
            push!(paths, d)
        end
        return join(paths, " ")
    end

    offset_x = min_x - padding
    offset_y = min_y - padding

    svg_parts = String[]
    push!(svg_parts, """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $(width) $(height_svg)" width="$(width)" height="$(height_svg)">""")
    push!(svg_parts, "<style>")
    push!(svg_parts, ".depto { fill: #008080; stroke: #2b3636; stroke-width: $(stroke_width); }")
    push!(svg_parts, ".terraza { fill: #2F4F4F; stroke: #2b3636; stroke-width: $(stroke_width); }")
    push!(svg_parts, ".pasillo { fill: #CBD5E0; stroke: #2b3636; stroke-width: $(stroke_width); }")
    push!(svg_parts, ".escalera { fill: #bfb4a8; stroke: #2b3636; stroke-width: $(stroke_width); }")
    push!(svg_parts, ".ascensor { fill: #918981; stroke: #2b3636; stroke-width: $(stroke_width); }")
    push!(svg_parts, ".otros-espacios { fill: #826d57; stroke: #2b3636; stroke-width: $(stroke_width); }")
    push!(svg_parts, ".unidad-depto:hover .depto, .unidad-depto:hover .terraza { filter: brightness(1.15); cursor: pointer; }")
    push!(svg_parts, ".unidad-comun:hover { filter: brightness(1.15); cursor: pointer; }")
    push!(svg_parts, "</style>")

    if ps_pasillo !== nothing && ps_pasillo.NumRegions > 0
        area_pasillo = polyArea(ps_pasillo)
        path_d = poly_to_path(ps_pasillo, offset_x, offset_y, height_svg, scale)
        push!(svg_parts, """<g class="unidad-comun" data-tipo="pasillo" data-nombre="$(nombre_area_comun)" data-sup-comun="$(round(area_pasillo, digits=2))">""")
        push!(svg_parts, """<title>$(nombre_area_comun)\nSuperficie: $(round(area_pasillo, digits=2)) m²</title>""")
        push!(svg_parts, """<path class="pasillo" d="$(path_d)"/>""")
        push!(svg_parts, "</g>")
    end

    if ps_escalera !== nothing && ps_escalera.NumRegions > 0 && polyArea(ps_escalera) > 0.0
        area_escalera = polyArea(ps_escalera)
        path_d = poly_to_path(ps_escalera, offset_x, offset_y, height_svg, scale)
        push!(svg_parts, """<g class="unidad-comun" data-tipo="escalera" data-sup-comun="$(round(area_escalera, digits=2))">""")
        push!(svg_parts, """<title>Escalera\nSuperficie: $(round(area_escalera, digits=2)) m²</title>""")
        push!(svg_parts, """<path class="escalera" d="$(path_d)"/>""")
        push!(svg_parts, "</g>")
    end

    if ps_ascensor !== nothing && ps_ascensor.NumRegions > 0 && polyArea(ps_ascensor) > 0.0
        area_ascensor = polyArea(ps_ascensor)
        path_d = poly_to_path(ps_ascensor, offset_x, offset_y, height_svg, scale)
        push!(svg_parts, """<g class="unidad-comun" data-tipo="ascensor" data-sup-comun="$(round(area_ascensor, digits=2))">""")
        push!(svg_parts, """<title>Ascensor\nSuperficie: $(round(area_ascensor, digits=2)) m²</title>""")
        push!(svg_parts, """<path class="ascensor" d="$(path_d)"/>""")
        push!(svg_parts, "</g>")
    end

    if ps_otros_espacios_comunes !== nothing && ps_otros_espacios_comunes.NumRegions > 0 && polyArea(ps_otros_espacios_comunes) > 0.0
        area_otros = polyArea(ps_otros_espacios_comunes)
        path_d = poly_to_path(ps_otros_espacios_comunes, offset_x, offset_y, height_svg, scale)
        push!(svg_parts, """<g class="unidad-comun" data-tipo="otros-espacios" data-sup-comun="$(round(area_otros, digits=2))">""")
        push!(svg_parts, """<title>Otros espacios comunes\nSuperficie: $(round(area_otros, digits=2)) m²</title>""")
        push!(svg_parts, """<path class="otros-espacios" d="$(path_d)"/>""")
        push!(svg_parts, "</g>")
    end

    function vertices_to_json(ps::PolyShape)::String
        if ps.NumRegions == 0
            return "[]"
        end
        regions = String[]
        for i in 1:ps.NumRegions
            V = ps.Vertices[i]
            points = ["[$(round(V[j,1], digits=4)),$(round(V[j,2], digits=4))]" for j in axes(V, 1)]
            push!(regions, "[" * join(points, ",") * "]")
        end
        return "[" * join(regions, ",") * "]"
    end

    function edge_lengths_to_json(vec_edge)::String
        if isa(vec_edge, Dict)
            parts = String[]
            for (k, v) in vec_edge
                push!(parts, "\"$(k)\":$(round(v, digits=2))")
            end
            return "{" * join(parts, ",") * "}"
        elseif isa(vec_edge, Vector)
            orientaciones = ["N", "E", "S", "O"]
            parts = String[]
            for (i, v) in enumerate(vec_edge)
                if i <= length(orientaciones)
                    push!(parts, "\"$(orientaciones[i])\":$(round(v, digits=2))")
                end
            end
            return "{" * join(parts, ",") * "}"
        else
            return "{}"
        end
    end

    for (idx, info) in enumerate(vec_info_deptos)
        ps_depto = info["ps_depto"]
        ps_terraza = info["ps_terraza"]
        numeracion = get(info, "numeracion", idx)
        area_depto = round(get(info, "area_depto", polyArea(ps_depto)), digits=2)
        area_terraza = round(get(info, "area_terraza", polyArea(ps_terraza)), digits=2)
        area_util = round(area_depto + 0.5 * area_terraza, digits=2)
        orientacion = get(info, "orientacion", "")
        vec_edge_total_lengths = get(info, "vec_edge_total_lengths", Dict())

        letra_tipo = Char('A' + idx - 1)
        num_dormitorios = Int(get(info, "num_dormitorios", 0))
        num_banos = Int(get(info, "num_baños", 0))

        json_depto = replace(vertices_to_json(ps_depto), "\"" => "&quot;")
        json_terraza = replace(vertices_to_json(ps_terraza), "\"" => "&quot;")
        json_edges = replace(edge_lengths_to_json(vec_edge_total_lengths), "\"" => "&quot;")

        push!(svg_parts, """<g class="unidad-depto" data-depto-tipo="$(letra_tipo)" data-stack="$(numeracion)" data-sup-interior="$(area_depto)" data-sup-terraza="$(area_terraza)" data-sup-util="$(area_util)" data-orientacion="$(orientacion)" data-num-dormitorios="$(num_dormitorios)" data-num-banos="$(num_banos)" data-vertices-depto="$(json_depto)" data-vertices-terraza="$(json_terraza)" data-edge-lengths="$(json_edges)">""")
        push!(svg_parts, """<title>Depto Tipo $(letra_tipo) – $(numeracion)\nSup interior: $(area_depto) m²\nSup terraza: $(area_terraza) m²\nSup útil: $(area_util) m²\nOrientación: $(orientacion)\nDormitorios: $(num_dormitorios)\nBaños: $(num_banos)</title>""")

        if ps_depto.NumRegions > 0
            path_d = poly_to_path(ps_depto, offset_x, offset_y, height_svg, scale)
            push!(svg_parts, """<path class="depto" d="$(path_d)"/>""")
        end

        if ps_terraza.NumRegions > 0
            path_d = poly_to_path(ps_terraza, offset_x, offset_y, height_svg, scale)
            push!(svg_parts, """<path class="terraza" d="$(path_d)"/>""")
        end

        push!(svg_parts, "</g>")
    end

    push!(svg_parts, "</svg>")
    return join(svg_parts, "\n")
end

function planta2svg(vec_ps::Vector{PolyShape})::String
    if isempty(vec_ps)
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\"></svg>"
    end

    min_x, max_x = Inf, -Inf
    min_y, max_y = Inf, -Inf
    for ps in vec_ps
        for i in 1:ps.NumRegions
            V = ps.Vertices[i]
            min_x = min(min_x, minimum(V[:, 1]))
            max_x = max(max_x, maximum(V[:, 1]))
            min_y = min(min_y, minimum(V[:, 2]))
            max_y = max(max_y, maximum(V[:, 2]))
        end
    end

    padding = 2.0
    base_width = max_x - min_x + 2 * padding
    base_height = max_y - min_y + 2 * padding

    target_size = 800.0
    scale = target_size / max(base_width, base_height)

    width = base_width * scale
    height_svg = base_height * scale
    stroke_width = max(1.0, scale * 0.1)

    function poly_to_path(ps::PolyShape, offset_x::Float64, offset_y::Float64, h::Float64, s::Float64)::String
        paths = String[]
        for i in 1:ps.NumRegions
            V = ps.Vertices[i]
            n = size(V, 1)
            if n < 3
                continue
            end
            x1 = (V[1,1] - offset_x) * s
            y1 = h - (V[1,2] - offset_y) * s
            d = "M $(x1) $(y1)"
            for j in 2:n
                xj = (V[j,1] - offset_x) * s
                yj = h - (V[j,2] - offset_y) * s
                d *= " L $(xj) $(yj)"
            end
            d *= " Z"
            push!(paths, d)
        end
        return join(paths, " ")
    end

    offset_x = min_x - padding
    offset_y = min_y - padding

    colors = ["#4A90D9", "#68D391", "#F6AD55", "#FC8181", "#B794F4", "#63B3ED", "#F6E05E", "#68D391"]
    strokes = ["#2C5282", "#276749", "#C05621", "#C53030", "#6B46C1", "#2B6CB0", "#B7791F", "#276749"]

    svg_parts = String[]
    push!(svg_parts, "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 $(width) $(height_svg)\" width=\"$(width)\" height=\"$(height_svg)\">")

    for (idx, ps) in enumerate(vec_ps)
        if ps.NumRegions > 0
            color_idx = mod1(idx, length(colors))
            path_d = poly_to_path(ps, offset_x, offset_y, height_svg, scale)
            push!(svg_parts, "<path fill=\"$(colors[color_idx])\" stroke=\"$(strokes[color_idx])\" stroke-width=\"$(stroke_width)\" d=\"$(path_d)\"/>")
        end
    end

    push!(svg_parts, "</svg>")
    return join(svg_parts, "\n")
end


function angle_between_vectors(v1::Vector{Float64}, v2::Vector{Float64})
    dot_prod = dot(v1, v2)
    len1 = sqrt(sum(v1.^2))
    len2 = sqrt(sum(v2.^2))

    if len1 == 0.0 || len2 == 0.0
        return 0.0
    end

    cos_angle = clamp(dot_prod / (len1 * len2), -1.0, 1.0)
    return acos(cos_angle)
end


function polyShapeLayers2json(vec_ps::Vector{PolyShape}, vec_heights::Vector{Float64}; simplify::Bool=true, angle_threshold::Float64=5.0)::String

    function compute_layer_slope(ps1::PolyShape, ps2::PolyShape, h1::Float64, h2::Float64)
        if ps1.NumRegions == 0 || ps2.NumRegions == 0
            return [0.0, 0.0, 0.0]
        end

        V1 = ps1.Vertices[1]
        V2 = ps2.Vertices[1]
        n = min(size(V1, 1), size(V2, 1))

        avg_slope = [0.0, 0.0, 0.0]

        for i in 1:n
            avg_slope[1] += V2[i, 1] - V1[i, 1]
            avg_slope[2] += h2 - h1
            avg_slope[3] += V2[i, 2] - V1[i, 2]
        end

        avg_slope ./= n
        return avg_slope
    end

    function reduce_layers_by_slope(vec_ps::Vector{PolyShape}, vec_heights::Vector{Float64}, angle_threshold_deg::Float64=5.0)
        if length(vec_ps) <= 2
            return vec_ps, vec_heights
        end

        threshold_rad = angle_threshold_deg * π / 180.0

        key_indices = [1]

        prev_slope = compute_layer_slope(vec_ps[1], vec_ps[2], vec_heights[1], vec_heights[2])

        for i in 2:(length(vec_ps)-1)
            curr_slope = compute_layer_slope(vec_ps[i], vec_ps[i+1], vec_heights[i], vec_heights[i+1])
            angle = angle_between_vectors(prev_slope, curr_slope)

            if angle > threshold_rad
                push!(key_indices, i)
                prev_slope = curr_slope
            end
        end

        push!(key_indices, length(vec_ps))

        @info "Layer reduction: $(length(vec_ps)) -> $(length(key_indices)) layers ($(round((1 - length(key_indices)/length(vec_ps)) * 100, digits=1))% reduction)"

        return vec_ps[key_indices], vec_heights[key_indices]
    end


    if length(vec_ps) != length(vec_heights)
        throw(ArgumentError("Number of polyshapes must equal number of heights"))
    end

    if simplify
        vec_ps, vec_heights = reduce_layers_by_slope(vec_ps, vec_heights, angle_threshold)
    end

    all_vertices = Float64[]
    all_indices = Int[]
    vertex_count = 0
    level_regions_info = []
    original_vertices_dict = Dict{Tuple{Int,Int}, Matrix{Float64}}()

    for (level_idx, (ps, height)) in enumerate(zip(vec_ps, vec_heights))
        if ps.NumRegions == 0
            continue
        end

        level_info = []
        for region_idx = 1:ps.NumRegions
            V = ps.Vertices[region_idx]
            n_vertices = size(V, 1)

            if n_vertices < 3
                continue
            end

            region_start = vertex_count
            for j = 1:n_vertices
                append!(all_vertices, [V[j, 2], height, V[j, 1]])
            end

            vertex_count += n_vertices
            push!(level_info, (region_start, n_vertices))
            original_vertices_dict[(level_idx, region_idx)] = V
        end
        push!(level_regions_info, level_info)
    end

    if !isempty(level_regions_info)
        bottom_level = level_regions_info[1]
        for (idx, (region_start, _)) in enumerate(bottom_level)
            V = original_vertices_dict[(1, idx)]
            tri_indices = _triangulatePolygon(V)
            for tri_idx in tri_indices
                append!(all_indices, [region_start + tri_idx])
            end
        end

        top_level = level_regions_info[end]
        top_level_idx = length(level_regions_info)
        for (idx, (region_start, _)) in enumerate(top_level)
            V = original_vertices_dict[(top_level_idx, idx)]
            tri_indices = _triangulatePolygon(V)
            for tri_idx in reverse(tri_indices)
                append!(all_indices, [region_start + tri_idx])
            end
        end
    end

    for level_idx in 2:lastindex(level_regions_info)
        curr_level = level_regions_info[level_idx]
        prev_level = level_regions_info[level_idx - 1]

        num_regions_to_connect = min(length(curr_level), length(prev_level))

        for region_idx in 1:num_regions_to_connect
            curr_region_start, curr_n = curr_level[region_idx]
            prev_region_start, prev_n = prev_level[region_idx]

            n_edges = min(curr_n, prev_n)
            for j in 0:n_edges-1
                next_j = (j + 1) % n_edges

                bottom_current = prev_region_start + j
                top_current = curr_region_start + j
                bottom_next = prev_region_start + next_j
                top_next = curr_region_start + next_j

                append!(all_indices, [bottom_current, bottom_next, top_current])
                append!(all_indices, [top_current, bottom_next, top_next])
            end
        end
    end

    geometry_data = Dict(
        "vertices" => all_vertices,
        "indices" => all_indices,
        "vertexCount" => length(all_vertices) ÷ 3,
        "triangleCount" => length(all_indices) ÷ 3,
        "levels" => length(vec_ps)
    )

    return threejs2json(geometry_data)
end

function subterraneo2json(vec_ps::Vector{PolyShape}, vec_np::Vector{Int}, alturaPiso::Float64)::String

    if length(vec_ps) != length(vec_np)
        throw(ArgumentError("Number of polyshapes must equal number of floor counts"))
    end

    all_vertices = Float64[]
    all_indices = Int[]
    vertex_count = 0

    current_height = 0.0

    for (building_idx, (ps, n_floors)) in enumerate(zip(vec_ps, vec_np))
        if ps.NumRegions == 0 || n_floors == 0
            continue
        end

        V = ps.Vertices[1]
        n_verts = size(V, 1)

        floor_range = n_floors >= 0 ? (0:n_floors) : (n_floors:0)
        for floor_idx in floor_range
            floor_height = current_height + floor_idx * alturaPiso
            floor_start = vertex_count

            for j in 1:n_verts
                append!(all_vertices, [V[j, 2], floor_height, V[j, 1]])
            end

            vertex_count += n_verts

            first_floor = n_floors >= 0 ? 0 : n_floors
            last_floor = n_floors >= 0 ? n_floors : 0

            if floor_idx == first_floor
                tri_indices = _triangulatePolygon(V)
                for idx in tri_indices
                    append!(all_indices, [floor_start + idx])
                end
            elseif floor_idx == last_floor
                tri_indices = _triangulatePolygon(V)
                for idx in reverse(tri_indices)
                    append!(all_indices, [floor_start + idx])
                end
            end

            if (n_floors >= 0 && floor_idx > 0) || (n_floors < 0 && floor_idx > n_floors)
                prev_floor_start = floor_start - n_verts
                for j in 0:n_verts-1
                    next_j = (j + 1) % n_verts

                    bottom_current = prev_floor_start + j
                    top_current = floor_start + j
                    bottom_next = prev_floor_start + next_j
                    top_next = floor_start + next_j

                    append!(all_indices, [bottom_current, bottom_next, top_current])
                    append!(all_indices, [top_current, bottom_next, top_next])
                end
            end
        end

        current_height += n_floors * alturaPiso
    end

    geometry_data = Dict{String, Any}(
        "vertices" => all_vertices,
        "indices" => all_indices
    )

    return threejs2json(geometry_data)
end


function polyShape2json(ps::PolyShape; height::Float64=0.0)::String

    if ps.NumRegions == 0
        return threejs2json(Dict{String, Any}("vertices" => Float64[], "indices" => Int[]))
    end

    all_vertices = Float64[]
    all_indices = Int[]

    for region_idx in 1:ps.NumRegions
        V = ps.Vertices[region_idx]
        n_verts = size(V, 1)

        region_start = length(all_vertices) ÷ 3

        for i in 1:n_verts
            push!(all_vertices, V[i, 2], height, V[i, 1])
        end

        triangle_indices = _triangulatePolygon(V)
        for idx in triangle_indices
            push!(all_indices, region_start + idx)
        end
    end

    geometry_data = Dict{String, Any}(
        "vertices" => all_vertices,
        "indices" => all_indices
    )

    return threejs2json(geometry_data)
end
