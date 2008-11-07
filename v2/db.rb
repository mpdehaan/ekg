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
                   table.column :url
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

