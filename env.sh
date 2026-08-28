# Environment for the mflowgen ASIC flow. Source it, don't execute it:
#     source env.sh
#
# mflowgen itself is installed editable into .venv (uv pip install -e
# tech/mflowgen), so the `mflowgen` command comes from .venv/bin and the
# upstream quick-start instructions work verbatim. This file only supplies
# what pip cannot: where the ADK lives, and the EDA tool modules.

# resolve repo root whether sourced from bash or zsh, independent of cwd
if [ -n "${BASH_SOURCE[0]:-}" ]; then
    _MFG_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
else
    _MFG_ROOT="$( cd "$( dirname "${(%):-%x}" )" && pwd )"
fi

# TOP matches the variable the upstream docs use for the mflowgen repo root,
# so their command lines can be copied as-is.
export TOP="$_MFG_ROOT/tech/mflowgen"
export MFLOWGEN_HOME="$TOP"

# Repo root, so design nodes (e.g. designs/Accelerator/rtl/build_design.sh) can
# find the real RTL sources under rtl/ without hardcoding a path relative to
# wherever the mflowgen build sandbox happens to live (repo checkout, /tmp
# scratch dir, or the tech/mflowgen/build symlink).
export NBODY_ROOT="$_MFG_ROOT"

# MFLOWGEN_PATH is where flows look for ADKs. tech/freepdk-45nm is the
# FreePDK45 + NanGate kit (submodule), whose NanGate cells are properly
# characterized -- unlike the OSU gscl45nm kit in ~/tech, whose flip-flop
# setup tables carry 6.2ns outliers among 0.05ns neighbours and yield a
# ~110ns setup requirement and meaningless timing.
export MFLOWGEN_PATH="$_MFG_ROOT/tech/freepdk-45nm"

# uv's cache defaults to ~/.cache, which sits on the engin-labs CIFS mount.
# CIFS cannot do the atomic renames uv's build isolation needs, so installs
# fail there with "[Errno 11] Resource temporarily unavailable". Point it at
# local disk. Only matters when installing, but harmless to always set.
export UV_CACHE_DIR="${UV_CACHE_DIR:-/tmp/$USER-uv-cache}"

# The EDA tools the flow drives:
#   synopsys-synth  DC (synthesis)      innovus  floorplan/place/CTS/route
#   primetime       timing signoff      calibre  DRC/LVS
# Deliberately NOT module-loading synopsys-synth. CAEN's /usr/caen/bin/dc_shell
# is a wrapper that calls `modexec`, which sets up more than a bare `module
# load` does. With the module preloaded, even plain dc_shell dies with
#     site .snps_container file not found; installation needs to be configured
# whereas the unwrapped-PATH version starts fine. This is exactly why `make
# synth` has always worked: it runs without this file sourced. Leave the
# Synopsys tools to their wrappers.
#
# Cadence is the opposite case: there is NO /usr/caen/bin/innovus wrapper, so
# the module is the only way to get it on PATH. Loading it does not disturb the
# Synopsys tools because those go through their own modexec wrapper (see the
# dc_shell-xg-t shim), which sets up its environment independently.
# Use the DDI bundle, NOT the standalone innovus/* modules. DDI 25.10 is a 2025
# build that runs on this RHEL 9.8 host; every standalone innovus module here is
# older and fails -- 21.37 exits 1 because checkSysConf rejects RHEL 9.8, 18.10
# dies on missing CXXABI_1.3.8 in libstdc++, and the rest are ACL-hidden on this
# machine. DDI ships both innovus and genus.
if command -v module >/dev/null 2>&1; then
    module load ddi/25.10.000 2>/dev/null

    # Formality (fm_shell) for the verif_post_synth equivalence-check node.
    # Pinned to 2019.12-SP4, not the newest available:
    #   - verif_post_synth's own scripts/setup-session.tcl hardcodes
    #     `set_app_var verification_clock_gate_hold_mode any`, and "any" was
    #     removed as a valid value starting in 2021.06-SP1 (only NONE, LOW,
    #     HIGH, COLLAPSE_ALL_CG_CELLS accepted from then on) -- confirmed by
    #     testing the app var directly against 2019.12-SP4/2021.06-SP1/2022.03-SP3.
    #   - formality/2025.06-SP1 separately fails to even launch:
    #     libkrb5.so.3: undefined symbol krb5int_c_deprecated_enctype
    #     against RHEL 9's Kerberos.
    module load formality/2019.12-SP4 2>/dev/null
fi

# tools/ holds shims for tool names mflowgen expects but that are broken or
# absent here -- currently dc_shell-xg-t. This MUST come after the module loads:
# `module load synopsys-synth` prepends the Synopsys bin directory, which does
# contain a dc_shell-xg-t, but one that dies with "site .snps_container file not
# found". Prepending tools/ afterwards is what makes the shim actually win.
export PATH="$_MFG_ROOT/tools:$PATH"

echo "mflowgen env ready"
echo "  TOP           = $TOP"
echo "  MFLOWGEN_PATH = $MFLOWGEN_PATH  (ADK)"
echo "  mflowgen      = $(command -v mflowgen 2>/dev/null || echo '(activate .venv first)')"

unset _MFG_ROOT
