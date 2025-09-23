################################################################################
#                    SCRIPT 2A - VOLUMETRIC OPTIMIZATION                     #
################################################################################

using LandValue, DotEnv, LinearAlgebra, OrderedCollections, Distributed, DataFrames

################################################################################
#                        DATABASE CONNECTION SETUP                           #
################################################################################

@everywhere function setup_database_connections(my_env)
    max_retries = 3
    retry_delay = 2.0

    for attempt in 1:max_retries
        try
            conn_aws = aws_julia.connection(my_env["AWS_ACCESS_KEY"], my_env["AWS_SECRET_KEY"], my_env["AWS_REGION"])

            neo4j_host = "bolt://localhost:7687"
            neo4j_user = "neo4j"
            neo4j_password = "x67y1332"
            key_pair = "neo4j-key-pair.pem"
            ec2_user = "ec2-user"

            # Retry EC2 DNS lookup
            public_dns = nothing
            for dns_attempt in 1:3
                try
                    public_dns = aws_julia.find_instance_by_name("Neo4j-EC2", conn_aws)["dnsName"]
                    break
                catch e
                    if dns_attempt == 3
                        rethrow(e)
                    end
                    @warn "Worker $(myid()) DNS lookup attempt $dns_attempt failed: $e"
                    sleep(1.0)
                end
            end

            folder = "/usr/bin/cypher-shell"
            conn_neo4j = neo4j_julia.connection(neo4j_host, neo4j_user, neo4j_password, folder, key_pair, ec2_user, public_dns)

            # Retry Postgres connection
            pg_public_dns = aws_julia.find_instance_by_name("Postgres-EC2", conn_aws)["dnsName"]
            conn_postgres = pg_julia.connection("landengines", my_env["PG_AWS_USER"], my_env["PG_AWS_PASSWORD"], pg_public_dns)

            # Test connections
            try
                pg_julia.query(conn_postgres, "SELECT 1")
            catch e
                @warn "Worker $(myid()) Postgres connection test failed: $e"
                pg_julia.close_db(conn_postgres)
                throw(e)
            end

            println("Worker $(myid()) database connections established successfully")
            return conn_neo4j, conn_postgres

        catch e
            @warn "Worker $(myid()) database connection attempt $attempt failed: $e"
            if attempt == max_retries
                error("Failed to establish database connections after $max_retries attempts: $e")
            end
            sleep(retry_delay * attempt)
        end
    end
end

function main()
    # Main process connections
    global my_env = DotEnv.config("secrets.env")
    global conn_aws = aws_julia.connection(my_env["AWS_ACCESS_KEY"], my_env["AWS_SECRET_KEY"], my_env["AWS_REGION"])
    global conn_neo4j, conn_postgres = setup_database_connections(my_env)

    ################################################################################
    #                         3D VISUALIZATION SETTINGS                          #
    ################################################################################

    global fpe = FlagPlotEdif3D()
    fpe.predio = true
    fpe.volTeorico = true
    fpe.volConSombra = true
    fpe.edif = true
    fpe.sombraVolTeorico_p = true
    fpe.sombraVolTeorico_o = true
    fpe.sombraVolTeorico_s = true
    fpe.sombraEdif_p = true
    fpe.sombraEdif_o = true
    fpe.sombraEdif_s = true

    global worker_ids = setup_workers()

    # Load optimization data after worker setup
    global df_instancias, df_combis, df_combined = load_optimization_data(conn_postgres, conn_neo4j)

    global num_instancias = size(df_instancias, 1)
    global jobs, results = create_optimized_channels(num_instancias, length(worker_ids))

    # Execute the optimization
    success_count, fail_count, total_time = execute_parallel_optimization()

    return success_count, fail_count, total_time
end

################################################################################
#                          HELPER FUNCTIONS                                  #
################################################################################

@everywhere function handle_optimization_error(conn_postgres, id_opti, error_msg, error)
    println("$error_msg for ID $id_opti: $error")
    update_query = """
    UPDATE public.tabla_instancias_optimizacion
    SET status = -1
    WHERE id_opti = $id_opti
    """
    pg_julia.query(conn_postgres, update_query)
end

@everywhere function update_optimization_status(conn_postgres, id_opti, status)
    update_query = """
    UPDATE public.tabla_instancias_optimizacion
    SET status = $status
    WHERE id_opti = $id_opti
    """
    pg_julia.query(conn_postgres, update_query)
end

@everywhere function process_geometry_for_combi(df_combined_row, id_combi)
    try
        return safe_obtiene_geometrias_combi(df_combined_row), true, nothing
    catch e
        return nothing, false, e
    end
end

@everywhere function run_single_optimization(dict_geom, dict_arquitectura, dict_requerimientos, id_opti, id_combi)
    try
        dict_resultados, dict_proyecto_vs_normativa = opti_edificio(dict_geom, dict_arquitectura, dict_requerimientos, id_opti, id_combi)
        return (dict_resultados, dict_proyecto_vs_normativa), true, nothing
    catch e
        return (nothing, nothing), false, e
    end
end

function juliaTypeToPgType(juliaType::Type)
    if juliaType <: Integer
        return "int4"
    elseif juliaType <: AbstractFloat
        return "numeric(10,2)"
    elseif juliaType <: AbstractString
        return "text"
    elseif juliaType <: Bool
        return "boolean"
    else
        return "text"
    end
end

function dict2tablevec(dict, primaryKeyStr::String="id")
    vecColumnNames = [string(k) for k in keys(dict)]
    if !(primaryKeyStr in vecColumnNames)
        push!(vecColumnNames, primaryKeyStr)
    end
    vecColumnTypes = [juliaTypeToPgType(typeof(haskey(dict, col) ? dict[col] : 1)) for col in vecColumnNames]
    return vecColumnNames, vecColumnTypes
end

@everywhere function processValue(value, dict_geom)
    if typeof(value) == Bool
        return value ? 1 : 0
    elseif isa(value, Tuple)
        tuple_str = string(value)
        tuple_str = replace(tuple_str, r"[\"'\[\](){}]" => " ")
        return strip(tuple_str)
    else
        return value
    end
end

@everywhere function createArchitectureDict(variante_norm)
    return OrderedDict(
        "arq_alturaPiso" => 2.55,
        "arq_K" => 1,
        "arq_ancho_crujia_min" => 8,
        "arq_ancho_crujia_max" => 18,
        "arq_tipo_edificio" => "departamento",
        "arq_flag_sombra" => true,
        "arq_flag_vano" => false,
        "arq_vecSupInterior" => [25, 65, 85, 120, 240],
        "arq_vecSupTerraza" => [10, 20, 30, 40, 40],
        "arq_vecSupUtil" => [30, 75, 100, 140, 260],
        "arq_supPorEstacionamiento" => 30,
        "arq_supPorBodega" => 5,
        "arq_supPorBicicleta" => 4,
        "arq_coefSupComunPrimerPiso" => 0.10,
        "arq_coefSupComunPisosSup" => 0.05,
        "arq_coefSupComun" => 0.1,
        "arq_variante_normativa" => variante_norm
    )
end

################################################################################
#                          DATA LOADING SECTION                              #
################################################################################

function load_optimization_data(conn_postgres, conn_neo4j)
    println("Loading optimization instances...")
    query_pg = """
    SELECT * FROM public.tabla_instancias_optimizacion
    WHERE status = 0
    ORDER BY id_opti ASC
    """
    df_instancias = pg_julia.query(conn_postgres, query_pg)

    if isempty(df_instancias)
        error("No optimization instances found with status = 0")
    end

    println("Found $(nrow(df_instancias)) optimization instances")

    println("Loading combi data...")
    query_combis = """
    MATCH (p:Predio)-[]-(c:Combi)
    RETURN DISTINCT c.id_combi AS id_combi, c.predios AS list_predios
    ORDER BY id_combi
    """
    df_combis = neo4j_julia.cypher_to_dataframe(query_combis, conn_neo4j)

    if isempty(df_combis)
        error("No combi data found in Neo4j")
    end

    lista_combi_instancias = unique(df_instancias.id_combi)
    if isempty(lista_combi_instancias)
        error("No valid combi IDs found in optimization instances")
    end

    cypher_list = "[" * join("\"" .* lista_combi_instancias .* "\"", ", ") * "]"

    println("Loading geometries for $(length(lista_combi_instancias)) combis...")
    query_geom = """
    MATCH (c:Combi)-[:CONTIENE_CALLES]->(cc:Calle_Combi)
    WHERE c.id_combi IN $cypher_list
    RETURN DISTINCT c.id_combi AS id_combi, c.sup_combi_sii AS sup_terreno_sii,
            c.geom_combi AS geom_wkt, c.num_predios AS num_predios,
            c.calles_contexto_wkt AS calles_contexto_wkt,
            cc.id_calle_combi AS id_calle_combi, cc.geom_wkt AS calles_combi_wkt
    ORDER BY id_combi, id_calle_combi
    """
    df_combined = neo4j_julia.cypher_to_dataframe(query_geom, conn_neo4j)

    if isempty(df_combined)
        error("No geometry data found for the specified combis")
    end

    println("Loaded $(nrow(df_combined)) geometry records")

    return df_instancias, df_combis, df_combined
end

function setup_workers()
    available_cores = length(Sys.cpu_info())
    optimal_workers = max(1, available_cores - 4)  # Leave 4 cores for system

    println("Setting up $optimal_workers workers (from $available_cores available cores)...")

    if nprocs() == 1  # No workers added yet
        try
            addprocs(optimal_workers; exeflags="--project")
            println("Successfully added $(nworkers()) workers")
        catch e
            @warn "Failed to add all requested workers: $e"
            if nworkers() == 0
                error("No workers available for parallel processing")
            end
        end
    else
        println("Using existing $(nworkers()) workers")
    end

    # Load required packages on all workers
    @everywhere begin
        using LandValue, Distributed, OrderedCollections, DataFrames
        println("Worker $(myid()) initialized successfully")
    end

    return workers()
end

worker_ids = setup_workers()

# Load optimization data after worker setup
df_instancias, df_combis, df_combined = load_optimization_data(conn_postgres, conn_neo4j)

################################################################################
#                      MAIN OPTIMIZATION PROCESSING LOOP                     #
################################################################################

const PRIMARY_KEY = "id_opti"
const TABLE_NAME = "tabla_resultados_optimizacion"
const PRIORITY_KEYS = ["id_opti", "id_combi", "flag_sombra", "arq_variante_normativa", "arq_tipo_edificio"]

function create_optimized_channels(num_jobs, num_workers)
    job_buffer_size = min(num_jobs, max(20, num_workers))
    result_buffer_size = min(num_jobs, max(50, num_workers * 2))

    println("Creating channels: jobs($job_buffer_size), results($result_buffer_size)")

    return RemoteChannel(()->Channel{Any}(job_buffer_size)), RemoteChannel(()->Channel{Any}(result_buffer_size))
end

function populate_job_queue(df_instancias, df_combis, df_combined, my_env, jobs)
    println("Populating job queue with $(nrow(df_instancias)) optimization tasks...")

    jobs_created = 0
    for row in eachrow(df_instancias)
        job_data = Dict(
            "id_opti" => row.id_opti,
            "id_combi" => row.id_combi,
            "variante_norm" => row.variante_norm,
            "my_env" => my_env,
            "df_combis" => df_combis,
            "df_combined" => df_combined
        )
        put!(jobs, job_data)
        jobs_created += 1
    end

    # Add termination signals for each worker
    termination_signals = length(worker_ids)
    for _ in 1:termination_signals
        put!(jobs, nothing)
    end

    close(jobs)
    println("Job queue populated: $jobs_created jobs + $termination_signals termination signals")
end

num_instancias = size(df_instancias, 1)
jobs, results = create_optimized_channels(num_instancias, length(worker_ids))

@everywhere function safe_obtiene_geometrias_combi(df_combined_row)
    # Validate input data
    if nrow(df_combined_row) == 0
        throw(ArgumentError("Empty DataFrame provided"))
    end

    # Validate required geometry fields
    required_fields = ["geom_wkt", "calles_contexto_wkt", "num_predios"]
    for field in required_fields
        if !hasproperty(df_combined_row, field)
            throw(ArgumentError("Missing required field: $field"))
        end
        if ismissing(df_combined_row[1, field]) || isnothing(df_combined_row[1, field])
            throw(ArgumentError("Field $field is missing or null"))
        end
    end

    # Validate geometry data
    geom_wkt = df_combined_row[1, "geom_wkt"]
    if !isa(geom_wkt, AbstractString) || length(strip(geom_wkt)) == 0
        throw(ArgumentError("Invalid geometry WKT: empty or not a string"))
    end

    calles_contexto_wkt = df_combined_row[1, "calles_contexto_wkt"]
    if !isa(calles_contexto_wkt, AbstractString) || length(strip(calles_contexto_wkt)) == 0
        throw(ArgumentError("Invalid calles_contexto_wkt: empty or not a string"))
    end

    try
        # Process main geometry with validation
        ps_combi = polyGdal.astext2shape([geom_wkt])
        if isempty(ps_combi.pols) || isempty(ps_combi.pols[1])
            throw(ArgumentError("Invalid geometry: empty polygon after parsing"))
        end

        ps_combi = polyShape.setPolyOrientation(ps_combi, 1)
        ps_combi = polyShape.shape_4326to32719(ps_combi)
        ps_combi, dx, dy = polyShape.ajustaCoordenadas(ps_combi)
        ps_combi = polyShape.polyUnion(ps_combi)
        ps_combi = polyGdal.shapeSimplify(ps_combi, 1.0)
        ps_combi = polyShape.polyEliminaColineales(ps_combi)

        # Validate processed geometry
        if isempty(ps_combi.pols) || isempty(ps_combi.pols[1])
            throw(ArgumentError("Geometry became invalid after processing"))
        end

        # Process context streets
        ps_calles_contexto = polyGdal.astext2shape([calles_contexto_wkt])
        ps_calles_contexto = polyShape.shape_4326to32719(ps_calles_contexto)
        ps_calles_contexto = polyShape.ajustaCoordenadas(ps_calles_contexto, dx, dy)

        # Process street data with validation
        calles_data = filter(row -> !ismissing(row.calles_combi_wkt) &&
                           !isnothing(row.calles_combi_wkt) &&
                           isa(row.calles_combi_wkt, AbstractString) &&
                           length(strip(row.calles_combi_wkt)) > 0, df_combined_row)

        if isempty(calles_data)
            @warn "No valid street data found, using empty defaults"
            ps_calles = polyShape.PolyShape()
            ps_publico = ps_combi
            ps_bruto = ps_combi
            vecAnchoCalle = Float64[]
            vecSecConCalle = Int[]
        else
            display("Procesamiento del conjunto de calles en el entorno del predio")
            ps_calles, ps_publico, ps_bruto, vecAnchoCalle, vecSecConCalle = obtieneCalles(calles_data, ps_combi, dx, dy)
        end

        # Process edges with validation
        vec_edges_predio, aux = polyShape.shape2vector(ps_combi)
        numLadosPredio = length(vec_edges_predio)

        if numLadosPredio == 0
            throw(ArgumentError("Processed geometry has no edges"))
        end

        vecSecTodos = collect(1:numLadosPredio)
        vecSecSinCalle = setdiff(vecSecTodos, vecSecConCalle)

        # Validate num_predios
        n_predios = df_combined_row[1, "num_predios"]
        if !isa(n_predios, Integer) || n_predios <= 0
            @warn "Invalid num_predios: $n_predios, using 1"
            n_predios = 1
        end

        dict_geom = Dict(
            "ps_combi" => ps_combi,
            "ps_calles" => ps_calles,
            "ps_publico" => ps_publico,
            "ps_bruto" => ps_bruto,
            "ps_calles_contexto" => ps_calles_contexto,
            "n_predios" => n_predios,
            "vecSecTodos" => vecSecTodos,
            "vecSecSinCalle" => vecSecSinCalle,
            "vecSecConCalle" => vecSecConCalle,
            "vecAnchoCalle" => vecAnchoCalle,
            "sup_terreno_sii" => haskey(df_combined_row[1,:], "sup_terreno_sii") && !ismissing(df_combined_row[1, "sup_terreno_sii"]) ? df_combined_row[1, "sup_terreno_sii"] : nothing,
            "dx" => dx,
            "dy" => dy
        )

        return dict_geom

    catch e
        @error "Geometry processing failed: $e"
        rethrow(e)
    end
end

@everywhere function distributed_work(jobs, results)
    conn_postgres = nothing
    conn_neo4j = nothing

    try
        while true
            local job_data
            try
                job_data = take!(jobs)
                if job_data === nothing
                    println("Worker $(myid()) received termination signal")
                    break
                end
            catch e
                if isa(e, InvalidStateException) && e.state === :closed
                    println("Worker $(myid()) detected closed channel, shutting down")
                    break
                end
                @error "Worker $(myid()) error taking job: $e"
                continue
            end

            # Comprehensive job data validation
            required_fields = ["id_opti", "id_combi", "variante_norm", "my_env", "df_combis", "df_combined"]
            if any(field -> !haskey(job_data, field), required_fields)
                @error "Worker $(myid()) received invalid job data, missing required fields"
                continue
            end

            # Extract and validate job data
            id_opti = job_data["id_opti"]
            id_combi = job_data["id_combi"]
            variante_norm = job_data["variante_norm"]
            my_env = job_data["my_env"]
            df_combis = job_data["df_combis"]
            df_combined = job_data["df_combined"]

            # Validate data types and values
            if !isa(id_opti, Integer) || id_opti <= 0
                @error "Worker $(myid()) invalid id_opti: $id_opti"
                continue
            end

            if !isa(id_combi, AbstractString) || isempty(id_combi)
                @error "Worker $(myid()) invalid id_combi: $id_combi"
                continue
            end

            if !isa(df_combis, DataFrame) || nrow(df_combis) == 0
                @error "Worker $(myid()) invalid df_combis data"
                continue
            end

            if !isa(df_combined, DataFrame) || nrow(df_combined) == 0
                @error "Worker $(myid()) invalid df_combined data"
                continue
            end

            println("Worker $(myid()) processing optimization ID: $id_opti (Combi: $id_combi)")

            try
                # Establish database connections for this job
                conn_neo4j, conn_postgres = setup_database_connections(my_env)

                # Process optimization with memory management
                df_combis_row = filter(r -> r.id_combi == id_combi, df_combis)
                if isempty(df_combis_row)
                    handle_optimization_error(conn_postgres, id_opti, "No combi data found", "")
                    continue
                end

                vec_predios = parse.(Int, split(strip(df_combis_row[1, "list_predios"], ['(', ')']), ';'))

                df_combined_row = filter(r -> r.id_combi == id_combi, df_combined)
                if isempty(df_combined_row)
                    handle_optimization_error(conn_postgres, id_opti, "No geometries found", "")
                    continue
                end

                # Process geometry with error handling
                dict_geom, geom_success, geom_error = process_geometry_for_combi(df_combined_row, id_combi)
                if !geom_success
                    handle_optimization_error(conn_postgres, id_opti, "Geometry processing failed", geom_error)
                    continue
                end

                # Clear intermediate data to save memory
                df_combis_row = nothing
                df_combined_row = nothing
                GC.safepoint() # Allow garbage collection

                dict_arquitectura = createArchitectureDict(variante_norm)
                dict_requerimientos = obtiene_requerimientos_normativos(vec_predios[1], dict_arquitectura["arq_variante_normativa"], conn_neo4j)

                (dict_resultados, dict_proyecto_vs_normativa), opti_success, opti_error = run_single_optimization(dict_geom, dict_arquitectura, dict_requerimientos, id_opti, id_combi)
                if !opti_success
                    handle_optimization_error(conn_postgres, id_opti, "Optimization failed", opti_error)
                    continue
                end

                # Process results efficiently
                dict_all = OrderedDict{String,Any}()
                dicts = [dict_resultados, dict_proyecto_vs_normativa, dict_arquitectura]

                for dict in dicts
                    for (key, value) in dict
                        dict_all[key] = processValue(value, dict_geom)
                    end
                end

                # Clear intermediate results to save memory
                dict_resultados = nothing
                dict_proyecto_vs_normativa = nothing
                dict_arquitectura = nothing
                dict_requerimientos = nothing
                dict_geom = nothing
                GC.safepoint()

                status_optim = haskey(dict_all, "optimo_solucion") ? dict_all["optimo_solucion"] : "Optimo Encontrado"
                put!(results, (dict_all, id_opti, status_optim, myid()))

                println("Worker $(myid()) completed optimization ID: $id_opti successfully")

            catch e
                @error "Worker $(myid()) unexpected error processing ID $id_opti: $e"
                try
                    handle_optimization_error(conn_postgres, id_opti, "Unexpected worker error", e)
                catch cleanup_error
                    @error "Worker $(myid()) failed to update error status: $cleanup_error"
                end
            finally
                # Always cleanup connections
                try
                    conn_postgres !== nothing && pg_julia.close_db(conn_postgres)
                catch e
                    @warn "Worker $(myid()) error closing Postgres connection: $e"
                end
                # Note: Neo4j connection cleanup commented out as in original
            end
        end
    finally
        println("Worker $(myid()) shutting down")
        # Final cleanup if needed
        try
            conn_postgres !== nothing && pg_julia.close_db(conn_postgres)
        catch e
            @warn "Worker $(myid()) error in final cleanup: $e"
        end
    end
end

function execute_parallel_optimization()
    println("\n" * "="^80)
    println("STARTING DISTRIBUTED OPTIMIZATION PROCESSING")
    println("="^80)

    start_time = time()

    # Setup result table
    flag_create_table = false
    table_check_query = """
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = '$TABLE_NAME'
    """
    existing_table = pg_julia.query(conn_postgres, table_check_query)
    if isempty(existing_table)
        flag_create_table = true
        println("Table '$TABLE_NAME' does not exist, will create on first result")
    else
        println("Table '$TABLE_NAME' already exists")
    end

    # Start job distribution asynchronously
    println("Starting job distribution...")
    @async populate_job_queue(df_instancias, df_combis, df_combined, my_env, jobs)

    # Launch workers
    println("Launching $(length(worker_ids)) workers...")
    for worker_id in worker_ids
        remote_do(distributed_work, worker_id, jobs, results)
    end

    # Process results with enhanced monitoring
    completed_jobs = 0
    successful_jobs = 0
    failed_jobs = 0

    println("Processing results...")
    println("Progress: [Completed/Total] [Success/Failed] - Latest ID")

    while completed_jobs < num_instancias
        try
            dict_all, id_opti, status, worker_id = take!(results)
            completed_jobs += 1

            if status == "Optimo Encontrado"
                successful_jobs += 1

                # Sort results by priority
                dict_all = OrderedDict(sort(collect(dict_all), by=x -> (findfirst(==(x[1]), PRIORITY_KEYS) === nothing ? 1000 : findfirst(==(x[1]), PRIORITY_KEYS), x[1])))

                vecColumnNames, vecColumnTypes = dict2tablevec(dict_all, PRIMARY_KEY)

                if flag_create_table
                    println("Creating results table: $TABLE_NAME")
                    pg_julia.createTable(conn_postgres, TABLE_NAME, vecColumnNames, vecColumnTypes, PRIMARY_KEY)
                    flag_create_table = false
                end

                vecColumnValue = Vector{Any}(undef, length(vecColumnNames))
                for (idx, col_name) in enumerate(vecColumnNames)
                    vecColumnValue[idx] = haskey(dict_all, col_name) ? dict_all[col_name] : nothing
                end

                pg_julia.insertRow!(conn_postgres, TABLE_NAME, vecColumnNames, vecColumnValue, Symbol(PRIMARY_KEY))
                update_optimization_status(conn_postgres, id_opti, 1)

                println("Progress: [$completed_jobs/$num_instancias] [✓$successful_jobs/✗$failed_jobs] - ID $id_opti (Worker $worker_id)")
            else
                failed_jobs += 1
                println("Progress: [$completed_jobs/$num_instancias] [✓$successful_jobs/✗$failed_jobs] - ID $id_opti FAILED")
            end

        catch e
            @error "Error processing result: $e"
            break
        end
    end

    elapsed_time = time() - start_time

    println("\n" * "="^80)
    println("OPTIMIZATION PROCESSING COMPLETED")
    println("="^80)
    println("Total jobs: $num_instancias")
    println("Successful: $successful_jobs")
    println("Failed: $failed_jobs")
    println("Success rate: $(round(successful_jobs/num_instancias*100, digits=1))%")
    println("Total time: $(round(elapsed_time, digits=1)) seconds")
    println("Average time per job: $(round(elapsed_time/num_instancias, digits=2)) seconds")
    println("="^80)

    return successful_jobs, failed_jobs, elapsed_time
end

# Execute the optimization
success_count, fail_count, total_time = execute_parallel_optimization()