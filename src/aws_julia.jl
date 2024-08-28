using DotEnv, AWS, DataFrames, CSV
using AWS: @service

function pd_read_s3_csv(bucket, file_name, aws_client, S3)
    
    text = String(S3.get_object(bucket, file_name; aws_config=aws_client))
    df = CSV.File(IOBuffer(text)) |> DataFrame

    return df
end

function query_to_dataframe(query, database_name, bucket, athena_output, athena_catalog_name, aws_client, Athena)
    exe_query = execute_athena_query(query, database_name, bucket, athena_output, athena_catalog_name, aws_client, Athena)

    result = Athena.get_query_results( exe_query["QueryExecutionId"]; aws_config = aws_client)
        
    column_names = [col["Label"] for col in result["ResultSet"]["ResultSetMetadata"]["ColumnInfo"]]
    column_types = [col["Type"] for col in result["ResultSet"]["ResultSetMetadata"]["ColumnInfo"]]

    type_mapping = Dict(
        "double" => Float64,
        "bigint" => Int,
        "int" => Int
    )

    data_rows = result["ResultSet"]["Rows"]
    data = [[(column_types[i] == "varchar" ? row["Data"][i]["VarCharValue"] : parse(Int, row["Data"][i]["VarCharValue"])) for i in 1:length(column_names)] for row in data_rows[2:end]]
    data = []
    for row in data_rows[2:end]  # Start from the second element
        row_data = Any[]
        for i in 1:length(column_names)
            value = row["Data"][i]["VarCharValue"]
            if column_types[i] in keys(type_mapping)
                try
                    parsed_value = parse(get(type_mapping, column_types[i], Any),value)
                    push!(row_data, parsed_value)
                catch
                    push!(row_data, value)  # Keep the original string value if parsing fails
                end
            else
                push!(row_data, value)
            end
        end
        push!(data, row_data)
    end

    data = permutedims(hcat(data...))

    # Create a DataFrame with appropriate column names
    df = DataFrame(data, Symbol.(column_names[1:size(data, 2)]))

    return df
end

function get_execution_response(aws_client, exe_query)
    # Obtiene el estatus de la ejecución de una query
    status = Athena.get_query_execution(exe_query["QueryExecutionId"])["QueryExecution"]["Status"]["State"]
    return status
end

function execute_athena_query(query, database_name, bucket, athena_output, athena_catalog_name, aws_client, Athena)

    athena_params = Dict(
    "ResultConfiguration" => Dict(
        "OutputLocation" => "s3://"*bucket*"/"*athena_output*"/"
    ),
    "QueryExecutionContext" => Dict(
        "Database" => database_name,
        "Catalog" => athena_catalog_name
    )
    )

    exe_query = Athena.start_query_execution(query, athena_params; aws_config = aws_client)
    
    status = get_execution_response(aws_client, exe_query)
    contador = 0
    while (contador < 10) & (status != "SUCCEEDED")
        sleep(2)
        status = get_execution_response(aws_client, exe_query)
        contador = contador + 1
    end
    print("Status Execute_athena_query: "*status)

    return exe_query
end

athena_output = "query-results"
athena_catalog_name = "AwsDataCatalog"
database_name = "datos_base"

DotEnv.load("secrets.env") #Caso Docker
aws_access_key_id = ENV["AWS_ACCESS_KEY"]
aws_secret_access_key = ENV["AWS_SECRET_KEY"]
aws_region = ENV["AWS_REGION"]
creds = AWSCredentials(aws_access_key_id, aws_secret_access_key)
# const AWS_GLOBAL_CONFIG = Ref{AWS.AWSConfig}()

aws_client = AWS.global_aws_config(region=aws_region, creds=creds)
bucket = "landengines-data"
file_name = "raw-data/sii/valor_tipo_construccion/valor_tipo_construccion_sii.csv"

@service S3
# df = pd_read_s3_csv(bucket, file_name, aws_client, S3)

query = """
SELECT rut, nombre_empresa 
FROM datos_empresas
WHERE nombre_empresa <> ''
LIMIT 10
"""
@service Athena
df = query_to_dataframe(query, database_name, bucket, athena_output, athena_catalog_name, aws_client, Athena)

print(df)
a=1

# function pd_read_s3_parquet(bucket, file_name, s3_client=None)
#     # Descarga un archivo parquet desde S3 y lo entrega como Dataframe
#     if s3_client is None:
#         s3_client = boto3.client('s3')
#     obj = s3_client.get_object(Bucket=bucket, Key=f'{file_name}')
#     return pd.read_parquet(io.BytesIO(obj['Body'].read()))

# # function create_athena_database(athena_client, database_name, bucket)
# #     # Crea una base de datos database_name
# #     query = f"CREATE DATABASE IF NOT EXISTS {database_name};"
# #     response = athena_client.start_query_execution(
# #         QueryString=query,
# #         ResultConfiguration={
# #             'OutputLocation': f's3://{bucket}/query-results/'
# #         }
# #     )



# function create_s3_folder(s3_client, athena_bucket, nombre_folder)
#     # Crea un folder S3 dentro de un bucket específico
#     s3_client.put_object(Bucket=athena_bucket, Key=(nombre_folder+'/'))

# function create_s3_bucket(s3_client, athena_bucket)
#     response = s3_client.create_bucket(
#         Bucket=athena_bucket)

# function get_execution_response(athena_client, queryExecutionId)
#     # Obtiene el estatus de la ejecución de una query
#     status = athena_client.get_query_execution(
#         QueryExecutionId=queryExecutionId)['QueryExecution']['Status']['State']
#     return status

# function query_to_dataframe(query, bucket, output, database_name, athena_client, s3_client)
#     # Ejecuta una query y entrega el resultado en un Dataframe
#     queryExecutionId = execute_athena_query(athena_client, query, database_name, bucket, output)
#     try:
#         temp_file_location: str = "temp_query_results.csv"
#         s3_client.download_file(
#             bucket,
#             f"{output}/{queryExecutionId}.csv",
#             temp_file_location
#         )
#         df = pd.read_csv(temp_file_location)
#         os.remove(temp_file_location)
#         return df
#     except:
#         return print('Error!')

# function check_if_file_exists(s3_client, bucket, s3_file)
#     # Chequea si archivo s3_file del bucket existe o no
#     try:
#         s3_client.head_object(Bucket=bucket, Key=s3_file)
#         return 'SUCCEEDED'
#     except:
#         return 'ERROR'

# function upload_file(s3_client, local_file, bucket, s3_file)
#     # Sube archivo local_file a un bucket en S3 con el nombre s3_file
#     response = s3_client.upload_file(local_file, bucket, s3_file)
#     time.sleep(2)
#     status = check_if_file_exists(s3_client, bucket, s3_file)
#     contador = 0
#     if contador < 10 and status != 'SUCCEEDED':
#         contador = contador + 1
#         time.sleep(2)
#         status = check_if_file_exists(s3_client, bucket, s3_file)
#     print(f'Status Upload archivo {s3_file}: {status}')
#     return response

# function check_if_table_exists(athena_client, athena_catalog_name, nombre_tabla, db_name)
#     # Chequea si existe o no una tabla específica 
#     try: 
#         response = athena_client.get_table_metadata(
#         CatalogName=athena_catalog_name,
#         DatabaseName=db_name,
#         TableName=nombre_tabla
#         )
#         response['TableMetadata']['Parameters']['location']
#         satus = 'EXISTS'
#         return satus
#     except:
#         satus = 'ERROR'
#         return satus

# function genera_tablas(athena_client, athena_catalog_name, nombre_tabla, direccion, columnas_tabla_con_tipo, columnas_particion,
#                   DB_NAME, athena_bucket, athena_output)
#     # Genera una tabla Athena y una Iceberg a partir de datos en S3. En caso que los datos no hayan sido subidos
#     # a S3, realiza el proceso de descarga y posterior upload de los datos a S3.

#     status_table = check_if_table_exists(athena_client, athena_catalog_name, nombre_tabla, f'{DB_NAME}')
#     if status_table != 'EXISTS':  #Si No existe la tabla, se realiza todo el proceso
#         local_file_name = f'{nombre_tabla}.gzip'
#         S3_file_name = f'{athena_bucket}/{direccion}/{local_file_name}'

#         # Se crea la tabla en Athena y se Pobla con datos inmediatamente
#         print(f'Creando tabla {DB_NAME}.{nombre_tabla} en Athena')
#         if columnas_particion == ''
#             query_create_athena_table = f"""
#             CREATE EXTERNAL TABLE IF NOT EXISTS {DB_NAME}.{nombre_tabla} ( {columnas_tabla_con_tipo}
#                 )
#             STORED AS PARQUET
#             LOCATION
#             's3://{athena_bucket}/{direccion}/';
#             """
#         else
#             query_create_athena_table = f"""
#             CREATE EXTERNAL TABLE IF NOT EXISTS {DB_NAME}.{nombre_tabla} ( {columnas_tabla_con_tipo}
#                 )
#             PARTITIONED BY (
#                 {columnas_particion}
#             )
#             STORED AS PARQUET
#             LOCATION
#             's3://{athena_bucket}/{direccion}/';
#             """

#         execute_athena_query(athena_client, query_create_athena_table, f'{DB_NAME}', athena_bucket, athena_output)

#     else #Si la tabla fue creada previamente
#         print(f'Tabla {nombre_tabla} ya existe. No se volverá a crear')

#     query_repair = f"""
#     MSCK REPAIR TABLE {nombre_tabla}
#     """
#     execute_athena_query(athena_client, query_repair, f'{DB_NAME}', athena_bucket, athena_output)

