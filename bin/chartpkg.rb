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

output     = true

sym = Cotcube::Helpers.get_id_set(symbol: contract[..1])
# TODO: apply daylight time pimped diff to all relevant datetimes in series
timediff = if %w[ NYBOT NYMEX ].include? sym[:exchange]
             5.hours
           elsif %w[ DTB ].include? sym[:exchane]
             1.hour
           else
             6.hours
           end

continuous = %w[currencies interest indices].include? sym[:type]
intraday   = ARGV.include? 'intraday'
interval   = intraday ? 30.minutes : 1.day
ema_period = 50

indicators = {
  ema_high:    CcI.ema(key: :high,    length: ema_period,  smoothing: 2),
  ema_low:     CcI.ema(key: :low,     length: ema_period,  smoothing: 2)
}

intrabase = []
dailybase = [] 
stencil   = nil
swaps     = [] 
istencil  = nil
iswaps    = []
collector_threads = [] 

collector_threads << Thread.new do 
  begin
    intrabase = JSON.parse(Cotcube::Helpers::DataClient.new.get_historical(contract: contract, interval: :min30, duration: '3_W' ), symbolize_names: true)[:base].
      map{ |z| 
      z[:datetime] = DateTime.parse(z[:time])
      %i[time created_at wap trades].each{|k| z.delete(k)}
      z
    } if intraday
  rescue
    intrabase = [] 
  end
end

collector_threads << Thread.new do
  dailybase = if continuous 
                Cotcube::Bardata.continuous(symbol: contract[..1], indicators: indicators)[-300..].
                  map{ |z| 
                  z[:datetime] = DateTime.parse(z[:date])
                  z.delete(:contracts)
                  z
                }
              else
                Cotcube::Bardata.provide_daily(contract: contract, indicators: indicators)[-300..]
              end
end

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

base = intraday ? intrabase : dailybase
base.select!{|z| z[:high]}

if intraday
  daily_bar   = { date: '1900-01-01' }
  base.each do |bar|
    date      = (bar[:datetime] + 2.hours).strftime('%Y-%m-%d')
    daily_bar = (dailybase.find{|z| z[:date] == date}.presence || daily_bar) unless daily_bar[:date] == date 
    bar[:ema_high] = daily_bar[:ema_high]
    bar[:ema_low]  = daily_bar[:ema_low]
  end
end

scaleBreaks = [] 
brb  = intraday ? istencil.base : stencil.base
brb.each_with_index.map{|z,i| 
  next if i.zero?
  if brb[i][:datetime] - brb[i-1][:datetime] > (intraday ? 1 : 1.day) and brb[i][:datetime] > base.first[:datetime] and brb[i-1][:datetime] < base.last[:datetime]
    scaleBreaks << { startValue: brb[i-1][:datetime] + 0.5 * interval, endValue: brb[i][:datetime] - 0.5 * interval }
  end
} unless base.empty?

pkg = {sym:    sym, 
       base:   base,
       swaps:  swaps,
       iswaps: iswaps,
       breaks: scaleBreaks
}

puts pkg.to_json if output
