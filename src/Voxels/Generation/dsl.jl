# Defines the parsing of some Julia syntax structures into voxel generators.

"
Holds any information needed when parsing the DSL.
The DSL parser may also mutate certain fields.
"
Base.@kwdef mutable struct DslState
    # Variables that DSL expressions can reference.
    # New expressions can add new variables to this lookup.
    vars::Dict{Symbol, Any} = Dict{Symbol, Any}()

    # The current context of the parser, sort of like a function stack.
    # If an error occurs, the full context is printed.
    # Each element is a tuple that's splatted when printing.
    context::Stack{Tuple} = Stack{Tuple}()
end

"Plain scalar data types for the DSL."
const DslScalar = Union{ScalarBits, Bool}
"Plain vector data types for the DSL."
const DslVector = VecT{<:DslScalar}

const DslPrimitive = Union{DslScalar, DslVector}


##   Internal helpers   ##

"
Adds a message to the context stack for the duration of the given function/lambda.
Returns the output of the lambda.
"
function dsl_context_block(to_do, state::DslState, new_context...)
    # Note that if an exception is thrown, we don't handle it in any special way,
    #    and this new context information stays on the stack.
    # This is intentional; errors are caught in the root function for DSL evaluation
    #    and we need this context to be visible up there!
    push!(state.context, new_context)
    value = to_do()
    pop!(state.context)
    return value
end


##   Top-level function   ##

"
Converts parsed DSL into the `AbstactVoxelGenerator` it describes.
If an error occurred, returns an error message as a `Vector` of objects to print.

Note that simpler values such as numbers or vectors could also technically be returned,
    if that's what your DSL describes.
"
function eval_dsl(expr, state::DslState = DslState())
    try
        if Base.is_expr(expr, :toplevel) || Base.is_expr(expr, :block)
            return eval_dsl_top_level_sequence(expr.args, state)
        else
            return eval_dsl_top_level_expression(expr, 1, state)
        end
    catch e
        # Build the error printout, containing nested context.
        context_msg = Any[ "Error, in the following location:\n" ]
        context_start_idx::Int = length(context_msg) + 1
        for (shallowness::Int, context_item::Tuple) in enumerate(state.context)
            # insert!() only takes one element at a time, so we have to insert things in backwards order.

            # Put a line break at the end.
            insert!(context_msg, context_start_idx, "\n")

            # Put each element of the context into this line.
            for element_idx in length(context_item):-1:1
                element = context_item[element_idx]
                if element isa Exception
                    element = sprint(io -> showerror(io, element))
                end
                insert!(context_msg, context_start_idx, element)
            end

            # Tab in the line based on its depth.
            depth::Int = length(state.context) - shallowness + 1
            for i in 1:depth
                insert!(context_msg, context_start_idx, "  ")
            end
        end
        push!(context_msg, "\n", sprint(showerror, e))
        return context_msg
    end
end

##    Grammar evaluators   ##

"Returns the output of the given DSL code (as a series of assignment/return expressions)."
function eval_dsl_top_level_sequence(exprs, state::DslState)
    important_exprs = filter(e -> !isa(e, LineNumberNode), exprs)
    for (i, expr) in enumerate(important_exprs)
        returned_result = eval_dsl_top_level_expression(expr, i, state)
        if exists(returned_result)
            return returned_result
        end
    end
    error("No 'return' statement exists!")
end

"
Handles a top-level DSL expression, almost always mutating `state.vars`.
If it was a `return` expression, the final value is returned.
"
function eval_dsl_top_level_expression(expr, idx, state::DslState)::Optional
    if expr isa LineNumberNode
        return nothing
    else
        return dsl_context_block(state, "Root expression ", idx) do 
            #TODO: Allow definition of functions, by treating it like a new top-level context/DslState with access to pre-existing variables.
            if Base.is_expr(expr, :(=))
                (name, value_expr) = expr.args
                if !isa(name, Symbol)
                    error("Value is assigned to something other than a name: '", name, "' = ...")
                else
                    state.vars[name] = dsl_expression(value_expr, state)
                end
            elseif Base.is_expr(expr, :return)
                return dsl_expression(expr.args[1], state)
            else
                error("Top-level expression must be an assignment ('a = b') or return ('return a'). It was :",
                      (expr isa Expr) ? expr.head : typeof(expr))
            end
            return nothing
        end
    end
end


##   Interface   ##

"Given some kind of Julia data or expression, return the expression's value."
dsl_expression(expr, state::DslState) = expr # Assume it's a literal and pass it through

"Given some kind of Julia `Expr`, return the expression's value."
dsl_julia_expr(v::Val, expr_args, dsl_state) = error("Unexpected expression type: ", val_type(v))

"Given some kind of function or operator call, evaluate and return its value."
dsl_call(v::Val, args, dsl_state) = error("Unknown function/operator '", val_type(v), "'")

"
Applies the given changes to `src`.
Examples of changes:
  * `radius *= 0.5` translates to `:radius => (:*= => 0.5)`
  * `min = 1+2` translates to `:min => (:(=) => :( 1 + 2 ))`

Default behavior: calls `dsl_copy(src)`, then attempts to set the copy's properties if any are provided.
"
dsl_copy(src, changes::Dict{Any, Pair{Symbol, Any}}, dsl_state) = let dest = Ref(dsl_copy(src))
    for (prop_name, (modification, rhs)) in changes
        #TODO: If prop_name is something other than a symbol, assume it's a key/index into a collection
        dsl_context_block(dsl_state, "Property ", :prop_name) do
            dsl_copy_field(dest, prop_name, modification, rhs, dsl_state)
        end
    end
    return dest[]
end

"Overload this for making copies of data."
dsl_copy(value) = copy(value)
dsl_copy(value::Union{ScalarBits, Vec}) = value


##   Core implementations   ##

# Provide the hook for 'dsl_julia_expr()'.
dsl_expression(expr::Expr, state::DslState) = dsl_julia_expr(Val(expr.head), expr.args, state)

# Provide the hook for 'dsl_call()'.
dsl_julia_expr(::Val{:call}, args::Vector{Any}, state::DslState) = dsl_call(Val(args[1]), args[2:end], state)

# Allow the DSL to reference variables by name.
function dsl_expression(name::Symbol, state::DslState)
    if haskey(state.vars, name)
        return state.vars[name]
    else
        error("Unknown variable '", name, "'")
    end
end

# Define the 'braces' expression to construct Vec instances.
function dsl_julia_expr(::Val{:braces}, args::Vector{Any}, state::DslState)
    # Evaluate each of the arguments into vectors and scalars,
    #    then append them all together.
    evaluated_args = map(a -> dsl_expression(a, state), args)

    # Check the component types.
    if !all(a -> a isa DslPrimitive, evaluated_args)
        error("A Vec can only be made from numbers and smaller vectors. Instead found ",
              join(map(typeof, filter(a -> !(a isa DslPrimitive), evaluated_args)),
                   ", "))
    end

    # Append the args together into a single Vec.
    return vappend(evaluated_args...)
end

# Define the ability to get (and swizzle) a vector's components.
#TODO: Support index-based swizzling like the Vec type.
function dsl_julia_expr(::Val{:.}, args, dsl_state::DslState)
    (value_expr, component_expr) = args
    if !isa(component_expr, QuoteNode)
        error("Unexpected vector swizzle ", component_expr,
              " in '", value_expr, ".", component_expr, "'")
    end
    component_expr = component_expr.value

    value = dsl_expression(value_expr, dsl_state)
    if value isa DslScalar
        value = Vec(value)
    elseif !(value isa DslVector)
        error("Value should be a vector (or scalar), got ", typeof(value), ", in '",
              value_expr, ".", component_expr, "'")
    end

    return Bplus.Math.swizzle(value, component_expr)
end

"
Performs a modification to an object's property by some value, e.x. `mySphere.radius *= 5`.
Designed for use by `dsl_copy()`.
"
function dsl_copy_field(dest::Ref, prop_name::Symbol,
                        modification::Symbol, rhs_expr,
                        dsl_state::DslState
                       )::Nothing
    rhs_value = dsl_expression(rhs_expr, dsl_state)
    new_value = if modification == :(=)
                    rhs_value
                elseif haskey(ASSIGNMENT_INNER_OP, modification)
                    dynamic_modify(modification, getproperty(dest[], prop_name), rhs_value)
                else
                    error("Unsupported operator: ", modification)
                end
    if ismutable(dest[])
        setproperty!(dest[], prop_name, new_value)
    else
        assignment = merge(NamedTuple(), tuple(prop_name => new_value))
        dest[] = Setfield.setproperties(dest[], assignment)
    end
    nothing
end


function dsl_component_wise_expr(functor, args, dsl_state::DslState)
    # Evaluate the arguments.
    arguments = dsl_expression.(args, Ref(dsl_state))

    # If all arguments are scalars, then trivially invoke the function.
    if all(a -> a isa DslScalar, arguments)
        return functor(arguments...)
    # Otherwise, some arguments are vectors, so invoke the function per-component.
    else
        if !all(a -> a isa DslPrimitive, arguments)
            error("Unexpected argument types in function '", functor, "': ",
                  "[ ", join(typeof.(arguments), ", "), " ]")
        end
        # Map scalars to a Ref, and vectors to a tuple. Then use Julia's '.' syntax.
        arguments = map(a -> (a isa DslScalar) ? Ref(a) : a.data,
                        arguments)
        values = functor.(arguments...)
        return Vec(values...)
    end
end


# Generate basic scalar expressions.
for scalar_func in [ :+, :-, :*, :/, :%, :^, :÷,
                     :&, :|, :!, :~, :<<, :>>, :⊻, :⊼,
                     :(==), :!=, :<=, :>=, :<, :>,
                     :abs, :sqrt, :sign, :copysign,
                     :sin, :cos, :tan, :acos, :asin, :atan,
                     :log2, :log10, :log, :exp2, :exp10, :exp,
                     :min, :max, :floor, :ceil, :trunc, :round,
                   ]
    @eval dsl_call(::Val{$(QuoteNode(scalar_func))}, args, dsl_state) =
            dsl_component_wise_expr($scalar_func, args, dsl_state)
end


# Generate basic vector expressions.
for vector_func in [ :vdot, :vcross, :⋅, :×, :∘,
                     :vlength, :vlength_sqr,
                     :vdist, :vdist_sqr,
                     :vnorm
                   ]
    @eval dsl_call(::Val{$(QuoteNode(vector_func))}, args, dsl_state) =
            $vector_func(dsl_expression.(args, Ref(dsl_state))...)
end


# "average()" sums its values and divides by their length.
dsl_call(::Val{:average}, args, dsl_state) = +(dsl_expression.(args, Ref(dsl_state))...) /
                                               Float32(length(args))


# Generate conversion expressions, such as 'Float32(a)'.
for type in union_types(DslScalar)
    symbolized = QuoteNode(Symbol(type))
    @eval function dsl_call(::Val{$symbolized}, args, dsl_state)
        if length(args) != 1
            error("Expected exactly one argument to '",
                $symbolized, "()', got ", length(args))
        end
        value = dsl_expression(args[1], dsl_state)
        if value isa DslScalar
            return convert($type, value)
        elseif value isa DslVector
            return map($type, value)
        else
            error("Unsure how to create a number/vector from a ", typeof(value))
        end
    end
end
# Also define a converter for 'Int', 'UInt', and 'Float'/'Double'.
dsl_call(::Val{:UInt}, args, dsl_state) = dsl_call(Val(:UInt64), args, dsl_state)
dsl_call(::Val{:Int}, args, dsl_state) = dsl_call(Val(:Int64), args, dsl_state)
dsl_call(::Val{:Float}, args, dsl_state) = dsl_call(Val(:Float32), args, dsl_state)
dsl_call(::Val{:Double}, args, dsl_state) = dsl_call(Val(:Float64), args, dsl_state)

function dsl_call(::Val{:copy}, args, dsl_state)
    src_value = dsl_context_block(dsl_state, "Source value") do
        dsl_expression(args[1], dsl_state)
    end
    modifications = Dict{Any, Pair{Symbol, Any}}(map(enumerate(args[2:end])) do (i, arg)
        dsl_context_block(dsl_state, "Arg ", i) do
            # Note that the '=' operator may come in as an Expr named :kw.
            if !isa(arg, Expr) ||
               (!Base.isexpr(arg, :(=)) && !Base.isexpr(arg, :kw) && !haskey(ASSIGNMENT_INNER_OP, arg.head))
            #begin
                error("Expected an assignment expression, like 'x += 5'). Got \"", arg, "\"")
            end
            head = (Base.isexpr(arg, :kw) ? :(=) : arg.head)
            return arg.args[1] => (head => arg.args[2])
        end
    end)
    return dsl_copy(src_value, modifications, dsl_state)
end


#TODO: DslState holds a PRNG, and "rand([min][, max])" function is implemented using it
#TODO: Add noise (e.x. perlin) after the above TODO is done
#TODO: Simple loop (e.x. "repeat(1:10) do i ... end")
#TODO: Special mutations of existing variables (e.x. "push!(my_arr, 5 + 8)")