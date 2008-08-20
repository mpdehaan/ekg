require 'open-uri'
require 'date'
require 'hpricot' # yum install ruby-hpricot
require 'activerecord'

#       insert_record(url,subject,list,from_addr,from_domain,sent_date)
#
class Post < ActiveRecord::Base
   has_one  :post_url
   has_one  :post_subject
   has_one  :post_list
   has_one  :post_from_addr
   has_one  :post_from_domain
   has_one  :post_sent_date
end


class Scanner

   def initialize(config)
      File.open(config) { |yf|
         @data = YAML::load(yf)
      }
      @mailmen = @data["mailmen"]
      @lists = []
      if @data.has_key?("lists")
          @lists = @data["lists"]
      end

   end

   def run()
      # check mailmen to build up the lists of lists to scan
      scan_mailmen() 
      # scan lists explicitly listed in the config file, if any
      scan_lists()
   end

   def scan_lists()
      @lists.each { |list, list_config|
         (list_url, list_type) = list_config
         # url is like: https://www.redhat.com/mailman/listinfo/amd64-list
         if list_type == "default"
             list_url.sub!("mailman/listinfo", "archives")
         elsif list_type == "pipermail"
             list_url.sub!("mailman/listinfo", "pipermail")
         else
             raise "unknown mailman type: #{mailman_type}"
         end
         scan_index(list,list_url)
      }
   end

   def scan_mailmen()
      @mailmen.each { |mailman, mailman_config| 
         mailman_url, mailman_type = mailman_config
         puts "#{mailman} mailman: #{mailman_url}"
         doc = Hpricot(URI.parse(mailman_url).read())
         doc.search("a") { |link| 
            new_url = link.attributes["href"]
            if new_url.include?("mailman/listinfo")
               listname = new_url.split("/").slice(-1)
               #if mailman_type == "default"
               #    archives = new_url.sub("mailman/listinfo", "archives")
               #elsif mailman_type == "pipermail"
               #    archives = new_url.sub("mailman/listinfo", "pipermail")
               #else
               #    raise "unknown mailman type: #{mailman_type}"
               #end
               #
               #scan_index(listname, archives) 
               @lists[listname] = [new_url, mailman_type]
            end
         } 
      }
   end

   def scan_index(list,url)
      puts "#{list} index: #{url}"
      begin
          doc = Hpricot(URI.parse(url).read())
      rescue OpenURI::HTTPError
          puts "warning: could not access archives: #{url}"
          return
      end
      doc.search("a") { |link|
         new_url = link.attributes["href"]
         if new_url.include?("thread.html")
             puts "attributes: #{new_url}"
             scan_threads(list,"#{url}/#{new_url}")
         end
      }      

   end

   def scan_threads(list,url)
      puts "#{list} threads: #{url}"
      top = url.split("/").slice(0..-2).join("/") # FIXME
      doc = Hpricot(URI.parse(url).read())
      doc.search("a") { |link|
         if link.attributes.has_key?("href")
             url = link.attributes["href"]
             unless url.grep(/index.html|thread.html|date.html|author.html/).length() > 0
                 new_url = "#{top}/#{url}"
                 scan_message(link.inner_html,list,new_url)
             end
         end
      }
   end

   def scan_message(subject,list,url)
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
      puts "message #{url} subject #{subject} to #{list} from #{from_addr} on #{month} #{day} #{year}"

      post = Post.create(
         :post_url => url,
         :post_subject => subject,
         :post_list => list,
         :post_from_domain => from_domain,
         :post_from_addr => from_addr,
         :post_sent_date => sent_date
      )

      #insert_record(url,subject,list,from_addr,from_domain,sent_date)

   end

  
   

end


