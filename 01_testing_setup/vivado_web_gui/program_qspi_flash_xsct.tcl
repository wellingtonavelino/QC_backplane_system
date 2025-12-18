# ================================
# QSPI Flash Programming TCL Script
# ================================
# Python will inject:
#     set target_id <number>
# at the top of this file before running

# If not injected, default to target 12
if {![info exists target_id]} {
    set target_id 12
}

puts "🔌 Connecting to hw_server..."
connect -url tcp:127.0.0.1:3121
after 1000

puts "🎯 Selecting target $target_id..."
target $target_id
after 500

# Get script directory and construct file paths
set script_path [file normalize [info script]]
set script_dir [file dirname $script_path]
set fsbl_path [file join $script_dir "fsbl.elf"]
set boot_bin_path [file join $script_dir "BOOT.bin"]

puts "📥 FSBL path: $fsbl_path"
puts "📦 BOOT.BIN path: $boot_bin_path"

# Build the flash programming command
set flash_cmd "program_flash -fsbl \"$fsbl_path\" -f \"$boot_bin_path\" -offset 0 -flash_type qspi-x8-dual_parallel"

puts "⚡ Running flash programming command:"
puts "$flash_cmd"

# Run the flash programming command
set result [catch {exec {*}$flash_cmd} flash_output]
if {$result != 0} {
    puts "❌ Flash programming failed:"
    puts $flash_output
    exit 1
} else {
    puts "✅ Flash programming completed successfully."
}

# Optional: Reset board after programming
puts "🔁 Power-on reset..."
rst -por
puts "✅ Reset complete. Board should now boot from QSPI."

exit
