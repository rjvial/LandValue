module polyPlot

using LandValue, PyCall, PyPlot, LazySets, ImageBinarization, DataFrames



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
        ps = shapeBuffer(ps, point_width)
    elseif ps isa LineShape
        numSectors = ps.NumLines
        ps = shapeBuffer(ps, line_width, line_end)
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
function plotPolyshape2DVecin3D(vec_ps::Array{LineShape,1}, vec_h::Vector{Float64}, fc::String="red", a::Real=0.1; fig::Union{Nothing,PyPlot.Figure}=nothing, ax=nothing, ax_mat=nothing, line_width::Real=0.5, line_end::Int64=3)
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
    ps = shapeBuffer(ps, line_width)
    fig, ax, ax_mat = plotPolyshape2Din3D(ps, height, fc, a; fig=fig, ax=ax, ax_mat=ax_mat)
end
function plotPolyshape2Din3D(ls::LineShape, height::Real=0.0, fc::String="blue", a::Real=0.25; fig::Union{Nothing,PyPlot.Figure}=nothing, ax=nothing, ax_mat=nothing, line_width::Real=0.5, line_end::Int64=3, filestr="none")
    ps = shapeBuffer(ls, line_width, line_end)
    fig, ax, ax_mat = plotPolyshape2Din3D(ps, height, fc, a; fig=fig, ax=ax, ax_mat=ax_mat)
end

function plotPolyshape2DVecin3D(vec_ps::Array{PolyShape,1}, vec_h::Vector{Float64}, fc::String="red", a::Real=0.1; fig::Union{Nothing,PyPlot.Figure}=nothing, ax=nothing, ax_mat=nothing, line_width::Real=0.5, edge_color="k", filestr="none")
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
    #     ls_vec = polyShape.shape2vector(ps)
    #     fig, ax, ax_mat = polyPlot.plotPolyshape2DVecin3D(ls_vec, height *ones(size(ls_vec)), fc, a, fig=fig, ax=ax, ax_mat=ax_mat, line_width=line_width, line_end=3)
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



export plotPolyshape2D, plotPolyshape2Din3D, 
    plotPolyshape2DVecin3D, plotFig, plotScatter3d, 
    plotPolyshape3D, 
    imageWhiteSpaceReduction
end

#polyEliminaSpikes, polyEliminaCrucesComplejos, polySimplify, polyEliminaRepetidos, orderLineVec, 
