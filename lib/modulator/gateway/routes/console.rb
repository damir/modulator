require 'aws-sdk-cloudformation'

# console API
Gateway.route('console') do |r|

  client    = Aws::CloudFormation::Client.new
  app_name  = (opts[:app_dir] || Pathname.getwd.basename.to_s).camelize

  # helpers
  def capture_output
    previous_stdout, $stdout = $stdout, StringIO.new
    previous_stderr, $stderr = $stderr, StringIO.new
    yield
    $stdout.string if $stdout.string.size > 0
    $stderr.string if $stderr.string.size > 0
    ensure
      $stdout = previous_stdout
      $stderr = previous_stderr
  end

  def render_command_result(command_result, command_output)
    if command_result
      command_result.to_hash
    else
      {'aws-sdk-cloudformation': command_output.split("\n").first}
    end
  end

  r.on 'stack' do
    bucket_name = ENV['S3BUCKET'] || 'modulator-lambdas'
    payload = request.params.symbolize_keys
    command_result = nil

    r.get 'events' do
      resp = client.describe_stack_events(stack_name: app_name, next_token: @headers['X-Next-Token'])
      response['X-Next-Token'] = resp.next_token
      resp.stack_events.map(&:to_hash)
    end

    r.on 'init' do
      serializer = :yaml
      content_type = 'text/html'

      r.on 'json' do
        serializer = :json
        content_type = 'application/json'
        r.pass
      end

      # init stack
      stack = Modulator.init_stack(
        app_name: app_name,
        bucket: bucket_name,
        timeout: 15
      )

      # add stack parameters if found in payload
      bucket_name[:parameters]&.each do |param|
        stack.add_parameter(param[:key],
          description: param[:description],
          type: param[:type],
          value: param[:value]
        )
      end

      r.post 'valid' do
        command_output = capture_output do
          command_result = stack.valid?
        end
        render_command_result(command_result, command_output)
      end

      r.post 'deploy' do
        command_output = capture_output do
          command_result = stack.deploy(
            parameters: bucket_name[:parameters]&.map{|param| {parameter_key: param[:key], parameter_value: param[:value]}},
            capabilities: ['CAPABILITY_IAM']
          )
        end
        render_command_result(command_result, command_output)
      end

      r.post do
        response['Content-Type'] = content_type
        template = stack.to_cf(serializer)
      end
    end
  end
end
