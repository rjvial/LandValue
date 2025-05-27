module aws_julia

using DotEnv, AWS, DataFrames, CSV, JSON

using AWS: @service
@service S3
@service Athena
@service Ec2

function connection(aws_access_key_id::AbstractString,
                    aws_secret_access_key::AbstractString,
                    aws_region::AbstractString)
    creds      = AWSCredentials(aws_access_key_id, aws_secret_access_key)
    aws_client = AWS.global_aws_config(region=aws_region, creds=creds)
    return aws_client
end

function pd_read_s3_csv(bucket, file_name, aws_client)
    text = String(S3.get_object(bucket, file_name; aws_config=aws_client))
    df = CSV.File(IOBuffer(text)) |> DataFrame
    return df
end

function query_to_dataframe(query, database_name, bucket, athena_output, athena_catalog_name, aws_client)
    exe_query = execute_athena_query(query, database_name, bucket, athena_output, athena_catalog_name, aws_client)
    file_name = "query-results/" * exe_query["QueryExecutionId"] * ".csv"
    df = aws_julia.pd_read_s3_csv(bucket, file_name, aws_client)
    return df
end

function get_execution_response(exe_query)
    status = Athena.get_query_execution(exe_query["QueryExecutionId"])["QueryExecution"]["Status"]["State"]
    return status
end

function execute_athena_query(query, database_name, bucket, athena_output, athena_catalog_name, aws_client)
    athena_params = Dict(
        "ResultConfiguration" => Dict(
            "OutputLocation" => "s3://" * bucket * "/" * athena_output * "/"
        ),
        "QueryExecutionContext" => Dict(
            "Database" => database_name,
            "Catalog" => athena_catalog_name
        )
    )

    exe_query = Athena.start_query_execution(query, athena_params; aws_config=aws_client)
    
    status = get_execution_response(exe_query)
    contador = 0
    while (contador < 100) && (status != "SUCCEEDED")
        sleep(2)
        status = get_execution_response(exe_query)
        contador += 1
    end
    println("Status Execute_athena_query: ", status)

    return exe_query
end


# Helper to convert single items into vectors for consistent iteration
function ensure_vector(x)
    if x === nothing
        return []
    elseif isa(x, AbstractVector)
        return x
    else
        return [x]  # Wrap single item in vector
    end
end
function find_ec2_instances(aws_client)
    try
        # Call EC2 describe_instances using the provided aws_client
        resp = Ec2.describe_instances(; aws_config=aws_client)

        # Array to store all instances
        instances_data = []

        # Check if reservationSet exists
        if !haskey(resp, "reservationSet") || resp["reservationSet"] === nothing
            result = Dict("status" => "success", "message" => "No reservations found", "instances" => instances_data)
            return result
        end

        reservation_set = resp["reservationSet"]
        reservations_raw = get(reservation_set, "item", [])
        reservations = ensure_vector(reservations_raw)

        if isempty(reservations)
            result = Dict("status" => "success", "message" => "No reservations found", "instances" => instances_data)
            return result
        end

        for res in reservations
            if !haskey(res, "instancesSet") || res["instancesSet"] === nothing
                continue
            end

            instances_raw = get(res["instancesSet"], "item", [])
            instances = ensure_vector(instances_raw)

            for inst in instances
                id = get(inst, "instanceId", "unknown")
                state_info = get(inst, "instanceState", Dict())
                st = get(state_info, "name", "unknown")
                ip = get(inst, "ipAddress", "none")
                dns = get(inst, "dnsName", "none")

                name_tag = "none"
                if haskey(inst, "tagSet") && inst["tagSet"] !== nothing
                    tag_set = get(inst["tagSet"], "item", [])
                    tags = ensure_vector(tag_set)
                    for tag in tags
                        if get(tag, "key", "") == "Name"
                            name_tag = get(tag, "value", "none")
                            break
                        end
                    end
                end

                instance_obj = Dict(
                    "instanceId" => id,
                    "name" => name_tag,
                    "state" => st,
                    "ipAddress" => ip,
                    "dnsName" => dns
                )

                push!(instances_data, instance_obj)
            end
        end

        result = Dict(
            "status" => "success",
            "message" => "Successfully retrieved $(length(instances_data)) instance(s)",
            "instances" => instances_data
        )
        return result

    catch e
        error_result = Dict(
            "status" => "error",
            "message" => "Error occurred: $e"
        )

        if isa(e, AWS.AWSException)
            error_result["aws_error_code"] = e.code
            error_result["aws_error_message"] = e.message
        end
        return error_result
    end
end

function find_instance_by_name(target_name::String, aws_client)
    result = find_ec2_instances(aws_client)

    if result["status"] != "success"
        error("Failed to retrieve instances: ", result["message"])
    end

    for instance in result["instances"]
        if instance["name"] == target_name
            return Dict(
                "ipAddress" => instance["ipAddress"],
                "instanceId" => instance["instanceId"],
                "dnsName" => instance["dnsName"],
                "state" => instance["state"]
            )
        end
    end

    error("Instance with name '$target_name' not found.")
end

export connection,
       pd_read_s3_csv,
       query_to_dataframe,
       get_execution_response,
       execute_athena_query,
       find_ec2_instances,
       find_instance_by_name
end




# function find_instance_by_name(name::String)
#     # Construct the AWS CLI command
#     cmd = `aws ec2 describe-instances --filters Name=tag:Name,Values=$name --output json`

#     # Initialize raw output variable
#     raw = ""

#     # Run the command and capture output
#     try
#         raw = read(cmd, String)
#     catch err
#         error("Failed to run AWS CLI: ", err)
#     end

#     # Parse JSON response
#     data = JSON3.read(raw)
#     reservations = get(data, "Reservations", [])

#     for res in reservations
#         instances = get(res, "Instances", [])
#         for inst in instances
#             instance_id = inst["InstanceId"]::String
#             public_ip = haskey(inst, "PublicIpAddress") ? inst["PublicIpAddress"]::String : nothing
#             public_dns = haskey(inst, "PublicDnsName") ? inst["PublicDnsName"]::String : nothing
#             state = inst["State"]["Name"]::String
#             println("Found instance $instance_id @ $public_ip, DNS: $public_dns (state: $state)")
#             return instance_id, public_ip, public_dns, state
#         end
#     end

#     error("No instance found with Name tag '$name'")
# end


