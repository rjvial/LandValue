function opti_piso_depto(floor_poly::PolyShape, apt_areas::Vector{Float64}, apt_counts::Vector{Int}; core_width::Float64 = 2.0)

    if length(apt_areas) != length(apt_counts)
        error("apt_areas and apt_counts must have the same length")
    end

    if floor_poly.NumRegions != 1
        error("floor_poly must be a single rectangular polygon")
    end

    vertices_original = floor_poly.Vertices[1]

    centroid_x = sum(vertices_original[1:end-1, 1]) / (size(vertices_original, 1) - 1)
    centroid_y = sum(vertices_original[1:end-1, 2]) / (size(vertices_original, 1) - 1)

    edge1 = vertices_original[2, :] - vertices_original[1, :]
    angle_original = atan(edge1[2], edge1[1])

    rotation_angle = -angle_original
    cos_theta = cos(rotation_angle)
    sin_theta = sin(rotation_angle)

    vertices_centered = copy(vertices_original)
    vertices_centered[:, 1] .- centroid_x
    vertices_centered[:, 2] .- centroid_y

    vertices_rotated = similar(vertices_original)
    for i in axes(vertices_original, 1)
        dx = vertices_original[i, 1] - centroid_x
        dy = vertices_original[i, 2] - centroid_y
        vertices_rotated[i, 1] = dx * cos_theta - dy * sin_theta
        vertices_rotated[i, 2] = dx * sin_theta + dy * cos_theta
    end

    x_coords = vertices_rotated[:, 1]
    y_coords = vertices_rotated[:, 2]
    W_calc = maximum(x_coords) - minimum(x_coords)
    H_calc = maximum(y_coords) - minimum(y_coords)

    if H_calc > W_calc
        rotation_angle += π/2
        cos_theta = cos(rotation_angle)
        sin_theta = sin(rotation_angle)

        for i in axes(vertices_original, 1)
            dx = vertices_original[i, 1] - centroid_x
            dy = vertices_original[i, 2] - centroid_y
            vertices_rotated[i, 1] = dx * cos_theta - dy * sin_theta
            vertices_rotated[i, 2] = dx * sin_theta + dy * cos_theta
        end

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

    apts_north = zeros(Int, num_apt_types)
    apts_south = zeros(Int, num_apt_types)

    for i in 1:num_apt_types
        half_count = apt_counts[i] ÷ 2
        apts_north[i] = half_count
        apts_south[i] = apt_counts[i] - half_count
    end

    area_north = sum(apt_areas[i] * apts_north[i] for i in 1:num_apt_types)
    area_south = sum(apt_areas[i] * apts_south[i] for i in 1:num_apt_types)

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

    widths_north = zeros(Float64, num_apt_types)
    widths_south = zeros(Float64, num_apt_types)

    for i in 1:num_apt_types
        if apts_north[i] > 0
            widths_north[i] = (apt_areas[i] * apts_north[i]) / h_north
        end
        if apts_south[i] > 0
            widths_south[i] = (apt_areas[i] * apts_south[i]) / h_south
        end
    end

    total_width_north = sum(widths_north)
    total_width_south = sum(widths_south)

    unused_north = W - total_width_north
    unused_south = W - total_width_south
    total_unused = unused_north * h_north + unused_south * h_south

    x_min = minimum(x_coords)
    y_min = minimum(y_coords)
    y_min += h_slack/2

    vec_polyshapes_north = PolyShape[]
    vec_polyshapes_south = PolyShape[]
    x_start_north = Float64[]
    x_end_north = Float64[]
    apt_widths_north = Float64[]

    x_current_north = x_min
    for i in 1:num_apt_types
        for j in 1:apts_north[i]
            apt_width = apt_areas[i] / h_north

            vertices_local = [
                x_current_north y_min;
                x_current_north + apt_width y_min;
                x_current_north + apt_width y_min + h_north;
                x_current_north y_min + h_north
            ]

            vertices_rotated_back = similar(vertices_local)
            cos_back = cos(-rotation_angle)
            sin_back = sin(-rotation_angle)

            for k in axes(vertices_local, 1)
                dx = vertices_local[k, 1]
                dy = vertices_local[k, 2]
                x_rot = dx * cos_back - dy * sin_back
                y_rot = dx * sin_back + dy * cos_back
                vertices_rotated_back[k, 1] = x_rot + centroid_x
                vertices_rotated_back[k, 2] = y_rot + centroid_y
            end

            push!(vec_polyshapes_north, PolyShape([vertices_rotated_back], 1))
            push!(x_start_north, x_current_north)
            push!(x_end_north, x_current_north + apt_width)
            push!(apt_widths_north, apt_width)
            x_current_north += apt_width
        end
    end

    x_start_south = Float64[]
    x_end_south = Float64[]
    apt_widths_south = Float64[]

    x_current_south = x_min
    y_south_base = y_min + h_north

    for i in 1:num_apt_types
        for j in 1:apts_south[i]
            apt_width = apt_areas[i] / h_south

            vertices_local = [
                x_current_south y_south_base;
                x_current_south + apt_width y_south_base;
                x_current_south + apt_width y_south_base + h_south;
                x_current_south y_south_base + h_south
            ]

            vertices_rotated_back = similar(vertices_local)
            cos_back = cos(-rotation_angle)
            sin_back = sin(-rotation_angle)

            for k in axes(vertices_local, 1)
                dx = vertices_local[k, 1]
                dy = vertices_local[k, 2]
                x_rot = dx * cos_back - dy * sin_back
                y_rot = dx * sin_back + dy * cos_back
                vertices_rotated_back[k, 1] = x_rot + centroid_x
                vertices_rotated_back[k, 2] = y_rot + centroid_y
            end

            push!(vec_polyshapes_south, PolyShape([vertices_rotated_back], 1))
            push!(x_start_south, x_current_south)
            push!(x_end_south, x_current_south + apt_width)
            push!(apt_widths_south, apt_width)
            x_current_south += apt_width
        end
    end

    x_east_wall_first_north = x_end_north[1]
    x_east_wall_first_south = x_end_south[1]
    x_core_start = min(x_east_wall_first_north, x_east_wall_first_south)

    x_west_wall_last_north = x_start_north[end]
    x_west_wall_last_south = x_start_south[end]
    x_core_end = max(x_west_wall_last_north, x_west_wall_last_south)

    core_length = x_core_end - x_core_start
    y_core = y_min + h_north - core_width / 2

    vertices_core_local = [
        x_core_start y_core;
        x_core_end y_core;
        x_core_end y_core + core_width;
        x_core_start y_core + core_width
    ]

    vertices_core_rotated = similar(vertices_core_local)
    cos_back = cos(-rotation_angle)
    sin_back = sin(-rotation_angle)

    for k in axes(vertices_core_local, 1)
        dx = vertices_core_local[k, 1]
        dy = vertices_core_local[k, 2]
        x_rot = dx * cos_back - dy * sin_back
        y_rot = dx * sin_back + dy * cos_back
        vertices_core_rotated[k, 1] = x_rot + centroid_x
        vertices_core_rotated[k, 2] = y_rot + centroid_y
    end

    core_polyshape = PolyShape([vertices_core_rotated], 1)

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

    for i in eachindex(vec_polyshapes_north)
        extension_height = intersection_areas_north[i] / apt_widths_north[i]

        vertices_extended_local = [
            x_start_north[i] y_min - extension_height;
            x_end_north[i] y_min - extension_height;
            x_end_north[i] y_min + h_north;
            x_start_north[i] y_min + h_north
        ]

        vertices_extended_rotated = similar(vertices_extended_local)
        cos_back = cos(-rotation_angle)
        sin_back = sin(-rotation_angle)

        for k in axes(vertices_extended_local, 1)
            dx = vertices_extended_local[k, 1]
            dy = vertices_extended_local[k, 2]
            x_rot = dx * cos_back - dy * sin_back
            y_rot = dx * sin_back + dy * cos_back
            vertices_extended_rotated[k, 1] = x_rot + centroid_x
            vertices_extended_rotated[k, 2] = y_rot + centroid_y
        end

        vec_polyshapes_north[i] = PolyShape([vertices_extended_rotated], 1)
    end

    for i in eachindex(vec_polyshapes_south)
        extension_height = intersection_areas_south[i] / apt_widths_south[i]

        vertices_extended_local = [
            x_start_south[i] y_min + h_north;
            x_end_south[i] y_min + h_north;
            x_end_south[i] y_min + h_north + h_south + extension_height;
            x_start_south[i] y_min + h_north + h_south + extension_height
        ]

        vertices_extended_rotated = similar(vertices_extended_local)
        cos_back = cos(-rotation_angle)
        sin_back = sin(-rotation_angle)

        for k in axes(vertices_extended_local, 1)
            dx = vertices_extended_local[k, 1]
            dy = vertices_extended_local[k, 2]
            x_rot = dx * cos_back - dy * sin_back
            y_rot = dx * sin_back + dy * cos_back
            vertices_extended_rotated[k, 1] = x_rot + centroid_x
            vertices_extended_rotated[k, 2] = y_rot + centroid_y
        end

        vec_polyshapes_south[i] = PolyShape([vertices_extended_rotated], 1)
    end

    for i in eachindex(vec_polyshapes_north)
        vec_polyshapes_north[i] = polyShape.polyDifference(vec_polyshapes_north[i], core_polyshape)
    end

    for i in eachindex(vec_polyshapes_south)
        vec_polyshapes_south[i] = polyShape.polyDifference(vec_polyshapes_south[i], core_polyshape)
    end

    results = Dict(
        "feasible" => true,
        "status" => "LOCALLY_SOLVED",
        "widths_north" => round.(widths_north, digits=2),
        "widths_south" => round.(widths_south, digits=2),
        "apts_north" => apts_north,
        "apts_south" => apts_south,
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
