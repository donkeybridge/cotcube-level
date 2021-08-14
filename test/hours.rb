#!/usr/bin/env ruby

require_relative '../lib/cotcube-level'

base = JSON.parse(File.read('/var/cotcube/bardata/a6u21_example_hours.json'))

puts "Got base containing #{base.size} records, with following bounderies: "
p base.first
p "..."
p base[-2] 
p base[-1]


