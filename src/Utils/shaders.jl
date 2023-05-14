
"
Any shader code before this token is removed.
This allows you to add things for the IDE/linter only.
"
const SHADER_CUTOFF_TOKEN = "#J#J#"

"Processes a shader file to remove the `SHADER_CUTOFF_TOKEN` and execute `#include` statements."
function process_shader_contents(str::AbstractString, insert_at_top::AbstractString = "")::AbstractString
    # First, cut off everything above the special cutoff token.
    while true
        try_find::Optional{UnitRange{Int}} = findfirst(SHADER_CUTOFF_TOKEN, str)
        if isnothing(try_find)
            break
        else
            #TODO: Insert a '#line' statement (should be easy here, just count newlines).
            str = str[last(try_find)+1 : end]
        end
    end

    # Next, inject any desired code at the top of the file.
    str = "$insert_at_top\n$str"

    # Finally, recursively evaluate include statements.
    included_already = Set{AbstractString}() # Don't double-include
    while true
        try_find::Optional{UnitRange{Int}} = findfirst("#include", str)
        if isnothing(try_find)
            break
        else
            stop_idx = findnext('\n', str, last(try_find))
            if isnothing(stop_idx)
                stop_idx = length(str)
            end
            after_directive = @view str[last(try_find):stop_idx]
            # Find the opening of the file name.
            name_start = findfirst('"', after_directive)
            name_end_char = '"'
            if isnothing(name_start)
                name_start = findfirst('<', after_directive)
                name_end_char = '>'
                if isnothing(name_start)
                    error("Couldn't find the name for an #include statement")
                end
            end
            # Find the closing of the file-name.
            after_name_opening = @view after_directive[name_start + 1 : end]
            name_end = findfirst(name_end_char, after_name_opening)
            if isnothing(name_end)
                error("Couldn't find the end of the file-name for an #include statement")
            end
            # Calculate the exact position of the include statement and the file-name;
            #     'name_start' and 'name_end' are both relative indices.
            name_start_idx = last(try_find) + name_start
            name_end_idx = name_start_idx + name_end - 2
            file_name = @view str[name_start_idx:name_end_idx]
            include_statement_range = first(try_find):(name_end_idx+1)
            # Read the file that was included.
            file_path = abspath(joinpath(ASSETS_PATH, file_name))
            local file_contents::AbstractString
            if file_path in included_already
                file_contents = ""
            elseif !isfile(file_path)
                file_contents = "#error File not found: \"$file_path\""
            else
                push!(included_already, file_path)
                file_contents = String(open(read, file_path, "r"))
                # Inject a '#line' directive before and afterwards.
                incoming_line = "#line 1"
                # The line directive afterwards is hard to count, so for now
                #    set it to an obviously-made-up value to prevent red-herrings.
                #TODO: If we process includes from last to first, then line counts would be correct. However, we'd have to keep moving the included code backwards to the first instance of each file being included. So you'd have to insert stand-in tokens that get replaced at the end of include processing.
                outgoing_line = "#line 99999"
                file_contents = "$incoming_line\n$file_contents\n$outgoing_line"
            end
            # Update the file for the include() statement.
            str_chars = collect(str)
            splice!(str_chars, include_statement_range, file_contents)
            str = String(str_chars)
        end
    end

    return str
end
