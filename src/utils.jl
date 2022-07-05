function check_gl_logs(context::String)
    logs = pull_gl_logs()
    for log in pull_gl_logs()
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
end

"Asserts for this specific project: `@bpworld_assert`, `@bpworld_debug`."
@make_toggleable_asserts bpworld_
bpworld_asserts_enabled() = false