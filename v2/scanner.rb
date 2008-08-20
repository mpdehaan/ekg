require 'open-uri'

class Scanner

   def initialize(config)
      @config = config
      @lists = config.data()["lists"]
   end

   def run()
      @lists.each { |list, url|
         # url is like: https://www.redhat.com/mailman/listinfo/amd64-list
         url.sub!(/mailman\/listinfo/, "archives")
         scan_months(list,url)
      } 
   end


   def scan_months(list,url)
      puts "#{list} index: #{url}"
      # url is like: https://www.redhat.com/archives/amd64-list
      open(url) { |f|
         matches = f.read().scan(/"(.*thread.html)"/).each { |m|
            scan_threads(list,"#{url}/#{m}")
         }
      }
   end

   def scan_threads(list,url)
      puts "#{list} thread: #{url}"
      # url is like: https://www.redhat.com/archives/amd64-list/2008-January/msg99999.html
      top = url.split("/").slice(0..-1).join("/")
      open(url) { |f|
         matches = f.read().scan(/"(msg.*\.html)"/).each { |m|
            scan_message(list,"#{top}/#{m}")
         }
      }
   end

   
   def scan_message(list,url)
      puts "#{list} message: #{url}"
   end
end


