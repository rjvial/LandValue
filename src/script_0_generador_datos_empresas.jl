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
SELECT *
FROM (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY rut_sociedad_completo, razon_social_sociedad
               ORDER BY razon_social_sociedad
           ) AS rn
    FROM "iceberg_db"."empresas_consolidada"
) t
WHERE rn = 1
ORDER BY razon_social_sociedad;
"""
dfB = aws_julia.query_to_dataframe(query, database_name, athena_bucket, athena_output, athena_catalog_name, conn_aws)

# owner_type = "\'Person\'" 
# query = """
# SELECT propietario, tipo_propietario
# FROM datos_tgr
# WHERE tipo_propietario = $owner_type
# ORDER BY propietario;
# """
# dfC = aws_julia.query_to_dataframe(query, database_name, athena_bucket, athena_output, athena_catalog_name, conn_aws)

using DataFrames, Graphs, Unicode, CSV, Base.Threads

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION — tune these based on your review of diagnostics
# ═══════════════════════════════════════════════════════════════════════════════
const CONFIG = (
    cluster_threshold    = 0.88,

    match_high           = 0.92,
    match_medium         = 0.85,
    match_low            = 0.80, #0.75,

    match_second_pass    = 0.78, #0.72,

    max_block_size       = 2000,
    max_candidates       = 200,

    ambiguity_margin     = 0.05,

    min_length_ratio     = 0.3,

    legal_type_penalty   = 0.15,

    top_k_diagnostics    = 3,

    sig_token_match_threshold = 0.92,
    sig_unmatch_jw_threshold  = 0.85,
    min_soft_score_continue   = 0.5,
)

# ═══════════════════════════════════════════════════════════════════════════════
# NORMALIZATION
# ═══════════════════════════════════════════════════════════════════════════════

# Abbreviation rules: order matters — longer forms first
const ABBREVIATION_RULES = [
    r"\bSOCIEDAD POR ACCIONES\b"    => "SPA",
    r"\bSOCIEDAD ANONIMA\b"         => "SA",
    r"\bLEASING\s*HABITACIONAL\b"   => "LEASINGHAB",
    r"\bS A\b"                      => "SA",
    r"\bLIMITADA\b"                 => "LTDA",
    r"\bLIMITDA\b"                  => "LTDA",
    r"\bALTDA\b"                    => "LTDA",
    r"\bLIMITAD\b"                  => "LTDA",
    r"\bLIMITA\b"                   => "LTDA",
    r"\bLIMIT\b"                    => "LTDA",
    r"\bLIMI\b"                     => "LTDA",
    r"\bLIM\b"                      => "LTDA",
    r"\bLTD\b"                      => "LTDA",
    r"\bSP\b"                       => "SPA",
    r"\bSOCIED\b"                   => "SOCIEDAD",
    r"\bSOC\b"                      => "SOCIEDAD",
    r"\bINMOBILIARIO\b"             => "INMOBILIARIA",
    r"\bINMOBILIARIOS\b"            => "INMOBILIARIA",
    r"\bINMOBILIA\b"                => "INMOBILIARIA",
    r"\bINMOBIL\b"                  => "INMOBILIARIA",
    r"\bINMOB\b"                    => "INMOBILIARIA",
    r"\bVIV\b"                      => "VIVIENDAS",
    r"\bECONOMICAS\b"               => "ECONOMICA",
    r"\bECONO\b"                    => "ECONOMICA",
    r"\bECON\b"                     => "ECONOMICA",
    r"\bMETROPOLITANAS\b"           => "METROPOLITANA",
    r"\bINGENIEROS\b"               => "ING",
    r"\bINGENIERO\b"                => "ING",
    r"\bCIVILES\b"                  => "CIV",
    r"\bCIVIL\b"                    => "CIV",
    r"\bCIVI\b"                     => "CIV",
    r"\bASOCIADOS\b"                => "ASOC",
    r"\bASOCIADAS\b"                => "ASOC",
    r"\bASOCIAD\b"                  => "ASOC",
    r"\bUNIVERSIDAD\b"              => "UNIV",
    r"\bSANTIAGO\b"                 => "STGO",
    r"\bCOMPANY\b"                  => "CO",
    r"\bGENERAL\b"                  => "GRAL",
    r"\bINVERSIONES\b"              => "INV",
    r"\bINVERSION\b"                => "INV",
    r"\bINEVERSION\b"               => "INV",
    r"\bEMPRE\b"                    => "EMPRESA",
    r"\bEMP\b"                      => "EMPRESA",
    r"\bNACIONAL\b"                 => "NAC",
    r"\bNACIONA\b"                  => "NAC",
    r"\bCIA\b"                      => "COMPANIA",
    r"\bCI\b"                       => "COMPANIA",
    r"\bAND\b"                      => "Y",
    r"\bPROPIEDADES\b"              => "PROP",
    r"\bRENTAS\b"                   => "RENT",
    r"\bCORREDORES\b"               => "CORR",
    r"\bCORREDORA\b"                => "CORR",
    r"\bFINANCIERA\b"               => "FIN",
    r"\bTECNOLOGIA\b"               => "TEC",
    r"\bSOLUCIONES\b"               => "SOL",
    r"\bEIRL\b"                     => "EIRL",
    r"\bE I R L\b"                  => "EIRL",
]

function normalize_name(s::AbstractString)::String
    s = uppercase(strip(s))
    s = Unicode.normalize(s, :NFD)
    s = replace(s, r"\p{Mn}" => "")
    s = replace(s, 'Ñ' => 'N')
    s = replace(s, r"[ªº°]" => "")
    s = replace(s, r"[^\x00-\x7F]" => "")
    s = replace(s, "&" => " Y ")
    s = replace(s, r"[^\w\s]" => " ")

    for (pat, rep) in ABBREVIATION_RULES
        s = replace(s, pat => rep)
    end

    s = replace(s, r"\s+" => " ")
    # Collapse spaced single letters: "S P A" → "SPA"
    s = replace(s, r"\b([A-Z])\s+([A-Z])\s+([A-Z])\s+([A-Z])\b" => s"\1\2\3\4")
    s = replace(s, r"\b([A-Z])\s+([A-Z])\s+([A-Z])\b" => s"\1\2\3")
    s = replace(s, r"\b([A-Z])\s+([A-Z])\b" => s"\1\2")
    strip(s)
end

# ═══════════════════════════════════════════════════════════════════════════════
# SIMILARITY PRIMITIVES
# ═══════════════════════════════════════════════════════════════════════════════

const SKIP_WORDS = Set([
    "SOCIEDAD", "EMPRESA", "COMERCIAL", "SERVICIOS", "SA", "SPA", "LTDA",
    "LIMITADA", "Y", "DE", "LA", "EL", "LOS", "LAS", "E", "DEL",
    "INMOBILIARIA", "INMOBILIARIO", "ADMINISTRADORA", "ADMINISTRACION",
    "ASESORIAS", "ASESORIA", "GESTION", "GESTIONES", "DESARROLLO",
    "AGRICOLA", "CONSTRUCTORA", "CONSTRUCCIONES", "CONSULTORA",
    "CONSULTORES", "HOLDING", "CAPITAL", "GRUPO", "HERMANOS",
    "ABOGADOS", "PROFESIONALES", "INV", "INVER", "INVERSIONES",
    "SEGUROS", "SEGURO", "VIDA", "SALUD", "FONDO", "FONDOS",
    "CHILE", "CHILENA", "CHILENO", "GENERAL", "GRAL", "NACIONAL", "NAC",
    "INTERNACIONAL", "INTERAMERICANA", "PENSIONES", "PENSION",
    "PREVISION", "PREVISIONAL", "ASOC", "ASOCIACION", "COMPANIA",
])

"""Pre-processed record for efficient comparison."""
struct ProcessedRecord
    original::String          # original name from source
    norm::String              # normalized string
    tokens::Set{String}       # token set
    token_vec::Vector{String} # token vector (ordered)
    sig_tokens::Vector{String}# significant tokens only (not in SKIP_WORDS, len≥3)
    trigram_set::Set{String}  # character trigrams
    legal_type::String        # "SA", "SPA", "LTDA", or ""
    n_tokens::Int             # number of tokens
end

function process_record(original::AbstractString, norm::AbstractString)::ProcessedRecord
    tokens = Set{String}(split(norm))
    token_vec = String.(collect(tokens))
    sig = [t for t in token_vec if !(t in SKIP_WORDS) && length(t) >= 3]
    tri = _trigrams(norm)
    lt = _extract_legal_type(norm)
    ProcessedRecord(original, norm, tokens, token_vec, sig, tri, lt, length(token_vec))
end

function _extract_legal_type(s::AbstractString)::String
    s = strip(s)
    endswith(s, " SA") && return "SA"
    endswith(s, " SPA") && return "SPA"
    endswith(s, " LTDA") && return "LTDA"
    endswith(s, " EIRL") && return "EIRL"
    ""
end

function _trigrams(s::AbstractString)::Set{String}
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

function jaro_winkler(s1::AbstractString, s2::AbstractString; p::Float64=0.1)::Float64
    isempty(s1) && isempty(s2) && return 1.0
    (isempty(s1) || isempty(s2)) && return 0.0
    s1 == s2 && return 1.0

    c1, c2 = collect(s1), collect(s2)
    len1, len2 = length(c1), length(c2)

    # Early exit: if lengths are too different, score will be low
    ratio = min(len1, len2) / max(len1, len2)
    ratio < 0.4 && return 0.0

    match_dist = max(0, max(len1, len2) ÷ 2 - 1)
    s1m, s2m = falses(len1), falses(len2)
    matches = 0
    transpositions = 0

    @inbounds for i in 1:len1
        lo = max(1, i - match_dist)
        hi = min(len2, i + match_dist)
        for j in lo:hi
            s2m[j] && continue
            c1[i] != c2[j] && continue
            s1m[i] = s2m[j] = true
            matches += 1
            break
        end
    end
    matches == 0 && return 0.0

    k = 1
    @inbounds for i in 1:len1
        !s1m[i] && continue
        while !s2m[k]; k += 1; end
        c1[i] != c2[k] && (transpositions += 1)
        k += 1
    end

    jaro = (matches/len1 + matches/len2 + (matches - transpositions÷2)/matches) / 3.0
    prefix_len = 0
    @inbounds for i in 1:min(4, len1, len2)
        c1[i] == c2[i] ? (prefix_len += 1) : break
    end
    jaro + prefix_len * p * (1.0 - jaro)
end

function trigram_jaccard(t1::Set{String}, t2::Set{String})::Float64
    (isempty(t1) || isempty(t2)) && return 0.0
    n_inter = length(intersect(t1, t2))
    n_inter / (length(t1) + length(t2) - n_inter)
end

function token_overlap(ta::Set, tb::Set)::Float64
    (isempty(ta) || isempty(tb)) && return 0.0
    length(intersect(ta, tb)) / min(length(ta), length(tb))
end

# ═══════════════════════════════════════════════════════════════════════════════
# IMPROVED SIMILARITY: directional soft match + asymmetric penalty
# ═══════════════════════════════════════════════════════════════════════════════

"""
Directional soft token similarity: for each token in `from`, find best match in `to`.
Returns (avg_score, n_unmatched) where unmatched means best_jw < 0.8.
"""
function directional_soft_match(from::Vector{String}, to::Vector{String})
    n = length(from)
    n == 0 && return (0.0, 0)
    total = 0.0
    unmatched = 0
    @inbounds for i in 1:n
        ta = from[i]
        best = 0.0
        for j in 1:length(to)
            tb = to[j]
            ta == tb && (best = 1.0; break)
            s = jaro_winkler(ta, tb)
            s > best && (best = s)
        end
        total += best
        best < 0.8 && (unmatched += 1)
    end
    (total / n, unmatched)
end

"""
Asymmetric soft similarity: penalizes when significant tokens in A are absent from B.
This prevents "CONSTRUCTORA ACME" from matching "ACME INVERSIONES CHILE SA" at high score
when the distinctive word "CONSTRUCTORA" has no counterpart.
"""
function soft_token_similarity_v2(a::ProcessedRecord, b::ProcessedRecord)::Float64
    (isempty(a.token_vec) || isempty(b.token_vec)) && return 0.0

    score_ab, unmatch_ab = directional_soft_match(a.token_vec, b.token_vec)
    score_ba, unmatch_ba = directional_soft_match(b.token_vec, a.token_vec)
    base = min(score_ab, score_ba)

    # Penalty for significant tokens in A not found in B (or vice versa)
    sig_unmatch_a = count(t -> !any(u -> t == u || jaro_winkler(t, u) >= CONFIG.sig_unmatch_jw_threshold, b.token_vec), a.sig_tokens)
    sig_unmatch_b = count(t -> !any(u -> t == u || jaro_winkler(t, u) >= CONFIG.sig_unmatch_jw_threshold, a.token_vec), b.sig_tokens)
    max_sig = max(length(a.sig_tokens), length(b.sig_tokens))
    sig_penalty = max_sig > 0 ? 0.15 * (sig_unmatch_a + sig_unmatch_b) / (2 * max_sig) : 0.0

    max(0.0, base - sig_penalty)
end

# ═══════════════════════════════════════════════════════════════════════════════
# COMPOSITE SIMILARITY FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

function compute_idf(records_a::Vector{ProcessedRecord}, records_b::Vector{ProcessedRecord})::Dict{String,Float64}
    doc_freq = Dict{String,Int}()
    n_total = length(records_a) + length(records_b)
    for r in records_a
        for t in r.tokens
            doc_freq[t] = get(doc_freq, t, 0) + 1
        end
    end
    for r in records_b
        for t in r.tokens
            doc_freq[t] = get(doc_freq, t, 0) + 1
        end
    end
    Dict(term => log(n_total / df) for (term, df) in doc_freq)
end

function tfidf_overlap(ta::Set, tb::Set, idf::Dict{String,Float64})::Float64
    (isempty(ta) || isempty(tb)) && return 0.0
    common = intersect(ta, tb)
    isempty(common) && return 0.0
    common_w = sum(get(idf, t, 1.0) for t in common)
    smaller = length(ta) < length(tb) ? ta : tb
    total_w = sum(get(idf, t, 1.0) for t in smaller)
    total_w > 0 ? common_w / total_w : 0.0
end

"""
Full similarity score between two records.
Returns a score in [0, 1] with penalties applied.
"""
function full_similarity(a::ProcessedRecord, b::ProcessedRecord, idf::Dict{String,Float64})::Float64
    # Length ratio guard
    ratio = min(a.n_tokens, b.n_tokens) / max(a.n_tokens, b.n_tokens)
    ratio < CONFIG.min_length_ratio && return 0.0

    # Component scores
    s_tfidf   = tfidf_overlap(a.tokens, b.tokens, idf)
    s_soft    = soft_token_similarity_v2(a, b)
    s_trigram = trigram_jaccard(a.trigram_set, b.trigram_set)
    s_jw      = jaro_winkler(a.norm, b.norm)

    # Weighted combination
    score = 0.30 * s_tfidf + 0.30 * s_soft + 0.20 * s_trigram + 0.20 * s_jw

    # Legal type soft penalty (instead of hard filter)
    if !isempty(a.legal_type) && !isempty(b.legal_type) && a.legal_type != b.legal_type
        score -= CONFIG.legal_type_penalty
    end

    max(0.0, score)
end

function _has_sig_token_match(a::ProcessedRecord, b::ProcessedRecord)::Bool
    for ta in a.sig_tokens, tb in b.sig_tokens
        (ta == tb || jaro_winkler(ta, tb) >= CONFIG.sig_token_match_threshold) && return true
    end
    false
end

"""Fast pre-filter similarity for Phase 1 (A-A clustering)."""
function fast_similarity_v2(a::ProcessedRecord, b::ProcessedRecord)::Float64
    !_has_sig_token_match(a, b) && return 0.0

    s_soft = soft_token_similarity_v2(a, b)
    s_soft < CONFIG.min_soft_score_continue && return s_soft
    s_tri = trigram_jaccard(a.trigram_set, b.trigram_set)
    0.7 * s_soft + 0.3 * s_tri
end

# ═══════════════════════════════════════════════════════════════════════════════
# BLOCKING (improved: multi-strategy)
# ═══════════════════════════════════════════════════════════════════════════════

"""
Generate block keys for a record. Multiple strategies for better recall:
1. Prefix-3 and prefix-5 of significant tokens
2. First 2 chars of each significant token
3. Sorted bigram of first 2 significant tokens (catches reorderings)
"""
function generate_block_keys(r::ProcessedRecord)::Vector{String}
    keys = String[]

    for t in r.sig_tokens
        push!(keys, "P3:" * first(t, min(3, length(t))))
        length(t) >= 5 && push!(keys, "P5:" * first(t, 5))
        length(t) >= 2 && push!(keys, "P2:" * first(t, 2))
    end

    # Sorted pair key for the first 2 significant tokens → catches reorderings
    if length(r.sig_tokens) >= 2
        pair = sort(r.sig_tokens[1:2])
        push!(keys, "PAIR:" * first(pair[1], min(3, length(pair[1]))) * "+" * first(pair[2], min(3, length(pair[2]))))
    end

    unique!(keys)
end

function build_block_index(records::Vector{ProcessedRecord}, max_block::Int)::Dict{String,Vector{Int}}
    idx = Dict{String,Vector{Int}}()
    for i in eachindex(records)
        for bk in generate_block_keys(records[i])
            push!(get!(Vector{Int}, idx, bk), i)
        end
    end
    # Prune oversized blocks but DON'T empty them — sample instead
    for (k, v) in idx
        if length(v) > max_block
            # Keep a random sample instead of dropping entirely
            shuffle_indices = sortperm(rand(length(v)))
            idx[k] = v[shuffle_indices[1:max_block]]
        end
    end
    idx
end

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIDENCE CLASSIFICATION
# ═══════════════════════════════════════════════════════════════════════════════

function classify_confidence(score::Float64, margin::Float64, is_ambiguous::Bool)::String
    score >= CONFIG.match_high && !is_ambiguous && return "HIGH"
    score >= CONFIG.match_medium && return "MEDIUM"
    score >= CONFIG.match_low && return "LOW"
    "NONE"
end

# ═══════════════════════════════════════════════════════════════════════════════
# MATCH RESULT TYPE
# ═══════════════════════════════════════════════════════════════════════════════

struct MatchResult
    a_id::String
    b_id::Union{String,Missing}
    cluster_id::Int
    score::Float64
    confidence::String
    margin::Float64          # gap between best and second-best
    is_ambiguous::Bool
    best_b_name::String      # for diagnostics
    second_b_id::Union{String,Missing}
    second_b_score::Float64
end

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 1: CLUSTER A INTERNALLY
# ═══════════════════════════════════════════════════════════════════════════════

function cluster_records(records::Vector{ProcessedRecord}; threshold::Float64)
    n = length(records)
    println("  Building block index for clustering...")
    block_idx = build_block_index(records, CONFIG.max_block_size)

    println("  Finding similar pairs ($(nthreads()) threads)...")
    blocks_vec = [(bk, rows) for (bk, rows) in block_idx if length(rows) >= 2]
    sort!(blocks_vec, by = x -> length(x[2]), rev = true)

    thread_edges = [Vector{Tuple{Int,Int}}() for _ in 1:nthreads()]
    thread_seen = [Set{UInt64}() for _ in 1:nthreads()]
    thread_comps = zeros(Int, nthreads())

    @threads for bidx in eachindex(blocks_vec)
        tid = threadid()
        (_, rows) = blocks_vec[bidx]
        seen = thread_seen[tid]
        edges = thread_edges[tid]

        for i in 1:length(rows)-1
            u = rows[i]
            for j in i+1:length(rows)
                v = rows[j]
                # Cantor pairing for fast hash
                pair_hash = u < v ? UInt64(u) * UInt64(n) + UInt64(v) : UInt64(v) * UInt64(n) + UInt64(u)
                pair_hash in seen && continue
                push!(seen, pair_hash)

                ru, rv = records[u], records[v]
                # Legal type hard filter in clustering (same entity, should match type)
                (!isempty(ru.legal_type) && !isempty(rv.legal_type) && ru.legal_type != rv.legal_type) && continue

                thread_comps[tid] += 1
                sim = fast_similarity_v2(ru, rv)
                sim >= threshold && push!(edges, (u, v))
            end
        end
    end

    g = SimpleGraph(n)
    for edges in thread_edges
        for (u, v) in edges
            add_edge!(g, u, v)
        end
    end
    total_comps = sum(thread_comps)
    println("  Comparisons: $total_comps | Edges: $(ne(g))")

    comps = connected_components(g)
    println("  Clusters: $(length(comps))")
    comps
end

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 2: MATCH A-CLUSTERS → B
# ═══════════════════════════════════════════════════════════════════════════════

function match_clusters_to_b(
    comps::Vector{Vector{Int}},
    records_a::Vector{ProcessedRecord},
    records_b::Vector{ProcessedRecord},
    ids_a::Vector{String},
    ids_b::Vector{String},
    idf::Dict{String,Float64};
    min_threshold::Float64,
    fast_overlap_threshold::Float64 = 0.25,
    pass_name::String = "Primary"
)
    n_clusters = length(comps)
    println("  Building B block index...")
    block_idx_b = build_block_index(records_b, CONFIG.max_block_size * 2)

    println("  Pre-computing A block keys...")
    block_keys_a = [generate_block_keys(r) for r in records_a]

    println("  Matching $n_clusters clusters ($pass_name, $(nthreads()) threads)...")
    step = max(1, n_clusters ÷ 20)

    thread_results = [Vector{MatchResult}() for _ in 1:nthreads()]
    thread_diag = [Vector{NamedTuple{(:cluster_id, :rank, :b_id, :b_name, :score), Tuple{Int,Int,String,String,Float64}}}() for _ in 1:nthreads()]
    progress = Atomic{Int}(0)

    # Sort clusters largest-first for better load balancing
    cluster_order = sortperm(comps, by = length, rev = true)

    @threads for idx in 1:n_clusters
        tid = threadid()
        cid = cluster_order[idx]
        comp = comps[cid]

        cnt = atomic_add!(progress, 1)
        cnt % step == 0 && print("\r    $pass_name: $cnt / $n_clusters")

        # Gather candidate B records via blocking
        candidate_b = Set{Int}()
        for a_idx in comp
            for bk in block_keys_a[a_idx]
                haskey(block_idx_b, bk) && union!(candidate_b, block_idx_b[bk])
            end
        end

        # Cluster legal type
        cluster_lt = ""
        for a_idx in comp
            lt = records_a[a_idx].legal_type
            if !isempty(lt); cluster_lt = lt; break; end
        end

        # Fast pre-filter: token overlap
        filtered = Vector{Tuple{Int,Float64}}()
        sizehint!(filtered, min(length(candidate_b), CONFIG.max_candidates))
        for b in candidate_b
            best_overlap = 0.0
            for a in comp
                ovlp = token_overlap(records_a[a].tokens, records_b[b].tokens)
                ovlp > best_overlap && (best_overlap = ovlp)
            end
            best_overlap >= fast_overlap_threshold && push!(filtered, (b, best_overlap))
        end
        sort!(filtered, by = x -> x[2], rev = true)
        length(filtered) > CONFIG.max_candidates && resize!(filtered, CONFIG.max_candidates)

        # Full similarity: track top-2 and store all scores for diagnostics
        best_b = nothing
        best_sim = 0.0
        second_b = nothing
        second_sim = 0.0
        all_scores = Vector{Tuple{Int,Float64}}()
        sizehint!(all_scores, length(filtered))

        for (b, _) in filtered
            max_sim_for_b = 0.0
            for a in comp
                sim = full_similarity(records_a[a], records_b[b], idf)
                sim > max_sim_for_b && (max_sim_for_b = sim)
            end
            push!(all_scores, (b, max_sim_for_b))
            if max_sim_for_b > best_sim
                second_b = best_b
                second_sim = best_sim
                best_b = b
                best_sim = max_sim_for_b
            elseif max_sim_for_b > second_sim
                second_b = b
                second_sim = max_sim_for_b
            end
        end

        # Diagnostics: top-K candidates (reuse already computed scores)
        if !isempty(all_scores)
            sort!(all_scores, by = x -> x[2], rev = true)
            for (rank, (b, sc)) in enumerate(all_scores[1:min(length(all_scores), CONFIG.top_k_diagnostics)])
                push!(thread_diag[tid], (
                    cluster_id = cid,
                    rank = rank,
                    b_id = ids_b[b],
                    b_name = records_b[b].original,
                    score = round(sc, digits=4)
                ))
            end
        end

        # Build results
        margin = best_sim - second_sim
        is_ambiguous = !isnothing(second_b) && margin < CONFIG.ambiguity_margin && best_sim >= min_threshold
        matched = best_sim >= min_threshold

        b_id = matched ? ids_b[best_b] : missing
        b_name = matched ? records_b[best_b].original : ""
        s_b_id = (is_ambiguous && !isnothing(second_b)) ? ids_b[second_b] : missing
        conf = matched ? classify_confidence(best_sim, margin, is_ambiguous) : "NONE"

        for a in comp
            push!(thread_results[tid], MatchResult(
                ids_a[a], b_id, cid,
                round(best_sim, digits=4), conf, round(margin, digits=4),
                is_ambiguous, b_name, s_b_id, round(second_sim, digits=4)
            ))
        end
    end
    println()

    # Merge results
    results = MatchResult[]
    for tr in thread_results; append!(results, tr); end

    diag = NamedTuple{(:cluster_id, :rank, :b_id, :b_name, :score), Tuple{Int,Int,String,String,Float64}}[]
    for td in thread_diag; append!(diag, td); end

    (results, diag)
end

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN PIPELINE
# ═══════════════════════════════════════════════════════════════════════════════

function run_matching_pipeline(dfA::DataFrame, dfB::DataFrame; progress_callback::Union{Nothing,Function}=nothing)
    t0 = time()

    _log(msg) = isnothing(progress_callback) ? println(msg) : progress_callback(msg)

    :propietario in propertynames(dfA) || error("dfA must have column :propietario")
    :razon_social_sociedad in propertynames(dfB) || error("dfB must have column :razon_social_sociedad")
    :rut_sociedad_completo in propertynames(dfB) || error("dfB must have column :rut_sociedad_completo")

    _log("═══ PHASE 0: Preparing data ═══")
    dfA = copy(dfA)
    dfB = copy(dfB)
    dropmissing!(dfA, :propietario)
    dropmissing!(dfB, :razon_social_sociedad)
    filter!(row -> row.razon_social_sociedad != "", dfB)

    nA, nB = nrow(dfA), nrow(dfB)
    _log("  Records: A=$nA, B=$nB")

    _log("  Normalizing names...")
    norm_a = normalize_name.(dfA.propietario)
    norm_b = normalize_name.(dfB.razon_social_sociedad)

    _log("  Processing records...")
    records_a = [process_record(dfA.propietario[i], norm_a[i]) for i in 1:nA]
    records_b = [process_record(dfB.razon_social_sociedad[i], norm_b[i]) for i in 1:nB]

    ids_a = Vector{String}(dfA.propietario)
    ids_b = Vector{String}(dfB.rut_sociedad_completo)

    _log("  Computing IDF weights...")
    idf = compute_idf(records_a, records_b)

    _log("\n═══ PHASE 1: Clustering A records ═══")
    comps = cluster_records(records_a; threshold=CONFIG.cluster_threshold)

    _log("\n═══ PHASE 2: Primary matching (threshold=$(CONFIG.match_low)) ═══")
    results, diag = match_clusters_to_b(
        comps, records_a, records_b, ids_a, ids_b, idf;
        min_threshold = CONFIG.match_low,
        fast_overlap_threshold = 0.25,
        pass_name = "Primary"
    )

    # --- Phase 3: Second pass for unmatched ---
    matched_clusters = Set(r.cluster_id for r in results if !ismissing(r.b_id))
    unmatched_cids = [i for i in 1:length(comps) if !(i in matched_clusters)]

    if !isempty(unmatched_cids)
        _log("\n═══ PHASE 3: Second pass ($(length(unmatched_cids)) unmatched clusters, threshold=$(CONFIG.match_second_pass)) ═══")
        unmatched_comps = comps[unmatched_cids]

        # Remap IDs for the subset
        a_indices_in_unmatched = vcat(unmatched_comps...)
        unmatched_records_a = records_a  # keep full array, comps index into it
        # We pass the full comps subset; they still index into the original records_a

        results_2, diag_2 = match_clusters_to_b(
            unmatched_comps, records_a, records_b, ids_a, ids_b, idf;
            min_threshold = CONFIG.match_second_pass,
            fast_overlap_threshold = 0.15,
            pass_name = "Second pass"
        )

        # Merge second-pass results: update unmatched entries
        second_pass_map = Dict{String, MatchResult}()
        for r in results_2
            !ismissing(r.b_id) && (second_pass_map[r.a_id] = r)
        end

        for (i, r) in enumerate(results)
            if ismissing(r.b_id) && haskey(second_pass_map, r.a_id)
                results[i] = second_pass_map[r.a_id]
            end
        end

        append!(diag, diag_2)
        _log("  Second pass matched $(length(second_pass_map)) additional records")
    end

    _log("\n═══ PHASE 4: Building output ═══")
    sort!(results, by = r -> r.cluster_id)

    df_out = DataFrame(
        propietario      = [r.a_id for r in results],
        rut              = [ismissing(r.b_id) ? "0-0" : r.b_id for r in results],
        prop_tgr_id      = ["E" * lpad(string(r.cluster_id), 9, '0') for r in results],
        match_score      = [r.score for r in results],
        confidence       = [r.confidence for r in results],
        margin           = [r.margin for r in results],
        is_ambiguous     = [r.is_ambiguous for r in results],
        matched_name     = [r.best_b_name for r in results],
        second_best_rut  = [ismissing(r.second_b_id) ? "" : r.second_b_id for r in results],
        second_best_score = [r.second_b_score for r in results],
    )

    # Diagnostics DataFrame
    df_diag = DataFrame(diag)
    if nrow(df_diag) > 0
        sort!(df_diag, [:cluster_id, :rank])
    end

    # --- Save ---
    CSV.write("rel_prop_tgr_id_to_rut.csv", unique(select(df_out, :prop_tgr_id, :rut), [:prop_tgr_id, :rut]); delim='|')
    CSV.write("empresas_tgr.csv", select(df_out, :propietario, :prop_tgr_id, :rut); delim='|')
    CSV.write("empresas_tgr_full.csv", df_out; delim='|')
    CSV.write("empresas_tgr_diagnostics.csv", df_diag; delim='|')

    # --- Stats ---
    elapsed = round(time() - t0, digits=1)
    matched = count(r -> r != "0-0", df_out.rut)
    high   = count(r -> r == "HIGH", df_out.confidence)
    medium = count(r -> r == "MEDIUM", df_out.confidence)
    low    = count(r -> r == "LOW", df_out.confidence)
    ambig  = count(r -> r, df_out.is_ambiguous)
    unmatched = nrow(df_out) - matched

    _log("\n═══════════════════════════════════════")
    _log("  RESULTS SUMMARY")
    _log("═══════════════════════════════════════")
    _log("  Total records:     $(nrow(df_out))")
    _log("  Matched:           $matched ($(round(100*matched/nrow(df_out), digits=1))%)")
    _log("    HIGH confidence: $high")
    _log("    MEDIUM:          $medium")
    _log("    LOW:             $low")
    _log("  Ambiguous:         $ambig (margin < $(CONFIG.ambiguity_margin))")
    _log("  Unmatched:         $unmatched")
    _log("  Clusters:          $(length(comps))")
    _log("  Elapsed:           $(elapsed)s")
    _log("═══════════════════════════════════════")
    _log("\nFiles saved:")
    _log("  rel_prop_tgr_id_to_rut.csv        — relation table (prop_tgr_id|rut)")
    _log("  empresas_tgr.csv                  — (propietario|prop_tgr_id|rut)")
    _log("  empresas_tgr_full.csv             — with scores, confidence, ambiguity flags")
    _log("  empresas_tgr_diagnostics.csv      — top-$(CONFIG.top_k_diagnostics) candidates per cluster for review")


    df_out
end

# ═══════════════════════════════════════════════════════════════════════════════
# RUN
# ═══════════════════════════════════════════════════════════════════════════════
# Uncomment the line below to execute. Make sure dfA and dfB are loaded first.
result = run_matching_pipeline(dfA, dfB)

df_sii = rename(copy(dfB), :rut_sociedad_completo => :rut)
for col in names(df_sii, Union{Missing, AbstractString})
    df_sii[!, col] = replace.(coalesce.(df_sii[!, col], ""), "\"" => "")
end
CSV.write("empresas_sii.csv", df_sii; delim='|')

aws_julia.upload_csv_file_to_s3(conn_aws, "landengines-data", "kg/rel_prop_tgr_id_to_rut.csv", "rel_prop_tgr_id_to_rut.csv")
aws_julia.upload_csv_file_to_s3(conn_aws, "landengines-data", "kg/empresas_tgr.csv", "empresas_tgr.csv")
aws_julia.upload_csv_file_to_s3(conn_aws, "landengines-data", "kg/empresas_sii.csv", "empresas_sii.csv")