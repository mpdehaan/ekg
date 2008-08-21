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
      @track_limit = @data["track_limit"]
   end

   def run()
      lists = Post.connection.select_values("select DISTINCT(list_id) from posts")
      lists.each do |list|
            prefix = File.open("prefix").read()
            postfix = File.open("postfix").read()
            buckets = {}
            buckets["other"] = 0
            posts = Post.connection.select_values("select COUNT(*) from posts where list_id = '#{list}'")[0].to_f()
            domains = Post.connection.select_values("select DISTINCT(from_domain) from posts where list_id='#{list}'")
            size = domains.length()
            domains.each do |domain|
                count = Post.connection.select_values("select count(*) from posts where list_id='#{list}' and from_domain='#{domain}'")[0].to_f()
                ratio = count / posts 
                puts "#{list} #{domain} #{count} #{ratio}"
                if ratio > @track_limit
                    buckets[domain] = count
                else
                    buckets["other"] = buckets["other"] + count
                end
            end
            File.open("graph_#{list}.html","w+") do |f|
                f.write(prefix)
                ctr = 0 
                size = buckets.keys().length()
                buckets.each do |key,value|
                    ctr = ctr + 1
                    #unless ctr == size:
                    f.write("{ label: \"#{key}\", data: #{value} },")
                    #else
                    #    f.write("{ label: \"#{key}\", data: #{value} }")
                    #end
                end
                f.write(postfix)
            end    
       end
   end

end
