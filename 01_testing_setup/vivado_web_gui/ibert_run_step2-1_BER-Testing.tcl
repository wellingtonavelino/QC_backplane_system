# ======================================================
# ibert_links-crosstalk_tests_1.tcl
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

# --- 0) User parameters (make sure these appear before you ever use $cfg_file or $max_boards)
# ————————————————————————————————
#set cfg_file   "ibert_05012025-3.txt"
#set cfg_file   "ibert_links-lab_test.txt"
#set cfg_file "ibert_05012025-3-link_isolation.txt"
# --------- on-board links tests  -------------------- #
set cfg_file "ibert_06252025-verification_test.txt"
# --------- qsfp links tests  -------------------- #
#set cfg_file "ibert_06252025-qsfp_test.txt"
#set cfg_file "ibert_rev2_tests.txt"
#set serial_file   "serial_numbers.txt"
#set serial_file   "serial_numbers.txt"
# --------- on-board links tests  -------------------- #
#set serial_file   "serial_numbers_rev4.txt"  
# --------- qsfp links tests  -------------------- #
#set serial_file   "serial_numbers_qsfp.txt"
set serial_file   "serial_numbers.txt"  
set max_boards 4
# ————————————————————————————————

# --- Functions ------------------------------------------------------ #
# ————————————————————————————————————————————————————————————————————
# Resets PRBS counters and error logic multiple times to improve sync
# ————————————————————————————————————————————————————————————————————
proc reset_prbs_and_errcnt {linkObj repeat_count delay_ms} {
    puts "→ Performing $repeat_count PRBS resets on [get_property NAME $linkObj]"
    for {set i 0} {$i < $repeat_count} {incr i} {
        set_property PORT.RXPRBSCNTRESET 1 $linkObj
        after $delay_ms
        set_property PORT.RXPRBSCNTRESET 0 $linkObj
        after $delay_ms
    }

    puts "→ Resetting error counter logic..."
    set_property LOGIC.MGT_ERRCNT_RESET_CTRL 1 $linkObj
    after $delay_ms
    set_property LOGIC.MGT_ERRCNT_RESET_CTRL 0 $linkObj
    after $delay_ms
}
# ————————————————————————————————————————————————————————————————————
# Waits for RX bit flow and reasonable BER before BER read
# ————————————————————————————————————————————————————————————————————
proc wait_for_stable_ber {linkObj thresholdBits max_wait_ms} {
    set elapsed 0
    set wait_step 200

    puts "Waiting for RX bit count to start flowing..."
    set bits_before [get_property RX_RECEIVED_BIT_COUNT $linkObj]
    after $wait_step
    set bits_now [get_property RX_RECEIVED_BIT_COUNT $linkObj]

    while {$bits_now <= $bits_before && $elapsed < $max_wait_ms} {
        refresh_hw_device -force_poll [get_hw_devices]
        set bits_before $bits_now
        after $wait_step
        set bits_now [get_property RX_RECEIVED_BIT_COUNT $linkObj]
        incr elapsed $wait_step
    }

    if {$bits_now > $bits_before} {
        puts "Bit count increasing"
    } else {
        puts "Bit count did not increase after timeout → continuing anyway"
    }

    puts "Waiting for BER to drop below 0.2..."
    set ber [get_property RX_BER $linkObj]
    set target_ber 0.2
    set elapsed 0
    while {$ber > $target_ber && $elapsed < $max_wait_ms} {
        refresh_hw_device -force_poll [get_hw_devices]
        set ber [get_property RX_BER $linkObj]
		after $wait_step
        puts "… Waiting for BER < $target_ber → now=$ber"
        incr elapsed $wait_step
    }

    if {$ber < $target_ber} {
        puts " BER dropped to acceptable range: $ber"
    } else {
        puts " BER stayed high → result may be invalid"
    }
}

# ————————————————————————————————————————————————————————————————————
# Waits for PRBS lock on a given link before BER test
# ————————————————————————————————————————————————————————————————————
proc wait_for_prbs_lock {linkObj max_wait_ms} {
    set elapsed 0
    set wait_step 200
    set locked 0
    while {$elapsed < $max_wait_ms} {
        set locked [get_property PORT.RXPRBSLOCKED $linkObj]
        if {$locked == 1} {
            puts " PRBS LOCKED after ${elapsed}ms"
            return 1
        }
        after $wait_step
        incr elapsed $wait_step
    }
    puts " WARNING: PRBS NOT LOCKED after ${max_wait_ms}ms"
    return 0
}



# --- 2) Open & connect Hardware Manager -------------------------------------- #
open_hw_manager
after 5000
connect_hw_server -url localhost:3121
after 5000
# ----------------------------------------------------------------------------- #

set boards {}
set fp [open $cfg_file r]
foreach line [split [read $fp] "\n"] {
    set ltrim [string trim $line]
    if {$ltrim eq "" || [string index $ltrim 0] == "#"} continue
    lappend boards $ltrim
    if {[llength $boards] >= $max_boards} { break }
}
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
# ----------------------------------------------------------------------------- #
# ----------------------------------------------------------------------------- #
# ============================================================================= #
# Phase 2: BER tests on each board, one at a time
# ============================================================================= #

for {set pass 1} {$pass <= 4} {incr pass} {
    puts "\n=== Starting BER Test Pass #$pass ==="
    puts $log_fh "\n=== BER Test Pass #$pass ==="
	puts $log_fh "IBERT QC BER Log"
	puts $log_fh "Date: [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
	puts $log_fh "Serial,from Board,to Board,BER, ERRORS"

	set slt 0
	foreach entry $boards {
		# parse exactly as in Phase 1
		set parts     [split $entry ","]
		set to_board  [lindex $parts 0]
		set serial [lindex $serial_ns $slt]
		#set serial    [lindex $parts 1]
		set threshold [expr {[lindex $parts 3]}]
		set paths     [lrange $parts 4 6]
		set links     [lrange $parts 7 end]

		puts "\n=== BER Test for board #$slt: $serial ==="

		# 2.1) Switch & open the correct target
		catch { close_hw_target }
		##after 80
		##connect_hw_server -url localhost:3121
		after 800
		foreach t [get_hw_targets] {
			if {[lindex [split [get_property UID $t] "/"] end] eq $serial} {
				current_hw_target $t
				after 800
				if {[catch { open_hw_target } err]} {
					puts "ERROR opening target $serial: $err"
					continue 2
				}
				break
			}
		}
		incr slt

		# 2.2) Locate and refresh the FPGA device
		set fpga_dev [lindex [get_hw_devices -of_objects $t] 0]
		after 500
		refresh_hw_device -force_poll $fpga_dev
		after 500
		
		
		# --- New: clear existent links before creating new ones ---
		puts "Cleaning old existent links in the device..."
		set existing_links [get_hw_sio_links -of_objects $fpga_dev]
		if {[llength $existing_links] > 0} {
			foreach lnk $existing_links {
				delete_hw_sio_link $lnk
				after 1000
			}
			commit_hw_sio -non_blocking $existing_links
			after 8000
		} else {
			puts "No existing links found to delete."
		}
		after 500

		# 2.3) Grab raw TX/RX endpoints
		set txs [get_hw_sio_txs -of_objects $fpga_dev]
		after 500
		set rxs [get_hw_sio_rxs -of_objects $fpga_dev]
		after 500

		# 2.4) For each link in the text file, rebuild & test it
		set linkObjs {}                   ;# initialize
		for {set i 0} {$i < [llength $links]} {incr i 2} {
			
			# --- New block to ENSBLE/DISABLE treatment ---
			set txRaw [lindex $links $i]
			set rxRaw [lindex $links [expr {$i+1}]]

			# Ignore pair if um of them has :DISABLED
			if {[string match "*:DISABLED" $txRaw] || [string match "*:DISABLED" $rxRaw]} {
				puts " Skipping link (DISABLED): $txRaw ↔ $rxRaw"
				continue
			}

			# Extract TX/RX base name(removing :ENABLED or :DISABLED)
			set txName [lindex [split $txRaw ":"] 0]
			set rxName [lindex [split $rxRaw ":"] 0]
			
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
			after 500
			
			#commit_hw_sio $linkObj
			#after 10000
			
			#set_property TXPRE {3.90 dB (01111)} $linkObj
			set_property TXPRE {1.87 dB (01000)} $linkObj
			#set_property TXPRE {0.01 dB (00000)} $linkObj
			#after 8000		
			#set_property TXPOST {3.99 dB (01111)} $linkObj
			set_property TXPOST {2.98 dB (01011)} $linkObj
			#set_property TXPOST {0.00 dB (00000)} $linkObj
			#after 8000
			#set_property TXDIFFSWING {730 mV (01101)} $linkObj
			set_property TXDIFFSWING {780 mV (10000)} $linkObj
			#set_property TXDIFFSWING {390 mV (00000)} $linkObj
			#set_property TXDIFFSWING {1040 mV (11111)} $linkObj
			after 1000
			
			#set_property PORT.RXPOLARITY 0 $linkObj
			#commit_hw_sio $linkObj
			#after 8000
			
			#set_property PORT.TXPOLARITY 0 $linkObj
			#commit_hw_sio $linkObj
			#after 1000
			
			set_property TX_PATTERN {PRBS 31-bit} $linkObj
			#after 8000
			set_property RX_PATTERN {PRBS 31-bit} $linkObj
			after 500  ;# Allow PRBS logic to activate internally
			
			# --- Call the PRBS + error reset helper ---
			reset_prbs_and_errcnt $linkObj 3 500
			after 2000  ;# Let link settle after all resets

			
			#set_property PORT.TXPRBSSEL 3 $linkObj
			#commit_hw_sio $linkObj
			#after 8000
			
			#set_property PORT.RXPRBSSEL 3 $linkObj
			#commit_hw_sio $linkObj
			#after 1000
			

			#commit_hw_sio -non_blocking $linkObj
			#after 1000
			
			
			#refresh_hw_device -force_poll [get_hw_devices]
			#after 1000

			#commit_hw_sio -non_blocking $linkObj
			#after 10000
			
			# record the link object and a label
			lappend linkObjs [list $linkObj "$txName->$rxName"]
			after 500
			# cleanup txObj/rxObj for next iteration
			unset txObj rxObj
			after 800
			
			set_property LOGIC.MGT_ERRCNT_RESET_CTRL 1 $linkObj
			after 800
			#commit_hw_sio -non_blocking $linkObj
			#after 10000
			
			set_property LOGIC.MGT_ERRCNT_RESET_CTRL 0 $linkObj
			after 800
			
			#commit_hw_sio -non_blocking $linkObj
			#after 5000
			
			set_property PORT.RXPRBSCNTRESET 1 $linkObj
			after 500
			set_property PORT.RXPRBSCNTRESET 0 $linkObj
			after 500
			commit_hw_sio -non_blocking $linkObj
			after 800
			
			#refresh_hw_device -force_poll [get_hw_devices]
			#after 3000

			set elapsed 0
			set timeout 10000
			while {$elapsed < $timeout} {
				refresh_hw_device -force_poll [get_hw_devices]
				after 800
				set cdrlock [get_property PORT.RXCDRLOCK $linkObj]
				if {$cdrlock} {
					puts " CDR LOCKED after $elapsed sec"
					#return 1
					set elapsed 10000
				}
				incr elapsed
			}
		}
		
		# 2.5) Reset all link error counters before BER test
		puts "\nINFO: resetting error counters on all links..."
		foreach pair $linkObjs {
			set lnk [lindex $pair 0]
			# assert reset
			set_property LOGIC.MGT_ERRCNT_RESET_CTRL 1 $lnk
			after 800
			commit_hw_sio -non_blocking $lnk
			after 8000
		}
		# de-assert reset
		foreach pair $linkObjs {
			set lnk [lindex $pair 0]
			set_property LOGIC.MGT_ERRCNT_RESET_CTRL 0 $lnk
			after 1000
			commit_hw_sio -non_blocking $lnk
			after 8000
		}
		puts "OK: error counters cleared"
		
		set paths [lrange $parts 4 6]
		set from_board1 [lindex $paths 0]
		set from_board2 [lindex $paths 1]
		set from_board3 [lindex $paths 2]
		
		set board_labels [list $from_board1 $from_board2 $from_board3]
		set i 0


		# 2.6) Now run BER test on each link
		foreach pair $linkObjs {
			set linkObj [lindex $pair 0]
			set label   [lindex $pair 1]
			
			# --- Wait for PRBS lock before starting BER ---
			#puts "Waiting for PRBS lock on $label..."
			#wait_for_prbs_lock $linkObj 10000   ;# Wait up to 10 seconds
			#after 1000  ;# Extra delay for stability
			
			set bp_path [lindex $board_labels $i]

			# Wait for stabilization before starting the test
			#wait_for_stable_ber $linkObj $threshold 10000

			refresh_hw_device -force_poll $fpga_dev
			after 800

			puts "\nINFO: $label waiting for more than $threshold bits"
			set bits 0
			set link_error 0
			while {$bits < $threshold} {
				refresh_hw_device -force_poll $fpga_dev
				after 500
				set bits [get_property RX_RECEIVED_BIT_COUNT $linkObj]
				set ber [get_property RX_BER $linkObj]
				#after 500
			}
			puts "Link: $linkObj"
			puts "  CDR Locked: [get_property PORT.RXCDRLOCK $linkObj]"
			puts "  PRBS Locked: [get_property PORT.RXPRBSLOCKED $linkObj]"
			puts "  RX Valid: [get_property PORT.RXDATAVALID $linkObj]"
			refresh_hw_device -force_poll $fpga_dev
			#after 500
			set link_error [expr {$bits*$ber}]
			puts "RESULT: $serial - $bp_path -  bits=$bits   BER=$ber  ERRORS=$link_error"
		
			# puts "\n Checking RX activity before BER testing..."
			# foreach pair $linkObjs {
			# set lnk [lindex $pair 0]
			# set label [lindex $pair 1]

			# # Initial Reading of received bits 
			# set bits_before [get_property RX_RECEIVED_BIT_COUNT $lnk]
			# after 2000
			# set bits_after [get_property RX_RECEIVED_BIT_COUNT $lnk]
			# refresh_hw_device -force_poll $fpga_dev
			# after 800

			# # Verify if bits received increased 
			# set delta [expr {$bits_after - $bits_before}]
			# if {$delta < 0} {
				# puts "Bit counter restarted (overflow)."
				# set delta [expr {(2**64) + $delta}]  ;# estimativa para wrap de 64 bits
			# }
		
			# if {$delta > 0} {
				# puts "Active Link: increased in $delta bits ($bits_before → $bits_after)"
			# } else {
				# puts "Stopped Link: $bits_before = $bits_after"
			# }
		# }
			
			# Output for python integration
			set status "ENABLED"
			if {[string match "*:DISABLED" $txRaw] || [string match "*:DISABLED" $rxRaw]} {
				set status "DISABLED"
			}
			if {$pass > 3} {
				puts "PYTHON_OUT: serial=$serial;link=$label;status=$status;from=$bp_path;to=$to_board;ber=$ber;errors=$link_error"
				puts $log_fh "$serial,$bp_path,$to_board,$ber,$link_error"
			}	
			
			incr i
		}

		# 2.7) Close this target before moving on
		catch { close_hw_target }
	};# end foreach entry
    puts "\n=== BER Test Pass #$pass complete ==="
    puts $log_fh "=== BER Test Pass #$pass complete ==="
} ;# end for pass
puts $log_fh "\n=== All BER tests complete ==="
puts $log_fh ""

puts "\n=== All BER tests complete ==="

# ————————————————————————————————————————————————————————————
# Close out our BER log handle
# ————————————————————————————————————————————————————————————
close $log_fh
puts "Wrote BER results to $log_file"
# ————————————————————————————————————————————————————————————

# --- 3) Cleanup ---
close_hw_manager
puts "\nAll done. Processed [llength $boards] boards, [llength $all_tests] links."
exit 0