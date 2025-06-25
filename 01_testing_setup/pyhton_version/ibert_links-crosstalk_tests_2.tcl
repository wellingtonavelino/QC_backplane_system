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
set cfg_file "ibert_24062025-3-link_isolation.txt"
#set serial_file   "serial_numbers.txt"
#set serial_file   "serial_numbers.txt"
set serial_file   "serial_numbers_rev2-rev4.txt"
set max_boards 4
# ————————————————————————————————

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
	after 8000
	catch { disconnect_hw_server }
	after 8000
	connect_hw_server -url localhost:3121
	after 8000
    foreach t [get_hw_targets] {
        if {[lindex [split [get_property UID $t] "/"] end] eq $serial} {
            current_hw_target $t
			after 8000
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
	after 5000
    refresh_hw_device -force_poll $fpga_dev
	after 8000
	
	
	# --- Novo: Apaga links existentes antes de criar os novos ---
	puts " Cleaning old existent links in the device..."
	set existing_links [get_hw_sio_links -of_objects $fpga_dev]
	if {[llength $existing_links] > 0} {
    foreach lnk $existing_links {
        delete_hw_sio_link $lnk
		after 10000
    }
		commit_hw_sio -non_blocking $existing_links
		after 10000
	} else {
		puts "ℹ️  No existing links found to delete."
	}
	after 8000

    # 2.3) Grab raw TX/RX endpoints
    set txs [get_hw_sio_txs -of_objects $fpga_dev]
	after 3000
    set rxs [get_hw_sio_rxs -of_objects $fpga_dev]
	after 3000

    # 2.4) For each link in the CSV, rebuild & test it
	set linkObjs {}                   ;# initialize
    for {set i 0} {$i < [llength $links]} {incr i 2} {
        #set txName [lindex $links $i]
        #set rxName [lindex $links [expr {$i+1}]]
		
		# --- Novo bloco para tratamento de ENABLED/DISABLED ---
		set txRaw [lindex $links $i]
		set rxRaw [lindex $links [expr {$i+1}]]

		# Ignora o par se qualquer um dos dois estiver marcado como :DISABLED
		if {[string match "*:DISABLED" $txRaw] || [string match "*:DISABLED" $rxRaw]} {
			puts "🔕 Skipping link (DISABLED): $txRaw ↔ $rxRaw"
			continue
		}

		# Extrai apenas o nome base do TX/RX (removendo :ENABLED ou :DISABLED)
		set txName [lindex [split $txRaw ":"] 0]
		set rxName [lindex [split $rxRaw ":"] 0]
		# --- Novo bloco para tratamento de ENABLED/DISABLED ---
		

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
		after 10000
				
		# Set PRBS pattern
		#set_property TX_PATTERN {PRBS 7-bit} $linkObj
        #set_property RX_PATTERN {PRBS 7-bit} $linkObj
		#set_property TX_PATTERN {PRBS 15-bit} $linkObj
        #set_property RX_PATTERN {PRBS 15-bit} $linkObj
		#set_property TX_PATTERN {PRBS 23-bit} $linkObj
        #set_property RX_PATTERN {PRBS 23-bit} $linkObj
        set_property TX_PATTERN {PRBS 31-bit} $linkObj
        set_property RX_PATTERN {PRBS 31-bit} $linkObj
		
		
		# half data rate = 12.5 GHz
		#set_property TX_PATTERN {Fast Clk} $linkObj     
		#set_property RX_PATTERN {Fast Clk} $linkObj    
		# quarter data rate = 6.25 GHz		
		#set_property TX_PATTERN {Slow Clk} $linkObj  
		#set_property RX_PATTERN {Slow Clk} $linkObj
		after 8000
		
		# Commit settings (non-blocking commit is acceptable here)
        commit_hw_sio -non_blocking $linkObj
		after 10000

		
		# Additional signal integrity settings
		set_property TXPRE {3.90 dB (01111)} $linkObj
		#set_property TXPRE {1.87 dB (01000)} $linkObj
		#set_property TXPRE {0.01 dB (00000)} $linkObj
		after 10000		
		set_property TXPOST {3.99 dB (01111)} $linkObj
		#set_property TXPOST {2.98 dB (01011)} $linkObj
		#set_property TXPOST {0.00 dB (00000)} $linkO
		after 10000
		#set_property TXDIFFSWING {730 mV (01101)} $linkObj
		set_property TXDIFFSWING {780 mV (10000)} $linkObj
		#set_property TXDIFFSWING {390 mV (00000)} $linkObj
		after 10000

		
		# Commit settings (non-blocking commit is acceptable here)
        commit_hw_sio -non_blocking $linkObj
		after 10000
		
		# record the link object and a label
        lappend linkObjs [list $linkObj "$txName->$rxName"]
        # cleanup txObj/rxObj for next iteration
        unset txObj rxObj
		after 8000
		
		set_property LOGIC.MGT_ERRCNT_RESET_CTRL 1 $linkObj
		commit_hw_sio -non_blocking $linkObj
		after 10000
		
		set_property LOGIC.MGT_ERRCNT_RESET_CTRL 0 $linkObj
		commit_hw_sio -non_blocking $linkObj
		after 10000
		
		# Poll RXCDRLOCKSTICKY
		set elapsed 0
		set timeout 5000
		while {$elapsed < $timeout} {
			refresh_hw_device -force_poll [get_hw_devices]
			set cdrlock [get_property PORT.RXCDRLOCK $linkObj]
			if {$cdrlock} {
				puts " CDR LOCKED after $elapsed sec"
				#return 1
				set elapsed 5000
			}
			after 500
			incr elapsed
		}
    #puts "Timeout: RXCDRLOCKSTICKY never asserted"
		
	}
	
	puts "\n Verificando atividade de RX antes do teste BER..."
	foreach pair $linkObjs {
    set lnk [lindex $pair 0]
    set label [lindex $pair 1]

    # Leitura inicial de bits recebidos
    set bits_before [get_property RX_RECEIVED_BIT_COUNT $lnk]
    after 2000
    refresh_hw_device -force_poll $fpga_dev
    # Leitura após 2 segundos
    set bits_after [get_property RX_RECEIVED_BIT_COUNT $lnk]

    # Verifica se a contagem aumentou
	set delta [expr {$bits_after - $bits_before}]
	if {$delta < 0} {
		puts "⚠ Contador de bits reiniciou (overflow)."
		set delta [expr {(2**64) + $delta}]  ;# estimativa para wrap de 64 bits
	}
	
	if {$delta > 0} {
		puts "Link ativo: aumentou em $delta bits ($bits_before → $bits_after)"
	} else {
		puts "Link parado: $bits_before = $bits_after"
	}
	}

	
	
	
		
	# 4.x) Reset all link error counters before BER test
	puts "\nINFO: resetting error counters on all links..."
	foreach pair $linkObjs {
		set lnk [lindex $pair 0]
		# assert reset
		set_property LOGIC.MGT_ERRCNT_RESET_CTRL 1 $lnk
		after 8000
		commit_hw_sio -non_blocking $lnk
		after 8000
	}
	# de-assert reset
	foreach pair $linkObjs {
		set lnk [lindex $pair 0]
		set_property LOGIC.MGT_ERRCNT_RESET_CTRL 0 $lnk
		after 10000
		commit_hw_sio -non_blocking $lnk
		after 10000
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
		
		# # Verifica  CDR lock
		# set cdrlock [get_property PORT.RXCDRLOCK $rxObj]
		# if {$cdrlock != 1} {
			# puts "⚠CDR ainda não lockado (PORT.RXCDRLOCK=$cdrlock). Pode afetar a qualidade do Eye Scan."
		# } else {
			# puts "CDR lock confirmado (PORT.RXCDRLOCK=1)."
		# }

		# puts " CDR Lock status: $cdrlock"
		# if {!$cdrlock} {
			# puts " RX não está com CDR lock. Pulando o scan."
			# #continue
		# }

        puts "\nINFO: $label waiting for more than $threshold bits"
        set bits 0
		set link_error 0
        while {$bits < $threshold} {
            refresh_hw_device -force_poll $fpga_dev
			after 5000
            set bits [get_property RX_RECEIVED_BIT_COUNT $linkObj]
            after 5000
        }
        refresh_hw_device -force_poll $fpga_dev
		after 5000
        set ber [get_property RX_BER $linkObj]
		set link_error [expr {$bits*$ber}]
        puts "RESULT: $serial - $bp_path -  bits=$bits   BER=$ber  ERRORS=$link_error"
		# Determina se o link foi marcado como DISABLED
		set status "ENABLED"
		if {[string match "*:DISABLED" $txRaw] || [string match "*:DISABLED" $rxRaw]} {
			set status "DISABLED"
		}
		puts "PYTHON_OUT: serial=$serial;link=$label;status=$status;from=$bp_path;to=$to_board;ber=$ber;errors=$link_error"
		#puts "PYTHON_OUT: serial=$serial;link=$label;ber=$ber;errors=$link_error"
		#puts $log_fh "$serial,$label,$ber" bp_path
		puts $log_fh "$serial,$bp_path,$to_board,$ber,$link_error"
		#set bits_tested [get_property RX_RECEIVED_BIT_COUNT $rxRaw]
		#puts "\nBITS RECEIVED: $bits_tested bits"
		
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