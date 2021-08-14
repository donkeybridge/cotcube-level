#!/usr/bin/env ruby

require_relative '../lib/cotcube-level'
include Cotcube::Helpers

DEBUG = false
DATE  = ARGV[0] || '2021-08-08'
t0 = Time.now

show    = lambda {|x| puts "#{x.values_at(*%i[ datetime high low volume oi x ])}" }
measure = lambda {|x| puts "\nMeasured #{(Time.now - t0).to_f.round(2)}: ".colorize(:light_yellow) +  x + "\n\n" } 

base = JSON.parse(File.read('/var/cotcube/bardata/a6u21_example_days.json')).map{|x| x.transform_keys(&:to_sym)}.map{|x| x[:datetime] = DateTime.parse(x[:datetime]); x}

measure.call "Got base containing #{base.size} records, with following bounderies: "

show.call base.first
puts "..."
show.call base[-2] 
show.call  base[-1]
puts "\n\nretrieving stencil for last base"

stencil = Cotcube::Level::Stencil.new interval: :daily, swap_type: :full, contract: 'A6U21', date: '2021-08-13'

measure.call "Got stencil containing #{stencil.base.size} records with following boundaries: "
show.call stencil.base.first
puts "..."
show.call stencil.zero
puts "..."
show.call stencil.base[-2]
show.call stencil.base[-1]

stencil =  Cotcube::Level::Stencil.new interval: :daily, swap_type: :full, contract: 'A6U21', date: DATE
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

upper_swaps = Cotcube::Level.triangulate(base: base, deviation: 2, side: :upper, contract: 'A6U21', debug: DEBUG)
lower_swaps = Cotcube::Level.triangulate(base: base, deviation: 2, side: :lower, contract: 'A6U21', debug: DEBUG)

puts 'Upper swaps: '
upper_swaps.each_with_index {|x,i| puts "#{i}\t#{x[:members].map{|z| "#{z.values_at(*%i[date high x dx ])}" }.join("\n\t")}"}
puts 'Lower swaps: '
lower_swaps.each_with_index {|x,i| puts "#{i}\t#{x[:members].map{|z| "#{z.values_at(*%i[date low  x dx ])}" }.join("\n\t")}"} 
measure.call( 'finished searching swaps' )
