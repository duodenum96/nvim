# Run JET analyses on calls sent from Neovim.
#
# Loaded with `julia -L` by REPLs started from Neovim (see 'plugin/58_jet.lua'),
# which set `NVIM_JET_DIR`. Reports are shown in the REPL as usual and are also
# written into that directory, which Neovim watches to fill the quickfix list
# and diagnostics.
#
# Entry points (sent by Neovim, but can also be typed):
# - `NvimJET.@report_opt f(args...)`  - type instabilities (runtime dispatch)
# - `NvimJET.@report_call f(args...)` - type errors
# - `NvimJET.report_file(path)`       - errors in the whole file
# - `NvimJET.@bench f(args...)`       - `@btime` with interpolated arguments
module NvimJET

const dir = ENV["NVIM_JET_DIR"]

# Packages are loaded on first use, so that REPL starts fast. They should be
# installed into the global environment.
function load(pkg::Symbol)
    isdefined(@__MODULE__, pkg) && return
    try
        Core.eval(@__MODULE__, :(import $pkg))
    catch err
        err isa ArgumentError || rethrow()
        env = "@v$(VERSION.major).$(VERSION.minor)"
        error("$pkg is not installed. Install it into the global environment with ",
              "`julia --project=$env -e 'using Pkg; Pkg.add(\"$pkg\")'`")
    end
    return
end

oneline(x) = replace(strip(string(x)), r"\s*\n\s*" => " ", '\t' => ' ')

# Write lines at once, so that Neovim never reads a partial file
function write_result(lines)
    name = "jet-$(time_ns()).tsv"
    tmp = joinpath(dir, "." * name)
    write(tmp, isempty(lines) ? "" : join(lines, '\n') * '\n')
    mv(tmp, joinpath(dir, name))
    return
end

# Show error in REPL without a long stack trace of this module
function show_error(err)
    printstyled(stderr, "ERROR: "; bold = true, color = :red)
    showerror(stderr, err)
    println(stderr)
    return
end

macro report_opt(ex)
    return :(run(:report_opt, $(QuoteNode(ex))))
end

macro report_call(ex)
    return :(run(:report_call, $(QuoteNode(ex))))
end

report_file(path::AbstractString) = run(:report_file, path)

function run(kind::Symbol, arg)
    try
        load(:JET)
        # Loaded package can only be used in the latest world
        result, lines = Base.invokelatest(analyze, kind, arg)
        write_result(lines)
        return result
    catch err
        write_result(["error\t" * oneline(sprint(showerror, err))])
        show_error(err)
        return nothing
    end
end

function analyze(kind::Symbol, arg)
    result = if kind === :report_file
        JET.report_file(arg)
    else
        # Like typing JET's macro in the REPL: arguments are evaluated in `Main`
        jet_macro = GlobalRef(JET, Symbol('@', kind))
        Core.eval(Main, Expr(:macrocall, jet_macro, LineNumberNode(0, :nvim), arg))
    end
    return result, map(format_report, JET.get_reports(result))
end

path(file) = (p = string(file); isabspath(p) ? p : something(Base.find_source_file(p), p))

# User's code is in current project or sent to the REPL (like with slime)
function is_user_frame(frame)
    file = string(frame.file)
    return startswith(file, "REPL[") || startswith(path(file), joinpath(pwd(), ""))
end

function method_info(frame)
    m = frame.linfo.def
    m isa Method || return ("", 0, "")
    # Unnamed arguments (like `::Type{T}`) can't help to find the method
    argnames = join(filter(Base.isidentifier, Base.method_argnames(m)[2:end]), ',')
    return (string(m.name), m.line, argnames)
end

# Report as a line with fields: file, line, function name, line of function
# definition, argument names, message. Function info is used by Neovim to find
# functions defined at `REPL[n]` in the script they were sent from.
function format_report(report)
    fields = try
        if hasproperty(report, :vst)
            frames = report.vst
            i = something(findlast(is_user_frame, frames), lastindex(frames))
            frame = frames[i]
            message = sprint(JET.print_report_message, report)
            if i != lastindex(frames)
                message *= " (in $(first(method_info(frames[end]))))"
            end
            (path(frame.file), frame.line, method_info(frame)..., message)
        else
            # Top-level error, like failed `using` or syntax error
            (path(report.file), report.line, "", 0, "", sprint(JET.print_report, report))
        end
    catch err
        ("", 0, "", 0, "", "Could not show JET report: " * sprint(showerror, err))
    end
    return join(map(oneline, fields), '\t')
end

# Arguments are interpolated, so that time of accessing globals isn't measured
macro bench(ex)
    return :(bench($(QuoteNode(ex))))
end

function bench(ex)
    try
        load(:BenchmarkTools)
        Base.invokelatest(run_bench, ex)
    catch err
        show_error(err)
    end
    # Don't show the (possibly big) result of the call
    return nothing
end

function run_bench(ex)
    call = if Meta.isexpr(ex, :call)
        Expr(:call, ex.args[1], map(interpolate, ex.args[2:end])...)
    elseif Meta.isexpr(ex, :., 2) && Meta.isexpr(ex.args[2], :tuple)
        # Broadcasted call like `f.(x)`
        Expr(:., ex.args[1], Expr(:tuple, map(interpolate, ex.args[2].args)...))
    else
        ex
    end
    btime = GlobalRef(BenchmarkTools, Symbol("@btime"))
    Core.eval(Main, Expr(:macrocall, btime, LineNumberNode(0, :nvim), call))
    return
end

function interpolate(arg)
    Meta.isexpr(arg, :...) && return arg
    Meta.isexpr(arg, :kw) && return Expr(:kw, arg.args[1], interpolate(arg.args[2]))
    if Meta.isexpr(arg, :parameters)
        # Keyword arguments after `;`, including `f(; x)` shorthand
        kws = map(a -> a isa Symbol ? Expr(:kw, a, Expr(:$, a)) : interpolate(a), arg.args)
        return Expr(:parameters, kws...)
    end
    return Expr(:$, arg)
end

end
