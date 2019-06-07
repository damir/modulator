require 'pathname'

# NOTE: aws has LambdaHandler already defined as a class so we need an aws prefix here
module AwsLambdaHandler
  module_function

  # select event handler
  def call(event:, context:)
    # TODO: implement handlers for other event types based on some event key, like AwsS3EventHandler
    AwsApiGatewayEventHandler.call(event: event, context: context)
  end
end

module AwsApiGatewayEventHandler
  module_function

  NUMBER_REGEX = /\A[+-]?\d+(\.[\d]+)?\z/

  def call(event:, context:)
    wrapper_params = {}

    if ENV['wrapper_name']
      # module init
      require Pathname.getwd.join(ENV['wrapper_path']).to_s
      wrapper = Object.const_get(ENV['wrapper_name'])
      mod_method = ENV['wrapper_method']

      # check arity
      if wrapper.method(mod_method).parameters != [[:keyreq, :event], [:keyreq, :context]]
        raise("#{wrapper}.#{mod_method} should accept event and context keyword arguments")
      end

      # print call info
      puts "Calling wrapper #{wrapper}.#{mod_method}"
      wrapper_result = wrapper.send(mod_method, event: event, context: context)

      if wrapper_result.is_a?(Hash)
        # block with custom status and body
        return {
          statusCode: wrapper_result[:status],
          body: JSON.generate(wrapper_result[:body])
        } if wrapper_result[:status]

        # or set params
        wrapper_params = wrapper_result

      elsif !wrapper_result
        # block if result is false/nil
        return {
          statusCode: 403,
          body: JSON.generate(forbidden: "#{wrapper}.#{mod_method}")
        } if !wrapper_result
      end
    end

    # module init
    require Pathname.getwd.join(ENV['module_path']).to_s
    mod = Object.const_get(ENV['module_name'])
    mod_method = ENV['module_method']

    # gateway def
    verb = ENV['gateway_verb']
    path = ENV['gateway_path']

    # print call info
    method_signature = mod.method(mod_method).parameters
    puts "Resolving #{verb.to_s.upcase} #{path} to #{mod}.#{mod_method} with #{method_signature}"

    # cast path parameters to numbers
    path_params = event['pathParameters'].each_with_object({}) do |(key, value), params|
      if matcher = NUMBER_REGEX.match(value)
        value = matcher[1] ? Float(value) : value.to_i
      end
      params[key] = value
    end

    # merge wrapper params
    path_params.merge!(wrapper_params)

    # call the module method
    result =
    if ['GET', 'DELETE'].include?(verb)
      mod.send(mod_method, *path_params.values)

    elsif verb == 'POST'
      payload = JSON.parse(event['body'], symbolize_names: true)
      method_signature.each do |arg_type, arg_name|         # [[:req, :id], [:key, :pet]]
        payload = {arg_name => payload} if arg_type == :key # scope payload to first named argument
      end

      # we can override GET to POST without payload, ruby will break if **payload is resolved from {}
      if payload.any?
        mod.send(mod_method, *path_params.values, **payload)
      else
        mod.send(mod_method, *path_params.values)
      end

    else
      raise 'Verb should be GET, POST or DELETE'
    end

    # set status and body values
    if result.nil?
      status  = 404
      body    = nil # it will print json null string
    else
      status  = result[:status] ? result[:status] : 200
      body    = result[:body] ? result[:body] : result
    end

    # return result
    return {statusCode: status, body: JSON.generate(body)}

    # print and return error
    rescue => e
      puts output = {
        statusCode: 500,
        body: JSON.generate(
          error: {
            class: e.class,
            message: e.message
          }.merge(ENV['debug'] ? {backtrace: e.backtrace.take(20)} : {})
        )
      }
      output
  end
end
