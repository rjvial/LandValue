module expression_converter

export convert_ternary, convert_walrus_operator, convert_list_comprehension,
       convert_dictionary_literal, parse_python_expression, test_converter

"""
Convert Python ternary operator to Julia ternary operator.
Python: value_if_true if condition else value_if_false, and function-call: if(condition, value_if_true, value_if_false)
Julia:  condition ? value_if_true : value_if_false

Handles nested ternary operators and function-call style ternaries by processing them systematically.
"""
function convert_ternary(expr::String)
    result = expr
    # First, handle function-call style ternary: if(condition, value_if_true, value_if_false)
    func_pattern = r"if\s*\(\s*(.+?)\s*,\s*(.+?)\s*,\s*(.+?)\s*\)"
    max_iterations = 20
    for i in 1:max_iterations
        m = match(func_pattern, result)
        m === nothing && break

        condition      = strip(m.captures[1])
        value_if_true  = strip(m.captures[2])
        value_if_false = strip(m.captures[3])

        # wrap in () to keep parse-tree unambiguous
        replacement = "(" * condition * " ? " * value_if_true * " : " * value_if_false * ")"
        result = result[1:m.offset-1] * replacement * result[m.offset+length(m.match):end]
    end

    # Now handle Python-style ternary: value_if_true if condition else value_if_false
    simple_ternary = r"(.+?)\s+if\s+(.+?)\s+else\s+(.+?)(?=\s*[)}\],]|\s*$)"
    for i in 1:max_iterations
        m = match(simple_ternary, result)
        m === nothing && break

        value_if_true  = strip(m.captures[1])
        condition      = strip(m.captures[2])
        value_if_false = strip(m.captures[3])

        # wrap in () to keep parse-tree unambiguous
        replacement = "(" * condition * " ? " * value_if_true * " : " * value_if_false * ")"
        result = result[1:m.offset-1] * replacement * result[m.offset+length(m.match):end]
    end

    return result
end

"""
Convert Python walrus operator (:=) to Julia assignment.
Python: (variable := expression)
Julia:  (variable = expression)
"""
convert_walrus_operator(expr::String) = replace(expr, ":=" => "=")

"""
Convert Python list comprehensions and generator expressions to Julia comprehensions.
Also ensures multi-variable zip loops are parenthesized.
"""
function convert_list_comprehension(expr::String)
    result = expr

    # 1) generator expressions inside function calls with zip(...)
    generator_zip_pattern = r"(\w+)\(([^()]+?)\s+for\s+([^()]+?)\s+in\s+zip\(([^()]+?)\)\)"
    while true
        m = match(generator_zip_pattern, result)
        m === nothing && break
        func_name, expression, variables, zip_args = m.captures
        if !startswith(variables, "(") || !endswith(variables, ")")
            variables = "(" * variables * ")"
        end
        replacement = string(func_name, "(", expression, " for ", variables, " in zip(", zip_args, "))")
        result = replace(result, m.match => replacement, count=1)
    end

    # 2) list comprehensions with zip(...)
    zip_pattern = r"\[([^\[\]]+?)\s+for\s+([^\[\]]+?)\s+in\s+zip\(([^()]+?)\)\]"
    while true
        m = match(zip_pattern, result)
        m === nothing && break
        expression, variables, zip_args = m.captures
        if !startswith(variables, "(") || !endswith(variables, ")")
            variables = "(" * variables * ")"
        end
        replacement = "[" * expression * " for " * variables * " in zip(" * zip_args * ")]"
        result = replace(result, m.match => replacement, count=1)
    end

    # 3) parenthesized generator expressions with zip(...)
    paren_zip_pattern = r"\(([^()]+?)\s+for\s+([^()]+?)\s+in\s+zip\(([^()]+?)\)\)"
    while true
        m = match(paren_zip_pattern, result)
        m === nothing && break
        expression, variables, zip_args = m.captures
        if !startswith(variables, "(") || !endswith(variables, ")")
            variables = "(" * variables * ")"
        end
        replacement = "(" * expression * " for " * variables * " in zip(" * zip_args * "))"
        result = replace(result, m.match => replacement, count=1)
    end

    # 4) wrap any unhandled multi-variable zip loops in parentheses
    result = replace(result,
        r"for\s+([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)+)\s+in\s+zip\(" =>
        s"for (\1) in zip(")

    return result
end

"""
Convert Python dictionary literals to Julia Dict syntax with proper variable scoping.
Python: {'key': value, ...}
Julia:  Dict("key" => value, ...)

This version creates a let block to handle variable dependencies within the dictionary.
"""
function convert_dictionary_literal(expr::String)
    result = expr
    stripped = strip(result)
    if startswith(stripped, "{") && endswith(stripped, "}")
        # Remove the outer braces
        inner_content = String(strip(stripped[2:end-1]))
        
        # Split by commas (but be careful about nested structures)
        pairs = split_dict_pairs(inner_content)
        
        # Parse all key-value pairs
        parsed_pairs = []
        for pair in pairs
            # Split on the first colon to separate key and value
            colon_pos = findfirst(':', pair)
            if colon_pos !== nothing
                key_part = strip(pair[1:colon_pos-1])
                value_part = strip(pair[colon_pos+1:end])
                
                # Convert key quotes
                key_part = replace(key_part, r"'([^']+)'" => s"\"\1\"")
                clean_key = replace(key_part, "\"" => "")
                
                push!(parsed_pairs, (key_part, clean_key, value_part))
            end
        end
        
        # Check if we need variable assignments (if any value references other keys)
        all_keys = Set([clean_key for (_, clean_key, _) in parsed_pairs])
        needs_assignments = false
        
        for (_, clean_key, value_part) in parsed_pairs
            for other_key in all_keys
                if other_key != clean_key && contains(value_part, other_key)
                    needs_assignments = true
                    break
                end
            end
            if needs_assignments
                break
            end
        end
        
        if needs_assignments
            # Create let block with variable assignments
            result = "let\n"
            
            # Create assignments for each variable
            for (key_part, clean_key, value_part) in parsed_pairs
                result *= "    $clean_key = $value_part\n"
            end
            
            # Create the Dict with references to the variables
            result *= "    Dict(\n"
            dict_entries = String[]
            for (key_part, clean_key, value_part) in parsed_pairs
                push!(dict_entries, "        \"$clean_key\" => $clean_key")
            end
            result *= join(dict_entries, ",\n")
            result *= "\n    )\n"
            result *= "end"
        else
            # No interdependencies, just create the Dict directly
            result = "Dict(\n"
            dict_entries = String[]
            for (key_part, clean_key, value_part) in parsed_pairs
                push!(dict_entries, "    \"$clean_key\" => $value_part")
            end
            result *= join(dict_entries, ",\n")
            result *= "\n)"
        end
    end
    return result
end

"""
Helper function to split dictionary pairs while respecting nested structures.
"""
function split_dict_pairs(content::AbstractString)
    pairs = String[]
    current_pair = ""
    paren_count = 0
    bracket_count = 0
    brace_count = 0
    in_string = false
    string_char = ' '
    
    i = 1
    while i <= length(content)
        char = content[i]
        
        if !in_string && (char == '"' || char == '\'')
            in_string = true
            string_char = char
        elseif in_string && char == string_char
            in_string = false
        elseif !in_string
            if char == '('
                paren_count += 1
            elseif char == ')'
                paren_count -= 1
            elseif char == '['
                bracket_count += 1
            elseif char == ']'
                bracket_count -= 1
            elseif char == '{'
                brace_count += 1
            elseif char == '}'
                brace_count -= 1
            elseif char == ',' && paren_count == 0 && bracket_count == 0 && brace_count == 0
                push!(pairs, strip(current_pair))
                current_pair = ""
                i += 1
                continue
            end
        end
        
        current_pair *= char
        i += 1
    end
    
    if !isempty(strip(current_pair))
        push!(pairs, strip(current_pair))
    end
    
    return pairs
end

"""
Parse a Python expression and convert to Julia.
Handles walrus, comprehensions, ternaries, dicts, booleans, None/True/False, etc.
"""
function parse_python_expression(py_expr::String)
    expr = py_expr
    expr = convert_walrus_operator(expr)
    expr = convert_list_comprehension(expr)
    expr = convert_ternary(expr)
    expr = convert_dictionary_literal(expr)
    expr = replace(expr, r"\band\b" => " && ")
    expr = replace(expr, r"\bor\b"  => " || ")
    expr = replace(expr, r"\bnot\b" => " ! ")
    expr = replace(expr, r"\bNone\b"  => "nothing")
    expr = replace(expr, r"\bTrue\b"  => "true")
    expr = replace(expr, r"\bFalse\b" => "false")
    # Python's != maps directly to != in Julia
    return expr
end

end # module