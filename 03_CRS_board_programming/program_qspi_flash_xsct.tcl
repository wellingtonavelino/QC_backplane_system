# Connect to remote hw_server on Vivado Lab machine
# replace IP address to the machine where the board is connected
connect -url tcp:10.10.10.82:3121

# Wait a bit to ensure connection
after 1000

# List targets and select Cortex-A53 #0
puts "Available targets:"
targets
set target_id [lindex [targets -filter {name =~ "APU.*Cortex-A53 #0"}] 0]
puts "Selecting target ID: $target_id"
targets $target_id

# Reset processor
puts "Resetting processor..."
rst -processor

# Download and run FSBL
puts "Downloading FSBL..."
dow fsbl.elf
puts "Running FSBL..."
con

# Wait for FSBL to init QSPI
after 3000

# Program BOOT.bin into QSPI flash
puts "Programming BOOT.bin..."
program_flash -f BOOT.bin -flash_type qspi-x8-dual_parallel -offset 0

puts "Done programming flash!"
exit
