# ======================================================
# CRS_board_initialization.tcl
# ------------------------------------------------------
# Usage:
#   vivado -mode batch -source run_ibert_qc_multi.tcl \
#          -nojournal -nolog -log multi_run.log
# Expects in same folder:
#   • crs_board_programming.log
#	• crs_board_programming_list_01.txt
# ======================================================

# ————————————————————————————————————————————————————————————
# Open a log file for BER results
# ————————————————————————————————————————————————————————————
# Open (or create) the master BER log in append mode
set log_file "crs_board_programming.log"
set log_fh   [open $log_file a]

# Write a title and timestamp
puts $log_fh "CRS Board Initialization Log"
puts $log_fh "Date: [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
puts $log_fh "Serial,Model Board,Revision,Firmware version, Note"
# ————————————————————————————————————————————————————————————

# --- 1) User parameters (make sure these appear before you ever use $cfg_file or $max_boards)
# ————————————————————————————————
set cfg_file "crs_board_programming_list_01.txt"
#set serial_file   "serial_numbers_qsfp.txt"    
set max_boards 1
# ----------------------------------------------------------------------------- #

# --- 2) Locate & launch hw_server.bat by searching up from vivado.exe ---
set vivado_exe [file normalize [info nameofexecutable]]
set dir         [file dirname $vivado_exe]
set triedPaths  {}
set hw_server_bat ""

while {1} {
    set candidate [file join $dir bin hw_server.bat]
    lappend triedPaths $candidate
    if {[file exists $candidate]} {
        set hw_server_bat $candidate
        break
    }
    set parent [file dirname $dir]
    if {$parent eq $dir} break
    set dir $parent
}

puts "\nDEBUG: vivado.exe = $vivado_exe"
puts "DEBUG: tried for hw_server.bat:"
foreach p $triedPaths { puts "  $p" }

# ----------------------------------------------------------------------------- #

# --- 3) Open & connect Hardware Manager -------------------------------------- #
open_hw_manager
after 500
connect_hw_server -url localhost:3121
after 500
# ----------------------------------------------------------------------------- #


# --- 4) Open target and refreshe device -------------------------------------- #
open_hw_target
set xczu [lindex [get_hw_devices xczu*] 0]
refresh_hw_device $xczu
open_hw_device $xczu
# ----------------------------------------------------------------------------- #

# --- 5) Program QSPI Flash
program_flash -f boot.mcs -flash_type qspi_single -offset 0 -fsbl fsbl.elf

puts "Flash programming complete."
# ----------------------------------------------------------------------------- #

# program_flash -f BOOT.bin -offset 0 -flash_type qspi-x8-dual_parallel -fsbl fsbl.elf -blank_check -verify -url tcp:localhost:<port>