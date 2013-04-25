require 'uuid'
require 'rexml/document'
require 'rexml/xpath'
require 'icalendar'
require 'time'
require 'date'
require 'curb'
require 'tzinfo'
['client.rb', 'request.rb', 'filter.rb', 'event.rb'].each do |f|
    require File.join( File.dirname(__FILE__), 'agcaldav', f )
end
