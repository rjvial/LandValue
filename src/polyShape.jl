module polyShape

using LandValue, ..poly2D, Clipper, ArchGDAL, PyCall, PyPlot, Images, ImageBinarization, DataFrames



########################################################################
#              Funciones para efectuar Plot                            #
########################################################################


# Grafica polyshape en 2D.
function plotPolyshape2D(ps::PolyShape, color::String="red", alpha::Real=1.0; fig::Union{Nothing,PyPlot.Figure}=nothing, ax=nothing, ax_mat=nothing, line_width::Real=0.5, line_end::Int64=3)
    plt = PyCall.pyimport("matplotlib.pyplot")
    PathPatch = PyCall.pyimport("matplotlib.patches").PathPatch

    function patchify(ps)
        Path = PyCall.pyimport("matplotlib.path").Path

        function ring_coding(n)
            c = fill(Path.LINETO, n)
            c[1] = Path.MOVETO
            c[end] = Path.CLOSEPOLY
            return c
        end

        num_regions = ps.NumRegions
        codes = [0]
        vertices = [0 0]
        for i in 1:num_regions
            n_i = size(ps.Vertices[i], 1) + 1
            code_i = ring_coding(n_i)
            codes = vcat(codes, code_i)
            vertices = vcat(vertices, ps.Vertices[i], ps.Vertices[i][1,:]') 
        end
        codes = codes[2:end]
        vertices = vertices[2:end, :]
        path = Path(vertices, codes)

        return path
    end

    numSectors = ps.NumRegions

    min_ax, max_ax = ax_mat === nothing ? (0, 0) : (ax_mat[1], ax_mat[2])
    flag = fig === nothing ? false : true
    for i = 1:numSectors
        V_i = ps.Vertices[i]
        if ~flag
            min_ax = minimum([minimum(V_i[:, 1]) minimum(V_i[:, 2])])
            max_ax = maximum([maximum(V_i[:, 1]) maximum(V_i[:, 2])])
            flag = true
        else
            min_ax = minimum([min_ax minimum(V_i[:, 1]) minimum(V_i[:, 2])])
            max_ax = maximum([max_ax maximum(V_i[:, 1]) maximum(V_i[:, 2])])
        end
    end

    if fig === nothing
        PyCall.pygui(true)
        fig = plt.figure()
        ax = fig.add_subplot(1, 1, 1)
    end

    path = patchify(ps)
    polygon = PathPatch(path, color=color, alpha=alpha)

    ax.add_patch(polygon)

    ax.set_xlim(min_ax, max_ax)
    ax.set_ylim(min_ax, max_ax)
    ax.set_aspect("equal")
    ax.grid("on")

    ax_mat = [min_ax max_ax]

    return fig, ax, ax_mat

end
function plotPolyshape2D(ps::Union{PointShape,LineShape}, color::String="red", alpha::Real=1.0; fig::Union{Nothing,PyPlot.Figure}=nothing, ax=nothing, ax_mat=nothing, line_width::Real=0.5, line_end::Int64=3)

    if ps isa PointShape
        numSectors = ps.NumPoints
        point_width = 0.5
        ps = polyShape.shapeBuffer(ps, point_width)
    elseif ps isa LineShape
        numSectors = ps.NumLines
        ps = polyShape.shapeBuffer(ps, line_width, line_end)
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

        polygon = patch.Polygon(V_i, closed=true, color=color, alpha=alpha)

        ax.add_patch(polygon)

    end

    ax_mat = [min_ax max_ax]

    return fig, ax, ax_mat

end


# Grafica múltiples polyshape 2D en espacio 3D a distintas alturas.
function plotPolyshape2DVecin3D(vec_ps::Array{polyShape.LineShape,1}, vec_h::Vector{Float64}, fc::String="red", a::Real=0.1; fig::Union{Nothing,PyPlot.Figure}=nothing, ax=nothing, ax_mat=nothing, line_width::Real=0.5, line_end::Int64=3)
    fig_ = []
    ax_ = []
    ax_mat_ = []
    for i in eachindex(vec_h)
        ps_i = vec_ps[i]
        h_i = vec_h[i]
        if i == 1
            fig_, ax_, ax_mat_ = plotPolyshape2Din3D(ps_i, h_i, fc, a, fig=fig, ax=ax, ax_mat=ax_mat, line_width=line_width, line_end=line_end)
        end
        fig_, ax_, ax_mat_ = plotPolyshape2Din3D(ps_i, h_i, fc, a, fig=fig_, ax=ax_, ax_mat=ax_mat_, line_width=line_width, line_end=line_end)
    end
    return fig_, ax_, ax_mat_
end


# Grafica polyshape 2D en espacio 3D a una altura height.
function plotPolyshape2Din3D(ps::PointShape, height::Real=0.0, fc::String="blue", a::Real=0.25; fig::Union{Nothing,PyPlot.Figure}=nothing, ax=nothing, ax_mat=nothing, line_width::Real=0.5, filestr="none")
    ps = polyShape.shapeBuffer(ps, line_width)
    fig, ax, ax_mat = plotPolyshape2Din3D(ps, height, fc, a; fig=fig, ax=ax, ax_mat=ax_mat)
end
function plotPolyshape2Din3D(ls::LineShape, height::Real=0.0, fc::String="blue", a::Real=0.25; fig::Union{Nothing,PyPlot.Figure}=nothing, ax=nothing, ax_mat=nothing, line_width::Real=0.5, line_end::Int64=3, filestr="none")
    ps = polyShape.shapeBuffer(ls, line_width, line_end)
    fig, ax, ax_mat = plotPolyshape2Din3D(ps, height, fc, a; fig=fig, ax=ax, ax_mat=ax_mat)
end

function plotPolyshape2DVecin3D(vec_ps::Array{polyShape.PolyShape,1}, vec_h::Vector{Float64}, fc::String="red", a::Real=0.1; fig::Union{Nothing,PyPlot.Figure}=nothing, ax=nothing, ax_mat=nothing, line_width::Real=0.5, edge_color="k", filestr="none")
    fig_ = []
    ax_ = []
    ax_mat_ = []
    for i in eachindex(vec_h)
        ps_i = vec_ps[i]
        h_i = vec_h[i]
        if i == 1
            fig_, ax_, ax_mat_ = plotPolyshape2Din3D(ps_i, h_i, fc, a, fig=fig, ax=ax, ax_mat=ax_mat, line_width=line_width, edge_color=edge_color)
        end
        fig_, ax_, ax_mat_ = plotPolyshape2Din3D(ps_i, h_i, fc, a, fig=fig_, ax=ax_, ax_mat=ax_mat_, line_width=line_width, edge_color=edge_color)
    end
    return fig_, ax_, ax_mat_
end

function plotPolyshape2Din3D(ps::PolyShape, height::Real=0.0, fc::String="blue", a::Real=0.25; fig::Union{Nothing,PyPlot.Figure}=nothing, ax=nothing, ax_mat=nothing, line_width::Real=0.5, edge_color="k", filestr="none")
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

                ax.add_collection3d(art3d.Poly3DCollection(verts, facecolors=fc, linewidths=line_width, edgecolors=edge_color, alpha=a))
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

            ax.add_collection3d(art3d.Poly3DCollection(verts, facecolors=fc, linewidths=line_width, edgecolors=edge_color, alpha=a))

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


    ax_mat = [min_ax max_ax]

    # if line_width > 0.
    #     ls_vec = polyShape.polyShape2lineVec(ps)
    #     fig, ax, ax_mat = polyShape.plotPolyshape2DVecin3D(ls_vec, height *ones(size(ls_vec)), fc, a, fig=fig, ax=ax, ax_mat=ax_mat, line_width=line_width, line_end=3)
    # end

    if filestr != "none"
        plt.savefig(filestr, dpi=300)
    end


    return fig, ax, ax_mat

end


# Grafica polyshape 3D en espacio 3D.
function plotPolyshape3D(ps_volteor::PolyShape, matConexionVertices::Array{Float64,2}, vecVertices::Array{Any,1}, fc::String="red", a::Real=0.25; fig::Union{Nothing,PyPlot.Figure}=nothing, ax=nothing, ax_mat=nothing, filestr="none")
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


# Grafica polyshape 3D en espacio 3D.
function plotPolyshape3D(verts, fc::String="red", a::Real=0.25; fig::Union{Nothing,PyPlot.Figure}=nothing, ax=nothing, ax_mat=nothing, filestr="none")
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

    min_x = 10000
    min_y = 10000
    min_z = 10000
    max_x = -10000
    max_y = -10000
    max_z = -10000
    for k in eachindex(verts)
        for j = 1:4
            if verts[k][j][1] < min_x
                min_x = verts[k][j][1]
            end
            if verts[k][j][2] < min_y
                min_y = verts[k][j][2]
            end
            if verts[k][j][3] < min_z
                min_z = verts[k][j][3]
            end

            if verts[k][j][1] > max_x
                max_x = verts[k][j][1]
            end
            if verts[k][j][2] > max_y
                max_y = verts[k][j][2]
            end
            if verts[k][j][3] > max_z
                max_z = verts[k][j][3]
            end

        end
    end

    if fig === nothing
        pygui(true)

        fig = plt.figure()
        ax = fig.add_subplot(projection="3d")

        min_ax = minimum([min_x min_y min_z])
        max_ax = maximum([max_x max_y max_z])

    else
        min_ax = minimum([min_x min_y min_z])
        max_ax = maximum([max_x max_y max_z])
    end

    ax.set_xlim(min_ax, max_ax)
    ax.set_ylim(min_ax, max_ax)
    ax.set_zlim(max(0, min_ax), max_ax)

    # conjuntoAlturas = unique(V_[:, 3])
    # numAlturas = length(conjuntoAlturas)

    #numVerticesBase = Int(round(numVerticesTotales / numAlturas))

    ax.add_collection3d(art3d.Poly3DCollection(verts, facecolors=fc, linewidths=0.06, edgecolors="k", alpha=a))

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



function imageWhiteSpaceReduction(infileStr, outfileStr)

    img = load(infileStr)

    img_bn = binarize(Gray.(img), UnimodalRosin()) .< 0.5

    pos_vec = []

    vec_bn_h = sum(img_bn * 1, dims=1)
    for i = 1:length(vec_bn_h)-1
        if (vec_bn_h[i] == 0) && (vec_bn_h[i+1] >= 1) && (length(pos_vec) < 1)
            pos_vec = push!(pos_vec, i)
        end
    end
    for i = length(vec_bn_h):-1:2
        if (vec_bn_h[i] == 0) && (vec_bn_h[i-1] >= 1) && (length(pos_vec) < 2)
            pos_vec = push!(pos_vec, i)
        end
    end

    vec_bn_v = sum(img_bn * 1, dims=2)
    for i = 1:length(vec_bn_v)-1
        if (vec_bn_v[i] == 0) && (vec_bn_v[i+1] >= 1) && (length(pos_vec) < 3)
            pos_vec = push!(pos_vec, i)
        end
    end
    for i = length(vec_bn_v):-1:2
        if (vec_bn_v[i] == 0) && (vec_bn_v[i-1] >= 1) && (length(pos_vec) < 4)
            pos_vec = push!(pos_vec, i)
        end
    end

    img_cropped = img[pos_vec[3]:pos_vec[4], pos_vec[1]:pos_vec[2]]
    save(outfileStr, img_cropped)

    rm(infileStr)
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
        geom_i = polyShape.shape2geom(ps_i)
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
        geom1 = shape2geom(polyShape.subShape(shape1, i1))
        for i2 = 1:numRegions2
            geom2 = shape2geom(polyShape.subShape(shape2, i2))
            flag_12 = ArchGDAL.contains(geom1, geom2)
            if flag_12
                flag_out = true
            end
        end
    end

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
    geom = polyShape.shape2geom(shape)
    geom_out = ArchGDAL.convexhull(geom)
    shape_out = geom2shape(geom_out)
    V = shape_out.Vertices[1]
    shape_out = PolyShape([V[1:end-1, :]], 1)
    return shape_out
end


function shapeSimplify(shape::PosDimGeom, tol::Real)::PosDimGeom
    shape_out = shapeSimplifyTopology(shape, tol, false)
    return shape_out
end

function shapeSimplifyTopology(shape::PosDimGeom, tol::Real=0.05, flagTopo::Bool=true)::PosDimGeom
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



function shapeBuffer(shape::PosDimGeom, dist::Real, nseg::Int)
    if isa(shape, PolyShape)
        numElementos = shape.NumRegions
    elseif isa(shape, LineShape)
        numElementos = shape.NumLines
    end
    if numElementos == 1
        geom = polyShape.shape2geom(shape)
        poly_ = ArchGDAL.buffer(geom, dist, nseg)
        shape_ = polyShape.geom2shape(poly_)

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
            geom_k = polyShape.shape2geom(shape_k)
            poly_k = ArchGDAL.buffer(geom_k, dist, nseg)
            shape_k_ = polyShape.geom2shape(poly_k)
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


function shapeDistance(shape1::GeomObject, shape2::GeomObject)::Float64
    geom1 = shape2geom(shape1)
    geom2 = shape2geom(shape2)
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
        shape_i = subShape(shape1, i)
        for j = 1:numElements2
            shape_j = subShape(shape2, j)
            distMat[i, j] = shapeDistance(shape_i, shape_j)
        end
    end
    return distMat
end



function astext2polyshape(str)::PolyShape
    str = convert.(String, deepcopy(str))
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
        vec_path1 = polyShape.clipper_union(vec_path1)
        Clipper.add_paths!(c, vec_path1, Clipper.PolyTypeSubject, true)
    end
    if length(vec_path2) == 1
        Clipper.add_path!(c, vec_path2[1], Clipper.PolyTypeClip, true)
    else
        vec_path2 = polyShape.clipper_union(vec_path2)
        Clipper.add_paths!(c, vec_path2, Clipper.PolyTypeClip, true)
    end
    _, result_paths = Clipper.execute(c, ct, Clipper.PolyFillTypeEvenOdd, Clipper.PolyFillTypeEvenOdd)
    return result_paths
end


function clipper_union(vec_path1::Vector{Vector{IntPoint}}, vec_path2::Vector{Vector{IntPoint}})
    u_paths = polyShape.clipper_op(Clipper.ClipTypeUnion, vec_path1, vec_path2)
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
                vec_path_u = polyShape.clipper_op(Clipper.ClipTypeUnion, vec_path_u, vec_path2)
            end
        end
    else
        vec_path_u = vec_paths
    end
    return vec_path_u
end


function clipper_difference(vec_path1::Vector{Vector{IntPoint}}, vec_path2::Vector{Vector{IntPoint}})
    d_paths = polyShape.clipper_op(Clipper.ClipTypeDifference, vec_path1, vec_path2)
    return d_paths
end


function clipper_intersection(vec_path1::Vector{Vector{IntPoint}}, vec_path2::Vector{Vector{IntPoint}})
    i_paths = polyShape.clipper_op(Clipper.ClipTypeIntersection, vec_path1, vec_path2)
    return i_paths
end


function clipper_offset(vec_path_::Vector{Vector{IntPoint}}, delta, cjt=Clipper.JoinTypeMiter, cep=Clipper.EndTypeClosedPolygon)
    vec_path = deepcopy(vec_path_)
    delta = convert(Float64, delta)
    c = Clipper.ClipperOffset()
    if length(vec_path) == 1
        Clipper.add_path!(c, vec_path[1], cjt, cep)
    else
        vec_path = polyShape.clipper_union(vec_path)
        Clipper.add_paths!(c, vec_path, cjt, cep)
    end
    o_paths = Clipper.execute(c, delta)
    return o_paths
end


function clipper_scale(x::Real, magnitude::Int=8, sigdigits::Int=10)::Int
    return Int(round(x * 10^(sigdigits - magnitude)))
end


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

    path_s = polyShape.shape2clipper(ps_s)
    path_c = polyShape.shape2clipper(ps_c)
    result_path = polyShape.clipper_union(path_s, path_c)
    ps_out = polyShape.clipper2shape(result_path, PolyShape)
    return ps_out
end


function polyDifference(ps_s_::PolyShape, ps_c_::PolyShape)::PolyShape
    ps_s = deepcopy(ps_s_)
    ps_c = deepcopy(ps_c_)

    path_s = polyShape.shape2clipper(ps_s)
    path_c = polyShape.shape2clipper(ps_c)
    d_path = polyShape.clipper_difference(path_s, path_c)
    ps_out = polyShape.clipper2shape(d_path, PolyShape)
    return ps_out
end


function polyIntersect(ps_s_::PolyShape, ps_c_::PolyShape)::PolyShape
    ps_s = deepcopy(ps_s_)
    ps_c = deepcopy(ps_c_)

    path_s = polyShape.shape2clipper(ps_s)
    path_c = polyShape.shape2clipper(ps_c)
    i_path = polyShape.clipper_intersection(path_s, path_c)
    ps_out = polyShape.clipper2shape(i_path, PolyShape)

    return ps_out
end


# expande todos los lados en la misma distancia
function polyOffset(ps_::PolyShape, dist::Real)::PolyShape
    ps = deepcopy(ps_)

    delta = polyShape.clipper_scale(dist)
    path = polyShape.shape2clipper(ps)
    path_offset = polyShape.clipper_offset(path, delta, Clipper.JoinTypeMiter)
    ps_offset = polyShape.clipper2shape(path_offset, PolyShape)

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
            ps_actual = polyShape.polyOffset(ps_actual, delta)
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


############################################################################
########################### Funciones Especiales ###########################
############################################################################

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
            dist_offset = abs.([polyShape.lineLineDist(ls_base, vec_ls_comp[j]) for j in eachindex(vec_ls_comp)][parallel_id])
            parallel_id = parallel_id[argmin(abs.(dist_offset .- abs(distance_side)))]
        elseif length(parallel_id) == 1
            parallel_id = parallel_id[1]
        end
        return parallel_id
    end

    function polyShape2offsetPolyShape(ps, vec_partial_offset_id, vec_partial_offset_dist)
        # Genera vector de lineas offset en los lados vec_partial_offset_id y a la distancia vec_partial_offset_dist
        vec_ps_lines, _ = polyShape.polyShape2lineVec(ps)
        num_ps_lines = length(vec_ps_lines)

        # Initialize distance vector
        vec_todos_offset_dist_ = [0.0 for _ in 1:num_ps_lines]
        for i in eachindex(vec_partial_offset_dist)
            vec_todos_offset_dist_[vec_partial_offset_id[i]] = vec_partial_offset_dist[i]
        end
        vec_unique_dist = sort(unique(vec_partial_offset_dist))
        vec_ps_offsets = [polyShape.polyOffset(ps, vec_unique_dist[j]) for j in eachindex(vec_unique_dist)]

        vec_offsets_lines = []
        for i in eachindex(vec_ps_offsets)
            vec_offsets_lines_i, _ = polyShape.polyShape2lineVec(vec_ps_offsets[i])
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
        partial_offset_lines = Vector{LineShape}()
        vec_reg = Vector{Tuple{Int,Int}}()
        # Process offset lines
        flag_last_segment_end = false
        for i = 1:num_offset_lines
            cond_inicio = (i == 1)
            cond_termino = (i == num_offset_lines)

            current_side_index = i
            next_side_index = cond_inicio ? 2 : cond_termino ? 1 : i + 1

            cond_current_side_presente = ~(nonIntersecting_offset_lines[current_side_index].Vertices[1][1,:]' == [0 0] && 
                                            nonIntersecting_offset_lines[current_side_index].Vertices[1][2,:]' == [0 0])
            cond_next_side_presente = ~(nonIntersecting_offset_lines[next_side_index].Vertices[1][1,:]' == [0 0] && 
                                        nonIntersecting_offset_lines[next_side_index].Vertices[1][2,:]' == [0 0]) ||
                                        cond_termino

            if cond_current_side_presente && cond_next_side_presente
                current_line = deepcopy(nonIntersecting_offset_lines[current_side_index])
                dist_current = vec_todos_offset_dist_[current_side_index]
                next_line = deepcopy(nonIntersecting_offset_lines[next_side_index])
                dist_next = vec_todos_offset_dist_[next_side_index] 
                if flag_last_segment_end == false 
                    last_segment_end = current_line.Vertices[1][1, :]'
                    flag_last_segment_end = true
                else
                    last_segment_end = partial_offset_lines[end].Vertices[1][2, :]'
                end
                offset_distance_i = dist_current
                distance_to_next = polyShape.shapeDistance(current_line, next_line)
                if  0.1 < distance_to_next < abs(dist_next - dist_current) + .1
                    # Extend current and next lines and find intersection between them
                    extended_current_line = polyShape.extendLine(current_line, max(distance_to_next, abs(offset_distance_i)) * 1.2)
                    extended_next_line = polyShape.extendLine(next_line, max(distance_to_next, abs(offset_distance_i)) * 1.2)
                    intersection_point = polyShape.intersectLines(extended_current_line, extended_next_line)
                    if isnan(intersection_point.Vertices[1][1, 1]) # If segments don't intersect
                        if cond_inicio
                            push!(partial_offset_lines, current_line)
                        else
                            # Create a perpendicular line to next_line and find the intersection with extended_current_line
                            next_line_start_point = PointShape(next_line.Vertices[1][1, :]', 1)
                            perpendicular_line = polyShape.perpendicularLine(next_line_start_point, next_line, abs(offset_distance_i) * 1.2)
                            perpendicular_intersection_point = polyShape.intersectLines(extended_current_line, perpendicular_line)
                            if ~isnan(perpendicular_intersection_point.Vertices[1][1, 1])
                                last_segment = partial_offset_lines[end]
                                last_perp_intersection_point = polyShape.intersectLines(last_segment, perpendicular_line)
                                dist_last_perp = polyShape.pointLineDist(vec_ps_lines[i], last_perp_intersection_point)
                                if dist_last_perp < offset_distance_i
                                    current_line = deepcopy(LineShape([vcat(last_perp_intersection_point.Vertices[:]', last_perp_intersection_point.Vertices[:]')], 1))
                                    partial_offset_lines[end].Vertices[1][2, :] = last_perp_intersection_point.Vertices[:]
                                else
                                    current_line = deepcopy(LineShape([vcat(last_segment_end, perpendicular_intersection_point.Vertices[:]')], 1))
                                end
                            end
                            push!(partial_offset_lines, LineShape([vcat(last_segment_end, current_line.Vertices[1][2, :]')], 1))
                        end
                        # Project point to line
                        current_line_end_point = PointShape(current_line.Vertices[1][2, :]', 1)
                        projected_line_point = polyShape.point2lineProjection(current_line_end_point, next_line)
                        push!(partial_offset_lines, LineShape([vcat(current_line_end_point.Vertices[:]', projected_line_point.Vertices[1, :]')], 1))
                    else # If segments intersect
                        push!(partial_offset_lines, LineShape([vcat(last_segment_end, intersection_point.Vertices[1, :]')], 1))
                    end
                elseif cond_inicio
                    push!(partial_offset_lines, current_line)
                else
                    push!(partial_offset_lines, LineShape([vcat(last_segment_end, current_line.Vertices[1][2, :]')], 1))
                end
            end
        end
        start_pt = PointShape(partial_offset_lines[1].Vertices[1][1,:]',1)
        end_pt = PointShape(partial_offset_lines[end].Vertices[1][2,:]',1)
        dist_start_end = polyShape.distanceBetweenPoints(start_pt, end_pt)
        if .1 < dist_start_end 
            extended_start_line = polyShape.extendLine(partial_offset_lines[1], dist_start_end*1.2)
            extended_end_line = polyShape.extendLine(partial_offset_lines[end], dist_start_end*1.2)
            intersection_point = polyShape.intersectLines(extended_start_line, extended_end_line)
            if ~isnan(intersection_point.Vertices[1][1, 1])
                partial_offset_lines[1].Vertices[1][1,:] = intersection_point.Vertices
                partial_offset_lines[end].Vertices[1][2,:] = intersection_point.Vertices
            end
        end

        output_ps_ = polyShape.lineVec2polyShape(partial_offset_lines, vec_reg)
        return output_ps_, vec_todos_offset_dist_
    end

    max_dist = maximum(vec_partial_offset_dist) #-4
    ps_offset_max = polyShape.polyOffset(ps, max_dist)
    num_regions_offset_max = ps_offset_max.NumRegions
    if num_regions_offset_max >= 2
        vec_line_ps, _ = polyShape.polyShape2lineVec(ps)
        num_ps_lines = length(vec_line_ps)
        vec_todos_offset_dist = zeros(num_ps_lines)
        vec_todos_offset_dist[vec_partial_offset_id] .= copy(vec_partial_offset_dist)

        min_dist = minimum(vec_partial_offset_dist) #-7
        ps_offset_min = polyShape.polyOffset(ps, min_dist)

        output_ps = []
        for r = 1:ps_offset_min.NumRegions
            ps_offset_min_r = polyShape.subShape(ps_offset_min, r)
            vec_line_offset_min_r, _ = polyShape.polyShape2lineVec(ps_offset_min_r)
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


############################################################################
############################################################################
############################################################################




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

    if polyShape.polyIntersect(ps1, ps2).NumRegions >= 1

        numRegions1 = ps1.NumRegions
        numRegions2 = ps2.NumRegions
        ps_mat = Array{PolyShape,2}(undef, numRegions1, numRegions2)
        for i = 1:numRegions1
            ps1_i = polyShape.subShape(ps1, i)
            for j = 1:numRegions2
                ps2_j = polyShape.subShape(ps2, j)
                flag_ij = polyShape.shapeContains(ps1_i, ps2_j)
                if flag_ij #ps1_i contiene a ps2_j
                    centroid_j = polyShape.shapeCentroid(ps2_j).Vertices[1, :]

                    ps_box = polyShape.polyBox(centroid_j[1], centroid_j[2], 0.01, 1000.0, 0.0)
                    ps2_ex_j = polyShape.polyUnion(ps2_j, ps_box)
                    d_ps1_i_ps2_j = polyShape.polyDifference(ps1_i, ps2_ex_j)
                    ps_mat[i, j] = d_ps1_i_ps2_j
                elseif polyShape.polyIntersect(ps1_i, ps2_j).NumRegions >= 1
                    ps_mat[i, j] = polyShape.polyDifference(ps1_i, ps2_j)
                end

            end
        end

        ps_out = []
        flag = true
        for i = 1:numRegions1
            for j = 1:numRegions2
                try
                    if flag
                        ps_out = ps_mat[i, j]
                        flag = false
                    else
                        ps_intersect = polyShape.polyIntersect(ps_out, ps_mat[i, j])
                        if ps_intersect.NumRegions >= 1
                            ps_out = ps_intersect
                        else
                            ps_out = polyShape.polyUnion(ps_out, ps_mat[i, j])
                        end
                    end
                catch
                end
            end
        end

    else
        ps_out = deepcopy(ps1)
    end

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
            l_1 = polyShape.extendLine(lineVec_k[ix_1], 1.0)
            l_2 = polyShape.extendLine(lineVec_k[ix_2], 1.0)
            point_x_12 = polyShape.shapeIntersect(l_1, l_2)
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


function lineShape2lineVec(ls::LineShape)::Vector{LineShape}
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


function polyShape2lineVec(ps::PolyShape)

    num_regions = ps.NumRegions
    line_vec = Array{LineShape,1}()
    reg_vec = Array{Int,1}()
    for k = 1:num_regions
        V_k = copy(ps.Vertices[k])
        N_k = size(V_k, 1)

        # Obtiene vector de bordes del polígono original
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


function wkt_reproject(wkt_array::Vector{String}, epsg_source::Int64, epsg_target::Int64)
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
function wkt_reproject(df::DataFrame, geom_col_name::String, epsg_source::Int64, epsg_target::Int64)
    wkt_array = convert.(String, df[:, geom_col_name])
    transformed_wkts = polyShape.wkt_reproject(wkt_array, epsg_source, epsg_target)
    result_df = deepcopy(df)
    result_df[:, geom_col_name] = transformed_wkts
    return result_df
end


function polyReproject(ps::PolyShape, dx::Real, dy::Real, EPSG_in::Int64, EPSG_out::Int64)
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


function reverseLine(ls::LineShape)::LineShape
    numLines = ls.NumLines
    V = ls.Vertices
    V_ = deepcopy(V)
    for k = 1:numLines
        V_k = V[k]
        largo_k = size(V_k, 1)
        for i = 1:largo_k
            V_[k][i, :] = [V_k[end-(i-1), 1] V_k[end-(i-1), 2]]
        end
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
        d_12_i = polyShape.distanceBetweenPoints(p1_i, p2_i)

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


function distanceBetweenLines(l1::LineShape, l2::LineShape)
    if polyShape.isLineLineParallel(l1, l2)
        p1 = polyShape.midPointSegment(l1)
        dist = polyShape.pointLineDist(l2, p1)
    else
        dist = 10000
    end
    return dist
end


function polyProyeccion(ps, alt, orientacion)
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

########################################################################
########################################################################
########################################################################


export extraeInfoPoly, largoLadosPoly, isPolyConvex, isPolyInPoly, plotPolyshape2D, plotPolyshape2Din3D, plotPolyshape2DVecin3D,
    polyArea, polyDifference, polyDifference_v2, plotFig, plotScatter3d, polyShape2constraints, polyOrientation, polyUnion, shapeBuffer,
    polyIntersect, polyOffset, plotPolyshape3D, imageWhiteSpaceReduction,
    shape2geom, geom2shape, astext2polyshape, polyEliminaColineales,
    astext2lineshape, shapeContains, shapeArea, shapeDifference, shapeIntersect, shapeUnion, shapeHull, shapeSimplify, shapeSimplifyTopology, subShape,
    shapeVertex, numVertices, shapeCentroid, partialCentroid, shapeDistance, partialDistance, polyBox, polyRotate, polyReverse, setPolyOrientation,
    minPolyDistance, polyCopy, polyUnique, polyEliminateWithin, pointLineDist, intersectLines, findPolyIntersection, pointDistanceMat, 
    lineLineDist, parallelLineAtDist, lineAngle, halfspaceSignOfPointToLine, extendLine,
    polyObtieneCruces, replaceShapeVertex, lineVec2polyShape, polyShape2lineVec, polyShrink,
    ajustaCoordenadas, angleMaxDistRect, extendRectToIntersection, createLine, polyReproject, bisector_direction, angleBetweenLines,
    reverseLine, distanceBetweenPoints, midPointSegment, alphaPointSegment, points2Line, points2Poly, lineLength, isLineLineParallel, distanceBetweenLines,
    polyProyeccion, wkt_reproject,
    shape2clipper, clipper2shape, clipper_union, clipper_difference, clipper_intersection, clipper_offset,
    clipper_scale, lineShape2lineVec,
    partialPolyOffset, point2lineProjection, perpendicularLine, line2Box
end

#polyEliminaSpikes, polyEliminaCrucesComplejos, polySimplify, polyEliminaRepetidos, orderLineVec, 
