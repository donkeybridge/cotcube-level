#!/usr/bin/env ruby

require 'cotcube-bardata'
require 'cotcube-indicators'
require_relative '../lib/cotcube-level.rb'
CcI = Cotcube::Indicators

def exit_with_error(err)
  msg = { error: 1, message: "#{err}" }
  p msg.to_json
  exit 1
end

contract   = ARGV[0].nil? ? nil : ARGV[0].upcase
if contract.nil?
  exit_with_error('No contract given')
end

sym = Cotcube::Helpers.get_id_set(symbol: contract[..1])
continuous = %w[currencies interest indices].include? sym[:type]

# TODO: apply daylight time pimped diff to all relevant datetimes in series
timediff = if %w[ NYBOT NYMEX ].include? sym[:exchange]
             5.hours
           elsif %w[ DTB ].include? sym[:exchane]
             1.hour
           else
             6.hours
           end

stencil   = nil
swaps     = [] 
istencil  = nil
iswaps    = []
collector_threads = [] 

collector_threads << Thread.new do
  stencil = Cotcube::Level::EOD_Stencil.new( interval: :daily, swap_type: :full)
  swaps = Cotcube::Level::load_swaps(interval: (continuous ? :continuous : :daily), swap_type: :full, contract: contract, quiet: true).
    select{|z| not(z[:empty]) and
           not(z[:ignored]) and
           not(z[:exceeded].presence ? (z[:exceeded] < DateTime.now - 3.days) : false)
  }.map{|z|
    swap = { digest: z[:digest], color: z[:color], interval: z[:interval] }
    swap[:exceeded] = z[:exceeded] unless z[:exceeded].nil?
    swap[:members] = z[:members].map{|z1| { x: z1[:datetime], y: (z[:side] == :upper ? z1[:high] : z1[:low]) } }
    swap[:members] << { x: stencil.zero[:datetime].to_datetime, y: stencil.use(with: z, sym: sym)[:current_value].round(sym[:format][3].to_i) }
    swap
  }
end

collector_threads << Thread.new do 
  istencil = Cotcube::Level::Intraday_Stencil.new( interval: 30.minutes, swap_type: :full, asset: :full, weeks: 8)
  iswaps   = Cotcube::Level::load_swaps(interval: 30.minutes, swap_type: :full, contract: contract, sym: sym).
    select{|z| not(z[:empty]) and
           not(z[:ignored]) and
           not(z[:exceeded].presence ? (z[:exceeded] < DateTime.now - 1.days) : false)
  }.map {|z| 
    swap = { digest: z[:digest], color: z[:color], interval: z[:interval] } 
    swap[:exceeded] = z[:exceeded] unless z[:exceeded].nil?
    swap[:members] = z[:members].map{|z1| { x: z1[:datetime], y: (z[:side] == :upper ? z1[:high] : z1[:low]) } }
    swap[:members] << { x: istencil.zero[:datetime].to_datetime, y: istencil.use(with: z, sym: sym)[:current_value].round(sym[:format][3].to_i) } if swap[:exceeded].nil?
    swap
  }
end

collector_threads.each(&:join)

pkg = {
       daily:  swaps,
       intra: iswaps,
}

puts pkg.to_json
