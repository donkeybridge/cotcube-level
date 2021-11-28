#!/usr/bin/env ruby

require_relative '../lib/cotcube-level.rb'

HELP = <<HEREDOC
Display current intraday swaps.
    > USAGE: iswaps.rb <contract> [json]
    > contract      a contract known to the system
    > json          switch to toggle json output instead of human readable
HEREDOC
if ARGV.empty?
  puts HELP
  exit
end

contract   = ARGV[0].nil? ? nil : ARGV[0].upcase
json       = ARGV.include? 'json'

sym        = Cotcube::Helpers.get_id_set(contract: contract) rescue "Could not determine contract #{contract}"
if sym.is_a? Sring; puts sym; puts HELP; exit 1; end

swaps      = Cotcube::Level::load_swaps(interval: 30.minutes, swap_type: :full, contract: contract, sym: sym).
               select{|swap| not(swap[:empty]) and 
                             not(swap[:ignored]) and 
                             not(swap[:exceeded].presence ? (swap[:exceeded] < DateTime.now - 2.days) : false)
               }
stencil = Cotcube::Level::Intraday_Stencil.new( interval: 30.minutes, swap_type: :full, asset: contract[..1])
swaps.map!{|swap| stencil.use with: swap, sym: sym}

if json
  puts swaps.to_json
else
  puts '<none>' if swaps.empty?
  swaps.each {|swap|
    notice = if swap[:exceeded]
               "EXCEEDED #{swap[:exceeded]}"
             elsif swap[:ignored]
               'IGNORED'
             else
               "Current: #{format sym[:format], swap[:current_value]}"
             end
    Cotcube::Level.puts_swap(swap, format: sym[:format], notice: notice)
  }
end

