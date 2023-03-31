#!/usr/bin/env ruby

require_relative '../lib/cotcube-level.rb'

def log(whatever, data)
  File.open('/tmp/level_posting.log', 'a+'){|f| f << "#{DateTime.now.strftime('%Y%m%d-%H%M%S : ')}#{format '%8s   :',whatever.to_s}#{data}\n" }
end

def params_to_hash(params)
  params
    .split('&')
    .map{|z| z.split('=') }
    .map{|z| 
      z[1] = case
             when z[1].to_i.to_s == z[1]
               z[1].to_i
             when z[1].to_f.to_s == z[1]
               z[1].to_f
             when z[1].downcase == 'true'
               true
             when z[1].downcase == 'false'
               false
             when %w[nil null undefined].include?(z[1].downcase)
               nil
             else
               z[1]
             end
      z
    }.to_h
    .transform_keys(&:to_sym)
end

raw = ARGV.join(' ')
hsh = params_to_hash(raw) 

log 'Starting',''
begin
  sym   = Cotcube::Helpers.get_id_set(contract: hsh[:contract]) 
  interval = hsh[:intra] ? 1800 : %[ indices currencies interest].include?(sym[:type]) ? :continuous : :daily
  digest = hsh[:digest].split('x').last.split('_').last ## Must be fixed to use only valid digests
  swaps = Cotcube::Level.load_swaps(interval: interval, swap_type: :full, contract: hsh[:contract], digest: digest, quiet: true)
  case swaps.size
  when 0 #none found
    msg = { error: 1, message: "No swaps found for digest #{digest} on contract #{hsh[:contract]} / #{interval}." } 
  when 1 # good
    Cotcube::Level.mark_ignored(swap: swaps.first, sym: sym)
    swaps = Cotcube::Level.load_swaps(interval: interval, swap_type: :full, contract: hsh[:contract], digest: digest, quiet: true)
    if swaps.empty?
      msg = { error: 0, message: "Swap with digest #{digest} on #{hsh[:contract]} / #{interval} is marked to be ignored."}
    else
      msg = { error: 1, message: "Something went wrong while marking swap to be ignored:  #{digest} on #{hsh[:contract]} / #{interval} " }
    end
  else 
    msg = { error: 2, message: "Too many swaps found for digest #{digest}, consider using a more precise digest on #{hsh[:contract]} / #{interval}." }
  end
  log 'msg', msg
  puts msg.to_json
rescue => e
  log 'err', e.full_message
  msg = { error: 503, message: "Something went wrong while processing '#{raw}'."}.to_json
  puts msg.to_json
end

