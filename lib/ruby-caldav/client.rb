module CalDAV
  class Client
    include Icalendar
    attr_accessor :host, :port, :url, :user, :password, :ssl

    def format=( fmt )
      @format = fmt
    end

    def with_retry(times = 3)
      counter = 1
      begin
        yield
      rescue
        counter += 1
        retry if counter > times
      end
    end

    def format
      @format ||= Format::Debug.new
    end

    def initialize( data )
      unless data[:proxy_uri].nil?
        proxy_uri   = URI(data[:proxy_uri])
        @proxy_host = proxy_uri.host
        @proxy_port = proxy_uri.port.to_i
      end

      uri = URI(data[:uri])
      @host     = uri.host
      @port     = uri.port.to_i
      @url      = uri.path
      @user     = data[:user]
      @password = data[:password]
      @ssl      = uri.scheme == 'https'

      unless data[:authtype].nil?
      	@authtype = data[:authtype]
      	if @authtype == 'digest'

      		@digest_auth = Net::HTTP::DigestAuth.new
      		@duri = URI.parse data[:uri]
      		@duri.user = @user
      		@duri.password = @password

      	elsif @authtype == 'basic'
	    	  # this is fine for us
	    else
	    	raise "Please use basic or digest"
	    end
      else
      	@authtype = 'basic'
      end
    end

    def __create_http
      if @proxy_uri.nil?
        http = Net::HTTP.new(@host, @port)
      else
        http = Net::HTTP.new(@host, @port, @proxy_host, @proxy_port)
      end
      if @ssl
        http.use_ssl = @ssl
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
      # http.max_retries = 3
      http
    end

    def self.convert_to_str(value)
      if value.respond_to? :utc
        value.utc.strftime("%Y%m%dT%H%M%S")
      elsif value.respond_to? :strftime
        value.utc.strftime("%Y%m%dT%H%M%S")
      elsif value.is_a? Integer
        Time.at(value).utc.strftime("%Y%m%dT%H%M%S")
      else
        Time.parse(value).utc.strftime("%Y%m%dT%H%M%S")
      end
    end      

    def find_events data
      result = ""
      events = []
      res = nil
      __create_http.start {|http|

        req = Net::HTTP::Report.new(@url, initheader = {'Content-Type'=>'application/xml'} )

		if not @authtype == 'digest'
			req.basic_auth @user, @password
		else
			req.add_field 'Authorization', digestauth('REPORT')
		end
        dtstart = Client.convert_to_str(data[:start])
        dtend = Client.convert_to_str(data[:end])
        rep = CalDAV::Request::ReportVEVENT.new(dtstart, dtend)
        if block_given?
          req.body = rep.to_xml do |xml|
            yield xml
          end
        else
          req.body = rep.to_xml
        end
        res = http.request(req)
      }
        errorhandling res
        result = ""
        #puts res.body
        xml = REXML::Document.new(res.body)
        REXML::XPath.each( xml, '//c:calendar-data/', {"c"=>"urn:ietf:params:xml:ns:caldav"} ) do |c|
          r = Icalendar::Calendar.parse(c.text)
          unless r.empty?
            r.each do |calendar|
              calendar.events.each do |event|
                events << event
              end
            end
          end
        end
        events
    end

    def find_event uuid
      res = nil
      with_retry do
        __create_http.start {|http|
          req = Net::HTTP::Get.new("#{@url}/#{uuid}.ics")
          if not @authtype == 'digest'
          	req.basic_auth @user, @password
          else
          	req.add_field 'Authorization', digestauth('GET')
          end
          res = http.request( req )
        }
        errorhandling res
      end
      begin
      	r = Icalendar::Calendar.parse(res.body)
      rescue
      	return false
      else
      	r.first.events.first
      end


    end

    def delete_event uuid
      res = nil
      with_retry do
        __create_http.start {|http|
          req = Net::HTTP::Delete.new("#{@url}/#{uuid}.ics")
          if not @authtype == 'digest'
          	req.basic_auth @user, @password
          else
          	req.add_field 'Authorization', digestauth('DELETE')
          end
          res = http.request( req )
        }
        errorhandling res
      end
      # accept any success code
      if res.code.to_i.between?(200,299)
        return true
      else
        return false
      end
    end

    def create_event
      event = Icalendar::Event.new
      yield event
      add_event event
    end

    def add_event event
      c = Calendar.new
      uuid = UUID.new.generate
      raise DuplicateError if entry_with_uuid_exists?(uuid)
      event.uid = uuid
      c.add_event event
      cstring = c.to_ical
      with_retry do
        res = nil
        __create_http.start { |http|
          req = Net::HTTP::Put.new("#{@url}/#{uuid}.ics")
          req['Content-Type'] = 'text/calendar'
          if not @authtype == 'digest'
          	req.basic_auth @user, @password
          else
          	req.add_field 'Authorization', digestauth('PUT')
          end
          req.body = cstring
          res = http.request( req )
        }
        errorhandling res
      end
      find_event uuid
    end

    def update_event event
      #TODO... fix me
      if delete_event event.uid
        add_event event
      else
        return false
      end
    end

    def add_alarm tevent, altCal="Calendar"

    end

    def find_todo uuid
      res = nil
      __create_http.start {|http|
        req = Net::HTTP::Get.new("#{@url}/#{uuid}.ics")
        if not @authtype == 'digest'
        	req.basic_auth @user, @password
        else
        	req.add_field 'Authorization', digestauth('GET')
        end
        res = http.request( req )
      }
      errorhandling res
      r = Icalendar::Calendar.parse(res.body)
      r.first.todos.first
    end





    def create_todo todo
      c = Calendar.new
      uuid = UUID.new.generate
      raise DuplicateError if entry_with_uuid_exists?(uuid)
      c.todo do
        uid           uuid
        start         DateTime.parse(todo[:start])
        duration      todo[:duration]
        summary       todo[:title]
        description   todo[:description]
        klass         todo[:accessibility] #PUBLIC, PRIVATE, CONFIDENTIAL
        location      todo[:location]
        percent       todo[:percent]
        priority      todo[:priority]
        url           todo[:url]
        geo           todo[:geo_location]
        status        todo[:status]
        rrule         todo[:rrule]
      end
      c.todo.uid = uuid
      cstring = c.to_ical
      res = nil
      __create_http.start { |http|
        req = Net::HTTP::Put.new("#{@url}/#{uuid}.ics")
        req['Content-Type'] = 'text/calendar'
        if not @authtype == 'digest'
        	req.basic_auth @user, @password
        else
        	req.add_field 'Authorization', digestauth('PUT')
        end
        req.body = cstring
        res = http.request( req )
      }
      errorhandling res
      find_todo uuid
    end

    def create_todo
      res = nil
      raise DuplicateError if entry_with_uuid_exists?(uuid)

      __create_http.start {|http|
        req = Net::HTTP::Report.new(@url, initheader = {'Content-Type'=>'application/xml'} )
        if not @authtype == 'digest'
        	req.basic_auth @user, @password
        else
        	req.add_field 'Authorization', digestauth('REPORT')
        end
        req.body = CalDAV::Request::ReportVTODO.new.to_xml
        res = http.request( req )
      }
      errorhandling res
      format.parse_todo( res.body )
    end

    private

    def digestauth method

	    h = Net::HTTP.new @duri.host, @duri.port
	    if @ssl
	    	h.use_ssl = @ssl
	    	h.verify_mode = OpenSSL::SSL::VERIFY_NONE
	    end
	    req = Net::HTTP::Get.new @duri.request_uri

	    res = h.request req
	    # res is a 401 response with a WWW-Authenticate header

	    auth = @digest_auth.auth_header @duri, res['www-authenticate'], method

    	return auth
    end

    def entry_with_uuid_exists? uuid
      res = nil

      __create_http.start {|http|
        req = Net::HTTP::Get.new("#{@url}/#{uuid}.ics")
        if not @authtype == 'digest'
        	req.basic_auth @user, @password
        else
        	req.add_field 'Authorization', digestauth('GET')
        end

        res = http.request( req )

      }
      begin
        errorhandling res
      	Icalendar::Calendar.parse(res.body)
      rescue
      	return false
      else
      	return true
      end
    end
    def  errorhandling response
      raise NotExistError if response.code.to_i == 404
      raise AuthenticationError if response.code.to_i == 401
      raise NotExistError if response.code.to_i == 410
      raise APIError if response.code.to_i >= 500
    end
  end


  class CalDAVError < StandardError
  end
  class AuthenticationError < CalDAVError; end
  class DuplicateError      < CalDAVError; end
  class APIError            < CalDAVError; end
  class NotExistError       < CalDAVError; end
end
