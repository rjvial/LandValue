module polyShape

using LandValue, ArchGDAL, LazySets, DataFrames, LinearAlgebra, Proj, Combinatorics, JSON

# polyShape Function Reference
# =========================
#
# Core Geometry Operations
# - polyUnion: Merge multiple polygon regions into a single unified polygon
# - polyDifference: Subtract one polygon from another (boolean difference operation)
# - polyIntersection: Find the overlapping area between two polygons
#
# Polygon Analysis
# - polyOrientation: Determine if polygon vertices are oriented clockwise or counterclockwise
# - polyArea: Calculate the total area of a polygon or areas of individual regions
# - isPolyConvex: Check if a polygon is convex (no interior angles > 180°)
#
# Shape Construction
# - polyBox: Create rectangular polygon from position, dimensions, and rotation angle
# - convHull: Generate convex hull (smallest convex polygon containing all points)
# - line2Box: Convert line segment to rectangular polygon with specified width
# - polyBoxFromEdge: Create rectangular extension from a specific polygon edge
#
# Shape Manipulation
# - polyRotate: Rotate polygon by specified angle around a center point
# - polyTranslate: Translate polygon by specified x and y offsets
# - polyReverse: Reverse the order of polygon vertices (flip orientation)
# - setPolyOrientation: Force polygon to have specific vertex orientation (CW/CCW)
# - polyCopy: Create deep copy of polygon, line, or point shape
# - polySimplify: Reduce polygon complexity using Douglas-Peucker algorithm
#
# Geometric Utilities
# - subShape: Extract specific region(s) from multi-region polygon
# - shapeVertex: Extract specific vertex or all vertices from shape as points
# - numVertices: Count number of vertices in a polygon region
#
# Line Operations
# - lineAngle: Calculate angle(s) of line segments in radians
# - lineLength: Compute length of line segment(s)
# - createLine: Create line segment between two points
# - transformLine: Apply geometric transformations (extend, parallel, reverse) to lines
# - intersectLines: Find intersection point between two line segments
# - isLineLineParallel: Check if two lines are parallel within tolerance
#
# Advanced Geometry
# - partialPolyOffset: Create polygon with selective edge offsetting by specified distances
# - polyEliminaColineales: Remove collinear vertices to simplify polygon shape
#
# Coordinate Systems
# - ajustaCoordenadas: Translate polygon coordinates by subtracting minimum x,y values
# - ajustaCoordenadasInversa: Reverse coordinate adjustment by adding back offset values
# - shape_32719to4326: Convert from UTM Zone 19S to WGS84 geographic coordinates
# - shape_4326to32719: Convert from WGS84 geographic to UTM Zone 19S coordinates
#
# Distance & Position
# - calculateDistance: Compute distance between lines, points, or line-to-point
# - halfspaceSignOfPointToLine: Determine which side of line a point lies on
#
# Complex Analysis
# - midPointSegment: Find midpoint(s) of line segment(s)
#
# Construction & Conversion
# - lineVec2polyShape: Convert vector of connected line segments to polygon
# - shape2vector: Break polygon into vector of individual edge line segments
# - polyshape2wkt: Convert polygon to Well-Known Text string format
#
# Specialized Operations
# - reversePath: Reverse order of vertices in coordinate array
# - intersectTwoEdges: Find intersection between two line segment edges
# - extendRectToIntersection: Extend rectangle until it intersects with polygon
# - poly2Constraints: Convert convex polygon to linear inequality constraints
# - constraints2poly: Convert linear constraints back to polygon representation
# - rotate_to_first_ccw: Rotate polygon vertex order to start with specific vertex


function polyUnion(ps_::PolyShape)::PolyShape
    ps = deepcopy(ps_)
    num_regions = ps.NumRegions
    if num_regions == 0
        return PolyShape(Vector{Matrix{Float64}}(), 0)
    end
    ps_out = polyShape.subShape(ps, 1)
    for i = 2:num_regions
        ps_out = polyShape.polyUnion(ps_out, polyShape.subShape(ps, i))
    end
    return ps_out
end
function polyUnion(vec_ps_::Vector{PolyShape})::PolyShape
    vec_ps = deepcopy(vec_ps_)

    num_ps = length(vec_ps)
    ps_out = polyUnion(vec_ps[1])
    for i = 2:num_ps
        ps_i = polyUnion(vec_ps[i])
        ps_out = polyShape.polyUnion(ps_out, ps_i)
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
    if ps_s_.NumRegions == 0
        return PolyShape(Vector{Matrix{Float64}}(), 0)
    end

    if ps_c_.NumRegions == 0
        return deepcopy(ps_s_)
    end

    ps_c_bounds = [minimum([minimum(region[:, 1]) for region in ps_c_.Vertices]),
                   minimum([minimum(region[:, 2]) for region in ps_c_.Vertices]),
                   maximum([maximum(region[:, 1]) for region in ps_c_.Vertices]),
                   maximum([maximum(region[:, 2]) for region in ps_c_.Vertices])]

    ps_s_bounds = [minimum([minimum(region[:, 1]) for region in ps_s_.Vertices]),
                   minimum([minimum(region[:, 2]) for region in ps_s_.Vertices]),
                   maximum([maximum(region[:, 1]) for region in ps_s_.Vertices]),
                   maximum([maximum(region[:, 2]) for region in ps_s_.Vertices])]

    if ps_s_bounds[1] > ps_c_bounds[3] || ps_s_bounds[3] < ps_c_bounds[1] ||
       ps_s_bounds[2] > ps_c_bounds[4] || ps_s_bounds[4] < ps_c_bounds[2]
        return deepcopy(ps_s_)
    end
    
    path_s = polyClipper.shape2clipper(ps_s_)
    path_c = polyClipper.shape2clipper(ps_c_)
    d_path = polyClipper.clipper_difference(path_s, path_c)
    ps_out = polyClipper.clipper2shape(d_path, PolyShape)
    
    return ps_out
end
function polyDifference(ls::LineShape, ps::PolyShape)::LineShape
    result = polyGdal.shapeDifference(ls, ps)
    if isa(result, LineShape)
        return result
    else
        return LineShape([], 0)
    end
end


function polyIntersection(ps_s_::PolyShape, ps_c_::PolyShape)::PolyShape
    ps_s = deepcopy(ps_s_)
    ps_c = deepcopy(ps_c_)
    
    if ps_s.NumRegions <= 10 && ps_c.NumRegions <= 10
        ps_c = polyShape.polyUnion(ps_c)
        path_s = polyClipper.shape2clipper(ps_s)
        path_c = polyClipper.shape2clipper(ps_c)
        i_path = polyClipper.clipper_intersection(path_s, path_c)
        ps_out = polyClipper.clipper2shape(i_path, PolyShape)
        return ps_out
    end
    
    ps_c_bounds = [minimum([minimum(region[:, 1]) for region in ps_c.Vertices]),
                   minimum([minimum(region[:, 2]) for region in ps_c.Vertices]),
                   maximum([maximum(region[:, 1]) for region in ps_c.Vertices]),
                   maximum([maximum(region[:, 2]) for region in ps_c.Vertices])]
    
    c_region_bounds = []
    for j = 1:ps_c.NumRegions
        c_bounds = [minimum(ps_c.Vertices[j][:, 1]), minimum(ps_c.Vertices[j][:, 2]), 
                   maximum(ps_c.Vertices[j][:, 1]), maximum(ps_c.Vertices[j][:, 2])]
        push!(c_region_bounds, c_bounds)
    end
    
    vec_V = []
    for i = 1:ps_s.NumRegions
        s_region_bounds = [minimum(ps_s.Vertices[i][:, 1]), minimum(ps_s.Vertices[i][:, 2]), 
                          maximum(ps_s.Vertices[i][:, 1]), maximum(ps_s.Vertices[i][:, 2])]
        
        if s_region_bounds[1] > ps_c_bounds[3] || s_region_bounds[3] < ps_c_bounds[1] ||
           s_region_bounds[2] > ps_c_bounds[4] || s_region_bounds[4] < ps_c_bounds[2]
            continue
        end
        
        overlapping_c_regions = Int64[]
        for j = 1:ps_c.NumRegions
            c_bounds = c_region_bounds[j]
            if !(s_region_bounds[1] > c_bounds[3] || s_region_bounds[3] < c_bounds[1] ||
                 s_region_bounds[2] > c_bounds[4] || s_region_bounds[4] < c_bounds[2])
                push!(overlapping_c_regions, j)
            end
        end
        
        if !isempty(overlapping_c_regions)
            ps_s_i = polyShape.subShape(ps_s, i)
            ps_c_subset = polyShape.subShape(ps_c, overlapping_c_regions)
            ps_c_subset = polyShape.polyUnion(ps_c_subset)
            
            path_s_i = polyClipper.shape2clipper(ps_s_i)
            path_c_subset = polyClipper.shape2clipper(ps_c_subset)
            i_path = polyClipper.clipper_intersection(path_s_i, path_c_subset)
            ps_out_i = polyClipper.clipper2shape(i_path, PolyShape)
            
            for k = 1:ps_out_i.NumRegions
                push!(vec_V, ps_out_i.Vertices[k])
            end
        end
    end
    ps_out = PolyShape(vec_V, length(vec_V))    

    return ps_out
end


function polyIntersects(shape1::PosDimGeom, shape2::PosDimGeom)::Bool
    # Validate inputs
    if !isValidShape(shape1) || !isValidShape(shape2)
        return false
    end
    
    try
        intersection = polyGdal.shapeIntersect(shape1, shape2)
        if typeof(intersection) == PolyShape
            return polyArea(intersection) > 0.0
        elseif typeof(intersection) == LineShape
            return intersection.NumLines > 0
        elseif typeof(intersection) == PointShape
            return intersection.NumPoints > 0
        end
        return false
    catch e
        return false
    end
end
function polyIntersects(shape1::PosDimGeom, pt::PointShape)::Bool
    return polyGdal.shapeContains(shape1, pt)
end
function polyIntersects(pt::PointShape, shape2::PosDimGeom)::Bool
    return polyGdal.shapeContains(shape2, pt)
end
function polyIntersects(pt1::PointShape, pt2::PointShape)::Bool
    return calculateDistance(pt1, pt2) < 1e-10
end
function polyIntersects(shape1::PosDimGeom, shape2::PosDimGeom, detailed::Bool)::Tuple{Bool, Matrix{Bool}}
    if !detailed
        return (polyIntersects(shape1, shape2), Matrix{Bool}(undef, 0, 0))
    end
    
    n1 = typeof(shape1) == PolyShape ? shape1.NumRegions : shape1.NumLines
    n2 = typeof(shape2) == PolyShape ? shape2.NumRegions : shape2.NumLines
    
    intersection_matrix = Matrix{Bool}(undef, n1, n2)
    overall_intersects = false
    
    for i = 1:n1
        sub_shape1 = subShape(shape1, i)
        for j = 1:n2
            sub_shape2 = subShape(shape2, j)
            intersects = polyIntersects(sub_shape1, sub_shape2)
            intersection_matrix[i, j] = intersects
            if intersects
                overall_intersects = true
            end
        end
    end
    
    return (overall_intersects, intersection_matrix)
end
function polyIntersects(shape1::PosDimGeom, pt::PointShape, detailed::Bool)::Tuple{Bool, Matrix{Bool}}
    if !detailed
        return (polyIntersects(shape1, pt), Matrix{Bool}(undef, 0, 0))
    end
    
    n1 = typeof(shape1) == PolyShape ? shape1.NumRegions : shape1.NumLines
    n2 = pt.NumPoints
    
    intersection_matrix = Matrix{Bool}(undef, n1, n2)
    overall_intersects = false
    
    for i = 1:n1
        sub_shape1 = subShape(shape1, i)
        for j = 1:n2
            sub_pt = subShape(pt, j)
            intersects = polyIntersects(sub_shape1, sub_pt)
            intersection_matrix[i, j] = intersects
            if intersects
                overall_intersects = true
            end
        end
    end
    
    return (overall_intersects, intersection_matrix)
end
function polyIntersects(pt::PointShape, shape2::PosDimGeom, detailed::Bool)::Tuple{Bool, Matrix{Bool}}
    if !detailed
        return (polyIntersects(pt, shape2), Matrix{Bool}(undef, 0, 0))
    end
    
    intersects, matrix = polyIntersects(shape2, pt, true)
    return (intersects, matrix')
end
function polyIntersects(pt1::PointShape, pt2::PointShape, detailed::Bool)::Tuple{Bool, Matrix{Bool}}
    if !detailed
        return (polyIntersects(pt1, pt2), Matrix{Bool}(undef, 0, 0))
    end
    
    n1 = pt1.NumPoints
    n2 = pt2.NumPoints
    
    intersection_matrix = Matrix{Bool}(undef, n1, n2)
    overall_intersects = false
    
    for i = 1:n1
        sub_pt1 = subShape(pt1, i)
        for j = 1:n2
            sub_pt2 = subShape(pt2, j)
            intersects = polyIntersects(sub_pt1, sub_pt2)
            intersection_matrix[i, j] = intersects
            if intersects
                overall_intersects = true
            end
        end
    end
    
    return (overall_intersects, intersection_matrix)
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
        parallel_id = findall(x -> x == 1, [polyShape.isLineLineParallel(ls_base, vec_ls_comp[j], 0.01) for j in eachindex(vec_ls_comp)])
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

        nonIntersecting_offset_lines_2 = Vector{LineShape}()
        for i in eachindex(vec_ps_lines)
            flag_rev = vec_todos_offset_dist_[i] >= 0. ? false : true
            ps_box_i = polyShape.line2Box(vec_ps_lines[i], 40., flag_rev)
            ls_intersect_i = polyGdal.shapeIntersect(nonIntersecting_offset_lines[i], ps_box_i)
            if typeof(ls_intersect_i) == LineShape
                push!(nonIntersecting_offset_lines_2, ls_intersect_i)
            else
                push!(nonIntersecting_offset_lines_2, vec_ps_lines[i])
            end
        end
 
        nonIntersecting_offset_lines_2 = nonIntersecting_offset_lines_2[findall(polyShape.lineLength.(nonIntersecting_offset_lines_2) .>= 1)]
        V_aux = [0.0 0.0]
        for i in eachindex(nonIntersecting_offset_lines_2)
            current_side_index = i
            next_side_index = mod1(current_side_index + 1, length(nonIntersecting_offset_lines_2))

            lin1 = polyShape.transformLine(nonIntersecting_offset_lines_2[current_side_index], :extend, 60)
            lin2 = polyShape.transformLine(nonIntersecting_offset_lines_2[next_side_index], :extend, 60)
            intersection_point = polyShape.intersectLines(lin1, lin2)
            if isnan(intersection_point.Vertices[1])
                point1 = nonIntersecting_offset_lines_2[current_side_index].Vertices[1][2, :]'
                point2 = nonIntersecting_offset_lines_2[next_side_index].Vertices[1][1, :]'
                V_aux = vcat(V_aux, point1)
                V_aux = vcat(V_aux, point2)
            else
                point = intersection_point.Vertices[1, :]'
                V_aux = vcat(V_aux, point)
            end
        end
        V_aux = V_aux[2:end,:]
        ps_out = polyShape.polySimplify(PolyShape([V_aux], 1), 0.1)

        return ps_out, vec_todos_offset_dist_
    end

    if isempty(vec_partial_offset_dist)
        return ps
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

function polyTranslate(ps::PolyShape, dx::Real, dy::Real)::PolyShape
    if isempty(ps.Vertices) || polyArea(ps) == 0.0
        return ps
    end
    translation = [dx, dy]
    ps_ = deepcopy(ps)
    V = ps_.Vertices[1]
    V_translated = V .+ translation'
    ps_translated = PolyShape([V_translated], 1)
    return ps_translated
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
function ajustaCoordenadas(ls::LineShape)::Tuple{LineShape,Float64,Float64}
    dx = 10000000
    dy = 10000000
    numLines = ls.NumLines
    for i = 1:numLines
        V_i = ls.Vertices[i]
        dx_i = minimum(V_i[:, 1])
        dy_i = minimum(V_i[:, 2])
        if dx_i < dx
            dx = dx_i
        end
        if dy_i < dy
            dy = dy_i
        end
    end
    for i = 1:numLines
        ls.Vertices[i][:, 1] = ls.Vertices[i][:, 1] .- dx
        ls.Vertices[i][:, 2] = ls.Vertices[i][:, 2] .- dy
    end
    return ls, dx, dy
end
function ajustaCoordenadas(ls::LineShape, dx::Real, dy::Real)
    numLines = ls.NumLines
    for i = 1:numLines
        ls.Vertices[i][:, 1] = ls.Vertices[i][:, 1] .- dx
        ls.Vertices[i][:, 2] = ls.Vertices[i][:, 2] .- dy
    end
    return ls
end


# polyBox(pos_x::Real, pos_y::Real, dx::Real, dy::Real=dx, angulo::Real=0.0, cr=[pos_x; pos_y])
function polyBoxFromEdge(ps::PolyShape, edge_id::Int, extension_length::Real)::PolyShape
    V = ps.Vertices[1]
    num_vertices = size(V, 1)

    # Get the selected edge vertices
    edge_1 = edge_id
    edge_2 = mod1(edge_1 + 1, num_vertices)

    p1 = V[edge_1, :]
    p2 = V[edge_2, :]

    # Calculate edge vector and length
    edge_vector = p2 - p1
    edge_length = sqrt(sum(edge_vector .^ 2))

    # Calculate edge angle
    edge_angle = atan(edge_vector[2], edge_vector[1])

    pos_x = p2[1]
    pos_y = p2[2]
    dx = edge_length
    dy = extension_length
    angulo = edge_angle - pi

    box_out = polyShape.polyBox(pos_x, pos_y, dx, dy, angulo)

    return box_out
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
            if !isempty(point_x_12.Vertices) && size(point_x_12.Vertices[1], 1) >= 1
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


function lineLength(l::LineShape)
    numLines = l.NumLines
    
    # Handle empty LineShape
    if numLines == 0 || (numLines > 0 && isempty(l.Vertices)) || (numLines > 0 && size(l.Vertices[1], 1) == 0)
        return numLines > 1 ? Float64[] : 0.0
    end
    
    len = []
    for i = 1:numLines
        # Check if this specific line has vertices
        if size(l.Vertices[i], 1) < 2
            line_length = 0.0
        else
            p1_i = polyShape.shapeVertex(l, i, 1)
            p2_i = polyShape.shapeVertex(l, i, 2)
            line_length = polyShape.calculateDistance(p1_i, p2_i)
        end

        if numLines > 1
            push!(len, line_length)
        else
            len = line_length
        end
    end
    return len
end


function isLineLineParallel(l1::LineShape, l2::LineShape, tol = 0.015)::Bool

    angle1 = polyShape.lineAngle(l1)
    angle2 = polyShape.lineAngle(l2)

    flag = false
    if abs(angle1 - angle2) <= tol || abs((angle1 - pi) - angle2) <= tol || abs(angle1 - (angle2 - pi)) <= tol
        flag = true
    end

    return flag
end


function poly2Constraints(ps_::PolyShape)
    # Convert a PolyShape to halfspace constraints. Only works for convex or near convex polygons.
    ps = setPolyOrientation(polyGdal.shapeHull(ps_), 1)
    v1 = ps.Vertices[1][1,:]
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


function rotate_to_first_ccw(ps::PolyShape, v1::Vector{Float64}, tolerance::Float64=1e-3)
    # Ensure vertices are CCW oriented
    vertices = ps.Vertices[1]
    vertices = polyShape.setPolyOrientation(PolyShape([vertices], 1), 1).Vertices[1]
    idx = findfirst(row -> all(abs.(row .- v1) .< tolerance), eachrow(vertices))
    if isnothing(idx)
        error("The vertex v1 is not found in the given list.")
    end
    rotated_vertices = [vertices[idx:end, :]; vertices[1:idx-1, :]]
    ps_out = PolyShape([rotated_vertices],1)
    return ps_out
end


function polySimplify(ps_::PolyShape, tolerance::Real=0.1)::PolyShape
    ps = polyShape.polyCopy(ps_)
    
    function removeSmallImperfections(vertices::Array{Float64,2}, tolerance::Real)::Array{Float64,2}
        n = size(vertices, 1)
        if n < 4
            return vertices
        end
        
        # First, merge very close consecutive points
        merged_vertices = [vertices[1, :]]
        for i = 2:n
            dist = sqrt(sum((vertices[i, :] - merged_vertices[end]).^2))
            if dist >= tolerance
                push!(merged_vertices, vertices[i, :])
            end
        end
        vertices = hcat(merged_vertices...)'
        n = size(vertices, 1)
        
        if n < 4
            return vertices
        end
        
        keep_vertex = fill(true, n)
        
        # Remove vertices that create small features
        for i = 1:n
            prev_idx = mod1(i - 1, n)
            next_idx = mod1(i + 1, n)
            
            p_prev = vertices[prev_idx, :]
            p_curr = vertices[i, :]
            p_next = vertices[next_idx, :]
            
            # Calculate edge lengths
            edge1_length = sqrt(sum((p_curr - p_prev).^2))
            edge2_length = sqrt(sum((p_next - p_curr).^2))
            
            # Remove vertex if both adjacent edges are very short
            if edge1_length < tolerance && edge2_length < tolerance
                keep_vertex[i] = false
                continue
            end
            
            # Calculate angle at current vertex
            vec1 = p_prev - p_curr
            vec2 = p_next - p_curr
            
            if sqrt(sum(vec1.^2)) > 1e-10 && sqrt(sum(vec2.^2)) > 1e-10
                vec1_norm = vec1 / sqrt(sum(vec1.^2))
                vec2_norm = vec2 / sqrt(sum(vec2.^2))
                
                dot_product = clamp(sum(vec1_norm .* vec2_norm), -1.0, 1.0)
                angle = acos(abs(dot_product))
                
                # Remove vertex if angle is very small (nearly collinear) AND edge is short
                if angle < 0.1 && min(edge1_length, edge2_length) < tolerance * 2
                    keep_vertex[i] = false
                end
            end
        end
        
        # Ensure we keep at least 3 vertices
        if sum(keep_vertex) < 3
            # Keep vertices that are furthest apart
            keep_vertex = fill(false, n)
            keep_vertex[[1, div(n,3), div(2*n,3)]] .= true
        end
        
        return vertices[keep_vertex, :]
    end
    
    function simplifyRegion(vertices::Array{Float64,2}, tolerance::Real)::Array{Float64,2}
        n = size(vertices, 1)
        if n < 3
            return vertices
        end
        
        # First pass: remove small imperfections
        simplified = removeSmallImperfections(vertices, tolerance)
        
        # Second pass: remove nearly collinear points
        n_simp = size(simplified, 1)
        if n_simp >= 4
            keep_vertex = fill(true, n_simp)
            
            for i = 1:n_simp
                if !keep_vertex[i]
                    continue
                end
                
                prev_idx = mod1(i - 1, n_simp)
                next_idx = mod1(i + 1, n_simp)
                
                # Skip if adjacent vertices are already marked for removal
                if !keep_vertex[prev_idx] || !keep_vertex[next_idx]
                    continue
                end
                
                p_prev = simplified[prev_idx, :]
                p_curr = simplified[i, :]
                p_next = simplified[next_idx, :]
                
                # Calculate distance from current point to line between prev and next
                line_start = PointShape(p_prev', 1)
                line_end = PointShape(p_next', 1)
                line_seg = polyShape.createLine(line_start, line_end)
                curr_point = PointShape(p_curr', 1)
                
                distance = abs(polyShape.calculateDistance(line_seg, curr_point))
                
                # Remove if point is very close to the line (nearly collinear)
                if distance < tolerance * 0.5
                    keep_vertex[i] = false
                end
            end
            
            # Ensure we keep at least 3 vertices
            if sum(keep_vertex) >= 3
                simplified = simplified[keep_vertex, :]
            end
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


function ajustaCoordenadasInversa(ps::PolyShape, dx::Real, dy::Real)::PolyShape
    ps_ = polyShape.polyCopy(ps)
    for i = 1:ps_.NumRegions
        ps_.Vertices[i][:, 1] = ps_.Vertices[i][:, 1] .+ dx
        ps_.Vertices[i][:, 2] = ps_.Vertices[i][:, 2] .+ dy
    end
    return ps_
end


function shape_32719to4326(ps::PolyShape)::PolyShape
    EPSG_in = 32719
    EPSG_out = 4326
    ps_ = polyShape.polyCopy(ps)
    source = ArchGDAL.importEPSG(EPSG_in)
    target = ArchGDAL.importEPSG(EPSG_out; order=:trad)

    for i = 1:ps_.NumRegions
        x = ps_.Vertices[i][:, 1]
        y = ps_.Vertices[i][:, 2]
        points = ArchGDAL.createpoint.(x, y)
        ArchGDAL.createcoordtrans(source, target) do transform
            for point in points
                ArchGDAL.transform!(point, transform)
            end
        end
        for j in eachindex(points)
            transformed_x = ArchGDAL.getx(points[j], 0)
            transformed_y = ArchGDAL.gety(points[j], 0)
            ps_.Vertices[i][j, :] = [transformed_x, transformed_y]
        end
    end
    return ps_
end
function shape_4326to32719(geom::T)::T where T <: PosDimGeom
    EPSG_in = 4326
    EPSG_out = 32719
    trans = Proj.Transformation("EPSG:$(EPSG_in)", "EPSG:$(EPSG_out)")
    
    if isa(geom, PolyShape)
        transformed_vertices = [
            hcat([collect(trans(lat, lon)) for (lon, lat) in eachrow(polygon)]...)'
            for polygon in geom.Vertices
        ]
        return PolyShape(transformed_vertices, geom.NumRegions)
    elseif isa(geom, LineShape)
        transformed_vertices = [
            hcat([collect(trans(lat, lon)) for (lon, lat) in eachrow(line)]...)'
            for line in geom.Vertices
        ]
        return LineShape(transformed_vertices, geom.NumLines)
    elseif isa(geom, PointShape)
        n_points = size(geom.Vertices, 1)
        transformed_vertices = hcat([collect(trans(geom.Vertices[i, 2], geom.Vertices[i, 1])) for i in 1:n_points]...)'
        return PointShape(transformed_vertices, geom.NumPoints)
    else
        error("Unsupported geometry type: $(typeof(geom))")
    end
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


function dividePoly(ps::PolyShape, point::Vector{Float64})::Tuple{PolyShape, PolyShape}
    V = ps.Vertices[1]
    n = size(V, 1)
    total_area = polyShape.polyArea(ps)
    
    best_poly1 = PolyShape([], 0)
    best_poly2 = PolyShape([], 0)
    min_area_diff = Inf
    
    # Try all possible ways to divide the polygon by connecting the point to two vertices
    for i = 1:n
        for j = i+2:n
            # Skip adjacent vertices and cases that don't create proper divisions
            if j - i == n - 1
                continue
            end
            
            # Create first polygon: point -> vertex i -> vertices i+1 to j -> point
            V_1_indices = collect(i:j)
            V_1 = [point'; V[V_1_indices, :]; point']
            
            # Create second polygon: point -> vertex j -> vertices j+1 to i (wrapping) -> point
            if j < n
                V_2_indices = [collect(j:n); collect(1:i)]
            else
                V_2_indices = [n; collect(1:i)]
            end
            V_2 = [point'; V[V_2_indices, :]; point']
            
            # Remove duplicate consecutive points
            V_1_clean = unique_consecutive_rows(V_1)
            V_2_clean = unique_consecutive_rows(V_2)
            
            # Create polygons
            if size(V_1_clean, 1) >= 3 && size(V_2_clean, 1) >= 3
                poly1 = PolyShape([V_1_clean], 1)
                poly2 = PolyShape([V_2_clean], 1)
                
                area1 = polyShape.polyArea(poly1)
                area2 = polyShape.polyArea(poly2)
                area_diff = abs(area1 - area2)
                
                # Check if this gives a better (more equal) area split
                if area_diff < min_area_diff
                    min_area_diff = area_diff
                    best_poly1 = deepcopy(poly1)
                    best_poly2 = deepcopy(poly2)
                end
            end
        end
    end
    
    # If no valid division found, create a simple division through polygon centroid
    if min_area_diff == Inf
        centroid = [sum(V[:, 1])/n, sum(V[:, 2])/n]
        
        # Find two vertices that are roughly opposite each other
        distances_from_centroid = [sqrt(sum((V[i, :] - centroid).^2)) for i = 1:n]
        max_dist_idx = argmax(distances_from_centroid)
        
        # Find vertex roughly opposite to max_dist_idx
        opposite_idx = mod1(max_dist_idx + div(n, 2), n)
        
        # Create division
        if max_dist_idx < opposite_idx
            V_1_indices = collect(max_dist_idx:opposite_idx)
            V_2_indices = [collect(opposite_idx:n); collect(1:max_dist_idx)]
        else
            V_1_indices = [collect(max_dist_idx:n); collect(1:opposite_idx)]
            V_2_indices = collect(opposite_idx:max_dist_idx)
        end
        
        V_1 = [point'; V[V_1_indices, :]; point']
        V_2 = [point'; V[V_2_indices, :]; point']
        
        V_1_clean = unique_consecutive_rows(V_1)
        V_2_clean = unique_consecutive_rows(V_2)
        
        best_poly1 = PolyShape([V_1_clean], 1)
        best_poly2 = PolyShape([V_2_clean], 1)
    end
    
    return best_poly1, best_poly2
end

function unique_consecutive_rows(V::Matrix{Float64})::Matrix{Float64}
    if size(V, 1) <= 1
        return V
    end
    
    result = V[1:1, :]
    for i = 2:size(V, 1)
        last_row = result[end, :]
        current_row = V[i, :]
        if !isapprox(current_row, last_row, atol=1e-10)
            result = [result; V[i:i, :]]
        end
    end
    
    # Remove last point if it's the same as first (close polygon properly)
    if size(result, 1) > 2 && isapprox(result[1, :], result[end, :], atol=1e-10)
        result = result[1:end-1, :]
    end
    
    return result
end


function polyHasnan(ps::PolyShape)::Bool
    for region in ps.Vertices
        if any(isnan.(region))
            return true
        end
    end
    return false
end

function isValidShape(shape::PosDimGeom)::Bool
    if typeof(shape) == PolyShape
        if shape.NumRegions == 0
            return false
        end
        for i = 1:shape.NumRegions
            if size(shape.Vertices[i], 1) < 3
                return false
            end
            if any(isnan.(shape.Vertices[i]))
                return false
            end
        end
    elseif typeof(shape) == LineShape
        if shape.NumLines == 0
            return false
        end
        for i = 1:shape.NumLines
            if size(shape.Vertices[i], 1) < 2
                return false
            end
            if any(isnan.(shape.Vertices[i]))
                return false
            end
        end
    end
    return true
end

function isValidShape(pt::PointShape)::Bool
    if pt.NumPoints == 0
        return false
    end
    if any(isnan.(pt.Vertices))
        return false
    end
    return true
end


function lines2Polygons(ls::LineShape, width::Real)::PolyShape
    numLines = ls.NumLines
    
    if numLines == 0
        return PolyShape(Vector{Matrix{Float64}}(), 0)
    end
    
    all_vertices = Vector{Matrix{Float64}}()
    
    for i = 1:numLines
        V_line = ls.Vertices[i]
        n_points = size(V_line, 1)
        
        if n_points < 2
            continue
        end
        
        left_side = Matrix{Float64}(undef, n_points, 2)
        right_side = Matrix{Float64}(undef, n_points, 2)
        half_width = width / 2.0
        
        for j = 1:n_points
            if j == 1
                if n_points == 1
                    continue
                end
                dx = V_line[2, 1] - V_line[1, 1]
                dy = V_line[2, 2] - V_line[1, 2]
            elseif j == n_points
                dx = V_line[n_points, 1] - V_line[n_points-1, 1]
                dy = V_line[n_points, 2] - V_line[n_points-1, 2]
            else
                dx1 = V_line[j, 1] - V_line[j-1, 1]
                dy1 = V_line[j, 2] - V_line[j-1, 2]
                dx2 = V_line[j+1, 1] - V_line[j, 1]
                dy2 = V_line[j+1, 2] - V_line[j, 2]
                
                len1 = sqrt(dx1^2 + dy1^2)
                len2 = sqrt(dx2^2 + dy2^2)
                
                if len1 > 0 && len2 > 0
                    dx1 /= len1
                    dy1 /= len1
                    dx2 /= len2
                    dy2 /= len2
                    dx = (dx1 + dx2) / 2
                    dy = (dy1 + dy2) / 2
                else
                    dx = dx1 + dx2
                    dy = dy1 + dy2
                end
            end
            
            line_len = sqrt(dx^2 + dy^2)
            if line_len > 0
                perp_x = -dy / line_len
                perp_y = dx / line_len
                
                left_side[j, 1] = V_line[j, 1] + half_width * perp_x
                left_side[j, 2] = V_line[j, 2] + half_width * perp_y
                right_side[j, 1] = V_line[j, 1] - half_width * perp_x
                right_side[j, 2] = V_line[j, 2] - half_width * perp_y
            else
                left_side[j, :] = V_line[j, :]
                right_side[j, :] = V_line[j, :]
            end
        end
        
        polygon_vertices = [left_side; reverse(right_side, dims=1)]
        push!(all_vertices, polygon_vertices)
    end
    
    return PolyShape(all_vertices, length(all_vertices))
end

function polyHeight(ps::PolyShape, box::PolyShape, method::Symbol=:average, tolerance::Float64=1e-6)::Float64

    edge_points = polyShape.sampleEdgePoints(ps, 1.)

    intersected_points = polyGdal.shapeIntersect(edge_points, box)
    num_points = intersected_points.NumPoints

    box_edges, _ = polyShape.shape2vector(box)
    base_edge = box_edges[1]
    base_line = polyShape.transformLine(base_edge, :extend, 60.0)

    vec_dist = []
    for i = 1:num_points
        p_i = polyShape.subShape(intersected_points, i)
        d_i = polyShape.calculateDistance(base_line, p_i)
        if d_i > 5
            push!(vec_dist, d_i)
        end
    end

    if isempty(vec_dist)
        return 0.0
    end

    if method == :average
        return sum(vec_dist) / length(vec_dist)
    elseif method == :maximum
        return maximum(vec_dist)
    elseif method == :minimum
        return minimum(vec_dist)
    else
        throw(ArgumentError("Invalid method: $method. Use :average, :maximum, or :minimum"))
    end
end

function sampleEdgePoints(ps::PolyShape, sample_distance::Float64=1.0)::PointShape
    if ps.NumRegions == 0 || isempty(ps.Vertices)
        return PointShape(zeros(Float64, 0, 2), 0)
    end

    all_points = Matrix{Float64}(undef, 0, 2)

    for vertices in ps.Vertices
        n_vertices = size(vertices, 1)
        if n_vertices < 3
            continue
        end

        for i in 1:n_vertices
            p1 = vertices[i, :]
            p2 = vertices[i % n_vertices + 1, :]

            edge_vec = p2 - p1
            edge_len = sqrt(sum(edge_vec.^2))

            if edge_len < sample_distance / 10
                continue
            end

            num_samples = max(1, round(Int, edge_len / sample_distance))

            for j in 0:num_samples-1
                t = j / num_samples
                sample_point = p1 + t * edge_vec
                all_points = vcat(all_points, sample_point')
            end
        end
    end

    if size(all_points, 1) == 0
        return PointShape(zeros(Float64, 0, 2), 0)
    end

    return PointShape(all_points, size(all_points, 1))
end


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



function building2json(results_primer_piso::Dict, results_pisos_superiores::Dict, num_pisos_superiores::Int, alturaPiso::Float64)::Dict{String, String}

    function triangulatePolygon(V::Matrix{Float64})::Vector{Int}
        function pointInTriangle(p::Vector{Float64}, a::Vector{Float64}, b::Vector{Float64}, c::Vector{Float64})::Bool
            d1 = sign((p[1] - b[1]) * (a[2] - b[2]) - (a[1] - b[1]) * (p[2] - b[2]))
            d2 = sign((p[1] - c[1]) * (b[2] - c[2]) - (b[1] - c[1]) * (p[2] - c[2]))
            d3 = sign((p[1] - a[1]) * (c[2] - a[2]) - (c[1] - a[1]) * (p[2] - a[2]))
            has_neg = (d1 < 0) || (d2 < 0) || (d3 < 0)
            has_pos = (d1 > 0) || (d2 > 0) || (d3 > 0)
            return !(has_neg && has_pos)
        end

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
                            if pointInTriangle(pt, p1, p2, p3)
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

            tri_indices = triangulatePolygon(V)
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
            vec_deptos_primer = results_primer_piso["vec_ps_deptos_interior_all"]
            for ps_depto in vec_deptos_primer
                if polyArea(ps_depto) > 0.0
                    addPolyShapeTo3D(ps_depto, 0.0, alturaPiso, all_vertices, all_indices)
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
            vec_terrazas_primer = results_primer_piso["vec_ps_terrazas_all"]
            for ps_terraza in vec_terrazas_primer
                if polyArea(ps_terraza) > 0.0
                    addPolyShapeTo3D(ps_terraza, 0.0, 1.0, all_vertices, all_indices)
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
            ps_area_comun_primer = results_primer_piso["ps_area_comun_total"]
            addPolyShapeTo3D(ps_area_comun_primer, 0.0, alturaPiso, all_vertices, all_indices)

            ps_pasillo = results_pisos_superiores["ps_pasillo"]
            for piso in 1:num_pisos_superiores
                z_low = alturaPiso * piso
                z_high = alturaPiso * (piso + 1)
                addPolyShapeTo3D(ps_pasillo, z_low, z_high, all_vertices, all_indices)
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


function planta2svg(vec_info_deptos::Vector, ps_area_comun::Union{PolyShape, Nothing}, ps_pasillo::Union{PolyShape, Nothing}; nombre_area_comun::String="Circulación")::String
    all_shapes = PolyShape[]
    for info in vec_info_deptos
        push!(all_shapes, info["ps_depto"])
        push!(all_shapes, info["ps_terraza"])
    end
    if ps_area_comun !== nothing
        push!(all_shapes, ps_area_comun)
    end
    if ps_pasillo !== nothing
        push!(all_shapes, ps_pasillo)
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
    push!(svg_parts, ".depto { fill: #4A90D9; stroke: #2C5282; stroke-width: $(stroke_width); }")
    push!(svg_parts, ".terraza { fill: #68D391; stroke: #276749; stroke-width: $(stroke_width); }")
    push!(svg_parts, ".area-comun { fill: #F6AD55; stroke: #C05621; stroke-width: $(stroke_width); }")
    push!(svg_parts, ".pasillo { fill: #CBD5E0; stroke: #4A5568; stroke-width: $(stroke_width); }")
    push!(svg_parts, ".unidad-depto:hover .depto, .unidad-depto:hover .terraza { filter: brightness(1.15); cursor: pointer; }")
    push!(svg_parts, ".unidad-comun:hover .pasillo, .unidad-comun:hover .area-comun { filter: brightness(1.15); cursor: pointer; }")
    push!(svg_parts, "</style>")

    if ps_pasillo !== nothing && ps_pasillo.NumRegions > 0
        area_pasillo = polyArea(ps_pasillo)
        path_d = poly_to_path(ps_pasillo, offset_x, offset_y, height_svg, scale)
        push!(svg_parts, """<g class="unidad-comun" data-tipo="superficie-comun" data-nombre="$(nombre_area_comun)" data-sup-comun="$(round(area_pasillo, digits=2))">""")
        push!(svg_parts, """<title>Superficie común – $(nombre_area_comun)\nSuperficie: $(round(area_pasillo, digits=2)) m²</title>""")
        push!(svg_parts, """<path class="pasillo" d="$(path_d)"/>""")
        push!(svg_parts, "</g>")
    end

    if ps_area_comun !== nothing && ps_area_comun.NumRegions > 0
        area_comun = polyArea(ps_area_comun)
        path_d = poly_to_path(ps_area_comun, offset_x, offset_y, height_svg, scale)
        push!(svg_parts, """<g class="unidad-comun" data-tipo="area-comun" data-sup-comun="$(round(area_comun, digits=2))">""")
        push!(svg_parts, """<title>Área común\nSuperficie: $(round(area_comun, digits=2)) m²</title>""")
        push!(svg_parts, """<path class="area-comun" d="$(path_d)"/>""")
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

        json_depto = replace(vertices_to_json(ps_depto), "\"" => "&quot;")
        json_terraza = replace(vertices_to_json(ps_terraza), "\"" => "&quot;")
        json_edges = replace(edge_lengths_to_json(vec_edge_total_lengths), "\"" => "&quot;")

        push!(svg_parts, """<g class="unidad-depto" data-depto-tipo="$(letra_tipo)" data-stack="$(numeracion)" data-sup-interior="$(area_depto)" data-sup-terraza="$(area_terraza)" data-sup-util="$(area_util)" data-orientacion="$(orientacion)" data-vertices-depto="$(json_depto)" data-vertices-terraza="$(json_terraza)" data-edge-lengths="$(json_edges)">""")
        push!(svg_parts, """<title>Depto Tipo $(letra_tipo) – $(numeracion)\nSup interior: $(area_depto) m²\nSup terraza: $(area_terraza) m²\nSup útil: $(area_util) m²\nOrientación: $(orientacion)</title>""")

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

    function triangulatePolygon(V::Matrix{Float64})::Vector{Int}
        function pointInTriangle(p::Vector{Float64}, a::Vector{Float64}, b::Vector{Float64}, c::Vector{Float64})::Bool
            d1 = sign((p[1] - b[1]) * (a[2] - b[2]) - (a[1] - b[1]) * (p[2] - b[2]))
            d2 = sign((p[1] - c[1]) * (b[2] - c[2]) - (b[1] - c[1]) * (p[2] - c[2]))
            d3 = sign((p[1] - a[1]) * (c[2] - a[2]) - (c[1] - a[1]) * (p[2] - a[2]))
            has_neg = (d1 < 0) || (d2 < 0) || (d3 < 0)
            has_pos = (d1 > 0) || (d2 > 0) || (d3 > 0)
            return !(has_neg && has_pos)
        end

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
                            if pointInTriangle(pt, p1, p2, p3)
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
            tri_indices = triangulatePolygon(V)
            for tri_idx in tri_indices
                append!(all_indices, [region_start + tri_idx])
            end
        end

        top_level = level_regions_info[end]
        top_level_idx = length(level_regions_info)
        for (idx, (region_start, _)) in enumerate(top_level)
            V = original_vertices_dict[(top_level_idx, idx)]
            tri_indices = triangulatePolygon(V)
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

    function triangulatePolygon(V::Matrix{Float64})::Vector{Int}
        function pointInTriangle(p::Vector{Float64}, a::Vector{Float64}, b::Vector{Float64}, c::Vector{Float64})::Bool
            d1 = sign((p[1] - b[1]) * (a[2] - b[2]) - (a[1] - b[1]) * (p[2] - b[2]))
            d2 = sign((p[1] - c[1]) * (b[2] - c[2]) - (b[1] - c[1]) * (p[2] - c[2]))
            d3 = sign((p[1] - a[1]) * (c[2] - a[2]) - (c[1] - a[1]) * (p[2] - a[2]))
            has_neg = (d1 < 0) || (d2 < 0) || (d3 < 0)
            has_pos = (d1 > 0) || (d2 > 0) || (d3 > 0)
            return !(has_neg && has_pos)
        end

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
                            if pointInTriangle(pt, p1, p2, p3)
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
                tri_indices = triangulatePolygon(V)
                for idx in tri_indices
                    append!(all_indices, [floor_start + idx])
                end
            elseif floor_idx == last_floor
                tri_indices = triangulatePolygon(V)
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

    function triangulatePolygon(V::Matrix{Float64})::Vector{Int}

        function pointInTriangle(p::Vector{Float64}, a::Vector{Float64}, b::Vector{Float64}, c::Vector{Float64})::Bool
            d1 = sign((p[1] - b[1]) * (a[2] - b[2]) - (a[1] - b[1]) * (p[2] - b[2]))
            d2 = sign((p[1] - c[1]) * (b[2] - c[2]) - (b[1] - c[1]) * (p[2] - c[2]))
            d3 = sign((p[1] - a[1]) * (c[2] - a[2]) - (c[1] - a[1]) * (p[2] - a[2]))

            has_neg = (d1 < 0) || (d2 < 0) || (d3 < 0)
            has_pos = (d1 > 0) || (d2 > 0) || (d3 > 0)

            return !(has_neg && has_pos)
        end

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
                            if pointInTriangle(pt, p1, p2, p3)
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

        triangle_indices = triangulatePolygon(V)
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


export isPolyConvex,
    polyArea, polyDifference, polyOrientation, polyUnion, polyIntersection, polyIntersects, polyOffset,
    polyEliminaColineales, subShape, shapeVertex, numVertices,
    polyBox, polyRotate, polyReverse, setPolyOrientation, polyCopy, intersectLines,
    lineAngle, halfspaceSignOfPointToLine, lineVec2polyShape, ajustaCoordenadas, polyBoxFromEdge,
    createLine, convHull, midPointSegment, lineLength, isLineLineParallel, partialPolyOffset,
    line2Box, lines2Polygons, poly2Constraints, constraints2poly, rotate_to_first_ccw,
    calculateDistance, shape2vector, transformLine, polySimplify,
    ajusteCoordenadasInversa, shape_32719to4326, shape_4326to32719, polyshape2wkt, dividePoly,
    polyHasnan, sampleEdgePoints, polyShapeLayers2json, threejs2json,
    polyShape2json, building2json, subterraneo2json, planta2json,
    planta2svg
end
