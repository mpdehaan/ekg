# Copyright 2008, Red Hat, Inc
#
# This software may be freely redistributed under the terms of the GNU
# general public license.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

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
   end

   def run()
      # main entry point
      # check mailmen to build up the lists of lists to scan
      # the scan lists explicitly listed in the config file, if any
      scan_lists()
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
         scan_archives(list,list_url,list_count,lists_size,hits,list_type)
         list_count = list_count + 1
      }
   end

   def scan_archives(list,url,list_count,lists_size,hits,list_type)
      # read a mailing archives page to find the threads listed on that page
      mon_count = 1
      puts "#{list} archives page is: #{url}"
      begin
          doc = Hpricot(URI.parse(url).read())
      rescue OpenURI::HTTPError
          puts "warning: could not access archives: #{url}"
          return
      end
      doc.search("a") { |link|
         new_url = link.attributes["href"]
         if new_url.include?("thread.html")

             thread_url = "#{url}/#{new_url}"

             scan_this = false
             if mon_count != 1
                found = Scan.connection.select_values("select COUNT(*) from scans where url = \"#{thread_url}\"")[0].to_i()
                scan_this = true if found == 0
             end

             if (mon_count == 1) || (scan_this)
                 scan_threads(list,"#{url}/#{new_url}",list_count,lists_size,mon_count,hits,list_type)
             end

             # flag that we are done scanning the month if this month is not THIS month
             if mon_count != 1
                 flag = Scan.create(
                     :url => "#{url}/#{new_url}"
                 )
             end 

             mon_count = mon_count +1
         end
         if mon_count > @limit_months:
             return
         end
      }      

   end

   def scan_threads(list,url,list_count,lists_size,mon_count,hits,list_type)
      # read a given month's archives page to find the messages within
    
      count = 0
      top = url.split("/").slice(0..-2).join("/") # FIXME
      puts "scanning threads page: #{url}"
      begin
          doc = Hpricot(URI.parse(url).read())
      rescue OpenURI::HTTPError
          puts "warning: could not access threads: #{url}"
          return
      end

      Post.transaction do
          doc.search("a") do |link|
              if link.attributes.has_key?("HREF") or link.attributes.has_key?("href")
                  new_url = link.attributes["HREF"]
                  if new_url.nil?
                     new_url = link.attributes["href"]
                  end
                  # puts "considering URL = #{new_url}"
                  if new_url =~ /\.html$/ and new_url !~ /\.\.|thread\.html|date\.html|author\.html/
                      unless new_url =~ /^http/
                         new_url = "#{top}/#{new_url}"
                      end
                      count = count + 1 
                      if (count % 20 == 0)
                         puts "#{list} (list #{list_count}/#{lists_size} month #{mon_count}/#{@limit_months}) post #{count}"
                      end
                      # puts "here is a thread URL: #{link.inner_html}"
                      scan_message(link.inner_html,list,new_url,list_count,lists_size,mon_count,count,list_type)
                  end
              end
          end
      end

   end

   def scan_message(subject,list,msg_url,list_count, lists_size,mon_count,count,list_type)
      # puts msg_url
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

      if from_domain.nil? and list_type != "pipermail"
          # puts "looking for domain"
          doc.search("link") { |link| 
              # FIXME: @redhat.com specific
              # puts "link=#{link}" 
              if link.attributes["HREF"] =~ /listinfo|mailto/
                  tokens = link.attributes["HREF"].split(":")
                  from_addr = tokens[1]
                  from_domain = tokens[1].split("@")[-1]
                  break
              end
          }
      end

      if from_domain.nil?
          # looks like Fedora Hosted then
          doc.search("a") { |link|
              if link.attributes["HREF"] =~ /lists\.fedorahosted\.org/
                  tokens = link.inner_html.split(" at ")
                  if tokens.length == 2
                     tokens[0] = tokens[0].strip()
                     tokens[1] = tokens[1].strip()
                     from_addr = "#{tokens[0]}@#{tokens[1]}"
                     from_domain = tokens[1]
                     break
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
      if sent_date.nil?
          doc.search("li") { |li|
              # redhat.com uses a <em>Date:</em>: string
              # which is in local time with offset
              if li.inner_html =~ /<em>Date/
                  sent_date = li.inner_html.sub("<em>Date</em>:","").strip()
                  break
              end
          }
      end   
      if sent_date.nil?
          doc.search("i") { |it|
              # jboss lists have other date data, fun!
              if it.inner_html =~ /(Mon|Tue|Wed|Thu|Fri|Sat|Sun)/
                  sent_date = it.inner_html
                  break
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

      raise "error, bad from_domain: #{from_domain}" if from_domain.nil?

      if (ok == 1)
          #begin
          #puts "sent_date is #{sent_date}"
          #puts "list is #{list}"
          #puts "subject is #{subject}"
          insert_record(msg_url,subject,list,from_domain,from_addr,sent_date)
          #rescue
          #    puts "insert fail: url=(#{msg_url}) subject=(#{subject}) list=(#{list}) domain=(#{from_domain}) from_addr=(#{from_addr}) sent_date=(#{sent_date})"
          #end
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
      # Post.connection.execute(stmt)

   end

end
