# frozen_string_literal: true
#

module Kernel
  alias deep_freeze freeze
  alias deep_frozen? frozen?
end

module Enumerable
  def deep_freeze
    if !@deep_frozen
      each(&:deep_freeze)
      @deep_frozen = true
    end
    freeze
  end

  def deep_frozen?
    !!@deep_frozen
  end
end

#

require 'active_support'
require 'active_support/core_ext/time'
require 'active_support/core_ext/numeric'
require 'colorize'
require 'date'    unless defined?(DateTime)
require 'csv'     unless defined?(CSV)
require 'yaml'    unless defined?(YAML)
require 'cotcube-helpers'



# require_relative 'cotcube-level/filename



module Cotcube
  module Level
    include Helpers

    # module_function :init, # checks whether environment is prepared and returns the config hash
    
    # please note that module_functions of sources provided in private files must slso be published within these
  end
end

