# Show plots in Neovim's figure pane.
#
# Used as R profile (`R_PROFILE_USER`) by REPLs started from Neovim (see
# 'plugin/55_figures.lua'), which set `NVIM_FIG_DIR`. Plots are drawn on a device
# without output. After every command, the current plot is saved as PNG file
# into that directory (if it changed), which Neovim watches. Like in MATLAB,
# `dev.off()` is not needed and figures are resized to fill the pane.
#
# Default packages are not attached yet when profile is run, so functions from
# them are used with `::`.

# This profile is used instead of the usual one, so run that first
local({
  profile <- if (file.exists(".Rprofile")) ".Rprofile" else path.expand("~/.Rprofile")
  if (file.exists(profile)) source(profile)
})

if (interactive()) local({
  dir <- Sys.getenv("NVIM_FIG_DIR")
  pane_file <- file.path(dir, "pane")

  # Pane size in pixels and dpi to render with. Written by Neovim.
  read_pane <- function() {
    pane <- if (file.exists(pane_file)) scan(pane_file, quiet = TRUE)
    if (length(pane) == 3) pane else c(672, 672, 96)
  }

  # Device without output, which only records plots
  options(device = function(...) {
    pane <- read_pane()
    grDevices::pdf(NULL, width = pane[1] / pane[3], height = pane[2] / pane[3])
    grDevices::dev.control("enable")
  })

  # Last saved plot and pane size of each device
  last <- list()

  save_plot <- function() {
    dev <- grDevices::dev.cur()
    if (dev == 1) return()

    # Plot is empty also for devices which don't record plots, like `png()` to
    # save a plot
    plot <- grDevices::recordPlot()
    pane <- read_pane()
    key <- as.character(dev)
    if (is.null(plot[[1]]) || identical(last[[key]], list(plot, pane))) return()
    last[[key]] <<- list(plot, pane)

    # Same device means new version of the same figure
    name <- sprintf("nvimfig-r%d-%.0f.png", dev, as.numeric(Sys.time()) * 1e6)
    # Write to temporary file first, so that Neovim never sees a partial file
    tmp <- file.path(dir, paste0(".", name))
    grDevices::png(tmp, width = pane[1], height = pane[2], res = pane[3])
    tryCatch(grDevices::replayPlot(plot), finally = {
      grDevices::dev.off()
      grDevices::dev.set(dev)
    })
    file.rename(tmp, file.path(dir, name))
  }

  addTaskCallback(function(...) {
    tryCatch(save_plot(), error = function(e) message("Figure pane: ", conditionMessage(e)))
    TRUE
  }, name = "nvim_fig")
})
