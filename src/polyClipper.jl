module polyClipper

using LandValue, Clipper, LazySets, DataFrames, LinearAlgebra



########################################################################
#              Funciones en base a Clipper                   #
########################################################################


function shape2clipper(ps_::PosDimGeom)
    ps = deepcopy(ps_)

    if typeof(ps) == PolyShape
        n = ps.NumRegions
    else
        n = ps.NumLines
    end
    magnitude = 8
    sigdigits = 10
    vec_path = Vector{Vector{Clipper.IntPoint}}()
    for k = 1:n
        path_k = Vector{Clipper.IntPoint}()
        V_k = ps.Vertices[k]
        for j in eachindex(V_k[:, 1])
            push!(path_k, Clipper.IntPoint(V_k[j, 1], V_k[j, 2], magnitude, sigdigits))
        end
        push!(vec_path, path_k)
    end
    return vec_path
end


function clipper2shape(vec_path_::Vector{Vector{IntPoint}}, shapeType::DataType)
    vec_path = deepcopy(vec_path_)

    n = length(vec_path)
    magnitude = 8
    sigdigits = 10
    V = []
    for k = 1:n
        vec_clipper_k = vec_path[k]
        V_k = zeros(length(vec_clipper_k), 2)
        for j in eachindex(vec_clipper_k)
            p_j = vec_clipper_k[j]
            V_k[j, 1], V_k[j, 2] = Clipper.tofloat(p_j, magnitude, sigdigits)
        end
        push!(V, V_k)
    end
    if shapeType == PolyShape
        ps = PolyShape(V, n)
    elseif shapeType == LineShape
        ps = LineShape(V, n)
    end
    return ps
end


function clipper_op(ct::ClipType, vec_path1_::Vector{Vector{IntPoint}}, vec_path2_::Vector{Vector{IntPoint}})
    vec_path1 = deepcopy(vec_path1_)
    vec_path2 = deepcopy(vec_path2_)

    c = Clipper.Clip()
    if length(vec_path1) == 1
        Clipper.add_path!(c, vec_path1[1], Clipper.PolyTypeSubject, true)
    else
        vec_path1 = clipper_union(vec_path1)
        Clipper.add_paths!(c, vec_path1, Clipper.PolyTypeSubject, true)
    end
    if length(vec_path2) == 1
        Clipper.add_path!(c, vec_path2[1], Clipper.PolyTypeClip, true)
    else
        vec_path2 = clipper_union(vec_path2)
        Clipper.add_paths!(c, vec_path2, Clipper.PolyTypeClip, true)
    end
    _, result_paths = Clipper.execute(c, ct, Clipper.PolyFillTypeEvenOdd, Clipper.PolyFillTypeEvenOdd)
    return result_paths
end


function clipper_union(vec_path1::Vector{Vector{IntPoint}}, vec_path2::Vector{Vector{IntPoint}})
    u_paths = clipper_op(Clipper.ClipTypeUnion, vec_path1, vec_path2)
    return u_paths
end
function clipper_union(vec_paths_::Vector{Vector{IntPoint}})
    vec_paths = deepcopy(vec_paths_)

    num_paths = length(vec_paths)
    if num_paths >= 2
        for i = 1:num_paths
            if i == 1
                vec_path_u = [deepcopy(vec_paths[1])]
            else
                vec_path2 = [deepcopy(vec_paths[i])]
                vec_path_u = clipper_op(Clipper.ClipTypeUnion, vec_path_u, vec_path2)
            end
        end
    else
        vec_path_u = vec_paths
    end
    return vec_path_u
end


function clipper_difference(vec_path1::Vector{Vector{IntPoint}}, vec_path2::Vector{Vector{IntPoint}})
    d_paths = clipper_op(Clipper.ClipTypeDifference, vec_path1, vec_path2)
    return d_paths
end


function clipper_intersection(vec_path1::Vector{Vector{IntPoint}}, vec_path2::Vector{Vector{IntPoint}})
    i_paths = clipper_op(Clipper.ClipTypeIntersection, vec_path1, vec_path2)
    return i_paths
end


function clipper_offset(vec_path_::Vector{Vector{IntPoint}}, delta, cjt=Clipper.JoinTypeMiter, cep=Clipper.EndTypeClosedPolygon)
    vec_path = deepcopy(vec_path_)
    delta = convert(Float64, delta)
    c = Clipper.ClipperOffset()
    if length(vec_path) == 1
        Clipper.add_path!(c, vec_path[1], cjt, cep)
    else
        vec_path = clipper_union(vec_path)
        Clipper.add_paths!(c, vec_path, cjt, cep)
    end
    o_paths = Clipper.execute(c, delta)
    return o_paths
end


function clipper_scale(x::Real, magnitude::Int=8, sigdigits::Int=10)::Int
    return Int(round(x * 10^(sigdigits - magnitude)))
end

# expande todos los lados en la misma distancia
function polyOffset(ps_::PolyShape, dist::Real)::PolyShape
    ps = deepcopy(ps_)

    delta = clipper_scale(dist)
    path = shape2clipper(ps)
    path_offset = clipper_offset(path, delta, Clipper.JoinTypeMiter)
    ps_offset = clipper2shape(path_offset, PolyShape)

    vec_line_ps, _ = polyShape.polyShape2lineVec(ps)
    vec_line_offset, reg_offset = polyShape.polyShape2lineVec(ps_offset)

    vec_line_offset_final = Vector{LineShape}()
    reg_offset_final = Vector{Int}()
    for i in eachindex(vec_line_offset)
        flag_offset_i = [polyShape.isLineLineParallel(vec_line_offset[i], vec_line_ps[j]) for j in eachindex(vec_line_ps)]
        if sum(flag_offset_i) >= 1
            push!(vec_line_offset_final, vec_line_offset[i])
            push!(reg_offset_final, reg_offset[i])
        end
    end
    ps_offset_final = polyShape.lineVec2polyShape(vec_line_offset_final, reg_offset_final)


    return ps_offset_final
end



export shape2clipper, clipper2shape, clipper_op, clipper_union, clipper_difference, clipper_intersection, clipper_offset,
clipper_scale, polyOffset
end
