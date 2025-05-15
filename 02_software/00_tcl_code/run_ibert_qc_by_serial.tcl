# ======================================================
# run_ibert_qc_by_serial.tcl
# ------------------------------------------------------
# Usage: vivado -mode tcl -source run_ibert_qc_by_serial.tcl
#
# Expects in same folder:
#   • ibert_05012025.txt
#       serial,bitfile,threshold_bits,link1,link2,...
#   • <BITFILE>.bit
# ======================================================

# --- User params ---
set cfg_file   "ibert_05012025.txt"
set max_boards 1

# --- Helper sleep ---
proc busySleep {ms} { after $ms }

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

# --- 1) Open HW Manager ---
puts "\nINFO: open_hw_manager..."
if {[catch { open_hw_manager } err]} {
    puts "ERROR at open_hw_manager: $err"; exit 1
} else {
    puts "OK: open_hw_manager"
}

# --- 2) Connect to hw_server ---
puts "INFO: connect_hw_server..."
if {[catch { connect_hw_server -url localhost:3121 } err]} {
    puts "ERROR at connect_hw_server: $err"; exit 1
} else {
    puts "OK: connect_hw_server"
}

# --- 3) Read config file ---
puts "\nINFO: reading '$cfg_file'..."
if {[catch { set fh [open $cfg_file r] } err]} {
    puts "ERROR opening '$cfg_file': $err"; exit 1
}
if {[catch { set lines [split [read $fh] "\n"] } err]} {
    puts "ERROR reading '$cfg_file': $err"; close $fh; exit 1
}
close $fh
puts "OK: read config file"

# --- 4) Parse first data line ---
set entry ""
foreach l $lines {
    set line [string trim $l]
    if {$line eq "" || [string index $line 0] == "#"} continue
    set entry $line; break
}
if {$entry eq ""} {
    puts "ERROR: no valid data in '$cfg_file'"; exit 1
}
set parts [split $entry ","]
if {[llength $parts] < 4} {
    puts "ERROR: need at least 4 fields (serial,bitfile,threshold,links…)"; exit 1
}
set serialWanted   [string trim [lindex $parts 0]]
set bitfile        [string trim [lindex $parts 1]]
if {[catch { expr {[lindex $parts 2]} } _ threshold_bits]} {
    puts "ERROR parsing threshold_bits"; exit 1
}
set links          [lrange $parts 3 end]
puts "OK: cfg → SERIAL=$serialWanted  BITFILE=$bitfile  THRESHOLD_BITS=$threshold_bits"
puts "    LINKS=$links"

# --- 5) Find & open the target by matching serial only ---
puts "\nINFO: get_hw_targets..."
if {[catch { set tgtlist [get_hw_targets] } err]} {
    puts "ERROR at get_hw_targets: $err"; exit 1
}
puts "DEBUG: Available target UIDs:"
foreach t $tgtlist {
    puts "  [get_property UID $t]"
}

set tgt ""
foreach t $tgtlist {
    if {[catch { set uidVal [get_property UID $t] }]} continue
    set ser [lindex [split $uidVal "/"] end]
    if {$ser eq $serialWanted} {
        set tgt $t; break
    }
}
if {$tgt eq ""} {
    puts "ERROR: no hw_target with serial='$serialWanted'"; exit 1
}
puts "OK: matched target [get_property NAME $tgt] (UID=[get_property UID $tgt])"

puts "INFO: current_hw_target..."
if {[catch { current_hw_target $tgt } err]} {
    puts "ERROR at current_hw_target: $err"; exit 1
} else {
    puts "OK: current_hw_target"
}

puts "INFO: open_hw_target..."
if {[catch { open_hw_target } err]} {
    puts "ERROR at open_hw_target: $err"; exit 1
} else {
    puts "OK: open_hw_target"
}


# --- 6) Locate & program the FPGA device ---
puts "\nINFO: get_hw_devices..."
if {[catch { set devs [get_hw_devices -of_objects $tgt] } err]} {
    puts "ERROR at get_hw_devices: $err"
    exit 1
}

# (Optional) debug dump omitted for brevity…

# Initialize before matching
set fpga_dev ""
foreach d $devs {
    if {[catch { set nameVal [string tolower [get_property NAME $d]] }]} { set nameVal "" }
    if {[catch { set partVal [string tolower [get_property PART_NAME $d]] }]} { set partVal "" }
    if {[string match "*xczu47dr*" $nameVal] || [string match "*xczu47dr*" $partVal]} {
        set fpga_dev $d
        break
    }
}

if {$fpga_dev eq ""} {
    puts "ERROR: no XCZU47DR device found"
    exit 1
}
puts "OK: FPGA device = [get_property NAME $fpga_dev]"

# 6.1) Associate the bitstream with the device
puts "INFO: set_property PROGRAM.FILE → $bitfile"
if {[catch { set_property PROGRAM.FILE $bitfile $fpga_dev } err]} {
    puts "ERROR at set_property PROGRAM.FILE: $err"
    exit 1
} else {
    puts "OK: set_property PROGRAM.FILE"
}

# 6.2) Program the device
puts "INFO: program_hw_devices $fpga_dev"
if {[catch { program_hw_devices $fpga_dev } err]} {
    puts "ERROR at program_hw_devices: $err"
    exit 1
} else {
    puts "OK: program_hw_devices"
}

# --- 6.3) Refresh the device so that IBERT cores & links show up ---
puts "INFO: refresh_hw_device (scan for IBERT/ILA cores)…"
if {[catch { refresh_hw_device -force_poll $fpga_dev } err]} {
    puts "ERROR at refresh_hw_device: $err"
    exit 1
} else {
    puts "OK: refresh_hw_device"
}

puts "\n=== DEBUG: ILA cores under $fpga_dev ==="
# List any ILA cores (IBERT cores appear here as “sio_linkgroup” parents)
if {[catch { set ilas [get_hw_ilas -of_objects $fpga_dev] } err]} {
    puts "ERROR getting ILAs: $err"
} elseif {[llength $ilas] == 0} {
    puts "  (none found – no IBERT/ILA cores detected!)"
} else {
    foreach i $ilas {
        puts "  ILA object: $i   NAME=[get_property NAME $i]"
    }
}
puts "========================================\n"


# --- DEBUG: dump all SIO links under the FPGA device ---
puts "\n=== All SIO links under [get_property NAME $fpga_dev] ==="
if {[catch { set all_sio [get_hw_sio_links -of_objects $fpga_dev] } err]} {
    puts "ERROR getting any SIO links: $err"
} elseif {[llength $all_sio] == 0} {
    puts "  (none found)"
} else {
    foreach lnk $all_sio {
        # Print the NAME and any other useful properties
        set nm    [get_property NAME               $lnk]
        set cnt   [catch { get_property RX_BER     $lnk } ;# BER may or may not exist
                    set ber "[lindex [split [info complete $::errorInfo] "\n"] 0]"
                    ]
        set cnt2  [catch { get_property RX_RECEIVED_BIT_COUNT $lnk } ;# bit count
                    set bits "[lindex [split [info complete $::errorInfo] "\n"] 0]"
                    ]
        puts " Link object: $lnk"
        puts "    NAME                   : $nm"
        if {$cnt  == 0} { puts "    RX_BER                 : [get_property RX_BER $lnk]" }
        if {$cnt2 == 0} { puts "    RX_RECEIVED_BIT_COUNT  : [get_property RX_RECEIVED_BIT_COUNT $lnk]" }
    }
}
puts "=============================================\n"

# ======================================================
# 7) PRBS31 test loop via dynamic SIO links + BER check
# ======================================================

# 7.1) Grab all TX and RX endpoint objects
puts "\nINFO: retrieving raw TX/RX endpoints..."
if {[catch { set txs [get_hw_sio_txs -of_objects $fpga_dev] } err]} {
    puts "ERROR: get_hw_sio_txs failed: $err"; exit 1
}
if {[catch { set rxs [get_hw_sio_rxs -of_objects $fpga_dev] } err]} {
    puts "ERROR: get_hw_sio_rxs failed: $err"; exit 1
}
puts "DEBUG: found [llength $txs] TX endpoints and [llength $rxs] RX endpoints"
foreach t $txs { puts "  TX: [get_property NAME $t]" }
foreach r $rxs { puts "  RX: [get_property NAME $r]" }

# 7.2) Pair up endpoints and run PRBS31 test
#    we expect $links to be: TX1,RX1,TX2,RX2,...
for {set i 0} {$i < [llength $links]} {incr i 2} {
    set txName [lindex $links $i]
    set rxName [lindex $links [expr {$i+1}]]
    puts "\nINFO: setting up link for TX=$txName  RX=$rxName"

    # find endpoints by suffix match
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
        puts "ERROR: could not find TX or RX endpoint for $txName/$rxName"
        continue
    }

    # 7.2.1) Create & commit the SIO link
    puts "INFO: create_hw_sio_link..."
    if {[catch { set linkObj [create_hw_sio_link $txObj $rxObj] } err]} {
        puts "ERROR at create_hw_sio_link: $err"; continue
    }
    puts "OK: created link = $linkObj"

    puts "INFO: commit_hw_sio..."
    if {[catch { commit_hw_sio $linkObj } err]} {
        puts "ERROR at commit_hw_sio: $err"; continue
    }
    puts "OK: link committed"

    # 7.2.2) Configure PRBS 31‐bit
    puts "INFO: enabling PRBS 31‐bit..."
    if {[catch {
        set_property TX_PATTERN {PRBS 31-bit} $linkObj
        set_property RX_PATTERN {PRBS 31-bit} $linkObj
        commit_hw_sio -non_blocking $linkObj
    } err]} {
        puts "ERROR enabling PRBS-31 bit: $err"
        continue
    }
    puts "OK: PRBS-31 bit enabled"



    # 7.2.3) Wait for ≥ threshold_bits received
    puts "INFO: waiting for ≥ $threshold_bits bits..."
    set bits 0
    while {$bits < $threshold_bits} {
        refresh_hw_sio $linkObj
        set bits [get_property RX_RECEIVED_BIT_COUNT $linkObj]
        after 500
    }

    # 7.2.4) Final refresh & BER read
    refresh_hw_sio $linkObj
    set ber [get_property RX_BER $linkObj]
    puts "RESULT: link=(TX=$txName,RX=$rxName)  bits=$bits  BER=$ber"
}

# --- end of PRBS31 test loop ---



puts "\nINFO: close_hw_manager..."
catch { close_hw_manager }
puts "PRBS31 QC run complete."
exit 0
