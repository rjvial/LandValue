module polyShape

using LandValue, ArchGDAL, LazySets, DataFrames, LinearAlgebra, Proj, Combinatorics


function polyUnion(ps_::PolyShape)::PolyShape
    ps = deepcopy(ps_)
    num_regions = ps.NumRegions
    ps_out = []
    for i = 1:num_regions
        if i == 1
            ps_out = polyShape.subShape(ps, 1)
        else
            ps_out = polyShape.polyUnion(ps_out, polyShape.subShape(ps, i))
        end
    end
    return ps_out
end
function polyUnion(vec_ps_::Vector{PolyShape})::PolyShape
    vec_ps = deepcopy(vec_ps_)

    num_ps = length(vec_ps)
    ps_out = []
    for i = 1:num_ps
        ps_i = polyUnion(vec_ps[i])
        if i == 1
            ps_out = deepcopy(ps_i)
        else
            ps_out = polyShape.polyUnion(ps_out, ps_i)
        end
    end
    return ps_out
end
function polyUnion(ps_s_::PolyShape, ps_c_::PolyShape)::PolyShape
    ps_s = deepcopy(ps_s_)
    ps_c = deepcopy(ps_c_)

    path_s = polyClipper.shape2clipper(ps_s)
    path_c = polyClipper.shape2clipper(ps_c)
    result_path = polyClipper.clipper_union(path_s, path_c)
    ps_out = polyClipper.clipper2shape(result_path, PolyShape)
    return ps_out
end


function polyDifference(ps_s_::PolyShape, ps_c_::PolyShape)::PolyShape
    ps_s = deepcopy(ps_s_)
    ps_c = deepcopy(ps_c_)

    path_s = polyClipper.shape2clipper(ps_s)
    path_c = polyClipper.shape2clipper(ps_c)
    d_path = polyClipper.clipper_difference(path_s, path_c)
    ps_out = polyClipper.clipper2shape(d_path, PolyShape)
    return ps_out
end


function polyIntersect(ps_s_::PolyShape, ps_c_::PolyShape)::PolyShape
    ps_s = deepcopy(ps_s_)
    ps_c = deepcopy(ps_c_)
    ps_c = polyShape.polyUnion(ps_c)

    path_c = polyClipper.shape2clipper(ps_c)
    vec_V = []
    for i = 1:ps_s.NumRegions
        ps_s_i = polyShape.subShape(ps_s, i)
        path_s_i = polyClipper.shape2clipper(ps_s_i)
        i_path = polyClipper.clipper_intersection(path_s_i, path_c)
        ps_out_i = polyClipper.clipper2shape(i_path, PolyShape)
        for j = 1:ps_out_i.NumRegions
            push!(vec_V, ps_out_i.Vertices[j])
        end
    end
    ps_out = PolyShape(vec_V, length(vec_V))    

    return ps_out
end


function polyShrink(ps_base_, ratio)
    ps_base = deepcopy(ps_base_)

    area_target = polyShape.polyArea(ps_base) * ratio
    ps_actual = polyShape.polyCopy(ps_base)
    area_actual = polyShape.polyArea(ps_actual)
    delta = -0.01
    while true
        p = abs((area_actual - area_target) / area_target)
        delta = -0.1 * p
        if p <= 0.00001
            return ps_actual
        else
            ps_actual = polyClipper.polyOffset(ps_actual, delta)
            area_actual = polyShape.polyArea(ps_actual)
        end
    end
end


function polyOrientation(ps::PolyShape)::Union{Int64,Array{Int64,1}}
    numRegions = ps.NumRegions
    ccw_vec = fill(0, numRegions)

    for i = 1:numRegions
        V_i = ps.Vertices[i]
        s = 0
        numVertices = size(V_i, 1)
        for j = 1:numVertices
            if j <= numVertices - 1
                x0 = V_i[j, 1]
                x1 = V_i[j+1, 1]
                y0 = V_i[j, 2]
                y1 = V_i[j+1, 2]
            else
                x0 = V_i[numVertices, 1]
                x1 = V_i[1, 1]
                y0 = V_i[numVertices, 2]
                y1 = V_i[1, 2]
            end
            s += (x1 - x0) * (y1 + y0)
        end
        ccw_vec[i] = s < 0 ? 1 : -1
    end
    if length(ccw_vec) == 1
        ccw_vec = ccw_vec[1]
    end
    return ccw_vec
end


function convHull(V::Array{Float64,2})::Array{Float64,2}

    n = size(V,1)
    v = [[V[i,1], V[i,2]] for i=1:n]
    ch_v = LazySets.convex_hull(v)

    V_out = [0 0]; for i in eachindex(ch_v); V_out=[V_out; ch_v[i]']; end; V_out = V_out[2:end,:]

    return V_out
end
function convHull(ps::PolyShape)::PolyShape
    hull_vertices = convHull(ps.Vertices[1])
    return PolyShape([hull_vertices], 1)
end


function line2Box(ls::LineShape, width::Real, rev::Bool=false)
    V_ls = ls.Vertices[1]
    dx = polyShape.lineLength(ls)
    dy = width
    p =  rev ? PointShape(V_ls[1,:]', 1) : PointShape(V_ls[2,:]', 1)
    angulo = rev ? polyShape.lineAngle(ls) : polyShape.lineAngle(ls) - pi
    ps_out = polyShape.polyBox(p, dx, dy, angulo)
    return ps_out
    
end


function partialPolyOffset(ps::PolyShape, vec_partial_offset_id::Vector{Int}, vec_partial_offset_dist::Vector{T}) where {T<:Real}

    function findParallelId(ls_base, vec_ls_comp, distance_side)
        # Encuentra el id del segmento de vec_ls_comp paralelo al segmento ls_base
        parallel_id = findall(x -> x == 1, [polyShape.isLineLineParallel(ls_base, vec_ls_comp[j]) for j in eachindex(vec_ls_comp)])
        if length(parallel_id) >= 2
            dist_offset = abs.([polyShape.calculateDistance(ls_base, vec_ls_comp[j]) for j in eachindex(vec_ls_comp)][parallel_id])
            parallel_id = parallel_id[argmin(abs.(dist_offset .- abs(distance_side)))]
        elseif length(parallel_id) == 1
            parallel_id = parallel_id[1]
        end
        return parallel_id
    end

    function polyShape2offsetPolyShape(ps, vec_partial_offset_id, vec_partial_offset_dist)
        # Genera vector de lineas offset en los lados vec_partial_offset_id y a la distancia vec_partial_offset_dist
        vec_ps_lines, _ = polyShape.shape2vector(ps)
        num_ps_lines = length(vec_ps_lines)

        # Initialize distance vector
        vec_todos_offset_dist_ = [0.0 for _ in 1:num_ps_lines]
        for i in eachindex(vec_partial_offset_dist)
            vec_todos_offset_dist_[vec_partial_offset_id[i]] = vec_partial_offset_dist[i]
        end
        vec_unique_dist = sort(unique(vec_partial_offset_dist))
        vec_ps_offsets = [polyClipper.polyOffset(ps, vec_unique_dist[j]) for j in eachindex(vec_unique_dist)]

        vec_offsets_lines = []
        for i in eachindex(vec_ps_offsets)
            vec_offsets_lines_i, _ = polyShape.shape2vector(vec_ps_offsets[i])
            push!(vec_offsets_lines, vec_offsets_lines_i)
        end
    
        num_ps_lines = length(vec_todos_offset_dist_)
        nonIntersecting_offset_lines = Vector{LineShape}()
        for i in eachindex(vec_todos_offset_dist_) #Recorre cada lado de ps
            distance_side_i = vec_todos_offset_dist_[i]
            if abs(distance_side_i) > 0
                id_unique_dist = findfirst(x -> x == distance_side_i, vec_unique_dist)
                vec_offsets_lines_i = vec_offsets_lines[id_unique_dist]

                parallel_offset_indices = findParallelId(vec_ps_lines[i], vec_offsets_lines_i, distance_side_i)
                if ~isempty(parallel_offset_indices)
                    added_line = vec_offsets_lines_i[parallel_offset_indices]
                    push!(nonIntersecting_offset_lines, added_line)
                else
                    parallel_line = LineShape([[0 0; 0 0]],1)
                    push!(nonIntersecting_offset_lines, parallel_line)
                end
            else
                push!(nonIntersecting_offset_lines, vec_ps_lines[i])
            end
        end
 
        # Genera polyshape a partir de las lineas del offset sin intersectar
        num_offset_lines = length(nonIntersecting_offset_lines)
        V_aux = [0 0]
        for i = 1:num_offset_lines
            current_side_index = i            
            prev_side_index = mod1(current_side_index - 1, num_offset_lines)
            next_side_index = mod1(current_side_index + 1, num_offset_lines)

            cond_current_side_presente = ~(nonIntersecting_offset_lines[current_side_index].Vertices[1][1,:]' == [0 0] && 
                                            nonIntersecting_offset_lines[current_side_index].Vertices[1][2,:]' == [0 0])
            cond_prev_side_presente = ~(nonIntersecting_offset_lines[prev_side_index].Vertices[1][1,:]' == [0 0] && 
                                        nonIntersecting_offset_lines[prev_side_index].Vertices[1][2,:]' == [0 0])
            cond_next_side_presente = ~(nonIntersecting_offset_lines[next_side_index].Vertices[1][1,:]' == [0 0] && 
                                        nonIntersecting_offset_lines[next_side_index].Vertices[1][2,:]' == [0 0])

            if cond_current_side_presente && cond_prev_side_presente
                lin1 = polyShape.transformLine(nonIntersecting_offset_lines[prev_side_index], :extend, 100)
                lin2 = polyShape.transformLine(nonIntersecting_offset_lines[current_side_index], :extend, 100)
                intersection_point = polyShape.intersectLines(lin1, lin2)
            elseif cond_current_side_presente && cond_next_side_presente
                lin1 = polyShape.transformLine(nonIntersecting_offset_lines[current_side_index], :extend, 100)
                lin2 = polyShape.transformLine(nonIntersecting_offset_lines[next_side_index], :extend, 100)
                intersection_point = polyShape.intersectLines(lin1, lin2)
            elseif cond_prev_side_presente && cond_next_side_presente
                lin1 = polyShape.transformLine(nonIntersecting_offset_lines[prev_side_index], :extend, 100)
                lin2 = polyShape.transformLine(nonIntersecting_offset_lines[next_side_index], :extend, 100)
                intersection_point = polyShape.intersectLines(lin1, lin2)
            end
            V_aux = [vcat(V_aux[1], intersection_point.Vertices[1, :]')]

        end
        ps_out = PolyShape([V_aux[1][2:end, :]], 1)

        return ps_out, vec_todos_offset_dist_
    end

    max_dist = maximum(vec_partial_offset_dist) #-4
    ps_offset_max = polyClipper.polyOffset(ps, max_dist)
    num_regions_offset_max = ps_offset_max.NumRegions
    if num_regions_offset_max >= 2
        vec_line_ps, _ = polyShape.shape2vector(ps)
        num_ps_lines = length(vec_line_ps)
        vec_todos_offset_dist = zeros(num_ps_lines)
        vec_todos_offset_dist[vec_partial_offset_id] .= copy(vec_partial_offset_dist)

        min_dist = minimum(vec_partial_offset_dist) #-7
        ps_offset_min = polyClipper.polyOffset(ps, min_dist)

        output_ps = []
        for r = 1:ps_offset_min.NumRegions
            ps_offset_min_r = polyShape.subShape(ps_offset_min, r)
            vec_line_offset_min_r, _ = polyShape.shape2vector(ps_offset_min_r)
            num_offset_line_r = length(vec_line_offset_min_r)
            vec_id_offset_r = [i for i = 1:num_offset_line_r]
            vec_id_ps_r = [findParallelId(vec_line_offset_min_r[j], vec_line_ps, vec_partial_offset_dist[j]) for j = 1:num_offset_line_r]
            vec_dist_r = copy(vec_todos_offset_dist[vec_id_ps_r])
            delta_r = vec_dist_r .- min_dist
            ps_offset_r, _ = polyShape2offsetPolyShape(ps_offset_min_r, vec_id_offset_r, delta_r)
            if r == 1
                output_ps = deepcopy(ps_offset_r)
            else
                output_ps = polyShape.polyUnion(output_ps, ps_offset_r)
            end
        end
    else
        output_ps, vec_todos_offset_dist = polyShape2offsetPolyShape(ps, vec_partial_offset_id, vec_partial_offset_dist)
    end

    return output_ps
end
function partialPolyOffset(ps::PolyShape, vec_partial_offset_id::Vector{Int}, dist::T) where {T<:Real}
    vec_partial_offset_dist = [dist for _ in eachindex(vec_partial_offset_id)]
    ps_out = polyShape.partialPolyOffset(ps, vec_partial_offset_id, vec_partial_offset_dist)
    return ps_out
end


function lineAngle(sh::PosDimGeom)
    if isa(sh, PolyShape)
        numLines = sh.NumRegions
        VV = []
        for i = 1:numLines
            VV = push!(VV, vcat(sh.Vertices[i], sh.Vertices[i][1, :]'))
        end
        ls = LineShape(VV, numLines)
    else
        ls = deepcopy(sh)
        numLines = ls.NumLines
    end
    vec_angles = Array{Array{Float64,1},1}(undef, numLines)
    for i = 1:numLines
        ls_i = polyShape.subShape(ls, i)
        V_k = []
        for k = 1:size(ls_i.Vertices[1], 1)-1
            p0 = ls_i.Vertices[1][k, :]
            p1 = ls_i.Vertices[1][k+1, :]
            dx = p1[1] - p0[1]
            dy = p1[2] - p0[2]
            if dy >= 0
                angle_ik = acos(dx / sqrt(dx^2 + dy^2))
            else
                angle_ik = pi + acos(-dx / sqrt(dx^2 + dy^2))
            end
            V_k = push!(V_k, angle_ik)
        end
        vec_angles[i] = V_k
    end
    if length(vec_angles) == 1
        if length(vec_angles[1]) == 1
            out = vec_angles[1][1]
        else
            out = vec_angles[1]
        end
    else
        out = vec_angles
    end

    return out
end


function isPolyConvex(ps::PolyShape)::Bool

    function checkConvex(V::Array{Float64,2})::Bool
        size(V, 1) < 3 && return true
        size(V, 2) != 2 && throw(ArgumentError("Input must be an Nx2 array of 2D points"))
        
        numPoints = size(V, 1)
        numPoints < 3 && return true
        
        # For triangles, always convex
        numPoints == 3 && return true
        
        px, py = V[:, 1], V[:, 2]
        
        # Calculate cross product sign for first edge pair
        v1 = [px[end] - px[end-1], py[end] - py[end-1]]
        v2 = [px[1] - px[end], py[1] - py[end]]
        cross_product = v1[1] * v2[2] - v1[2] * v2[1]
        
        # Skip if vectors are colinear (zero cross product)
        if abs(cross_product) < 1e-12
            reference_sign = 0
        else
            reference_sign = sign(cross_product)
        end
        
        # Check all subsequent edge pairs
        for i = 1:numPoints-1
            v1 = v2
            v2 = [px[mod1(i+1, numPoints)] - px[i], py[mod1(i+1, numPoints)] - py[i]]
            cross_product = v1[1] * v2[2] - v1[2] * v2[1]
            
            # Skip colinear vectors
            abs(cross_product) < 1e-12 && continue
            
            current_sign = sign(cross_product)
            
            # Set reference sign if not yet set
            if reference_sign == 0
                reference_sign = current_sign
            elseif current_sign != reference_sign
                return false
            end
        end
        
        return true
    end


    # Given a set of points determine if they form a convex polygon
    numRegiones = ps.NumRegions
    isConvexVec = fill(false, numRegiones)
    for j = 1:numRegiones
        V_j = ps.Vertices[j]
        isConvexVec[j] = checkConvex(V_j)
    end
    return isConvexVec
end


function isPolyInPoly(ps_s::PolyShape, ps::PolyShape)::Bool
    ps_r = polyDifference(ps_s, ps)
    if polyShape.polyArea(ps_r) < 0.01
        return true
    else
        return false
    end
end


function subShape(shape::PolyShape, k::Int=1)::PolyShape
    out_shape = PolyShape([shape.Vertices[k]], 1)
    return out_shape
end
function subShape(shape::PolyShape, v::Array{Int64,1})::PolyShape
    out_shape = PolyShape(shape.Vertices[v], length(v))
    return out_shape
end
function subShape(shape::LineShape, k::Int=1)::LineShape
    out_shape = LineShape([shape.Vertices[k]], 1)
    return out_shape
end
function subShape(shape::PointShape, k::Int=1)::PointShape
    out_shape = PointShape([shape.Vertices[k, 1] shape.Vertices[k, 2]], 1)
    return out_shape
end


function shapeVertex(shape::PolyShape, k::Int, v::Int)::PointShape
    out_shape = PointShape(shape.Vertices[k][v, :]', 1)
    return out_shape
end
function shapeVertex(shape::PolyShape)::PointShape
    numRegions = shape.NumRegions
    V = [0 0]
    numVertices = 0
    for i = 1:numRegions
        numVertices_i = size(shape.Vertices[i], 1)
        numVertices = numVertices + numVertices_i
        V = [V; shape.Vertices[i]]
    end
    V = V[2:end, :]
    out_shape = PointShape(V, numVertices)
    return out_shape
end
function shapeVertex(shape::LineShape, k::Int=1, v::Int=1)::PointShape
    out_shape = PointShape(shape.Vertices[k][v, :]', 1)
    return out_shape
end


function numVertices(shape::PolyShape, k::Int=1)::Int
    shape_k = PolyShape([shape.Vertices[k]], 1)
    num = size(shape_k.Vertices[1], 1)
    return num
end



function polyBox(pos_x::Real, pos_y::Real, dx::Real, dy::Real=dx, angulo::Real=0.0, cr=[pos_x; pos_y])::PolyShape
    V = [pos_x pos_y; pos_x+dx pos_y; pos_x+dx pos_y+dy; pos_x pos_y+dy]
    ps = PolyShape([V], 1)
    ps_out = polyShape.polyRotate(ps, angulo, cr)
    return ps_out
end
function polyBox(p::PointShape, dx::Real, dy::Real=dx, angulo::Real=0.0)::PolyShape
    pos_x = p.Vertices[1, 1]
    pos_y = p.Vertices[1, 2]
    cr = [pos_x; pos_y]
    ps_out = polyShape.polyBox(pos_x, pos_y, dx, dy, angulo, cr)
    return ps_out
end


function polyRotate(ps::PolyShape, angulo::Real, cr)::PolyShape
    R = [cos(angulo) -sin(angulo); sin(angulo) cos(angulo)]
    V = ps.Vertices[1]
    numVertices = size(V, 1)
    V_aux = [vec(R * (V[i, 1:2] - cr) + cr) for i in 1:numVertices]
    V_rot = mapreduce(permutedims, vcat, V_aux)
    ps_rot = PolyShape([V_rot], 1)
    return ps_rot
end


function polyArea(ps::PolyShape; sep_flag::Bool=false)::Union{Float64,Array{Float64,1}}
    function polygonArea(V::Array{Float64,2})::Float64
        isempty(V) && return 0.0
        size(V, 2) != 2 && throw(ArgumentError("Input must be an Nx2 array of 2D points"))
        size(V, 1) < 3 && return 0.0
        
        x, y = V[:, 1], V[:, 2]
        numPoints = length(x)
        
        area = 0.0
        j = numPoints
        
        for i = 1:numPoints
            area += (x[j] + x[i]) * (y[j] - y[i])
            j = i
        end
        
        return abs(area / 2)
    end

    numRegions = ps.NumRegions
    if numRegions >= 1
        vecArea = [polygonArea(ps.Vertices[i]) for i = 1:numRegions]
        if sep_flag
            out = vecArea
        else
            out = sum(vecArea)
        end
    else
        out = 0.0
    end
end


function setPolyOrientation(ps::PolyShape, orientacion_deseada)::PolyShape
    numRegions = ps.NumRegions
    V = ps.Vertices
    for i = 1:numRegions
        ps_i = polyShape.subShape(ps, i)
        orientacion_actual = polyShape.polyOrientation(ps_i)
        if orientacion_actual != orientacion_deseada
            ps_i = polyShape.polyReverse(ps_i)
            V[i] = ps_i.Vertices[1]
        end
    end
    ps_out = PolyShape(V, numRegions)
    return ps_out

end


function polyReverse(ps::PolyShape)::PolyShape
    numRegions = ps.NumRegions
    V = ps.Vertices
    for i = 1:numRegions
        V_i = V[i]
        V_out_i = polyShape.reversePath(V_i)
        V[i] = V_out_i
    end
    ps_out = PolyShape(V, numRegions)
    return ps_out
end


function reversePath(V::Array{Float64,2})::Array{Float64,2}
    V_ = copy(V)
    numVertices = size(V_, 1)
    V_out = fill(0.0, numVertices, 2)
    for i = 1:numVertices
        V_out[end-i+1, :] = V_[i, :]
    end
    return V_out
end


function minPolyDistance(ps1::PolyShape, ps2::PolyShape)
    numVertices_1 = polyShape.numVertices(ps1, 1)
    numVertices_2 = polyShape.numVertices(ps2, 1)
    V1 = ps1.Vertices[1]
    V2 = ps2.Vertices[1]
    dist_min = 100000
    id1_min = 0
    id2_min = 0
    for i = 1:numVertices_1
        p1_i = V1[i, :]
        for j = 1:numVertices_2
            p2_j = V2[j, :]
            dist_ij = sqrt((p1_i[1] - p2_j[1])^2 + (p1_i[2] - p2_j[2])^2)
            if dist_ij < dist_min
                dist_min = dist_ij
                id1_min = i
                id2_min = j
            end
        end
    end

    return dist_min, id1_min, id2_min
end


function polyCopy(ps::PolyShape)::PolyShape
    ps_out = deepcopy(ps)
    return ps_out
end
function polyCopy(ls::LineShape)::LineShape
    ls_out = deepcopy(ls)
    return ls_out
end
function polyCopy(p::PointShape)::PointShape
    p_out = deepcopy(p)
    return p_out
end


function cleanPolygon(ps_::PolyShape, method::Symbol)::PolyShape
    ps = polyCopy(ps_)
    numRegions = ps.NumRegions
    V = copy(ps.Vertices)
    
    if method == :duplicates
        for i = 1:numRegions-1
            ps_i = polyShape.subShape(ps, i)
            area_i = polyShape.polyArea(ps_i)
            for j = i+1:numRegions
                ps_j = polyShape.subShape(ps, j)
                area_j = polyShape.polyArea(ps_j)
                if abs(area_i - area_j) < 1
                    ps_dif = polyShape.polyDifference(ps_i, ps_j)
                    area_dif = polyShape.polyArea(ps_dif)
                    if area_dif < 1
                        V[i] = [0.0 0.0]
                    end
                end
            end
        end
    elseif method == :contained
        for i in 1:numRegions
            ps_i = polyShape.subShape(ps, i)
            for j in setdiff(1:numRegions, i)
                ps_j = polyShape.subShape(ps, j)
                if polyGdal.shapeContains(ps_i, ps_j)
                    V[j] = [0.0 0.0]
                end
            end
        end
    end
    
    V_out = []
    for i = 1:numRegions
        if size(V[i], 1) >= 2
            V_out = push!(V_out, V[i])
        end
    end
    ps_out = PolyShape(V_out, length(V_out))
    return ps_out
end


function calculateDistance(l::LineShape, p::PointShape)::Float64
    V_line = l.Vertices[1]
    V_point = p.Vertices
    q, p1, p2 = V_point[:], V_line[1, :], V_line[2, :]
    dist = sqrt(sum( ((q-p1) - ((q-p1)'*(p2-p1)) / ((p2-p1)'*(p2-p1)) * (p2-p1) ).^2))
    return dist
end
function calculateDistance(l1::LineShape, l2::LineShape)::Float64
    V1 = l1.Vertices[1]
    V2 = l2.Vertices[1]
    
    q = (V2[1, :] + V2[2, :]) / 2
    p = PointShape([q[1] q[2]], 1)
    
    p1, p2 = V1[1, :], V1[2, :]
    line_vec = p2 - p1
    point_vec = q - p1
    line_length_sq = sum(line_vec .^ 2)
    
    if line_length_sq < 1e-12
        d = sqrt(sum((q - p1) .^ 2))
    else
        projection_scalar = sum(point_vec .* line_vec) / line_length_sq
        projection = projection_scalar * line_vec
        perpendicular = point_vec - projection
        d = sqrt(sum(perpendicular .^ 2))
    end
    
    s = polyShape.halfspaceSignOfPointToLine(l1, p)
    return s * d
end
function calculateDistance(p1::PointShape, p2::PointShape)::Float64
    V1 = p1.Vertices[1, :]
    V2 = p2.Vertices[1, :]
    dist = sqrt(sum((V1 - V2) .^ 2))
    return dist
end
function calculateDistance(l1::LineShape, l2::LineShape, parallel_check::Bool)::Float64
    if parallel_check && polyShape.isLineLineParallel(l1, l2)
        p1 = polyShape.midPointSegment(l1)
        dist = polyShape.calculateDistance(l2, p1)
    else
        dist = 10000
    end
    return dist
end


function halfspaceSignOfPointToLine(l::LineShape, p::PointShape)::Int64
    V = l.Vertices[1]

    x0 = V[1, 1]
    y0 = V[1, 2]
    x = p.Vertices[1, 1]
    y = p.Vertices[1, 2]

    if sqrt((V[2, 1] - V[1, 1])^2 + (V[2, 2] - V[1, 2])^2) < 10^-10
        s = 0
    elseif abs(V[2, 1] - V[1, 1]) > 10^-12
        m = (V[2, 2] - V[1, 2]) / (V[2, 1] - V[1, 1])
        if y - m * x < y0 - m * x0
            s = 1
        else
            s = -1
        end
    else
        if -x < -x0
            s = 1
        else
            s = -1
        end
    end
    return s
end


function intersectLines(l1::LineShape, l2::LineShape)::PointShape

    function intersectEdges(edge1, edge2)

        x1_ini  = edge1[1];
        y1_ini  = edge1[2];
        x1_fin  = edge1[3];
        y1_fin  = edge1[4];
        dx1 = x1_fin - x1_ini;
        dy1 = y1_fin - y1_ini;
        m1 = dy1 / dx1;

        x2_ini  = edge2[1];
        y2_ini  = edge2[2];
        x2_fin  = edge2[3];
        y2_fin  = edge2[4];
        dx2 = x2_fin - x2_ini;
        dy2 = y2_fin - y2_ini;
        m2 = dy2 / dx2;

        min_e1_x = min(x1_ini,x1_fin)
        min_e2_x = min(x2_ini,x2_fin)
        max_e1_x = max(x1_ini,x1_fin)
        max_e2_x = max(x2_ini,x2_fin)

        min_e1_y = min(y1_ini,y1_fin)
        min_e2_y = min(y2_ini,y2_fin)
        max_e1_y = max(y1_ini,y1_fin)
        max_e2_y = max(y2_ini,y2_fin)

        # tolerance for precision
        tol = 1e-3; #1e-14; 

        # initialize result array
        x0  = 0;
        y0  = 0;

        # indices of parallel edges
        par = abs(m1 - m2) < tol;

        # Parallel edges have no intersection -> return [NaN NaN]
        if par
            x0 = NaN;
            y0 = NaN;
        end

        # Process non parallel cases

        # compute intersection points of supporting lines
        delta = dx2 * dy1 - dx1 * dy2;
        x0 = ((y2_ini - y1_ini) * dx1 * dx2 + x1_ini * dy1 * dx2 - x2_ini * dy2 * dx1) / delta;
        y0 = ((x2_ini - x1_ini) * dy1 * dy2 + y1_ini * dx1 * dy2 - y2_ini * dx2 * dy1) / -delta;

        if  x0 < min_e1_x-tol || x0 < min_e2_x-tol || x0 > max_e1_x+tol || x0 > max_e2_x+tol || 
            y0 < min_e1_y-tol || y0 < min_e2_y-tol || y0 > max_e1_y+tol || y0 > max_e2_y+tol
            point = [NaN NaN];
        else
            point = [x0 y0];    
        end

    end


    V_line1 = l1.Vertices[1]
    V_line2 = l2.Vertices[1]
    edge1 = [V_line1[1, :]' V_line1[2, :]']
    edge2 = [V_line2[1, :]' V_line2[2, :]']
    vec_point = intersectEdges(edge1, edge2)
    p = PointShape(vec_point, 1)
    return p
end


function transformLine(l::LineShape, operation::Symbol, params...)::LineShape
    if operation == :extend
        d = params[1]
        V = l.Vertices[1]
        V_ = copy(V)
        x1 = V[1, 1]
        y1 = V[1, 2]
        x2 = V[2, 1]
        y2 = V[2, 2]

        if abs(x2 - x1) > 10^-12
            if x2 < x1
                d = -d
            end

            m = (y2 - y1) / (x2 - x1)
            x1_ = x1 - d / sqrt(m^2 + 1)
            y1_ = y1 - m * (x1 - x1_)
            x2_ = x2 + d / sqrt(m^2 + 1)
            y2_ = y2 + m * (x2_ - x2)
            V_ = [x1_ y1_; x2_ y2_]
        else
            V_ = [x1 y1-d; x2 y2+d]
        end
        return LineShape([V_], 1)
        
    elseif operation == :parallel
        d = params[1]
        V = l.Vertices[1]
        p1, p2 = V[1, :], V[2, :]
        
        dir_vec = p2 - p1
        perp_vec = [-dir_vec[2], dir_vec[1]]
        perp_length = sqrt(perp_vec[1]^2 + perp_vec[2]^2)
        if perp_length > 0
            perp_unit = perp_vec / perp_length
        else
            throw(ArgumentError("Line has zero length"))
        end
        
        offset = d * perp_unit
        new_p1 = p1 + offset
        new_p2 = p2 + offset
        
        return LineShape([[new_p1[1] new_p1[2]; new_p2[1] new_p2[2]]], 1)
        
    elseif operation == :reverse
        numLines = l.NumLines
        V = l.Vertices
        V_ = deepcopy(V)
        for k = 1:numLines
            V_k = V[k]
            largo_k = size(V_k, 1)
            for i = 1:largo_k
                V_[k][i, :] = [V_k[end-(i-1), 1] V_k[end-(i-1), 2]]
            end
        end
        return LineShape(V_, numLines)
    end
end


function findPolyIntersection(ps1::PolyShape, ps2::PolyShape)
    V1 = ps1.Vertices[1]
    V2 = ps2.Vertices[1]
    
    # Close polygons by adding first point at end
    V1_closed = [V1; V1[1, :]']
    V2_closed = [V2; V2[1, :]']
    N1 = size(V1_closed, 1)
    N2 = size(V2_closed, 1)
    
    # Initialize result arrays
    edge_indices1 = Int64[]
    edge_indices2 = Int64[]
    intersection_points = zeros(Float64, 0, 2)
    
    # Loop over all edge pairs
    for n1 = 1:N1-1
        for n2 = 1:N2-1
            # Define edges as [x1_start, y1_start, x1_end, y1_end]
            e1 = [V1_closed[n1, 1], V1_closed[n1, 2], V1_closed[n1+1, 1], V1_closed[n1+1, 2]]
            e2 = [V2_closed[n2, 1], V2_closed[n2, 2], V2_closed[n2+1, 1], V2_closed[n2+1, 2]]
            
            # Calculate intersection using line-line intersection
            p_int = intersectTwoEdges(e1, e2)
            
            # Check if intersection is valid (not NaN)
            if !isnan(p_int[1]) && !isnan(p_int[2])
                push!(edge_indices1, n1)
                push!(edge_indices2, n2)
                intersection_points = [intersection_points; p_int']
            end
        end
    end
    
    # Create PointShape from intersection points
    if size(intersection_points, 1) > 0
        p = PointShape(intersection_points, size(intersection_points, 1))
    else
        p = PointShape(zeros(Float64, 0, 2), 0)
    end
    
    return edge_indices1, edge_indices2, p
end


function intersectTwoEdges(edge1::Vector{Float64}, edge2::Vector{Float64})::Vector{Float64}
    x1_ini, y1_ini, x1_fin, y1_fin = edge1
    x2_ini, y2_ini, x2_fin, y2_fin = edge2
    
    dx1 = x1_fin - x1_ini
    dy1 = y1_fin - y1_ini
    dx2 = x2_fin - x2_ini
    dy2 = y2_fin - y2_ini
    
    # Check for parallel lines
    denom = dx1 * dy2 - dx2 * dy1
    tol = 1e-12
    
    if abs(denom) < tol
        return [NaN, NaN]  # Parallel lines
    end
    
    # Calculate intersection point of infinite lines
    dx = x2_ini - x1_ini
    dy = y2_ini - y1_ini
    
    t1 = (dx2 * dy - dy2 * dx) / denom
    t2 = (dx1 * dy - dy1 * dx) / denom
    
    # Check if intersection is within both line segments
    if t1 >= -tol && t1 <= 1 + tol && t2 >= -tol && t2 <= 1 + tol
        x_int = x1_ini + t1 * dx1
        y_int = y1_ini + t1 * dy1
        return [x_int, y_int]
    else
        return [NaN, NaN]  # Intersection outside segments
    end
end


function createLine(point1::PointShape, point2::PointShape)::LineShape
    v_1 = point1.Vertices[:]'
    v_2 = point2.Vertices[:]'
    V = [v_1; v_2]
    l_out = LineShape([V], 1)
    return l_out
end


function polyEliminaColineales(ps::PolyShape, tol::Float64=0.001, topoFlag::Bool=false)::PolyShape
    function polyEliminaColineales_single(ps::PolyShape, tol::Float64=0.001, topoFlag::Bool=false)::PolyShape
        ps_in = polyShape.polyCopy(ps)
        area_in = polyShape.polyArea(ps_in)
        V_in = copy(ps_in.Vertices[1])
        numVertices_in = size(V_in, 1)

        if numVertices_in >= 4
            if topoFlag == false
                vec_flag = fill(1, numVertices_in)
                for i = 1:numVertices_in
                    vec_flag_i = copy(vec_flag)
                    vec_flag_i[i] = 0
                    ps_i = PolyShape([V_in[vec_flag_i.==1, :]], 1)
                    area_i = polyShape.polyArea(ps_i)
                    dif_area = abs(area_in - area_i) / area_in
                    if dif_area < tol
                        vec_flag[i] = 0
                    end
                end

                V_out = copy(ps_in.Vertices[1])[vec_flag.==1, :]
                ps_out = PolyShape([V_out], 1)
            else
                vec_flag = fill(1, numVertices_in)
                V_out = copy(V_in)
                for i = 1:numVertices_in
                    vec_flag_i = copy(vec_flag)
                    vec_flag_i[i] = 0
                    ps_i = PolyShape([V_in[vec_flag_i.==1, :]], 1)
                    area_i = polyShape.polyArea(ps_i)
                    dif_area = abs(area_in - area_i) / area_in
                    if dif_area < tol
                        if i == 1
                            ia = numVertices_in
                            ip = 2
                        elseif i == numVertices_in
                            ia = numVertices_in - 1
                            ip = 1
                        else
                            ia = i - 1
                            ip = i + 1
                        end
                        V_ia = copy(V_out)
                        V_ia[i, :] = 0.999 * V_out[ia, :] + 0.001 * V_out[ip, :]
                        ps_ia = PolyShape([V_ia], 1)
                        area_ia = polyShape.polyArea(ps_ia)
                        dif_area_ia = abs(area_in - area_ia) / area_in
                        V_ip = copy(V_out)
                        V_ip[i, :] = 0.99 * V_out[ip, :] + 0.01 * V_out[ia, :]
                        ps_ip = PolyShape([V_ip], 1)
                        area_ip = polyShape.polyArea(ps_ip)
                        dif_area_ip = abs(area_in - area_ip) / area_in
                        if dif_area_ia <= dif_area_ip
                            V_out = copy(V_ia)
                        else
                            V_out = copy(V_ip)
                        end
                    end
                    ps_out = PolyShape([V_out], 1)

                end
            end

        else
            ps_out = polyShape.polyCopy(ps)
        end

        return ps_out

    end

    num_regions = ps.NumRegions
    V = Vector{Matrix{Float64}}()
    for i = 1:num_regions
        ps_i = polyShape.subShape(ps, i)
        ps_i = polyEliminaColineales_single(ps_i, tol, topoFlag)
        push!(V, ps_i.Vertices[1])
    end
    return PolyShape(V, num_regions)

end


function polyObtieneCruces(ps::PolyShape)

    V = copy(ps.Vertices[1])
    N = size(V, 1)

    mat_x = [0 0]
    V_x = [0 0]
    for i = 1:N
        for j = 1:N
            if (j >= i + 2 && j - i <= N - 2)
                if i <= N - 1
                    ki_0 = i
                    ki_1 = i + 1
                else
                    ki_0 = N
                    ki_1 = 1
                end
                if j <= N - 1
                    kj_0 = j
                    kj_1 = j + 1
                else
                    kj_0 = N
                    kj_1 = 1
                end

                li = LineShape([V[[ki_0, ki_1], :]], 1)
                lj = LineShape([V[[kj_0, kj_1], :]], 1)
                x_ij = polyGdal.shapeIntersect(li, lj)
                if typeof(x_ij) == PointShape
                    mat_x = vcat(mat_x, [ki_0 kj_0])
                    V_x = vcat(V_x, x_ij.Vertices)
                end
            end
        end
    end

    mat_x = mat_x[2:end, :]
    V_x = V_x[2:end, :]

    return mat_x, V_x
end


function ajustaCoordenadas(ps::PolyShape)::Tuple{PolyShape,Float64,Float64}
    dx = 10000000
    dy = 10000000
    numRegions = ps.NumRegions
    for i = 1:numRegions
        V_i = ps.Vertices[i]
        dx_i = minimum(V_i[:, 1])
        dy_i = minimum(V_i[:, 2])
        if dx_i < dx
            dx = dx_i
        end
        if dy_i < dy
            dy = dy_i
        end
    end
    for i = 1:numRegions
        ps.Vertices[i][:, 1] = ps.Vertices[i][:, 1] .- dx
        ps.Vertices[i][:, 2] = ps.Vertices[i][:, 2] .- dy
    end
    return ps, dx, dy
end
function ajustaCoordenadas(ps::PolyShape, dx::Real, dy::Real)
    numRegions = ps.NumRegions
    for i = 1:numRegions
        ps.Vertices[i][:, 1] = ps.Vertices[i][:, 1] .- dx
        ps.Vertices[i][:, 2] = ps.Vertices[i][:, 2] .- dy
    end
    return ps
end
function ajustaCoordenadas(ls::LineShape, dx::Real, dy::Real)
    numLines = ls.NumLines
    for i = 1:numLines
        ls.Vertices[i][:, 1] = ls.Vertices[i][:, 1] .- dx
        ls.Vertices[i][:, 2] = ls.Vertices[i][:, 2] .- dy
    end
    return ls
end


function angleMaxDistRect(pos_x, pos_y, anchoLado, angleSpace, ps, template=0)

    if template == 0
        # Inicialización
        max_dist = 0.0
        angle_max_dist = 0.0

        # Busca angulo para maximizar distancia
        box_out = PolyShape([], 0)
        for angle in angleSpace
            dist, box_out = polyShape.extendRectToIntersection(pos_x, pos_y, anchoLado, angle, ps, "tall")
            if dist > max_dist
                max_dist = dist - 1
                angle_max_dist = angle
            end
        end

    elseif template == 1
        # Inicialización
        max_dist_1 = 0.0
        angle_max_dist = 0.0

        for angle in angleSpace
            dist_1, box_1 = polyShape.extendRectToIntersection(pos_x, pos_y, anchoLado, angle, ps, "fat")
            dist_2, box_2 = polyShape.extendRectToIntersection(pos_x, pos_y, anchoLado, angle, ps, "tall")
            footPrint = polyShape.polyUnion(box_1, box_2)

            if dist > max_dist
                max_dist = dist - 1
                angle_max_dist = angle
            end
        end

    end

    return max_dist, angle_max_dist
end


function extendRectToIntersection(pos_x, pos_y, anchoLado, angle, ps, rectType="tall")

    # Inicialización
    dist = 0
    largoIni = 130.0
    box_out = PolyShape([], 0)

    # Prueba si rectangulo anchLado*1 en pos_x, pos_y con angle se encuentra dentro de ps
    if rectType == "tall"
        box = polyShape.polyBox(pos_x, pos_y, anchoLado, 1.0, angle)
        edge = polyShape.LineShape([box.Vertices[1][[3, 4], :]], 1)
    elseif rectType == "fat"
        box = polyShape.polyBox(pos_x, pos_y, 1.0, anchoLado, angle)
        edge = polyShape.LineShape([box.Vertices[1][[2, 3], :]], 1)
    end
    flag = polyShape.isPolyInPoly(box, ps)

    # Extiende lado de rectangulo hasta que intersecta con ps
    if flag
        if rectType == "tall"
            box_ext = polyShape.polyBox(pos_x, pos_y, anchoLado, largoIni, angle)
        elseif rectType == "fat"
            box_ext = polyShape.polyBox(pos_x, pos_y, largoIni, anchoLado, angle)
        end
        edges1, edges2, p_inter = polyShape.findPolyIntersection(box_ext, ps)
        point_1 = polyShape.subShape(p_inter, 1)
        dist_1 = polyShape.calculateDistance(edge, point_1)
        point_2 = polyShape.subShape(p_inter, 2)
        dist_2 = polyShape.calculateDistance(edge, point_2)
        buf = 1
        if dist_1 < dist_2
            dist = dist_1 + 1 - buf
        else
            dist = dist_2 + 1 - buf
        end

        # Genera rectangulo de máxima distancia
        if rectType == "tall"
            box_out = polyShape.polyBox(pos_x, pos_y, anchoLado, Float64(dist), angle)
        elseif rectType == "fat"
            box_out = polyShape.polyBox(pos_x, pos_y, Float64(dist), anchoLado, angle)
        end

    end

    return dist, box_out
end


function polyBoxFromEdge(ps::PolyShape, edge_id::Int, extension_length::Real)::PolyShape
    V = ps.Vertices[1]
    num_vertices = size(V, 1)
    
    # Get the selected edge vertices
    p1 = V[edge_id, :]
    p2_id = edge_id == num_vertices ? 1 : edge_id + 1
    p2 = V[p2_id, :]
    
    # Calculate edge vector and length
    edge_vector = p2 - p1
    edge_length = sqrt(sum(edge_vector .^ 2))
    
    # Calculate edge angle
    edge_angle = atan(edge_vector[2], edge_vector[1])
    
    # Calculate outward normal (perpendicular vector pointing outside the polygon)
    perp_vector = [-edge_vector[2], edge_vector[1]]
    
    # Determine which direction is "outward" by checking polygon centroid
    centroid = sum(V, dims=1) / num_vertices
    edge_midpoint = (p1 + p2) / 2
    to_centroid = centroid' - edge_midpoint
    
    # If perpendicular vector points toward centroid, flip it to point outward
    if sum(perp_vector .* to_centroid) > 0
        perp_vector = -perp_vector
    end
    
    # Normalize the perpendicular vector and get outward direction
    perp_unit = perp_vector / sqrt(sum(perp_vector .^ 2))
    outward_offset = extension_length * perp_unit
    
    # Position the box so the selected edge aligns with one side
    # Start from p1 and offset outward
    box_origin = p1 + outward_offset
    
    # Use polyBox with the edge length as width, extension_length as height, and edge angle
    box_out = polyBox(box_origin[1], box_origin[2], edge_length, extension_length, edge_angle)
    
    return box_out
end


function minBoundingBox(ps::PolyShape)::PolyShape
    V = ps.Vertices[1]
    num_vertices = size(V, 1)
    
    # Get convex hull first to reduce computation
    hull_vertices = convHull(V)
    hull_ps = PolyShape([hull_vertices], 1)
    
    min_area = Inf
    best_box = PolyShape([], 0)
    
    # Test each edge of the convex hull as a potential orientation
    hull_V = hull_vertices
    num_hull_vertices = size(hull_V, 1)
    
    for i = 1:num_hull_vertices
        # Get edge vector
        p1 = hull_V[i, :]
        p2_id = i == num_hull_vertices ? 1 : i + 1
        p2 = hull_V[p2_id, :]
        edge_vector = p2 - p1
        
        # Calculate rotation angle for this edge to be horizontal
        edge_angle = atan(edge_vector[2], edge_vector[1])
        
        # Rotate the polygon so this edge becomes horizontal
        centroid = sum(hull_V, dims=1) / num_hull_vertices
        rotated_ps = polyRotate(hull_ps, -edge_angle, centroid[:])
        
        # Get axis-aligned bounding box of rotated polygon
        rotated_V = rotated_ps.Vertices[1]
        min_x = minimum(rotated_V[:, 1])
        max_x = maximum(rotated_V[:, 1])
        min_y = minimum(rotated_V[:, 2])
        max_y = maximum(rotated_V[:, 2])
        
        # Calculate dimensions
        width = max_x - min_x
        height = max_y - min_y
        area = width * height
        
        # Check if this is the minimum area so far
        if area < min_area
            min_area = area
            
            # Create the bounding box in the rotated space
            box_rotated = polyBox(min_x, min_y, width, height)
            
            # Rotate the box back to original orientation
            best_box = polyRotate(box_rotated, edge_angle, centroid[:])
        end
    end
    
    return best_box
end


function polyshape2wkt(ps::PolyShape)::String
    if ps.NumRegions == 0
        return "POLYGON EMPTY"
    elseif ps.NumRegions == 1
        vertices = ps.Vertices[1]
        if size(vertices, 1) < 3
            return "POLYGON EMPTY"
        end
        
        wkt_coords = join([string(vertices[i, 1]) * " " * string(vertices[i, 2]) for i in axes(vertices, 1)], ", ")
        
        if vertices[1, :] != vertices[end, :]
            wkt_coords *= ", " * string(vertices[1, 1]) * " " * string(vertices[1, 2])
        end
        
        return "POLYGON((" * wkt_coords * "))"
    else
        polygon_parts = String[]
        
        for i in eachindex(ps.Vertices)
            vertices = ps.Vertices[i]
            if size(vertices, 1) >= 3
                wkt_coords = join([string(vertices[j, 1]) * " " * string(vertices[j, 2]) for j in axes(vertices, 1)], ", ")
                
                if vertices[1, :] != vertices[end, :]
                    wkt_coords *= ", " * string(vertices[1, 1]) * " " * string(vertices[1, 2])
                end
                
                push!(polygon_parts, "(" * wkt_coords * ")")
            end
        end
        
        if isempty(polygon_parts)
            return "MULTIPOLYGON EMPTY"
        elseif length(polygon_parts) == 1
            return "POLYGON(" * polygon_parts[1] * ")"
        else
            return "MULTIPOLYGON(" * join(["(" * part * ")" for part in polygon_parts], ", ") * ")"
        end
    end
end


function replaceShapeVertex(pt::PointShape, id::Int, shape::PosDimGeom)::PosDimGeom
    V = copy(shape.Vertices[1])
    v_pt = copy(pt.Vertices[1, :])
    V[id, :] = v_pt'
    if typeof(shape) == PolyShape
        shape_out = PolyShape([V], 1)
    elseif typeof(shape) == LineShape
        shape_out = LineShape([V], 1)
    end

    return shape_out
end


function lineVec2polyShape(lineVec::Array{LineShape,1}, reg_vec=[])::PolyShape

    if isempty(reg_vec)
        num_reg = 1
    else
        num_reg = maximum(reg_vec)
    end

    ps_out = []
    for k = 1:num_reg
        if reg_vec == []
            lineVec_k = deepcopy(lineVec)
        else
            lineVec_k = deepcopy(lineVec[reg_vec.==k])
        end
        N_k = length(lineVec_k)
        V_k = fill(0.0, N_k, 2)
        for i = 1:N_k
            ix_1 = i
            if i == N_k
                ix_2 = 1
            else
                ix_2 = i + 1
            end
            l_1 = polyShape.transformLine(lineVec_k[ix_1], :extend, 1.0)
            l_2 = polyShape.transformLine(lineVec_k[ix_2], :extend, 1.0)
            point_x_12 = polyGdal.shapeIntersect(l_1, l_2)
            if size(point_x_12.Vertices[1], 1) >= 1
                V_k[ix_2, :] = point_x_12.Vertices[1, :]'
            else
                V_k[ix_2, :] = V_k[ix_1, :]
            end
        end
        if k == 1
            ps_out = PolyShape([V_k], 1)
        else
            ps_out = polyShape.polyUnion(ps_out, PolyShape([V_k], 1))
        end
    end

    return ps_out
end


function shape2vector(ls::LineShape)::Vector{LineShape}
    num_lines = ls.NumLines
    vec_ls = Vector{LineShape}()
    for k = 1:num_lines
        V_k = ls.Vertices[k]
        num_points_k = size(V_k, 1)
        for i = 2:num_points_k
            ls_i = LineShape([V_k[i-1:i, :]], 1)
            push!(vec_ls, ls_i)
        end
    end
    return vec_ls
end
function shape2vector(ps::PolyShape)
    num_regions = ps.NumRegions
    line_vec = Array{LineShape,1}()
    reg_vec = Array{Int,1}()
    for k = 1:num_regions
        V_k = copy(ps.Vertices[k])
        N_k = size(V_k, 1)

        for i in 1:N_k
            if i < N_k
                l_i = LineShape([[V_k[i, :]'; V_k[i+1, :]']], 1)
            else
                l_i = LineShape([[V_k[i, :]'; V_k[1, :]']], 1)
            end
            line_vec = push!(line_vec, l_i)
            reg_vec = push!(reg_vec, k)
        end
    end

    return line_vec, reg_vec
end


function convertWKTCoordinates(wkt_array::Vector{String}, epsg_source::Int64, epsg_target::Int64)
    source = ArchGDAL.importEPSG(epsg_source; order=:trad)
    target = ArchGDAL.importEPSG(epsg_target; order=:trad)
    transformed_wkts = String[]
    for i = 1:length(wkt_array)
        wkt = wkt_array[i]
        ArchGDAL.createcoordtrans(source, target) do transform
            point = ArchGDAL.fromWKT(wkt)
            ArchGDAL.transform!(point, transform)
            append!(transformed_wkts, [ArchGDAL.toWKT(point)])
        end
    end
    return transformed_wkts
end
function convertWKTCoordinates(df::DataFrame, geom_col_name::String, epsg_source::Int64, epsg_target::Int64)
    wkt_array = convert.(String, df[:, geom_col_name])
    transformed_wkts = polyShape.convertWKTCoordinates(wkt_array, epsg_source, epsg_target)
    result_df = deepcopy(df)
    result_df[:, geom_col_name] = transformed_wkts
    return result_df
end


function transformPolyshapeEPSG(ps::PolyShape, dx::Real, dy::Real, EPSG_in::Int64, EPSG_out::Int64)
    # transforma un PolyShape de un sistema de proyección a otro

    ps_ = polyShape.polyCopy(ps)
    source = ArchGDAL.importEPSG(EPSG_in)
    if EPSG_out == 4326
        target = ArchGDAL.importEPSG(EPSG_out; order=:trad)
    else
        target = ArchGDAL.importEPSG(EPSG_out)
    end

    for i = 1:ps_.NumRegions
        x = ps_.Vertices[i][:, 1] .+ dx
        y = ps_.Vertices[i][:, 2] .+ dy
        points = ArchGDAL.createpoint.(x, y)
        ArchGDAL.createcoordtrans(source, target) do transform
            ArchGDAL.transform!.(points, Ref(transform))
        end
        for j in eachindex(points)
            transformed_x = ArchGDAL.getx(points[j], 0)
            transformed_y = ArchGDAL.gety(points[j], 0)
            ps_.Vertices[i][j, :] = [transformed_x, transformed_y]
        end
    end
    if ps_.NumRegions == 1
        V_k = ps_.Vertices[1]
        largo_k = size(V_k, 1)
        line_k = [(Float64(V_k[i, 1]), Float64(V_k[i, 2])) for i = 1:largo_k]
        push!(line_k, (Float64(V_k[1, 1]), Float64(V_k[1, 2])))
        poly = ArchGDAL.createpolygon(line_k)
    else
        poly = polyGdal.shape2geom(ps_)
    end
    return poly
end


# Calculate the bisector direction for a vertex
function bisector_direction(edge1::LineShape, edge2::LineShape)::LineShape
    V1 = edge1.Vertices[1]
    V2 = edge2.Vertices[1]
    p1_start = V1[1, :]
    p1_end = V1[2, :]
    p2_start = V2[1, :]
    p2_end = V2[2, :]

    edgeA_direction = ([p1_end[1] - p1_start[1], p1_end[2] - p1_start[2]])
    edgeA_direction = edgeA_direction ./ sqrt(edgeA_direction[1]^2 + edgeA_direction[2]^2)
    edgeB_direction = ([p2_end[1] - p2_start[1], p2_end[2] - p2_start[2]])
    edgeB_direction = edgeB_direction ./ sqrt(edgeB_direction[1]^2 + edgeB_direction[2]^2)

    dir = edgeA_direction + edgeB_direction
    dir = dir ./ sqrt(dir[1]^2 + dir[2]^2)

    bisector_dir = LineShape([[0 0; dir[1] dir[2]]], 1)

    return bisector_dir
end


# Calculate the angle between two edges 
function angleBetweenLines(edge1, edge2)
    V1 = edge1.Vertices[1]
    V2 = edge2.Vertices[1]
    p1_start = V1[1, :]
    p1_end = V1[2, :]
    p2_start = V2[1, :]
    p2_end = V2[2, :]

    edgeA_direction = ([p1_end[1] - p1_start[1], p1_end[2] - p1_start[2]])
    edgeB_direction = ([p2_end[1] - p2_start[1], p2_end[2] - p2_start[2]])

    edgeAB = sum(edgeA_direction .* edgeB_direction)
    absA = sqrt(edgeA_direction[1]^2 + edgeA_direction[2]^2)
    absB = sqrt(edgeB_direction[1]^2 + edgeB_direction[2]^2)

    return acos(edgeAB / absA / absB)
end


function midPointSegment(edge::LineShape)::PointShape
    num_lines = edge.NumLines
    V_out = zeros(num_lines, 2)
    for i = 1:num_lines
        V_i = edge.Vertices[i]
        V_out[i, :] = 0.5 * V_i[1, :] + 0.5 * V_i[2, :]
    end
    p_out = PointShape(V_out, num_lines)
    return p_out
end


function alphaPointSegment(edge::LineShape, α)::PointShape
    num_lines = edge.NumLines
    V_out = zeros(num_lines, 2)
    for i = 1:num_lines
        V_i = edge.Vertices[i]
        V_out[i, :] = (1 - α) * V_i[1, :] + α * V_i[2, :]
    end
    p_out = PointShape(V_out, num_lines)
    return p_out
end


function points2Line(p1::PointShape, p2::PointShape)::LineShape
    V1 = p1.Vertices[:]'
    V2 = p2.Vertices[:]'
    l = LineShape([[V1; V2]], 1)
    return l
end


function points2Poly(p::PointShape...)
    num_points = length(p)
    V = [0 0]
    for i = 1:num_points
        V_i = p[i].Vertices[:]
        V = [V; V_i[:]']
    end
    V = V[2:end, :]
    ps = PolyShape([V], 1)
    return ps
end


function lineLength(l::LineShape)
    numLines = l.NumLines
    len = []
    for i = 1:numLines
        p1_i = polyShape.shapeVertex(l, i, 1)
        p2_i = polyShape.shapeVertex(l, i, 2)
        d_12_i = polyShape.calculateDistance(p1_i, p2_i)

        if numLines > 1
            push!(len, d_12_i)
        else
            len = d_12_i
        end
    end
    return len
end


function point2lineProjection(p::PointShape, l::LineShape)
    start, finish = l.Vertices[1][1, :], l.Vertices[1][2, :]
    v = finish .- start
    t = ((p.Vertices[1] - start[1]) * v[1] + (p.Vertices[2] - start[2]) * v[2]) / (v[1]^2 + v[2]^2)
    t = max(0, min(1, t))
    return PointShape((start + t * v)', 1)
end


function perpendicularLine(p::PointShape, l::LineShape, d::Real)
    start, finish = l.Vertices[1][1, :], l.Vertices[1][2, :]
    v = finish .- start
    perp_v = [-v[2], v[1]]
    perp_v_length = sqrt(perp_v[1]^2 + perp_v[2]^2)
    perp_v_norm = perp_v / perp_v_length
    end_point = p.Vertices - d * perp_v_norm'
    return LineShape([vcat(p.Vertices, end_point)], 1)
end


function isLineLineParallel(l1::LineShape, l2::LineShape)::Bool
    err = 0.0015

    angle1 = polyShape.lineAngle(l1)
    angle2 = polyShape.lineAngle(l2)

    flag = false
    if abs(angle1 - angle2) <= err || abs(angle1 - pi - angle2) <= err
        flag = true
    end

    return flag
end


function projectBuildingShadow(ps, alt, orientacion)
    num_regions = ps.NumRegions
    V = []
    for k = 1:num_regions
        V_k = ps.Vertices[k]
        num_verts_k = size(V_k, 1)
        if orientacion == "p"
            V_k_ = [V_k[:, 1] - ones(num_verts_k, 1) * alt / 0.49 V_k[:, 2]]
        elseif orientacion == "o"
            V_k_ = [V_k[:, 1] + ones(num_verts_k, 1) * alt / 0.49 V_k[:, 2]]
        else
            V_k_ = [V_k[:, 1] V_k[:, 2] - ones(num_verts_k, 1) * alt / 1.54]
        end
        push!(V, V_k_)
    end

    return PolyShape(V, length(V))

end


function polyshapeToUTM(ps::PolyShape, EPSG_in = 4326, utm_out = "+proj=utm +zone=19 +south +datum=WGS84")::PolyShape
    trans = Proj.Transformation("EPSG:$(EPSG_in)", utm_out)
    transformed_vertices = [
        hcat([collect(trans(lat, lon)) for (lon, lat) in eachrow(polygon)]...)'
        for polygon in ps.Vertices
    ]
    return PolyShape(transformed_vertices, ps.NumRegions)
end


function poly2Constraints(ps_::PolyShape)
    # Convert a PolyShape to halfspace constraints. Only works for convex or near convex polygons.
    v1 = ps_.Vertices[1][1,:]
    ps = setPolyOrientation(polyGdal.shapeHull(ps_), 1)
    ps = polyShape.rotate_to_first_ccw(ps, v1)

    V = ps.Vertices[1]

    n = size(V, 1)
    A = zeros(n, 2)
    b = zeros(n)

    for i in 1:n
        p1 = V[i, :]
        p2 = V[mod1(i + 1, n), :]

        # Edge vector from p1 to p2
        edge = p2 - p1

        # Outward normal (rotate edge 90° clockwise)
        # For counter-clockwise vertices, this gives outward normal
        outward_normal = [edge[2], -edge[1]]

        # Normalize
        outward_normal = outward_normal / norm(outward_normal)

        # For constraint a^T x <= b, we want the normal to point outward
        # so that points inside satisfy the constraint
        A[i, :] = outward_normal
        b[i] = dot(outward_normal, p1)
    end

    return A, b
end


function constraints2poly(A, b; tol=1e-10)
    
    m, n = size(A)  # m constraints, n variables
    if n > m
        error("Underdetermined system: more variables than constraints")
    end
        
    V = [0 0]
    # Generate all combinations of n constraints from m total constraints
    for constraint_indices in combinations(1:m, n)
        # Extract the selected constraint rows
        A_selected = A[constraint_indices, :]
        b_selected = b[constraint_indices]
        
        # Solve the system A_selected * x = b_selected
        try
            if abs(det(A_selected)) > tol  # Check if matrix is invertible
                x = A_selected \ b_selected
                
                # Only keep points that satisfy ALL original constraints
                if all(A * x .<= b .+ tol)
                    V = vcat(V, [x[1] x[2]])
                end
            end
        catch
            # Skip if system is singular or other numerical issues
            continue
        end
    end

    V = copy(V[2:end,:]) 
    ps_pt = PolyShape([V], 1)
    ps_out = setPolyOrientation(polyGdal.shapeHull(ps_pt), 1)

    V_out = ps_out.Vertices[1]

    vec_V = []
    n = size(V, 1)
    for i in 1:n
        p1 = V_out[i, :]'
        p2 = V_out[mod1(i + 1, n), :]'

        push!(vec_V, [p1[1] p1[2]; p2[1] p2[2]])
    end
    ls_out = LineShape(vec_V, length(vec_V))
    
    return ps_out, ls_out
end


function rotate_to_first_ccw(ps::PolyShape, v1::Vector{Float64})
    # Ensure vertices are CCW oriented
    vertices = ps.Vertices[1]
    vertices = polyShape.setPolyOrientation(PolyShape([vertices], 1), 1).Vertices[1]
    idx = findfirst(row -> all(row .≈ v1), eachrow(vertices))
    if isnothing(idx)
        error("The vertex v1 is not found in the given list.")
    end
    rotated_vertices = [vertices[idx:end, :]; vertices[1:idx-1, :]]
    ps_out = PolyShape([rotated_vertices],1)
    return ps_out
end

function polySimplify(ps_::PolyShape, tolerance::Real=0.1)::PolyShape
    ps = polyShape.polyCopy(ps_)
    
    function douglasPeucker(vertices::Array{Float64,2}, tolerance::Real)::Array{Float64,2}
        n = size(vertices, 1)
        if n <= 2
            return vertices
        end
        
        start_point = PointShape(vertices[1, :]', 1)
        end_point = PointShape(vertices[end, :]', 1)
        line_segment = polyShape.createLine(start_point, end_point)
        
        max_distance = 0.0
        max_index = 0
        
        for i = 2:n-1
            point = PointShape(vertices[i, :]', 1)
            distance = abs(polyShape.calculateDistance(line_segment, point))
            
            if distance > max_distance
                max_distance = distance
                max_index = i
            end
        end
        
        if max_distance > tolerance && max_index > 0
            left_vertices = vertices[1:max_index, :]
            right_vertices = vertices[max_index:end, :]
            
            left_simplified = douglasPeucker(left_vertices, tolerance)
            right_simplified = douglasPeucker(right_vertices, tolerance)
            
            simplified = vcat(left_simplified[1:end-1, :], right_simplified)
        else
            simplified = vertices[[1, end], :]
        end
        
        return simplified
    end
    
    function simplifyRegion(vertices::Array{Float64,2}, tolerance::Real)::Array{Float64,2}
        n = size(vertices, 1)
        if n < 3
            return vertices
        end
        
        closed_vertices = vcat(vertices, vertices[1, :]')
        simplified = douglasPeucker(closed_vertices, tolerance)
        
        if size(simplified, 1) > 1 && all(simplified[1, :] .≈ simplified[end, :])
            simplified = simplified[1:end-1, :]
        end
        
        if size(simplified, 1) < 3
            simplified = polyShape.convHull(vertices)
        end
        
        return simplified
    end
    
    numRegions = ps.NumRegions
    simplified_vertices = Vector{Matrix{Float64}}()
    
    for i = 1:numRegions
        region_vertices = ps.Vertices[i]
        simplified_region = simplifyRegion(region_vertices, tolerance)
        push!(simplified_vertices, simplified_region)
    end
    
    ps_out = PolyShape(simplified_vertices, length(simplified_vertices))
    return ps_out
end

########################################################################
########################################################################
########################################################################



export isPolyConvex, isPolyInPoly,  
    polyArea, polyDifference, polyOrientation, polyUnion, polyIntersect, polyOffset,  
    polyEliminaColineales, subShape, shapeVertex, numVertices,
    polyBox, polyRotate, polyReverse, setPolyOrientation, minPolyDistance, 
    polyCopy, intersectLines, findPolyIntersection, 
    lineAngle, halfspaceSignOfPointToLine,
    polyObtieneCruces, replaceShapeVertex, lineVec2polyShape, polyShrink,
    ajustaCoordenadas, angleMaxDistRect, extendRectToIntersection, polyBoxFromEdge, minBoundingBox,
    createLine, convHull, bisector_direction, angleBetweenLines, midPointSegment,
    alphaPointSegment, points2Line, points2Poly, lineLength, isLineLineParallel,
    projectBuildingShadow, partialPolyOffset, point2lineProjection, 
    perpendicularLine, line2Box, poly2Constraints, constraints2poly, rotate_to_first_ccw,
    calculateDistance, cleanPolygon, shape2vector, transformLine, polySimplify,
    transformPolyshapeEPSG, convertWKTCoordinates, polyshapeToUTMv, polyshape2wkt
end
