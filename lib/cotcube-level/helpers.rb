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
    def member_to_human(member,side: ,format:, daily: false, tws: false)
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
    def puts_swap(swap, format: , short: true, notice: nil, hash: 3, tws: false)
      return '' if swap[:empty]

      # if presenting swaps from json, the datetimes need to be parsed first
      swap[:datetime] = DateTime.parse(swap[:datetime]) if swap[:datetime].is_a? String
      swap[:exceeded] = DateTime.parse(swap[:exceeded]) if swap[:exceeded].is_a? String
      swap[:ignored]  = DateTime.parse(swap[:ignored])  if swap[:ignored ].is_a? String
      swap[:side]     = swap[:side].to_sym
      swap[:members].each do |mem|
        mem[:datetime] = DateTime.parse(mem[:datetime]) if mem[:datetime].is_a? String
      end

      # TODO: create config-entry to contain 1.hour -- set of contracts ; 7.hours -- set of contracts [...]
      #       instead of hard-coding in here
      # TODO: add also to :member_to_human
      #       then commit
      if tws
        case swap[:contract][0...2]
        when *%w[ GC SI PL PA HG NG CL HO RB ] 
          delta_datetime = 1.hour
        when *%w[ GG DX ]
          delta_datetime = 7.hours
        else
          delta_datetime = 0
        end
      else
        delta_datetime = 0 
      end
      daily =  %i[ continuous daily ].include?(swap[:interval].to_sym) rescue false
      datetime_format = daily ? '%Y-%m-%d' : '%Y-%m-%d %I:%M %p'
      high = swap[:side] == :high
      ohlc = high ? :high : :low
      if notice.nil? and swap[:exceeded]
        notice = "exceeded #{(swap[:exceeded] + delta_datetime).strftime(datetime_format)}"
      end
      if swap[:ignored] 
        notice += "  IGNORED"
      end
      if short
        res ="#{format '%7s', swap[:digest][...hash]
            } #{   swap[:contract]
            } #{   swap[:side].to_s
            }".colorize( swap[:side] == :upper ? :light_green : :light_red ) +
           " (#{   format '%4d', swap[:length]
            },#{   format '%4d', swap[:rating]
            },#{   format '%4d', swap[:depth]
        }) P: #{   format '%6s', (format '%4.2f', swap[:ppi])
           }  #{
                if swap[:current_value].nil?
              "I: #{   format '%8s', (format format, swap[:members].last[ ohlc ]) }"
                else
              "C: #{   format '%8s', (format format, swap[:current_value]) } "
                end
          } [#{ (swap[:members].first[:datetime] + delta_datetime).strftime(datetime_format)
         } - #{    (swap[:members].last[:datetime] + delta_datetime).strftime(datetime_format)
           }]#{"    NOTE: #{notice}" unless notice.nil?
           }".colorize(swap[:color] || :white )
        puts res
      else
        res = ["side: #{swap[:side] }\tlen: #{swap[:length]}  \trating: #{swap[:rating]}".colorize(swap[:color] || :white )]
        res <<  "diff: #{swap[:ticks]}\tdif: #{swap[:diff].round(7)}\tdepth: #{swap[:depth]}".colorize(swap[:color] || :white )
        res << "tpi:  #{swap[:tpi]  }\tppi: #{swap[:ppi]}".colorize(swap[:color] || :white )
        res << "NOTE: #{notice}".colorize(:light_white) unless notice.nil?
        swap[:members].each {|x| res << member_to_human(x, side: swap[:side], format: format, daily: daily) }
        res = res.join("\n")
        puts res
      end
      res
    end

    # create a standardized name for the cache files
    # and, on-the-fly, create these files plus their directory
    def get_jsonl_name(interval:, swap_type:, contract:, sym: nil)
      raise "Interval #{interval } is not supported, please choose from #{INTERVALS}" unless INTERVALS.include?(interval) || interval.is_a?(Integer)
      raise "Swaptype #{swap_type} is not supported, please choose from #{SWAPTYPES}" unless SWAPTYPES.include? swap_type
      sym ||= Cotcube::Helpers.get_id_set(contract: contract)
      root = '/var/cotcube/level'
      dir     = "#{root}/#{sym[:id]}"
      symlink = "#{root}/#{sym[:symbol]}"
      `mkdir -p #{dir}`         unless File.exist?(dir)
      `ln -s #{dir} #{symlink}` unless File.exist?(symlink)
      file = "#{dir}/#{contract}_#{interval.to_s}_#{swap_type.to_s}.jsonl"
      unless File.exist? file
        `touch #{file}`
      end
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
    #
    # it is not too nice that some actual interactive process is done here in the load section
    def load_swaps(interval:, swap_type:, contract:, sym: nil, datetime: nil, recent: false, digest: nil, quiet: false, exceed: false, keep_ignored: false)
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
            (sw[:ignored] = DateTime.parse(sw[:ignored]) rescue nil) if sw[:ignored]
            sw[:interval] = interval
            sw[:swap_type] = swap_type
            sw[:contract] = contract
            %i[ side ].each {|key| sw[key] = sw[key].to_sym rescue false }
            unless sw[:empty] or sw[:exceeded] or sw[:ignored]
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
      # assign ignorance data to actual swaps
      data.select{|swap| swap[:ignored] }.each do |ign|
	swap = data.find{|ref| ref[:digest] == ign[:ref]}
        raise RuntimeError, "Inconsistent history for '#{ign}'. Origin not found." if swap.nil?
        swap[:ignored] = ign[:ignored]
      end
      # do not return bare exceedance information
      data.reject!{|swap| (swap[:ignored] or swap[:exceeded]) and swap[:members].nil? }
      # do not return swaps that are found 'later'
      data.reject!{|swap| swap[:datetime] > datetime } unless datetime.nil?
      # do not return exceeded swaps, that are exceeded in the past
      recent  = 7.days  if recent.is_a? TrueClass
      recent += 5.hours if recent
      data.reject!{|swap| swap[:ignored] } unless keep_ignored
      data.reject!{|swap| swap[:exceeded] and swap[:exceeded] < datetime - (recent ? recent : 0) } unless datetime.nil?
      # remove exceedance information that is found 'later'
      data.map{|swap| swap.delete(:exceeded) if swap[:exceeded] and swap[:exceeded] > datetime} unless datetime.nil?
      unless digest.nil?
        data.select! do |z|
          (Cotcube::Helpers.sub(minimum: digest.length){ z[:digest] } === digest) and
          not z[:empty]
        end
        case data.size
        when 0
          puts "No swaps found for digest '#{digest}'." unless quiet
        when 1
          sym ||= Cotcube::Helpers.get_id_set(contract: contract)
          if not quiet or exceed
            puts "Found 1 digest: "
            data.each {|d| puts_swap( d, format: sym[:format], short: true, hash: digest.size + 2) }
            if exceed
              exceed = DateTime.now if exceed.is_a? TrueClass
              mark_exceeded(swap: data.first, datetime: exceed)
              puts "Swap marked exceeded."
            end
          end
        else
          sym ||= Cotcube::Helpers.get_id_set(contract: contract)
          unless quiet
            puts "Too many digests found for digest '#{digest}', please consider sending more figures: "
            data.each {|d| puts_swap( d, format: sym[:format], short: true, hash: digest.size + 3)}
          end
        end
      end
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
        %i[ current_change current_value current_diff current_dist alert].map{|key| swap[key] = update[key] }
        swap
      end.compact
    end

    def mark_exceeded(swap:, datetime:, debug: false, sym: nil)
      to_save = {
        datetime: datetime,
        ref:      swap[:digest],
        side:     swap[:side],
        exceeded: datetime
      }
      sym ||=  Cotcube::Helpers.get_id_set(contract: swap[:contract])
      save_swaps to_save, interval: swap[:interval], swap_type: swap[:swap_type], sym: sym, contract: swap[:contract], quiet: (not debug)
      swap
    end

    def mark_ignored(swap:, datetime: DateTime.now, sym: , debug: true)
      to_save = {
        datetime: datetime,
        ref:      swap[:digest],
        side:     swap[:side],
        ignored:  datetime
      }
      save_swaps to_save, interval: swap[:interval],  swap_type: swap[:swap_type], sym: sym, contract: swap[:contract], quiet: (not debug)
      swap
    end

  end
end

