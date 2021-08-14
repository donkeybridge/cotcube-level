module Cotcube
  module Level
    #
      # TODO: add support for slopes not only exactly matching but also allow 'dip' of n x ticksize
      def detect_slope(base:, max: 90, debug: false, format: '% 5.2f', calculus: false, ticksize: nil, max_dev: 200)
        raise ArgumentError, "'0 < max < 90, but got '#{max}'" unless max.is_a? Numeric and 0 < max and max <= 90
        #
        # aiming for a shearing angle, all but those in a line below the abscissa
        #
        # doing a binary search starting at part = 45 degrees
        # on each iteration,
        #   part is halved and added or substracted based on current success
        #   if more than the mandatory result is found, all negative results are removed and degrees are increased by part
        #
        raise ArgumentError, 'detect_slope needs param Array :base' unless base.is_a? Array

        # from given base, choose non-negative stencil containing values
        old_base = base.dup.select{|b| b[:x] >= 0 and not b[:y].nil? }

        # some debug output
        old_base.each {|x| p x} if old_base.size < 50 and debug

        # set initial shearing angle if not given as param
        deg ||= -max / 2.0 

        # create first sheering. please note how selection working with d[:yy]
        new_base = shear_to_deg(base: old_base, deg: deg).select { |d| d[:yy] >= 0 } #-ticksize }

        # debug output
        puts "Iterating slope:\t#{format '% 7.5f',deg
                           }\t\t#{new_base.size
                           } || #{new_base.values_at(*[0]).map{|f| "'#{f[:x]
                                                                    } | #{format format,f[:y]
                                                                    } | #{format format,f[:yy]}'"}.join(" || ") }" if debug
        # set initial part to deg
        part = deg.abs
        #
        # the loop, that runs until either
        #   - only two points are left on the slope
        #   - the slope has even angle
        #   - several points are on the slope in quite a good approximation ('round(7)')
        #
        until deg.round(PRECISION).zero? || part.round(PRECISION).zero? ||
            ((new_base.size >= 2) && (new_base.map { |f| f[:yy].round(PRECISION).zero? }.uniq.size == 1))

          part /= 2.0
          if new_base.size == 1
            # the graph was sheared too far, reuse old_base
            deg = deg + part
          else
            # the graph was sheared too short, continue with new base
            deg = deg - part
            old_base = new_base.dup unless deg.round(PRECISION).zero?
          end

          # the actual sheering operation
          # note that this basically maps old_base with yy = y + (dx||x * tan(deg) )
          #
          new_base = shear_to_deg(base: old_base, deg: deg).select { |d| d[:yy] >= 0 } #-ticksize }
          new_base.last[:dx] = 0.0 
          if debug
            print " #{format '% 8.5f',deg}"
            puts "Iterating slope:\t#{format '% 8.5f',deg
                                 }\t#{new_base.size
                               } || #{new_base.values_at(*[0]).map{|f| "'#{f[:x]
                                                                     } | #{format '%4.5f', part
                                                                     } | #{format format,f[:y]
                                                                     } | #{format format,f[:yy]}'"}.join(" || ") }"
          end
        end
        puts ' done.' if debug

        ### Sheering ends here

        # define the approximited result as (also) 0.0
        new_base.each{|x| x[:yy] = 0.0}
        if debug
          puts "RESULT: #{deg} #{deg2rad(deg)}"
          new_base.each {|f| puts "\t#{f.inspect}" }
        end
        # there is speacial treatment for even slopes
        if deg.round(PRECISION).zero?
          #puts "found even slope"
          # this is intentionally voided as evenness is calculated somewhere else
          # even_base = base.dup.select{|b| b[:x] >= 0 and not b[:y].nil? }[-2..-1].map{|x| x.dup}
          # last_barrier is the last bar, that exceeds
          #binding.irb
          #last_barrier = even_base.select{|bar| (bar[:y] - even_base.last[:y]).abs > evenness * ticksize}.last
          #even_base.select!{|bar| (bar[:y] - even_base.last[:y]).abs <= evenness * ticksize}
          # could be, that no last barrier exists, when there is a top or bottom plateau
          #even_base.select!{|bar| bar[:x] < last_barrier[:x]} unless last_barrier.nil?
          # TODO
          return { deg: 0,  slope: 0, members: [] } #, members: even_base.map { |x| xx = x.dup; %i[y yy].map { |z|  xx[z]=nil }; xx } })
        end


        #####################################################################################
        # Calculate the slope bsaed on the angle that resulted above
        #     y = m x + n -->
        #                     m = delta-y / delta-x
        #                     n = y0 - m * x0
        #
        slope     = (new_base.first[:y] - new_base.last[:y]) / (
                        (new_base.first[:dx].nil? ? new_base.first[:x] : new_base.first[:dx]).to_f - 
                        (new_base. last[:dx].nil? ? new_base. last[:x] : new_base. last[:dx]).to_f 
                    )
        # the result
        {
          deg:        deg,
          slope:      slope,
          members:   new_base.map { |x| x.dup }
        }
      end
  end
end


