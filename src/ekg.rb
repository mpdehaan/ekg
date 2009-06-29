#!/usr/bin/ruby
#
# Copyright 2008, Red Hat, Inc
#
# This software may be freely redistributed under the terms of the GNU
# general public license.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

require 'getoptlong'
require 'active_record'

require 'grapher'
require 'scanner'
require 'kevinbacon'
require 'finder'
require 'db'

if File.exists?("/etc/ekg/settings"):
   # Use system default if possible
   config = "/etc/ekg/settings"
else
   # assume a local run
   config = "settings"
end

is_scanning = false
is_graphing = false
is_finding  = false
is_kevinbacon = false

opts = GetoptLong.new(
   [ "--config", "-c", GetoptLong::OPTIONAL_ARGUMENT ],
   [ "--scan",   "-s", GetoptLong::NO_ARGUMENT ],
   [ "--graph",  "-g", GetoptLong::NO_ARGUMENT ],
   [ "--find",   "-f", GetoptLong::NO_ARGUMENT ],
   [ "--kevinbacon", "-k", GetoptLong::NO_ARGUMENT ]
)

begin
   opts.each { |opt, arg|
      case opt
      when "--config"
         config_file = arg
      when "--scan"
         is_scanning = true
      when "--graph"
         is_graphing = true
      when "--find"
         is_finding =  true
      when "--kevinbacon"
         is_kevinbacon = true
      end
   }
rescue GetoptLong::InvalidOption => ex
   # Give a different exit code if we get an invalid option
   exit(2)
end

if not (is_scanning or is_graphing or is_finding or is_kevinbacon)
   puts "nothing to do"
   exit(1)
end

db = Db.new()
db.connect()
db.setup()

Scanner.new(config).run if is_scanning
Grapher.new(config).run if is_graphing
Finder.new(config).run  if is_finding
KevinBacon.new(config).run if is_kevinbacon

