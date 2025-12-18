# This script assumes fixed Vivado/Vitis locations

# === Step 1: Get serial numbers from Vivado ===
puts "🔍 Getting USB serial numbers from Vivado..."
exec C:/Xilinx/Vivado/2022.2/bin/vivado.bat -mode tcl -nolog -nojournal -notrace << {
    open_hw
    connect_hw_server
    foreach c [get_hw_targets] {
        set ser [get_property JTAG_SERIAL_NUMBER $c]
        puts "$c SERIAL=$ser"
    }
    exit
}

# === Step 2: Get target IDs from XSCT ===
puts "\n🔍 Getting target IDs from XSCT..."
#exec C:\Xilinx\Vitis\2022.2\settings64.bat
exec C:/Xilinx/Vitis/2022.2/bin/xsct.bat << {
    connect -url tcp:127.0.0.1:3121
    puts "=== XSCT Targets ==="
    targets
    exit
}
