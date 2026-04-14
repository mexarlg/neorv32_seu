# =============================================================================
# run_neorv32.tcl
# NEORV32 On-Chip Debugger Setup — Zybo Z7-20
#
# Usage (Vivado Tcl Console or batch mode):
#   source scripts/run_neorv32.tcl
#   vivado -mode batch -source scripts/run_neorv32.tcl
#
# Expected directory layout (relative to this script's location):
#   rtl/core/               <- NEORV32 upstream core files (*.vhd)
#   rtl/top/                <- Your top-level wrapper (*.vhd)
#   rtl/seu/                <- SEU mitigation modules (*.vhd) — can be empty
#   constraints/            <- XDC file generated alongside this script
#   scripts/                <- This file lives here
# =============================================================================

# -----------------------------------------------------------------------------
# 0. Resolve paths relative to THIS script's location so the project can be
#    moved or cloned anywhere without breaking.
# -----------------------------------------------------------------------------
set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize "$script_dir/../build"]
set rtl_dir     [file normalize "$script_dir/../rtl"]
set con_dir     [file normalize "$script_dir/../constraints"]

# -----------------------------------------------------------------------------
# 1. Project parameters — edit these if needed
# -----------------------------------------------------------------------------
set project_name  "neorv32_zybo_z7"
set fpga_part     "xc7z020clg400-1"    ;# Zybo Z7-20 exact part number

# -----------------------------------------------------------------------------
# 2. Create the Vivado project
# -----------------------------------------------------------------------------
puts "INFO: Creating project '$project_name' in '$project_dir'"

create_project $project_name "$project_dir/$project_name" \
    -part $fpga_part \
    -force

set_property target_language  VHDL [current_project]
set_property simulator_language VHDL [current_project]
set_property INCREMENTAL false [get_filesets sim_1]

# -----------------------------------------------------------------------------
# 3. Add NEORV32 core source files via the official file list
#    file_list_soc.f is maintained by the NEORV32 project and contains
#    exactly the files needed — no more, no less.
# -----------------------------------------------------------------------------
set neorv32_home [file normalize "$script_dir/.."]

set file_list_raw  [read [open "$neorv32_home/rtl/file_list_soc.f" r]]
set core_files     [string map \
    [list "NEORV32_RTL_PATH_PLACEHOLDER" "$neorv32_home/rtl"] \
    $file_list_raw]

puts "INFO: NEORV32 core files:"
puts $core_files

add_files $core_files
set_property library neorv32 [get_files $core_files]

# -----------------------------------------------------------------------------
# 4. Add your top-level / system-integration source files
# -----------------------------------------------------------------------------
set top_files [glob -nocomplain "$rtl_dir/top/neorv32_seu_debugger_top.vhd"]

if {[llength $top_files] == 0} {
    puts "WARNING: No .vhd files found in $rtl_dir/top/ — \
          add your top-level wrapper there before running synthesis."
} else {
    puts "INFO: Adding [llength $top_files] files from rtl/top/"
    add_files -norecurse $top_files
}
update_compile_order -fileset sources_1

# -----------------------------------------------------------------------------
# 5. Add SEU mitigation source files (directory may be empty initially)
# -----------------------------------------------------------------------------
set mit_files [glob -nocomplain "$rtl_dir/seu/*.vhd"]
# Remove a specific file (e.g., exclude "exclude_me.vhd")
set mit_files [lsearch -all -inline -not -exact $mit_files "$rtl_dir/seu/project_name.vhd"]
set mit_files [lsearch -all -inline -not -exact $mit_files "$rtl_dir/seu/project_name_pkg.vhd"]

if {[llength $mit_files] > 0} {
    puts "INFO: Adding [llength $mit_files] mitigation module(s)"
    add_files -norecurse $mit_files
} else {
    puts "INFO: rtl/seu/ is empty — no mitigation files added yet."
}

# -----------------------------------------------------------------------------
# 6. Set VHDL-2008 on every source file
#    NEORV32 REQUIRES VHDL-2008. Forgetting this is the #1 cause of
#    cryptic synthesis errors with NEORV32 in Vivado.
# -----------------------------------------------------------------------------
puts "INFO: Setting VHDL-2008 on all design source files"
set all_vhd [get_files -filter {FILE_TYPE == VHDL}]
set_property file_type {VHDL 2008} $all_vhd

# -----------------------------------------------------------------------------
# 7. Set top-level module
#    Change "neorv32_seu_debugger_top" to match the entity name in your
#    system_integration wrapper VHDL file.
# -----------------------------------------------------------------------------
set top_entity "neorv32_seu_debugger_top"
set_property top $top_entity [current_fileset]
puts "INFO: Top module set to '$top_entity'"

# -----------------------------------------------------------------------------
# 8. Add XDC constraints file
# -----------------------------------------------------------------------------
set xdc_file "$con_dir/zybo_z7_neorv32.xdc"

if {[file exists $xdc_file]} {
    add_files -fileset constrs_1 -norecurse $xdc_file
    puts "INFO: Constraints file added: $xdc_file"
} else {
    puts "WARNING: XDC file not found at $xdc_file"
    puts "         Create constraints/zybo_z7_neorv32.xdc before running \
implementation."
}

# -----------------------------------------------------------------------------
# 9. Synthesis strategy — prefer speed for baseline characterisation
# -----------------------------------------------------------------------------
set_property strategy               "Vivado Synthesis Defaults" \
    [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY rebuilt \
    [get_runs synth_1]

# Keep hierarchy visible — important for per-module resource analysis when
# comparing baseline vs. mitigated designs.
set_property STEPS.SYNTH_DESIGN.ARGS.KEEP_EQUIVALENT_REGISTERS true \
    [get_runs synth_1]

# -----------------------------------------------------------------------------
# 10. Implementation strategy
# -----------------------------------------------------------------------------
set_property strategy "Vivado Implementation Defaults" [get_runs impl_1]

# Generate bitstream automatically after a successful implementation run
set_property STEPS.WRITE_BITSTREAM.ARGS.BIN_FILE true [get_runs impl_1]

# -----------------------------------------------------------------------------
# 11. Done — print summary and remind the user of next steps
# -----------------------------------------------------------------------------
puts ""
puts "============================================================"
puts " Project created successfully!"
puts "============================================================"
puts " Location : $project_dir/$project_name"
puts " Part     : $fpga_part"
puts " Top      : $top_entity"
puts ""
puts " Next steps:"
puts "  1. Open the project:"
puts "       vivado $project_dir/$project_name/$project_name.xpr"
puts "  2. Verify VHDL-2008 is set on all files (Sources -> right-click -> Properties)"
puts "  3. Run Synthesis and check the utilisation report for your baseline"
puts "  4. Run Implementation and Generate Bitstream"
puts "  5. Program via Hardware Manager (the Zybo's Digilent USB-JTAG)"
puts "  6. Open a serial terminal at 19200 8N1 on the Pmod UART adapter"
puts "     (Pmod JB pins 1=TXD, 2=RXD — see constraints/zybo_z7_neorv32.xdc)"
puts "============================================================"