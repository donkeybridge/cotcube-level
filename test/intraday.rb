#!/usr/bin/env ruby

require_relative '../lib/cotcube-level'
include Cotcube::Helpers
DEBUG = false
t0 = Time.now
show    = lambda {|x| puts "#{x.values_at(*%i[ datetime high low volume x ])}" }
measure = lambda {|x| puts "\nMeasured #{(Time.now - t0).to_f.round(2)}: ".colorize(:light_yellow) +  x + "\n\n" }
contract = 'A6U21'
sym = Cotcube::Helpers.get_id_set(contract: contract)

base = JSON.parse(File.read("/var/cotcube/level/testing/#{contract}_example_intraday.json")).map{|x| x.transform_keys(&:to_sym)}.map{|x| x[:datetime] = DateTime.parse(x[:datetime]); x}

measure.call "Got base containing #{base.size} records, with following bounderies: "


show.call base.first
puts "..."
show.call base[-2]
show.call  base[-1]

# testing shiftsets

s1 = Cotcube::Level::Intraday_Stencil.shiftset(asset: 'A6')
p s1

s2 = Cotcube::Level::Intraday_Stencil.shiftset(asset: 'GC')
p s2

p base[-13]
stencil = Cotcube::Level::Intraday_Stencil.new asset: sym[:symbol], interval: 30.minutes, weeks: 21, datetime: base[-13][:datetime], base: base, type: :full

measure.call "Got stencil containing #{stencil.base.size} records with following boundaries: "
3.times{|i| p stencil.base[i] }
puts "..."
3.times{|i| p stencil.base[-(i+1)]}

stencil = Cotcube::Level::Intraday_Stencil.new asset: sym[:symbol], interval: 30.minutes, weeks: 21, datetime: base[-13][:datetime], base: base, type: :full
# TODO: resulting base is not zeroed on base[-13] but on base.last

measure.call "Got stencil again. "

stencil.apply to: base, type: :full

measure.call "Applied stencil to base "
3.times{|i| p base[i] }
puts "..."
3.times{|i| p base[-(3 - i)]}

#contract = 'HEV21'
#sym      = Cotcube::Helpers.get_id_set contract: contract
#base = JSON.parse(File.read("/var/cotcube/level/testing/#{contract}_example_intraday.json")).map{|x| x.transform_keys(&:to_sym)}.map{|x| x[:datetime] = DateTime.parse(x[:datetime]); x}
stencil = Cotcube::Level::Intraday_Stencil.new asset: :full, interval: 30.minutes, weeks: 21, datetime: base[-13][:datetime], base: base, type: :full
measure.call "Applied stencil to base "
3.times{|i| p stencil.base[i] }
puts "..."
puts stencil.zero
puts "..."
3.times{|i| p stencil.base[-3+i]}


swaps = Cotcube::Helpers.parallelize(%i[ upper lower]){|side| Cotcube::Level.triangulate(base: stencil.base, deviation: 2, side: side, contract: contract, debug: DEBUG, interval: :halfs) }

sym = Cotcube::Helpers.get_id_set(contract: contract)
puts "#{sym}"

measure.call( 'finished searching swaps' )

present_swaps = lambda do |sw|
  Cotcube::Level.puts_swaps(sw, format: sym[:format])
end

index = -800
while index <= -1
  current_datetime = base[index][:datetime] + 31.minutes
  puts "#{index}:\t#{current_datetime}"
  stencil = Cotcube::Level::Intraday_Stencil.new asset: :full, interval: 30.minutes, weeks: 21, datetime: current_datetime,  base: base, type: :full
  swaps = Cotcube::Helpers.parallelize(%i[ upper lower ]){|side|
    Cotcube::Level.triangulate(base: stencil.base, deviation: 4, side: side, contract: contract, debug: DEBUG, swap_type: :full, interval: :halfs, min_rating: 5, min_length: 20)
  }
  present_swaps.call(swaps.flatten(1))
  STDIN.gets unless swaps.flatten(1).compact.size.zero?
  index += 1
end


