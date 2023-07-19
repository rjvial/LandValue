module pg_julia

using LibPQ, Tables, DataFrames,  IterTools, CSV, XLSX


function connection(dbStr::String, userStr::String, pwStr::String)
    #conn = pg_julia.connection("LandValue", "postgres", "lm4321")
    connStr = string("dbname=", dbStr, " user=", userStr, " password=", pwStr)
    conn = LibPQ.Connection(connStr)
    return conn
end
function connection(dbStr::String, userStr::String, pwStr::String, hostStr::String)
    #conn = pg_julia.connection("LandValue", "postgres", "lm4321")
    connStr = string("dbname=", dbStr, " user=", userStr, " password=", pwStr, " host=", hostStr)
    conn = LibPQ.Connection(connStr)
    return conn
end

function simpleQuery(conn::LibPQ.Connection; from_str::String, select_str::String = "*", where_str::String = "")
    query_str = "Select " * select_str * " From " * from_str * " Where " * where_str
    df = pg_julia.query(conn, query_str)
    return df
end

function query(conn::LibPQ.Connection, queryStr::String)
    #df = pg_julia.query(conn, """SELECT * FROM public."tablaCabidaNormativa";""")
    #queryStr = """SELECT * FROM public."tablaCabidaNormativa";"""
    #queryStr = """
    #            SELECT *
    #            FROM public."tablaCabidaNormativa";
    #            """
    #queryStr = """
    #        INSERT INTO public."tablaCabidaNormativa" (
    #        "DISTANCIAMIENTO", "ANTEJARDIN", "RASANTE", "RASANTESOMBRA", "ALTURAMAX", "MAXPISOS", "COEFOCUPACION", "SUBPREDIALMIN", "DENSIDADMAX", "FLAGDENSIDADBRUTA", "COEFCONSTRUCTIBILIDAD", "ESTACIONAMIENTOSPORVIV", "PORCADICESTACVISITAS", "SUPPORESTACIONAMIENTO", "ESTBICICLETAPOREST", "BICICLETASPOREST", "FLAGCAMBIOESTPORBICICLETA", "MAXSUBTE", "COEFOCUPACIONEST", "SEPESTMIN", "REDUCCIONESTPORDISTMETRO", "id_Normativa") VALUES (
    #        '4'::double precision, '4'::double precision, '2.75'::double precision, '5'::double precision, '60'::double precision, '30'::integer, '0.7'::double precision, '1000'::double precision, '2500'::double precision, true::boolean, '4'::double precision, '1'::double precision, '.15'::double precision, '34'::double precision, '.5'::double precision, '3'::double precision, true::boolean, '10'::integer, '.8'::double precision, '7'::double precision, false::boolean, '2'::integer)
    #        """
    #queryStr = """INSERT INTO public."tablaCabidaNormativa" ("DISTANCIAMIENTO", "ANTEJARDIN", "RASANTE", "RASANTESOMBRA", "ALTURAMAX", "MAXPISOS", "COEFOCUPACION", "SUBPREDIALMIN", "DENSIDADMAX", "FLAGDENSIDADBRUTA", "COEFCONSTRUCTIBILIDAD", "ESTACIONAMIENTOSPORVIV", "PORCADICESTACVISITAS", "SUPPORESTACIONAMIENTO", "ESTBICICLETAPOREST", "BICICLETASPOREST", "FLAGCAMBIOESTPORBICICLETA", "MAXSUBTE", "COEFOCUPACIONEST", "SEPESTMIN", "REDUCCIONESTPORDISTMETRO", "id_Normativa") VALUES ('4'::double precision, '4'::double precision, '2.75'::double precision, '5'::double precision, '60'::double precision, '30'::integer, '0.7'::double precision, '1000'::double precision, '2500'::double precision, true::boolean, '4'::double precision, '1'::double precision, '.15'::double precision, '34'::double precision, '.5'::double precision, '3'::double precision, true::boolean, '10'::integer, '.8'::double precision, '7'::double precision, false::boolean, '3'::integer)"""
    #queryStr = "INSERT INTO public.\"tablaCabidaNormativa\" (\"DISTANCIAMIENTO\", \"ANTEJARDIN\", \"RASANTE\", \"RASANTESOMBRA\", \"ALTURAMAX\", \"MAXPISOS\", \"COEFOCUPACION\", \"SUBPREDIALMIN\", \"DENSIDADMAX\", \"FLAGDENSIDADBRUTA\", \"COEFCONSTRUCTIBILIDAD\", \"ESTACIONAMIENTOSPORVIV\", \"PORCADICESTACVISITAS\", \"SUPPORESTACIONAMIENTO\", \"ESTBICICLETAPOREST\", \"BICICLETASPOREST\", \"FLAGCAMBIOESTPORBICICLETA\", \"MAXSUBTE\", \"COEFOCUPACIONEST\", \"SEPESTMIN\", \"REDUCCIONESTPORDISTMETRO\", \"id_Normativa\") VALUES ('4', '4', '2.75', '5', '60', '30', '0.7', '1000', '2500', true, '4', '1', '.15', '34', '.5', '3', true, '10', '.8', '7', false, '5')"
    #queryStr = """
    #            SELECT *
    #            FROM public."tablaCabidaNormativa"
    #            WHERE "DISTANCIAMIENTO" = 5
    #            ORDER BY "DISTANCIAMIENTO";
    #            """
    #queryStr = """
    #            DELETE FROM public."tablaCabidaNormativa" WHERE "id_Normativa">1;
    #            """
    try
        result = execute(conn, queryStr; throw_error = false)
        if length(result) >= 1
            df = myDataFrame(result)
            if !isempty(df)
                return df
            end
        else
            return []
        end
    catch
        return []
    end
end

function myDataFrame(result)
    df = DataFrame(result)
    columnsAsSymbol = propertynames(df)
    typeList = [Int64, Float64]
    for c in columnsAsSymbol
        for tl in typeList
            if tl <: eltype.(df[:,c][1])
                df[!, c] = convert.(tl, df[:, c])
            end 
            
        end
    end
    return df
end

function appendToTable!(conn::LibPQ.Connection, tableStr::String, df::DataFrame, id::Symbol)
    #df_out = pg_julia.appendToTable!(conn, "tablaCabidaNormativa", df, :id_Normativa)
    #id_max = maximum(df[!, id])
    #df[!, id] .= Int64.(round.(df[!, id]; digits = 0) .+ id_max)
    dfStr = imap(eachrow(df)) do row
        join((ismissing(x) ? "" : x for x in row), ",") * "\n"
    end
    copyinStr = LibPQ.CopyIn("COPY public.\"$tableStr\" FROM STDIN (FORMAT CSV);", dfStr)
    execute(conn, copyinStr)
    df_out = pg_julia.query(conn, """SELECT * FROM public."$tableStr";""")
    return df_out
end


function createTable(conn::LibPQ.Connection, tableNameStr, vecColumnNames, vecColumnType, primaryKeyStr)
    #vecColumnNames = ["DISTANCIAMIENTO", "ANTEJARDIN", "RASANTE", "RASANTESOMBRA", "ALTURAMAX", "MAXPISOS", "COEFOCUPACION", "SUBPREDIALMIN", "DENSIDADMAX", "FLAGDENSIDADBRUTA", "COEFCONSTRUCTIBILIDAD", "ESTACIONAMIENTOSPORVIV", "PORCADICESTACVISITAS", "SUPPORESTACIONAMIENTO", "ESTBICICLETAPOREST", "BICICLETASPOREST", "FLAGCAMBIOESTPORBICICLETA", "MAXSUBTE", "COEFOCUPACIONEST", "SEPESTMIN", "REDUCCIONESTPORDISTMETRO", "id_Normativa"]
    #vecColumnType = ["float8", "float8", "float8", "float8", "float8", "int8", "float8", "float8", "float8", "bool", "float8", "float8", "float8", "float8", "float8", "float8", "bool", "int8", "float8", "float8", "bool", "int8"]
    #df = pg_julia.createTable(conn, "tablaprueba", vecColumnNames, vecColumnType, "id_Normativa")
    tableNameStr = lowercase(tableNameStr)
    columnStr = join((string("\"", x, "\"", " ", "\"", y, "\"") for (x, y) in zip(vecColumnNames, vecColumnType)), ", ")
    executeStr = "CREATE TABLE $tableNameStr (" * columnStr * ", PRIMARY KEY ( \"$primaryKeyStr\" )" * ");"
    pg_julia.query(conn, executeStr)
    df_out = pg_julia.query(conn, """SELECT * FROM public."$tableNameStr";""")
    return df_out
end


function deleteTable(conn::LibPQ.Connection, tableNameStr::String)
    #pg_julia.deleteTable(conn, "tablaPrueba")
    tableNameStr = lowercase(tableNameStr)
    executeStr = """DROP TABLE IF EXISTS public."$tableNameStr";"""
    pg_julia.query(conn, executeStr)
end


function deleteRows!(conn::LibPQ.Connection, tableNameStr::String, columnNameCondStr::String, deleteCondStr::String)
    #df_out = pg_julia.deleteRows!(conn, "tablaCabidaNormativa", "id_Normativa", ">=2")
    executeStr = """DELETE FROM public."$tableNameStr" WHERE "$columnNameCondStr" $deleteCondStr;"""
    pg_julia.query(conn, executeStr)
    df_out = pg_julia.query(conn, """SELECT * FROM public."$tableNameStr";""")
    return df_out
end


function insertRow!(conn::LibPQ.Connection, tableNameStr::String, vecColumnNames, vecColumnValue, id::Symbol)
    #vecColumnNames = ["DISTANCIAMIENTO", "ANTEJARDIN", "RASANTE", "RASANTESOMBRA", "ALTURAMAX", "MAXPISOS", "COEFOCUPACION", "SUBPREDIALMIN", "DENSIDADMAX", "FLAGDENSIDADBRUTA", "COEFCONSTRUCTIBILIDAD", "ESTACIONAMIENTOSPORVIV", "PORCADICESTACVISITAS", "SUPPORESTACIONAMIENTO", "ESTBICICLETAPOREST", "BICICLETASPOREST", "FLAGCAMBIOESTPORBICICLETA", "MAXSUBTE", "COEFOCUPACIONEST", "SEPESTMIN", "REDUCCIONESTPORDISTMETRO", "id_Normativa"]
    #vecColumnValue = ["4", "4", "2.75", "5", "60", "30", "0.7", "1000", "2500", "true", "4", "1", ".15", "34", ".5", "3", "true", "10", ".8", "7", "false", "20"]
    #df_out = pg_julia.insertRow!(conn, "tablaCabidaNormativa", vecColumnNames, vecColumnValue, :id_Normativa)
    df = pg_julia.query(conn, """SELECT * FROM public."$tableNameStr";""")
    
    posId = findall(x -> x == string(id), vecColumnNames)[1]
    if !isempty(df)
        numRows, numColumns = size(df)
        id_max = maximum(df[!, id])
    else
        id_max = 0
    end
    vecColumnValue[posId] = string(id_max + 1)
    columnNameStr = join((string("\"", x, "\"") for x in vecColumnNames), ", ")
    columnValueStr = join((string("\'", x, "\'") for x in vecColumnValue), ", ")
    executeStr = "INSERT INTO public.\"$tableNameStr\" (" * columnNameStr * ") VALUES (" * columnValueStr * ");"
    pg_julia.query(conn, executeStr)
    # df_out = pg_julia.query(conn, """SELECT * FROM public."$tableNameStr";""")
    df_out = []
    return df_out
end


#UPDATE table_name SET column1 = value1, column2 = value2...., columnN = valueN WHERE [condition];
function modifyRow!(conn::LibPQ.Connection, tableNameStr::String, vecColumnNames, vecColumnValue, columnNameCondStr::String, modifyCondStr::String)
    #vecColumnNames = ["DISTANCIAMIENTO", "ANTEJARDIN"]
    #vecColumnValue = ["4", "4"]
    #df_out = pg_julia.modifyRow!(conn, "tablaCabidaNormativa", vecColumnNames, vecColumnValue, "RASANTE", ">=2.75")
    columnStr = join((string("\"", x, "\"", "=", y) for (x, y) in zip(vecColumnNames, vecColumnValue)), ", ")
    executeStr = "UPDATE public.\"$tableNameStr\" SET " * columnStr * " WHERE \"$columnNameCondStr\" $modifyCondStr;"
    pg_julia.query(conn, executeStr)
    #df_out = pg_julia.query(conn, """SELECT * FROM public."$tableNameStr";""")
    df_out = []
    return df_out
end


function df2csv(df::DataFrames.DataFrame, outfileStr::String)
    CSV.write(outfileStr, df)
end

function csv2df(infileStr::String)
    DataFrame(CSV.File(infileStr))
end

function df2xlsx(df::DataFrames.DataFrame, outfileStr::String)
    
    XLSX.openxlsx(outfileStr,mode="w") do xf
         XLSX.addsheet!(xf,"data")
         sheet = xf["data"]
         columnNames = names(df)
         c = 0
         for cn in columnNames
            c += 1
            sheet[XLSX.CellRef(1 , c )] = cn

         end
         for r in eachindex(df[:,1]), c in eachindex(names(df))
              sheet[XLSX.CellRef(r+1 , c )] = df[r,c]
         end
    end

end

function close_db(conn)
    LibPQ.close(conn::LibPQ.Connection)
end

export connection, query, simpleQuery, appendToTable!, createTable, deleteTable, deleteRows!, insertRow!, modifyRow!, 
        df2csv, csv2df, df2xlsx, close_db


end


"""
anteJardin = df.ANTEJARDIN

nombreColumnas = names(df)
nombreColumnasAsSymbol = propertynames(df)

df[:, [:RASANTE, :RASANTESOMBRA]]
df[:, :RASANTE]
df[[1,3], [:RASANTE, :ANTEJARDIN]]

df_byRows = eachrow(df)
row_2 = df_byRows[2]
row_3_Antejardin = df_byRows[3][:ANTEJARDIN]

select(df, Not(:RASANTE)) # Selecciona columnas que no contienen :RASANTE
select(df, (r"RASAN")) # Selecciona columnas que contienen :RASAN*
"""