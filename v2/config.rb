require 'yaml'

class Config

   attr_reader :data

   def initialize(filename)
      File.open(filename) { |yf| 
         @data = YAML::load(yf) 
      }
   end
     
end
