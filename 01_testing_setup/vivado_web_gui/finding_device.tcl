set target_serial "000026A"

connect -url tcp:127.0.0.1:3121

puts "🔍 Scanning hardware targets for serial match: $target_serial"

set found 0
set all_targets [targets]

foreach t $all_targets {
    set t_str "$t"
	puts "→ $t"
    if {[string match "*$target_serial*" $t_str]} {
        puts "✅ Match found!"
        puts "→ $t_str"
        set found 1
    }
}

if {!$found} {
    puts "❌ No matching target with serial $target_serial found."
}
