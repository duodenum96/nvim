# Show plots in Neovim's figure pane.
#
# Loaded with `julia -L` by REPLs started from Neovim (see 'plugin/55_figures.lua'),
# which set `NVIM_FIG_DIR`. Anything that can be shown as PNG (Plots.jl, Makie,
# images, ...) is saved into that directory, which Neovim watches. Everything
# else is shown in the REPL as usual.
module NvimFig

import REPL

const dir = ENV["NVIM_FIG_DIR"]

struct FigDisplay <: AbstractDisplay
    repl::REPL.AbstractREPL
end

function Base.display(::FigDisplay, ::MIME"image/png", x)
    # Same object means new version of the same figure (like after `plot!()`)
    name = "nvimfig-$(string(objectid(x), base = 16))-$(time_ns()).png"
    # Write to temporary file first, so that Neovim never sees a partial file
    tmp = joinpath(dir, "." * name)
    open(io -> show(io, MIME"image/png"(), x), tmp, "w")
    mv(tmp, joinpath(dir, name))
    return nothing
end

function Base.display(d::FigDisplay, x)
    showable(MIME"image/png"(), x) && return display(d, MIME"image/png"(), x)
    return display(REPL.REPLDisplay(d.repl), x)
end

# Packages can put their own displays on top of the display stack
function raise()
    displays = Base.Multimedia.displays
    last(displays) isa FigDisplay && return
    i = findlast(d -> d isa FigDisplay, displays)
    i === nothing || pushdisplay(popat!(displays, i))
    return
end

atreplinit() do repl
    repl isa REPL.LineEditREPL || return
    # Used for values returned in the REPL instead of its own display
    repl.specialdisplay = FigDisplay(repl)
    # Used for explicit `display()` calls
    pushdisplay(FigDisplay(repl))
    push!(Base.package_callbacks, _ -> raise())
end

end
