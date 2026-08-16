
# =============================================================================
# DESIGN PARAMETERS
# Top-level module name, RTL sources, and clock period.
# clock_period is read from the "clock" file next to this script.
# script_dir is injected by the Makefile via -x "set script_dir .." so that
# all paths resolve correctly when DC runs from synthesis/build/ as its CWD.
# If running dc_shell manually from synthesis/, omit -x and the default "."
# fallback keeps every path working unchanged.
# =============================================================================
if {![info exists script_dir]} { set script_dir "." }

set design_name accelerator

set SOURCES [list \
    $script_dir/../rtl/newton_lut.sv \
    $script_dir/../rtl/rsqrt_newton_step.sv \
    $script_dir/../rtl/inv_pwr_3d2_unit.sv \
    $script_dir/../rtl/accel_unit.sv \
    $script_dir/../rtl/accel_module.sv \
    $script_dir/../rtl/pos_module.sv \
    $script_dir/../rtl/vel_module.sv \
    $script_dir/../rtl/integrator.sv \
    $script_dir/../rtl/accelerator.sv \
]

# Read clock period (ns) from the "clock" file next to this script
set fp [open "$script_dir/clock" r]
set clock_period [string trim [read $fp]]
close $fp

set clock_name clk


# =============================================================================
# LIBRARY SETUP
# target_library: standard cell library DC maps logic into (gates, FFs, etc.).
# link_library:   libraries searched when resolving cell references; "*" means
#                 also search the design currently in memory.
# lec25dscc25_TT = TSMC 250nm, typical process corner, 25C, nominal voltage.
# =============================================================================
# A technology is four library-specific things: where the .db lives, its
# library name, a wire load model, and a cell to model input drive with. Cell
# names are NOT portable between libraries (dffacs1 exists only in the 250nm
# lib), so each preset carries its own. Select with:
#     dc_shell -x "set script_dir ..; set tech n16" -f ../synth.tcl
# or  make synth TECH=n16
if {![info exists tech]} { set tech lec25 }

switch -- $tech {
    lec25 {
        # TSMC 250nm educational library, typical corner, 25C, nominal voltage.
        set lib_dir      "/usr/caen/misc/class/eecs470/lib/synopsys/"
        set lib_file     "lec25dscc25_TT"
        set lib_name     "lec25dscc25_TT"
        set wire_load    "tsmcwire"
        set drive_cell   "dffacs1"
        set drive_pin    "Q"
    }
    n16 {
        # TSMC 16nm ADFP standard cells, typical 0.8V 25C. NOTE: this is a
        # foundry PDK under the terms in the kit's
        # N16ADFP_TERMS_AND_CONDITIONS pdf -- check that your use is covered
        # before publishing area or timing derived from it.
        set lib_dir      "/usr/caen/misc/class/tsmc16adfp/tsmc16adfp/Collaterals/IP/stdcell/N16ADFP_StdCell/NLDM/"
        set lib_file     "N16ADFP_StdCelltt0p8v25c"
        set lib_name     "N16ADFP_StdCelltt0p8v25c"
        set wire_load    "ZeroWireload"
        set drive_cell   "BUFFD1BWP16P90"
        set drive_pin    "Z"
    }
    freepdk45 {
        # NCSU FreePDK45 1.4 / OSU gscl45nm standard cells (Apache-2.0, so
        # results are publishable without qualification). Nominal 1.1V, 27C.
        # The kit ships gscl45nm.db already compiled -- no lc_shell step.
        # TECH_HOME defaults to ~/tech and can be overridden.
        #
        # Only 31 cells, and NO wire load models in the .lib (hence the empty
        # wire_load below): expect worse QoR and optimistic pre-layout timing
        # relative to the 250nm library, which is the price of an open kit.
        if {[info exists env(TECH_HOME)]} {
            set tech_home $env(TECH_HOME)
        } else {
            set tech_home "$env(HOME)/tech"
        }
        set lib_dir      "$tech_home/FreePDK45/osu_soc/lib/files/"
        set lib_file     "gscl45nm"
        set lib_name     "gscl45nm"
        set wire_load    ""
        set drive_cell   "BUFX2"
        set drive_pin    "Y"
    }
    nangate45 {
        # FreePDK45 + NanGate Open Cell Library, from the tech/freepdk-45nm
        # submodule (the mflowgen ADK). PREFER THIS over tech=freepdk45: the
        # OSU gscl45nm kit's flip-flop setup tables carry 6.2ns/5.125ns
        # outliers among 0.05-0.3ns neighbours, which DC extrapolates into a
        # ~110ns setup requirement and a meaningless timing report. NanGate's
        # characterization is clean, and this kit also ships wire load models
        # and bc/wc corners. Nominal 1.1V, 25C.
        set lib_dir      "$script_dir/../tech/freepdk-45nm/"
        set lib_file     "stdcells"
        set lib_name     "NangateOpenCellLibrary"
        set wire_load    "5K_hvratio_1_1"
        set drive_cell   "BUF_X1"
        set drive_pin    "Z"
    }
    default {
        error "unknown tech '$tech' -- expected one of: lec25 n16 freepdk45 nangate45"
    }
}

puts "synth.tcl: tech=$tech  library=$lib_name"
puts "synth.tcl: lib_dir=$lib_dir"

# lib_file is the .db FILENAME, lib_name is the library name INSIDE it. They
# match for most kits, but the mflowgen ADK ships stdcells.db containing a
# library called NangateOpenCellLibrary -- target_library wants the former,
# set_wire_load_model -lib wants the latter.
set primary_corner $lib_name
set target_library [list ${lib_file}.db]
set link_library "* $target_library"


# =============================================================================
# SEARCH PATH
# Directories DC checks when resolving `include files and .db library names.
# "$script_dir/../rtl/" must be present so `include "defs.svh" resolves.
# =============================================================================
set search_path [list "./" $script_dir $script_dir/../rtl/ $lib_dir]


# =============================================================================
# ELABORATION
# DC is invoked from synthesis/build/ so command.log, filenames.log, cksum_dir,
# and the PRESTO intermediates (.pvl, .syn, .mr) all land there directly.
# hdlin_precompile_dir ".": store PRESTO intermediates in the CWD (build/).
# set_svf:                  store the formal verification file in the CWD.
# hdlin_ff_always_sync_set_reset: treat resets in always_ff as synchronous,
#   matching the RTL's "if (rst | restart)" style.
# analyze:      parse and syntax-check the SystemVerilog source files.
# elaborate:    build the design hierarchy from the parsed modules.
# current_design: set the elaborated design as the active target.
# =============================================================================
set_app_var hdlin_precompile_dir "."
set_svf "default.svf"
set hdlin_ff_always_sync_set_reset "true"

# rtl_defines lets the build override defs.svh's guarded macros (N, NUMPIPES,
# NUMLANES) without editing the file, e.g.
#     dc_shell -x "set script_dir ..; set rtl_defines {N=20 NUMPIPES=10}" -f ../synth.tcl
# Without this, dc_shell only ever sees whatever is literally in defs.svh, so
# area/timing could silently describe a different design than the VCS benchmark
# (which gets the same values via +define+).
if {![info exists rtl_defines]} { set rtl_defines {} }
if {[llength $rtl_defines] > 0} {
    puts "synth.tcl: overriding RTL macros with: $rtl_defines"
    analyze -f sverilog -define $rtl_defines $SOURCES
} else {
    analyze -f sverilog $SOURCES
}
elaborate ${design_name}
current_design ${design_name}


# =============================================================================
# WIRE LOAD MODEL
# Estimates interconnect resistance/capacitance before place-and-route.
# compile_top_all_paths: report timing through all paths, not just worst-case.
# auto_wire_load_selection false: use the model we specify, not DC's auto pick.
# set_wire_load_mode top: apply the top-level model to all sub-blocks.
# set_fix_multiple_port_nets: insert buffers for constants on multi-driven nets.
# =============================================================================
set_app_var compile_top_all_paths "false"
set_app_var auto_wire_load_selection "false"

# Not every library ships wire load models (modern PDKs expect real parasitics
# from place-and-route instead), so skip the call when the preset leaves it empty.
if {$wire_load ne ""} {
    set_wire_load_model -name $wire_load -lib $lib_name ${design_name}
    set_wire_load_mode top
} else {
    puts "synth.tcl: no wire load model for tech=$tech (pre-layout estimates will be optimistic)"
}
set_fix_multiple_port_nets -outputs -buffer_constants


# =============================================================================
# INPUT DRIVE STRENGTH
# Tells DC how strong the signals driving the inputs are so it can accurately
# model input transition times. "dffacs1 Q" = single-strength DFF output.
# =============================================================================
set_driving_cell -lib_cell $drive_cell -pin $drive_pin [all_inputs]


# =============================================================================
# CLOCK CONSTRAINT
# Creates a clock object on the top-level clk port with the period from file.
# set_clock_uncertainty adds guardband for skew and jitter (ns).
# set_fix_hold instructs DC to insert buffers to meet hold-time requirements.
# =============================================================================
create_clock -period $clock_period -name $clock_name [find port $clock_name]
set_clock_uncertainty 0.1 $clock_name
set_fix_hold $clock_name


# =============================================================================
# COMPILE
# Runs logic synthesis and technology mapping.
# -map_effort high:  spend extra time finding better gate mappings (slower but
#                    produces better timing and area results).
# -area_effort none: skip the post-compile area-reduction pass; change to
#                    "high" if area matters once timing has closed.
# =============================================================================
compile -map_effort high -area_effort high

# =============================================================================
# OUTPUTS
# Netlist and SDC go to synthesis/build/ (the CWD).
# Reports go to synthesis/report/ so they are easy to find separately from
# the intermediate build artifacts.
# =============================================================================
write -format verilog -hierarchy -output "${design_name}.synth.v"
write_sdc "${design_name}.sdc"

file mkdir ../report

# timing: design summary + critical paths + constraint violations
set timing_rpt "../report/${design_name}_timing.rpt"
redirect $timing_rpt         { report_design      -nosplit }
redirect -append $timing_rpt { report_timing      -max_paths 2 -input_pins -nets -transition_time -nosplit }
redirect -append $timing_rpt { report_constraints -all_violators -verbose -nosplit -significant_digits 4 }

# area: cell/resource utilization
set area_rpt "../report/${design_name}_area.rpt"
redirect $area_rpt           { report_resources -hier }
redirect -append $area_rpt   { report_area      -hierarchy }

# power
set power_rpt "../report/${design_name}_power.rpt"
redirect $power_rpt          { report_power }

exit
