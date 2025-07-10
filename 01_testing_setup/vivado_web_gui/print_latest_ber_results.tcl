# ---------------------------------------------
# print_latest_ber_results.tcl
# Show latest BER results
# ---------------------------------------------

set log_file "ibert_qc_ber.log"

if {![file exists $log_file]} {
    puts "ERROR: File '$log_file' not found."
    exit 1
}

set fh [open $log_file r]
set lines [split [read $fh] "\n"]
close $fh

# Find all indicces whre block starts
set starts {}
for {set i 0} {$i < [llength $lines]} {incr i} {
    if {[string match "IBERT QC BER Log*" [lindex $lines $i]]} {
        lappend starts $i
    }
}

if {[llength $starts] == 0} {
    puts "No block found in log."
    exit 0
}

# Extract last block
set start_idx [lindex $starts end]
set block [lrange $lines $start_idx end]

# Find header and data lines 
set header_line ""
set data_lines {}

foreach line $block {
    if {[string match "Serial,*" $line]} {
        set header_line $line
        continue
    }
    if {[string match "===*" $line] || $line eq ""} {
        break
    }
    if {$header_line ne ""} {
        lappend data_lines $line
    }
}

if {$header_line eq "" || [llength $data_lines] == 0} {
    puts "Block found, but no data available."
    exit 0
}

# Display formatted data
puts "\n Lastest BER Results:"
puts "---------------------------"
puts $header_line
foreach line $data_lines {
    puts $line
}
puts "---------------------------"
puts "Shown Lines: [llength $data_lines]"
