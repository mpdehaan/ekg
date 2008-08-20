#!/usr/bin/ruby

# ruby standard
require 'getoptlong'

# our stuff
require 'config'
require 'grapher'
require 'scanner'

#config_file = "/etc/ekg/settings"
config_file = "settings" # until packaged

is_scanning = true
is_graphing = false

opts = GetoptLong.new(
   [ "--config", "-c", GetoptLong::OPTIONAL_ARGUMENT ],
   [ "--noscan", "-n", GetoptLong::NO_ARGUMENT ],
   [ "--graph",  "-g", GetoptLong::NO_ARGUMENT ]
)

opts.each { |opt, arg|
   case opt
   when "config"
      config_file = arg
   when "noscan"
      is_scanning = false
   when "graph"
      is_graphing = true
   end
}

config = Config.new(config_file)

if not is_scanning and not is_graphing
   puts "nothing to do"
   exit(1)
end

Scanner.new(config).run if is_scanning
Grapher.new(config).run if is_graphing


