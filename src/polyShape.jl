module polyShape

using LandValue, ..poly2D, Devices, Clipper, ArchGDAL, PyCall, PyPlot



########################################################################
#              Funciones para efectuar Plot                            #
########################################################################

# Grafica polyshape en 2D.
function plotPolyshape2D(ps::GeomObject, color::String="red", alpha::Float64=1.0; fig::Union{Nothing,PyPlot.Figure}=nothing, ax=nothing, ax_mat=nothing, line_width::Float64=0.5, line_end::Int64=3)

    if ps isa PointShape
        numSectors = ps.NumPoints
        point_width = 0.5
        ps = polyShape.shapeBuffer(ps, point_width)
    elseif ps isa LineShape
        numSectors = ps.NumLines
        ps = polyShape.shapeBuffer(ps, line_width, line_end)
    else
        numSectors = ps.NumRegions
    end

    patch = PyCall.pyimport("matplotlib.patches")
    plt = PyCall.pyimport("matplotlib.pyplot")

    if ax_mat === nothing
        min_ax = 0
        max_ax = 0
    else
        min_ax = ax_mat[1]
        max_ax = ax_mat[2]
    end

    for i = 1:numSectors
        V_i = ps.Vertices[i]

        if fig === nothing
            PyCall.pygui(true)

            fig = plt.figure()
            ax = fig.add_subplot(1, 1, 1)

            min_ax = minimum([minimum(V_i[:, 1]) minimum(V_i[:, 2])])
            max_ax = maximum([maximum(V_i[:, 1]) maximum(V_i[:, 2])])
        else
            min_ax = minimum([min_ax minimum(V_i[:, 1]) minimum(V_i[:, 2])])
            max_ax = maximum([max_ax maximum(V_i[:, 1]) maximum(V_i[:, 2])])
        end

        ax.set_xlim(min_ax, max_ax)
        ax.set_ylim(min_ax, max_ax)
        ax.set_aspect("equal")
        ax.grid("on")

        polygon = patch.Polygon(V_i, true, color=color, alpha=alpha)
        ax.add_patch(polygon)

    end

    ax_mat = [min_ax max_ax]

    return fig, ax, ax_mat

end



# Grafica múltiples polyshape 2D en espacio 3D a distintas alturas.
function plotPolyshape2DVecin3D(vec_ps::Array{polyShape.PolyShape,1}, vec_h, fc::String="red", a::Float64=0.1; fig::Union{Nothing,PyPlot.Figure}=nothing, ax=nothing, ax_mat=nothing, line_width::Float64=0.5, line_end::Int64=3)
    fig_ = []
    ax_ = []
    ax_mat_ = []
    for i in eachindex(vec_h)
        ps_i = vec_ps[i]
        h_i = vec_h[i]
        if i == 1
            fig_, ax_, ax_mat_ = plotPolyshape2Din3D(ps_i, h_i, fc, a, fig=fig, ax=ax, ax_mat=ax_mat)
        end
        fig_, ax_, ax_mat_ = plotPolyshape2Din3D(ps_i, h_i, fc, a, fig=fig_, ax=ax_, ax_mat=ax_mat_)
    end
    return fig_, ax_, ax_mat_
end


# Grafica polyshape 2D en espacio 3D a una altura height.
function plotPolyshape2Din3D(ps::PointShape, height::Float64=0.0, fc::String="blue", a::Float64=0.25; fig::Union{Nothing,PyPlot.Figure}=nothing, ax=nothing, ax_mat=nothing, line_width::Float64=0.5, filestr="none")
    ps = polyShape.shapeBuffer(ps, line_width)
    fig, ax, ax_mat = plotPolyshape2Din3D(ps, height, fc, a; fig=fig, ax=ax, ax_mat=ax_mat)
end
function plotPolyshape2Din3D(ps::LineShape, height::Real=0.0, fc::String="blue", a::Float64=0.25; fig::Union{Nothing,PyPlot.Figure}=nothing, ax=nothing, ax_mat=nothing, line_width::Float64=0.5, line_end::Int64=3, filestr="none")
    ps = polyShape.shapeBuffer(ps, line_width, line_end)
    fig, ax, ax_mat = plotPolyshape2Din3D(ps, height, fc, a; fig=fig, ax=ax, ax_mat=ax_mat)
end
function plotPolyshape2Din3D(ps::GeomObject, height::Real=0.0, fc::String="blue", a::Float64=0.25; fig::Union{Nothing,PyPlot.Figure}=nothing, ax=nothing, ax_mat=nothing, filestr="none")
    plt = pyimport("matplotlib.pyplot")
    art3d = pyimport("mpl_toolkits.mplot3d.art3d")
    PyCall.pyimport("mpl_toolkits.mplot3d")

    numSectors = ps.NumRegions

    if ax_mat === nothing
        min_ax = 0
        max_ax = 0
    else
        min_ax = ax_mat[1]
        max_ax = ax_mat[2]
    end

    for i = 1:numSectors
        V_i = ps.Vertices[i]
        numVerticesTotales, numDim = size(V_i)

        if fig === nothing
            pygui(true)

            fig = plt.figure()
            ax = fig.add_subplot(projection="3d")

            if numDim == 3
                min_ax = minimum([minimum(V_i[:, 1]) minimum(V_i[:, 2]) minimum(V_i[:, 3])])
                max_ax = maximum([maximum(V_i[:, 1]) maximum(V_i[:, 2]) maximum(V_i[:, 3])])
            else
                min_ax = minimum([minimum(V_i[:, 1]) minimum(V_i[:, 2])])
                max_ax = maximum([maximum(V_i[:, 1]) maximum(V_i[:, 2])])
            end

        else
            if numDim == 3
                min_ax = minimum([min_ax minimum(V_i[:, 1]) minimum(V_i[:, 2]) minimum(V_i[:, 3])])
                max_ax = maximum([max_ax maximum(V_i[:, 1]) maximum(V_i[:, 2]) maximum(V_i[:, 3])])
            else
                min_ax = minimum([min_ax minimum(V_i[:, 1]) minimum(V_i[:, 2])])
                max_ax = maximum([max_ax maximum(V_i[:, 1]) maximum(V_i[:, 2])])
            end
        end

        ax.set_xlim(min_ax, max_ax)
        ax.set_ylim(min_ax, max_ax)
        ax.set_zlim(max(0, min_ax), max_ax)

        if numDim == 3

            conjuntoAlturas = unique(V_i[:, 3])
            numAlturas = length(conjuntoAlturas)

            numVerticesBase = Int(round(numVerticesTotales / numAlturas))

            for k = 2:numAlturas

                x1vec = V_i[numVerticesBase*(k-2)+1:numVerticesBase*(k-1), 1]
                y1vec = V_i[numVerticesBase*(k-2)+1:numVerticesBase*(k-1), 2]
                z1vec = V_i[numVerticesBase*(k-2)+1:numVerticesBase*(k-1), 3]

                x2vec = V_i[numVerticesBase*(k-1)+1:numVerticesBase*k, 1]
                y2vec = V_i[numVerticesBase*(k-1)+1:numVerticesBase*k, 2]
                z2vec = V_i[numVerticesBase*(k-1)+1:numVerticesBase*k, 3]

                verts = []

                for j = 1:numVerticesBase
                    if j == numVerticesBase
                        j0 = j
                        j1 = 1
                    else
                        j0 = j
                        j1 = j + 1
                    end
                    x1 = x1vec[j0]
                    x2 = x1vec[j1]
                    x3 = x2vec[j1]
                    x4 = x2vec[j0]

                    y1 = y1vec[j0]
                    y2 = y1vec[j1]
                    y3 = y2vec[j1]
                    y4 = y2vec[j0]

                    z1 = z1vec[j0]
                    z2 = z1vec[j1]
                    z3 = z2vec[j1]
                    z4 = z2vec[j0]

                    vert = [[x1, y1, z1],
                        [x2, y2, z2],
                        [x3, y3, z3],
                        [x4, y4, z4]]

                    push!(verts, vert)

                end

                ax.add_collection3d(art3d.Poly3DCollection(verts, facecolors=fc, linewidths=0.4, edgecolors="k", alpha=a))
            end

        else
            numVerticesBase = Int(numVerticesTotales)

            V_i = [V_i height .* ones(numVerticesTotales, 1)]

            verts_ = []
            for j = 1:numVerticesTotales
                vert = [V_i[j, 1], V_i[j, 2], V_i[j, 3]]
                push!(verts_, vert)
            end
            verts = [verts_]

            ax.add_collection3d(art3d.Poly3DCollection(verts, facecolors=fc, linewidths=0.4, edgecolors="k", alpha=a))

        end

        ax.set_xlabel("X")
        ax.set_ylabel("Y")
        ax.set_zlabel("Z")
    end

    # Hide grid lines
    ax.grid(false)

    # Hide axes ticks
    ax.set_xticks([])
    ax.set_yticks([])
    ax.set_zticks([])

    plt.axis("off")

    plt.show()

    if filestr != "none"
        plt.savefig(filestr, dpi=300)
    end

    ax_mat = [min_ax max_ax]

    fig, ax, ax_mat

end



# Grafica polyshape 3D en espacio 3D.
function plotPolyshape3D(ps_volteor::PolyShape, matConexionVertices::Array{Float64,2}, vecVertices::Array{Any,1}, fc::String="red", a::Float64=0.25; fig::Union{Nothing,PyPlot.Figure}=nothing, ax=nothing, ax_mat=nothing, filestr="none")
    plt = pyimport("matplotlib.pyplot")
    art3d = pyimport("mpl_toolkits.mplot3d.art3d")
    pyimport("mpl_toolkits.mplot3d")

    if ax_mat === nothing
        min_ax = 0
        max_ax = 0
    else
        min_ax = ax_mat[1]
        max_ax = ax_mat[2]
    end

    V_ = ps_volteor.Vertices[1]
    #numVerticesTotales = size(V_,1)

    if fig === nothing
        pygui(true)

        fig = plt.figure()
        ax = fig.add_subplot(projection="3d")

        min_ax = minimum([minimum(V_[:, 1]) minimum(V_[:, 2]) minimum(V_[:, 3])])
        max_ax = maximum([maximum(V_[:, 1]) maximum(V_[:, 2]) maximum(V_[:, 3])])

    else
        min_ax = minimum([min_ax minimum(V_[:, 1]) minimum(V_[:, 2]) minimum(V_[:, 3])])
        max_ax = maximum([max_ax maximum(V_[:, 1]) maximum(V_[:, 2]) maximum(V_[:, 3])])
    end

    ax.set_xlim(min_ax, max_ax)
    ax.set_ylim(min_ax, max_ax)
    ax.set_zlim(max(0, min_ax), max_ax)

    conjuntoAlturas = unique(V_[:, 3])
    numAlturas = length(conjuntoAlturas)

    #numVerticesBase = Int(round(numVerticesTotales / numAlturas))

    for k = 1:numAlturas-1

        verts = []

        for j = 1:length(vecVertices[k])
            if j == length(vecVertices[k])
                jl0 = Int.(vecVertices[k][j])
                jl1 = Int.(vecVertices[k][1])
            else
                jl0 = Int.(vecVertices[k][j])
                jl1 = Int.(vecVertices[k][j+1])
            end
            x1 = V_[jl0, 1]
            y1 = V_[jl0, 2]
            z1 = V_[jl0, 3]
            x2 = V_[jl1, 1]
            y2 = V_[jl1, 2]
            z2 = V_[jl1, 3]
            ju0 = Int.(matConexionVertices[matConexionVertices[:, 1].==jl0, 2])[1]
            ju1 = Int.(matConexionVertices[matConexionVertices[:, 1].==jl1, 2])[1]

            x3 = V_[ju1, 1]
            y3 = V_[ju1, 2]
            z3 = V_[ju1, 3]
            x4 = V_[ju0, 1]
            y4 = V_[ju0, 2]
            z4 = V_[ju0, 3]

            vert = [[x1, y1, z1],
                [x2, y2, z2],
                [x3, y3, z3],
                [x4, y4, z4]]

            push!(verts, vert)

        end

        ax.add_collection3d(art3d.Poly3DCollection(verts, facecolors=fc, linewidths=0.06, edgecolors="k", alpha=a))
    end

    ax.set_xlabel("X")
    ax.set_ylabel("Y")
    ax.set_zlabel("Z")

    plt.show()

    if filestr != "none"
        plt.savefig(filestr)
    end

    ax_mat = [min_ax max_ax]

    fig, ax, ax_mat

end




function plotScatter3d(x, y, z, fig=nothing, ax=nothing, ax_mat=nothing, color="red", marker="o", alpha=0.3)

    plt = pyimport("matplotlib.pyplot")
    pyimport("mpl_toolkits.mplot3d")


    if fig === nothing
        pygui(true)

        fig = plt.figure()
        ax = fig[:add_subplot](111, projection="3d")

        min_ax_x = minimum(x)
        min_ax_y = minimum(y)
        min_ax_z = minimum(z)
        max_ax_x = maximum(x)
        max_ax_y = maximum(y)
        max_ax_z = maximum(z)
    else
        min_ax_x = ax_mat[1, 1]
        min_ax_y = ax_mat[2, 1]
        min_ax_z = ax_mat[3, 1]
        max_ax_x = ax_mat[1, 2]
        max_ax_y = ax_mat[2, 2]
        max_ax_z = ax_mat[3, 2]
        min_ax_x = minimum([min_ax_x minimum(x)])
        min_ax_y = minimum([min_ax_y minimum(y)])
        min_ax_z = minimum([min_ax_z minimum(z)])
        max_ax_x = maximum([max_ax_x maximum(x)])
        max_ax_y = maximum([max_ax_y maximum(y)])
        max_ax_z = maximum([max_ax_z maximum(z)])

    end

    ax.set_xlim(min_ax_x, max_ax_x)
    ax.set_ylim(min_ax_y, max_ax_y)
    ax.set_zlim(min_ax_z, max_ax_z)

    ax[:scatter3D](x, y, z, color=color, marker=marker, alpha=alpha)

    ax.set_xlabel("X")
    ax.set_ylabel("Y")
    ax.set_zlabel("Z")

    plt.show()

    ax_mat = [min_ax_x max_ax_x; min_ax_y max_ax_y; min_ax_z max_ax_z]

    return fig, ax, ax_mat

end



########################################################################
########################################################################
########################################################################



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
            line_k = ArchGDAL.getgeom(poly_k, 0)
            numVertices_k = ArchGDAL.ngeom(line_k)
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
            numVertices_k = ArchGDAL.ngeom(line_k)
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
        for i = 1:numPoints
            point_i = ArchGDAL.getgeom(geom, i - 1)
            V[i, 1] = ArchGDAL.getx(point_i, 0)
            V[i, 2] = ArchGDAL.gety(point_i, 0)
        end
        out = PointShape(V, numPoints)
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
    largo = size(V, 1)
    out = ArchGDAL.createmultipoint([Float64(V[i, 1]) for i = 1:largo], [Float64(V[i, 2]) for i = 1:largo])
    return out
end


function shapeArea(shape::PosDimGeom)::Float64
    geom = polyShape.shape2geom(shape)
    area = ArchGDAL.geomarea(geom)

    return area
end

function shapeContains(shape1::PosDimGeom, shape2::GeomObject)::Bool
    geom1 = shape2geom(shape1)
    geom2 = shape2geom(shape2)
    flag_out = ArchGDAL.contains(geom1, geom2)
    return flag_out
end



function shapeDifference(shape1::PosDimGeom, shape2::PosDimGeom)::PosDimGeom
    geom1 = shape2geom(shape1)
    geom2 = shape2geom(shape2)
    geom_out = ArchGDAL.difference(geom1, geom2)
    shape_out = geom2shape(geom_out)
    return shape_out
end


function shapeIntersect(shape1::PosDimGeom, shape2::PosDimGeom)::GeomObject
    geom1 = shape2geom(shape1)
    geom2 = shape2geom(shape2)
    geom_out = ArchGDAL.intersection(geom1, geom2)
    shape_out = geom2shape(geom_out)
    return shape_out
end


function shapeUnion(shape1::PosDimGeom, shape2::PosDimGeom)::PosDimGeom # polyUnion es más robusto
    geom1 = shape2geom(shape1)
    geom2 = shape2geom(shape2)
    geom_out = ArchGDAL.union(geom1, geom2)
    shape_out = geom2shape(geom_out)
    return shape_out
end
function shapeUnion(shape::PolyShape)::PolyShape
    numElementos = shape.NumRegions
    shape_out = PolyShape([], 0)
    for i = 1:numElementos
        shape_i = subShape(shape, i)
        shape_out = shapeUnion(shape_out, shape_i)
    end
    return shape_out
end
function shapeUnion(shape::LineShape)::LineShape
    numElementos = shape.NumLines
    shape_out = LineShape([], 0)
    for i = 1:numElementos
        shape_i = subShape(shape, i)
        shape_out = shapeUnion(shape_out, shape_i)
    end
    return shape_out
end


function shapeHull(shape::PosDimGeom)::PosDimGeom

    geom = shape2geom(shape)
    geom_out = ArchGDAL.convexhull(geom)
    shape_out = geom2shape(geom_out)
    V = shape_out.Vertices[1]
    shape_out = PolyShape([V[1:end-1, :]], 1)
    return shape_out
end


function shapeSimplify(shape::PosDimGeom, tol::Float64)::PosDimGeom
    shape_out = shapeSimplifyTopology(shape, tol, false)
    return shape_out
end

function shapeSimplifyTopology(shape::PosDimGeom, tol::Float64=0.05, flagTopo::Bool=true)::PosDimGeom
    if isa(shape, PolyShape)
        numElementos = shape.NumRegions
    elseif isa(shape, LineShape)
        numElementos = shape.NumLines
    end
    if numElementos == 1
        geom = shape2geom(shape)
        if flagTopo
            geom_ = ArchGDAL.simplifypreservetopology(geom, tol)
        else
            geom_ = ArchGDAL.simplify(geom, tol)
        end
        shape_ = geom2shape(geom_)
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
            shape_i = subShape(shape, i)
            geom_i = shape2geom(shape_i)
            if flagTopo
                geom_i_ = ArchGDAL.simplifypreservetopology(geom_i, tol)
            else
                geom_i_ = ArchGDAL.simplify(geom_i, tol)
            end
            shape_i_ = geom2shape(geom_i_)
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



function shapeBuffer(shape::PosDimGeom, dist, nseg)::PosDimGeom
    if isa(shape, PolyShape)
        numElementos = shape.NumRegions
    elseif isa(shape, LineShape)
        numElementos = shape.NumLines
    end
    if numElementos == 1
        geom = shape2geom(shape)
        poly_ = ArchGDAL.buffer(geom, dist, nseg)
        shape_ = geom2shape(poly_)

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
            geom_k = shape2geom(shape_k)
            poly_k = ArchGDAL.buffer(geom_k, dist, nseg)
            shape_k_ = geom2shape(poly_k)
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
function shapeBuffer(shape::PointShape, dist=0.1)::PolyShape
    numElementos = shape.NumPoints
    VV = Array{Array{Float64,2},1}(undef, numElementos)
    for i = 1:numElementos
        point_i = PointShape(shape.Vertices[i, :]', 1)
        geom = polyShape.shape2geom(point_i)
        poly_ = ArchGDAL.buffer(geom, dist, 3)
        shape_ = polyShape.geom2shape(poly_)
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
    geom_point = ArchGDAL.centroid(shape2geom(shape))
    out = geom2shape(geom_point)
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
        shape_i = subShape(shape, i)
        cent_i = shapeCentroid(shape_i)
        V[i, :] = cent_i.Vertices
    end
    out = PointShape(V, numElements)
    return out
end


function shapeDistance(shape1::PosDimGeom, shape2::PosDimGeom)::Float64
    geom1 = shape2geom(shape1)
    geom2 = shape2geom(shape2)
    dist = ArchGDAL.distance(geom1, geom2)
    return dist
end
function shapeDistance(shape1::PointShape, shape2::PointShape)::Float64
    dist = sqrt(sum((shape1.Vertices[1, :] .- shape2.Vertices[1, :]) .^ 2))
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
        shape_i = subShape(shape1, i)
        for j = 1:numElements2
            shape_j = subShape(shape2, j)
            distMat[i, j] = shapeDistance(shape_i, shape_j)
        end
    end
    return distMat
end



function astext2polyshape(str)::PolyShape
    if isa(str, Array)
        largo = length(str)
        ps_out = PolyShape([], 0)
        V = []
        for i = 1:largo
            shape_i = geom2shape(ArchGDAL.fromWKT(str[i]))
            V_ = shape_i.Vertices[1]
            push!(V, V_[1:end-1, :])
        end
        ps_out = PolyShape(V, length(V))
    else
        shape = geom2shape(ArchGDAL.fromWKT(str))
        V_ = shape.Vertices[1]
        V = V_[1:end-1, :]
        ps_out = PolyShape([V], 1)
    end

    return ps_out
end


function astext2lineshape(str::String)::LineShape
    shape = geom2shape(ArchGDAL.fromWKT(str))
    V = shape.Vertices[1]
    ls_out = LineShape([V], 1)
    return ls_out
end
function astext2lineshape(str_array::Array)::LineShape
    numLines = length(str_array)
    geom_ls = ArchGDAL.createmultilinestring()
    for i = 1:numLines
        str_i = str_array[i]
        ls_i = astext2lineshape(str_i)
        V_i = ls_i.Vertices[1]
        geom_i = shape2geom(LineShape([V_i], 1))
        geom_ls = ArchGDAL.union(geom_ls, geom_i)

    end
    ls_out = geom2shape(geom_ls)
    return ls_out
end

########################################################################
########################################################################
########################################################################



########################################################################
#              Funciones en base a Devices - Clipper                   #
########################################################################

function clipper2polyshape(poly)::PolyShape
    numRegiones = length(poly)
    ps_out = PolyShape([], numRegiones)

    for k = 1:numRegiones
        poly_k = poly[k].p
        numVertices_k = length(poly_k)
        V_k = fill(0.0, numVertices_k, 2)
        for i = 1:numVertices_k
            V_k[i, 1] = poly_k[i][1]
            V_k[i, 2] = poly_k[i][2]
        end
        ps_out.Vertices = push!(ps_out.Vertices, V_k)
    end
    ps_out.NumRegions = length(ps_out.Vertices)
    return ps_out
end


function polyshape2clipper(ps::PolyShape)
    n = ps.NumRegions
    poly_out = Array{Devices.Polygon{Float64},1}()
    for k = 1:n
        V_k = ps.Vertices[k]
        largo_k = size(V_k, 1)
        poly_k = Devices.Polygon([Devices.Point(V_k[i, 1], V_k[i, 2]) for i = 1:largo_k])
        push!(poly_out, poly_k)
    end
    return poly_out
end


function polyUnion(ps_s::PolyShape, ps_c::PolyShape)::PolyShape
    poly_s = polyshape2clipper(ps_s)
    poly_c = polyshape2clipper(ps_c)
    poly_ = Devices.Polygons.clip(Clipper.ClipTypeUnion, poly_s, poly_c)
    ps_out = clipper2polyshape(poly_)

    return ps_out
end
function polyUnion(ps::PolyShape)::PolyShape
    ps_out = polyShape.polyCopy(ps)
    numRegiones = ps.NumRegions
    VV = Array{Array{Float64,2},1}(undef, numRegiones)
    ps_ = polyShape.subShape(ps, 1)
    largo_salida = 0
    largo_vv = 0
    for i = 1:numRegiones
        area_ = polyShape.polyArea(ps_)
        ps_i = polyShape.subShape(ps, i)
        area_i = polyShape.polyArea(ps_i)
        ps_union_i = polyShape.polyUnion(ps_, ps_i)
        if ps_union_i.NumRegions > numRegiones # Mala solucion -> arreglar
            ps_union_i = PolyShape(ps_union_i.Vertices[1:numRegiones], numRegiones)
        end
        area_union_i = polyShape.polyArea(ps_union_i)
        if area_union_i - (area_ + area_i) < 5
            for l = 1:length(ps_union_i.Vertices)
                VV[l] = ps_union_i.Vertices[l]
            end
            ps_ = polyShape.polyCopy(ps_union_i)
            largo_vv = length(ps_.Vertices)

        else
            VV[largo_vv+1] = ps_i.Vertices[1]
            ps_ = PolyShape(VV[1:largo_vv+1], largo_vv + 1)
            largo_vv = length(ps_.Vertices)
        end
        largo_salida = largo_vv
    end
    ps_out = PolyShape(VV[1:largo_salida], largo_salida)
    return ps_out
end


function polyDifference(ps_s::PolyShape, ps_c::PolyShape)::PolyShape
    poly_s = polyshape2clipper(ps_s)
    poly_c = polyshape2clipper(ps_c)
    poly_ = Devices.Polygons.clip(Clipper.ClipTypeDifference, poly_s, poly_c)
    ps_out = clipper2polyshape(poly_)

    return ps_out
end


function polyIntersect(ps_s::PolyShape, ps_c::PolyShape)::PolyShape
    n_s = ps_s.NumRegions
    n_c = ps_c.NumRegions
    VV = []
    cont = 0
    for i = 1:n_s
        poly_s_i = polyShape.polyshape2clipper(polyShape.subShape(ps_s, i))
        for j = 1:n_c
            poly_c_j = polyShape.polyshape2clipper(polyShape.subShape(ps_c, j))
            poly_ij = Devices.Polygons.clip(Clipper.ClipTypeIntersection, poly_s_i, poly_c_j)
            ps_ij = polyShape.clipper2polyshape(poly_ij)
            if polyShape.polyArea(ps_ij) >= 0.01
                n_ij = ps_ij.NumRegions
                for k = 1:n_ij
                    cont += 1
                    VV = push!(VV, ps_ij.Vertices[k])
                end
            end
        end
    end
    ps_out = PolyShape(VV[1:cont], cont)
    #ps_out = polyShape.polyUnion(ps_out)
    return ps_out
end


# expande todos los lados en la misma distancia
function polyExpand(ps::PolyShape, dist::Union{Real,Array{Real,1}})::PolyShape
    poly = polyShape.polyshape2clipper(ps)
    poly_ = Devices.Polygons.offset(poly, dist, j=Clipper.JoinTypeMiter, e=Clipper.EndTypeClosedPolygon)
    ps_out = polyShape.clipper2polyshape(poly_)
    num_regions = length(poly_)
    if num_regions == 1
        V = ps.Vertices[1]
        V_out = ps_out.Vertices[1]
        vec_dist_primer = (V_out[:, 1] .- V[1, 1]) .^ 2 .+ (V_out[:, 2] .- V[1, 2]) .^ 2
        pos_min = argmin(vec_dist_primer)
        V_out = [V_out[pos_min:end, :]; V_out[1:pos_min-1, :]]
        ps_out = PolyShape([V_out], 1)
    end
    return ps_out
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

########################################################################
########################################################################
########################################################################



########################################################################
#            Funciones Varias                                          #
########################################################################



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


# Extrae características de un polígono (PolyShape): Largo de lados, Angulos exteriores, Angulos interiores, Largo de diagonales
function extraeInfoPoly(ps::PolyShape)
    V = ps.Vertices[1]
    numLados = size(V, 1)

    vecLargoLados = fill(0.0, numLados)
    vecAnguloExt = fill(0.0, numLados)
    VecAnguloInt = fill(0.0, numLados)
    for i = 1:numLados
        if i == 1
            point_1 = V[numLados, :]
            point_2 = V[1, :]
            point_3 = V[2, :]
        elseif i == numLados
            point_1 = V[numLados-1, :]
            point_2 = V[numLados, :]
            point_3 = V[1, :]
        else
            point_1 = V[i-1, :]
            point_2 = V[i, :]
            point_3 = V[i+1, :]
        end
        vecLargoLados[i] = sqrt(sum((point_3 - point_2) .^ 2))
        tramo1 = point_1 - point_2
        tramo2 = point_3 - point_2
        acos_val = sum(tramo1 .* tramo2) / sqrt(sum(tramo1 .* tramo1)) / sqrt(sum(tramo2 .* tramo2))
        VecAnguloInt[i] = abs(acos_val) > 1 ? acos(sign(acos_val)) : acos(acos_val)
    end

    vecAnguloExt = polyShape.lineAngle(ps)

    matLargoDiag = fill(0.0, numLados, numLados)
    for i = 1:numLados
        for j = 1:numLados
            if i != j
                point_1 = V[i, :]
                point_2 = V[j, :]
                matLargoDiag[i, j] = sqrt(sum((point_2 - point_1) .^ 2))
            end

        end
    end

    return vecLargoLados[:, 1], vecAnguloExt[:, 1], VecAnguloInt[:, 1], matLargoDiag

end


function largoLadosPoly(ps::PolyShape)::Array{Float64,1}
    V = ps.Vertices[1]
    numLados = size(V, 1)

    vecLargoLados = fill(0.0, numLados)
    for i = 1:numLados
        if i == 1
            point_1 = V[numLados, :]
            point_2 = V[1, :]
            point_3 = V[2, :]
        elseif i == numLados
            point_1 = V[numLados-1, :]
            point_2 = V[numLados, :]
            point_3 = V[1, :]
        else
            point_1 = V[i-1, :]
            point_2 = V[i, :]
            point_3 = V[i+1, :]
        end
        vecLargoLados[i, 1] = sqrt(sum((point_3 - point_2) .^ 2))
    end
    return vecLargoLados[:, 1]
end


function isPolyConvex(ps::PolyShape)::Bool
    # Given a set of points determine if they form a convex polygon
    numRegiones = ps.NumRegions
    isConvexVec = fill(false, numRegiones)
    for j = 1:numRegiones
        V_j = ps.Vertices[j]
        isConvexVec[j] = poly2D.checkConvex(V_j)
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



function polyBox(pos_x::Real, pos_y::Real, dx::Float64, dy::Float64=dx, angulo::Float64=0.0, cr=[pos_x; pos_y])::PolyShape
    V = [pos_x pos_y; pos_x+dx pos_y; pos_x+dx pos_y+dy; pos_x pos_y+dy]
    ps = PolyShape([V], 1)
    ps_out = polyShape.polyRotate(ps, angulo, cr)
    return ps_out
end
function polyBox(p::PointShape, dx::Float64, dy::Float64=dx, angulo::Float64=0.0)::PolyShape
    pos_x = p.Vertices[1, 1]
    pos_y = p.Vertices[1, 2]
    cr = [pos_x; pos_y]
    ps_out = polyShape.polyBox(pos_x, pos_y, dx, dy, angulo, cr)
    return ps_out
end


function polyRotate(ps::PolyShape, angulo::Float64, cr)::PolyShape
    R = poly2D.rotationMatrix(angulo)
    V = ps.Vertices[1]
    numVertices = size(V, 1)
    V_aux = [vec(R * (V[i, 1:2] - cr) + cr) for i in 1:numVertices]
    V_rot = mapreduce(permutedims, vcat, V_aux)
    ps_rot = PolyShape([V_rot], 1)
    return ps_rot
end



function polyArea(ps::PolyShape; sep_flag::Bool=false)::Union{Float64,Array{Float64,1}}
    numRegions = ps.NumRegions
    if numRegions >= 1
        vecArea = [poly2D.polyArea(ps.Vertices[i]) for i = 1:numRegions]
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


function polyDifference_v2(ps1::PolyShape, ps2::PolyShape)::PolyShape

    # Revisa si ciertas regiones están contenidas en otras. En caso de estarlo se aplica diferenciación especial

    numRegions1 = ps1.NumRegions
    numRegions2 = ps2.NumRegions
    Vout_vec = Array{Array{Float64,2},1}(undef, numRegions1)
    for i = 1:numRegions1
        ps1_i = polyShape.subShape(ps1, i)
        Vout_vec[i] = ps1_i.Vertices[1]
        for j = 1:numRegions2
            V1_i = copy(Vout_vec[i])
            ps2_j = polyShape.subShape(ps2, j)
            flag_ij = polyShape.shapeContains(ps1_i, ps2_j)
            if flag_ij #ps1_i contiene a ps2_j
                dist_min, id1_min, id2_min = polyShape.minPolyDistance(ps1_i, ps2_j)
                V2_j = ps2_j.Vertices[1]
                V2_j_ = [V2_j[id2_min:-1:1, :]; V2_j[end:-1:id2_min, :]]
                Vout_vec[i] = [V1_i[1:id1_min, :]; V2_j_; V1_i[id1_min:end, :]]
            end

        end
    end

    ps1_ = PolyShape(Vout_vec, numRegions1)

    ps_out = polyShape.polyDifference(ps1_, ps2)

    return ps_out
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


function polyUnique(ps_::PolyShape)::PolyShape
    ps = polyCopy(ps_)
    numRegions = ps.NumRegions
    V = copy(ps.Vertices)
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
    V_out = []
    for i = 1:numRegions
        if size(V[i], 1) >= 2
            V_out = push!(V_out, V[i])
        end
    end
    ps_out = PolyShape(V_out, length(V_out))
    return ps_out
end


function polyEliminateWithin(ps_::PolyShape)::PolyShape
    ps = polyShape.polyCopy(ps_)
    numRegions = ps.NumRegions
    V = copy(ps.Vertices)
    for i in 1:numRegions
        ps_i = polyShape.subShape(ps, i)
        for j in setdiff(1:numRegions, i)
            ps_j = polyShape.subShape(ps, j)
            if polyShape.shapeContains(ps_i, ps_j)
                V[j] = [0.0 0.0]
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


function pointLineDist(l::LineShape, p::PointShape)::Float64
    # Obtiene la distacia entre un punto a una línea
    V_line = l.Vertices[1]
    V_point = p.Vertices
    dist = poly2D.distPointLine(V_point[:], V_line[1, :], V_line[2, :])
    return dist
end


function halfspaceSignOfPointToLine(l::LineShape, p::PointShape)::Int64
    # Obtiene el signo del subespacio donde se encuentra el punto respecto a la línea
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



function lineLineDist(l1::LineShape, l2::LineShape)::Float64
    # Distance of line l2 to line l1
    V1 = l1.Vertices[1]
    q = l2.Vertices[1][1, :] * 0.5 + l2.Vertices[1][2, :] * 0.5
    p = PointShape([q[1] q[2]], 1)
    d = poly2D.distPointLine(q, V1[1, :], V1[2, :])
    s = halfspaceSignOfPointToLine(l1, p)
    return s * d
end



function parallelLineAtDist(l::LineShape, d::Real)::LineShape
    V = l.Vertices[1]
    line = poly2D.createLine(V[1, :], V[2, :])
    vec_out = poly2D.parallelLine(line, d)
    x1 = vec_out[1]
    y1 = vec_out[2]
    x2 = vec_out[1] + vec_out[3]
    y2 = vec_out[2] + vec_out[4]
    l_out = LineShape([[x1 y1; x2 y2]], 1)

    return l_out
end



function intersectLines(l1::LineShape, l2::LineShape)::PointShape
    V_line1 = l1.Vertices[1]
    V_line2 = l2.Vertices[1]
    edge1 = [V_line1[1, :]' V_line1[2, :]']
    edge2 = [V_line2[1, :]' V_line2[2, :]']
    vec_point = poly2D.intersectEdges(edge1, edge2)
    p = PointShape(vec_point, 1)
    return p
end


function extendLine(l::LineShape, d::Real)::LineShape
    # Extiende ambas puntas del segmento l en una distancia d
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
    l_out = LineShape([V_], 1)
    return l_out

end


function findPolyIntersection(ps1::PolyShape, ps2::PolyShape)
    V1 = ps1.Vertices[1]
    V2 = ps2.Vertices[1]
    res = poly2D.intersectPoly2d(V1, V2)
    edges1 = res[:, 1]
    edges2 = res[:, 2]
    p = PointShape(res[:, 3:4], length(edges1))
    return edges1, edges2, p
end


function pointDistanceMat(p1::PointShape, p2::PointShape)::Array{Float64,2}
    distMat = distanceMat(p1.Vertices, p2.Vertices)
    return distMat
end


function polyEliminaRepetidos(ps::PolyShape, tol::Float64=0.1)::PolyShape
    ps_ = polyShape.polyCopy(ps)
    numVertices_ = size(ps_.Vertices[1], 1)
    vec_flag_ = fill(1, numVertices_)
    points_ = polyShape.shapeVertex(ps_)
    for i = 1:numVertices_
        if i == numVertices_
            ip = 1
        else
            ip = i + 1
        end
        p = polyShape.subShape(points_, i)
        p_p = polyShape.subShape(points_, ip)
        dist = polyShape.shapeDistance(p, p_p)
        if dist <= tol
            vec_flag_[i] = 0
        end
    end
    V_ = copy(ps_.Vertices[1][vec_flag_.==1, :])
    ps_out = PolyShape([V_], 1)

    return ps_out
end


function createLine(point1::PointShape, point2::PointShape)::LineShape
    v_1 = point1.Vertices[:]'
    v_2 = point2.Vertices[:]'
    V = [v_1; v_2]
    l_out = LineShape([V], 1)
    return l_out
end



function polyEliminaColineales(ps::PolyShape, tol::Float64=0.001, topoFlag::Bool=false)::PolyShape
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



function polyEliminaSpikes(ps::PolyShape)::PolyShape

    area_ps = polyShape.polyArea(ps)
    V = copy(ps.Vertices[1])
    numPoints = size(V, 1)

    V_ = copy(ps.Vertices[1])

    for i = 1:numPoints
        V_i = V_[setdiff(1:numPoints, i), :]
        area_psi = polyShape.polyArea(PolyShape([V_i], 1))

        if abs(area_ps - area_psi) / area_ps <= 0.001
            if i == 1
                V_[1, :] = 0.99 * V[numPoints, :] + 0.01 * V_[1, :]
            else
                V_[i, :] = 0.99 * V[i-1, :] + 0.01 * V_[i, :]
            end
        end
    end

    ps_out = PolyShape([V_], 1)

    return ps_out


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
                x_ij = polyShape.shapeIntersect(li, lj)
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


function polyEliminaCrucesComplejos(ps::PolyShape)::PolyShape

    cond = true
    V = copy(ps.Vertices[1])
    N = size(V, 1)

    ps_ = polyShape.polyCopy(ps)

    V_ = copy(ps_.Vertices[1])

    # Obtiene los puntos de cruce y los guarda en mat_x
    mat_x, V_x = polyShape.polyObtieneCruces(ps_)


    num_cruces = size(mat_x, 1)

    V_a = copy(ps_.Vertices[1])
    V_b = copy(ps_.Vertices[1])
    vvv = vcat(1:N, 1:N)

    k = 0
    while cond
        k += 1
        if k <= num_cruces
            l1_ini = mat_x[k, 1]
            if l1_ini <= N - 1
                l1_fin = l1_ini + 1
            else
                l1_fin = 1
            end
            l2_ini = mat_x[k, 2]
            if l2_ini <= N - 1
                l2_fin = l2_ini + 1
            else
                l2_fin = 1
            end

            dist_l2_l1 = l2_ini - l1_ini > 0 ? l2_ini - l1_ini : N - l1_ini + l2_ini

            set_a = vvv[findall(x -> (x >= l2_ini && x <= l2_ini + N - dist_l2_l1), 1:N*2)][2:end-1]
            V_a[l1_ini, :] = V_x[1, :]' * 0.999 + V[l1_fin, :]' * 0.001
            V_a[l2_fin, :] = V_x[1, :]' * 0.999 + V[l2_ini, :]' * 0.001
            V_a[set_a, :] = length(set_a) > 1 ? repeat(V_x[1, :]', length(set_a), 1) : V_x[1, :]'

            set_b = vvv[findall(x -> (x >= l1_ini && x <= l1_ini + dist_l2_l1), 1:N*2)][2:end-1]
            V_b[l1_fin, :] = V_x[1, :]' * 0.999 + V[l1_ini, :]' * 0.001
            V_b[l2_ini, :] = V_x[1, :]' * 0.999 + V[l2_fin, :]' * 0.001
            V_b[set_b, :] = length(set_b) > 1 ? repeat(V_x[1, :]', length(set_b), 1) : V_x[1, :]'

            areaInteseccion_a = polyShape.polyArea(polyShape.polyIntersect(polyShape.PolyShape([V_a], 1), ps))
            areaInteseccion_b = polyShape.polyArea(polyShape.polyIntersect(polyShape.PolyShape([V_b], 1), ps))

            if areaInteseccion_a > areaInteseccion_b
                V_ = copy(V_a)
                ps_ = polyShape.polyEliminaSpikes(PolyShape([V_], 1))
                cond = false
            else
                V_ = copy(V_b)
                ps_ = polyShape.polyEliminaSpikes(PolyShape([V_], 1))
                cond = false
            end
        else
            cond = false
        end
        ps_ = polyShape.polyEliminaSpikes(PolyShape([V_], 1))
    end

    return ps_

end


function polySimplify(ps::PolyShape)::PolyShape

    numRegiones = ps.NumRegions

    VV = Array{Array{Float64,2},1}(undef, numRegiones)
    for i = 1:numRegiones
        ps_i = polyShape.subShape(ps, i)

        # Elimina spikes
        ps_i = polyShape.polyEliminaSpikes(ps_i)

        # Elimina cruces que forman poligonos complejos
        ps_i = polyShape.polyEliminaCrucesComplejos(ps_i)
        V_i = copy(ps_i.Vertices[1])

        VV[i] = V_i

    end

    ps_out = PolyShape(VV, numRegiones)

    return ps_out
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

function ajustaCoordenadas(ps::PolyShape, dx::Float64, dy::Float64)
    numRegions = ps.NumRegions
    for i = 1:numRegions
        ps.Vertices[i][:, 1] = ps.Vertices[i][:, 1] .- dx
        ps.Vertices[i][:, 2] = ps.Vertices[i][:, 2] .- dy
    end
    return ps
end

function ajustaCoordenadas(ls::LineShape, dx::Float64, dy::Float64)
    numLines = ls.NumLines
    for i = 1:numLines
        ls.Vertices[i][:, 1] = ls.Vertices[i][:, 1] .- dx
        ls.Vertices[i][:, 2] = ls.Vertices[i][:, 2] .- dy
    end
    return ls
end




########################################################################
########################################################################
########################################################################


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
        dist_1 = polyShape.pointLineDist(edge, point_1)
        point_2 = polyShape.subShape(p_inter, 2)
        dist_2 = polyShape.pointLineDist(edge, point_2)
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


function lineVec2polyShape(lineVec::Array{LineShape,1})::PolyShape
    N = length(lineVec)
    V = fill(0.0, N, 2)
    for i = 1:N
        ix_1 = i
        if i == N
            ix_2 = 1
        else
            ix_2 = i + 1
        end
        l_1 = lineVec[ix_1]
        l_2 = lineVec[ix_2]
        point_x_12 = polyShape.shapeIntersect(l_1, l_2)
        if size(point_x_12.Vertices[1], 1) >= 1
            V[ix_2, :] = point_x_12.Vertices[1, :]'
        else
            V[ix_2, :] = V[ix_1, :]
        end

    end
    ps_out = PolyShape([V], 1)

    return ps_out
end



function polyShape2lineVec(ps::PolyShape)::Array{LineShape,1}
    V = copy(ps.Vertices[1])
    N = size(V, 1)

    # Obtiene vector de bordes del polígono original
    line_vec = Array{LineShape,1}()
    for i in 1:N
        if i < N
            l_i = LineShape([[V[i, :]'; V[i+1, :]']], 1)
        else
            l_i = LineShape([[V[i, :]'; V[1, :]']], 1)
        end
        line_vec = push!(line_vec, l_i)
    end

    return line_vec
end



function polyExpandSegmentVec(ps::PolyShape, distVec::Array{Float64,1}, sVec::Array{Int64,1})::PolyShape

    line_vec = polyShape.polyShape2lineVec(ps)
    N = length(line_vec)

    # Obtiene vector de bordes del polígono expandido
    line_vec_exp = Array{LineShape,1}()
    for i in 1:N
        line_vec_i = line_vec[i]
        V_i = line_vec_i.Vertices[1]
        line_i_length = sqrt((V_i[1, 1] - V_i[2, 1])^2 + (V_i[1, 2] - V_i[2, 2])^2)

        if i in sVec
            pos_i = findfirst(id -> id == i, sVec)
            l_exp_i = polyShape.extendLine(polyShape.parallelLineAtDist(line_vec_i, distVec[pos_i]), max(30, 4 * line_i_length))
        else
            l_exp_i = polyShape.extendLine(line_vec_i, max(30, 4 * line_i_length))
        end

        line_vec_exp = push!(line_vec_exp, l_exp_i)
    end

    # Establece el polígono de chequeo 
    ps_aux = polyShape.lineVec2polyShape(line_vec_exp)
    if polyShape.polyArea(ps) >= polyShape.polyArea(ps_aux)
        ps_cheq_ = polyShape.polyCopy(ps)
    else
        ps_cheq_ = polyShape.polyCopy(ps_aux)
    end
    ps_cheq = polyShape.polyExpand(ps_cheq_, 1.0)

    # Encuentra los vértices de intersección
    point_vec_x = Array{PointShape,1}()
    for i = 1:N

        condInter = true
        ix = i
        cont = 0
        while condInter
            cont += 1
            if ix == N
                ix = 1
            else
                ix += 1
            end
            point_x_i = polyShape.shapeIntersect(line_vec_exp[i], line_vec_exp[ix])
            flag_in_poly = polyShape.shapeContains(ps_cheq, point_x_i)
            if flag_in_poly || cont == N
                condInter = false
                if typeof(point_x_i) == PointShape
                    point_vec_x = push!(point_vec_x, point_x_i)
                end
            end
        end
    end

    V_out = fill(0.0, N, 2)
    for i = 1:N
        if i > 1
            V_out[i, :] = point_vec_x[i-1].Vertices
        else
            V_out[i, :] = point_vec_x[end].Vertices
        end
    end

    ps_out = PolyShape([V_out], 1)

    return ps_out
end


# expande todos los lados en la misma distancia
function polyEqualExpand(ps::PolyShape, dist::Union{Real,Array{Real,1}})::PolyShape

    if dist > 0
        V = ps.Vertices[1]
        N = size(V, 1)
        V_ = copy(V)
        line_vec = Array{LineShape,1}()
        for i = 1:N
            if i < N
                l_i = LineShape([[V_[i, :]'; V_[i+1, :]']], 1)
            else
                l_i = LineShape([[V_[i, :]'; V_[1, :]']], 1)
            end
            line_vec = push!(line_vec, l_i)
        end

        line_vec_exp = Array{LineShape,1}()
        for i = 1:N
            line_vec_i = line_vec[i]
            V_i = line_vec_i.Vertices[1]
            line_i_length = sqrt((V_i[1, 1] - V_i[2, 1])^2 + (V_i[1, 2] - V_i[2, 2])^2)
            l_exp_i = extendLine(parallelLineAtDist(line_vec_i, dist), 4 * line_i_length)
            line_vec_exp = push!(line_vec_exp, l_exp_i)
        end

        point_vec_x = Array{PointShape,1}()
        for i = 1:N
            if i < N
                point_x_i = shapeIntersect(line_vec_exp[i], line_vec_exp[i+1])
            else
                point_x_i = shapeIntersect(line_vec_exp[i], line_vec_exp[1])
            end
            point_vec_x = push!(point_vec_x, point_x_i)
        end

        V_out = fill(0.0, N, 2)
        for i = 1:N
            if i > 1
                V_out[i, :] = point_vec_x[i-1].Vertices
            else
                V_out[i, :] = point_vec_x[end].Vertices
            end
        end

        ps_out = PolyShape([V_out], 1)

    else
        ps_out = polyShape.polyExpand(ps, dist)
    end

    return ps_out

end


function polyReproject(ps::PolyShape, dx::Float64, dy::Float64, EPSG_in::Int64, EPSG_out::Int64)
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
        points_ = ArchGDAL.createcoordtrans(source, target) do transform
            ArchGDAL.transform!.(points, Ref(transform))
        end
        for j = 1:length(points_)
            point_j = polyShape.geom2shape(points[j])
            ps_.Vertices[i][j, :] = point_j.Vertices[1, :]
        end
    end
    poly = polyShape.shape2geom(ps_)
    return poly
end


function polyskel(ps::PolyShape)
    # Non-convex ps = PolyShape([[0 0;100 5;80 15;100 40;100 60;40 55;30 30;20 55;0 55]],1)
    # Convex ps = PolyShape([[0 0;100 0;100 40;0 40]],1)
    # Convex ps = PolyShape([[0 0;100 0;100 40;60 80;40 80;0 40]],1)
    # Convex ps = PolyShape([[10 10;100 5;110 15;110 40;95 50;60 67;30 67;20 65;0 55]],1)
    # Convex ps = PolyShape([[10 10; 30 -40; 60 -40; 100 5;110 15;110 40;95 50;60 67;30 67;20 65;0 55]],1)

    function generaBisectricesPoligono(ps)
        vertices = polyShape.shapeVertex(ps)
        numVertices = vertices.NumPoints
        edges = polyShape.polyShape2lineVec(ps)
        vec_bisectriz = []
        vec_edges_bisectriz = []
        bisec_dir = []
        for i in 1:numVertices
            id_edge_a = i > 1 ? i-1 : numVertices
            edge_a = polyShape.reverseLine(edges[id_edge_a])
            id_edge_p = i
            edge_p = edges[id_edge_p]
            push!(bisec_dir, polyShape.bisector_direction(edge_a, edge_p))    
            vertex_i = polyShape.subShape(vertices, i)
            l_i = bisec_dir[i] + vertex_i
            vertex_end_i = polyShape.shapeVertex(l_i, 1, 2)
            flag_i = polyShape.shapeContains(ps, vertex_end_i)
            if !flag_i
                dir_i = bisec_dir[i]
                bisec_dir[i] = dir_i * -1
                l_i = bisec_dir[i] + vertex_i
            end
            l_i = l_i * 100
            push!(vec_bisectriz, l_i)
            push!(vec_edges_bisectriz, [i, id_edge_a, id_edge_p, edge_a, edge_p])
        end
        return vec_bisectriz, vec_edges_bisectriz
    end

    function generaBisectrizVertice!(V_lav, vec_bisectriz, pos_id_vert, vec_edges_bisectriz)
        vec_bisectriz_ = copy(vec_bisectriz)
        id_edge_a = vec_edges_bisectriz[end][2]
        id_edge_p = vec_edges_bisectriz[end][3]
        edge_a = polyShape.reverseLine(vec_edges_bisectriz[id_edge_a][5])
        edge_p = vec_edges_bisectriz[id_edge_p][5]
        bisec_dir = polyShape.bisector_direction(edge_a, edge_p)
        vertex = PointShape(V_lav[Int(pos_id_vert),:]',1)
        b_line = bisec_dir + vertex
        b_line = b_line * 100
        push!(vec_bisectriz_, b_line) # se agrega nueva bisectriz al final del vector 
        vec_edges_bisectriz[end][4] = edge_a
        vec_edges_bisectriz[end][5] = edge_p
        vec_bisectriz_ = copy(vec_bisectriz_)
        return vec_bisectriz_, vec_edges_bisectriz
    end

    function intersectaBisectrices(vec_bisectriz, pos_ps)
        numBisectrices = length(vec_bisectriz)
        vec_interseccion = []
        for i in 1:numBisectrices
            b_1 = vec_bisectriz[i]
            p_1 = PointShape(b_1.Vertices[1][1,:]',1)
            i_a = i > 1 ? i-1 : numBisectrices
            i_p = i < numBisectrices ? i+1 : 1
            b_2a = vec_bisectriz[i_a]
            b_2p = vec_bisectriz[i_p]
            p_12a = polyShape.intersectLines(b_1, b_2a)
            p_12p = polyShape.intersectLines(b_1, b_2p)
            dist_12a = polyShape.shapeDistance(p_1,p_12a)
            dist_12a = isnan(dist_12a) ? 1000000 : dist_12a
            dist_12p = polyShape.shapeDistance(p_1,p_12p)
            dist_12p = isnan(dist_12p) ? 1000000 : dist_12p
            if min(dist_12a, dist_12p) == dist_12a
                push!(vec_interseccion, [pos_ps[i], p_12a, pos_ps[i_a], pos_ps[i]])
            else
                push!(vec_interseccion, [pos_ps[i], p_12p, pos_ps[i], pos_ps[i_p]])
            end
            
        end
        return vec_interseccion
    end

    function generaMatDist(vec_interseccion_activos, vec_edges_bisectriz, pos_ps)
        #Genera matriz de distacia pos_ps
        numIntersecciones = length(pos_ps)
        queue_dist = zeros(numIntersecciones, 4)
        for i in 1:numIntersecciones
            p_i = vec_interseccion_activos[i][2]
            edge_i_a = vec_edges_bisectriz[pos_ps[i]][4]
            queue_dist[i, 1] = pos_ps[i]
            dist_i_a = polyShape.pointLineDist(edge_i_a, p_i)
            queue_dist[i, 2] = round(dist_i_a, digits=4)
            queue_dist[i, 3] = vec_interseccion_activos[i][3]
            queue_dist[i, 4] = vec_interseccion_activos[i][4]
        end
        queue_dist = queue_dist[sortperm(queue_dist[:, 2] .+ 0.0001*queue_dist[:, 1]), :]
        return queue_dist
    end

    function polyskel_vec(V_lv, ss_list)
        num = length(ss_list)
        vec_lines = []
        for i = 1:num
            id_end = Int(ss_list[i][1])
    
            id_ini_1 = Int(ss_list[i][2])
            line_1_i = LineShape([[V_lv[id_ini_1, :]'; V_lv[id_end, :]']],1)
            push!(vec_lines, line_1_i)
    
            id_ini_2 = Int(ss_list[i][3])
            line_2_i = LineShape([[V_lv[id_ini_2, :]'; V_lv[id_end, :]']],1)
            push!(vec_lines, line_2_i)
        end
        return vec_lines
    end

    # Inicialización
    ss_list = []
    vec_edges_bisectriz = []
    ss_row = []
    vec_bisectriz = []
    vec_lines = []
    cond = true
    flag_inicio = true
    id_nuevo_vert = 0

    numVertices = size(ps.Vertices[1], 1)
    lv = hcat(1:numVertices, trues(numVertices, 1))
    lav = copy(lv)
    pos_ps = copy(lav[:, 1])
    V_lv = ps.Vertices[1]
    V_lav = copy(V_lv)
    while cond
        if flag_inicio
            vec_bisectriz, vec_edges_bisectriz = generaBisectricesPoligono(ps)
            flag_inicio = false
        else
            pos_id_vert = findall(x -> x == id_nuevo_vert, pos_ps)[1]
            id_edge_a = vec_edges_bisectriz[Int(ss_row[2])][2]
            id_edge_p = vec_edges_bisectriz[Int(ss_row[3])][3]
            push!(vec_edges_bisectriz, [id_nuevo_vert, id_edge_a, id_edge_p, [], []])
            vec_bisectriz, vec_edges_bisectriz = generaBisectrizVertice!(V_lav, vec_bisectriz, pos_id_vert, vec_edges_bisectriz)
        end
        vec_bisectriz_activos = vec_bisectriz[pos_ps]
        vec_interseccion_activos = intersectaBisectrices(vec_bisectriz_activos, pos_ps)
        queue_dist = generaMatDist(vec_interseccion_activos, vec_edges_bisectriz, pos_ps) # Matriz de intersecciones ordenada de menor a mayor distancia
        
        if size(lav,1) <= 3
            cond = false
            id_vert_1 = lav[1]
            id_vert_2 = lav[2]
            p_1 = PointShape(V_lv[id_vert_1,:]',1)
            p_1 = PointShape(V_lv[id_vert_2,:]',1)
            vert_intersec = vec_interseccion_activos[1][2].Vertices[:]
            id_nuevo_vert = size(lv, 1) + 1
            lv = vcat(lv, [id_nuevo_vert true]) # Se incluye nuevo vertice al final del listado de vertices
            # Se marca vertices asociados a la intersección mas cercana como "No Activos"
            lv[findall(x -> x in [id_vert_1, id_vert_2], lv[:, 1]), 2] .= false
            V_lv = vcat(V_lv, [vert_intersec[1] vert_intersec[2]]) # Está ordenado de menor a mayor id
            ss_row = [id_nuevo_vert; [id_vert_1, id_vert_2] ]
            push!(ss_list, ss_row)
            if size(lav,1) == 3
                id_vert_3 = lav[3]
                ss_row = [id_nuevo_vert; [id_vert_2, id_vert_3] ]
                push!(ss_list, ss_row)
            end
        else
            row = queue_dist[1, :] # Punto más cercano de intersección que se saca de la matriz de distancias
            vert_intersec = vec_interseccion_activos[findall(x -> x == Int(row[1]), pos_ps)][1][2].Vertices[:]
            id_vert_1 = row[3]
            id_vert_2 = row[4]
    
            if min(id_vert_1, id_vert_2) == id_vert_1
                min_vert, max_vert = id_vert_1, id_vert_2
            else
                min_vert, max_vert = id_vert_2, id_vert_1
            end
    
            id_nuevo_vert = size(lv, 1) + 1
            lv = vcat(lv, [id_nuevo_vert true]) # Se incluye nuevo vertice al final del listado de vertices
            # Se marca vertices asociados a la intersección mas cercana como "No Activos"
            lv[findall(x -> x in [id_vert_1, id_vert_2], lv[:, 1]), 2] .= false
    
            pos_ps[pos_ps[:] .== min_vert] = [id_nuevo_vert]
            pos_ps = filter(!=(max_vert), pos_ps)
            
            V_lv = vcat(V_lv, [vert_intersec[1] vert_intersec[2]]) # Está ordenado de menor a mayor id
            lav = lv[lv[:, 2].==1, :] # Está ordenado de menor a mayor id
            V_lav = V_lv[pos_ps,:] # Está ordenado según el polinomio
            ss_row = [id_nuevo_vert; [id_vert_1, id_vert_2] ]
            push!(ss_list, ss_row)    
        end
        vec_lines = polyskel_vec(V_lv, ss_list)

        # fig, ax, ax_mat = polyShape.plotPolyshape2D(ps, "green", 0.2)
        # fig, ax, ax_mat = polyShape.plotPolyshape2D(polyShape.polyExpand(ps, -5), "red", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
        # fig, ax, ax_mat = polyShape.plotPolyshape2D(polyShape.polyExpand(ps, -10), "red", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
        # fig, ax, ax_mat = polyShape.plotPolyshape2D(polyShape.polyExpand(ps, -15), "red", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
        # fig, ax, ax_mat = polyShape.plotPolyshape2D(polyShape.polyExpand(ps, -20), "red", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
        # fig, ax, ax_mat = polyShape.plotPolyshape2D(polyShape.polyExpand(ps, -21), "red", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
        # fig, ax, ax_mat = polyShape.plotPolyshape2D(polyShape.polyExpand(ps, -22), "red", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
        # fig, ax, ax_mat = polyShape.plotPolyshape2D(polyShape.polyExpand(ps, -23), "red", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
        # fig, ax, ax_mat = polyShape.plotPolyshape2D(polyShape.polyExpand(ps, -24), "red", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
        # fig, ax, ax_mat = polyShape.plotPolyshape2D(polyShape.polyExpand(ps, -25), "red", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
        # fig, ax, ax_mat = polyShape.plotPolyshape2D(polyShape.polyExpand(ps, -26), "red", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
        # fig, ax, ax_mat = polyShape.plotPolyshape2D(polyShape.polyExpand(ps, -27), "red", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
        # fig, ax, ax_mat = polyShape.plotPolyshape2D(polyShape.polyExpand(ps, -28), "red", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
        # fig, ax, ax_mat = polyShape.plotPolyshape2D(polyShape.polyExpand(ps, -29), "red", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
        # fig, ax, ax_mat = polyShape.plotPolyshape2D.(vec_lines, "red", 0.5, line_width = 0.1, fig=fig, ax=ax, ax_mat=ax_mat)  

    end

    return ss_list, vec_lines
end


function reverseLine(ls::LineShape)::LineShape
    numLines = ls.NumLines
    V = ls.Vertices
    V_ = deepcopy(V)
    for i = 1:numLines
        V_[i][1, :] = copy(V[i][2, :])
        V_[i][2, :] = copy(V[i][1, :])
    end
    ls_out = LineShape(V_, numLines)
    return ls_out
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


function distanceBetweenPoints(p1::PointShape, p2::PointShape)::Float64
    V1 = p1.Vertices[1, :]
    V2 = p2.Vertices[1, :]
    dist = sqrt(sum((V1 - V2) .^ 2))
    return dist
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
        V_out[i, :] = 0.5 * V_i[1,:] + 0.5 * V_i[2,:]
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
    ps = PolyShape([V],1)
    return ps
end

function lineLength(l::LineShape)
    numLines = l.NumLines
    len = []
    for i = 1:numLines
        p1_i = polyShape.shapeVertex(l, i, 1)
        p2_i = polyShape.shapeVertex(l, i, 2)
        d_12_i = polyShape.distanceBetweenPoints(p1_i, p2_i)
        
        if numLines > 1
            push!(len, d_12_i)
        else
            len = d_12_i
        end
    end
    return len
end


########################################################################
########################################################################
########################################################################


export extraeInfoPoly, largoLadosPoly, isPolyConvex, isPolyInPoly, plotPolyshape2D, plotPolyshape2Din3D, plotPolyshape2DVecin3D,
    polyArea, polyDifference, polyDifference_v2, plotFig, plotScatter3d, polyShape2constraints, polyOrientation, polyUnion, shapeBuffer,
    polyIntersect, polyExpand, plotPolyshape3D,
    polyshape2clipper, clipper2polyshape, shape2geom, geom2shape, astext2polyshape, polyEliminaColineales,
    astext2lineshape, shapeContains, shapeArea, shapeDifference, shapeIntersect, shapeUnion, shapeHull, shapeSimplify, shapeSimplifyTopology, subShape,
    shapeVertex, numVertices, shapeCentroid, partialCentroid, shapeDistance, partialDistance, polyBox, polyRotate, polyReverse, setPolyOrientation,
    minPolyDistance, polyCopy, polyUnique, polyEliminateWithin, pointLineDist, intersectLines, findPolyIntersection, pointDistanceMat, polySimplify,
    lineLineDist, parallelLineAtDist, lineAngle, halfspaceSignOfPointToLine, extendLine, polyEliminaRepetidos, polyEliminaSpikes, polyEliminaCrucesComplejos,
    polyObtieneCruces, polyEqualExpand, polyExpandSegmentVec, replaceShapeVertex, lineVec2polyShape, polyShape2lineVec,
    ajustaCoordenadas, angleMaxDistRect, extendRectToIntersection, createLine, polyReproject, polyskel, bisector_direction, angleBetweenLines,
    reverseLine, distanceBetweenPoints, midPointSegment, points2Line, points2Poly, lineLength

end


