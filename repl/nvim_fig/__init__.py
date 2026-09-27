"""Matplotlib backend that shows figures in Neovim's figure pane.

Used by REPLs started from Neovim (see 'plugin/55_figures.lua'), which set
`MPLBACKEND=module://nvim_fig` and `NVIM_FIG_DIR`. Figures are saved as PNG
files into that directory, which Neovim watches.

Like in MATLAB, `plt.show()` is not needed: the current figure is saved every
time Python gets back to the prompt after it has changed. Figures of default
size are resized to fill the pane.

This package also has dark themes matching Neovim color schemes. The one for
the current color scheme is used when the REPL starts. Switch with:
    plt.style.use('nvim_fig.catppuccin-mocha')
    plt.style.use('nvim_fig.ayu-dark')
    plt.style.use('nvim_fig.miniwinter')
    plt.style.use('default')  # Light theme, like for figures for a paper
    mpl.rc_file_defaults()    # Back to the theme from REPL start
Only figures created after switching are affected.
"""

import ctypes
import os
import sys
import time
import traceback

import matplotlib as mpl
from matplotlib._pylab_helpers import Gcf
from matplotlib.backend_bases import FigureManagerBase
from matplotlib.backends.backend_agg import FigureCanvasAgg

_dir = os.environ["NVIM_FIG_DIR"]

# Pane size in pixels and dpi to render with. Written by Neovim.
_pane_file = os.path.join(_dir, "pane")
_pane_mtime = None


def _read_pane():
    try:
        with open(_pane_file) as f:
            width, height, dpi = map(float, f.read().split())
    except (OSError, ValueError):
        return None
    return width, height, dpi


def _save(manager):
    fig = manager.canvas.figure
    dpi = fig.dpi
    pane = _read_pane()
    if pane is not None:
        width, height, dpi = pane
        # Fill the pane, unless size was set explicitly
        if tuple(fig.get_size_inches()) == manager.auto_size:
            fig.set_size_inches(width / dpi, height / dpi)
            manager.auto_size = tuple(fig.get_size_inches())

    # Same figure number means new version of the same figure
    name = f"nvimfig-{manager.num}-{time.time_ns()}.png"
    # Write to temporary file first, so that Neovim never sees a partial file
    tmp = os.path.join(_dir, "." + name)
    try:
        fig.savefig(tmp, format="png", dpi=dpi)
        os.replace(tmp, os.path.join(_dir, name))
    finally:
        # Saving with different dpi marks figure as changed. Also don't retry
        # on every prompt tick if drawing failed.
        fig.stale = False


def _on_idle():
    global _pane_mtime
    try:
        try:
            mtime = os.stat(_pane_file).st_mtime_ns
        except OSError:
            mtime = None
        resized, _pane_mtime = mtime != _pane_mtime, mtime

        manager = Gcf.get_active()
        if manager is not None and (manager.canvas.figure.stale or resized):
            _save(manager)
    except Exception:
        traceback.print_exc()
    return 0


class FigureManager(FigureManagerBase):
    def __init__(self, canvas, num):
        super().__init__(canvas, num)
        # Size which can be changed to fill the pane. See `_save()`.
        self.auto_size = tuple(mpl.rcParams["figure.figsize"])

    def show(self):
        _save(self)


class FigureCanvas(FigureCanvasAgg):
    manager_class = FigureManager

    def draw_idle(self, *args, **kwargs):
        # Figures are drawn once Python gets back to the prompt. See `_on_idle()`.
        pass


# Python calls `PyOS_InputHook` every 0.1 s while waiting for input at the
# prompt (GUI toolkits use it to run their event loops)
_input_hook = ctypes.CFUNCTYPE(ctypes.c_int)(_on_idle)
ctypes.c_void_p.in_dll(ctypes.pythonapi, "PyOS_InputHook").value = ctypes.cast(
    _input_hook, ctypes.c_void_p
).value

# IPython doesn't call `PyOS_InputHook`, but has an event for this
_ipython = getattr(sys.modules.get("IPython"), "get_ipython", lambda: None)()
if _ipython is not None:
    _ipython.events.register("post_execute", _on_idle)
