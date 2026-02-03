using Unicode
using Graphs
using LandValue, DotEnv, DataFrames

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

query = """
SELECT * FROM "iceberg_db"."datos_tgr"
ORDER BY propietario
"""
df = aws_julia.query_to_dataframe(query, database_name, athena_bucket, athena_output, athena_catalog_name, conn_aws)


# =========================
# PARAMETERS
# =========================
const SIM_THRESHOLD = 0.85

# =========================
# NAME NORMALIZATION
# =========================
function normalize_name(s::AbstractString)
    s = uppercase(s)
    s = Unicode.normalize(s, :NFD)
    s = replace(s, r"\p{Mn}" => "")
    s = replace(s, r"[^\w\s]" => " ")
    s = replace(s, r"\bSOCIEDAD ANONIMA\b" => "SA")
    s = replace(s, r"\bS A\b" => "SA")
    s = replace(s, r"\bLIMITADA\b" => "LTDA")
    s = replace(s, r"\bSOCIEDAD POR ACCIONES\b" => "SPA")
    s = replace(s, r"\s+" => " ")
    strip(s)
end

# =========================
# TOKEN SIMILARITY
# =========================
function token_jaccard(a::String, b::String)
    ta = Set(split(a))
    tb = Set(split(b))
    isempty(ta) || isempty(tb) ? 0.0 :
        length(intersect(ta, tb)) / length(union(ta, tb))
end

# =========================
# BLOCKING KEY
# =========================
function block_key(s::String)
    t = split(s)
    isempty(t) ? "" : t[1]
end

# =========================
# MAIN FUNCTION
# =========================
function link_companies(dfA::DataFrame, dfB::DataFrame)

    # --- normalize ---
    dfA = copy(dfA)
    dfB = copy(dfB)

    dfA.norm = normalize_name.(dfA.name)
    dfB.norm = normalize_name.(dfB.name)

    dfA.src .= :A
    dfB.src .= :B

    # --- unify ---
    dfU = vcat(
        dfA[:, [:id, :norm, :src]],
        dfB[:, [:id, :norm, :src]]
    )

    dfU.block = block_key.(dfU.norm)

    N = nrow(dfU)
    g = SimpleGraph(N)

    # --- edge generation (with B–B forbidden) ---
    for (_, grp) in pairs(groupby(dfU, :block))
        idx = grp.row
        for i = 1:length(idx)-1, j = i+1:length(idx)
            u, v = idx[i], idx[j]

            if dfU.src[u] == :B && dfU.src[v] == :B
                continue
            end

            sim = token_jaccard(dfU.norm[u], dfU.norm[v])
            sim ≥ SIM_THRESHOLD && add_edge!(g, u, v)
        end
    end

    # --- clustering ---
    comps = connected_components(g)

    # --- final A → B mapping ---
    result = DataFrame(A_id = Int[], B_id = Union{Int,Missing}[])

    for comp in comps
        b_nodes = [i for i in comp if dfU.src[i] == :B]

        if length(b_nodes) == 1
            b = b_nodes[1]
            for i in comp
                dfU.src[i] == :A &&
                    push!(result, (dfU.id[i], dfU.id[b]))
            end
        else
            # unresolved cluster (no B)
            for i in comp
                dfU.src[i] == :A &&
                    push!(result, (dfU.id[i], missing))
            end
        end
    end

    return result
end
