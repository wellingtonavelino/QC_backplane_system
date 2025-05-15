# -------------------------------------------------------------------------------------------------------------- #
# --------------------------------------------- 25Gbps Links Testing  ------------------------------------------ #
# -------------------------------------------------------------------------------------------------------------- #


# 1. Connect to the hardware server
open_hw_manager
connect_hw_server
open_hw_target
refresh_hw_device [get_hw_devices]

# 1.1 Get all connected devices
set devices [get_hw_devices]

foreach dev $devices {
    puts "Device: $dev"
    puts "  DISPLAY_NAME: [get_property NAME $dev]"
    puts "  PART: [get_property PART $dev]"
    puts "  PROGRAM.FILE property: [get_property PROGRAM.FILE $dev]"
}

# 2. Program the FPGA with the iBERT bitstream
# set my_device [lindex [get_hw_devices] 0]  ;# Select first detected FPGA
# set slot1_device [lindex [get_hw_devices] 1]  ;# Select second detected FPGA
# set slot2_device [lindex [get_hw_devices] 2]  ;# Select third detected FPGA
# set slot3_device [lindex [get_hw_devices] 3]  ;# Select fourth detected FPGA

# Iterate over devices
foreach dev $devices {

	set result [catch {
        set_property PROGRAM.FILE "G:/IBERT_CRS_Boards/example_ibert_ultrascale_gty_0.bit" $dev
        program_hw_devices $dev
    } errMsg]
	
	if {$result == 0} {
        puts "Successfully programmed: $dev"
    } else {
        puts "Skipping non-programmable or failed device: $dev"
        puts "   Reason: $errMsg"
    }
	
    # set prog_file_property [get_property PROGRAM.FILE $dev]
	
	# if {![catch {set_property PROGRAM.FILE "G:/IBERT_CRS_Boards/example_ibert_ultrascale_gty_0.bit" $dev} result]}
	# {
		# puts "Programming device: $dev"
		# #set_property PROGRAM.FILE G:/IBERT_CRS_Boards/example_ibert_ultrascale_gty_0.bit $dev
		# program_hw_devices $dev
		# }
	# else
	# {
		# puts "Skipping non-programmable device: $dev"
	# }
}

# # SLOT_0
# #set_property PROGRAM.FILE C:/Wellington/iBERT_testing/TCL_scripts/example_ibert_ultrascale_gty_0.bit $my_device
# set_property PROGRAM.FILE G:/IBERT_CRS_Boards/example_ibert_ultrascale_gty_0.bit $my_device
# program_hw_devices $my_device
# refresh_hw_device $my_device

# # SLOT_1
# #set_property PROGRAM.FILE C:/Wellington/iBERT_testing/TCL_scripts/example_ibert_ultrascale_gty_0.bit $my_device
# set_property PROGRAM.FILE G:/IBERT_CRS_Boards/example_ibert_ultrascale_gty_0.bit $slot1_device
# program_hw_devices $slot1_device
# refresh_hw_device $slot1_device

# # SLOT_2
# #set_property PROGRAM.FILE C:/Wellington/iBERT_testing/TCL_scripts/example_ibert_ultrascale_gty_0.bit $my_device
# set_property PROGRAM.FILE G:/IBERT_CRS_Boards/example_ibert_ultrascale_gty_0.bit $slot2_device
# program_hw_devices $slot2_device
# refresh_hw_device $slot2_device

# # SLOT_3
# #set_property PROGRAM.FILE C:/Wellington/iBERT_testing/TCL_scripts/example_ibert_ultrascale_gty_0.bit $my_device
# set_property PROGRAM.FILE G:/IBERT_CRS_Boards/example_ibert_ultrascale_gty_0.bit $slot3_device
# program_hw_devices $slot3_device
# refresh_hw_device $slot3_device

# 3.1 Check available IBERT cores
get_hw_sio_iberts

# Select iBERT core
set ibert [get_hw_sio_iberts]
# open_hw_sio_ibert $ibert
# commit_hw_sio_ibert $ibert
#set_property CONTROL.ENABLE 1 $ibert

if {$ibert eq ""} {
    puts "Error: No IBERT core found. Ensure the FPGA is programmed with IBERT."
    exit
}
refresh_hw_device [lindex [get_hw_devices] 0]
refresh_hw_sio $ibert

puts "Checking available IBERT links..."
detect_hw_sio_links

set links [get_hw_sio_links]

if {$links eq ""} {
    puts "Error: No hw_sio_links detected. Ensure IBERT is configured correctly."
} else {
    puts "Available links: $links"
}
# 3.2 Forcing Links. Set them manually
set xil_newLinks [list]

# ------------------- ONBOARD LINKS ---------------- #
# SLOT0 --> SLOT1
set tx_path_01 "$ibert/Quad_131/MGT_X0Y18/TX"
set rx_path_01 "$ibert/Quad_131/MGT_X0Y18/RX"
# SLOT1 --> SLOT0
set tx_path_10 "$ibert/Quad_130/MGT_X0Y14/TX"
set rx_path_10 "$ibert/Quad_131/MGT_X0Y18/RX"
# SLOT0 --> SLOT2
set tx_path_02 "$ibert/Quad_131/MGT_X0Y16/TX"
set rx_path_02 "$ibert/Quad_131/MGT_X0Y18/RX"
# SLOT2 --> SLOT0
set tx_path_20 "$ibert/Quad_131/MGT_X0Y18/TX"
set rx_path_20 "$ibert/Quad_131/MGT_X0Y16/RX"
# SLOT0 --> SLOT3
set tx_path_03 "$ibert/Quad_130/MGT_X0Y14/TX"
set rx_path_03 "$ibert/Quad_131/MGT_X0Y18/RX"
# SLOT3 --> SLOT0
set tx_path_30 "$ibert/Quad_131/MGT_X0Y18/TX"
set rx_path_30 "$ibert/Quad_130/MGT_X0Y14/RX"

# SLOT1 --> SLOT2
set tx_path_12 "$ibert/Quad_131/MGT_X0Y16/TX"
set rx_path_12 "$ibert/Quad_131/MGT_X0Y16/RX"
# SLOT2 --> SLOT1
set tx_path_21 "$ibert/Quad_131/MGT_X0Y16/TX"
set rx_path_21 "$ibert/Quad_131/MGT_X0Y16/RX"
# SLOT1 --> SLOT3
set tx_path_13 "$ibert/Quad_131/MGT_X0Y18/TX"
set rx_path_13 "$ibert/Quad_131/MGT_X0Y16/RX"
# SLOT3 --> SLOT1
set tx_path_31 "$ibert/Quad_131/MGT_X0Y16/TX"
set rx_path_31 "$ibert/Quad_130/MGT_X0Y14/RX"

# SLOT2 --> SLOT3
set tx_path_23 "$ibert/Quad_130/MGT_X0Y14/TX"
set rx_path_23 "$ibert/Quad_130/MGT_X0Y14/RX"
# SLOT3 --> SLOT2
set tx_path_32 "$ibert/Quad_130/MGT_X0Y14/TX"
set rx_path_32 "$ibert/Quad_130/MGT_X0Y14/RX"



# ------------------- QSFP LINKS --------------- #
# BOARD0 --> BOARD1 (slot0)
set tx_path_b01 "$ibert/Quad_131/MGT_X0Y19/TX"
set rx_path_b01 "$ibert/Quad_130/MGT_X0Y15/RX"

# BOARD0 --> BOARD2 (slot0)
set tx_path_b02 "$ibert/Quad_131/MGT_X0Y17/TX"
set rx_path_b02 "$ibert/Quad_131/MGT_X0Y19/RX"

# BOARD0 --> BOARD3 (slot0)
set tx_path_b03 "$ibert/Quad_130/MGT_X0Y15/TX"
set rx_path_b03 "$ibert/Quad_131/MGT_X0Y17/RX"

set tx_path2 "$ibert/Quad_131/MGT_X0Y17/TX"
set rx_path2 "$ibert/Quad_130/MGT_X0Y15/RX"

if {$links eq ""} {
    puts "Error: No hw_sio_links detected. Creating them manuallly."
	set xil_newLink [create_hw_sio_link -description {Link 0} [lindex [get_hw_sio_txs $tx_path] 0] [lindex [get_hw_sio_rxs $rx_path] 0]]
	lappend xil_newLinks $xil_newLink
	set xil_newLink [create_hw_sio_link -description {Link 1} [lindex [get_hw_sio_txs $tx_path2] 0] [lindex [get_hw_sio_rxs $rx_path2] 0]]
	lappend xil_newLinks $xil_newLink
} else {
    # puts "Available links: $links"
	set links [get_hw_sio_links]
}
set xil_newLinkGroup [create_hw_sio_linkgroup -description {Link Group 0} [get_hw_sio_links $xil_newLinks]]
#unset xil_newLinks


# set xil_newLink [create_hw_sio_link -description {Link 0} [lindex [get_hw_sio_txs localhost:3121/xilinx_tcf/Xilinx/00035A/0_1_0_0/IBERT/Quad_130/MGT_X0Y15/TX] 0] [lindex [get_hw_sio_rxs localhost:3121/xilinx_tcf/Xilinx/00035A/0_1_0_0/IBERT/Quad_131/MGT_X0Y17/RX] 0] ]
# lappend xil_newLinks $xil_newLink
# set xil_newLink [create_hw_sio_link -description {Link 1} [lindex [get_hw_sio_txs localhost:3121/xilinx_tcf/Xilinx/00035A/0_1_0_0/IBERT/Quad_131/MGT_X0Y17/TX] 0] [lindex [get_hw_sio_rxs localhost:3121/xilinx_tcf/Xilinx/00035A/0_1_0_0/IBERT/Quad_130/MGT_X0Y15/RX] 0] ]
# lappend xil_newLinks $xil_newLink
# set xil_newLinkGroup [create_hw_sio_linkgroup -description {Link Group 0} [get_hw_sio_links $xil_newLinks]]
# unset xil_newLinks

# Define parameter ranges
set precursors {0 5 10}  ;# Adjust based on your needs
set precursor_values { 0.01 dB (00000);
					   0.20 dB (00001);
					   0.32 dB (00010); 
					   0.73 dB (00011); 
					   0.81 dB (00100);
					   1.17 dB (00101); 
					   1.30 dB (00110); 
					   1.74 dB (00111);
}
set postcursors {0 5 10}
set diffswings {0 1}  ;# 4-bit TXDIFFCTRL range (0-15 in steps of 1 or 3)

# Variable to store the best configuration
set best_ber 1.0   ;# Start with worst-case BER
set best_params ""
set threshold 100000000000  ; # 10 Terabits (10^13 bits)

#set_property TXPRE {0.32 dB (00010)} [get_hw_sio_links -of_objects [get_hw_sio_linkgroups {Link_Group_0}]]
#commit_hw_sio -non_blocking [get_hw_sio_links -of_objects [get_hw_sio_linkgroups {Link_Group_0}]]

set_property TX_PATTERN {PRBS 31-bit} [get_hw_sio_links -of_objects [get_hw_sio_linkgroups {Link_Group_0}]]
commit_hw_sio -non_blocking [get_hw_sio_links -of_objects [get_hw_sio_linkgroups {Link_Group_0}]]

set_property RX_PATTERN {PRBS 31-bit} [get_hw_sio_links -of_objects [get_hw_sio_linkgroups {Link_Group_0}]]
commit_hw_sio -non_blocking [get_hw_sio_links -of_objects [get_hw_sio_linkgroups {Link_Group_0}]]

after 2000  ;# 2 second delay (adjust as needed)

# Reseting the system
set_property LOGIC.MGT_ERRCNT_RESET_CTRL 1 [get_hw_sio_links -of_objects [get_hw_sio_linkgroups {Link_Group_0}]]
commit_hw_sio -non_blocking [get_hw_sio_links -of_objects [get_hw_sio_linkgroups {Link_Group_0}]]
set_property LOGIC.MGT_ERRCNT_RESET_CTRL 0 [get_hw_sio_links -of_objects [get_hw_sio_linkgroups {Link_Group_0}]]
commit_hw_sio -non_blocking [get_hw_sio_links -of_objects [get_hw_sio_linkgroups {Link_Group_0}]]

#set txs [get_hw_sio_links [lindex $links 0]]
set x 0 ;

# --------------------------- Running tests until 10Tb --------------------------------- #
while {$x<10} {
	if {$links eq ""} {
		set tested_bits [get_property RX_RECEIVED_BIT_COUNT  [get_hw_sio_links [lindex $xil_newLinks 0]]]
		puts $tested_bits
	} else {
		set tested_bits [get_property RX_RECEIVED_BIT_COUNT  [get_hw_sio_links [lindex $links 0]]]
		puts $tested_bits
	}
	
	if {$tested_bits >= $threshold } {
        puts "Threshold of 10Tb reached. Stopping IBERT test."
        break
    }
}
# ------------------------------------------------------------------------------------ #


set ber 0
if {$links eq ""}
{
	set ber [get_property RX_BER [lindex $xil_newLinks 0]]
	} else {
	set ber [get_property RX_BER $links]
	}

puts "BER: $ber"

set xil_newScan [create_hw_sio_scan -description {Scan 0} 2d_full_eye  [lindex $xil_newLinks 0]]]
set_property HORIZONTAL_INCREMENT {1} [get_hw_sio_scans $xil_newScan]
set_property VERTICAL_INCREMENT {1} [get_hw_sio_scans $xil_newScan]
set_property DWELL_BER 1e-7 [get_hw_sio_scans $xil_newScan]
run_hw_sio_scan [get_hw_sio_scans $xil_newScan]

set open_area_value [get_property OPEN_AREA $xil_newScan]
puts "OPEN AREA: $open_area_value"

#remove_hw_sio_scan [get_hw_sio_scans {SCAN_0}]

# # Loop through all parameter combinations
foreach precursor $precursors {
    foreach postcursor $postcursors {
        foreach diffswing $diffswings {
            # Apply settings to the GT link
			set_property TXPRE $precursor $txs/TX
            #set_property TX_PRECURSOR $precursor [lindex $links 0]
            #set_property TX_POSTCURSOR $postcursor [lindex $links 0]
            #set_property TXDIFFCTRL $diffswing [lindex $links 0]
            
            # Commit the changes
            commit_hw_sio $ibert
            
            # Wait for the link to stabilize
            after 1000  ;# 1 second delay (adjust as needed)
            
            # Read BER from the link
            #set ber [get_property BER $links]
			set open_area_value [get_property OPEN_AREA $xil_newScan]
            
            # Print results
            #puts "Tx_Pre: $precursor, Tx_Post: $postcursor, Tx_Diff: $diffswing -> BER: $ber"
			puts "OPEN AREA: $open_area_value"
            
            # Store the best setting
            if {$ber < $best_ber} {
                set best_ber $ber
                set best_params "Tx_Pre: $precursor, Tx_Post: $postcursor, Tx_Diff: $diffswing"
            }
        }
    }
}

# # Print the best result
# puts "Best settings found: $best_params with BER: $best_ber"

#commit_hw_sio $ibert

# set gt_links [list [get_hw_sio_links Quad_130/MGT_X0Y15TX] [get_hw_sio_links Quad_130/MGT_X0Y15RX]]



# Close hardware connection
# close_hw_sio_ibert $ibert


#report_property [lindex $links 0]
#report_property [lindex $xil_newLinks 0]

disconnect_hw_server

