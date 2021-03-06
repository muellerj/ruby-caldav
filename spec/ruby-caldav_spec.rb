# encoding: UTF-8
require 'spec_helper'
require 'fakeweb'

require 'ruby-caldav'

RSpec.describe CalDAV::Client do

  before(:each) do
    @c = CalDAV::Client.new(:uri => "http://localhost:8008/calendars/users/user1/calendar/", :user => "user1" , :password => "password1")
  end

  before(:all) do
    class UUID
      def generate
        "360232b0-371c-0130-9e6b-001999638933"
      end
    end
  end

  it "check Class of client" do
    expect(@c.class.to_s).to eq "CalDAV::Client"
  end

end
