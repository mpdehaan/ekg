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
    
    def subcompute(list1, list2, domain, multiplier, gravity, linkage, color)
 
       search = "='#{domain}'"
       if domain != "other"
           query = "from_domain#{search}"
       else
           #query = "from_domain <> 'redhat.com' and from_domain <> 'googlemail.com' and from_domain <> 'gmail.com' and from_domain <> 'fedoraproject.org' and from_domain <> 'jboss.com' and from_domain <> 'jboss.org'"
           query = "from_domain <> 'redhat.com'"
       end
       
       posters1 = Post.connection.select_values("select distinct from_addr from posts where list_id='#{list1}' and #{query}")
       posters2 = Post.connection.select_values("select distinct from_addr from posts where list_id='#{list2}' and #{query}")
       intersection = posters1 & posters2
       weight = intersection.length()
       puts "          #{list1} * #{list2} =  #{intersection.length()} on #{domain}"
       lname1 = list1.gsub("-","_")
       lname2 = list2.gsub("-","_")
       gravity[lname1] = gravity[lname1] + weight
       gravity[lname2] = gravity[lname2] + weight
       if weight >= @kb["minimum_score"]
           linkage["#{lname1}--#{lname2}"] = "#{weight}-#{color}"
       end
    end

    # ====================================================
    
    def compute(lists, outfile)

        outfile.write("digraph EKGLinkage {\n")
 
        gravity = {}
        linkage = {}
        gravity.default = 0
        linkage.default = 0
        pos1 = 0
        set1 = @kb['explicit_lists'].keys().sort().clone()
        set2 = set1.clone()
        set1.each() do |l1|
           pos1 = pos1 + 1
           pos2 = 0 
           set2.each() do |l2|
              pos2 = pos2 + 1
              puts "#{pos1}/#{pos2}"
              # development code to stop things early:
              # break if pos1 > 1
 
              if l1.casecmp(l2) == -1
                  subcompute(l1,l2,"redhat.com",1, gravity, linkage, "red")
                  #subcompute(l1,l2,"gmail.com",1,  gravity, linkage, "green")
                  #subcompute(l1,l2,"googlemail.com",1, gravity, linkage, "green")
                  #subcompute(l1,l2,"fedoraproject.org",1, gravity, linkage, "blue")
                  #subcompute(l1,l2,"jboss.org",1, gravity, linkage, "yellow")
                  #subcompute(l1,l2,"jboss.com",1, gravity, linkage, "yellow")
                  subcompute(l1,l2,"other",1, gravity, linkage, "green")
              end
           end
        end

         
        clusters = {}
        @kb['explicit_lists'].each_pair do |k,c|
           clusters[c] = c
        end

        clusters.keys().each do |cluster|
           # subgraphs can result in misleading data
           #outfile.write("subgraph #{cluster} {\n")
           #outfile.write("label=\"#{cluster}\";\n")
           set1.each do |listname|
              if @kb['explicit_lists'][listname] == cluster
                  usename = listname.gsub("-","_") 
                  outfile.write("#{usename} [label=\"#{listname.gsub("-","_")} (#{gravity[usename]})\"]\n")
                  outfile.write("\n")
              end
           end
           #outfile.write("}\n")
        end

        linkage.each_pair do |combo, attributes|
           (list1,list2) = combo.split("--")
           (force, color) = attributes.split("-")
           force = force.to_i()
           if gravity[list1] > gravity[list2]

               outfile.write("#{list1} -> #{list2}")
           elsif gravity[list1] == gravity[list2]
               outfile.write("#{list1} -- #{list2}")
           else
               outfile.write("#{list2} -> #{list1}")
           end

           outfile.write(" [ weight=#{force * force}, color=\"#{color}\", label=\"#{force}\"];\n")

        end

        outfile.write("}\n")
        puts "---"
        puts "done."
        cmd = "dot kevinbacon.gv -Tsvg -o kevinbacon.svg"
        puts "now run: #{cmd}"
    end

    def run()
        lists = @kb['explicit_lists'].keys()
        File.open("kevinbacon.gv","w+") { |f|
           compute(lists,f) 
        }
     end

end
