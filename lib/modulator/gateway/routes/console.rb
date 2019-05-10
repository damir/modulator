Gateway.route('console') do |r|

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

  # list registered lambdas
  r.on 'lambdas' do
    r.get 'list' do
      Modulator::LAMBDAS
    end
  end

  # stack operations
  r.on 'stack' do
    client    = Aws::CloudFormation::Client.new
    app_name  = (opts[:app_dir] || Pathname.getwd.basename.to_s).camelize
    s3_bucket = opts[:s3_bucket] || ENV['MODULATOR_S3_BUCKET'] || 'modulator-lambdas'
    payload   = request.params.symbolize_keys
    command_result = nil

    r.get 'events' do
      resp = client.describe_stack_events(stack_name: app_name, next_token: @headers['X-Next-Token'])
      response['X-Next-Token'] = resp.next_token
      resp.stack_events.map(&:to_hash)
    end


    # initialize stack
    r.on 'init' do
      serializer = :yaml
      content_type = 'text/html'

      r.on 'json' do
        serializer = :json
        content_type = 'application/json'
        r.pass
      end

      stack = Modulator.init_stack(
        s3_bucket: s3_bucket,
        timeout: 15,
        skip_upload: true
      )

      # validate stack
      r.post 'valid' do
        command_output = capture_output do
          command_result = stack.valid?
        end
        render_command_result(command_result, command_output)
      end

      # deploy stack
      r.post 'deploy' do
        command_output = capture_output do
          command_result = stack.deploy(
            parameters: s3_bucket[:parameters]&.map{|param| {parameter_key: param[:key], parameter_value: param[:value]}},
            capabilities: ['CAPABILITY_IAM']
          )
        end
        render_command_result(command_result, command_output)
      end

      # print template
      r.post do
        response['Content-Type'] = content_type
        stack.to_cf(serializer)
      end
    end
  end
end
