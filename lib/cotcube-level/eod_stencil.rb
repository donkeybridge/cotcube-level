# frozen_string_literal: true

module Cotcube
  module Level

    class EOD_Stencil
      attr_accessor :base
      attr_reader   :interval


      # Class method that loads the (latest) obligatory stencil for given interval and type.
      # These raw stencils are located in /var/cotcube/level/stencils
      #
      # Current daily stencils contain dates from 2020-01-01 to 2023-12-31
      #
      def self.provide_raw_stencil(type:, interval: :daily, version: nil, timezone: Cotcube::Helpers::CHICAGO)
        loading = lambda do |typ|
          file_base = "/var/cotcube/level/stencils/stencil_#{interval.to_s}_#{typ.to_s}.csv_"
          if Dir["#{file_base}?*"].empty?
            raise ArgumentError, "Could not find any stencil matching interval #{interval} and type #{typ}. Check #{file_base} manually!"
          end
          if version.nil? # use latest available version if not given
            file = Dir["#{file_base}?*"].sort.last
          else
            file = "#{file_base}#{version}"
            unless File.exist? file
              raise ArgumentError, "Cannot open stencil from non-existant file #{file}."
            end
          end
          CSV.read(file).map{|x| { datetime: timezone.parse(x.first).freeze, x: x.last.to_i.freeze } }
        end
        unless const_defined? :RAW_STENCILS
          const_set :RAW_STENCILS, { daily:
                                     { full: loading.call( :full).freeze,
                                       rtc:  loading.call( :rtc).freeze
            }.freeze
          }.freeze
        end
        RAW_STENCILS[interval][type].map{|x| x.dup}
      end

      def initialize(
        range: nil,                 # used to shrink the stencil size, accepts String or Date
        interval:,
        swap_type:,
        date: nil,
        debug: false,
        version: nil,               # when referring to a specicic version of the stencil
        timezone: Cotcube::Helpers::CHICAGO,
        stencil: nil,               # instead of preparing, use this one if set
        warnings: true              # be more quiet
      )
        @debug     = debug
        @interval  = interval == :continuous ? :daily : interval
        @swap_type = swap_type
        @warnings = warnings
        step =  case @interval
                when :hours, :hour; 1.hour
                when :quarters, :quarter; 15.minutes
                else; 1.day
                end

        case @interval
        when :day, :days, :daily, :dailies, :synth, :synthetic #, :week, :weeks, :month, :months
          unless range.nil?
            starter = range.begin.is_a?(String) ? timezone.parse(range.begin) : range.begin
            ender   = range.  end.is_a?(String) ? timezone.parse(range.  end) : range.  end
          end

          stencil_type = case swap_type
                       when :rth
                         :full
                       when :rthc
                         :rtc
                       else
                         swap_type
                       end
          # TODO: Check / warn / raise whether stencil (if provided) is a proper data type
          raise ArgumentError, "EOD_Stencil should be nil or Array" unless [NilClass, Array].include? stencil.class
          raise ArgumentError, "Each stencil members should contain at least :datetime and :x" unless stencil.nil? or
            stencil.map{|x| ([:datetime, :x] - x.keys).empty? and [ActiveSupport::TimeWithZone, Day].include?( x[:datetime] ) and x[:x].is_a?(Integer)}.reduce(:&)

          base = stencil || EOD_Stencil.provide_raw_stencil(type: stencil_type, interval: :daily, version: version, timezone: timezone)

          # fast rewind to previous trading day
          date = timezone.parse(date) unless [NilClass, Date, ActiveSupport::TimeWithZone].include? date.class
          @date = date || Date.today
          best_match = base.select{|x| x[:datetime].to_date <= @date}.last[:datetime]
          @date  = best_match

          offset = base.map{|x| x[:datetime]}.index(@date)

          # apply offset to stencil, so zero will match today (or what was provided as 'date')
          @base = base.map.
            each_with_index{|d,i| d[:x] = (offset - i).freeze; d }
          # if range was given, shrink stencil to specified range
          @base.select!{|d| (d[:datetime] >= starter and d[:datetime] <= ender) } unless range.nil?
        else
          raise RuntimeError, "'interval: #{interval}' was provided, what does not match anything this tool can handle (currently :days, :dailies, :synthetic)."
        end
      end

      def dup
        EOD_Stencil.new(
          debug:      @debug,
          interval:   @interval,
          swap_type:  @swap_type,
          date:       @date,
          stencil:    @base.map{|x| x.dup}
        )
      end

      def zero
        index(0)
      end

      def index(offset = 0)
        @index ||= @base.index{|b| b[:x].zero? }
        @base[@index + offset]
      end

      def apply(to: )
        offset = 0 
        @base.each_index do |i| 
          begin
            offset += 1 while to[i+offset][:datetime].to_date < @base[i][:datetime].to_date
          rescue
            # appending
            to << @base[i]
            next
          end
          if to[i+offset][:datetime].to_date > @base[i][:datetime].to_date
            # skipping 
            offset -= 1
            next
          end
          # merging
          to[i+offset][:x] = @base[i][:x]
        end
        # finally remove all bars that do not belong to the stencil (i.e. holidays)
        to.reject!{|x| x[:x].nil? }
      end

      def use(with:, sym:, zero: nil, grace: -2)
        # todo: validate with (check if vslid swap
        #                sym  (check keys)
        #                zero (ohlc with x.zero?)
        #                side ( upper or lower)
        swap  = with.dup
        high  = swap[:side] == :upper
        ohlc  = high ? :high : :low
        start = base.find{|x| swap[:datetime] == x[:datetime]}
        swap[:current_change] = (swap[:tpi] * start[:x]).round(8)
        swap[:current_value]  =  swap[:members].last[ ohlc ] + swap[:current_change] * sym[:ticksize]
        unless zero.nil? 
          swap[:current_diff]   = (swap[:current_value] - zero[ohlc]) * (high ? 1 : -1 )
          swap[:current_dist]   = (swap[:current_diff] / sym[:ticksize]).to_i
          swap[:exceeded]       =  zero[:datetime] if swap[:current_dist] < grace
        end
        swap
      end
end

end

end

