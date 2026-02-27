
using LandValue, DotEnv, OrderedCollections, DataFrames, JuMP, HiGHS, Statistics, CSV, Plots

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


struct StrategicPowerData
    num_predios::Int
    num_combies::Int
    A::Matrix{Int} # Incidence [ predios x combies ]
    v::Vector{Float64} # Combi values
end

function compute_bypassability(p::Int, data) :: Float64
    A = data.A
    Cp = [c for c in 1:data.num_combies if A[p, c] == 1]
    Cnotp = [c for c in 1:data.num_combies if A[p, c] == 0]
    isempty(Cp) && return 0.0
    isempty(Cnotp) && return 0.0
    beta = 0.0
    for c in Cnotp
        blocked = count(cp -> any((A[:, c] .& A[:, cp]) .> 0), Cp)
        beta = max(beta, blocked/length(Cp) )
    end
    return beta
end

function compute_value_weighted_bypassability(p::Int, data)::Float64
    A, v = data.A, data.v
    Cp = [c for c in 1: data.num_combies if A[p, c] == 1]
    Cnotp = [c for c in 1: data.num_combies if A[p, c] == 0]
    isempty(Cp) && return 0.0
    total_p_value = sum(v[c] for c in Cp)
    total_p_value == 0.0 && return 0.0
    beta_v = 0.0
    for c in Cnotp
        blocked_val = sum((v[cp] for cp in Cp if any((A[:, c] .& A[:, cp]) .> 0)), init=0.0)
        beta_v = max(beta_v, blocked_val / total_p_value)
    end
    return beta_v
end

function compute_V(data; forbidden_predios = Int[])::Float64
    A, v = data.A , data.v
    P, C = data.num_predios, data.num_combies
    model = Model(HiGHS.Optimizer )
    set_silent(model)
    @variable(model, x[1:C], Bin)
    # Forbid combies containing forbidden predios
    for p in forbidden_predios, c in 1:C
        A[p, c] == 1 && @constraint(model, x[c] == 0)
    end
    # Set packing : each predio used at most once
    for p in 1:P
        p in forbidden_predios && continue
        @constraint(model, sum(A[p, c]*x[c] for c in 1:C) <= 1)
    end
    @objective(model, Max, sum(v[c]*x[c] for c in 1:C))
    optimize!(model)
    return objective_value(model)
end
function compute_SP(p::Int, data, V::Float64)::Float64
    V_minus_p = compute_V(data; forbidden_predios = [p])
    return V - V_minus_p
end
function compute_relative_strategic_power(data)
    P = data.num_predios
    P <= 1 && return zeros(P)
    V = compute_V(data)
    SP = [compute_SP(p, data, V) for p in 1:P]
    # SP_norm = [compute_SP(p, data, V) / V for p in 1:P]
    RSP = zeros(P)
    for p in 1:P
        others = [SP[q] for q in 1:P if q != p]
        RSP[p] = SP[p] - median(others)
    end
    return RSP
end


min_rectangularity = 0.95

query = """
MATCH (m:Manzana)-[]-(p:Predio)-[]-(c:Combi) 
WHERE c.rectangularity >= $(min_rectangularity)
RETURN DISTINCT c.manzent as manzent, c.id_combi as id_combi, p.codigo_predial as codigo_predial, p.sup_terreno_sii as sup_terreno_sii 
ORDER BY manzent, id_combi, codigo_predial
"""
df_predios_combis = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)
unique_manzanas = sort(unique(df_predios_combis.manzent))
num_manzanas = length(unique_manzanas)

df_resultados = DataFrame(codigo_predial=Int[], manzent=Int[], bypassability=Float64[], strategic_power=Float64[])

# Loop over each manzana
for i_m in eachindex(unique_manzanas)
    
    println("Manzana: $(unique_manzanas[i_m]), Index: $(i_m) / $(num_manzanas)")

    df_predios_m = df_predios_combis[df_predios_combis.manzent .== unique_manzanas[i_m], :]
    unique_combis_m = unique(df_predios_m.id_combi)
    num_combis_m = length(unique_combis_m)
    unique_predios_m = unique(df_predios_m.codigo_predial)
    num_predios_m = length(unique_predios_m)

    A_m = zeros(Int, num_predios_m, num_combis_m)
    for row in eachrow(df_predios_m)
        i_p = findfirst(==(row.codigo_predial), unique_predios_m)
        i_c = findfirst(==(row.id_combi), unique_combis_m)
        A_m[i_p, i_c] = 1
    end

    sup_predios = [df_predios_m[findfirst(==(cod), df_predios_m.codigo_predial), :sup_terreno_sii] for cod in unique_predios_m]
    v = vec(sup_predios' * A_m)
    data_m = StrategicPowerData(num_predios_m, num_combis_m, A_m, v)

    bypassability = [compute_value_weighted_bypassability(p, data_m) for p in 1:data_m.num_predios]
    strategic_power = compute_relative_strategic_power(data_m)

    for (i_p, cod) in enumerate(unique_predios_m)
        println("Predio: $(cod); bypassability: $(bypassability[i_p]); strategic_power: $(strategic_power[i_p])")
        push!(df_resultados, (cod, unique_manzanas[i_m], bypassability[i_p], strategic_power[i_p]))
    end

end

CSV.write("resultados_strategic_power.csv", df_resultados, delim='|')

scatter(df_resultados.bypassability, df_resultados.strategic_power,
    xlabel="bypassability", ylabel="Strategic Power",
    title="bypassability vs Strategic Power",
    legend=false, markersize=3, alpha=0.6)

