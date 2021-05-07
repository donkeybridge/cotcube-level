def verbose_toggle
  irb_context.echo ? irb_context.echo = false : irb_context.echo = true
end

alias vt verbose_toggle

$debug = true
IRB.conf[:USE_MULTILINE] = false
# require 'bundler'
# Bundler.require

require_relative 'lib/cotcube-level'
