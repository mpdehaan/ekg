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
require 'gchart/lib/gchart.rb'

class Grapher

    def initialize(config)

        # get the list of mailmen indexes and individual lists to process
        # from the config file

        File.open(config) { |yf|
           @data = YAML::load(yf)
        }
        @track_limit = @data["track_limit"]
        @listdata = @data["explicit_lists"]

    end

    # ===================================================================

    def month_sort(a,b)

        # given two dates, ex 2008-10 and 2008-07, sort them in increasing chronological order

        m1,m2 = a.split("-")
        m3,m4 = b.split("-")
        return 1000 * m1.to_i + m2.to_i <=> 1000 * m3.to_i + m4.to_i

    end

    # ===================================================================

    def compute_time_dataset(list,months)

        # return an array of arrays containing the following graphs over time
        # total posts on list per month
        # total posts on list from redhat.com/jboss.com and other known internal mailing addrs
        # total posts from outside mailing addrs

        inside_data  = []
        outside_data = []
        total_data   = []

        inside_ttl   = 0
        outside_ttl  = 0
        total_ttl    = 0

        # puts months

        last = 0
        months.each { |month|
            puts "this month: #{month}"

            # sent-dates are unreliable since they come from the mail client
            # so we use the URL! 

            query = "select url from posts p where list_id == '#{list}' and url like '%/#{month}/%'"
            outside_query = query + " and from_domain <> 'jboss.org' and from_domain <> 'jboss.com' and from_domain <> 'redhat.com'"
            #puts query
            #puts outside_query 

            month_ct   = Post.connection.select_values(query).length()
            outside_ct = Post.connection.select_values(outside_query).length()
            inside_ct  = month_ct - outside_ct
            #puts "month=#{month}, posts=#{month_ct}, inside=#{inside_ct}, outside=#{outside_ct}"

            if (outside_ct > month_ct)
               raise "something wrong here"
            end

            inside_data  << inside_ct
            outside_data << outside_ct
            total_data   << month_ct

            inside_ttl    = inside_ttl  + inside_ct
            outside_ttl   = outside_ttl + outside_ct
            total_ttl     = total_ttl   + month_ct

            last = month_ct

        }
        dataset = [ total_data, inside_data, outside_data ]
        return total_ttl, inside_ttl, outside_ttl, dataset, last

    end

    # ===================================================================

    def compute_time_dataset2(list,months)

      # return an array of arrays containing the following graphs over time

      # total unique posters on list per month in tracked domain A
      # total unique posters on list per month in tracked domain B (etc)
      # total unique posters outside of tracked domains

      inside_data  = []

      inside_ttl   = 0

      # puts months

      domains = @data['colors'].keys().sort()

      results = {}


      months.each { |month|

        query = "select distinct from_addr, from_domain from posts p where list_id = '#{list}' and url like '%/#{month}/%'"
        result = Post.connection.select_rows(query)
        total_ct = result.length


        puts "this month: #{month}"

        color_tags = @data['colors']

        tracked = 0
        color_tags.each do |domain, color|
          if not results.has_key?(domain)
            results[domain] = []
          end

          count = result.select do |row| row[1] == domain end.length

          results[domain] << count

          tracked += count


        end

        print "total = #{total_ct}"
        print "tracked = #{tracked}"

        untracked = total_ct - tracked
        print "untracked = #{untracked}"
        results['other'] = [] if not results.has_key?("other")
        results['other'] << untracked


      }
      return results

    end


    # ===================================================================

    def compute_months()

        return @data["report_months"]

    end

    # ===================================================================
 
    def compute_pie_dataset(buckets)

        # convert the bucket data into the format needed by the chart package

        labels = []
        values = []
        buckets.sort{|a,b| b[1]<=>a[1]}.each do |key,value|
            unless key == "other" and value == 0
                labels << key
                values << value
            end
        end

        return [labels, values]

    end
   
    # ===================================================================

    def compute_buckets(list,domains,posts)
       
        # on a given mailing list split the posts out by each domain they are a part of
        # and get the count of each seperate domain
       
        buckets = {}
        buckets["other"] = 0
        # go through all the posts and see which domains are the highest
        size = domains.length()
      counts = Post.connection.select_rows("select from_domain, count(id) from posts where list_id='#{list}' group by from_domain")
      counts = Hash[*counts.flatten]
        domains.each do |domain|
#             count = Post.connection.select_values("select count(*) from posts where list_id='#{list}' and from_domain='#{domain}'")[0].to_f()
        count = counts[domain].to_f
            ratio = count / posts
            puts "#{list} #{domain} #{count} #{ratio}"
            perc = (ratio * 1000).to_i() / 10
            if ratio > @track_limit
                buckets["#{domain} (#{count.to_i}/#{perc}%)"] = count.to_i
            else
                buckets["other"] = buckets["other"] + count.to_i
            end
        end
        other_ct = buckets["other"].to_i
        buckets.delete("other")
        ratio = other_ct / posts
        perc = (ratio * 1000).to_i() / 10
        buckets["other (#{other_ct.to_i}/#{perc}%)"] = other_ct
        return buckets

    end

    # ===================================================================

    def get_lists()

        # what lists have we scanned?

        return Post.connection.select_values("select DISTINCT(list_id) from posts")

    end

    # ===================================================================

    def get_post_count_from_list(list)

        # how many posts on this mailing list for the entire life of the scan?

        return Post.connection.select_values("select COUNT(*) from posts where list_id = '#{list}'")[0].to_f()

    end

    # ===================================================================

    def get_domains_from_list(list)

        # which domains have posted on this list?

        return domains = Post.connection.select_values("select DISTINCT(from_domain) from posts where list_id='#{list}'")

    end

    # ===================================================================

    def get_identity_cell(listurl,list)
 
        # return a table element that shows what this mailing list is, that links to it, and shows
        # where it is being hosted

        lpostfix = ""
        lpostfix = "(FH)" if @listdata[list][0] =~ /fedorahosted/
        lpostfix = "(J)"  if @listdata[list][0] =~ /jboss/
        lpostfix = "(R)"  if @listdata[list][0] =~ /redhat.com/
        lpostfix = "<font size='-2'>#{lpostfix}</font>"
        return "<TD><font size='-1'><A HREF=\"#{listurl}\">#{list}#{lpostfix}</font></A></TD>\n"

    end

    # ===================================================================

    def colorize(labels)
      colors = []
      color_tags = @data['colors']
      labels.each do |label|
        col_found = false # i don't know how to break loops in Ruby yet -ynemoy
        color_tags.each_pair do |dom, color|
          if (label =~ Regexp.new(dom) and not col_found)
            colors << color
            col_found = true
          end
        end
        if (not col_found)
          colors << "AAAAAA"
        end
      end
      return colors
    end

   # ===================================================================

   def get_mix_cell(buckets,list)

         # generate a pie graph cell showing the mix of folks contributing on this list, showing
         # what domains are most active.

         buf = "<TD>\n"
         # figure out the data we need to build the google chart
         labels, values = compute_pie_dataset(buckets)
         colors = colorize(labels)
         # write the google chart
         chart = Gchart.pie(
             :data => values, 
             :title => '', 
             :size => '550x300', 
             :labels => labels,
             :line_colors => colorize(labels)
         )
         buf = buf + "<IMG SRC='#{chart}'/></TD>"
         return buf
    end

    # ===================================================================

    def get_time_cell(list,months)

         # generate a graph cell showing the activity over time for a mailing list, month by month

         total_ct, inside_ct, outside_ct, dataset, last_ct = compute_time_dataset(list,months)

         # HACK -- print list, inside, outside, total for grepping
         # 
         # should we move this to a reporter module or make a seperate flag to the grapher that outputs text
         # instead, or also generate a seperate report at the same time as the HTML page? -- MPD

         puts "dashlist #{list}"
         puts "dashinside #{inside_ct}"
         puts "dashoutside #{outside_ct}"
         puts "dashtotal #{total_ct}"

         avg = total_ct / months.length()

         month_chart = Gchart.line(
             :title => '', 
             :data => dataset,
             :legend => ["combined (total=#{total_ct}, avg=#{avg}, last=#{last_ct})","inside (#{inside_ct})","outside (#{outside_ct})"],
             :size => '400x300',
             :line_colors => [ "000000", "ff0000", "0000ff" ],
             :axis_labels => months   
         )
 
         base = "<TD><IMG SRC='#{month_chart}'/>"

         perc = ((avg - last_ct + 0.0).abs() / (avg + 0.0)) * 100
         perc = perc.to_i()

         if avg > last_ct
            base = base + "<br/>DECREASED #{perc}% posts vs average"
         else
            base = base + "<br/>INCREASED #{perc}% posts vs average"
         end

         return base + "</TD>"

    end

    # ===================================================================
    

    def get_time_cell2(list,months)

         # generate a graph cell showing unique posters per tracked domain per month

         results = compute_time_dataset2(list,months)

         # make sure the colors are in the right order
         colors = []
         points = []
         legends = []
         results.each_pair do |domain, values|
             points << values
             if domain == 'other'
                 colors << "AAAAAA"
             else
                 colors << @data['colors'][domain]
             end
             sum = 0
             nonzero = 0
             values.each { |x|
                sum = sum + x
                if x !=0
                   nonzero = nonzero + 1
                end
             }
             last = values[-1]
             if nonzero != 0
                 avg = sum / nonzero
             else
                 avg = "?"
             end
             legends << "#{domain} (total=#{sum}, avg=#{avg}, last=#{last})" # FIXME: include total count here
         end

         month_chart = Gchart.line(
             :title => '', 
             :data => points,
             :legend => legends,
             :size => '400x300',
             :line_colors => colors,
             :axis_labels => months   
         )
 
         return "<TD><IMG SRC='#{month_chart}'/></TD>"

    end

    # ===================================================================

    def each_list(list, months)

      begin
        listurl = @data['explicit_lists'][list][0]
      rescue
        return
      end

      posts   = get_post_count_from_list(list)
      domains = get_domains_from_list(list)
      buckets = compute_buckets(list,domains,posts)

      primary_table = Array.new
      primary_table << "<TR>" <<
        get_identity_cell(listurl, list) <<
        get_mix_cell(buckets,list) <<
        get_time_cell(list,months) <<
        get_time_cell2(list,months) <<
        "</TR>"
      primary_table.each do |line| yield line end
    end

    # ===================================================================

    def run()

        # what are all of the lists we want to index?
        lists = get_lists()
        # what months are we running reports on?
        months = compute_months()

        # open the output graph and generate a section for each list
        File.open("graphs.html","w+") do |f|
           f.write(File.open("prefix").read())
           lists.sort().each do |list|
              each_list(list, months) do |x| f.write x end
           end
           f.write(File.open("postfix").read())
        end

     end


end
