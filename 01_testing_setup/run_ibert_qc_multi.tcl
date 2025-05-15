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
puts $log_fh ""
puts $log_fh "Serial,Link,BER"
# ————————————————————————————————————————————————————————————

# ————————————————————————————————
# 0) User parameters (make sure these appear 
# before you ever use $cfg_file or $max_boards)
set cfg_file   "ibert_05012025-2.txt"
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
connect_hw_server -url localhost:3121

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

# global list of all tests: each element = [boardIdx linkObj threshold linkLabel]
set all_tests {}

# --- 4) Phase 1: Program & setup links for each board ---
set idx 0
foreach entry $boards {
    incr idx
    puts "\n=== Board #$idx: $entry ==="
    set parts [split $entry ","]
    set serial    [lindex $parts 0]
    set bitfile   [lindex $parts 1]
    set threshold [expr {[lindex $parts 2]}]
    set links     [lrange $parts 3 end]

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
    program_hw_devices $fpga_dev

    # 4.3) Refresh so the IBERT cores become visible
    refresh_hw_device -force_poll $fpga_dev

    # 4.4) Grab raw TX/RX endpoints
    set txs [get_hw_sio_txs -of_objects $fpga_dev]
    set rxs [get_hw_sio_rxs -of_objects $fpga_dev]

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
        commit_hw_sio $linkObj

        # enable PRBS 31-bit
        set_property TX_PATTERN {PRBS 31-bit} $linkObj
        set_property RX_PATTERN {PRBS 31-bit} $linkObj
        commit_hw_sio -non_blocking $linkObj

        # record for Phase 2: [target device link threshold label]
        set label "$txName->$rxName"
        lappend all_tests [list $tgt $fpga_dev $linkObj $threshold $label]
        puts "Scheduled test: Board#$idx $label"
    }
	
	# 4.x) Done with this board: close it so next one can open
    puts "INFO: closing target [get_property NAME $tgt]"
    catch { close_hw_target }
}

# ======================================================
# Phase 2: BER tests on each board, one at a time
#   (must come AFTER all boards have been programmed)
# ======================================================

foreach entry $boards {
    # parse exactly as in Phase 1
    set parts     [split $entry ","]
    set serial    [lindex $parts 0]
    set threshold [expr {[lindex $parts 2]}]
    set links     [lrange $parts 3 end]

    puts "\n=== BER Test for board serial=$serial ==="

    # 2.1) Switch & open the correct target
    catch { close_hw_target }
    foreach t [get_hw_targets] {
        if {[lindex [split [get_property UID $t] "/"] end] eq $serial} {
            current_hw_target $t
            if {[catch { open_hw_target } err]} {
                puts "ERROR opening target $serial: $err"
                continue 2
            }
            break
        }
    }

    # 2.2) Locate and refresh the FPGA device
    set fpga_dev [lindex [get_hw_devices -of_objects $t] 0]
    refresh_hw_device -force_poll $fpga_dev

    # 2.3) Grab raw TX/RX endpoints
    set txs [get_hw_sio_txs -of_objects $fpga_dev]
    set rxs [get_hw_sio_rxs -of_objects $fpga_dev]

    # 2.4) For each link in the CSV, rebuild & test it
	set linkObjs {}                   ;# initialize
    for {set i 0} {$i < [llength $links]} {incr i 2} {
        set txName [lindex $links $i]
        set rxName [lindex $links [expr {$i+1}]]

        # find the two endpoint objects by suffix match
        set txObj ""; foreach x $txs {
            if {[string match "*$txName" [get_property NAME $x]]} { set txObj $x; break }
        }
        set rxObj ""; foreach x $rxs {
            if {[string match "*$rxName" [get_property NAME $x]]} { set rxObj $x; break }
        }
        if {$txObj eq "" || $rxObj eq ""} {
            puts "WARN: Could not find endpoints $txName/$rxName"
            continue
        }

        # 2.4.1) Re-create the SIO link & arm PRBS31
        set linkObj [create_hw_sio_link $txObj $rxObj]
        commit_hw_sio   $linkObj
        set_property TX_PATTERN {PRBS 31-bit} $linkObj
        set_property RX_PATTERN {PRBS 31-bit} $linkObj
        commit_hw_sio -non_blocking $linkObj
		after 500
		
		# record the link object and a label
        lappend linkObjs [list $linkObj "$txName->$rxName"]
        # cleanup txObj/rxObj for next iteration
        unset txObj rxObj
	}
		
	# 4.x) Reset all link error counters before BER test
	puts "\nINFO: resetting error counters on all links..."
	foreach pair $linkObjs {
		set lnk [lindex $pair 0]
		# assert reset
		set_property LOGIC.MGT_ERRCNT_RESET_CTRL 1 $lnk
		commit_hw_sio -non_blocking $lnk
		after 1000
	}
	# de-assert reset
	foreach pair $linkObjs {
		set lnk [lindex $pair 0]
		set_property LOGIC.MGT_ERRCNT_RESET_CTRL 0 $lnk
		commit_hw_sio -non_blocking $lnk
		after 500
	}
	puts "OK: error counters cleared"

    # 4.6) Now run BER test on each link
    foreach pair $linkObjs {
        set linkObj [lindex $pair 0]
        set label   [lindex $pair 1]

        puts "\nINFO: $label waiting for ≥ $threshold bits…"
        set bits 0
        while {$bits < $threshold} {
            refresh_hw_device -force_poll $fpga_dev
            set bits [get_property RX_RECEIVED_BIT_COUNT $linkObj]
            after 1000
        }
        refresh_hw_device -force_poll $fpga_dev
        set ber [get_property RX_BER $linkObj]
        puts "RESULT: $serial $label → bits=$bits   BER=$ber"
		puts $log_fh "$serial,$label,$ber"
    }

    # 2.5) Close this target before moving on
    catch { close_hw_target }
}

puts "\n=== All BER tests complete ==="

# ————————————————————————————————————————————————————————————
# Close out our BER log handle
# ————————————————————————————————————————————————————————————
close $log_fh
puts "Wrote BER results to $log_file"
# ————————————————————————————————————————————————————————————

# --- 6) Cleanup ---
close_hw_manager
puts "\nAll done. Processed [llength $boards] boards, [llength $all_tests] links."
exit 0
