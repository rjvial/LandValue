module expression_converter

function convert_ternary(expr::String)
    """
    Convert Python ternary operator to Julia ternary operator.
    Python: value_if_true if condition else value_if_false
    Julia:  condition ? value_if_true : value_if_false
    """
    
    # Handle the specific case of expressions inside parentheses
    # Look for patterns like: ( something if condition else something )
    
    result = expr
    
    # First, handle ternary expressions inside parentheses
    paren_ternary_pattern = r"\(\s*([^()]+?)\s+if\s+([^()]+?)\s+else\s+([^()]+?)\s*\)"
    result = replace(result, paren_ternary_pattern => s"(\2 ? \1 : \3)")
    
    # Then handle simple ternary expressions (no parentheses)
    simple_ternary_pattern = r"([^()]+?)\s+if\s+([^()]+?)\s+else\s+([^()]+?)(?=\s*[)}\],]|\s*$)"
    result = replace(result, simple_ternary_pattern => s"\2 ? \1 : \3")
    
    return result
end

function parse_python_expression(py_expr::String)
    """
    Parse a Python expression string and convert it to Julia syntax.
    
    Handles common Python constructs like:
    - Ternary operators (a if condition else b)
    - Boolean operators (and, or, not)
    - Comparison operators (==, !=, etc.)
    - Mathematical operators
    - Variable names and literals
    """
    
    expr = py_expr
    expr = convert_ternary(expr)
    
    # Handle boolean operators
    expr = replace(expr, r"\band\b" => " && ")
    expr = replace(expr, r"\bor\b" => " || ")
    expr = replace(expr, r"\bnot\b" => " ! ")
    
    # Handle None/True/False
    expr = replace(expr, r"\bNone\b" => "nothing")
    expr = replace(expr, r"\bTrue\b" => "true")
    expr = replace(expr, r"\bFalse\b" => "false")
    
    # Handle Python's != operator (Julia uses != as well, but let's be explicit)
    expr = replace(expr, "!=" => "!=")
    
    return expr
end

export convert_ternary, parse_python_expression

end