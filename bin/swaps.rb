#!/usr/bin/env ruby

require_relative '../lib/cotcube-level.rb'

HELP = <<HEREDOC
swaps.rb: Display current eod swaps.
    > USAGE: swaps.rb <contract> [json]
    > contract      a contract known to the system
    > json          switch to toggle json output instead of human readable
HEREDOC
if ARGV.empty?
  puts HELP
  exit
end


contract   = ARGV[0].nil? ? nil : ARGV[0].upcase
json       = ARGV.include? 'json'

sym     = Cotcube::Helpers.get_id_set(contract: contract) rescue "ERROR: Could not determine contract '#{contract}'."

if sym.is_a? String; puts sym; puts HELP; exit 1; end

swaps   = Cotcube::Level::load_swaps(interval: :daily, swap_type: :full, contract: contract, quiet: true).
            select{|swap| not(swap[:empty]) and 
                       not(swap[:ignored]) and 
                       not(swap[:exceeded].presence ? (swap[:exceeded] < DateTime.now - 2.days) : false)
            }
stencil = Cotcube::Level::EOD_Stencil.new( interval: :daily, swap_type: :full)
swaps.map!{|swap| stencil.use with: swap, sym: sym}
if json
  puts swaps.to_json
else
  puts '<none>' if swaps.empty?
  swaps.each {|swap| 
    notice = if swap[:exceeded]
               "EXCEEDED #{swap[:exceeded].strftime('%Y-%m-%d')}"
             elsif swap[:ignored] 
               'IGNORED'
             else
               "Current: #{format sym[:format], swap[:current_value]}"
             end
    Cotcube::Level.puts_swap(swap, format: sym[:format], notice: notice)
  }
end
