require 'db'

require 'open-uri'
require 'date'
require 'hpricot' 
require 'activerecord'

class Grapher

   def initialize(config)
      # get the list of mailmen indexes and individual lists to scan
      # from the config file
      File.open(config) { |yf|
         @data = YAML::load(yf)
      }
      @track_domains = @data["track_domains"]
   end

   def run()
      puts "grapher not implemented yet"
   end
