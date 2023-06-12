module graphMod

using LandValue, Graphs, GraphPlot, MetaGraphs


function dfs(g::MetaGraphs.MetaGraph{Int64, Int64}, u::Int64, v::Int64) #Depth First Search
    # Esta función calcula todas los caminos entre dos nodos de un grafo. 
    function dfs_(u, v, cPath, sPaths, vis)
        cPath_ = copy(cPath)
        sPaths_ = copy(sPaths)
        vis_ = copy(vis)
        if vis_[u] == false
            vis_[u] = true
            push!(cPath_, u)
            if u == v
                push!(sPaths_, cPath_)
            else
                for next in neighbors(g, u)
                    cPath_, sPaths_, vis_ = dfs_(next, v, cPath_, sPaths_, vis_)
                end
            end
            vis_[u] = false
            cPath__ = copy(cPath_)
            pop!(cPath__)
            cPath_ = copy(cPath__)
        end
        return cPath_, sPaths_, vis_
    end
    vis = zeros(Bool, nv(g))
    cPath = []
    sPaths = []
    _, simplePaths, _ = dfs_(u, v, cPath, sPaths, vis)
    return simplePaths
end
function dfs(A::Matrix{Int64}, u::Int64, v::Int64)
    g = graphMod.simpleGraph(A)
    simplePaths = graphMod.dfs(g, u, v)
    return simplePaths
end


function node_combis(g::MetaGraphs.MetaGraph{Int64, Int64}; flag_mat::Bool = false)
    # Esta función calcula todas las combinaciones de nodos que están conectados 
    function node_combis_(u, v, cPath, sCombis, vis, g)
        cPath_ = copy(cPath)
        sCombis_ = copy(sCombis)
        vis_ = copy(vis)
        if vis_[u] == false
            vis_[u] = true
            push!(cPath_, u)
            if u == v
                cPath_aux = sort(cPath_)[2:end-1] .- 1
                if !(cPath_aux in sCombis_)
                    push!(sCombis_, cPath_aux)
                end
            else
                for next in neighbors(g, u)
                    cPath_, sCombis_, vis_ = node_combis_(next, v, cPath_, sCombis_, vis_, g)
                end
            end
            vis_[u] = false
            cPath__ = copy(cPath_)
            pop!(cPath__)
            cPath_ = copy(cPath__)
        end
        return cPath_, sCombis_, vis_
    end    

    A = graphMod.getAdjacencyMat(g)
    A_ext = graphMod.extendAdjMat(A)
    g_ext = graphMod.simpleGraph(A_ext)
    start_node = 1
    end_node = graphMod.numVertices(g_ext)

    vis = zeros(Bool, Graphs.nv(g_ext))
    cPath = []
    sCombis = []
    _, simpleCombi, _ = node_combis_(start_node, end_node, cPath, sCombis, vis, g_ext)

    if flag_mat
        num_combi = length(simpleCombi)
        num_nodos = graphMod.numVertices(g)
        mat_combis = zeros(Int, num_combi, num_nodos)
        for i = 1:num_combi 
            id_non_zero = simpleCombi[i]
            mat_combis[i, id_non_zero] .= 1
        end
        simpleCombi = copy(mat_combis)
    end

    return simpleCombi
end
function node_combis(A::Matrix{Int64}; flag_mat::Bool = false)
    g = graphMod.simpleGraph(A)
    simpleCombi = graphMod.node_combis(g, flag_mat = flag_mat)
    return simpleCombi
end


function extendAdjMat(A::Matrix{Int64})
    filas, columnas = size(A)
    A_ext = zeros(Int64, filas+2, columnas+2)
    for i = 1:filas
        A_ext[i+1,1] = 1
        A_ext[i+1,end] = 1
        for j = 1:columnas
            A_ext[i+1,j+1] = A[i,j]    
        end
    end
    for j = 1:columnas
        A_ext[1,j+1] = 1
        A_ext[end,j+1] = 1
    end
    return A_ext
end


function simpleGraph(A::Matrix{Int64})
    g = GraphPlot.SimpleGraph(A)
    mg = MetaGraphs.MetaGraph(g, 1)
    return mg
end


function getDisconnectedSubgraphs(A::Matrix{Int64})
    g = GraphPlot.SimpleGraph(A)
    list_subgraphs = connected_components(g)
    return list_subgraphs
end

function getDisconnectedSubgraphs_v2(C::Matrix{Int64})
    function CtoA!(A, C, k)
        A_ = copy(A)
        num_lotes = size(C, 2)
        vec = collect(1:num_lotes)
        set = C[k,:] .* vec
        set = set[set .>= 1]
        for i in set
            for j in setdiff(set, i)
                A_[i,j] = 1
            end
        end
        return A_
    end
    num_combis, num_lotes = size(C)
    A = zeros(Int, num_lotes, num_lotes)

    for k = 1:num_combis
        A = CtoA!(A, C, k)
    end
    vec = graphMod.getDisconnectedSubgraphs(A)
    return vec
end

function getAdjacencyMat(g::MetaGraphs.MetaGraph{Int64, Int64})
    A_aux = adjacency_matrix(g)
    filas, columnas = size(A_aux)
    A = zeros(Int64, filas, columnas)
    for i = 1:filas
        for j = 1:columnas
            if A_aux[i,j] == 1
                A[i,j] = A_aux[i,j] 
            end
        end
    end
    return A
end


function graphPlot(g::MetaGraphs.MetaGraph{Int64, Int64}; nodelabel=1:Graphs.nv(g), nodelabeldist=0, nodelabelangleoffset=π/4, edgelabel=1:Graphs.ne(g), NODELABELSIZE=6)
    GraphPlot.gplot(g, nodelabel=nodelabel, nodelabeldist=nodelabeldist, nodelabelangleoffset=nodelabelangleoffset, edgelabel=edgelabel, NODELABELSIZE=NODELABELSIZE)
end
function graphPlot(A::Matrix{Int64}; nodelabel=1:size(A,1), nodelabeldist=0, nodelabelangleoffset=π/4, edgelabel=1:(sum(A)/2), NODELABELSIZE=6)
    g = graphMod.simpleGraph(A)
    graphMod.graphPlot(g, nodelabel=nodelabel, nodelabeldist=nodelabeldist, nodelabelangleoffset=nodelabelangleoffset, edgelabel=edgelabel, NODELABELSIZE=NODELABELSIZE)
end



function setProp!(g::MetaGraphs.MetaGraph{Int64, Int64}, v::Int, d::Dict{Symbol, Any})    
    # graphMod.setProp!(g, 1, Dict(:rol => "123-1", :sup => 100))
    MetaGraphs.set_props!(g, v, d)
end
function setProp!(g::MetaGraphs.MetaGraph{Int64, Int64}, v::Int, name::Symbol, value::Any)
    # graphMod.setProp!(g, 1, 2, :periComp, 20)
    MetaGraphs.set_prop!(g, v, name, value)
end
function setProp!(g::MetaGraphs.MetaGraph{Int64, Int64}, e::Graphs.SimpleGraphs.SimpleEdge{Int64}, name::Symbol, value::Any)
    MetaGraphs.set_prop!(g, e, name, value)
end
function setProp!(g::MetaGraphs.MetaGraph{Int64, Int64}, e_ini::Int, e_fin::Int, name::Symbol, value::Any)
    MetaGraphs.set_prop!(g, e_ini, e_fin, name, value)
end


function getProp(g::MetaGraphs.MetaGraph{Int64, Int64}, v::Int)::Dict{Symbol, Any}
    # graphMod.getProp(g, 2)
    return MetaGraphs.props(g, v)
end
function getProp(g::MetaGraphs.MetaGraph{Int64, Int64}, v::Int, name::Symbol)
    # graphMod.getProp(g, 2, :sup)
    return MetaGraphs.get_prop(g, v, name)
end
function getProp(g::MetaGraphs.MetaGraph{Int64, Int64}, e_ini::Int, e_fin::Int)
    # graphMod.getProp(g, 5, 6)
    return MetaGraphs.props(g, e_ini, e_fin)
end
function getProp(g::MetaGraphs.MetaGraph{Int64, Int64}, e_ini::Int, e_fin::Int, name::Symbol)
    # graphMod.getProp(g, 5, 6, :periComp)
    return MetaGraphs.get_prop(g, e_ini, e_fin, name)
end


function getVertices(g::MetaGraphs.MetaGraph{Int64, Int64})
    return collect(Graphs.vertices(g))
end


function getEdges(g::MetaGraphs.MetaGraph{Int64, Int64})
    # listEdges = graphMod.getEdges(g)
    return collect(Graphs.edges(g))
end


function nodeSubgraph(g::MetaGraphs.MetaGraph{Int64, Int64}, name::Symbol, value)
    # sg = graphMod.nodeSubgraph(g, :sup, 100)
    v_vec = graphMod.filterVertices(g, name::Symbol, value)
    sg, _ = MetaGraphs.induced_subgraph(g, v_vec)
    return sg
end
function nodeSubgraph(g::MetaGraphs.MetaGraph{Int64, Int64}, name::Symbol; lb=0 , ub=10^8)
    # sg = graphMod.nodeSubgraph(g, :sup, lb=200)
    v_vec = graphMod.filterVertices(g, name, lb=lb , ub=ub)
    sg, _ = MetaGraphs.induced_subgraph(g, v_vec)
    return sg
end


function edgeSubgraph(g::MetaGraphs.MetaGraph{Int64, Int64}, name::Symbol, value)
    # sg = graphMod.edgeSubgraph(g, :periComp, 10)
    e_vec = graphMod.filterEdges(g, name::Symbol, value)
    sg, _ = MetaGraphs.induced_subgraph(g, e_vec)
    return sg
end
function edgeSubgraph(g::MetaGraphs.MetaGraph{Int64, Int64}, name::Symbol; lb=0 , ub=10^8)
    # sg = graphMod.edgeSubgraph(g, :periComp, lb=13 , ub=10^8)
    e_vec = graphMod.filterEdges(g, name, lb=lb , ub=ub)
    sg, _ = MetaGraphs.induced_subgraph(g, e_vec)
    return sg
end


function numVertices(g::MetaGraphs.MetaGraph{Int64, Int64})
    return Graphs.nv(g)
end


function numEdges(g::MetaGraphs.MetaGraph{Int64, Int64})
    return Graphs.ne(g)
end


function filterVertices(g::MetaGraphs.MetaGraph{Int64, Int64}, name::Symbol, value)
    return collect(MetaGraphs.filter_vertices(g, name, value))
end
function filterVertices(g::MetaGraphs.MetaGraph{Int64, Int64}, name::Symbol; lb=0 , ub=10^8)
    function fn_vert(g::AbstractMetaGraph, v::Integer)
        val = MetaGraphs.props(g, v)[name]
        flag = (val >= lb) & (val <= ub)
        return flag
    end
    return collect(MetaGraphs.filter_vertices(g, fn_vert))
end


function filterEdges(g::MetaGraphs.MetaGraph{Int64, Int64}, name::Symbol, value)
    # iter_edges = graphMod.filterEdges(g, :periComp, 10)
    return collect(MetaGraphs.filter_edges(g, name, value))
end
function filterEdges(g::MetaGraphs.MetaGraph{Int64, Int64}, name::Symbol; lb=0 , ub=10^8)
    # iter_edges = graphMod.filterEdges(g, :periComp, lb=10 , ub=10^8)
    function fn_vert(g::AbstractMetaGraph, e)
        val = MetaGraphs.props(g, e)[name]
        flag = (val >= lb) & (val <= ub)
        return flag
    end
    return collect(MetaGraphs.filter_edges(g, fn_vert))
end


function neighbors(g::MetaGraphs.MetaGraph{Int64, Int64}, v)
    # neighbor_vec = graphMod.neighbors(g, 2)
    return Graphs.neighbors(g, v)
end


function adjMatSubNode(A::Matrix{Int64}, n_out::Int64)
    #Obtiene la matriz de adyacencia sin el nodo n_out
    A_ant_f = copy(A[1:n_out-1,:])
    A_post_f = copy(A[n_out+1:end,:])
    A_f = [A_ant_f; A_post_f]
    A_ant_c = A_f[:,1:n_out-1]
    A_post_c = A_f[:,n_out+1:end]
    A_sub = [A_ant_c A_post_c]
    return A_sub
end


function combiMatForNode(matCombis::Matrix{Int64}, n::Int64)
    #Obtiene todas las combinaciones donde participa el nodo n
    matCombis_ = copy(matCombis)
    matCombis_n = matCombis_[matCombis_[:,n] .== 1, :]
    return matCombis_n
end


function eliminateNodeAdjMat(A::Matrix{Int64}, k::Int64)
    # Get the number of rows and columns in A
    A_ = copy(A)
    m = size(A_, 1)
    
    # Check if k is a valid index
    if k > m 
        error("k is out of bounds")
    end
    
    # Use array slicing to eliminate the k-th row and k-th column
    B = A_[setdiff(1:m, [k]), setdiff(1:m, [k])]
    
    return B
end


export dfs, node_combis, simpleGraph, getDisconnectedSubgraphs, getDisconnectedSubgraphs_v2, getAdjacencyMat, 
        graphPlot, setProp!, getProp, getVertices, getEdges, nodeSubgraph, edgeSubgraph, numVertices, 
        numEdges, filterVertices, filterEdges, neighbors, adjMatSubNode, combiMatForNode, eliminateNodeAdjMat

end