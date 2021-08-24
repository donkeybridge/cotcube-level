module Cotcube
  module Level
    def detect_slope(base:, max: 90, debug: false, format: '% 5.2f', calculus: false, ticksize: nil, max_dev: 200)
      raise ArgumentError, "'0 < max < 90, but got '#{max}'" unless max.is_a? Numeric and 0 < max and max <= 90
      #
      # this method processes a 'well prepared' stencil in a way, that :y values are sheared around stencil.zero,
      #     resulting to a temporary :yy value for each point. this process is iterated until no more :yy
      #     values are above the abscissa ( yy > 0 ) but at least one other values is on (yy == 0)
      #
      # the entire process initially aimed to find slopes that contain 3 or more members. the current version 
      #     is confident with 2 members--or even one member, which results in an even slope.
      #
      # it works by running a binary search, whereon each iteration,
      #   - :part is halved and added or substracted based on current success
      #   - if more than the mandatory result is found, all negative results are removed and degrees are increased by part
      #   - if no results are found, the process is repeated with the same current base after degrees are decreased by part
      #
      raise ArgumentError, 'detect_slope needs param Array :base' unless base.is_a? Array

      # from given base, choose non-negative stencil containing values
      old_base = base.dup.select{|b| b[:x] >= 0 and not b[:y].nil? }

      # set initial shearing angle if not given as param. This is a prepared functionality, that is not yet used.
      # when implemented to use in tritangulate, it would speed up the binary search process, but initial part 
      # has to be set in a different way
      deg ||= -max / 2.0

      # create first shearing. please note how selection works with d[:yy]
      new_base = shear_to_deg(base: old_base, deg: deg).select { |d| d[:yy] >= 0 }

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
      #   - several points are found on the slope in quite a good approximation ('round(PRECISION)')
      #
      until deg.round(PRECISION).zero? || part.round(PRECISION).zero? ||
          ((new_base.size >= 2) && (new_base.map { |f| f[:yy].round(PRECISION / 2).zero? }.uniq.size == 1))

        part /= 2.0
        if new_base.size == 1
          # the graph was sheared too far, reuse old_base
          deg += part
        else
          # the graph was sheared too short, continue with new base
          deg -= part
          old_base = new_base.dup unless deg.round(PRECISION).zero?
        end

        # the actual shearing operation
        # this basically maps old_base with yy = y + (dx||x * tan(deg) )
        #
        new_base = shear_to_deg(base: old_base, deg: deg).select { |d| d[:yy] >= 0 }
        new_base.last[:dx] = 0.0

        # debug output is reduced by appr. 70%
        if debug and Random.rand < 0.3
          print " #{format '% 18.15f',deg}\t"
          puts "Iterating slope:\t#{format '% 18.10f',deg
                               }\t#{new_base.size
                             } || #{new_base.values_at(*[0]).map{|f| "'#{f[:x]
                                                                   } | #{format '%4.5f', part
                                                                   } | #{format format,f[:y]
                                                          } | #{format format,f[:yy]}'"}.join(" || ") }"
        end
      end
      ### Sheering ends here

      # define the approximited result as (also) 0.0
      new_base.each{|x| x[:yy] = 0.0}

      #####################################################################################
      # Calculate the slope based on the angle that resulted above
      #     y = m x + n -->
      #                     m = delta-y / delta-x
      #                     n = y0 - m * x0
      #
      slope     = deg.zero? ? 0 : (new_base.first[:y] - new_base.last[:y]) / (
        (new_base.first[:dx].nil? ? new_base.first[:x] : new_base.first[:dx]).to_f -
        (new_base. last[:dx].nil? ? new_base. last[:x] : new_base. last[:dx]).to_f
      )
      # the result
      {
        deg:       deg,
        slope:     slope,
        members:   new_base.map { |x| x.dup }
      }
    end
  end
end
