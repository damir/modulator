require 'rack/test'
require_relative '../../lib/gateway/gateway'

include Rack::Test::Methods

module Rack
  module Test
    class Session
      def post(uri, params = {}, env = {}, &block)
        header "Content-Type", "application/json"
        custom_request('POST', uri, params.to_json, env, &block)
      end
    end
  end
end

def app
  builder = Rack::Builder.new
  @app ||= builder.run Gateway
end

def status
  last_response.status
end

def response
  JSON.parse(last_response.body) rescue last_response.body
end
