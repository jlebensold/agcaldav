require 'curb'
require 'tzinfo'
module AgCalDAV
  class Client
    include Icalendar
    attr_accessor :host, :port, :url, :user, :password, :ssl, :shared_calendar

=begin
    def timezone_standard block
      block.timezone do
        timezone_id             "Europe/Paris"
        daylight do
          timezone_offset_from  "+0200"
          timezone_offset_to    "+0100"
          timezone_name         "GMT+01:00"
          dtstart               "19961027T030000"
          add_recurrence_rule   "FREQ=YEARLY;BYDAY=-1SU;BYMONTH=3"
        end

        standard do
          timezone_offset_from  "+0100"
          timezone_offset_to    "+0200"
          timezone_name         "GMT+01:00"
          dtstart               "19961027T030000"
          add_recurrence_rule   "FREQ=YEARLY;BYDAY=-1SU;BYMONTH=10"
        end
      end
    end
=end
    def initialize( data )
      uri = URI(data[:uri])
      @host     = uri.host
      @port     = uri.port.to_i
      @url      = (data[:shared_calendar].nil?) ? uri.path : "#{uri.path}/#{data[:shared_calendar]}"
      @user     = data[:user]
      @password = data[:password]
      @ssl      = uri.scheme == 'https'
      
      unless data[:authtype].nil?
      	@authtype = data[:authtype]
	    else
      	@authtype = 'basic'
      end
    end

    def find_events data
      result = ""
      events = []
      res = nil

		  if data[:start].is_a? Integer
        body = AgCalDAV::Request::ReportVEVENT.new(Time.at(data[:start]).strftime("%Y%m%dT%H%M%S"), 
                                                      Time.at(data[:end]).strftime("%Y%m%dT%H%M%S") ).to_xml
      else
        body = AgCalDAV::Request::ReportVEVENT.new(DateTime.parse(data[:start]).strftime("%Y%m%dT%H%M%S"), 
                                                      DateTime.parse(data[:end]).strftime("%Y%m%dT%H%M%S") ).to_xml
      end
      responses = []
      xml =''
      c = Curl::http :REPORT, base_url(), nil, body do |curl|
        curl.http_auth_types = :digest  if (@authtype == 'digest')
        curl.headers['Content-Type'] = 'application/xml'
        curl.username = @user
        curl.password = @password
        curl.on_body { |data| responses << data; data.size }
      end
      c.perform
      result = ''
      xml = REXML::Document.new(responses.first)
      REXML::XPath.each( xml, '//c:calendar-data/', {"c"=>"urn:ietf:params:xml:ns:caldav"} ){ |c|  result << c.text}
      r = Icalendar.parse(result)
      unless r.empty?
        r.each do |calendar|
          calendar.events.each do |event|
            events << event
          end
        end
        events
      else
        return false
      end
    end

    def find_event uuid
      response = ''
      c = Curl::Easy.new([base_uri, "#{uuid}.ics"].join('/')) do |curl|
        curl.http_auth_types = :digest  if (@authtype == 'digest')
        curl.username = @user
        curl.password = @password
        curl.on_body { |data| response = data ; data.size }
      end
      c.perform
      begin
      	r = Icalendar.parse(response)
      rescue
      	return false
      else
      	r.first.events.first 
      end

    end

    def delete_event uuid
      res = nil
      c = Curl::Easy.http_delete([base_uri, "#{uuid}.ics"].join('/')) do |curl|
        if (@authtype == 'digest')
          curl.http_auth_types = :digest
        end
        curl.username = @user
        curl.password = @password
      end
      return ! entry_with_uuid_exists?(uuid)
    end

    def create_event event
      c = Calendar.new
      #c.timezone = timezone_standard()
      
      c.events = []
      uuid = UUID.new.generate
      raise DuplicateError if entry_with_uuid_exists?(uuid)
      c.event do
        uid           uuid
        dtstart       event[:start].strftime("%Y%m%dT%H%M%SZ")
        dtend         event[:end].strftime("%Y%m%dT%H%M%SZ")
        dtstamp       DateTime.now.strftime("%Y%m%dT%H%M%SZ")
        categories    event[:categories]# Array
        contacts       event[:contacts] # Array
        attendees      event[:attendees]# Array
        duration      event[:duration]
        summary       event[:title]
        description   event[:description]
        klass         event[:accessibility] #PUBLIC, PRIVATE, CONFIDENTIAL
        location      event[:location]
        geo_location  event[:geo_location]
        status        event[:status]
      end
      res = nil
      c = Curl::Easy.http_put([base_uri, "#{uuid}.ics"].join('/'),c.to_ical) do |curl|
        if (@authtype == 'digest')
          curl.http_auth_types = :digest
        end
        curl.headers['Content-Type'] = 'text/calendar'
        curl.username = @user
        curl.password = @password
      #  curl.on_body { |data|  }
      end
      find_event uuid
    end

    def base_uri
      protocol = @ssl ? "https" : "http"
      "#{protocol}://#{@host}:#{@port}#{@url}"
    end


    def update_event event
      props = event.properties.inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}
      if delete_event props[:uid]
        props[:start] = props[:dtstart] if props[:start].nil?
        props[:end] = props[:dtend] if props[:end].nil?
        create_event props 
      else
        return false
      end
    end



  private
    
    def entry_with_uuid_exists? uuid
      res = nil
      e = find_event uuid
      return false if e == false
      true
    end
    
    def  errorhandling code
      pp code
      raise AuthenticationError if code == 401
      raise NotExistError if code == 410 
      raise APIError if code >= 500
    end
  end

  class AgCalDAVError < StandardError
  end
  class AuthenticationError < AgCalDAVError; end
  class DuplicateError      < AgCalDAVError; end
  class APIError            < AgCalDAVError; end
  class NotExistError       < AgCalDAVError; end
end
