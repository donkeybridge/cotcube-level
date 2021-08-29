# frozen_string_literal: true
#

require 'active_support'
require 'active_support/core_ext/time'
require 'active_support/core_ext/numeric'
require 'colorize'
require 'date'    unless defined?(DateTime)
require 'csv'     unless defined?(CSV)
require 'yaml'    unless defined?(YAML)
require 'json'    unless defined?(JSON)
require 'digest'  unless defined?(Digest)
require 'cotcube-helpers'

%w[ eod_stencil intraday_stencil detect_slope tritangulate helpers].each do |part|
  require_relative "cotcube-level/#{part}"
end

module Cotcube
  module Level

    PRECISION = 16
    INTERVALS = %i[ daily continuous hours halfs ]
    SWAPTYPES = %i[ full ]
    TIMEZONES = { 'CT' => Time.find_zone('America/Chicago'),
                  'DE' => Time.find_zone('Europe/Berlin')    }
    GLOBAL_SOW = { 'CT' => '0000-1700' }
    GLOBAL_EOW = { 'CT' => '1700-0000' }
    GLOBAL_EOD = { 'CT' => '1600-1700' }

    #module_function :init, # checks whether environment is prepared and returns the config hash
    module_function :detect_slope,    # in detect_slope.rb
                    :tritangulate,     # in tritangulate.rb
                    :shear_to_deg,    # in helpers.rb
                    :shear_to_rad,    # same all below
                    :rad2deg,
                    :deg2rad,
                    :puts_swap,
                    :save_swaps,
                    :get_jsonl_name,
                    :load_swaps,
                    :check_exceedance,
                    :member_to_human
    
    # please note that module_functions of sources provided in non-public files must slso be published within these
  end
end

