using Unicode
using Graphs
using LandValue, DotEnv, DataFrames
using Base.Threads

my_env = DotEnv.config("secrets.env")
conn_aws = aws_julia.connection(my_env["AWS_ACCESS_KEY"], my_env["AWS_SECRET_KEY"], my_env["AWS_REGION"])


# ── SSH + Remote cypher-shell (no local cypher-shell needed) ─────────────────
key_pair   = "neo4j-key-pair.pem"
ec2_user   = "ec2-user"

INSTANCIA_EC2 = "Neo4j-EC2-V2"
instance_info = aws_julia.find_instance_by_name(INSTANCIA_EC2, conn_aws)
public_dns = instance_info["dnsName"]

folder = "/usr/bin/cypher-shell"
neo4j_host = my_env["NEO4J_URI"]
neo4j_user = my_env["NEO4J_USER"]
neo4j_password = my_env["NEO4J_PASSWORD"]

conn_neo4j = neo4j_julia.connection(neo4j_host, neo4j_user, neo4j_password, folder, key_pair, ec2_user, public_dns)

athena_bucket = "landengines-data"
athena_output = "query-results"
athena_catalog_name = "AwsDataCatalog"
database_name = "iceberg_db"

owner_type = "\'Organization\'" 
query = """
SELECT propietario, tipo_propietario
FROM (
    SELECT propietario, tipo_propietario,
    ROW_NUMBER() OVER (PARTITION BY propietario ORDER BY year DESC, half DESC) AS rn
    FROM datos_tgr
    WHERE tipo_propietario = $owner_type
) t
WHERE rn = 1
ORDER BY propietario;
"""
dfA = aws_julia.query_to_dataframe(query, database_name, athena_bucket, athena_output, athena_catalog_name, conn_aws)

query = """
SELECT DISTINCT rut_sociedad_completo, razon_social_sociedad
FROM "iceberg_db"."empresas_consolidada"
ORDER BY razon_social_sociedad;
"""
dfB = aws_julia.query_to_dataframe(query, database_name, athena_bucket, athena_output, athena_catalog_name, conn_aws)




using DataFrames, Graphs, Unicode

const SIM_THRESHOLD = 0.88

function normalize_name(s::AbstractString)
    s = uppercase(s)
    s = Unicode.normalize(s, :NFD)
    s = replace(s, r"\p{Mn}" => "")
    s = replace(s, 'Ñ' => 'N')
    s = replace(s, r"[ªº°]" => "")
    s = replace(s, r"[^\x00-\x7F]" => "")
    s = replace(s, "&" => " Y ")
    s = replace(s, r"[^\w\s]" => " ")
    s = replace(s, r"\bSOCIEDAD ANONIMA\b" => "SA")
    s = replace(s, r"\bS A\b" => "SA")
    s = replace(s, r"\bSOCIED\b" => "SOCIEDAD")
    s = replace(s, r"\bSOC\b" => "SOCIEDAD")
    s = replace(s, r"\bINMOBILIARIO\b" => "INMOBILIARIA")
    s = replace(s, r"\bINMOBILIARIOS\b" => "INMOBILIARIA")
    s = replace(s, r"\bINMOBILIA\b" => "INMOBILIARIA")
    s = replace(s, r"\bINMOBIL\b" => "INMOBILIARIA")
    s = replace(s, r"\bINMOB\b" => "INMOBILIARIA")
    s = replace(s, r"\bVIV\b" => "VIVIENDAS")
    s = replace(s, r"\bECONOMICAS\b" => "ECONOMICA")
    s = replace(s, r"\bECONO\b" => "ECONOMICA")
    s = replace(s, r"\bECON\b" => "ECONOMICA")
    s = replace(s, r"\bMETROPOLITANAS\b" => "METROPOLITANA")
    s = replace(s, r"\bINGENIEROS\b" => "ING")
    s = replace(s, r"\bINGENIERO\b" => "ING")
    s = replace(s, r"\bCIVILES\b" => "CIV")
    s = replace(s, r"\bCIVIL\b" => "CIV")
    s = replace(s, r"\bCIVI\b" => "CIV")
    s = replace(s, r"\bASOCIADOS\b" => "ASOC")
    s = replace(s, r"\bASOCIADAS\b" => "ASOC")
    s = replace(s, r"\bASOCIAD\b" => "ASOC")
    s = replace(s, r"\bUNIVERSIDAD\b" => "UNIV")
    s = replace(s, r"\bSANTIAGO\b" => "STGO")
    s = replace(s, r"\bCOMPANY\b" => "CO")
    s = replace(s, r"\bGENERAL\b" => "GRAL")
    s = replace(s, r"\bINVERSIONES\b" => "INV")
    s = replace(s, r"\bINVERSION\b" => "INV")
    s = replace(s, r"\bINEVERSION\b" => "INV")
    s = replace(s, r"\bEMPRE\b" => "EMPRESA")
    s = replace(s, r"\bEMP\b" => "EMPRESA")
    s = replace(s, r"\bNACIONAL\b" => "NAC")
    s = replace(s, r"\bNACIONA\b" => "NAC")
    s = replace(s, r"LEASING\s*HABITACIONAL" => "LEASINGHAB")
    s = replace(s, r"\bCIA\b" => "COMPANIA")
    s = replace(s, r"\bCI\b" => "COMPANIA")
    s = replace(s, r"\bAND\b" => "Y")
    s = replace(s, r"\bLIMITADA\b" => "LTDA")
    s = replace(s, r"\bLIMITDA\b" => "LTDA")
    s = replace(s, r"\bALTDA\b" => "LTDA")
    s = replace(s, r"\bLIMITAD\b" => "LTDA")
    s = replace(s, r"\bLIMITA\b" => "LTDA")
    s = replace(s, r"\bLIMIT\b" => "LTDA")
    s = replace(s, r"\bLIMI\b" => "LTDA")
    s = replace(s, r"\bLIM\b" => "LTDA")
    s = replace(s, r"\bLTD\b" => "LTDA")
    s = replace(s, r"\bSOCIEDAD POR ACCIONES\b" => "SPA")
    s = replace(s, r"\bSP\b" => "SPA")
    s = replace(s, r"\s+" => " ")
    s = replace(s, r"\b([A-Z])\s+([A-Z])\s+([A-Z])\s+([A-Z])\b" => s"\1\2\3\4")
    s = replace(s, r"\b([A-Z])\s+([A-Z])\s+([A-Z])\b" => s"\1\2\3")
    s = replace(s, r"\b([A-Z])\s+([A-Z])\b" => s"\1\2")
    strip(s)
end

# Precompute token sets once
function tokenize(s::AbstractString)::Set{SubString{String}}
    Set(split(s))
end

function token_overlap(ta::Set, tb::Set)
    isempty(ta) || isempty(tb) ? 0.0 :
        length(intersect(ta, tb)) / min(length(ta), length(tb))
end

function jaro_winkler(s1::AbstractString, s2::AbstractString; p::Float64=0.1)
    isempty(s1) && isempty(s2) && return 1.0
    (isempty(s1) || isempty(s2)) && return 0.0
    s1 == s2 && return 1.0

    c1 = collect(s1)
    c2 = collect(s2)
    len1, len2 = length(c1), length(c2)
    match_dist = max(len1, len2) ÷ 2 - 1
    match_dist = max(0, match_dist)

    s1_matches = falses(len1)
    s2_matches = falses(len2)
    matches = 0
    transpositions = 0

    @inbounds for i in 1:len1
        start_j = max(1, i - match_dist)
        end_j = min(len2, i + match_dist)
        for j in start_j:end_j
            s2_matches[j] && continue
            c1[i] != c2[j] && continue
            s1_matches[i] = true
            s2_matches[j] = true
            matches += 1
            break
        end
    end

    matches == 0 && return 0.0

    k = 1
    @inbounds for i in 1:len1
        !s1_matches[i] && continue
        while !s2_matches[k]
            k += 1
        end
        c1[i] != c2[k] && (transpositions += 1)
        k += 1
    end

    jaro = (matches/len1 + matches/len2 + (matches - transpositions÷2)/matches) / 3.0

    prefix_len = 0
    @inbounds for i in 1:min(4, len1, len2)
        c1[i] == c2[i] ? (prefix_len += 1) : break
    end

    jaro + prefix_len * p * (1 - jaro)
end

function trigrams(s::AbstractString)::Set{String}
    chars = collect(s)
    len = length(chars)
    len < 3 && return Set{String}([s])
    result = Set{String}()
    sizehint!(result, len - 2)
    @inbounds for i in 1:len-2
        push!(result, String(chars[i:i+2]))
    end
    result
end

function trigram_similarity_precomputed(t1::Set{String}, t2::Set{String})
    (isempty(t1) || isempty(t2)) && return 0.0
    n_inter = length(intersect(t1, t2))
    n_inter / (length(t1) + length(t2) - n_inter)
end

function directional_soft_sim(tokens_a::Vector{String}, tokens_b::Vector{String})
    total_score = 0.0
    na = length(tokens_a)
    @inbounds for i in 1:na
        ta = tokens_a[i]
        best_match = 0.0
        for j in 1:length(tokens_b)
            tb = tokens_b[j]
            ta == tb && (best_match = 1.0; break)
            score = jaro_winkler(ta, tb)
            score > best_match && (best_match = score)
        end
        total_score += best_match
    end
    total_score / na
end

function soft_token_similarity(tokens_a::Vector{String}, tokens_b::Vector{String})
    (isempty(tokens_a) || isempty(tokens_b)) && return 0.0
    min(directional_soft_sim(tokens_a, tokens_b), directional_soft_sim(tokens_b, tokens_a))
end

function tfidf_weighted_overlap(tokens_a::Set, tokens_b::Set, idf::Dict{String,Float64})
    (isempty(tokens_a) || isempty(tokens_b)) && return 0.0

    common = intersect(tokens_a, tokens_b)
    isempty(common) && return 0.0

    common_weight = sum(get(idf, String(t), 1.0) for t in common)
    smaller_set = length(tokens_a) < length(tokens_b) ? tokens_a : tokens_b
    total_weight = sum(get(idf, String(t), 1.0) for t in smaller_set)

    total_weight > 0 ? common_weight / total_weight : 0.0
end

function has_distinctive_match(vec_a::Vector{String}, vec_b::Vector{String})
    for ta in vec_a
        ta in SKIP_WORDS && continue
        for tb in vec_b
            tb in SKIP_WORDS && continue
            (ta == tb || jaro_winkler(ta, tb) >= 0.92) && return true
        end
    end
    false
end

function fast_similarity(vec_a::Vector{String}, vec_b::Vector{String}, tri_a::Set{String}, tri_b::Set{String})
    !has_distinctive_match(vec_a, vec_b) && return 0.0
    score_soft = soft_token_similarity(vec_a, vec_b)
    score_soft < 0.5 && return score_soft
    score_trigram = trigram_similarity_precomputed(tri_a, tri_b)
    0.7 * score_soft + 0.3 * score_trigram
end

function hybrid_similarity(tokens_a::Set, tokens_b::Set, vec_a::Vector{String}, vec_b::Vector{String}, tri_a::Set{String}, tri_b::Set{String}, idf::Dict{String,Float64})
    score_tfidf = tfidf_weighted_overlap(tokens_a, tokens_b, idf)
    score_tfidf == 0.0 && isempty(intersect(tokens_a, tokens_b)) && return 0.0

    score_soft = soft_token_similarity(vec_a, vec_b)
    score_trigram = trigram_similarity_precomputed(tri_a, tri_b)

    0.4 * score_tfidf + 0.4 * score_soft + 0.2 * score_trigram
end

function hybrid_similarity_v2(tokens_a::Set, tokens_b::Set, vec_a::Vector{String}, vec_b::Vector{String}, tri_a::Set{String}, tri_b::Set{String}, idf::Dict{String,Float64}, full_a::String, full_b::String)
    score_tfidf = tfidf_weighted_overlap(tokens_a, tokens_b, idf)
    score_tfidf == 0.0 && isempty(intersect(tokens_a, tokens_b)) && return 0.0

    score_soft = soft_token_similarity(vec_a, vec_b)
    score_trigram = trigram_similarity_precomputed(tri_a, tri_b)
    score_jw = jaro_winkler(full_a, full_b)

    0.3 * score_tfidf + 0.3 * score_soft + 0.2 * score_trigram + 0.2 * score_jw
end

# Common business words to skip in blocking (these don't distinguish companies)
const SKIP_WORDS = Set([
    "SOCIEDAD", "EMPRESA", "COMERCIAL", "SERVICIOS", "INVERSIONES", "INVERSION",
    "CIA", "COMPANIA", "SA", "SPA", "LTDA", "LIMITADA", "Y", "DE", "LA", "EL", "LOS", "LAS",
    "INMOBILIARIA", "INMOBILIARIO", "INMOBILIARIOS", "INMOB",
    "ADMINISTRADORA", "ADMINISTRACION", "ADMINISTRACIONES", "ADM",
    "ASESORIAS", "ASESORIA", "ASESOR", "ASES",
    "GESTION", "GESTIONES", "DESARROLLO", "DESARROLLOS",
    "AGRICOLA", "AGRICOLAS", "CONSTRUCTORA", "CONSTRUCCIONES",
    "CONSULTORA", "CONSULTORES", "HOLDING", "CAPITAL", "GRUPO",
    "HERMANOS", "ABOGADOS", "ASOCIADOS", "PROFESIONALES",
    "INV", "INVER", "E", "DEL", "LIMITAD", "LIMIT",
    "SEGUROS", "SEGURO", "SEG", "VIDA", "SALUD",
    "FONDO", "FONDOS", "CHILE", "CHILENA", "CHILENO",
    "GENERAL", "GRAL", "NACIONAL", "NAC",
    "INTERNACIONAL", "INTERAMERICANA",
    "PENSIONES", "PENSION", "PENS", "PREVISION", "PREVISIONAL",
    "ADMINISTRADORAS", "ASOC",
    "ASOCIACION", "ASOCIACIONES"
])

function block_keys(s::AbstractString)
    tokens = split(s)
    significant = [t for t in tokens if !(t in SKIP_WORDS) && length(t) >= 3]
    isempty(significant) && return [isempty(tokens) ? "" : first(tokens[1], 3)]

    keys = String[]
    for t in significant
        push!(keys, first(t, 3))
        if length(t) >= 5
            push!(keys, first(t, 5))
        end
        if length(t) >= 2 && isascii(t[1]) && isletter(t[1])
            push!(keys, first(t, 2))
        end
    end
    unique(keys)
end

# --- normalize & prepare ---
dfA = copy(dfA)
dfB = copy(dfB)

dropmissing!(dfA, :propietario)
dropmissing!(dfB, :razon_social_sociedad)
filter!(row -> row.razon_social_sociedad != "", dfB)

dfA.norm = normalize_name.(dfA.propietario)
dfB.norm = normalize_name.(dfB.razon_social_sociedad)

id_A = Vector{String}(dfA.propietario)
id_B = Vector{String}(dfB.rut_sociedad_completo)

# =============================
# PHASE 1: Cluster A internally
# =============================
nA = nrow(dfA)
nB = nrow(dfB)

println("Tokenizing A ($nA records)...")
norm_A = Vector{String}(dfA.norm)
token_sets_A = [tokenize(s) for s in norm_A]
token_vecs_A = [String.(collect(ts)) for ts in token_sets_A]

println("Pre-computing trigrams for A...")
trigrams_A = [trigrams(s) for s in norm_A]

println("IDF weights will be computed after B tokenization...")

function extract_legal_type(s::AbstractString)
    s = strip(s)
    endswith(s, " SA") && return "SA"
    endswith(s, " SPA") && return "SPA"
    endswith(s, " LTDA") && return "LTDA"
    return ""
end

legal_types_A = [extract_legal_type(s) for s in norm_A]

println("Building block index for A...")
block_to_A = Dict{String, Vector{Int}}()
for i in 1:nA
    for bk in block_keys(dfA.norm[i])
        push!(get!(Vector{Int}, block_to_A, bk), i)
    end
end

MAX_BLOCK_SIZE = 500
for (k, v) in block_to_A
    length(v) > MAX_BLOCK_SIZE && empty!(v)
end

println("Clustering A records ($(length(block_to_A)) blocks) using $(nthreads()) threads...")
gA = SimpleGraph(nA)

blocks_vec = [(bk, rows) for (bk, rows) in block_to_A if !isempty(rows)]
sort!(blocks_vec, by = x -> length(x[2]), rev = true)
nblocks = length(blocks_vec)

estimated_edges = nblocks * 10
thread_edges = [sizehint!(Vector{Tuple{Int,Int}}(), estimated_edges ÷ nthreads()) for _ in 1:nthreads()]
thread_comparisons = zeros(Int, nthreads())
thread_seen = [Set{Tuple{Int,Int}}() for _ in 1:nthreads()]

@threads for idx in 1:nblocks
    tid = threadid()
    (_, rows) = blocks_vec[idx]
    local_seen = thread_seen[tid]
    local_edges = thread_edges[tid]

    for i in 1:length(rows)-1
        u = rows[i]
        for j in i+1:length(rows)
            v = rows[j]
            pair = minmax(u, v)
            pair in local_seen && continue
            push!(local_seen, pair)
            lt_u = legal_types_A[u]
            lt_v = legal_types_A[v]
            (!isempty(lt_u) && !isempty(lt_v) && lt_u != lt_v) && continue
            thread_comparisons[tid] += 1
            sim = fast_similarity(token_vecs_A[u], token_vecs_A[v], trigrams_A[u], trigrams_A[v])
            sim >= SIM_THRESHOLD && push!(local_edges, (u, v))
        end
    end
end

all_edges = Set{Tuple{Int,Int}}()
for edges in thread_edges
    for e in edges
        push!(all_edges, e)
    end
end
for (u, v) in all_edges
    add_edge!(gA, u, v)
end

n_comparisons = sum(thread_comparisons)
println("A-A comparisons: $n_comparisons, Edges: $(ne(gA))")

comps_A = connected_components(gA)
println("Found $(length(comps_A)) A clusters")

# =============================
# PHASE 2: Match A clusters to B
# =============================
println("\nTokenizing B ($nB records)...")
norm_B = Vector{String}(dfB.norm)
token_sets_B = [tokenize(s) for s in norm_B]
token_vecs_B = [String.(collect(ts)) for ts in token_sets_B]

println("Pre-computing trigrams for B...")
trigrams_B = [trigrams(s) for s in norm_B]

println("Computing IDF weights over A+B corpus...")
doc_freq = Dict{String,Int}()
n_total = nA + nB
for ts in token_sets_A
    for t in ts
        doc_freq[String(t)] = get(doc_freq, String(t), 0) + 1
    end
end
for ts in token_sets_B
    for t in ts
        doc_freq[String(t)] = get(doc_freq, String(t), 0) + 1
    end
end
idf_weights = Dict{String,Float64}()
for (term, df) in doc_freq
    idf_weights[term] = log(n_total / df)
end

println("Extracting legal types for B...")
legal_types_B = [extract_legal_type(s) for s in norm_B]

println("Pre-computing block keys for A...")
block_keys_A = [block_keys(s) for s in norm_A]

println("Building block index for B...")
block_to_B = Dict{String, Vector{Int}}()
for i in 1:nB
    for bk in block_keys(norm_B[i])
        push!(get!(Vector{Int}, block_to_B, bk), i)
    end
end

const MAX_CANDIDATES = 100
const FAST_THRESHOLD = 0.3

using CSV

println("Matching A clusters to B using $(nthreads()) threads...")
n_clusters = length(comps_A)
step = max(1, n_clusters ÷ 20)
save_step = max(1, n_clusters ÷ 10)

cluster_order = sortperm(comps_A, by = length, rev = true)

estimated_results = nA ÷ nthreads() + 100
thread_results = [sizehint!(Vector{NamedTuple{(:A_id, :B_id, :cluster_id), Tuple{String, Union{String,Missing}, Int}}}(), estimated_results) for _ in 1:nthreads()]
progress_counter = Atomic{Int}(0)
last_save = Atomic{Int}(0)
save_lock = ReentrantLock()

function save_progress(thread_results, filename="matching_results_progress.csv")
    temp_result = DataFrame(A_id = String[], B_id = Union{String,Missing}[], cluster_id = Int[])
    for tr in thread_results
        for row in tr
            push!(temp_result, row)
        end
    end
    sort!(temp_result, :cluster_id)
    CSV.write(filename, temp_result; delim='|')
    temp_result
end

@threads for idx in 1:n_clusters
    tid = threadid()
    cluster_id = cluster_order[idx]
    comp = comps_A[cluster_id]

    cnt = atomic_add!(progress_counter, 1)
    cnt % step == 0 && print("\r  Cluster $cnt / $n_clusters")

    if cnt % save_step == 0
        lock(save_lock) do
            if cnt > last_save[]
                last_save[] = cnt
                save_progress(thread_results)
                println(" [saved progress at $cnt/$n_clusters]")
            end
        end
    end

    cluster_blocks = Set{String}()
    for i in comp
        for bk in block_keys_A[i]
            push!(cluster_blocks, bk)
        end
    end

    candidate_B = Set{Int}()
    for bk in cluster_blocks
        haskey(block_to_B, bk) && union!(candidate_B, block_to_B[bk])
    end

    cluster_lt = ""
    for i in comp
        lt = legal_types_A[i]
        if !isempty(lt)
            cluster_lt = lt
            break
        end
    end

    filtered = Vector{Tuple{Int,Float64}}()
    for b in candidate_B
        if !isempty(cluster_lt) && !isempty(legal_types_B[b]) && cluster_lt != legal_types_B[b]
            continue
        end
        best_overlap = 0.0
        for a in comp
            ovlp = token_overlap(token_sets_A[a], token_sets_B[b])
            ovlp > best_overlap && (best_overlap = ovlp)
        end
        best_overlap >= FAST_THRESHOLD && push!(filtered, (b, best_overlap))
    end
    sort!(filtered, by = x -> x[2], rev = true)
    length(filtered) > MAX_CANDIDATES && resize!(filtered, MAX_CANDIDATES)

    best_b = nothing
    best_sim = SIM_THRESHOLD
    if !isempty(filtered)
        for (b, _) in filtered
            for a in comp
                sim = hybrid_similarity_v2(token_sets_A[a], token_sets_B[b], token_vecs_A[a], token_vecs_B[b], trigrams_A[a], trigrams_B[b], idf_weights, norm_A[a], norm_B[b])
                if sim > best_sim
                    best_sim = sim
                    best_b = b
                end
            end
            best_sim >= 1.0 && break
        end
    end

    b_id = isnothing(best_b) ? missing : id_B[best_b]
    for a in comp
        push!(thread_results[tid], (A_id=id_A[a], B_id=b_id, cluster_id=cluster_id))
    end
end
println()

println("\nSecond pass for unmatched clusters...")
matched_set = Set{Int}()
for tr in thread_results
    for row in tr
        if !ismissing(row.B_id)
            push!(matched_set, row.cluster_id)
        end
    end
end
unmatched_clusters = Int[]
for cid in 1:length(comps_A)
    cid in matched_set && continue
    push!(unmatched_clusters, cid)
end

if !isempty(unmatched_clusters)
    println("  $(length(unmatched_clusters)) unmatched clusters, running second pass...")
    SIM_THRESHOLD_2 = 0.80

    block_to_B_expanded = Dict{String, Vector{Int}}()
    for i in 1:nB
        for bk in block_keys(norm_B[i])
            push!(get!(Vector{Int}, block_to_B_expanded, bk), i)
        end
        tokens_b = split(norm_B[i])
        sig_b = [t for t in tokens_b if !(t in SKIP_WORDS) && length(t) >= 2]
        for t in sig_b
            bk2 = first(t, 2)
            push!(get!(Vector{Int}, block_to_B_expanded, bk2), i)
        end
    end
    for (k, v) in block_to_B_expanded
        unique!(v)
    end

    n_unmatched = length(unmatched_clusters)
    step2 = max(1, n_unmatched ÷ 20)
    progress_counter2 = Atomic{Int}(0)

    thread_results_2 = [sizehint!(Vector{NamedTuple{(:A_id, :B_id, :cluster_id), Tuple{String, Union{String,Missing}, Int}}}(), n_unmatched ÷ nthreads() + 10) for _ in 1:nthreads()]

    @threads for uidx in 1:n_unmatched
        tid = threadid()
        cluster_id = unmatched_clusters[uidx]
        comp = comps_A[cluster_id]

        cnt = atomic_add!(progress_counter2, 1)
        cnt % step2 == 0 && print("\r  Second pass: $cnt / $n_unmatched")

        cluster_blocks = Set{String}()
        for i in comp
            for bk in block_keys_A[i]
                push!(cluster_blocks, bk)
            end
            tokens_i = split(norm_A[i])
            sig_i = [t for t in tokens_i if !(t in SKIP_WORDS) && length(t) >= 2]
            for t in sig_i
                push!(cluster_blocks, first(t, 2))
            end
        end

        candidate_B = Set{Int}()
        for bk in cluster_blocks
            haskey(block_to_B_expanded, bk) && union!(candidate_B, block_to_B_expanded[bk])
        end

        cluster_lt = ""
        for i in comp
            lt = legal_types_A[i]
            if !isempty(lt)
                cluster_lt = lt
                break
            end
        end

        filtered = Vector{Tuple{Int,Float64}}()
        for b in candidate_B
            if !isempty(cluster_lt) && !isempty(legal_types_B[b]) && cluster_lt != legal_types_B[b]
                continue
            end
            best_overlap = 0.0
            for a in comp
                ovlp = token_overlap(token_sets_A[a], token_sets_B[b])
                ovlp > best_overlap && (best_overlap = ovlp)
            end
            best_overlap >= 0.2 && push!(filtered, (b, best_overlap))
        end
        sort!(filtered, by = x -> x[2], rev = true)
        length(filtered) > MAX_CANDIDATES && resize!(filtered, MAX_CANDIDATES)

        best_b = nothing
        best_sim = SIM_THRESHOLD_2
        if !isempty(filtered)
            for (b, _) in filtered
                for a in comp
                    sim = hybrid_similarity_v2(token_sets_A[a], token_sets_B[b], token_vecs_A[a], token_vecs_B[b], trigrams_A[a], trigrams_B[b], idf_weights, norm_A[a], norm_B[b])
                    if sim > best_sim
                        best_sim = sim
                        best_b = b
                    end
                end
                best_sim >= 1.0 && break
            end
        end

        b_id = isnothing(best_b) ? missing : id_B[best_b]
        for a in comp
            push!(thread_results_2[tid], (A_id=id_A[a], B_id=b_id, cluster_id=cluster_id))
        end
    end
    println()

    second_pass_results = Dict{String, Union{String, Missing}}()
    for tr in thread_results_2
        for row in tr
            if !ismissing(row.B_id)
                second_pass_results[row.A_id] = row.B_id
            end
        end
    end

    for tr in thread_results
        for (ridx, row) in enumerate(tr)
            if ismissing(row.B_id) && haskey(second_pass_results, row.A_id)
                tr[ridx] = (A_id=row.A_id, B_id=second_pass_results[row.A_id], cluster_id=row.cluster_id)
            end
        end
    end

    newly_matched = length(second_pass_results)
    println("Second pass matched $newly_matched additional records")
end

result = save_progress(thread_results, "empresas_tgr.csv")

rm("matching_results_progress.csv"; force=true)


result.prop_tgr_id = ["E" * lpad(string(cid), 9, '0') for cid in result.cluster_id]

rename!(result, :A_id => :propietario, :B_id => :rut)
result.rut = [ismissing(r) ? "0-0" : r for r in result.rut]
select!(result, Not(:cluster_id))

CSV.write("empresas_tgr.csv", result; delim='|')

aws_client = conn_aws
aws_bucket = "landengines-data"
aws_file_name = "kg/empresas_tgr.csv"
local_file_name = "empresas_tgr.csv"
aws_julia.upload_csv_file_to_s3(aws_client, aws_bucket, aws_file_name, local_file_name)


matched = count(r -> r != "0-0", result.rut)
println("Done. Result: $(nrow(result)) rows, $matched matched ($(round(100*matched/nrow(result), digits=1))%)")
println("Saved to empresas_tgr.csv")