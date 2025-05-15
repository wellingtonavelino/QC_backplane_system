# ======================================================
# run_ibert_qc_defensive.tcl
# ------------------------------------------------------
# Usage:
#   vivado -mode tcl -source run_ibert_qc_defensive.tcl
#
# Expects ibert_05012025.txt in same folder:
#   UID,BITFILE,THRESHOLD_BITS,LINK0,LINK1,LINK2,LINK3
# ======================================================

# --- User parameters ---
set cfg_file   "ibert_05012025.txt"
set max_boards 1

# --- Step 1: Open HW Manager ---
puts "INFO: open_hw_manager..."
if {[catch { open_hw_manager } err]} {
    puts "ERROR at open_hw_manager: $err"
    exit 1
} else {
    puts "OK: open_hw_manager"
}

# --- Step 2: Connect to hw_server ---
puts "INFO: connect_hw_server..."
if {[catch { connect_hw_server -url tcp:localhost:3121 } err]} {
    puts "ERROR at connect_hw_server: $err"
    exit 1
} else {
    puts "OK: connect_hw_server"
}

# --- Step 3: Read config file ---
puts "INFO: open config file..."
if {[catch { set fh [open $cfg_file r] } err]} {
    puts "ERROR opening config file '$cfg_file': $err"
    exit 1
} else {
    puts "OK: opened '$cfg_file'"
}
puts "INFO: read config file..."
if {[catch { set lines [split [read $fh] "\n"] } err]} {
    puts "ERROR reading '$cfg_file': $err"
    exit 1
} else {
    puts "OK: read '$cfg_file'"
}
catch { close $fh }

# --- Step 4: Parse first non-comment line ---
set entry ""
foreach l $lines {
    set line [string trim $l]
    if {$line eq "" || [string index $line 0] == "#"} continue
    set entry $line
    break
}
if {$entry eq ""} {
    puts "ERROR: no data lines in $cfg_file"
    exit 1
}
set parts [split $entry ","]
if {[llength $parts] < 7} {
    puts "ERROR: malformed entry; need at least 7 fields"
    exit 1
}
set uid   [lindex $parts 0]
set bitfile [lindex $parts 1]
# parse threshold_bits as integer
if {[catch { expr {[lindex $parts 2]} } err threshold_bits]} {
    puts "ERROR parsing threshold_bits: $err"
    exit 1
} else {
    puts "OK: threshold_bits = $threshold_bits"
}
set links [lrange $parts 3 end]
puts "INFO: UID=$uid, BITFILE=$bitfile, LINKS=$links"

# --- Step 5: Find & open target by UID ---
puts "INFO: get_hw_targets..."
if {[catch { set tgtlist [get_hw_targets] } err]} {
    puts "ERROR at get_hw_targets: $err"
    exit 1
} else {
    puts "OK: get_hw_targets returned $tgtlist"
}
set tgt ""
foreach t $tgtlist {
    if {[catch { get_property UID $t } _ val]} {
        puts "WARN: cannot read UID for $t: $_"
        continue
    }
    if {$val eq $uid} {
        set tgt $t
        break
    }
}
if {$tgt eq ""} {
    puts "ERROR: no hw_target with UID='$uid'"
    exit 1
} else {
    puts "OK: matched target $tgt"
}

puts "INFO: current_hw_target..."
if {[catch { current_hw_target $tgt } err]} {
    puts "ERROR at current_hw_target: $err"
    exit 1
} else {
    puts "OK: current_hw_target"
}

puts "INFO: open_hw_target..."
if {[catch { open_hw_target } err]} {
    puts "ERROR at open_hw_target: $err"
    exit 1
} else {
    puts "OK: open_hw_target"
}

# --- Step 6: Locate FPGA device and program ---
puts "INFO: get_hw_devices..."
if {[catch { set devs [get_hw_devices -of_objects $tgt] } err]} {
    puts "ERROR at get_hw_devices: $err"
    exit 1
} else {
    puts "OK: get_hw_devices returned $devs"
}
set fpga_dev ""
foreach d $devs {
    if {[catch { get_property PART_NAME $d } _ part]} {
        puts "WARN: cannot read PART_NAME for $d"
        continue
    }
    if {[string tolower $part] contains "xczu47dr-1ffvg1517"} {
        set fpga_dev $d
        break
    }
}
if {$fpga_dev eq ""} {
    puts "ERROR: no XCZU47DR-1FFVG1517 FPGA found"
    exit 1
} else {
    puts "OK: FPGA device = $fpga_dev"
}

# Check bitfile exists
if {![file exists $bitfile]} {
    puts "ERROR: bitfile '$bitfile' not found"
    exit 1
}

puts "INFO: program_hw_devices..."
if {[catch { program_hw_devices -hw_devices $fpga_dev -bitfile $bitfile } err]} {
    puts "ERROR at program_hw_devices: $err"
    exit 1
} else {
    puts "OK: program_hw_devices"
}

# --- Step 7: IBERT test on each link ---
proc busySleep {ms} {
    after $ms
}
foreach linkName $links {
    puts "INFO: get_hw_sio_links for '$linkName'..."
    if {[catch { set sio_list [get_hw_sio_links -of_objects $fpga_dev -filter $linkName] } err]} {
        puts "ERROR at get_hw_sio_links($linkName): $err"
        continue
    }
    if {[llength $sio_list] == 0} {
        puts "ERROR: no link matching '$linkName'"
        continue
    }
    set sio [lindex $sio_list 0]
    puts "OK: found link object $sio"

    puts "INFO: waiting for RX_RECEIVED_BIT_COUNT ≥ $threshold_bits..."
    while {1} {
        if {[catch { set bits [get_property RX_RECEIVED_BIT_COUNT $sio] } err]} {
            puts "ERROR reading RX_RECEIVED_BIT_COUNT: $err"
            break
        }
        if {$bits >= $threshold_bits} { break }
        busySleep 500
    }

    if {[catch { set ber [get_property RX_BER $sio] } err]} {
        puts "WARN: reading RX_BER failed: $err"
        set ber "N/A"
    }

    puts "RESULT: link=$linkName  bits=$bits  BER=$ber"
}

# --- Cleanup ---
puts "INFO: close_hw_manager..."
catch { close_hw_manager }
puts "QC run complete."
exit 0
