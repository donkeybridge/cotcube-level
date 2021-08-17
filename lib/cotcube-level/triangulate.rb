module Cotcube
  module Level
      def triangulate(
          contract: nil,        # contract actually isnt needed to triangulation, but allows much more convenient output
          side:,                # :upper or :lower
          base:,                # the base of a readily injected stencil
          range: (0..-1),       # range is relative to base
          max: 90,              # the range which to scan for swaps goes from deg 0 to max
          debug: false,
          format: '% 5.2f',
          min_members: 3,       # this param should not be changed manually, it is used for the guess operation
          min_rating: 3,        # swaps having a lower rating are discarded
          allow_sub: true,      # this param determines whether guess can be called or not
          save: true,           # allow saving of results
          cached: true,         # allow loading of yet  cached intervals
          interval: nil,        # interval and swap_type are only needed if saving / caching of swaps is desired
          swap_type: nil,       #      if not given, a warning is printed and swaps are not saved
          deviation: 2)

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
        contract ||= zero.contract
        sym = Cotcube::Helpers.get_id_set(contract: contract)

        if cached
          if interval.nil? or swap_type.nil?
            puts "Warning: Cannot use cache as both :interval and :swap_type must be given".light_yellow
          else
            cache = load_swaps(interval: interval, swap_type: swap_type, contract: contract, sym: sym)
            selected = cache.select{|sw| sw[:datetime] == zero[:datetime] and sw[:side] == side}
            unless selected.empty?
              puts 'cache_hit'.light_white if debug
              return (selected.first[:empty] ? [] : selected )
            end
          end
        end
        ticksize = sym[:ticksize]  / sym[:bcf] # need to adjust, as we are working on barchart data, not on exchange data !!


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
        base.each_index.map{|i| base[i][:i] = -base.size + i }


        ###########################################################################################################################
        # LAMBDA no1: simplifying DEBUG output
        #
        present = lambda {|z| swap_to_human(z) }



        ###########################################################################################################################
        # LAMBDA no2: all members except the pivot itself now most probably are too far to the left
        #             finalizing tries to get the proper dx value for them
        #
        finalize = lambda do |res|
          res.map do |r|
            r[:members].each  do |m|
              next if m[:yy].nil? or m[:yy].zero?

              diff = (m[:x] - m[:dx]).abs / 2.0
              m[:dx] = m[:x] + diff
              # it employs another binary-search
              while m[:yy].round(PRECISION) != 0 # or m[:yy].round(PRECISION) < -ticksize
                print '.' if debug
                m[:yy] = shear_to_deg(deg: r[:deg], base: [ m ] ).first[:yy]
                diff /= 2.0
                if m[:yy] > 0
                  m[:dx] += diff
                else
                  m[:dx] -= diff
                end
              end
              m[:yy] = m[:yy].abs.round(8)
            end # r.members
            puts 'done!'.light_yellow if debug

            r[:members].each {|x| puts "finalizing #{x}".magenta } if debug
            ## The transforming part

            r
	  end    # res
	end      # lambda

        ###########################################################################################################################
	# LAMDBA no3:  the actual 'function' to retrieve the slope
        #
	get_slope = lambda do |b|
	  if debug
            puts "in get_slope ... SETTING BASE: ".light_green
	    puts "Last:\t#{present.call  b.last}"
	    puts "First:\t#{present.call b.first}"
	  end
	  members = [ b.last[:i] ]
	  loop do
	    current_slope   = detect_slope(base: b, ticksize: ticksize, format: sym[:format], debug: debug)
            current_members = current_slope[:members]
	      .map{|dot| dot[:i]}
	    new_members = current_members - members
	    puts "New members: #{new_members} as of #{current_members} - #{members}" if debug
	    # the return condition is if no new members are found in slope
	    # except lowest members are neighbours, what causes a re-run
	    if new_members.empty? 
	      mem_sorted=members.sort
	      if mem_sorted[1] == mem_sorted[0] + 1
                b2 = b[mem_sorted[1]..mem_sorted[-1]].map{|x| x.dup; x[:dx] = nil; x}
                puts 'starting rerun' if debug
                alternative_slope = get_slope.call(b2)
                alternative = alternative_slope[:members].map{|bar| bar[:i]}
		if (mem_sorted[1..-1] - alternative).empty?
		  current_slope = alternative_slope
		  members = alternative
		end
	      end
              if min_members >= 3 and members.size >= 3
                current_slope[:raw]    = members.map{|x| x.abs }.sort
                current_slope[:length] = current_slope[:raw][-1] - current_slope[:raw][0]
                current_slope[:rating] = current_slope[:raw][1..-2].map{|dot| [ dot - current_slope[:raw][0], current_slope[:raw][-1] - dot].min }.max
              end
              members.sort_by{|i| -i}.each do |x|
                puts "#{range}\t#{present.call(b[x])}" if debug
                current_slope[:members] << b[x] unless current_slope[:members].map{|x| x[:datetime]}.include? b[x][:datetime]
                current_slope[:members].sort_by!{|x| x[:datetime]}
              end
              return current_slope

            end
            new_members.each do |mem|
              current_deviation = (0.1 * b[mem][:x])
              current_deviation =  1                  if current_deviation < 1
              current_deviation =  deviation          if current_deviation > deviation
              b[mem][:dx] = b[mem][:x] + current_deviation
            end
            members += new_members
          end
        end # of lambda

        analyze = lambda do |swaps|
          swaps.each do |swap|
            swap[:datetime] = swap[:members].last[:datetime]
            swap[:side]   = side
            rat = swap[:rating]
            swap[:color ] = (rat > 75) ? :light_blue : (rat > 30) ? :magenta : (rat > 15) ? :light_magenta : (rat > 7) ? (high ? :light_green : :light_red) : high ? :green : :red
            swap[:diff]   = swap[:members].last[ high ? :high : :low ] - swap[:members].first[ high ? :high : :low ]
            swap[:ticks]  = (swap[:diff] / sym[:ticksize]).to_i
            swap[:tpi]    = (swap[:ticks].to_f / swap[:length]).round(3)
            swap[:ppi]    = (swap[:tpi] * sym[:power]).round(3)
            swap_base     = shear_to_deg(base: base[swap[:members].first[:i]..], deg: swap[:deg]).map{|x| x[:dev] = (x[:yy] / sym[:ticksize]).abs.floor; x}
            swap[:depth]  = swap_base.max_by{|x| x[:dev]}[:dev]
            swap[:avg_dev]= (swap_base.reject{|x| x[:dev].zero?}.map{|x| x[:dev]}.reduce(:+) / (swap_base.size - swap[:members].size).to_f).ceil rescue 0
            # a miss is considered a point that is less than 10% of the average deviation away of the slope
            unless swap[:avg_dev].zero?
              misses        = swap_base.select{|x| x[:dev] <= swap[:avg_dev] / 10.to_f and x[:dev] > 0}.map{|x| x[:miss] = x[:dev]; x}
              # misses are sorted among members, but stay marked
              swap[:members]= (swap[:members] + misses).sort_by{|x| x[:datetime] }
            end
          end # swap
        end # of lambda

        ###########################################################################################################################
        # after declaring lambdas, the rest is quite few code
        #
        current_range = (0..-1)                                                                                         # RANGE   set
        current_slope = { members: [] }                                                                                 # SLOPE   reset
        current_base = base[current_range]                                                                              # BASE    set
        current_results = [ ]                                                                                           # RESULTS reset
        while current_base.size >= 5                                                                                    # LOOP

          puts '-------------------------------------------------------------------------------------' if debug

          while current_base.size >= 5 and current_slope[:members].size < min_members
            puts "---- #{current_base.size} #{current_range.to_s.light_yellow} ------" if debug
            current_slope = get_slope.call(current_base)                                                                # SLOPE   call
            next_i  = current_slope[:members][-2]
            current_range = ((next_i.nil? ? -2 : next_i[:i])+1..-1)                                                     # RANGE   adjust
            current_base = base[current_range]                                                                          # BASE    adjust
            if debug
              print 'Hit <enter> to continue...'
              STDIN.gets
            end
          end
          puts "Current slope: ".light_yellow + "#{current_slope}" if debug
          current_results << current_slope if current_slope                                                             # RESULTS add
          current_slope = { members: [] }                                                                               # SLOPE   reset
        end
        current_results.select!{|x|  x[:members].size >= min_members }

        # Adjust all members (except pivot) to fit the actual dx-value
        finalize.call(current_results)
        analyze.call(current_results)
        current_results.reject!{|swap| swap[:rating] < min_rating}
        if save
          if interval.nil? or swap_type.nil?
            puts "WARNING: Cannot save swaps, as both :interval and :swap_type must be given".colorize(:light_yellow)
          else
            to_save = current_results.empty? ? [ { datetime: zero[:datetime], side: side, empty: true } ] : current_results
            save_swaps(to_save, interval: interval, swap_type: swap_type, contract: contract, sym: sym)
          end
        end
        current_results
      end
  end
end

