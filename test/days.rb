#!/usr/bin/env ruby

require_relative '../lib/cotcube-level'
include Cotcube::Helpers

DEBUG = false
DATE  = ARGV[0] || '2021-08-08'
t0 = Time.now

show    = lambda {|x| puts "#{x.values_at(*%i[ datetime high low volume oi x ])}" }
measure = lambda {|x| puts "\nMeasured #{(Time.now - t0).to_f.round(2)}: ".colorize(:light_yellow) +  x + "\n\n" } 

contract = 'A6U21'
base = JSON.parse(File.read("/var/cotcube/level/testing/#{contract}_example_days.json")).map{|x| x.transform_keys(&:to_sym)}.map{|x| x[:datetime] = DateTime.parse(x[:datetime]); x}

measure.call "Got base containing #{base.size} records, with following bounderies: "

show.call base.first
puts "..."
show.call base[-2] 
show.call  base[-1]
puts "\n\nretrieving stencil for last base"

stencil = Cotcube::Level::EOD_Stencil.new interval: :daily, swap_type: :full, contract: contract, date: '2021-08-13'

measure.call "Got stencil containing #{stencil.base.size} records with following boundaries: "
show.call stencil.base.first
puts "..."
show.call stencil.zero
puts "..."
show.call stencil.base[-2]
show.call stencil.base[-1]

stencil =  Cotcube::Level::EOD_Stencil.new interval: :daily, swap_type: :full, contract: contract, date: DATE
measure.call "Got stencil again"

show.call stencil.base.first
puts "..."
show.call stencil.zero
puts "..."
show.call stencil.base[-2]
show.call stencil.base[-1]


stencil.apply to: base
zero =  base.select{|b| b[:x].zero? } rescue [] 
raise "WARNING: Base should contain 1 zero, but contains #{zero.size}." unless zero.size == 1
measure.call "Applied stencil on base"
show.call base.first
puts "..."
show.call zero.first
puts "..."
show.call base[-2]
show.call base[-1]

swaps = Cotcube::Helpers.parallelize( %i[ upper lower ], processes: 2) {|side| 
  Cotcube::Level.triangulate(base: base, deviation: 2, side: side, contract: contract, debug: DEBUG, interval: :daily)
}.flatten(1)

sym = Cotcube::Helpers.get_id_set(contract: contract)
puts "#{sym}"

measure.call( 'finished searching swaps' )

present_swaps = lambda do |sw|
  Cotcube::Level.puts_swaps(sw, format: sym[:format])
end

current_date = Date.new(2021,6,1)

while current_date < Date.new(2021,8,15)
  current_date += 1
  next if [0,6].include? current_date.wday
  p current_date
  stencil =  Cotcube::Level::EOD_Stencil.new interval: :daily, swap_type: :full, contract: contract, date: current_date
  stencil.apply to: base
  swaps = Cotcube::Helpers.parallelize( %i[ upper lower ], processes: 2) {|side| 
    Cotcube::Level.triangulate(base: base, deviation: 2, side: side, contract: contract, debug: DEBUG, swap_type: :full, interval: :daily)
  }.flatten(1)
  present_swaps.call(swaps)
  #STDIN.gets unless lower_swaps.empty? and upper_swaps.empty?
end

__END__
