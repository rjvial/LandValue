function create_strip_apartments(apt_order::Vector{Tuple{Float64, Int}}, x_min::Float64, y_base::Float64, strip_height::Float64)
    x_start = Float64[]
    x_end = Float64[]
    apt_widths = Float64[]
    apt_types = Int[]

    x_current = x_min

    for (apt_area, apt_type) in apt_order
        apt_width = apt_area / strip_height

        push!(x_start, x_current)
        push!(x_end, x_current + apt_width)
        push!(apt_widths, apt_width)
        push!(apt_types, apt_type)
        x_current += apt_width
    end

    return x_start, x_end, apt_widths, apt_types
end

function extend_apartments_to_core(x_start::Vector{Float64}, x_end::Vector{Float64}, apt_widths::Vector{Float64}, y_base::Float64, strip_height::Float64, x_core_start::Float64, x_core_end::Float64, y_core::Float64, core_width::Float64, rotation_angle::Float64, cr::Vector{Float64}, extend_direction::Symbol)
    extension_heights = Float64[]
    extended_polyshapes = PolyShape[]

    core_vertices_local = [
        x_core_start y_core;
        x_core_end y_core;
        x_core_end y_core + core_width;
        x_core_start y_core + core_width
    ]
    core_local_poly = PolyShape([core_vertices_local], 1)
    core_poly_rotated = polyShape.polyRotate(core_local_poly, -rotation_angle, cr)

    for i in eachindex(x_start)
        x_overlap_start = max(x_start[i], x_core_start)
        x_overlap_end = min(x_end[i], x_core_end)

        if x_overlap_start < x_overlap_end
            overlap_width = x_overlap_end - x_overlap_start
            intersection_area = overlap_width * core_width
            extension_height = intersection_area / apt_widths[i]
        else
            extension_height = 0.0
        end

        push!(extension_heights, extension_height)

        if extend_direction == :north
            vertices_extended_local = [
                x_start[i] y_base;
                x_end[i] y_base;
                x_end[i] y_base + strip_height + extension_height;
                x_start[i] y_base + strip_height + extension_height
            ]
        else
            vertices_extended_local = [
                x_start[i] y_base - extension_height;
                x_end[i] y_base - extension_height;
                x_end[i] y_base + strip_height;
                x_start[i] y_base + strip_height
            ]
        end

        extended_local_poly = PolyShape([vertices_extended_local], 1)
        extended_poly_rotated = polyShape.polyRotate(extended_local_poly, -rotation_angle, cr)

        extended_poly = polyShape.polyDifference(extended_poly_rotated, core_poly_rotated)
        push!(extended_polyshapes, extended_poly)
    end

    return extended_polyshapes, extension_heights
end

function create_strip_terraces(apt_order::Vector{Tuple{Float64, Int}}, terrace_areas::Vector{Float64}, apt_widths::Vector{Float64}, x_start::Vector{Float64}, y_terrace_base::Vector{Float64}, rotation_angle::Float64, cr::Vector{Float64}, terrace_direction::Symbol)
    vec_terraces = PolyShape[]

    for (i, (_, apt_type)) in enumerate(apt_order)
        if apt_type == -1
            push!(vec_terraces, PolyShape([zeros(0, 2)], 0))
        else
            terrace_area = terrace_areas[apt_type]
            if terrace_area > 0.0
                apt_width = apt_widths[i]
                terrace_height = 1.75

                terrace_width = terrace_area / terrace_height

                if terrace_width > apt_width
                    terrace_width = apt_width
                    terrace_height = terrace_area / terrace_width
                end

                x_apt_start = x_start[i]
                x_terrace_start = x_apt_start + (apt_width - terrace_width) / 2

                if terrace_direction == :north
                    y_terrace_start = y_terrace_base[i]
                    vertices_terrace_local = [
                        x_terrace_start y_terrace_start;
                        x_terrace_start + terrace_width y_terrace_start;
                        x_terrace_start + terrace_width y_terrace_start + terrace_height;
                        x_terrace_start y_terrace_start + terrace_height
                    ]
                else
                    y_terrace_start = y_terrace_base[i] - terrace_height
                    vertices_terrace_local = [
                        x_terrace_start y_terrace_start;
                        x_terrace_start + terrace_width y_terrace_start;
                        x_terrace_start + terrace_width y_terrace_start + terrace_height;
                        x_terrace_start y_terrace_start + terrace_height
                    ]
                end

                terrace_poly = PolyShape([vertices_terrace_local], 1)
                terrace_rotated = polyShape.polyRotate(terrace_poly, -rotation_angle, cr)
                push!(vec_terraces, terrace_rotated)
            else
                push!(vec_terraces, PolyShape([zeros(0, 2)], 0))
            end
        end
    end

    return vec_terraces
end

function opti_floor_plan(floor_poly::PolyShape, apt_areas::Vector{Float64}, apt_counts::Vector{Int}; core_width::Float64 = 2.0, terrace_areas::Vector{Float64} = Float64[], stair_area::Float64 = 25.0, min_stair_width::Float64 = 5.0)

    if length(apt_areas) != length(apt_counts)
        error("apt_areas and apt_counts must have the same length")
    end

    if !isempty(terrace_areas) && length(terrace_areas) != length(apt_areas)
        error("terrace_areas must have the same length as apt_areas")
    end

    has_terraces = !isempty(terrace_areas)

    if floor_poly.NumRegions != 1
        error("floor_poly must be a single rectangular polygon")
    end

    # Align floor polygon to axis (width > height)
    vertices_original = floor_poly.Vertices[1]

    centroid_x = sum(vertices_original[1:end-1, 1]) / (size(vertices_original, 1) - 1)
    centroid_y = sum(vertices_original[1:end-1, 2]) / (size(vertices_original, 1) - 1)

    edge1 = vertices_original[2, :] - vertices_original[1, :]
    angle_original = atan(edge1[2], edge1[1])

    rotation_angle = -angle_original
    cr_centroid = [centroid_x, centroid_y]

    rotated_poly = polyShape.polyRotate(floor_poly, rotation_angle, cr_centroid)
    vertices_rotated = rotated_poly.Vertices[1]

    x_coords = vertices_rotated[:, 1]
    y_coords = vertices_rotated[:, 2]
    W_calc = maximum(x_coords) - minimum(x_coords)
    H_calc = maximum(y_coords) - minimum(y_coords)

    if H_calc > W_calc
        rotation_angle += π/2
        rotated_poly = polyShape.polyRotate(floor_poly, rotation_angle, cr_centroid)
        vertices_rotated = rotated_poly.Vertices[1]

        x_coords = vertices_rotated[:, 1]
        y_coords = vertices_rotated[:, 2]
        W = maximum(x_coords) - minimum(x_coords)
        H = maximum(y_coords) - minimum(y_coords)
    else
        W = W_calc
        H = H_calc
    end

    num_apt_types = length(apt_areas)
    total_apts = sum(apt_counts)

    # Sort apartments by area and distribute to north/south strips
    # Prioritize keeping same types in the same strip
    apt_types_sorted = sort(collect(1:num_apt_types), by = i -> apt_areas[i], rev = true)

    apts_by_strip_north = Tuple{Float64, Int, Int}[]
    apts_by_strip_south = Tuple{Float64, Int, Int}[]

    area_north = 0.0
    area_south = 0.0

    for apt_type in apt_types_sorted
        apt_area = apt_areas[apt_type]
        count = apt_counts[apt_type]
        total_type_area = apt_area * count

        if area_north <= area_south + stair_area
            for j in 1:count
                push!(apts_by_strip_north, (apt_area, apt_type, j))
            end
            area_north += total_type_area
        else
            for j in 1:count
                push!(apts_by_strip_south, (apt_area, apt_type, j))
            end
            area_south += total_type_area
        end
    end

    push!(apts_by_strip_south, (stair_area, -1, 1))
    area_south += stair_area

    # Calculate strip heights
    h_north_needed = area_north / W
    h_south_needed = area_south / W

    if h_north_needed + h_south_needed > H
        scale_factor = H / (h_north_needed + h_south_needed)
        h_north = h_north_needed * scale_factor
        h_south = h_south_needed * scale_factor
    else
        h_north = h_north_needed
        h_south = h_south_needed
    end

    h_slack = H - (h_north + h_south)

    total_width_north = sum(apt[1] for apt in apts_by_strip_north) / h_north
    total_width_south = sum(apt[1] for apt in apts_by_strip_south) / h_south

    unused_north = W - total_width_north
    unused_south = W - total_width_south
    total_unused = unused_north * h_north + unused_south * h_south

    x_min = minimum(x_coords)
    y_min = minimum(y_coords)
    y_min += h_slack/2

    # Arrange apartments horizontally (largest at ends)
    apt_order_north = Tuple{Float64, Int}[]
    apt_order_south = Tuple{Float64, Int}[]

    n_north = length(apts_by_strip_north)
    n_south_with_stair = length(apts_by_strip_south)
    n_south = n_south_with_stair - 1

    if total_apts >= 4
        push!(apt_order_north, (apts_by_strip_north[2][1], apts_by_strip_north[2][2]))
        if n_north > 2
            for i in 3:n_north
                push!(apt_order_north, (apts_by_strip_north[i][1], apts_by_strip_north[i][2]))
            end
        end
        push!(apt_order_north, (apts_by_strip_north[1][1], apts_by_strip_north[1][2]))

        n_south_half = div(n_south, 2)
        for i in 1:n_south_half
            push!(apt_order_south, (apts_by_strip_south[i][1], apts_by_strip_south[i][2]))
        end
        push!(apt_order_south, (stair_area, -1))
        for i in (n_south_half + 1):n_south
            push!(apt_order_south, (apts_by_strip_south[i][1], apts_by_strip_south[i][2]))
        end
    else
        for apt in apts_by_strip_north
            push!(apt_order_north, (apt[1], apt[2]))
        end
        n_south_half = div(n_south, 2)
        for i in 1:n_south_half
            push!(apt_order_south, (apts_by_strip_south[i][1], apts_by_strip_south[i][2]))
        end
        push!(apt_order_south, (stair_area, -1))
        for i in (n_south_half + 1):n_south
            push!(apt_order_south, (apts_by_strip_south[i][1], apts_by_strip_south[i][2]))
        end
    end

    cr = [centroid_x, centroid_y]
    y_north_base = y_min + h_south

    x_start_north, x_end_north, apt_widths_north, _ = create_strip_apartments(apt_order_north, x_min, y_north_base, h_north)

    x_start_south, x_end_south, apt_widths_south, apt_types_south = create_strip_apartments(apt_order_south, x_min, y_min, h_south)

    x_east_wall_first_north = x_end_north[1]
    x_east_wall_first_south = x_end_south[1]
    x_core_start = min(x_east_wall_first_north, x_east_wall_first_south)

    x_west_wall_last_north = x_start_north[end]
    x_west_wall_last_south = x_start_south[end]
    x_core_end = max(x_west_wall_last_north, x_west_wall_last_south)

    core_length = x_core_end - x_core_start
    y_core = y_min + h_south - core_width / 2

    vertices_core_local = [
        x_core_start y_core;
        x_core_end y_core;
        x_core_end y_core + core_width;
        x_core_start y_core + core_width
    ]

    core_local_poly = PolyShape([vertices_core_local], 1)
    core_polyshape = polyShape.polyRotate(core_local_poly, -rotation_angle, cr)

    vec_polyshapes_north, extension_heights_north = extend_apartments_to_core(x_start_north, x_end_north, apt_widths_north, y_north_base, h_north, x_core_start, x_core_end, y_core, core_width, rotation_angle, cr, :north)

    vec_polyshapes_south, extension_heights_south = extend_apartments_to_core(x_start_south, x_end_south, apt_widths_south, y_min, h_south, x_core_start, x_core_end, y_core, core_width, rotation_angle, cr, :south)

    vec_terraces_north = PolyShape[]
    vec_terraces_south = PolyShape[]

    if has_terraces
        y_terrace_base_north = [y_north_base + h_north + extension_heights_north[i] for i in eachindex(apt_order_north)]
        vec_terraces_north = create_strip_terraces(apt_order_north, terrace_areas, apt_widths_north, x_start_north, y_terrace_base_north, rotation_angle, cr, :north)

        y_terrace_base_south = [y_min - extension_heights_south[i] for i in eachindex(apt_order_south)]
        vec_terraces_south = create_strip_terraces(apt_order_south, terrace_areas, apt_widths_south, x_start_south, y_terrace_base_south, rotation_angle, cr, :south)
    end

    stair_idx = findfirst(t -> t == -1, apt_types_south)
    stair_polyshape = vec_polyshapes_south[stair_idx]
    stair_width = apt_widths_south[stair_idx]

    results = Dict(
        "feasible" => true,
        "status" => "LOCALLY_SOLVED",
        "n_apts_north" => n_north,
        "n_apts_south" => n_south,
        "apt_areas_north" => [apt[1] for apt in apt_order_north],
        "apt_areas_south" => [apt[1] for apt in apt_order_south if apt[2] != -1],
        "height_north" => round(h_north, digits=2),
        "height_south" => round(h_south, digits=2),
        "unused_north" => round(unused_north, digits=2),
        "unused_south" => round(unused_south, digits=2),
        "total_unused" => round(total_unused, digits=2),
        "floor_width" => W,
        "floor_height" => H,
        "core_width" => core_width,
        "core_length" => core_length,
        "core_polyshape" => core_polyshape,
        "stair_polyshape" => stair_polyshape,
        "stair_width" => round(stair_width, digits=2),
        "stair_height" => round(h_south, digits=2),
        "stair_area" => round(stair_area, digits=2),
        "vec_polyshapes_all" => vcat(vec_polyshapes_north, vec_polyshapes_south),
        "vec_terraces_all" => vcat(vec_terraces_north, vec_terraces_south),
        "has_terraces" => has_terraces
    )


    return results
end
