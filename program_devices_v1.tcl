# ======================================================
# program_by_uid_with_url.tcl
# ------------------------------------------------------
# Usage: vivado -mode tcl -source program_by_uid_with_url.tcl
#
# Expects a config file "fpga_uids_urls.txt" in the same folder:
#   Each non-empty line is:
#      <Vendor>/<Serial>,<hw_server_URL>
#   e.g.
#     Digilent/210203327463A,localhost:3121
#     Xilinx/000025A,192.168.1.20:3121
#     MyVendor/0012345,localhost:3141
#
# The script will:
#  1. connect to each hw_server URL
#  2. find the hw_target whose UID property matches Vendor/Serial
#  3. make it current, open it, and then grab the device
#  4. (optionally) program or test that device
# ======================================================

# --- User parameters ---
set cfg_file   "fpga_uids_urls.txt"
set max_boards 4
# Uncomment & set if you want to program .bit files named by serial:
# set bitfile_dir "/path/to/bitstreams"

# --- Start Vivado HW Manager ---
puts ""
puts "INFO: Starting Hardware Manager..."
if {[catch { open_hw_manager } err]} {
    puts "ERROR: cannot open hw manager: $err"
    exit 1
}

# --- Read config ---
if {![file exists $cfg_file]} {
    puts "ERROR: Config file '$cfg_file' not found."
    exit 1
}
set fh    [open $cfg_file r]
set lines [split [read $fh] "\n"]
close $fh

set count 0
foreach line $lines {
    if {$count >= $max_boards} { break }
    set entry [string trim $line]
    if {$entry eq "" || [string index $entry 0] == "#"} { continue }

    # parse UID and URL
    set parts [split $entry ","]
    if {[llength $parts] < 2} {
        puts "WARN: skipping malformed line: $entry"
        continue
    }
    set wantUID [string trim [lindex $parts 0]]
    set url     [string trim [lindex $parts 1]]

    puts ""
    puts "INFO: Board # [expr {$count+1}] → UID=$wantUID  URL=$url"

    # 1) connect to that hw_server
    if {[catch { connect_hw_server -url $url } connErr]} {
        puts "  ERROR: connect_hw_server failed: $connErr"
        continue
    }

    # 2) locate the hw_target by UID (vendor/serial)
    #    use a wildcard match on the NAME, then double-check the UID property
    set candidates [get_hw_targets *$wantUID*]
    set tgt ""
    foreach t $candidates {
        if {[catch { get_property UID $t } e uidVal]==0 && $uidVal eq $wantUID} {
            set tgt $t
            break
        }
    }
    if {$tgt eq ""} {
        puts "  ERROR: no hw_target with UID='$wantUID' found"
        continue
    }
    puts "  OK: found target [get_property NAME $tgt] (UID matches)"

    # 3) make it current and open it
    if {[catch { current_hw_target $tgt } curErr]} {
        puts "  ERROR: current_hw_target failed: $curErr"
        continue
    }
    if {[catch { open_hw_target } openErr]} {
        puts "  ERROR: open_hw_target failed: $openErr"
        continue
    }

    # 4) grab the FPGA device(s)
    set devs [get_hw_devices -of_objects $tgt]
    if {[llength $devs] == 0} {
        puts "  ERROR: no FPGA devices under this target"
        continue
    }
    set dev [lindex $devs 0]
    puts "  OK: found device: [get_property NAME $dev] (Part: [get_property PART_NAME $dev])"

    # ----- OPTIONAL: program a bitstream named <Serial>.bit -----
    # regexp {.*/(.+)$} $wantUID -> tmp
    # set serial [lindex [split $tmp "/"] 1]
    # set bitfile [file join $bitfile_dir "${serial}.bit"]
    # if {[file exists $bitfile]} {
    #     puts "  INFO: programming $bitfile..."
    #     if {[catch { program_hw_devices -hw_devices $dev -bitfile $bitfile } progErr]} {
    #         puts "    ERROR: program failed: $progErr"
    #     } else {
    #         puts "    OK: programming complete"
    #     }
    # } else {
    #     puts "  WARN: bitfile not found: $bitfile"
    # }

    incr count
}

puts ""
puts "INFO: done. processed $count board(s)."
catch { close_hw_manager }
exit 0
