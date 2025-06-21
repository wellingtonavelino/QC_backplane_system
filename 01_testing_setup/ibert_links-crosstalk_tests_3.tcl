# ======================================================
# Phase 2: BER tests on each board, one at a time
#   (must come AFTER all boards have been programmed)
# ======================================================

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
	# set retries 0
	# while {[llength [get_hw_targets -filter {IS_OPEN==true}]] != 0 && $retries < 5} {
			# after 1000
			# incr retries
		# }
	after 5000
	catch { disconnect_hw_server }
	after 2000
	connect_hw_server -url localhost:3121
	after 5000
    foreach t [get_hw_targets] {
        if {[lindex [split [get_property UID $t] "/"] end] eq $serial} {
            current_hw_target $t
			after 500
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

    # 2.3) Grab raw TX/RX endpoints
    set txs [get_hw_sio_txs -of_objects $fpga_dev]
	after 1000
    set rxs [get_hw_sio_rxs -of_objects $fpga_dev]
	after 1000

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
				
		# Set PRBS pattern
        set_property TX_PATTERN {PRBS 31-bit} $linkObj
        set_property RX_PATTERN {PRBS 31-bit} $linkObj
		#set_property TX_PATTERN {PRBS 7-bit} $linkObj
        #set_property RX_PATTERN {PRBS 7-bit} $linkObj
		
		# Additional signal integrity settings
		#set_property TXPRE {3.90 dB (01111)} $linkObj
		#set_property TXPRE {1.87 dB (01000)} $linkObj
		#set_property TXPRE {0.01 dB (00000)} $linkObj
		#after 1000		
		#set_property TXPOST {3.99 dB (01111)} $linkObj
		#set_property TXPOST {2.98 dB (01011)} $linkObj
		#set_property TXPOST {0.00 dB (00000)} $linkO
		#after 1000
		#set_property TXDIFFSWING {730 mV (01101)} $linkObj
		#set_property TXDIFFSWING {780 mV (10000)} $linkObj
		#set_property TXDIFFSWING {390 mV (00000)} $linkObj
		#after 3000

		
		# Commit settings (non-blocking commit is acceptable here)
        commit_hw_sio -non_blocking $linkObj
		after 1000
		
		# record the link object and a label
        lappend linkObjs [list $linkObj "$txName->$rxName"]
        # cleanup txObj/rxObj for next iteration
        unset txObj rxObj
		after 1000
		
		set_property LOGIC.MGT_ERRCNT_RESET_CTRL 1 $linkObj
		commit_hw_sio -non_blocking $linkObj
		after 1000
		
		set_property LOGIC.MGT_ERRCNT_RESET_CTRL 0 $linkObj
		commit_hw_sio -non_blocking $linkObj
		after 1000
		
		# Poll RXCDRLOCKSTICKY
		set elapsed 0
		set timeout 1000
		# while {$elapsed < $timeout} {
			# refresh_hw_device -force_poll [get_hw_devices]
			# set locked [get_property LOGIC.RXCDRLOCKSTICKY $linkObj]
			# if {$locked} {
				# puts " CDR LOCKED (sticky) after $elapsed sec"
				# return 1
        # }
        # after 1000
        # incr elapsed
    # }
    puts "Timeout: RXCDRLOCKSTICKY never asserted"
		
	}
		
	# 4.x) Reset all link error counters before BER test
	puts "\nINFO: resetting error counters on all links..."
	foreach pair $linkObjs {
		set lnk [lindex $pair 0]
		# assert reset
		set_property LOGIC.MGT_ERRCNT_RESET_CTRL 1 $lnk
		after 1000
		commit_hw_sio -non_blocking $lnk
		after 5000
	}
	# de-assert reset
	foreach pair $linkObjs {
		set lnk [lindex $pair 0]
		set_property LOGIC.MGT_ERRCNT_RESET_CTRL 0 $lnk
		after 1000
		commit_hw_sio -non_blocking $lnk
		after 5000
	}
	puts "OK: error counters cleared"
	
	set paths [lrange $parts 4 6]
	set from_board1 [lindex $paths 0]
	set from_board2 [lindex $paths 1]
	set from_board3 [lindex $paths 2]
	
	set board_labels [list $from_board1 $from_board2 $from_board3]
	set i 0


    # 4.6) Now run BER test on each link
    foreach pair $linkObjs {
        set linkObj [lindex $pair 0]
        set label   [lindex $pair 1]
		
		set bp_path [lindex $board_labels $i]

        puts "\nINFO: $label waiting for more than $threshold bits"
        set bits 0
		set link_error 0
        while {$bits < $threshold} {
            refresh_hw_device -force_poll $fpga_dev
			after 3000
            set bits [get_property RX_RECEIVED_BIT_COUNT $linkObj]
            after 3000
        }
        refresh_hw_device -force_poll $fpga_dev
		after 5000
        set ber [get_property RX_BER $linkObj]
		set link_error [expr {$bits*$ber}]
        puts "RESULT: $serial - $bp_path -  bits=$bits   BER=$ber  ERRORS=$link_error"
		#puts $log_fh "$serial,$label,$ber" bp_path
		puts $log_fh "$serial,$bp_path,$to_board,$ber,$link_error"
		
		incr i
    }

    # 2.5) Close this target before moving on
    catch { close_hw_target }
}
puts $log_fh "\n=== All BER tests complete ==="
puts $log_fh ""

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