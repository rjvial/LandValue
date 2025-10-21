function opti_floor_plan(floor_poly::PolyShape, apt_areas::Vector{Float64}, apt_counts::Vector{Int}; core_width::Float64 = 2.0)

    if length(apt_areas) != length(apt_counts)
        error("apt_areas and apt_counts must have the same length")
    end

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
    all_apts = Tuple{Float64, Int, Int}[]
    for i in 1:num_apt_types
        for j in 1:apt_counts[i]
            push!(all_apts, (apt_areas[i], i, j))
        end
    end

    sort!(all_apts, by = x -> x[1], rev = true)

    apts_by_strip_north = Tuple{Float64, Int, Int}[]
    apts_by_strip_south = Tuple{Float64, Int, Int}[]

    if total_apts >= 4
        push!(apts_by_strip_north, all_apts[1])
        push!(apts_by_strip_north, all_apts[2])
        push!(apts_by_strip_south, all_apts[3])
        push!(apts_by_strip_south, all_apts[4])

        area_north = all_apts[1][1] + all_apts[2][1]
        area_south = all_apts[3][1] + all_apts[4][1]

        for i in 5:total_apts
            if area_south < area_north
                push!(apts_by_strip_south, all_apts[i])
                area_south += all_apts[i][1]
            else
                push!(apts_by_strip_north, all_apts[i])
                area_north += all_apts[i][1]
            end
        end
    else
        half_total = total_apts ÷ 2
        for i in 1:half_total
            push!(apts_by_strip_north, all_apts[i])
        end
        for i in (half_total + 1):total_apts
            push!(apts_by_strip_south, all_apts[i])
        end
        area_north = sum(apt[1] for apt in apts_by_strip_north)
        area_south = sum(apt[1] for apt in apts_by_strip_south)
    end

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
    apt_order_north = Float64[]
    apt_order_south = Float64[]

    n_north = length(apts_by_strip_north)
    n_south = length(apts_by_strip_south)

    if total_apts >= 4
        push!(apt_order_north, apts_by_strip_north[2][1])
        if n_north > 2
            for i in 3:n_north
                push!(apt_order_north, apts_by_strip_north[i][1])
            end
        end
        push!(apt_order_north, apts_by_strip_north[1][1])

        push!(apt_order_south, apts_by_strip_south[2][1])
        if n_south > 2
            for i in 3:n_south
                push!(apt_order_south, apts_by_strip_south[i][1])
            end
        end
        push!(apt_order_south, apts_by_strip_south[1][1])
    else
        for apt in apts_by_strip_north
            push!(apt_order_north, apt[1])
        end
        for apt in apts_by_strip_south
            push!(apt_order_south, apt[1])
        end
    end

    # Create apartment polygons in rotated coordinate system
    vec_polyshapes_north = PolyShape[]
    vec_polyshapes_south = PolyShape[]
    x_start_north = Float64[]
    x_end_north = Float64[]
    apt_widths_north = Float64[]

    cr = [0.0, 0.0]

    x_current_north = x_min
    y_north_base = y_min + h_south
    for apt_area in apt_order_north
        apt_width = apt_area / h_north

        vertices_local = [
            x_current_north y_north_base;
            x_current_north + apt_width y_north_base;
            x_current_north + apt_width y_north_base + h_north;
            x_current_north y_north_base + h_north
        ]

        local_poly = PolyShape([vertices_local], 1)
        rotated_poly = polyShape.polyRotate(local_poly, -rotation_angle, cr)

        rotated_poly.Vertices[1][:, 1] .+= centroid_x
        rotated_poly.Vertices[1][:, 2] .+= centroid_y

        push!(vec_polyshapes_north, rotated_poly)
        push!(x_start_north, x_current_north)
        push!(x_end_north, x_current_north + apt_width)
        push!(apt_widths_north, apt_width)
        x_current_north += apt_width
    end

    x_start_south = Float64[]
    x_end_south = Float64[]
    apt_widths_south = Float64[]

    x_current_south = x_min

    for apt_area in apt_order_south
        apt_width = apt_area / h_south

        vertices_local = [
            x_current_south y_min;
            x_current_south + apt_width y_min;
            x_current_south + apt_width y_min + h_south;
            x_current_south y_min + h_south
        ]

        local_poly = PolyShape([vertices_local], 1)
        rotated_poly = polyShape.polyRotate(local_poly, -rotation_angle, cr)

        rotated_poly.Vertices[1][:, 1] .+= centroid_x
        rotated_poly.Vertices[1][:, 2] .+= centroid_y

        push!(vec_polyshapes_south, rotated_poly)
        push!(x_start_south, x_current_south)
        push!(x_end_south, x_current_south + apt_width)
        push!(apt_widths_south, apt_width)
        x_current_south += apt_width
    end

    # Create central core spanning between end apartments
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

    core_polyshape.Vertices[1][:, 1] .+= centroid_x
    core_polyshape.Vertices[1][:, 2] .+= centroid_y

    # Calculate core-apartment intersections
    intersection_areas_north = Float64[]
    for i in eachindex(vec_polyshapes_north)
        intersection_poly = polyShape.polyIntersection(vec_polyshapes_north[i], core_polyshape)
        intersection_area = polyShape.polyArea(intersection_poly)
        push!(intersection_areas_north, intersection_area)
    end

    intersection_areas_south = Float64[]
    for i in eachindex(vec_polyshapes_south)
        intersection_poly = polyShape.polyIntersection(vec_polyshapes_south[i], core_polyshape)
        intersection_area = polyShape.polyArea(intersection_poly)
        push!(intersection_areas_south, intersection_area)
    end

    # Extend apartments into core area
    for i in eachindex(vec_polyshapes_north)
        extension_height = intersection_areas_north[i] / apt_widths_north[i]

        vertices_extended_local = [
            x_start_north[i] y_north_base;
            x_end_north[i] y_north_base;
            x_end_north[i] y_north_base + h_north + extension_height;
            x_start_north[i] y_north_base + h_north + extension_height
        ]

        extended_local_poly = PolyShape([vertices_extended_local], 1)
        vec_polyshapes_north[i] = polyShape.polyRotate(extended_local_poly, -rotation_angle, cr)

        vec_polyshapes_north[i].Vertices[1][:, 1] .+= centroid_x
        vec_polyshapes_north[i].Vertices[1][:, 2] .+= centroid_y
    end

    for i in eachindex(vec_polyshapes_south)
        extension_height = intersection_areas_south[i] / apt_widths_south[i]

        vertices_extended_local = [
            x_start_south[i] y_min - extension_height;
            x_end_south[i] y_min - extension_height;
            x_end_south[i] y_min + h_south;
            x_start_south[i] y_min + h_south
        ]

        extended_local_poly = PolyShape([vertices_extended_local], 1)
        vec_polyshapes_south[i] = polyShape.polyRotate(extended_local_poly, -rotation_angle, cr)

        vec_polyshapes_south[i].Vertices[1][:, 1] .+= centroid_x
        vec_polyshapes_south[i].Vertices[1][:, 2] .+= centroid_y
    end

    # Subtract core from apartments
    for i in eachindex(vec_polyshapes_north)
        vec_polyshapes_north[i] = polyShape.polyDifference(vec_polyshapes_north[i], core_polyshape)
    end

    for i in eachindex(vec_polyshapes_south)
        vec_polyshapes_south[i] = polyShape.polyDifference(vec_polyshapes_south[i], core_polyshape)
    end

    results = Dict(
        "feasible" => true,
        "status" => "LOCALLY_SOLVED",
        "n_apts_north" => n_north,
        "n_apts_south" => n_south,
        "apt_areas_north" => apt_order_north,
        "apt_areas_south" => apt_order_south,
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
        "vec_polyshapes_all" => vcat(vec_polyshapes_north, vec_polyshapes_south)
    )


    return results
end
