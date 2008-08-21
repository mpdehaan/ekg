#!/usr/bin/ruby

require 'getoptlong'
require 'active_record'

require 'grapher'
require 'scanner'
require 'db'

#config = "/etc/ekg/settings"
config = "settings" # until packaged

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

if not is_scanning and not is_graphing
   puts "nothing to do"
   exit(1)
end

db = Db.new()
db.connect()
db.setup()

Scanner.new(config).run if is_scanning
Grapher.new(config).run if is_graphing


