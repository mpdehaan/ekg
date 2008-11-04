require 'db'

require 'open-uri'
require 'date'
require 'hpricot' 
require 'activerecord'

class Scanner

   def initialize(config)
      # get the list of mailmen indexes and individual lists to scan
      # from the config file
      File.open(config) { |yf|
         @data = YAML::load(yf)
      }
      # FIXME the mailmen scanning feature is probably not working now
      # because we have code references to explicit_lists.  This is ok.
      @mailmen = @data["mailmen"]
      @lists = @data["explicit_lists"]
      @start_time = DateTime.now()
      @month = @start_time.strftime("%B")
      @year = @start_time.year
      @year_month = "#{@year}-#{@month}"
      @limit_months = @data["limit_months"]
      @scan_mailmen = @data["scan_mailmen"]
   end

   def run()
      # main entry point
      # check mailmen to build up the lists of lists to scan
      # the scan lists explicitly listed in the config file, if any
      scan_mailmen() if @scan_mailmen ==1
      scan_lists()
   end
   
   def scan_mailmen()
      # find all the listinfo pages by reading the mailman page 
      @mailmen.each { |mailman, mailman_config| 
         mailman_url, mailman_type = mailman_config
         puts "#{mailman} mailman: #{mailman_url}"
         doc = Hpricot(URI.parse(mailman_url).read())
         doc.search("a") { |link| 
            new_url = link.attributes["href"]
            if new_url.include?("mailman/listinfo")
               listname = new_url.split("/").slice(-1)
               @lists[listname] = [new_url, mailman_type]
            end
         } 
      }
   end

   def scan_lists()
      # for each list we know we need to index, find the archives URL
      # and then request scanning of the archives
      list_count = 1
      lists_size = @lists.length()
      @lists.each { |list, list_config|
         hits = Post.connection.select_values("select url from posts where list_id = '#{list}'")
         (list_url, list_type) = list_config
         # url is like: https://www.redhat.com/mailman/listinfo/amd64-list
         if list_type == "default" or list_type == ""
             list_url.sub!("mailman/listinfo", "archives")
         elsif list_type == "pipermail" or list_type == "jboss"
             list_url.sub!("mailman/listinfo", "pipermail")
         else
             raise "unknown mailman type: #{list_type}"
         end
         puts "list #{list_count}/#{lists_size}"
         scan_archives(list,list_url,list_count,lists_size,hits)
         list_count = list_count + 1
      }
   end

   def scan_archives(list,url,list_count,lists_size,hits)
      # read a mailing archives page to find the threads listed on that page
      mon_count = 1
      puts "#{list} threads: #{url}"
      begin
          doc = Hpricot(URI.parse(url).read())
      rescue OpenURI::HTTPError
          puts "warning: could not access archives: #{url}"
          return
      end
      doc.search("a") { |link|
         new_url = link.attributes["href"]
         if new_url.include?("thread.html")
             scan_threads(list,"#{url}/#{new_url}",list_count,lists_size,mon_count,hits)
             mon_count = mon_count +1
         end
         if mon_count > @limit_months:
             return
         end
      }      

   end

   def scan_threads(list,url,list_count,lists_size,mon_count,hits)
      # read a given month's archives page to find the messages within

      count = 0
      top = url.split("/").slice(0..-2).join("/") # FIXME
      puts "scanning: (thread) #{url}"
      begin
          doc = Hpricot(URI.parse(url).read())
      rescue OpenURI::HTTPError
          puts "warning: could not access threads: #{url}"
          return
      end
      doc.search("a") { |link|
         if link.attributes.has_key?("href")
             new_url = link.attributes["href"]
             unless new_url.grep(/https:|http:|txt.gz|index.html|thread.html|date.html|author.html/).length() > 0
                 new_url = "#{top}/#{new_url}"
                 count = count + 1 
                 if not hits.grep(new_url).length() > 0
                     scan_message(link.inner_html,list,new_url,list_count,lists_size,mon_count,count)
                 end
             end
         end
      }
   end

   def scan_message(subject,list,msg_url,list_count, lists_size,mon_count,count)

      
      puts "#{list} (#{list_count}/#{lists_size} #{mon_count}/#{@limit_months}) post #{count}"

      begin
          doc = Hpricot(URI.parse(msg_url).read())
      rescue OpenURI::HTTPError
          puts "warning: could not access message: #{msg_url}"
          return
      end

      from_addr = nil
      from_domain = nil
      sent_date = nil


      # hack: some jboss lists show the email as do-not-reply@jboss.com
      # so we can only tell if someone there does /not/ have their mail
      # filtered out, so we get "less good" stats
      #

      if @lists[list][1] == "jboss" 
         doc.search("b") { |link|
             tokens = link.inner_html.split()
             if tokens.length == 3 and tokens[1] == "at" and tokens[2] =~ /\./
                 from_addr = "#{tokens[0]}@#{tokens[2]}"
                 from_domain = tokens[2]
                 break
             end
         }
      end

      if from_domain.nil?
          doc.search("a") { |link| 
              # at least for fedorahosted
              # if the href contains listinfo and the contents of the href contain "at" 
              # then the inner_html is the from address
              if link.attributes["href"] =~ /listinfo|mailto/
                  tokens = link.inner_html.split()
                  if tokens.length == 3 and tokens[1] == "at" and tokens[2] =~ /\./
                      if link.inner_html =~ /do-not-reply/
                          from_addr = "other@do-not-reply"
                          from_domain = "do-not-reply"
                          break
                      else
                          from_addr = "#{tokens[0]}@#{tokens[2]}"
                          from_domain = tokens[2]
                          break
                      end
                  end
              end
          }
      end

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
      if sent_date.nil?
          doc.search("i") { |it|
              # jboss lists have other date data, fun!
              if it.inner_html =~ /(Mon|Tue|Wed|Thu|Fri|Sat|Sun)/
                  sent_date = it.inner_html
              end
          }
      end
      if sent_date.nil?
          puts "totally failed to figure out the date"
      end

      ok = 1
      begin
          sent_date = Date.parse(sent_date)
          month, day, year = sent_date.month, sent_date.day, sent_date.year
      rescue
          ok = 0
          puts "date fail! #{sent_date}"
      end

      if (ok == 1)
          begin
              insert_record(msg_url,subject,list,from_domain,from_addr,sent_date)
          rescue
              puts "insert fail: url=(#{msg_url}) subject=(#{subject}) list=(#{list}) domain=(#{from_domain}) from_addr=(#{from_addr}) sent_date=(#{sent_date})"
          end
      end

   end

   def insert_record(url,subject,list,from_domain,from_addr,sent_date)

      post = Post.create(
         :url => url,
         :subject => subject,
         :list_id => list,
         :from_domain => from_domain,
         :from_addr => from_addr,
         :sent_date => sent_date
      )
   end

  
   

end


