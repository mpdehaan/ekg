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
      File.open("graphs.html","w+") do |f|
      prefix = File.open("prefix").read()
      postfix = File.open("postfix").read()
      f.write(prefix)
      lists.sort().each do |list|
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
            ctr = 0 
            f.write("\n")
            size = buckets.keys().length()
            #f.write("<div id='#{list}' style='overflow: auto; position:relative;height:350px;width:380px;'/>\n")

            # *** FIRST TABLE ROW (LIST NAME)
            f.write("<TR><TD>#{list}</TD>\n")

            # *** SECOND TABLE ROW (PIE GRAPH) 
            f.write("<TD><div id='#{list}' style='position:relative;height:350px;width:380px;'/>\n")

            f.write("<script type='text/javascript'>\n")
            f.write("var p = new pie();")
            buckets.sort{|a,b| a[1]<=>b[1]}.each do |key,value|
                unless key == "other" and value == 0
                    f.write("p.add('#{key}','#{value}');\n")
                end
            end
            f.write("p.render('#{list}','#{list}');\n")
            f.write("</script>\n<br/>\n</TD>\n")

            # *** THIRD TABLE ROW (LIST STATS)
            f.write("<TD>")
            f.write("<TABLE>")
            total = 0           
            buckets.sort{|a,b| a[1]<=>b[1]}.each do |key,value|
                unless key == "other" and value == 0
                    f.write("<TR><TD>#{key}</TD><TD>#{value.to_i}</TD></TR>\n")
                    total = total + value
                end
            end
            f.write("<TR><TD>total</TD><TD>#{total.to_i}</TD></TR>\n")
            f.write("</TABLE>")
            f.write("</TD>")

       end
       f.write(postfix)
       end
   end

end
