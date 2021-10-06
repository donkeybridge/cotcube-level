# frozen_string_literal: true

module Cotcube
  module Level

    class Intraday_Stencil


      # Class method that loads the (latest) shiftset for given asset
      # These raw stencils are located in /var/cotcube/level/stencils/shiftsets.csv
      #

      def self.shiftset(asset:, sym: nil)
        shiftset_file = '/var/cotcube/level/stencils/shiftsets.csv'
        headers =  %i[nr tz sod pre mpre rth post mpost rth5 mpost5 symbols]
        shiftsets = CSV.read(shiftset_file, headers: headers).
          map{|x| x.to_h}
        current_set = shiftsets.find{|s| s[:symbols] =~ /#{asset}/ }
        return current_set.tap{|s| headers.map{|h| s[h] = nil if s[h] == '---------' }; s[:rth5] ||= s[:rth]; s[:mpost5] ||= s[:mpost] }  unless current_set.nil?
        sym ||= Cotcube::Helpers.get_id_set(symbol: asset)
        current_set = shiftsets.find{|s| s[:symbols] =~ /#{sym[:type]}/ }
        return current_set.tap{|s| headers.map{|h| s[h] = nil if s[h] == '---------' }; s[:rth5] ||= s[:rth]; s[:mpost5] ||= s[:mpost] }  unless current_set.nil?
        raise "Cannot get shiftset for #{sym[:type]}: #{asset}, please prepare #{shiftset_file} before!"
      end

      attr_reader :base, :shiftset, :timezone, :datetime, :zero, :index



      def initialize(
        asset:,
        interval: 30.minutes,
        swap_type: :full,
        datetime: nil,
        debug: false,
        weeks: 6,
        future: 2,
        version: nil,               # when referring to a specicic version of the stencil
        stencil: nil,               # instead of preparing, use this one if set
        warnings: true              # be more quiet
      )
        @shiftset = Intraday_Stencil.shiftset(asset: asset)
        @timezone  = Cotcube::Level::TIMEZONES[@shiftset[:tz]]
        @debug     = debug
        @interval  = interval
        @swap_type = swap_type
        @warnings = warnings
        datetime ||= DateTime.now
        datetime  = @timezone.at(datetime.to_i) unless datetime.is_a? ActiveSupport::TimeWithZone
        @datetime = datetime.beginning_of_day
        @datetime += interval while @datetime <= datetime - interval
        @datetime -= interval

        const = "RAW_INTRA_STENCIL_#{@shiftset[:nr]}_#{interval.in_minutes.to_i}".to_sym
        if Object.const_defined? const
          @base = (Object.const_get const).map{|z| z.dup}
        else
          start_time    = lambda {|x| @shiftset[x].split('-').first rescue '' }
          start_hours   = lambda {|x| @shiftset[x].split('-').first[ 0.. 1].to_i.send(:hours)   rescue 0 }
          start_minutes = lambda {|x| @shiftset[x].split('-').first[-2..-1].to_i.send(:minutes) rescue 0 }
          end_time      = lambda {|x| @shiftset[x].split('-').last  rescue '' }
          end_hours     = lambda {|x| @shiftset[x].split('-').last [ 0.. 1].to_i.send(:hours)   rescue 0 }
          end_minutes   = lambda {|x| @shiftset[x].split('-').last [-2..-1].to_i.send(:minutes) rescue 0 }

         runner = (@datetime -
                    weeks * 7.days).beginning_of_week(:sunday)
          tm_runner = lambda { runner.strftime('%H%M') }
          @base = []
          (weeks+future).times do
            while tm_runner.call < GLOBAL_SOW[@shiftset[:tz]].split('-').last
              # if daylight is switched, this phase will be shorter or longer
              @base << { datetime: runner, type: :sow }
              runner += interval
            end
            end_of_week = runner + 6.days + 7.hours

            5.times do |i|
              # TODO: mark holidays as such
              [:sod, :pre, :mpre, (i<4 ? :rth : :rth5), :post, (i<4 ? :mpost : :mpost5)].each do |phase|
                yet_rth = false
                unless start_time.call(phase).empty?
                  eophase = end_time.call(phase)
                  sophase = start_time.call(phase)
                  phase = :rth   if phase == :rth5
                  phase = :mpost if phase == :mpost5
                  if %i[ pre rth ].include? phase and tm_runner.call > sophase
                    # fix previous interval
                    @base.last[:type] = phase
                    if phase == :rth and not yet_rth
                      @base.last[:block] = true
                      yet_rth = true
                    end
                  end
                  while ((sophase > eophase) ? (tm_runner.call >= sophase or tm_runner.call < eophase) : (tm_runner.call < eophase))
                    current = { datetime: runner, type: phase }
                    if phase == :rth and not yet_rth
                      current[:block] = true
                      yet_rth = true
                    end
                    @base << current
                    runner += interval
                  end
                end
              end
              while tm_runner.call < GLOBAL_EOD[@shiftset[:tz]].split('-').last
                @base << { datetime: runner, type: :eod }
                runner += interval
              end
            end # 5.times
            while runner < end_of_week
              @base << { datetime: runner, type: :eow }
              runner += interval
            end
          end
          Object.const_set(const, @base.map{|z| z.dup})
        end

        case swap_type
        when :full
          @base.select!{|x| %i[ pre rth post ].include?(x[:type]) }
        when :rth
          @base.select!{|x| x[:type] == :rth  }
          # to.map{    |x| [:high, :low, :volume].map{|z| x[z] = nil} if x[:block] }
        when :flow
          @base.reject!{|x| %i[ meow postmm postmm5 ].include?(x[:type]) }
          @base.
            map{ |x|
            [:high, :low, :volume].map{|z| x[z] = nil} unless x[:type] == :rth
            # [:high, :low, :volume].map{|z| x[z] = nil} if x[:block]
          }
        when :run
          @base.select!{|x| %i[ premarket rth postmarket ].include? x[:type]}
        else
          raise ArgumentError, "Unknown stencil/swap type '#{type}'"
        end
        @base.map!{|z| z.dup}

        @index = @base.index{|x| x[:datetime] == @datetime }
        @index -= 1 while %i[sow sod mpre mpost eod eow].include? @base[@index][:type]
        @datetime = @base[@index][:datetime]
        @zero  = @base[@index]
        counter = 0
        while @base[@index - counter] and @index - counter >= 0
          @base[@index - counter][:x] = counter
          counter += 1
        end
        counter = 0
        while @base[@index + counter] and @index + counter < @base.length
          @base[@index + counter][:x] = -counter
          counter += 1
        end
      end

=begin
      def dup
        Intraday_Stencil.new(
          debug:      @debug,
          interval:   @interval,
          swap_type:  @swap_type,
          datetime:   @datetime,
          stencil:    @base.map{|x| x.dup}
        )
      end
=end

      def zero
        @zero ||=  @base.find{|b| b[:x].zero? }
      end

      def apply(to: )
        offset = 0
        @base.each_index do |i|
          begin
            offset += 1 while to[i+offset][:datetime] < @base[i][:datetime]
          rescue
            # appending
            to << @base[i]
            next
          end
          if to[i+offset][:datetime] > @base[i][:datetime]
            # skipping
            offset -= 1
            next
          end
          # merging
          to[i+offset][:x] = @base[i][:x]
          to[i+offset][:type] = @base[i][:type]
        end
        # finally remove all bars that do not belong to the stencil (i.e. holidays)
        to.reject!{|x| x[:x].nil? }
      end

      def use(with:, sym:, zero:, grace: -2)
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
        swap[:current_diff]   = (swap[:current_value] - zero[ohlc]) * (high ? 1 : -1 )
        swap[:current_dist]   = (swap[:current_diff] / sym[:ticksize]).to_i
        swap[:exceeded]       =  zero[:datetime] if swap[:current_dist] < grace
        swap
      end
    end

  end

end
