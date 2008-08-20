require 'open-uri'
require 'date'
require 'hpricot' # yum install ruby-hpricot

class Scanner

   def initialize(config)
      @config = config
      @mailmen = config.data()["mailmen"]
      @lists = []
      if config.data().has_key?("lists")
          @lists = config.data()["lists"]
      end
   end

   def run()
      scan_lists()
      scan_mailmen() 
   end

   def scan_lists()
      @lists.each { |list, url|
         # url is like: https://www.redhat.com/mailman/listinfo/amd64-list
         url.sub!(/mailman\/listinfo/, "archives")
         scan_index(list,url)
      }
   end

   def scan_mailmen()
      @mailmen.each { |mailman, mailman_config| 
         mailman_url, mailman_type = mailman_config
         puts "#{mailman} mailman: #{mailman_url}"
         open(mailman_url) { |f| 
            f.read().scan(/"(https?:\/\/.*\/mailman\/listinfo\/.*)"/).each { |m|
               listname = m[0].split("/").slice(-1)
               if mailman_type == "default"
                   archives = m[0].sub(/mailman\/listinfo/, "archives")
               elsif mailman_type == "pipermail"
                   archives = m[0].sub(/mailman\/listinfo/, "pipermail")
               else
                   raise "unknown mailman type: #{mailman_type}"
               end
               scan_index(listname, archives) 
            }
         } 
      }
   end

   def scan_index(list,url)
      puts "#{list} index: #{url}"
      # url is like: https://www.redhat.com/archives/amd64-list
      open(url) { |f|
         f.read().scan(/="(\w+-\w+\/thread.html)"/).each { |m|
            scan_threads(list,"#{url}/#{m}")
         }
      }
   end

   def scan_threads(list,url)
      puts "#{list} thread: #{url}"
      # url is like: https://www.redhat.com/archives/amd64-list/2008-January/msg99999.html
      top = url.split("/").slice(0..-2).join("/") # FIXME
      open(url) { |f|
         matches = f.read().scan(/="(\w+\.html)"/).each { |m|
            unless m[0].include?("thread.html") or m[0].include?("date.html") or m[0].include?("author.html")
                new_url = "#{top}/#{m[0]}"
                scan_message(list,new_url)
            end
         }
      }
   end

   def scan_message(list,url)
      puts "#{list} message: #{url}"
      doc = Hpricot(URI.parse(url).read())
      from_addr = nil
      from_domain = nil
      sent_date = nil
      doc.search("a") { |link| 
          # at least for fedorahosted
          # if the href contains listinfo and the contents of the href contain "at" 
          # then the inner_html is the from address
          if link.attributes["href"] =~ /listinfo/
             tokens = link.inner_html.split()
             if tokens.length == 3 and tokens[1] == "at" and tokens[2] =~ /\./
                from_addr = "#{tokens[0]}@#{tokens[2]}"
                from_domain = tokens[2]
                break
             end
          end
      }
      doc.search("i") { |italics|
          # fedora hosted UTC date is in italics towards the top of the message
          if italics.inner_html =~ / UTC /
             sent_date = italics.inner_html
             break
          end
      }
      if from_addr.nil?
          doc.search("link") { |link|
              # redhat.com uses a LINK tag for the from address
              # with "@" just left as "@"
              if link.attributes["rev"] == "made"
                 from_addr = link.attributes["href"].sub("mailto:","")
                 from_domain = from_addr.split("@").slice(1)
              end
          }
      end
      if sent_date.nil?
          doc.search("li") { |li|
              # redhat.com uses a <em>Date:</em>: string
              # which is in local time with offset
              if li.inner_html =~ /<em>Date/
                  sent_date = li.inner_html.sub("<em>Date</em>:","").strip()
              end
          }
      end   

      sent_date = Date.parse(sent_date)
      month, day, year = sent_date.month, sent_date.day, sent_date.year

      # FIXME: here's where we'd make the database insert
      puts "message to #{list} from #{from_addr} on #{month} #{day} #{year}"

   end

end


