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

class KevinBacon

    def initialize(config)

        # get the list of mailmen indexes and individual lists to process
        # from the config file

        File.open(config) { |yf|
           @data = YAML::load(yf)
        }
        File.open("kevinbacon_settings") { |kb|
           @kb = YAML::load(kb)
        }
        @track_limit = @data["track_limit"]
        @listdata = @data["explicit_lists"]

    end

    # ====================================================
    
    def compute(lists, outfile)

        outfile.write("graph EKGLinkage {\n")
       
        gravity = {}
        linkage = {}
        gravity.default = 0
        linkage.default = 0
        pos1 = 0
        set1 = @kb['explicit_lists'].keys().sort().clone()
        set2 = set1.clone()
        set1.each() do |list1|
           pos1 = pos1 + 1
           pos2 = 0 
           set2.each() do |list2|
              pos2 = pos2 + 1
              if list1.casecmp(list2) == -1
                  chrono = "#{pos1}/#{pos2}"
                  posters1 = Post.connection.select_values("select distinct from_addr from posts where list_id='#{list1}'")
                  posters2 = Post.connection.select_values("select distinct from_addr from posts where list_id='#{list2}'")
                  intersection = posters1 & posters2
                  weight = intersection.length()
                  puts "#{chrono}: #{list1} * #{list2} =  #{intersection.length()}"
                  lname1 = list1.gsub("-","_")
                  lname2 = list2.gsub("-","_")
                  if weight > @kb["minimum_score"]
                      gravity[lname1] = gravity[lname1] + weight
                      gravity[lname2] = gravity[lname2] + weight 
                      linkage["#{lname1} -- #{lname2}"] = weight
                  end
              end
           end
        end
        gravity.each_pair do |list, force|
           puts "#{list} has gravity #{force}"
           outfile.write("#{list} [label=\"#{list} (#{force})\"]\n")
           outfile.write("\n")
        end
        linkage.each_pair do |combo, force|
           (list1,list2) = combo.split("-")
           outfile.write(combo)
           outfile.write(" [ weight=#{force}, label=\"#{force}\"]\n")
        end

        outfile.write("}\n")
        puts "---"
        puts "done."
        puts "now run: dot kevinbacon.gv -Tsvg -o kevinbacon.svg"
    end

    def run()
        lists = Post.connection.select_values("select DISTINCT(list_id) from posts")
        File.open("kevinbacon.gv","w+") { |f|
           compute(lists,f)
        }
     end

end
