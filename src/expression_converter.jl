module expression_converter

export convert_ternary, convert_walrus_operator, convert_list_comprehension,
       convert_dictionary_literal, parse_python_expression, test_converter, fix_julia_syntax

"""
Convert Python ternary operator to Julia ternary operator.
Python: value_if_true if condition else value_if_false, and function-call: if(condition, value_if_true, value_if_false)
Julia:  condition ? value_if_true : value_if_false

Handles nested ternary operators and function-call style ternaries by processing them systematically.
Improved version that better handles nested ternary expressions and parenthesization.
"""
function convert_ternary(expr::String)
    result = expr
    
    # First, handle function-call style ternary: if(condition, value_if_true, value_if_false)
    # Use more sophisticated parsing to handle nested parentheses
    max_iterations = 20
    for i in 1:max_iterations
        changed = false
        
        # Find if( pattern and parse carefully
        if_pos = findfirst("if(", result)
        if if_pos !== nothing
            start_pos = if_pos[end] + 1  # Position after "if("
            paren_count = 1
            current_pos = start_pos
            parts = String[]
            current_part = ""
            
            while current_pos <= length(result) && paren_count > 0
                char = result[current_pos]
                
                if char == '('
                    paren_count += 1
                    current_part *= char
                elseif char == ')'
                    paren_count -= 1
                    if paren_count == 0
                        push!(parts, strip(current_part))
                        break
                    else
                        current_part *= char
                    end
                elseif char == ',' && paren_count == 1
                    push!(parts, strip(current_part))
                    current_part = ""
                else
                    current_part *= char
                end
                
                current_pos += 1
            end
            
            if length(parts) == 3 && paren_count == 0
                condition = parts[1]
                value_if_true = parts[2]
                value_if_false = parts[3]
                
                # Create properly parenthesized replacement
                replacement = "((" * condition * ") ? (" * value_if_true * ") : (" * value_if_false * "))"
                
                # Replace in the original string
                end_pos = current_pos
                result = result[1:if_pos[1]-1] * replacement * result[end_pos+1:end]
                changed = true
            end
        end
        
        if !changed
            break
        end
    end

    # Now handle Python-style ternary: value_if_true if condition else value_if_false
    # Use a more careful approach to handle nested expressions
    for i in 1:max_iterations
        changed = false
        
        # Look for the pattern, but be more careful about boundaries
        if_matches = collect(eachmatch(r"\bif\b", result))
        
        for if_match in if_matches
            if_pos = if_match.offset
            
            # Find corresponding 'else'
            else_matches = collect(eachmatch(r"\belse\b", result[if_pos:end]))
            if isempty(else_matches)
                continue
            end
            
            else_pos = if_pos + else_matches[1].offset - 1
            
            # Extract the three parts more carefully
            # Look backwards from 'if' to find value_if_true
            true_start = 1
            for j in (if_pos-1):-1:1
                char = result[j]
                if char in ['(', '[', '{', ',', '=', '&', '|', '!', '?', ':', '\n', '\t', ' ']
                    if char in [' ', '\t']
                        continue  # Skip whitespace
                    else
                        true_start = j + 1
                        break
                    end
                end
            end
            
            # Extract parts
            value_if_true = strip(result[true_start:if_pos-1])
            
            # Find condition (between 'if' and 'else')
            condition_start = if_pos + 2  # after "if"
            condition_end = else_pos - 1   # before "else"
            condition = strip(result[condition_start:condition_end])
            
            # Find value_if_false (after 'else')
            false_start = else_pos + 4  # after "else"
            false_end = length(result)
            
            # Look for natural boundaries for value_if_false
            for j in false_start:length(result)
                char = result[j]
                if char in [')', ']', '}', ',', '\n', ';']
                    false_end = j - 1
                    break
                end
            end
            
            value_if_false = strip(result[false_start:false_end])
            
            # Skip if any part is empty or if this doesn't look like a valid ternary
            if isempty(value_if_true) || isempty(condition) || isempty(value_if_false)
                continue
            end
            
            # Create properly parenthesized replacement
            replacement = "((" * condition * ") ? (" * value_if_true * ") : (" * value_if_false * "))"
            
            # Replace in the original string
            result = result[1:true_start-1] * replacement * result[false_end+1:end]
            changed = true
            break  # Process one at a time
        end
        
        if !changed
            break
        end
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
Fix common Julia syntax issues that can occur during Python to Julia conversion.
"""
function fix_julia_syntax(expr::String)
    result = expr
    
    # Fix range operator issues in function calls
    # Convert patterns like min(1 : max(...)) to min(1, max(...))
    result = replace(result, r"min\(\s*(\d+(?:\.\d+)?)\s*:\s*" => s"min(\1, ")
    result = replace(result, r"max\(\s*(\d+(?:\.\d+)?)\s*:\s*" => s"max(\1, ")
    
    # Fix any remaining colon issues in function calls
    # Look for patterns like func(arg1 : arg2) and convert to func(arg1, arg2)
    # But be careful not to affect ternary operators
    result = replace(result, r"(\w+)\(([^():?]+)\s*:\s*([^():?,]+)\)" => s"\1(\2, \3)")
    
    # Ensure proper spacing around ternary operators
    result = replace(result, r"\?\s*([^:]+?)\s*:" => s"? \1 :")
    
    # Fix any double operators that might have been created
    result = replace(result, r"\s*,\s*," => ",")
    result = replace(result, r"\(\s*," => "(")
    result = replace(result, r",\s*\)" => ")")
    
    # Fix potential issues with nested parentheses in ternary operators
    # Ensure spaces around ? and : in ternary expressions
    result = replace(result, r"([^?\s])\?" => s"\1 ?")
    result = replace(result, r"\?([^?\s])" => s"? \1")
    result = replace(result, r"([^:\s]):" => s"\1 :")
    result = replace(result, r":([^:\s])" => s": \1")
    
    return result
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
    expr = replace(expr, r"'([^']*)'" => s"\"\1\"")

    # Add the syntax fix as the final step
    expr = fix_julia_syntax(expr)
    
    # Python's != maps directly to != in Julia
    return expr
end

"""
Test function to verify the converter works correctly.
"""
function test_converter()
    test_cases = [
        "x if condition else y",
        "if(condition, x, y)",
        "[x for x in items]",
        "{'key': value}",
        "x := y",
        "True and False or None",
        "min(1, max(0, x))",
        "max(true * (2.55 / 5), (flag_vano ? 3 + min(1, max(0, 2.55 - 7)) : 1.4))"
    ]
    
    println("Testing expression converter:")
    for test_case in test_cases
        result = parse_python_expression(test_case)
        println("Input:  ", test_case)
        println("Output: ", result)
        println()
    end
end

end # module