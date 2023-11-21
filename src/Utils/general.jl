"
Removes a type declaration.
This allows you to make a 'default' implementation that explicitly lists types,
    but doesn't risk ambiguity with more specific overloads.
"
macro omit_type(var_decl)
    @assert(Meta.isexpr(var_decl, :(::)) && isa(var_decl.args[1], Symbol),
            "Expected a typed variable declaration, got: $var_decl")
    return esc(var_decl.args[1])
end


"Checks and prints any messages/errors from OpenGL. Does nothing in release mode."
function check_gl_logs(context::String)
    @bpworld_debug for log in pull_gl_logs()
        if log.severity in (DebugEventSeverities.high, DebugEventSeverities.medium)
            @error "While $context. $(sprint(show, log))"
        elseif log.severity == DebugEventSeverities.low
            @warn "While $context. $(sprint(show, log))"
        elseif log.severity == DebugEventSeverities.none
            @info "While $context. $(sprint(show, log))"
        else
            error("Unhandled case: ", log.severity)
        end
    end
    return nothing
end


"
Simplifies a common design pattern for data containing B+ GL resources.
Defines `Base.close()` for a type to iterate through its fields, and calling `close()` on any resources.

You may also provide extra iterables of objects to call `close()` on.

Example:

````
@close_gl_resources(x::MyAssets, values(x.texture_lookup), x.my_file_handles)
````
"
macro close_gl_resources(object, iterators...)
    if !@capture(object, name_Symbol::type_)
        error("Expected first argument to be in the form 'name::Type'. Got: ", object)
    end
    object = esc(object)
    name = esc(name)
    type = esc(type)
    iterators = esc.(iterators)
    return :(
        function Base.close($object)
            resources = Iterators.flatten(tuple(
                Iterators.filter(field -> field isa $(Bplus.GL.AbstractResource),
                                 getfield.(Ref($name), fieldnames($type))),
                $(iterators...)
            ))
            for r in resources
                close(r)
            end
        end
    )
end