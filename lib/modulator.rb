require 'json'

require 'modulator/lambda/aws_lambda_handler'
require 'modulator/lambda/aws_stack_builder'
require 'utils'

module Modulator
  module_function
  LAMBDAS   = {}

  def add_lambda(lambda_def, **opts) # opts are for overrides
    if lambda_def.is_a?(Hash)
      add_lambda_from_hash(lambda_def)
    else
      add_lambda_from_module(lambda_def, **opts)
    end
  end

  def add_lambda_from_hash(hash)
    LAMBDAS[hash[:name]] = {
      name: hash[:name],
      gateway: hash[:gateway],
      module: hash[:module],
      wrapper: hash[:wrapper] || {},
      env: hash[:env] || {},
      settings: hash[:settings] || {}
    }
  end

  def add_lambda_from_module(mod, **opts)
    mod.singleton_methods.sort.each do |module_method|
      module_name = mod.to_s
      module_names = module_name.split('::').map(&:downcase)
      verb = 'GET'
      path_fragments = module_names.dup

      # process parameters
      # method(a, b, c = 1, *args, d:, e: 2, **opts)
      # [[:req, :a], [:req, :b], [:opt, :c], [:rest, :args], [:keyreq, :d], [:key, :e], [:keyrest, :opts]]
      mod.method(module_method).parameters.each do |param|
        param_type = param[0]
        param_name = param[1]

        # collect required params
        path_fragments << ":#{param_name}" if param_type == :req

        # post if we have optional key param, ie. pet: {}
        verb = 'POST' if param_type == :key
      end

      # delete is special case based on method name
      verb = 'DELETE' if %w[destroy delete remove implode].include? module_method.to_s

      # finalize path
      path_fragments << module_method
      path = path_fragments.join('/')

      add_lambda_from_hash(
        {
          name: "#{module_names.join('-')}-#{module_method}",
          gateway: {
            verb: opts.dig(module_method, :gateway, :verb) || verb,
            path: opts.dig(module_method, :gateway, :path) || path
          },
          module: {
            name: module_name,
            method: module_method.to_s,
            path: module_names.join('/') # file name
          },
          wrapper: opts.dig(module_method, :wrapper) || opts[:wrapper],
          env: opts.dig(module_method, :env),
          settings: opts.dig(module_method, :settings)
        }
      )
    end
  end

  def set_env(lambda_def)
    # remove wrapper if already set
    %w(name method path).each{|name| ENV.delete('wrapper_' + name)}
    # set env values
    lambda_def[:module].each{|name, value| ENV['module_' + name.to_s] = value.to_s}
    lambda_def[:gateway].each{|name, value| ENV['gateway_' + name.to_s] = value.to_s}
    lambda_def[:wrapper]&.each{|name, value| ENV['wrapper_' + name.to_s] = value.to_s}
    lambda_def[:env]&.each{|name, value| ENV[name.to_s] = value.to_s} # custom values
  end

  def init_stack(app_name:, bucket:, **stack_opts)
    stack = AwsStackBuilder.init({
        app_name: app_name.camelize,
        bucket: bucket,
      }.merge(stack_opts))

    # add lambdas to stack
    puts 'Generating endpoints'
    LAMBDAS.each do |name, config|
      puts "- adding #{config.dig(:module, :name)}.#{config.dig(:module, :method)} to #{config.dig(:gateway, :path)}"
      stack.add_lambda_endpoint(
        gateway: config[:gateway],
        mod: config[:module],
        wrapper: config[:wrapper] || {},
        env: config[:env] || {},
        settings: config[:settings] || {}
      )
    end

    # validate stack
    # puts 'Validating stack'
    # puts '- it is valid' if stack.valid?

    # return humidifier instance
    stack
  end
end
