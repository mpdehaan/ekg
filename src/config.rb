# Copyright 2008, Red Hat, Inc
#
# This software may be freely redistributed under the terms of the GNU
# general public license.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

require 'yaml'

class Config

   attr_reader :data

   def initialize(filename)
      File.open(filename) { |yf| 
         @data = YAML::load(yf) 
      }
   end
     
end
