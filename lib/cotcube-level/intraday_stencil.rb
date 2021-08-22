module Cotcube
  module Level
    class Intraday_Stencil

      GLOBAL_SOW = { 'CT' => '0000-1700' }
      GLOBAL_EOW = { 'CT' => '1700-0000' }
      GLOBAL_EOD = { 'CT' => '1600-1700' }


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

      # asset:    the asset the stencil will be applied to--or :full, if default stencil is desired
      # datetime: the datetime that will become 'zero'. 
      #           it will be calculated to the beginning of the previous interval
      #           it must match the timezone of the asset
      # interval: the interval as minutes
      # weeks:    the amount of weeks before the beginning of the current week
      # future:   the amount of weeks after  the beginning of the current week
      def initialize(asset:, sym: nil, datetime:, interval:, weeks:, future: 1, debug: false, type:, base: )
        @shiftset = Intraday_Stencils.shiftset(asset: asset)
        @timezone = TIMEZONES[@shiftset[:tz]]
        @debug    = debug
        datetime  = @timezone.at(datetime.to_i) unless datetime.is_a? ActiveSupport::TimeWithZone
        # slight flaw, as datetime does not carry the actuall timezone information but just the abbr. timezone name (like CDT or CEST)
        raise "Zone mismatch: Timezone of asset is #{@timezone.now.zone} but datetime given is #{dateime.zone}" unless @timezone.now.zone == datetime.zone
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
        self.apply to: base, type: type
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
        @base.select!{|z| z[:x] <= 0 or z[:high]}
      end

      def apply!(to:, type:) 
        apply(to: to, type: type, force: true)
      end

      # :force will apply values to each bar regardless of existing ones
      def apply(to:, type:, force: false, debug: false)
        offset = 0
        to.each_index do |i|
          begin
            offset += 1 while @base[i+offset][:datetime] < to[i][:datetime]
            puts "#{i}\t#{offset}\t#{@base[i+offset][:datetime]} < #{to[i][:datetime]}" if debug
          rescue
            # appending
            puts "appending #{i}\t#{offset}\t#{@base[i+offset][:datetime]} < #{to[i][:datetime]}" if debug
            @base << to[i]
            next
          end
          if @base[i+offset][:datetime] > to[i][:datetime]
            # skipping
            puts "skipping #{i}\t#{offset}\t#{@base[i+offset][:datetime]} < #{to[i][:datetime]}" if debug
            offset -= 1
            next
          end
          # merging
          j = i + offset
          @base[j]=@base[j].merge(to[i]) if force or (@base[j][:high].nil? and @base[j][:low].nil?)
          puts "MERGED:\t#{i}\t#{offset}\t#{@base[j]}" if debug
        end
        # finally remove all bars that do not belong to the stencil (i.e. holidays)
        case type
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
      end

    end

    Intraday_Stencils = Intraday_Stencil
  end
end
