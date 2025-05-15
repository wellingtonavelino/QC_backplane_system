# Open hardware manager and connect
open_hw
connect_hw_server

# Enumerate all JTAG cable targets
set targets [get_hw_targets *]

# Open each target individually
foreach target $targets {
    puts "\n📡 Opening JTAG target: $target"
    open_hw_target $target

    # Refresh devices under this cable
    refresh_hw_device [get_hw_devices]

    # Now iterate over the devices on this target (typically 2: arm_dap + FPGA)
    foreach dev [get_hw_devices] {
        set dev_name [get_property NAME $dev]
        set partname [get_property PART $dev]

        puts "🔍 Found device: $dev_name ($partname)"

        # Try to open the device (in case it’s not yet active)
        catch { open_hw_device $dev }

        # Only try to program FPGA-type devices
        set result [catch {
            set_property PROGRAM.FILE "G:/IBERT_CRS_Boards/example_ibert_ultrascale_gty_0.bit" $dev
            program_hw_devices $dev
            after 1000

            set status [get_property PROGRAM.HW_STATUS $dev]
            puts "✅ $dev_name programmed. Status: $status"
        } errMsg]
		after 1000

        if {$result != 0} {
            puts "⛔ Could not program $dev_name — $errMsg"
        }
		after 1000
    }

    # Optional: Close the current target to release it
    close_hw_target $target
}

puts "🏁 Done programming all boards!"

# Step 1: Reconnect to specific hardware target
# Safe reconnect logic
if {[llength [get_hw_servers]] == 0} {
    open_hw
}
if {[llength [get_hw_targets]] == 0} {
    connect_hw_server
}

catch { open_hw }
catch { connect_hw_server }

set targets [get_hw_targets *]

# Choose the first one (you can modify this to select by name or index)
set chosen_target [lindex $targets 0]
open_hw_target $chosen_target
refresh_hw_device [get_hw_devices]

# Step 2: Open the FPGA device
foreach dev [get_hw_devices] {
    catch { open_hw_device $dev }
}

# Step 3: Get IBERT core (should be visible now) - Discover and select IBERT cores
set iberts [get_hw_sio_iberts]
if {[llength $iberts] == 0} {
    puts "⛔ No hw_sio_ibert found. Is the IBERT core included in the bitstream?"
    return
}

set ibert [lindex $iberts 0]
puts "✅ Found IBERT: $ibert"

# # Define links explicitly
# set rx_paths {
    # "Quad_131/MGT_X0Y18/RX"
    # "Quad_130/MGT_X0Y14/RX"
# }
# set tx_paths {
    # "Quad_130/MGT_X0Y14/TX"
    # "Quad_131/MGT_X0Y18/TX"
# }

# # Create links from exact objects
# set links {}
# for {set i 0} {$i < [llength $rx_paths]} {incr i} {
    # set rx [get_hw_sio_links -of_objects $ibert -filter "NAME == \"[lindex $rx_paths $i]\""]
    # set tx [get_hw_sio_links -of_objects $ibert -filter "NAME == \"[lindex $tx_paths $i]\""]
    # set link [create_hw_sio_link -hw_sio_tx $tx -hw_sio_rx $rx]
    # lappend links $link
    # puts "✅ Created link: $link"
# }

# Function to find a hw_sio_rx or hw_sio_tx link by known suffix
proc find_hw_sio_link_by_suffix {suffix type} {
    set all_links ""
    if {$type eq "rx"} {
        set all_links [get_hw_sio_rxs]
    } elseif {$type eq "tx"} {
        set all_links [get_hw_sio_txs]
    } else {
        error "Unknown type '$type', expected 'rx' or 'tx'"
    }

    foreach l $all_links {
        set name [get_property NAME $l]
        if {[string match "*$suffix" $name]} {
            return $l
        }
    }

    return ""
}


set suffixes {
    {"Quad_131/MGT_X0Y18/TX" "Quad_130/MGT_X0Y14/RX"}  # slot 0 --> slot 3
    {"Quad_130/MGT_X0Y14/TX" "Quad_131/MGT_X0Y18/RX"}  # slot 3 --> slot 0
	{"Quad_131/MGT_X0Y19/TX" "Quad_131/MGT_X0Y17/RX"}  # slot 0 - board 1 --> board 2
	{"Quad_131/MGT_X0Y17/TX" "Quad_131/MGT_X0Y19/RX"}  # slot 0 - board 2 --> board 1
}

set all_links {}
set index 0
foreach pair $suffixes {
    set tx_suffix [lindex $pair 0]
    set rx_suffix [lindex $pair 1]
    set tx [find_hw_sio_link_by_suffix $tx_suffix "tx"]
    set rx [find_hw_sio_link_by_suffix $rx_suffix "rx"]

    if {[string length $tx] > 0 && [string length $rx] > 0} {
        set link [create_hw_sio_link -description "Link $index" $tx $rx]
        lappend all_links $link
        incr index
    } else {
        puts "⚠️ Could not find TX or RX for: $tx_suffix / $rx_suffix"
    }
}

# Define your parameter-sets as a list of prop/value pairs
# (one entry per link, in the same order as `get_hw_sio_links` returns them)
set paramSets {
    {TXPRE {3.90 dB (01111)} TXPOST {3.73 dB (01110)} TXDIFFSWING {930 mV (10111)}}
    {TXPRE {1.87 dB (01000)} TXPOST {2.98 dB (01011)} TXDIFFSWING {780 mV (10000)}}
    {TXPRE {3.66 dB (01110)} TXPOST {1.91 dB (01000)} TXDIFFSWING {1040 mV (11111)}}
	{TXPRE {1.87 dB (01000)} TXPOST {2.98 dB (01011)} TXDIFFSWING {780 mV (10000)}}
    ;# …add as many as you have links
}


# Step 6: Group the links
set link_group [create_hw_sio_linkgroup -description "MyGroup" $all_links]
puts "🔗 Created link group: $link_group"

# Sanity check: ensure you have exactly as many parameter-sets as links
if {[llength $link_group] != [llength $paramSets]} {
    puts "Link count ([llength $link_group]) != paramSet count ([llength $paramSets])"
}

# 1) Get all the hw_sio_link objects in that group
set group_links [get_hw_sio_links -of_objects $link_group]

# Loop by index, apply each set to the corresponding link
for {set i 0} {$i < [llength $group_links]} {incr i} {
    set lnk   [lindex $group_links   $i]
    set pset  [lindex $paramSets $i]

    puts "⚙️ Configuring link [get_property NAME $lnk] (index $i)…"
    foreach {prop val} $pset {
        set_property $prop $val $lnk
    }

    # Commit non‐blocking so you don’t stall the loop
    commit_hw_sio -non_blocking $lnk

    # Optional settle time
    after 500
}

puts "✅ All links individually configured with their parameter sets."

# 2) Reset the MGT error counters on every link
puts "🔄 Resetting error counters for all links…"
set_property LOGIC.MGT_ERRCNT_RESET_CTRL 1 $group_links
commit_hw_sio -non_blocking $group_links
set_property LOGIC.MGT_ERRCNT_RESET_CTRL 0 $group_links
commit_hw_sio -non_blocking $group_links
puts "✅ Error counters reset."

# 3) Configure TX pattern to PRBS-31
puts "⚙️ Setting TX_PATTERN to PRBS 31-bit on all links…"
set_property TX_PATTERN {PRBS 31-bit} $group_links
# set_property TXPRE {3.90 dB (01111)} $group_links
# set_property TXPOST {3.73 dB (01110)} $group_links
# set_property TXDIFFSWING {930 mV (10111)} $group_links
commit_hw_sio -non_blocking $group_links
puts "✅ TX_PATTERN set to PRBS-31."

after 2000

puts "⚙️ Setting RX_PATTERN to PRBS 31-bit on all links…"
set_property RX_PATTERN {PRBS 31-bit} $group_links
commit_hw_sio -non_blocking $group_links
puts "✅ TX_PATTERN set to PRBS-31."

after 5000

# Step 7: Reset all links (not the group)
puts "🔄 Resetting all links (CONTROL.RESET)..."
foreach link $all_links {
    catch {
        set_property CONTROL.RESET TRUE $link
    }
}
puts "✅ All links reset using CONTROL.RESET"
after 5000

for {set iter 1} {$iter <= 3} {incr iter} {
    puts "🔄 Reset iteration $iter of 3..."

    # pulse the error-counter reset
    set_property LOGIC.MGT_ERRCNT_RESET_CTRL 1 $group_links
    commit_hw_sio -non_blocking $group_links
    set_property LOGIC.MGT_ERRCNT_RESET_CTRL 0 $group_links
    commit_hw_sio -non_blocking $group_links

    puts "⏳ Waiting 2 seconds before next reset…"
    after 2000
}

puts "✅ Completed 3 resets of all links."

after 2000

# Step 8: Wait for sufficient bits transmitted
puts "⏳ Waiting for links to transmit more than 1 Gbit..."
set ready 0
while {!$ready} {
    set ready 1
    foreach link $all_links {
        set bits [get_property RX_RECEIVED_BIT_COUNT  [get_hw_sio_links [lindex $link 0]]]
        puts "🧪 $link → TESTED_BITS: $bits"
        if {$bits < 10000000000} {
            set ready 0
        }
    }
    if {!$ready} {
        after 1000
    }
}
puts "✅ All links passed 1Gbit threshold!"

# Step 9: Collect and log RX_BER for each link
puts "\n📊 Final BER values:"
foreach link $all_links {
    set ber [get_property RX_BER $link]
    puts "🔗 $link → RX_BER: $ber"
}
