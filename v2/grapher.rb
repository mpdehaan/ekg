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
      lists = Post.connection.select_values("select DISTINCT(list_id) from posts")
      lists.each do |list|
            domains = Post.connection.select_values("select DISTINCT(from_domain) from posts where list_id='#{list}'")
            domains.each do |domain|
               count = Post.connection.select_values("select count(*) from posts where list_id='#{list}' and from_domain='#{domain}'")
               puts "#{list} #{domain} #{count}"
            end
      end
   
   end

end
