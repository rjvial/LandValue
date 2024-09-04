using LandValue, DotEnv


athena_output = "query-results"
athena_catalog_name = "AwsDataCatalog"
database_name = "datos_base"

DotEnv.load("secrets.env") #Caso Docker
aws_access_key_id = ENV["AWS_ACCESS_KEY"]
aws_secret_access_key = ENV["AWS_SECRET_KEY"]
aws_region = ENV["AWS_REGION"]

bucket = "landengines-data"

aws_client = aws_julia.connection(aws_access_key_id, aws_secret_access_key, aws_region)

# file_name = "query-results/0a4735aa-97e6-442b-ae67-d0b6a9d918e1.csv"
# df = aws_julia.pd_read_s3_csv(bucket, file_name, aws_client)




query = """
SELECT codigo_predial_est as codigo_predial, comuna, geom_wkt
FROM datos_geom_predios
WHERE comuna = 'vitacura' AND codigo_predial_est > 0
"""
df = aws_julia.query_to_dataframe(query, database_name, bucket, athena_output, athena_catalog_name, aws_client)


# valorMercado_lotes = 100 * ones(6,1)
# num_lotes = length(valorMercado_lotes)
# superficie_lotes = 100 * ones(6,1)
# valorInmobiliario_combis = [150 * 3
#                             145 * 2
#                             150 * 3
#                             145 * 2
#                             160 * 5
#                             160 * 5
#                             163 * 6]


# # C = [1 1 0 0
# #      0 1 1 0
# #      1 1 1 0
# #      1 1 0 1
# #      0 1 1 1
# #      1 1 1 1]

# # valorMercado_lotes = 100 * ones(4,1)
# # superficie_lotes = 100 * ones(4,1)
# # valorInmobiliario_combis = [145 * 2
# #                             145 * 2
# #                             150 * 3
# #                             150 * 3
# #                             150 * 3
# #                             155 * 4]

# delta_lotes = .1
# delta_combis = .2
# delta_opt_lotes = .1
# delta_opt_combis = .2

# # x_opt = optimal_lot_selection(C)

# popt_r, util_opt_r = optimal_pricing(C, valorMercado_lotes, superficie_lotes, valorInmobiliario_combis, delta_lotes, delta_combis, delta_opt_lotes, delta_opt_combis)

# p_lotes = popt_r[1][1:num_lotes]
# p_combis = popt_r[1][num_lotes+1:end]

# display(p_lotes)
# display([valorInmobiliario_combis * (1-delta_opt_combis) p_combis valorInmobiliario_combis * (1+delta_opt_combis)])

# display(util_opt_r)