#!/usr/bin/ruby

# ruby standard
require 'getoptlong'

# our stuff
require 'grapher'
require 'scanner'
require 'active_record'

config = "/etc/ekg/settings"
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

ActiveRecord::Base.establish_connection(
   :adapter => "sqlite3",
   :dbfile  => "ekg_db"
)

# FIXME: only do this if table does not exist

begin
    ActiveRecord::Schema.define do
        create_table :posts do |table|
            table.column :post_url, :string
            table.column :post_subject, :string
            table.column :post_list, :string
            table.column :post_from_domain, :string
            table.column :post_from_addr, :string
            table.column :post_sent_date, :date
       end
    end
rescue
   puts "using existing database"
end

class Post < ActiveRecord::Base
  belongs_to :posts
end

Scanner.new(config).run if is_scanning
Grapher.new(config).run if is_graphing


