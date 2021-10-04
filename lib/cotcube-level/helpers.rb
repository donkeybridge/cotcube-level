# frozen_string_literal: true

module Cotcube
  module Level

    # 3 simple, self-explaining helpers
    def rad2deg(deg); deg * 180 / Math::PI; end
    def deg2rad(rad); rad * Math::PI / 180; end
    def shear_to_deg(base:, deg:); shear_to_rad(base: base, rad: deg2rad(deg)); end

    # the actual shearing takes place here. please not that shifting of :x takes place
    #     by setting the new :x as :dx. so if :dx is found, it is used, otherwise :x
    def shear_to_rad(base: , rad:)
      tan = Math.tan(rad)
      base.map { |member|
        # separating lines for easier debugging
        member[:yy] =
          member[:y] +
          (member[:dx].nil? ? member[:x] : member[:dx]) * tan
        member
      }
    end

    # human readable output
    # please note the format must be given, that should be taken from :sym
    def member_to_human(member,side: ,format:, daily: false)
      high = (side == :upper)
      "#{                         member[:datetime].strftime("%a, %Y-%m-%d#{daily ? "" :" %I:%M%p"}")
        }  x: #{format '%-4d',    member[:x]
        } dx: #{format '%-8.3f', (member[:dx].nil? ? member[:x] : member[:dx].round(3))
            } #{high ? "high" : "low"
           }: #{format format,    member[high ? :high : :low]
         } i: #{(format '%4d',    member[:i]) unless member[:i].nil?
         } d: #{format '%6.2f',   member[:dev] unless member[:dev].nil?
            } #{member[:near].nil? ? '' : "near: #{member[:near]}"
         }"
    end

    # human readable output
    # format: e.g. sym[:format]
    # short:  print one line / less verbose
    # notice: add this to output as well
    def puts_swap(swap, format: , short: true, notice: nil, hash: 2)
      return if swap[:empty]
      daily =  %i[ continuous daily ].include?(swap[:interval].to_sym)
      datetime_format = daily ? '%Y-%m-%d' : '%Y-%m-%d %H:%M'
      high = swap[:side] == :high
      ohlc = high ? :high : :low
      if short
        puts (hash ? "#{swap[:digest][..hash]}    ".colorize(:light_white) : '') +
             "S: #{swap[:side]
            } L: #{   format '%4d', swap[:length]
            } R: #{   format '%4d', swap[:rating]
            } D: #{   format '%4d', swap[:depth]
            } P: #{   format '%10s', (format '%5.2f', swap[:ppi])
            }   F: #{ format format, swap[:members].last[ ohlc ]
            }   S: #{ swap[:members].first[:datetime].strftime(datetime_format)
            } - #{    swap[:members].last[:datetime].strftime(datetime_format)
            }#{       format('%20s', (swap[:exceeded] ? "  XXX: #{swap[:exceeded].strftime(datetime_format)}" : ''))
            }#{"  NOTE: #{notice}" unless notice.nil?}".colorize(swap[:color] || :white )
      else
        puts "side: #{swap[:side] }\tlen: #{swap[:length]}  \trating: #{swap[:rating]}".colorize(swap[:color] || :white )
        puts "diff: #{swap[:ticks]}\tdif: #{swap[:diff].round(7)}\tdepth: #{swap[:depth]}".colorize(swap[:color] || :white )
        puts "tpi:  #{swap[:tpi]  }\tppi: #{swap[:ppi]}".colorize(swap[:color] || :white )
        puts "NOTE: #{notice}".colorize(:light_white) unless notice.nil?
        swap[:members].each {|x| puts member_to_human(x, side: swap[:side], format: format, daily: daily) }
      end
    end

    # create a standardized name for the cache files
    # and, on-the-fly, create these files plus their directory
    def get_jsonl_name(interval:, swap_type:, contract:, sym: nil)
      raise "Interval #{interval } is not supported, please choose from #{INTERVALS}" unless INTERVALS.include? interval
      raise "Swaptype #{swap_type} is not supported, please choose from #{SWAPTYPES}" unless SWAPTYPES.include? swap_type
      sym ||= Cotcube::Helpers.get_id_set(contract: contract)
      root = '/var/cotcube/level'
      dir     = "#{root}/#{sym[:id]}"
      symlink = "#{root}/#{sym[:symbol]}"
      `mkdir -p #{dir}`         unless File.exist?(dir)
      `ln -s #{dir} #{symlink}` unless File.exist?(symlink)
      file = "#{dir}/#{contract}_#{interval.to_s}_#{swap_type.to_s}.jsonl"
      `touch #{file}`
      file
    end

    # the name says it all.
    # just note the addition of a digest, that serves to check whether same swap has been yet saved
    # to the cache.
    #
    # there are actually 3 types of information, that are saved here:
    # 1. a swap
    # 2. an 'empty' information, referring to an interval that has been processed but no swaps were found
    # 3. an 'exceeded' information, referring to another swap, that has been exceeded
    #
    def save_swaps(swaps, interval:, swap_type:, contract:, sym: nil, quiet: false)
      file = get_jsonl_name(interval: interval, swap_type: swap_type, contract: contract, sym: sym)
      swaps = [ swaps ] unless swaps.is_a? Array
      swaps.each do |swap|
        raise "Illegal swap info: Must contain keys :datetime, :side... #{swap}" unless (%i[ datetime side ] - swap.keys).empty?
        %i[ interval swap_type ].map {|key| swap.delete(key) }
        sorted_keys = [ :datetime, :side ] + ( swap.keys - [ :datetime, :side ])
        swap_json = swap.slice(*sorted_keys).to_json
        digest = Digest::SHA256.hexdigest swap_json
        res = `cat #{file} | grep '"digest":"#{digest}"'`.strip
        unless res.empty?
          puts "Cannot save swap, it is already in #{file}:".light_red unless quiet
          p swap unless quiet
        else
          swap[:digest] = digest
          sorted_keys += %i[digest]
          File.open(file, 'a+'){|f| f.write(swap.slice(*sorted_keys).to_json + "\n") }
        end
      end
    end

    # loading of swaps is also straight forward
    # it takes few more efforts to normalize the values to their expected format
    def load_swaps(interval:, swap_type:, contract:, sym: nil, datetime: nil, recent: false)
      file = get_jsonl_name(interval: interval, swap_type: swap_type, contract: contract, sym: sym)
      jsonl = File.read(file)
      data = jsonl.
        each_line.
        map do |x|
        JSON.parse(x).
          deep_transform_keys(&:to_sym).
          tap do |sw|
            sw[:datetime] = DateTime.parse(sw[:datetime]) rescue nil
            (sw[:exceeded] = DateTime.parse(sw[:exceeded]) rescue nil) if sw[:exceeded]
            sw[:interval] = interval
            sw[:swap_type] = swap_type
            sw[:contract] = contract
            %i[ side ].each {|key| sw[key] = sw[key].to_sym rescue false }
            unless sw[:empty] or sw[:exceeded]
              sw[:color]    = sw[:color].to_sym
              sw[:members].map{|mem| mem[:datetime] = DateTime.parse(mem[:datetime]) }
            end
        end
      end
      # assign exceedance data to actual swaps
      data.select{|swap| swap[:exceeded] }.each do |exc|
        swap = data.find{|ref| ref[:digest] == exc[:ref]}
        raise RuntimeError, "Inconsistent history for '#{exc}'. Origin not found." if swap.nil?
        swap[:exceeded] = exc[:exceeded]
      end
      # do not return bare exceedance information
      data.reject!{|swap| swap[:exceeded] and swap[:members].nil? }
      # do not return swaps that are found 'later'
      data.reject!{|swap| swap[:datetime] > datetime } unless datetime.nil?
      # do not return exceeded swaps, that are exceeded in the past
      recent  = 7.days  if recent.is_a? TrueClass
      recent += 5.hours if recent
      data.reject!{|swap| swap[:exceeded] and swap[:exceeded] < datetime - (recent ? recent : 0) } unless datetime.nil?
      # remove exceedance information that is found 'later'
      data.map{|swap| swap.delete(:exceeded) if swap[:exceeded] and swap[:exceeded] > datetime} unless datetime.nil?
      data
    end

    # :swaps is an array of swaps
    # :zero  is the current interval (ohlc)
    # :stencil is the according current stencil (eod or intraday)
    def check_exceedance(swaps:, zero:, stencil:, contract:, sym:, debug: false)
      swaps.map do |swap|
        # swaps cannot exceed the day they are found (or if they are found in the future)
        next if  swap[:datetime] >= zero[:datetime] or swap[:empty]
        update = stencil.use with: swap, sym: sym, zero: zero
        if update[:exceeded]
          to_save = {
            datetime: zero[:datetime],
            ref:      swap[:digest],
            side:     swap[:side],
            exceeded: update[:exceeded]
          }
          save_swaps to_save, interval: swap[:interval], swap_type: swap[:swap_type], contract: contract, sym: sym, quiet: (not debug)
          swap[:exceeded] = update[:exceeded]
        end
        %i[ current_change current_value current_diff current_dist ].map{|key| swap[key] = update[key] }
        swap
      end.compact
    end

  end
end

