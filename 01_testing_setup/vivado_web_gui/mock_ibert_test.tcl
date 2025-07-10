# mock_ibert_test.tcl
puts "Connecting to hardware..."
after 1000
puts "Connected to mock hardware."

puts "Initializing iBERT..."
after 1000
puts "iBERT link training started."
after 2000
puts "Link training complete."

puts "Running BER test..."
after 1000

# Simulate progress
for {set i 1} {$i <= 5} {incr i} {
    puts "Testing channel ch$i: measuring..."
    after 1000
    set ber [expr {double(rand()) * 1e-6}]
    set errors [expr {int(rand() * 10000)}]
    puts "Result ch$i: BER=$ber, Errors=$errors"
}

puts "Test complete. Generating report..."
after 1000
puts "All results saved."

# Simulated data export (optional)
puts "BEGIN_RESULTS"
for {set i 0} {$i < 3} {incr i} {
    set ch "ch$i"
    set ber [expr {double(rand()) * 1e-6}]
    set err [expr {int(rand() * 10000)}]
    puts "$ch,$ber,$err"
}
puts "END_RESULTS"

puts "Mock test finished."
