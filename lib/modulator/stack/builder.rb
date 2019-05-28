require 'forwardable'
require 'humidifier'
require_relative 'uploader'
require_relative 'policies'

module StackBuilder
  module_function

  RUBY_VERSION = 'ruby2.5'
  GEM_PATH_RUBY_VERSION = '2.5.0'
  GEM_PATH = "/opt/ruby/#{GEM_PATH_RUBY_VERSION}"
  LAMBDA_HANDLER_FILE_NAME = 'modulator-lambda-handler'

  class << self
    attr_accessor :stack, :stack_opts, :app_name, :app_path, :app_dir
    attr_accessor :hidden_dir, :s3_bucket, :lambda_handler_s3_object_version
    attr_accessor :api_gateway_deployment, :api_gateway_id, :lambda_policies
    attr_accessor :lambda_handlers, :lambda_handler_s3_key
  end

  def init(app_name:, s3_bucket:, **stack_opts)
    puts 'Initializing stack'
    @app_name   = app_name.camelize
    @s3_bucket  = s3_bucket
    @app_path   = Pathname.getwd
    @app_dir    = app_path.basename.to_s
    @hidden_dir = '.modulator'
    @stack_opts = stack_opts
    @lambda_handlers = stack_opts[:lambda_handlers] || []
    @lambda_policies = Array(stack_opts[:lambda_policies]) << :cloudwatch

    # create hidden dir for build artifacts
    app_path.join(hidden_dir).mkpath

    # init stack instance
    self.stack = Humidifier::Stack.new(name: app_name, aws_template_format_version: '2010-09-09')

    # app environment -  test, development, production ...
    app_envs = stack_opts[:app_envs] || ['development']
    stack.add_parameter('AppEnvironment', description: 'Application environment', type: 'String', allowed_values: app_envs, constraint_description: "Must be one of #{app_envs.join(', ')}")

    if lambda_handlers.empty?
      # api stage
      stack.add_parameter('ApiGatewayStageName', description: 'Gateway deployment stage', type: 'String', default: 'v1')

      # add gateway
      stack.add_api_gateway
      stack.add_api_gateway_deployment
    end

    # add role
    stack.add_lambda_iam_role

    # add policies to role
    stack.lambda_policies.each do |policy|
      stack.add_policy(policy) if policy.is_a?(Symbol)
      stack.add_policy(policy[:name], **policy) if policy.is_a?(Hash)
    end

    # simple lambda app
    if lambda_handlers.any?
      stack.upload_lambda_files
      lambda_handlers.each do |handler|
        stack.add_lambda(handler: handler, env: stack_opts[:env] || {}, settings: stack_opts[:settings] || {})
      end
    else
      # upload handlers and layers
      stack.upload_files
    end

    # return humidifier instance
    stack
  end

  def upload_files
    if stack_opts[:skip_upload]
      puts 'Skipping upload'
      return
    end
    stack.upload_generic_lambda_handler
    puts 'Generating layers'
    stack.upload_gems_layer
    stack.upload_app_layer
  end

  def add_lambda_endpoint(**opts) # gateway:, mod:, wrapper: {}, env: {}, settings: {}
    # add api resources and its lambda
    stack.add_api_gateway_resources(gateway: opts[:gateway], lambda: stack.add_generic_lambda(opts))
  end

  # gateway
  def add_api_gateway
    self.api_gateway_id = 'ApiGateway'
    stack.add(api_gateway_id, Humidifier::ApiGateway::RestApi.new(name: app_name, description: app_name + ' API'))
  end

  # gateway deployment
  def add_api_gateway_deployment
    self.api_gateway_deployment = Humidifier::ApiGateway::Deployment.new(
      rest_api_id: Humidifier.ref(api_gateway_id),
      stage_name: Humidifier.ref("ApiGatewayStageName")
    )
    stack.add('ApiGatewayDeployment', api_gateway_deployment)
    stack.add_output('ApiGatewayInvokeURL',
        value: Humidifier.fn.sub("https://${#{api_gateway_id}}.execute-api.${AWS::Region}.amazonaws.com/${ApiGatewayStageName}"),
        description: 'API root url',
        export_name: app_name + 'RootUrl'
    )
    api_gateway_deployment.depends_on = []
  end

  # custom lambda function
  def add_lambda(handler:, env: {}, settings: {})
    lambda_resource = generate_lambda_resource(
      description: "Lambda for #{handler}",
      function_name: ([app_name] << handler.split('.')).flatten.join('-').dasherize,
      handler: handler,
      s3_key: lambda_handler_s3_key,
      env_vars: env.merge('app_env' => Humidifier.ref('AppEnvironment')),
      role: Humidifier.fn.get_att(['LambdaRole', 'Arn']),
      settings: settings
    )
    stack.add(handler.gsub('.', '_').camelize, lambda_resource)
  end

  # generic lambda function for gateway
  def add_generic_lambda(gateway: {}, mod: {}, wrapper: {}, env: {}, settings: {})
    lambda_config = {}
    name_parts = mod[:name].split('::')
    {gateway: gateway, module: mod, wrapper: wrapper}.each do |env_group_prefix, env_group|
      env_group.each{|env_key, env_value| lambda_config["#{env_group_prefix}_#{env_key}"] = env_value}
    end
    env_vars = env
        .reduce({}){|env_as_string, (k, v)| env_as_string.update(k.to_s => v.to_s)}
        .merge(lambda_config)
        .merge(
          'GEM_PATH' => GEM_PATH,
          'app_dir'  => app_dir,
          'app_env'  => Humidifier.ref('AppEnvironment')
        )

    lambda_resource = generate_lambda_resource(
      description: "Lambda for #{mod[:name]}.#{mod[:method]}",
      function_name: [app_name, name_parts, mod[:method]].flatten.join('-').dasherize,
      handler: "#{LAMBDA_HANDLER_FILE_NAME}.AwsLambdaHandler.call",
      s3_key: LAMBDA_HANDLER_FILE_NAME + '.rb.zip',
      env_vars: env_vars,
      role: Humidifier.fn.get_att(['LambdaRole', 'Arn']),
      settings: settings,
      layers: [Humidifier.ref(app_name + 'Layer'), Humidifier.ref(app_name + 'GemsLayer')]
    )

    # add to stack
    ['Lambda', name_parts, mod[:method].capitalize].join.tap do |id|
      stack.add(id, lambda_resource)
      stack.add_lambda_invoke_permission(id: id, gateway: gateway)
    end
  end

  def generate_lambda_resource(description:, function_name:, handler:, s3_key:, env_vars:, role:, settings:, layers: [])
    lambda_function = Humidifier::Lambda::Function.new(
      description: description,
      function_name: function_name,
      handler: handler,
      environment: {variables: env_vars},
      role: role,
      timeout: settings[:timeout] || stack_opts[:timeout] || 15,
      memory_size: settings[:memory_size] || stack_opts[:memory_size] || 128,
      runtime: RUBY_VERSION,
      code: {
        s3_bucket: s3_bucket,
        s3_key: s3_key,
        s3_object_version: lambda_handler_s3_object_version
      },
      layers: layers
    )
  end

  # invoke permission
  def add_lambda_invoke_permission(id:, gateway:)
    arn_path_matcher = gateway[:path].split('/').each_with_object([]) do |fragment, matcher|
      fragment = '*' if fragment.start_with?(':')
      matcher << fragment
    end.join('/')
    stack.add(id + 'InvokePermission' , Humidifier::Lambda::Permission.new(
        action: "lambda:InvokeFunction",
        function_name: Humidifier.fn.get_att([id, 'Arn']),
        principal: "apigateway.amazonaws.com",
        source_arn: Humidifier.fn.sub("arn:aws:execute-api:${AWS::Region}:${AWS::AccountId}:${#{api_gateway_id}}/*/#{gateway[:verb]}/#{arn_path_matcher}")
      )
    )
  end

  # gateway method
  def add_api_gateway_resources(gateway:, lambda:)

    # example: calculator/algebra/:x/:y/sum -> module name, args, method name
    path = gateway[:path].split('/')

    # root resource
    root_resource = path.shift
    stack.add(root_resource.camelize, Humidifier::ApiGateway::Resource.new(
        rest_api_id: Humidifier.ref(api_gateway_id),
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
      stack.add(parent_resource + fragment.camelize, Humidifier::ApiGateway::Resource.new(
          rest_api_id: Humidifier.ref(api_gateway_id),
          parent_id: Humidifier.ref(parent_resource),
          path_part: dynamic_fragment || fragment
        )
      )
      parent_resource = parent_resource + fragment.camelize
    end

    # attach lambda to last resource
    id = 'EndpointFor' + (gateway[:path].gsub(':', '').gsub('/', '_')).camelize
    stack.add(id, Humidifier::ApiGateway::Method.new(
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
        rest_api_id: Humidifier.ref(api_gateway_id),
        resource_id: Humidifier.ref(parent_resource) # last evaluated resource
      )
    )

    # deployment depends on each endpoint
    api_gateway_deployment.depends_on << id
  end
end

# delegate from stack instance to our module
module Humidifier
  class Stack
    extend Forwardable
    [StackBuilder, StackBuilder::LambdaPolicy].each do |mod|
      def_delegators mod.to_s.to_sym, *mod.singleton_methods
    end
  end
end
