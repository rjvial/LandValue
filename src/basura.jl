using DotEnv 

DotEnv.load("secrets.env")
conn_LandValue = pg_julia.connection("landengines_dev", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"])
conn_mygis_db = pg_julia.connection("gis_data", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"])

display(conn_LandValue)
display(conn_mygis_db)
