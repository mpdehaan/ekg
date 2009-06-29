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

class Finder

    def initialize(config)

        # get the list of mailmen indexes and individual lists to process
        # from the config file

        File.open(config) { |yf|
           @data = YAML::load(yf)
        }
        @track_limit = @data["track_limit"]
        @listdata = @data["explicit_lists"]

    end

    def run()

        person_ct = {}
        person_details = {}

        print "this may take several minutes"

        query = "select distinct from_addr from posts"
        everyone = Post.connection.select_values(query)
        universe = {}
        everyone.each do |person|
              query = "select count(*) from posts where from_addr == '#{person}'"
              ct = Post.connection.select_value(query)
              if !(person=~ /do-not-reply/ or person =~ /redhat.com/ or person=~/jboss.com/ or person =~/jboss.org/)
                  query2 = "select distinct list_id from posts where from_addr == '#{person}'"
                  lists = Post.connection.select_values(query2)

                  if ct.to_i > 20 
                      person_details[person] = "#{person} - #{lists.join(",")}"
                      # puts "scanned: %s" % person_details[person]
                      person_ct[person] = ct.to_i()
                  end
              end
        end

        def sorter(person_ct,a,b)
            person_ct[b] <=> person_ct[a]
        end

        people = person_details.keys().sort{|a,b|sorter(person_ct,a,b)}

        people.each do |p|
           puts "#{person_ct[p]} - #{person_details[p]}"
        end

    end

end
