module polyGdal

using LandValue, ArchGDAL, DataFrames, LinearAlgebra

# polyGdal Function Reference
# ===========================
#
# Core Conversion Functions
# - geom2shape: Convert GDAL geometry objects to polyShape/lineShape/pointShape format
# - shape2geom: Convert polyShape/lineShape/pointShape to GDAL geometry objects
#
# Geometric Analysis
# - shapeArea: Calculate area of polygon using GDAL precision algorithms
# - shapeDistance: Compute minimum distance between two geometry objects
# - partialDistance: Calculate distance matrix between all vertices of two shapes
# - shapeContains: Test if first geometry completely contains second geometry
#
# Boolean Operations
# - shapeDifference: Subtract second shape from first using GDAL boolean operations
# - shapeIntersect: Find intersection between two shapes (returns GeomObject)
# - shapeUnion: Merge two shapes or unify multi-region shape using GDAL algorithms
#
# Geometric Transformations
# - shapeHull: Generate convex hull using GDAL computational geometry
# - shapeSimplify: Simplify geometry by removing vertices within tolerance
# - shapeSimplifyTopology: Topology-preserving simplification with advanced options
# - shapeBuffer: Create buffer zone around geometry with specified distance and segments
# - shapeCentroid: Find geometric centroid of shape using GDAL algorithms
# - partialCentroid: Calculate centroid with partial geometry consideration
#
# Format Conversion
# - astext2shape: Parse WKT (Well-Known Text) strings to create appropriate geometry objects

########################################################################
#              Funciones en base a ArchGDAL                            #
########################################################################

function geom2shape(geom)::GeomObject
    if ArchGDAL.geomname(geom) == "POLYGON"
        geom_ = ArchGDAL.createmultipolygon()
        ArchGDAL.addgeom!(geom_, geom)
        geom = geom_
    elseif ArchGDAL.geomname(geom) == "LINESTRING"
        geom_ = ArchGDAL.createmultilinestring()
        ArchGDAL.addgeom!(geom_, geom)
        geom = geom_
    elseif ArchGDAL.geomname(geom) == "POINT"
        geom_ = ArchGDAL.createmultipoint()
        ArchGDAL.addgeom!(geom_, geom)
        geom = geom_
    end
    if ArchGDAL.geomname(geom) == "MULTIPOLYGON"
        numRegiones = ArchGDAL.ngeom(geom)
        out = PolyShape([], numRegiones)
        for k = 1:numRegiones
            poly_k = ArchGDAL.getgeom(geom, k - 1)
            if isnothing(poly_k) || ArchGDAL.ngeom(poly_k) == 0
                continue
            end
            line_k = ArchGDAL.getgeom(poly_k, 0)
            if isnothing(line_k)
                continue
            end
            numVertices_k = ArchGDAL.ngeom(line_k)
            if numVertices_k == 0
                continue
            end
            V_k = zeros(numVertices_k, 2)
            for i = 1:numVertices_k-1
                V_k[i, 1] = ArchGDAL.getx(line_k, i - 1)
                V_k[i, 2] = ArchGDAL.gety(line_k, i - 1)
            end
            out.Vertices = push!(out.Vertices, V_k)
        end
        out.NumRegions = length(out.Vertices)
        return out
    elseif ArchGDAL.geomname(geom) == "MULTILINESTRING"
        numLines = ArchGDAL.ngeom(geom)
        out = LineShape([], numLines)
        for k = 1:numLines
            line_k = ArchGDAL.getgeom(geom, k - 1)
            if isnothing(line_k)
                continue
            end
            numVertices_k = ArchGDAL.ngeom(line_k)
            if numVertices_k == 0
                continue
            end
            V_k = fill(0.0, numVertices_k, 2)
            for i = 1:numVertices_k
                V_k[i, 1] = ArchGDAL.getx(line_k, i - 1)
                V_k[i, 2] = ArchGDAL.gety(line_k, i - 1)
            end
            out.Vertices = push!(out.Vertices, V_k)
        end
        out.NumLines = length(out.Vertices)
        return out
    elseif ArchGDAL.geomname(geom) == "MULTIPOINT"
        numPoints = ArchGDAL.ngeom(geom)
        V = fill(0.0, numPoints, 2)
        valid_points = 0
        for i = 1:numPoints
            point_i = ArchGDAL.getgeom(geom, i - 1)
            if isnothing(point_i)
                continue
            end
            valid_points += 1
            V[valid_points, 1] = ArchGDAL.getx(point_i, 0)
            V[valid_points, 2] = ArchGDAL.gety(point_i, 0)
        end
        if valid_points == 0
            V = fill(0.0, 1, 2)
            valid_points = 1
        else
            V = V[1:valid_points, :]
        end
        out = PointShape(V, valid_points)
        return out
    end
end


function shape2geom(shape::PolyShape)
    n = shape.NumRegions
    out = ArchGDAL.createmultipolygon()
    for k = 1:n
        V_k = shape.Vertices[k]
        largo_k = size(V_k, 1)
        line_k = [(Float64(V_k[i, 1]), Float64(V_k[i, 2])) for i = 1:largo_k]
        push!(line_k, (Float64(V_k[1, 1]), Float64(V_k[1, 2])))
        poly_k = ArchGDAL.createpolygon(line_k)
        ArchGDAL.addgeom!(out, poly_k)
    end
    return out
end
function shape2geom(shape::LineShape)
    n = shape.NumLines
    out = ArchGDAL.createmultilinestring()
    for k = 1:n
        V_k = shape.Vertices[k]
        largo_k = size(V_k, 1)
        poly_k = ArchGDAL.createlinestring([(Float64(V_k[i, 1]), Float64(V_k[i, 2])) for i = 1:largo_k])
        ArchGDAL.addgeom!(out, poly_k)
    end
    return out
end
function shape2geom(shape::PointShape)
    n = shape.NumPoints
    V = shape.Vertices
    largo, dim = size(V)
    if dim == 2
        out = ArchGDAL.createmultipoint([Float64(V[i, 1]) for i = 1:largo], [Float64(V[i, 2]) for i = 1:largo])
    elseif dim == 3
        out = ArchGDAL.createmultipoint([Float64(V[i, 1]) for i = 1:largo], [Float64(V[i, 2]) for i = 1:largo], [Float64(V[i, 3]) for i = 1:largo])
    end
    return out
end


function shapeArea(ps::PolyShape)::Float64

    num_regions = ps.NumRegions
    area = 0
    for i = 1:num_regions
        ps_i = polyShape.subShape(ps, i)
        geom_i = polyGdal.shape2geom(ps_i)
        area_i = ArchGDAL.geomarea(geom_i)
        if polyShape.polyOrientation(ps_i) == 1
            area += area_i
        else
            area -= area_i
        end
    end
    return area
end


function shapeContains(shape1::PosDimGeom, shape2::GeomObject)::Bool
    numRegions1 = shape1.NumRegions
    if typeof(shape2) == LineShape
        numRegions2 = shape2.NumLines
    elseif typeof(shape2) == PointShape
        numRegions2 = shape2.NumPoints
    else
        numRegions2 = shape2.NumRegions
    end
    flag_out = false
    for i1 = 1:numRegions1
        geom1 = polyGdal.shape2geom(polyShape.subShape(shape1, i1))
        for i2 = 1:numRegions2
            geom2 = polyGdal.shape2geom(polyShape.subShape(shape2, i2))
            flag_12 = ArchGDAL.contains(geom1, geom2)
            if flag_12
                flag_out = true
            end
        end
    end

    return flag_out
end


function shapeDifference(shape1::PosDimGeom, shape2::PosDimGeom)::PosDimGeom
    geom1 = polyGdal.shape2geom(shape1)
    geom2 = polyGdal.shape2geom(shape2)
    geom_out = ArchGDAL.difference(geom1, geom2)
    shape_out = polyGdal.geom2shape(geom_out)
    return shape_out
end


function shapeIntersect(shape1::GeomObject, shape2::GeomObject)::GeomObject
    geom1 = polyGdal.shape2geom(shape1)
    geom2 = polyGdal.shape2geom(shape2)
    geom_out = ArchGDAL.intersection(geom1, geom2)
    shape_out = polyGdal.geom2shape(geom_out)
    return shape_out
end


function shapeTouches(shape1::PosDimGeom, shape2::PosDimGeom)::Bool
    try
        geom1 = polyGdal.shape2geom(shape1)
        geom2 = polyGdal.shape2geom(shape2)
        
        # Use GDAL's built-in intersects method which is much faster
        return ArchGDAL.intersects(geom1, geom2)
    catch
        return false
    end
end


function shapeUnion(shape1::PosDimGeom, shape2::PosDimGeom)::PosDimGeom # polyUnion es más robusto
    geom1 = polyGdal.shape2geom(shape1)
    geom2 = polyGdal.shape2geom(shape2)
    geom_out = ArchGDAL.union(geom1, geom2)
    shape_out = polyGdal.geom2shape(geom_out)
    return shape_out
end
function shapeUnion(shape::PolyShape)::PolyShape
    numElementos = shape.NumRegions
    shape_out = PolyShape([], 0)
    for i = 1:numElementos
        shape_i = polyShape.subShape(shape, i)
        shape_out = polyGdal.shapeUnion(shape_out, shape_i)
    end
    return shape_out
end
function shapeUnion(shape::LineShape)::LineShape
    numElementos = shape.NumLines
    shape_out = LineShape([], 0)
    for i = 1:numElementos
        shape_i = polyShape.subShape(shape, i)
        shape_out = polyGdal.shapeUnion(shape_out, shape_i)
    end
    return shape_out
end


function shapeHull(shape::PosDimGeom)::PosDimGeom
    geom = polyGdal.shape2geom(shape)
    geom_out = ArchGDAL.convexhull(geom)
    shape_out = polyGdal.geom2shape(geom_out)
    V = shape_out.Vertices[1]
    shape_out = PolyShape([V[1:end-1, :]], 1)
    return shape_out
end


function shapeSimplify(shape::PosDimGeom, tol::Real)::PosDimGeom
    shape_out = polyGdal.shapeSimplifyTopology(shape, tol, false)
    return shape_out
end


function shapeSimplifyTopology(shape::PosDimGeom, tol::Real=0.05, flagTopo::Bool=true)::PosDimGeom
    if isa(shape, PolyShape)
        numElementos = shape.NumRegions
    elseif isa(shape, LineShape)
        numElementos = shape.NumLines
    end
    if numElementos == 1
        geom = polyGdal.shape2geom(shape)
        if flagTopo
            geom_ = ArchGDAL.simplifypreservetopology(geom, tol)
        else
            geom_ = ArchGDAL.simplify(geom, tol)
        end
        shape_ = polyGdal.geom2shape(geom_)
        shape_ = PolyShape([shape_.Vertices[1][1:end-1, :]], 1)
        is_ccw = polyShape.polyOrientation(shape_)
        V = shape_.Vertices[1]
        if is_ccw == -1 # counter clockwise?
            V = polyShape.reversePath(V)
        end
        V = [V]
    else
        V = []
        for i = 1:numElementos
            shape_i = polyShape.subShape(shape, i)
            geom_i = polyGdal.shape2geom(shape_i)
            if flagTopo
                geom_i_ = ArchGDAL.simplifypreservetopology(geom_i, tol)
            else
                geom_i_ = ArchGDAL.simplify(geom_i, tol)
            end
            shape_i_ = polyGdal.geom2shape(geom_i_)
            shape_i_ = PolyShape([shape_i_.Vertices[1][1:end-1, :]], 1)
            is_ccw = polyShape.polyOrientation(shape_i_)
            V_i = shape_i_.Vertices[1]
            if is_ccw == -1 # counter clockwise?
                V_i = polyShape.reversePath(V_i)
            end
            push!(V, V_i)
        end
    end
    if isa(shape, PolyShape)
        shape_out = PolyShape(V, length(V))
    elseif isa(shape, LineShape)
        shape_out = LineShape(V, length(V))
    end

    return shape_out

end


function shapeBuffer(shape::PosDimGeom, dist::Real, nseg::Int)
    if isa(shape, PolyShape)
        numElementos = shape.NumRegions
    elseif isa(shape, LineShape)
        numElementos = shape.NumLines
    end
    if numElementos == 1
        geom = polyGdal.shape2geom(shape)
        poly_ = ArchGDAL.buffer(geom, dist, nseg)
        shape_ = polyGdal.geom2shape(poly_)

        shape_ = PolyShape([shape_.Vertices[1][1:end-1, :]], 1)
        is_ccw = polyShape.polyOrientation(shape_)
        V = shape_.Vertices[1]
        if is_ccw == -1 # counter clockwise?
            V = polyShape.reversePath(V)
        end
        ps_out = PolyShape([V], 1)
        return ps_out
    else
        V = []
        for k = 1:numElementos
            shape_k = isa(shape, LineShape) ? LineShape([shape.Vertices[k]], 1) : PolyShape([shape.Vertices[k]], 1)
            geom_k = polyGdal.shape2geom(shape_k)
            poly_k = ArchGDAL.buffer(geom_k, dist, nseg)
            shape_k_ = polyGdal.geom2shape(poly_k)
            shape_k_ = PolyShape([shape_k_.Vertices[1][1:end-1, :]], 1)
            is_ccw = polyShape.polyOrientation(shape_k_)
            V_k = shape_k_.Vertices[1]
            if is_ccw == -1 # counter clockwise?
                V_k = polyShape.reversePath(V_k)
            end
            push!(V, V_k)
        end
        ps_out = PolyShape(V, numElementos)
        return ps_out
    end
end
function shapeBuffer(shape::PointShape, dist::Real=0.1)
    numElementos = shape.NumPoints
    VV = Array{Array{Float64,2},1}(undef, numElementos)
    for i = 1:numElementos
        point_i = PointShape(shape.Vertices[i, :]', 1)
        geom = polyGdal.shape2geom(point_i)
        poly_ = ArchGDAL.buffer(geom, dist, 3)
        shape_ = polyGdal.geom2shape(poly_)
        shape_ = PolyShape([shape_.Vertices[1][1:end-1, :]], 1)
        is_ccw = polyShape.polyOrientation(shape_)
        V = shape_.Vertices[1]
        if is_ccw == -1 # counter clockwise?
            V = polyShape.reversePath(V)
        end
        VV[i] = V

    end
    ps_out = PolyShape(VV, numElementos)
    return ps_out

end


function shapeCentroid(shape::PosDimGeom)::PointShape
    geom_point = ArchGDAL.centroid(polyGdal.shape2geom(shape))
    out = polyGdal.geom2shape(geom_point)
    return out
end


function partialCentroid(shape::PosDimGeom)::PointShape
    if isa(shape, PolyShape)
        numElements = shape.NumRegions
    elseif isa(shape, LineShape)
        numElements = shape.NumLines
    end
    V = fill(0.0, numElements, 2)
    for i = 1:numElements
        shape_i = polyShape.subShape(shape, i)
        cent_i = polyGdal.shapeCentroid(shape_i)
        V[i, :] = cent_i.Vertices
    end
    out = PointShape(V, numElements)
    return out
end

   
function shapeDistance(shape1::GeomObject, shape2::GeomObject)::Float64
    geom1 = polyGdal.shape2geom(shape1)
    geom2 = polyGdal.shape2geom(shape2)
    dist = ArchGDAL.distance(geom1, geom2)
    return dist
end


function partialDistance(shape1::PosDimGeom, shape2::PosDimGeom)::Array{Float64,2}
    if isa(shape1, PolyShape)
        numElements1 = shape1.NumRegions
    elseif isa(shape1, LineShape)
        numElements1 = shape1.NumLines
    elseif isa(shape1, PointShape)
        numElements1 = shape1.NumPoints
    end
    if isa(shape2, PolyShape)
        numElements2 = shape2.NumRegions
    elseif isa(shape2, LineShape)
        numElements2 = shape2.NumLines
    elseif isa(shape2, PointShape)
        numElements2 = shape2.NumPoints
    end
    distMat = fill(0.0, numElements1, numElements2)
    for i = 1:numElements1
        shape_i = polyShape.subShape(shape1, i)
        for j = 1:numElements2
            shape_j = polyShape.subShape(shape2, j)
            distMat[i, j] = polyGdal.shapeDistance(shape_i, shape_j)
        end
    end
    return distMat
end


function astext2shape(str)::GeomObject
    str = convert.(String, deepcopy(str))
    
    if isa(str, Array)
        if length(str) == 0
            error("Empty string array provided")
        end
        
        # Detect geometry type from first WKT string
        first_geom = ArchGDAL.fromWKT(str[1])
        geom_type = ArchGDAL.geomname(first_geom)
        
        if startswith(geom_type, "POLYGON") || startswith(geom_type, "MULTI")
            # Handle as PolyShape
            V = []
            for i in eachindex(str)
                shape_i = polyGdal.geom2shape(ArchGDAL.fromWKT(str[i]))
                if isa(shape_i, PolyShape)
                    for j in 1:shape_i.NumRegions
                        V_ = shape_i.Vertices[j]
                        push!(V, V_[1:end-1, :])
                    end
                else
                    error("Mixed geometry types in array not supported")
                end
            end
            return PolyShape(V, length(V))
            
        elseif startswith(geom_type, "LINESTRING")
            # Handle as LineShape
            geom_ls = ArchGDAL.createmultilinestring()
            for i in eachindex(str)
                shape_i = polyGdal.geom2shape(ArchGDAL.fromWKT(str[i]))
                if isa(shape_i, LineShape)
                    V_i = shape_i.Vertices[1]
                    geom_i = polyGdal.shape2geom(LineShape([V_i], 1))
                    geom_ls = ArchGDAL.union(geom_ls, geom_i)
                else
                    error("Mixed geometry types in array not supported")
                end
            end
            return polyGdal.geom2shape(geom_ls)
            
        elseif startswith(geom_type, "POINT")
            # Handle as PointShape
            V = []
            for i in eachindex(str)
                shape_i = polyGdal.geom2shape(ArchGDAL.fromWKT(str[i]))
                if isa(shape_i, PointShape)
                    push!(V, shape_i.Vertices[1, :])
                else
                    error("Mixed geometry types in array not supported")
                end
            end
            V_matrix = hcat(V...)'
            return PointShape(V_matrix, length(str))
        else
            error("Unsupported geometry type: $(geom_type)")
        end
    else
        # Single WKT string
        geom = ArchGDAL.fromWKT(str)
        shape = polyGdal.geom2shape(geom)
        
        if isa(shape, PolyShape)
            V = []
            for j in 1:shape.NumRegions
                V_ = shape.Vertices[j]
                push!(V, V_[1:end-1, :])
            end
            return PolyShape(V, length(V))
        else
            return shape
        end
    end
end



export geom2shape, shape2geom, shapeArea, shapeContains, shapeDifference, shapeIntersect, shapeUnion, shapeHull, 
shapeSimplify, shapeSimplifyTopology, shapeBuffer, shapeCentroid, partialCentroid, shapeDistance, 
partialDistance, astext2shape, shapeTouches
end
