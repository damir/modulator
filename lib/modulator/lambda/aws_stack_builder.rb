require 'humidifier'
require_relative 'aws_stack_uploader'

module AwsStackBuilder
  module_function

  RUBY_VERSION = 'ruby2.5'
  GEM_PATH = '/opt/ruby/2.5.0'
  LAMBDA_HANDLER_FILE_NAME = 'lambda-handler'

  class << self
    attr_accessor :app_name, :stack, :api_gateway_deployment, :gateway_id, :app_path, :app_dir, :bucket, :stack_opts
  end

  def init(app_name:, bucket:, **stack_opts)
    puts 'Initializing stack'
    @app_name   = app_name.camelize
    @bucket     = bucket
    @app_path   = Pathname.getwd
    @app_dir    = app_path.basename.to_s
    @stack_opts = stack_opts
    @stack      = Humidifier::Stack.new(name: @app_name, aws_template_format_version: '2010-09-09')

    # api stage
    @stack.add_parameter('ApiGatewayStageName', description: 'Gateway deployment stage', type: 'String', default: 'v1')

    add_api_gateway
    add_api_gateway_deployment
    add_lambda_iam_role
    upload_files
    extend_stack_instance(@stack)
    @stack
  end

  def upload_files
    upload_lambda_handler
    puts 'Generating layers'
    app_path.join('.modulator').mkpath
    upload_gems_layer
    upload_app_layer
  end

  # helpers
  def extend_stack_instance(stack)
    stack.instance_eval do
      def add_lambda_endpoint(**opts) # gateway:, mod:, wrapper: {}, env: {}, settings: {}
        # add lambda
        lambda = AwsStackBuilder.add_lambda(opts)
        # add api resources
        AwsStackBuilder.add_api_gateway_resources(gateway: opts[:gateway], lambda: lambda)
      end
    end
  end

  # gateway
  def add_api_gateway
    @gateway_id = 'ApiGateway'
    @stack.add(gateway_id, Humidifier::ApiGateway::RestApi.new(name: app_name, description: app_name + ' API'))
  end

  # gateway deployment
  def add_api_gateway_deployment
    @api_gateway_deployment = Humidifier::ApiGateway::Deployment.new(
      rest_api_id: Humidifier.ref(gateway_id),
      stage_name: Humidifier.ref("ApiGatewayStageName")
    )
    @stack.add('ApiGatewayDeployment', @api_gateway_deployment)
    @stack.add_output('ApiGatewayInvokeURL',
        value: Humidifier.fn.sub("https://${#{gateway_id}}.execute-api.${AWS::Region}.amazonaws.com/${ApiGatewayStageName}"),
        description: 'API root url',
        export_name: app_name + 'RootUrl'
    )
    @api_gateway_deployment.depends_on = []
  end

  # lambda function
  def add_lambda(gateway:, mod:, wrapper: {}, env: {}, settings: {})
    lambda_config = {}
    name_parts = mod[:name].split('::')
    {gateway: gateway, module: mod, wrapper: wrapper}.each do |env_group_prefix, env_group|
      env_group.each{|env_key, env_value| lambda_config["#{env_group_prefix}_#{env_key}"] = env_value}
    end

    lambda_function = Humidifier::Lambda::Function.new(
      description: "Lambda for #{mod[:name]}.#{mod[:method]}",
      function_name: [app_name.dasherize, name_parts, mod[:method]].flatten.map(&:downcase).join('-'),
      handler: "#{LAMBDA_HANDLER_FILE_NAME}.AwsLambdaHandler.call",
      environment: {
        variables: env
          .reduce({}){|env_as_string, (k, v)| env_as_string.update(k.to_s => v.to_s)}
          .merge(lambda_config)
          .merge('GEM_PATH' => GEM_PATH, 'app_dir' => app_dir)
      },
      role: Humidifier.fn.get_att(['LambdaRole', 'Arn']),
      timeout: settings[:timeout] || stack_opts[:timeout] || 15,
      memory_size: settings[:memory_size] || stack_opts[:memory_size] || 128,
      runtime: RUBY_VERSION,
      code: {
        s3_bucket: bucket,
        s3_key: LAMBDA_HANDLER_FILE_NAME + '.rb.zip'
      },
      layers: [
        Humidifier.ref(app_name + 'Layer'),
        Humidifier.ref(app_name + 'GemsLayer')
      ]
    )
    id = ['Lambda', name_parts, mod[:method].capitalize].join
    @stack.add(id, lambda_function)
    add_lambda_invoke_permission(id: id, gateway: gateway)
    id
  end

  # invoke permission
  def add_lambda_invoke_permission(id:, gateway:)
    arn_path_matcher = gateway[:path].split('/').each_with_object([]) do |fragment, matcher|
      fragment = '*' if fragment.start_with?(':')
      matcher << fragment
    end.join('/')
    @stack.add('LambdaPermission', Humidifier::Lambda::Permission.new(
        action: "lambda:InvokeFunction",
        function_name: Humidifier.fn.get_att([id, 'Arn']),
        principal: "apigateway.amazonaws.com",
        source_arn: Humidifier.fn.sub("arn:aws:execute-api:${AWS::Region}:${AWS::AccountId}:${#{gateway_id}}/*/#{gateway[:verb]}/#{arn_path_matcher}")
      )
    )
  end

  # gateway method
  def add_api_gateway_resources(gateway:, lambda:)

    # example: calculator/algebra/:x/:y/sum -> module name, args, method name
    path = gateway[:path].split('/')

    # root resource
    root_resource = path.shift
    @stack.add(root_resource.camelize, Humidifier::ApiGateway::Resource.new(
        rest_api_id: Humidifier.ref(AwsStackBuilder.gateway_id),
        parent_id: Humidifier.fn.get_att(["ApiGateway", "RootResourceId"]),
        path_part: root_resource
      )
    )

    # args and method name are nested resources
    parent_resource = root_resource.camelize
    path.each do |fragment|
      if fragment.start_with?(':')
        fragment = fragment[1..-1]
        dynamic_fragment = "{#{fragment}}"
      end
      @stack.add(parent_resource + fragment.camelize, Humidifier::ApiGateway::Resource.new(
          rest_api_id: Humidifier.ref(AwsStackBuilder.gateway_id),
          parent_id: Humidifier.ref(parent_resource),
          path_part: dynamic_fragment || fragment
        )
      )
      parent_resource = parent_resource + fragment.camelize
    end

    # attach lambda to last resource
    id = 'EndpointFor' + (gateway[:path].gsub(':', '').gsub('/', '_')).camelize
    @stack.add(id, Humidifier::ApiGateway::Method.new(
        authorization_type: 'NONE',
        http_method: gateway[:verb].to_s.upcase,
        integration: {
          integration_http_method: 'POST',
          type: "AWS_PROXY",
          uri: Humidifier.fn.sub([
            "arn:aws:apigateway:${AWS::Region}:lambda:path/2015-03-31/functions/${lambdaArn}/invocations",
            'lambdaArn' => Humidifier.fn.get_att([lambda, 'Arn'])
          ])
        },
        rest_api_id: Humidifier.ref(gateway_id),
        resource_id: Humidifier.ref(parent_resource) # last evaluated resource
      )
    )

    # deployment depends on the method
    @api_gateway_deployment.depends_on << id
  end

  def add_lambda_iam_role(function_name: nil)
    @stack.add('LambdaRole', Humidifier::IAM::Role.new(
        assume_role_policy_document: {
          'Version' => "2012-10-17",
          'Statement' => [
            {
              'Action' => ["sts:AssumeRole"],
              'Effect' => "Allow",
              'Principal' => {
                'Service' => ["lambda.amazonaws.com"]
              }
            }
          ]
        },
        policies: [
          {
            'policy_document' => {
              'Version' => "2012-10-17",
              'Statement' => [
                {
                  'Action' => [
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                  ],
                  'Effect' => "Allow",
                  'Resource' => Humidifier.fn.sub("arn:aws:logs:${AWS::Region}:${AWS::AccountId}:*")
                },
                {
                  'Action' => [
                    "logs:CreateLogGroup",
                  ],
                  'Effect' => "Allow",
                  'Resource' => "*"
                }
              ]
            },
            'policy_name' => "cloud-watch-access"
          }
        ]
      )
    )
  end
end
