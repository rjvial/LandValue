function generate_stack_vector(pisos_tot, num_stacks)
    if num_stacks <= 0 || pisos_tot < 0
        return Vector{Vector}()
    end

    results = Vector{Vector}()

    function backtrack(current_vec::Vector, remaining_sum, remaining_positions)
        # Base case: filled all positions
        if remaining_positions == 0
            if remaining_sum == 0
                push!(results, copy(current_vec))
            end
            return
        end

        # Determine the maximum we can place here:
        #  • can’t exceed remaining_sum
        #  • must be ≤ last element (to enforce non-increasing order)
        max_val = remaining_sum
        if !isempty(current_vec)
            max_val = min(max_val, current_vec[end])
        end

        # Try all values from 0 up to that max
        for val in 0:max_val
            push!(current_vec, val)
            backtrack(current_vec, remaining_sum - val, remaining_positions - 1)
            pop!(current_vec)
        end
    end

    backtrack(Int[], pisos_tot, num_stacks)
    return results
end
