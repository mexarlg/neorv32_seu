# =============================================================================
# build_neorv32_bitstream.tcl
# Runs synthesis, implementation and bitstream generation for the NEORV32
# project on the Zybo Z7-20.
#
# USAGE (Vivado TCL console):
#   source scripts/build_neorv32_bitstream.tcl
#
# USAGE (batch mode, no GUI):
#   vivado -mode batch -source scripts/build_neorv32_bitstream.tcl
#
# PREREQUISITES:
#   - Project must already exist in build/ (run run_neorv32.tcl first)
#   - If project does not exist yet, run run_neorv32.tcl first
# =============================================================================

# -----------------------------------------------------------------------------
# 0. Paths
# -----------------------------------------------------------------------------
set script_dir   [file dirname [file normalize [info script]]]
set project_dir  [file normalize "$script_dir/../build"]
set project_name "neorv32_zybo_z7"
set project_file "$project_dir/$project_name/$project_name.xpr"

# -----------------------------------------------------------------------------
# 1. Open project (or use current if already open in GUI)
# -----------------------------------------------------------------------------
if {[catch {current_project} err]} {
    if {![file exists $project_file]} {
        error "ERROR: Project not found at $project_file\
               \nRun scripts/run_neorv32.tcl first to create the project."
    }
    puts "INFO: Opening project $project_file"
    open_project $project_file
} else {
    puts "INFO: Using already open project: [current_project]"
}

# -----------------------------------------------------------------------------
# 2. Reset runs to force a clean rebuild
#    Comment these two lines out if you want incremental build instead
# -----------------------------------------------------------------------------
puts "INFO: Resetting runs for clean rebuild..."
reset_run synth_1
reset_run impl_1

# -----------------------------------------------------------------------------
# 3. Synthesis
# -----------------------------------------------------------------------------
puts "INFO: Launching synthesis (this takes 5-10 minutes)..."
launch_runs synth_1 -jobs 4
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "ERROR: Synthesis failed — open the project in Vivado and check the log"
}
puts "INFO: Synthesis complete"

# Print utilisation summary
open_run synth_1
set util [report_utilization -return_string -quiet]
puts "INFO: Resource utilisation after synthesis:"
foreach line [split $util "\n"] {
    if {[regexp {LUT|FF|BRAM|DSP|Slice} $line]} {
        puts "  $line"
    }
}

# -----------------------------------------------------------------------------
# 4. Implementation
# -----------------------------------------------------------------------------
puts "INFO: Launching implementation (this takes 5-15 minutes)..."
launch_runs impl_1 -jobs 4
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "ERROR: Implementation failed — open the project in Vivado and check the log"
}
puts "INFO: Implementation complete"

# Check timing — warn if timing is not met
open_run impl_1
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
if {$wns < 0} {
    puts "WARNING: Timing NOT met — WNS = $wns ns"
    puts "WARNING: The design may malfunction on hardware"
    puts "WARNING: Consider reducing CLOCK_FREQUENCY in your top wrapper"
} else {
    puts "INFO: Timing met — WNS = $wns ns"
}

# -----------------------------------------------------------------------------
# 5. Generate bitstream
# -----------------------------------------------------------------------------
puts "INFO: Generating bitstream..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

# Find the bitstream file
set bit_file [glob -nocomplain "$project_dir/$project_name/${project_name}.runs/impl_1/*.bit"]

if {[llength $bit_file] == 0} {
    error "ERROR: Bitstream file not found — check implementation logs"
}

# -----------------------------------------------------------------------------
# 6. Done
# -----------------------------------------------------------------------------
puts ""
puts "============================================================"
puts " Bitstream generated successfully!"
puts "============================================================"
puts " File : $bit_file"
puts " WNS  : $wns ns"
puts ""
puts " Next steps:"
puts "  1. Program the FPGA:"
puts "       Vivado → Open Hardware Manager → Program Device"
puts "       Or run: source scripts/program_fpga.tcl"
puts "  2. Upload a program:"
puts "       ./scripts/neorv32_run.sh hello_world"
puts "============================================================"
