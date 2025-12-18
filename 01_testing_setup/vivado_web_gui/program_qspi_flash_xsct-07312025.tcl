# Connect to hw_server
puts "Connecting to hw_server..."
connect -url tcp:127.0.0.1:3121
after 1000

# Select known powered-on board (assumed to be target 12)
puts "Selecting default target 12 (Cortex-A53 #0)..."
target 12

# Get script directory and construct file paths
set script_path [file normalize [info script]]
set script_dir [file dirname $script_path]
set fsbl_path [file join $script_dir "fsbl.elf"]
set boot_bin_path [file join $script_dir "BOOT.bin"]

puts "📥 FSBL path: $fsbl_path"
puts "📦 BOOT.BIN path: $boot_bin_path"

# Build and run the shell command
#set flash_cmd "program_flash -fsbl \"$fsbl_path\" -f \"$boot_bin_path\" -offset 0 -flash_type qspi_single"
set flash_cmd "program_flash -fsbl fsbl.elf -f BOOT.bin -offset 0 -flash_type qspi-x8-dual_parallel"
#set flash_cmd "program_flash -f \"$boot_bin_path\" -offset 0 -flash_type qspi-x8-dual_parallel -fsbl \"$fsbl_path\" -blank_check -verify"

puts "⚡ Running shell command:\n$flash_cmd"

# Execute flash tool
set result [exec {*}$flash_cmd]

# Show output
puts "📄 Output from program_flash:"
puts $result

puts "🔁 Issuing power-on reset..."
rst -por
puts "✅ Reset done. The board should now boot from QSPI."

puts "✅ Flash programming finished."
exit
