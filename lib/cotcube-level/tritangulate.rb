module Cotcube
  module Level
    def tritangulate(
      contract: nil,        # contract actually isnt needed for tritangulation, but allows much more convenient output
                            # on some occasion here can also be given a :symbol, but this requires :sym to be set
      sym: nil,             # sym is the id set provided by Cotcube::Helper.get_id_set
      side:,                # :upper or :lower
      base:,                # the base of a readily injected stencil
      range: (0..-1),       # range is relative to base
      max: 90,              # the range which to scan for swaps goes from deg 0 to max
      debug: false,
      min_rating: 3,        # 1st criteria: swaps having a lower rating are discarded
      min_length: 8,        # 2nd criteria: shorter swaps are discared
      min_ratio:            # 3rd criteria: the ratio between rating and length (if true, swap is discarded)
        lambda {|r,l| r < l / 4.0 },
      save: true,           # allow saving  of results
      cached: true,         # allow loading of cached results
      interval: ,           # interval (currently) is one of %i[ daily continuous halfs ]
      swap_type: nil,       # if not given, a warning is printed and swaps won't be saved or loaded
      with_flaws: 0,        # the maximum amount of consecutive bars that would actually break the current swap
                            # should be set to 0 for dailies and I suggest no more than 3 for intraday
      deviation: 2          # the maximum shift of :x-values of found members
    )

      raise ArgumentError, "'0 < max < 90, but got '#{max}'" unless max.is_a? Numeric and 0 < max and max <= 90
      raise ArgumentError, 'need :side either :upper or :lower for dots' unless [:upper, :lower].include? side

      ###########################################################################################################################
      # init some helpers
      #
      high       = side == :upper
      first      = base.to_a.find{|x|  not x[:high].nil? }
      zero       = base.select{|x| x[:x].zero? }
      raise ArgumentError, "Inappropriate base, it should contain ONE :x.zero, but contains #{zero.size}." unless zero.size==1
      zero       = zero.first

      contract ||= zero[:contract]
      sym      ||= Cotcube::Helpers.get_id_set(contract: contract)


      if cached
        if interval.nil? or swap_type.nil?
          puts "Warning: Cannot use cache as both :interval and :swap_type must be given".light_yellow
        else
          cache = load_swaps(interval: interval, swap_type: swap_type, contract: contract, sym: sym, datetime: zero[:datetime])
          # if the current datetime was already processed but nothing has been found,
          # an 'empty' value is saved.
          # that means, if neither a swap (or more) nor :empty is found, the datetime has not been processed yet
          selected = cache.select{|sw| sw[:datetime] == zero[:datetime] and sw[:side] == side }
          unless selected.empty?
            puts 'cache_hit'.light_white if debug
            return (selected.first[:empty] ? [] : selected )
          end
        end
      end

      ###########################################################################################################################
      # prepare base (i.e. dupe the original, create proper :y, and reject unneeded items)
      #
      base = base.
        map { |x|
        y = x.dup
        y[:y] = (high ?
                 (y[:high] - zero[:high]).round(8) :
                 (zero[:low] - y[:low]).round(8)
                ) unless y[:high].nil?
        y
      }.
      reject{|b| b.nil? or b[:datetime] < first[:datetime] or b[:x] < 0 or b[:y].nil?}[range]

      # abs_peak is the absolute high / low of the base. the shearing operation ends there,
      # but results might be influenced when abs_peak becomes affected by :with_flaws
      abs_peak = base.send(high ? :max_by : :min_by){|x| x[high ? :high : :low] }[:datetime]
      base.reject!{|x| x[:datetime] < abs_peak}

      ###########################################################################################################################z
      # only if (and only if) the range portion above change the underlying base
      #   the offset has to be fixed for :x and :y

      unless range == (0..-1)
        puts "adjusting range to '#{range}'".light_yellow if debug
        offset_x = base.last[:x]
        offset_y = base.last[:y]
        base.map!{|b| b[:x] -= offset_x; b[:y] -= offset_y  ; b}
      end

      ###########################################################################################################################
      # introducing :i to the base, which provides the negative index of the :base Array of the current element
      # this simplifies handling during the, where I can use the members array,
      # that will carry just the index of the original base, regardless how many array_members have be already dropped
      base.each_index.map{|i| base[i][:i] = -base.size + i }


      ###########################################################################################################################
      # LAMBDA no1: simplifying DEBUG output
      #
      present = lambda {|z|  z.slice(*%i[datetime high low x y i yy dx dev near miss dev]) }


      ###########################################################################################################################
      # LAMBDA no2: all members except the pivot itself now most probably are too far to the left
      #             finalizing tries to get the proper dx value for them
      #
      finalize = lambda do |results|
        results.map do |result|
          result[:members].each  do |member|
            next if member[:yy].nil? or member[:yy].zero?

            diff = (member[:x] - member[:dx]).abs / 2.0
            member[:dx] = member[:x] + diff
            # it employs another binary-search
            while member[:yy].round(PRECISION) != 0
              print '.' if debug
              member[:yy] = shear_to_deg(deg: result[:deg], base: [ member ] ).first[:yy]
              diff /= 2.0
              if member[:yy] > 0
                member[:dx] += diff
              else
                member[:dx] -= diff
              end
            end
            member[:yy] = member[:yy].abs.round(8)
          end

          puts 'done!'.magenta if debug
          result[:members].each {|member| puts "finalizing #{member}".magenta } if debug
          result
        end
      end

      ###########################################################################################################################
      # LAMDBA no3:  the actual 'function' to retrieve the slope
      #
      # the idea implemented is based on the fact, that we don't know in which exact time of the interval the value
      #     was created. even further we know that the stencil might be incorrect. so after shearing the :x value of the
      #     recently found new member(s) is shifted by :deviation and shearing is repeated. this is done as long as new members
      #     are found.
      get_slope = lambda do |b|
        if debug
          puts "in get_slope ... SETTING BASE: ".light_green
          puts "Last: \t#{present.call b.last }".light_green
          puts "First:\t#{present.call b.first}".light_green
        end
        members = [ b.last[:i] ]
        loop do
          current_slope   = detect_slope(base: b, ticksize: sym[:ticksize], format: sym[:format], debug: debug)
          if debug
            puts "CURR: #{current_slope[:deg]} "
            current_slope[:members].each {|x| puts "CURR: #{present.call(x)}" }
          end
          current_members = current_slope[:members].map{|dot| dot[:i]}
          new_members = current_members - members
          puts "New members: #{new_members} (as of #{current_members} - #{members})" if debug
          # the return condition is if no new members are found in slope
          # except lowest members are neighbours, what (recursively) causes re-run until the
          # first member is solitary
          if new_members.empty?
            mem_sorted=members.sort
            if mem_sorted[1] == mem_sorted[0] + 1
              b2 = b[mem_sorted[1]..mem_sorted[-1]].map{|x| x.dup; x[:dx] = nil; x}
              puts 'starting recursive rerun'.light_red if debug
              alternative_slope = get_slope.call(b2)
              alternative = alternative_slope[:members].map{|bar| bar[:i]}
              # the alternative won't be used if it misses out a member that would have
              # been in the 'original' slope
              if (mem_sorted[1..-1] - alternative).empty?
                current_slope = alternative_slope
                members = alternative
              end
            end

            current_slope[:raw]    = members.map{|i| base[i][:x]}

            members.sort_by{|i| -i}.each_with_index do |i, index|

              puts "#{index}\t#{range}\t#{present.call b[i]}".light_yellow if debug

              current_slope[:members] << b[i] unless current_slope[:members].map{|x| x[:datetime]}.include? b[i][:datetime]
              current_slope[:members].sort_by!{|x| x[:datetime]}
            end
            return current_slope

          end
          # all new members found in current iteration have now receive their new :x value, depending on their distance to
          #    to the origin. when exploring near distance, it is assumned, that the actual :y value might have an
          #    additional distance of 1, further distant points can be distant even :deviation, what defaults to 2
          #    covering e.g. a holiday when using a daily base
          new_members.each do |mem|
            current_deviation = (0.1 * b[mem][:x])
            current_deviation =  1                  if current_deviation < 1
            current_deviation =  deviation          if current_deviation > deviation
            b[mem][:dx] = b[mem][:x] + current_deviation
          end
          members += new_members
        end
      end # of lambda

      ###########################################################################################################################
      # Lambda no. 4: analyzing the slope, adding near misses and characteristics
      #
      # near misses are treated as full members, as for example stacked orders within a swap architecture might impede that the
      # peak runs to the maximum expansion
      #
      # first, the swap_base is created by shearing the entire base to current :deg
      # then all base members are selected that fit the desired :y range.
      # please note that here also the processing of :with_flaws takes place
      #
      # the key :dev is introduced, which is actually a ticksize-based variant of :yy

      analyze = lambda do |swaps|
        swaps.each do |swap|

          swap_base      = base.map{|y|
            x = y.slice(*%i[ datetime high low dist x y i yy dx ])
            current_member = swap[:members].find{|z| z[:datetime] == x[:datetime] }
            x[:dx] = current_member[:dx] if current_member
            x
          }
          swap_base      = shear_to_deg(base: swap_base, deg: swap[:deg])
          swap_base.map!{|x| x[:dev] = (x[:yy] / sym[:ticksize].to_f); x[:dev] = -( x[:dev] > 0 ? x[:dev].floor : x[:dev].ceil);  x}
          invalids       = swap_base.select{|x| x[:dev] < 0 }
          with_flaws = 0 unless with_flaws # support legacy versions, where with_flaws was boolean
          if with_flaws > 0
            # TODO: this behaves only as expected when with_flaws == 2
            last_invalid   = invalids[(invalids[-2][:i] + 1 == invalids[-1][:i] ) ? -3 : -2] rescue nil
          else
            last_invalid   = invalids.last
          end

          # the 'near' members are all base members found, that fit
          #  1. being positive (as being zero means that they are original members)
          #  2. match a valid :dev
          #  3. appeared later than :last_invalid
          near           = swap_base.select{|x|
            x[:dev] <= [ 5, (x[:x] / 100)+2 ].min and
              x[:dev].positive? and
              (last_invalid.nil? ? true : x[:datetime] > last_invalid[:datetime])
          }.map{|x| x[:near] = x[:dev]; x}

          # these then are added to the swap[:members] and for further processing swap_base is cleaned
          swap[:members] = (swap[:members] + near).sort_by{|x| x[:datetime] }
          swap_base.select!{|x| x[:datetime] >= swap[:members].first[:datetime]}

          ########################################################################33
          # now swap characteristics are calculated
          #
          # avg_dev: the average distance of high or low to the swap_line
          swap[:avg_dev]   = (swap_base.reject{|x| x[:dev].zero?}.map{|x| x[:dev].abs}.reduce(:+) / (swap_base.size - swap[:members].size).to_f).ceil rescue 0
          # depth:   the maximum distance to the swap line
          swap[:depth]     = swap_base.max_by{|x| x[:dev]}[:dev]
          swap[:interval]  = interval
          swap[:swap_type] = swap_type
          swap[:raw]       = swap[:members].map{|x| x[:x]}.reverse
          swap[:size]      = swap[:members].size
          swap[:length]    = swap[:raw][-1] - swap[:raw][0]
          # rating:  the maximum distance of the 'most middle' point of the swap to the nearer end
          swap[:rating]    = swap[:raw][1..-2].map{ |dot| [ dot - swap[:raw][0], swap[:raw][-1] - dot].min }.max || 0
          swap[:datetime]  = swap[:members].last[:datetime]
          swap[:side]      = side
          rat = swap[:rating]
          # color:   to simplify human readability a standard set of colors for intraday and eod based swaps
          swap[:color]     =  (rat > 75)  ? :light_blue : (rat > 30) ? :magenta : (rat > 15) ? :light_magenta : (rat > 7) ? (high ? :light_green : :light_red) : high ? :green : :red
          unless %i[ daily continuous ].include? interval
            swap[:color]     = ((rat > 150) ? :light_blue : (rat > 80) ? :magenta : (rat > 30) ? :light_magenta : (rat > 15) ? :light_yellow : high ? :green : :red)
          end
          swap[:diff]      = (swap[:members].last[ high ? :high : :low ] - swap[:members].first[ high ? :high : :low ]).round(8)
          swap[:ticks]     = (swap[:diff] / sym[:ticksize]).to_i
          # tpi:     ticks per interval, how many ticks are passed each :interval
          swap[:tpi]       = (swap[:ticks].to_f / swap[:length]).round(3)
          # ppi:     power per interval, how many $dollar value is passed each :interval
          swap[:ppi]       = (swap[:tpi] * sym[:power]).round(3)
        end # swap
      end # lambda

      ###########################################################################################################################
      # after declaring lambdas, the rest is quite few code
      #
      # starting with the full range, a valid slope is searched. the found slope defines an interval of the
      # base array, in which again a (lower) slope can be uncovered.
      #
      # this process is repeated while the interval to be processed is large enough (:min_length)
      current_range = (0..-1)                                                                                         # RANGE   set
      current_slope = { members: [] }                                                                                 # SLOPE   reset
      current_base = base[current_range].map{|z| z.slice(*%i[datetime high low x y i ])}                              # BASE    set
      current_results = [ ]                                                                                           # RESULTS reset
      binding.irb if debug
      while current_base.size >= min_length                                                                           # LOOP

        puts '-------------------------------------------------------------------------------------' if debug

        while current_base.size >= min_length and current_slope[:members].size < 2

          puts "---- #{current_base.size} #{current_range.to_s.light_yellow} ------" if debug

          # get new slope
          current_slope = get_slope.call(current_base)                                                                # SLOPE   call

          # define new range and base
          next_i  = current_slope[:members].select{|z| z[:miss].nil? and z[:near].nil?}[-2]
          current_range = ((next_i.nil? ? -2 : next_i[:i])+1..-1)                                                     # RANGE   adjust
          current_base = base[current_range].map{|z| z.slice(*%i[datetime high low x y i ])}                          # BASE    adjust
        end
        puts "Current slope: ".light_yellow + "#{current_slope}" if debug
        current_results << current_slope if current_slope                                                             # RESULTS add
        current_slope = { members: [] }                                                                               # SLOPE   reset
      end

      finalize.call(current_results)
      analyze.call(current_results)
      binding.irb if debug

      # reject all results that do not suffice
      current_results.reject!{|swap| swap[:rating] < min_rating or swap[:length] < min_length or min_ratio.call(swap[:rating],swap[:length])}

      #####################################################################################################################3
      # finally save results for caching and return them
      if save
        if interval.nil? or swap_type.nil?
          puts "WARNING: Cannot save swaps, as both :interval and :swap_type must be given".colorize(:light_yellow)
        else
          current_results.map{|sw| mem = sw[:members]; sw[:slope] = (mem.last[:y] - mem.first[:y]) / (mem.last[mem.last[:dx].nil? ? :x : :dx] - mem.first[mem.first[:dx].nil? ? :x : :dx]).to_f }
          to_save = current_results.empty? ? [ { datetime: zero[:datetime], side: side, empty: true, interval: interval, swap_type: swap_type } ] : current_results
          save_swaps(to_save, interval: interval, swap_type: swap_type, contract: contract, sym: sym)
        end
      end
      current_results
    end
  end
end

