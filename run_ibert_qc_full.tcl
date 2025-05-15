# ======================================================
# run_ibert_qc_full.tcl
# ------------------------------------------------------
# Usage: vivado -mode tcl -source run_ibert_qc_full.tcl
# Expects in same folder:
#   • ibert_05012025.txt  (UID,BITFILE,THRESHOLD_BITS,LINK0,LINK1,LINK2,LINK3)
#   • <BITFILE>.bit
# ======================================================

# --- User params ---
set cfg_file   "ibert_05012025.txt"
set max_boards 1

# --- Helper sleep ---
proc busySleep {ms} { after $ms }

# --- 0) Locate & launch hw_server.bat by searching up from vivado.exe ---
#    with debug printing of every candidate path
puts ""
set vivado_exe  [file normalize [info nameofexecutable]]
puts "DEBUG: vivado executable = $vivado_exe"

set dir         [file dirname $vivado_exe]
set triedPaths  {}
set hw_server_bat ""

while {1} {
    # candidate is "<this_dir>/bin/hw_server.bat"
    set candidate [file join $dir bin hw_server.bat]
    lappend triedPaths $candidate
    if {[file exists $candidate]} {
        set hw_server_bat $candidate
        break
    }
    set parent [file dirname $dir]
    if {$parent eq $dir} { break }    ;# reached filesystem root
    set dir $parent
}

puts "DEBUG: tried paths:"
foreach p $triedPaths { puts "  $p" }

# if we still didn’t find it, fall back to a known location
if {$hw_server_bat eq ""} {
    set fallback "D:/Xilinx/Vivado_Lab/2023.1.1/bin/hw_server.bat"
    puts "WARN: auto-detect failed, falling back to hard-coded path:"
    puts "      $fallback"
    if {[file exists $fallback]} {
        set hw_server_bat $fallback
    } else {
        puts "ERROR: hw_server.bat not found at any of the above or at fallback."
        exit 1
    }
}

set hw_server_log [file join [file dirname $hw_server_bat] hw_server_debug.log]
puts "INFO: launching hw_server → $hw_server_bat"
if {[catch {
    exec cmd.exe /C start "" "\"$hw_server_bat\"" -d "$hw_server_log"
} err]} {
    puts "WARN: failed to launch hw_server: $err"
} else {
    puts "OK: hw_server launched (log → $hw_server_log)"
}
after 2000


# --- 1) Open HW Manager ---
puts "INFO: open_hw_manager..."
if {[catch { open_hw_manager } err]} {
    puts "ERROR at open_hw_manager: $err"; exit 1
} else { puts "OK: open_hw_manager" }
puts "\n=== Available hw_targets ==="
foreach t [get_hw_targets] {
    puts "Target object: $t"
    puts "  NAME: [get_property NAME $t]"
    puts "   UID: [get_property UID $t]"
    puts "   TID: [get_property TID $t]"
}
puts "=============================\n"


# --- 2) Connect to hw_server ---
puts "INFO: connect_hw_server..."
if {[catch { connect_hw_server -url localhost:3121 } err]} {
    puts "ERROR at connect_hw_server: $err"; exit 1
} else { puts "OK: connect_hw_server" }

# --- 3) Read config file ---
puts "INFO: reading '$cfg_file'..."
if {[catch { set fh [open $cfg_file r] } err]} {
    puts "ERROR opening '$cfg_file': $err"; exit 1
}
if {[catch { set lines [split [read $fh] "\n"] } err]} {
    puts "ERROR reading '$cfg_file': $err"; close $fh; exit 1
}
close $fh
puts "OK: read config file"

# --- 4) Parse first non-comment line ---
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
if {[llength $parts] < 7} {
    puts "ERROR: entry needs 7 fields, got [llength $parts]"; exit 1
}
set uid            [lindex $parts 0]
set bitfile        [lindex $parts 1]
if {[catch { expr {[lindex $parts 2]} } _ threshold_bits]} {
    puts "ERROR parsing threshold_bits"; exit 1
}
set links          [lrange $parts 3 end]
puts "OK: cfg → UID=$uid, BITFILE=$bitfile, THRESHOLD_BITS=$threshold_bits"
puts "    LINKS=$links"

# --- 5) Find & open the target by UID ---
puts "INFO: get_hw_targets..."
if {[catch { set tgtlist [get_hw_targets] } err]} {
    puts "ERROR at get_hw_targets: $err"; exit 1
}
set tgt ""
foreach t $tgtlist {
    if {[catch { get_property UID $t } _ val]} continue
    if {$val eq $uid} { set tgt $t; break }
}
if {$tgt eq ""} {
    puts "ERROR: no hw_target with UID='$uid'"; exit 1
}
puts "OK: matched target [get_property NAME $tgt]"

puts "INFO: current_hw_target..."
if {[catch { current_hw_target $tgt } err]} {
    puts "ERROR at current_hw_target: $err"; exit 1
} else { puts "OK: current_hw_target" }

puts "INFO: open_hw_target..."
if {[catch { open_hw_target } err]} {
    puts "ERROR at open_hw_target: $err"; exit 1
} else { puts "OK: open_hw_target" }

# --- 6) Locate & program the FPGA device ---
puts "INFO: get_hw_devices..."
if {[catch { set devs [get_hw_devices -of_objects $tgt] } err]} {
    puts "ERROR at get_hw_devices: $err"; exit 1
}
set fpga_dev ""
foreach d $devs {
    if {[catch { get_property PART_NAME $d } _ part]} continue
    if {[string tolower $part] contains "xczu47dr-1ffvg1517"} {
        set fpga_dev $d; break
    }
}
if {$fpga_dev eq ""} {
    puts "ERROR: no XCZU47DR-1FFVG1517 device found"; exit 1
}
puts "OK: FPGA device = [get_property NAME $fpga_dev]"

if {![file exists $bitfile]} {
    puts "ERROR: bitfile '$bitfile' not found"; exit 1
}
puts "INFO: programming bitstream..."
if {[catch { program_hw_devices -hw_devices $fpga_dev -bitfile $bitfile } err]} {
    puts "ERROR at program_hw_devices: $err"; exit 1
} else { puts "OK: program_hw_devices" }

# --- 7) IBERT test loop ---
foreach linkName $links {
    puts ""
    puts "INFO: get_hw_sio_links -filter '$linkName'..."
    if {[catch { set sl [get_hw_sio_links -of_objects $fpga_dev -filter $linkName] } err]} {
        puts "ERROR at get_hw_sio_links($linkName): $err"; continue
    }
    if {[llength $sl] == 0} {
        puts "ERROR: no link '$linkName'"; continue
    }
    set sio [lindex $sl 0]
    puts "OK: link object = $sio"

    puts "INFO: waiting for ≥ $threshold_bits bits..."
    while {1} {
        if {[catch { set bits [get_property RX_RECEIVED_BIT_COUNT $sio] } err]} {
            puts "ERROR reading RX_RECEIVED_BIT_COUNT: $err"; break
        }
        if {$bits >= $threshold_bits} { break }
        busySleep 500
    }
    if {[catch { set ber [get_property RX_BER $sio] } err]} {
        puts "WARN: reading RX_BER failed: $err"; set ber "N/A"
    }
    puts "RESULT: link=$linkName  bits=$bits  BER=$ber"
}

# --- 8) Cleanup ---
puts ""
puts "INFO: close_hw_manager..."
catch { close_hw_manager }
puts "QC run complete."
exit 0
