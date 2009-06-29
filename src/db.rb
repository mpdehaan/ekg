# Copyright 2008, Red Hat, Inc
#
# This software may be freely redistributed under the terms of the GNU
# general public license.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

require 'active_record'

class Db 

   def connect()
       ActiveRecord::Base.establish_connection(
           :adapter => "sqlite3",
           :dbfile  => "sqlite3.db"
       )
   end

   def setup()
       begin
           ActiveRecord::Schema.define do
               create_table :scans do |table|
                   table.column :url, :string
               end
               create_table :posts do |table|
                   table.column :url, :string
                   table.column :subject, :string
                   table.column :list_id, :string
                   table.column :from_domain, :string
                   table.column :from_addr, :string
                   table.column :sent_date, :date
               end
           end
       rescue
           puts "using existing database"
       end
   end

end

class Post < ActiveRecord::Base
  belongs_to :posts
end

class Scan < ActiveRecord::Base
  belongs_to :scans
end 
