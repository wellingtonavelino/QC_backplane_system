# Open hardware manager and connect once at script start
open_hw
connect_hw_server

# Function to program a single board
proc program_board {bitfile target_index} {
    set targets [get_hw_targets *]
    set chosen_target [lindex $targets $target_index]
    puts "📡 Opening JTAG target: $chosen_target"
    catch { open_hw_target $chosen_target }
    refresh_hw_device [get_hw_devices]

    foreach dev [get_hw_devices] {
        catch { open_hw_device $dev }
        set dev_name [get_property NAME $dev]
        set dev_part [get_property PART $dev]
        puts "✨ Found device: $dev_name ($dev_part)"
        if {![string match -nocase "*dap*" $dev_name] && [string match -nocase "xc*" $dev_part]} {
            puts "🚀 Programming FPGA: $dev_name"
            set_property PROGRAM.FILE $bitfile $dev
            program_hw_devices $dev
            after 1000
            set all_props [list_property $dev]
            if {"PROGRAM.HW_STATUS" in $all_props} {
                set status [get_property PROGRAM.HW_STATUS $dev]
                puts "✅ $dev_name programmed. Status: $status"
            } else {
                puts "✅ $dev_name programmed."
            }
        } else {
            puts "⚡ Skipping non-FPGA device: $dev_name"
        }
    }
    close_hw_target $chosen_target
}

# Function to set up links for a board
proc setup_links {target_index suffixes paramSets} {
    set targets [get_hw_targets *]
    set chosen_target [lindex $targets $target_index]
    puts "📡 Opening JTAG target for link setup: $chosen_target"
    catch { open_hw_target $chosen_target }
    refresh_hw_device [get_hw_devices]
    foreach dev [get_hw_devices] { catch { open_hw_device $dev } }

    set iberts [get_hw_sio_iberts]
    if {[llength $iberts] == 0} {
        puts "⛔ No IBERT found."
        close_hw_target $chosen_target
        return
    }
    set ibert [lindex $iberts 0]
    puts "✅ Found IBERT core: $ibert"

    proc find_hw_sio_link_by_suffix {suffix type} {
        set list [expr {$type eq "tx" ? [get_hw_sio_txs] : [get_hw_sio_rxs]}]
        foreach l $list {
            if {[string match "*$suffix" [get_property NAME $l]]} { return $l }
        }
        return ""
    }

    set all_links {}
    set idx 0
    foreach pair $suffixes {
        set tx [find_hw_sio_link_by_suffix [lindex $pair 0] "tx"]
        set rx [find_hw_sio_link_by_suffix [lindex $pair 1] "rx"]
        if {$tx ne "" && $rx ne ""} {
            set linkObj [create_hw_sio_link -description "Link${target_index}_$idx" $tx $rx]
            lappend all_links $linkObj
            incr idx
        } else {
            puts "⚠️ Could not find link for: $pair"
        }
    }
    set link_group [create_hw_sio_linkgroup -description "Group${target_index}" $all_links]

    set links_list [get_hw_sio_links -of_objects $link_group]
    for {set i 0} {$i < [llength $links_list]} {incr i} {
        set linkObj [lindex $links_list $i]
        foreach {prop val} [lindex $paramSets $i] {
            set_property $prop $val $linkObj
        }
        commit_hw_sio -non_blocking $linkObj
    }
    close_hw_target $chosen_target
}

# Function to test BER for a board
proc test_ber {target_index suffixes} {
    set targets [get_hw_targets *]
    set chosen_target [lindex $targets $target_index]
    puts "📡 Opening JTAG target for BER test: $chosen_target"
    catch { open_hw_target $chosen_target }
    refresh_hw_device [get_hw_devices]
    foreach dev [get_hw_devices] { catch { open_hw_device $dev } }

    proc find_hw_sio_link_by_suffix {suffix type} {
        set list [expr {$type eq "tx" ? [get_hw_sio_txs] : [get_hw_sio_rxs]}]
        foreach l $list {
            if {[string match "*$suffix" [get_property NAME $l]]} { return $l }
        }
        return ""
    }

    # Re-create links for testing
    set all_links {}
    foreach pair $suffixes {
        set tx [find_hw_sio_link_by_suffix [lindex $pair 0] "tx"]
        set rx [find_hw_sio_link_by_suffix [lindex $pair 1] "rx"]
        if {$tx ne "" && $rx ne ""} {
            set linkObj [create_hw_sio_link -description "TestLink${target_index}" $tx $rx]
            lappend all_links $linkObj
        } else {
            puts "⚠️ Could not find both ends for link: $pair"
        }
    }
    set link_group [create_hw_sio_linkgroup -description "TestGroup${target_index}" $all_links]

    # Reset error counters on individual links
    set link_members [get_hw_sio_links -of_objects $link_group]
    set_property LOGIC.MGT_ERRCNT_RESET_CTRL 1 $link_members
    commit_hw_sio -non_blocking $link_members
    set_property LOGIC.MGT_ERRCNT_RESET_CTRL 0 $link_members
    commit_hw_sio -non_blocking $link_members
    after 5000

    puts "⏳ Waiting for 1Gbit+ on all links..."
    set ready 0
    while {!$ready} {
        set ready 1
        foreach lnk $link_members {
            if {[get_property RX_RECEIVED_BIT_COUNT $lnk] < 1000000000} { set ready 0 }
        }
        if {!$ready} { after 1000 }
    }
    puts "✅ Bit threshold reached."

    # Collect BER
    set results {}
    foreach lnk $link_members {
        set name [get_property NAME $lnk]
        set ber [get_property RX_BER $lnk]
        lappend results [list $name $ber]
    }

    close_hw_target $chosen_target
    return $results
}

# -------------- Main Script --------------
set boards {
    {0 {
        {"Quad_130/MGT_X0Y14/TX" "Quad_131/MGT_X0Y18/RX"}
		{"Quad_131/MGT_X0Y19/TX" "Quad_131/MGT_X0Y17/RX"}
    } {
        {TXPRE {3.90 dB (01111)} TXPOST {3.73 dB (01110)} TXDIFFSWING {930 mV (10111)}}
        {TXPRE {1.87 dB (01000)} TXPOST {2.98 dB (01011)} TXDIFFSWING {780 mV (10000)}}
    }}
    {1 {
        {"Quad_131/MGT_X0Y18/TX" "Quad_130/MGT_X0Y14/RX"}
        {"Quad_131/MGT_X0Y17/TX" "Quad_131/MGT_X0Y19/RX"}
    } {
        {TXPRE {3.66 dB (01110)} TXPOST {1.91 dB (01000)} TXDIFFSWING {1040 mV (11111)}}
        {TXPRE {1.87 dB (01000)} TXPOST {2.98 dB (01011)} TXDIFFSWING {780 mV (10000)}}
    }}
}
foreach b $boards {
    set idx [lindex $b 0]
    set sif [lindex $b 1]
    set params [lindex $b 2]
    puts "\n🔧 Setting up Board $idx"
    program_board "G:/IBERT_CRS_Boards/example_ibert_ultrascale_gty_0.bit" $idx
    setup_links $idx $sif $params
}
set all_results {}
foreach b $boards {
    set idx [lindex $b 0]
    set sif [lindex $b 1]
    puts "\n🧪 Testing Board $idx BER"
    lappend all_results [list $idx [test_ber $idx $sif]]
}
puts "\n📊 Final BER Results"
foreach res $all_results {
    set idx [lindex $res 0]
    set vals [lindex $res 1]
    puts "-- Board $idx --"
    foreach pair $vals {
        puts "[lindex $pair 0] → RX_BER: [lindex $pair 1]"
    }
}
puts "\n🏁 All boards complete!"


# Set 31-bit PRBS
