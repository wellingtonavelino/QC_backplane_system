# ======================================================
# run_ibert_qc_multi.tcl
# ------------------------------------------------------
# Usage:
#   vivado -mode batch -source run_ibert_qc_multi.tcl \
#          -nojournal -nolog -log multi_run.log
# Expects in same folder:
#   • ibert_qc_ber.log
#	• ibert_05012025-2.txt   (serial,bitfile,threshold,link0,link1,...)
#   • example_ibert_ultrascale_gty_0.bit
# ======================================================

# ————————————————————————————————————————————————————————————
# Open a log file for BER results
# ————————————————————————————————————————————————————————————
# Open (or create) the master BER log in append mode
set log_file "ibert_qc_ber.log"
set log_fh   [open $log_file a]

# Write a title and timestamp
puts $log_fh "IBERT QC BER Log"
puts $log_fh "Date: [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
#puts $log_fh ""
#puts $log_fh "Serial,Link,BER"
puts $log_fh "Serial,from Board,to Board,BER, ERRORS"
# ————————————————————————————————————————————————————————————

# ————————————————————————————————
# 0) User parameters (make sure these appear 
# before you ever use $cfg_file or $max_boards)
set cfg_file   "ibert_05012025-3.txt"

# 0) serial numbers (make sure these appear 
# before you ever use $cfg_file or $max_boards)
set serial_file   "serial_numbers.txt"
set max_boards 4
# ————————————————————————————————


# --- 0) Locate & launch hw_server.bat by searching up from vivado.exe ---
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

if {$hw_server_bat eq ""} {
    set fallback "D:/Xilinx/Vivado_Lab/2023.1.1/bin/hw_server.bat"
	# in linux: set fallback "home/Xilinx/Vivado/2024.2/lab/bin/hw_server"
    puts "WARN: auto-detect failed, falling back to $fallback"
    if {[file exists $fallback]} {
        set hw_server_bat $fallback
    } else {
        puts "ERROR: hw_server.bat not found"; exit 1
    }
}
set hw_server_log [file join [file dirname $hw_server_bat] hw_server_debug.log]
puts "INFO: launching hw_server → $hw_server_bat"
if {[catch {
    exec cmd.exe /C start "" "\"$hw_server_bat\"" -d "$hw_server_log"
} err]} {
    puts "WARN: cannot launch hw_server: $err"
} else {
    puts "OK: hw_server launched (log→$hw_server_log)"
}
after 2000

# --- 2) Open & connect Hardware Manager ---
open_hw_manager
after 1000
connect_hw_server -url localhost:3121
after 1000

# --- 3) Read config and collect up to max_boards entries ---
set boards {}
set fp [open $cfg_file r]
foreach line [split [read $fp] "\n"] {
    set ltrim [string trim $line]
    if {$ltrim eq "" || [string index $ltrim 0] == "#"} continue
    lappend boards $ltrim
    if {[llength $boards] >= $max_boards} { break }
}
close $fp
if {[llength $boards] == 0} {
    puts "ERROR: no valid board entries in $cfg_file"; exit 1
}

# --- Read serial_numbers and place them in a variable ---
set serial_ns {}
set fs [open $serial_file r]
foreach line [split [read $fs] "\n"] {
    set ltrim [string trim $line]
    if {$ltrim eq "" || [string index $ltrim 0] == "#"} continue
    lappend serial_ns $ltrim
    if {[llength $serial_ns] >= $max_boards} { break }
}
close $fs
if {[llength $serial_ns] == 0} {
    puts "ERROR: no valid serial number entries in $serial_file"; exit 1
}

# global list of all tests: each element = [boardIdx linkObj threshold linkLabel]
set all_tests {}

# --- 4) Phase 1: Program & setup links for each board ---
set idx 0
foreach entry $boards {
    
    #puts "\n=== Board #$idx: $entry ==="
    set parts [split $entry ","]
    #set serial    [lindex $parts 1]
	set serial [lindex $serial_ns $idx]
    set bitfile   [lindex $parts 2]
    set threshold [expr {[lindex $parts 3]}]
	set paths     [lrange $parts 4 6]
    set links     [lrange $parts 7 end]
	
	puts "\n=== Board #$idx: $serial ==="

	#puts -nonewline "Enter serial number for Board #$idx: "
	#flush stdout
	#gets stdin serial
	
	incr idx

    # 4.1) Find the target by serial
    set tgt ""
    foreach t [get_hw_targets] {
        if {[catch { set uid [get_property UID $t] }]} continue
        if {[lindex [split $uid "/"] end] eq $serial} {
            set tgt $t; break
        }
    }
    if {$tgt eq ""} {
        puts "ERROR: no hw_target with serial=$serial"; continue
    }
    puts "OK: target = [get_property NAME $tgt] (UID=$serial)"

    #current_hw_target $tgt
    #open_hw_target

    # just switch—do NOT re-open
	# Before switching, close any open target
    catch { close_hw_target }
    puts "INFO: switching to target [get_property NAME $tgt]..."
	after 1000
	# Test if all connectior were closed
	set retries 0
		while {[llength [get_hw_targets -filter {IS_OPEN==true}]] != 0 && $retries < 5} {
			after 1000
			incr retries
		}
    current_hw_target $tgt


     # 4.2) Open this target (now that it's current)
    puts "INFO: open_hw_target for $tgt"
    if {[catch { open_hw_target } err]} {
        puts "ERROR at open_hw_target: $err"; continue
    }

    # Now you can safely do:
    set fpga_dev ""
    foreach d [get_hw_devices -of_objects $tgt] {
        if {[catch { set nm [string tolower [get_property NAME $d]] }]} continue
        if {[string match "*xczu47dr*" $nm]} { set fpga_dev $d; break }
    }
    if {$fpga_dev eq ""} {
        puts "ERROR: no XCZU47DR device found"; continue
    }
    puts "OK: FPGA device = [get_property NAME $fpga_dev]"

    if {![file exists $bitfile]} {
        puts "ERROR: bitfile '$bitfile' missing"; continue
    }
    set_property PROGRAM.FILE $bitfile $fpga_dev
	after 500

	puts -nonewline "Programming FPGA... "
    program_hw_devices $fpga_dev
	puts "Done."

    # 4.3) Refresh so the IBERT cores become visible
    refresh_hw_device -force_poll $fpga_dev
	after 500

    # 4.4) Grab raw TX/RX endpoints
    set txs [get_hw_sio_txs -of_objects $fpga_dev]
	after 500
    set rxs [get_hw_sio_rxs -of_objects $fpga_dev]
	after 500

    # 4.5) For each TX/RX link, create & configure PRBS31
    for {set j 0} {$j < [llength $links]} {incr j 2} {
        set txName [lindex $links $j]
        set rxName [lindex $links [expr {$j+1}]]

        # find endpoint objects by suffix match
        set txObj ""
        foreach t $txs {
            if {[string match "*$txName" [get_property NAME $t]]} {
                set txObj $t; break
            }
        }
        set rxObj ""
        foreach r $rxs {
            if {[string match "*$rxName" [get_property NAME $r]]} {
                set rxObj $r; break
            }
        }
        if {$txObj eq "" || $rxObj eq ""} {
            puts "WARN: missing endpoints for $txName/$rxName"; continue
        }

        # create & commit the link
        set linkObj [create_hw_sio_link $txObj $rxObj]
		after 500
        commit_hw_sio $linkObj

        # enable PRBS 31-bit
        #set_property TX_PATTERN {PRBS 31-bit} $linkObj
        #set_property RX_PATTERN {PRBS 31-bit} $linkObj
        #commit_hw_sio -non_blocking $linkObj

        # record for Phase 2: [target device link threshold label]
        set label "$txName->$rxName"
        lappend all_tests [list $tgt $fpga_dev $linkObj $threshold $label]
        puts "Scheduled test: Board#$idx $label"
    }
	
	# 4.x) Done with this board: close it so next one can open
    puts "INFO: closing target [get_property NAME $tgt]"
    catch { close_hw_target }
		set retries 0
		while {[llength [get_hw_targets -filter {IS_OPEN==true}]] != 0 && $retries < 5} {
			after 1000
			incr retries
		}
	#after 500
}