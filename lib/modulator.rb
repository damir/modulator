require 'json'

require 'modulator/lambda_handler'
require 'modulator/stack/builder'
require 'utils'

module Modulator
  module_function
  LAMBDAS = {}

  class << self
    attr_accessor :stack
  end

  def register(lambda_def, **opts) # opts are for overrides
    if lambda_def.is_a?(Hash)
      register_from_hash(lambda_def)
    else
      register_from_module(lambda_def, **opts)
    end
  end

  def register_from_hash(hash)
    LAMBDAS[hash[:name]] = {
      name:     hash[:name],
      gateway:  hash[:gateway],
      module:   hash[:module],
      wrapper:  hash[:wrapper]  || {},
      env:      hash[:env]      || {},
      settings: hash[:settings] || {}
    }
  end

  def register_from_module(mod, **opts)
    mod.singleton_methods.sort.each do |module_method|
      module_name     = mod.to_s
      module_names    = module_name.split('::').map(&:downcase)
      verb            = 'GET'
      path_fragments  = module_names.dup

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

      # delete is a special case based on method name
      verb = 'DELETE' if %w[destroy delete remove implode].include? module_method.to_s

      # finalize path
      path_fragments << module_method
      path = path_fragments.join('/')

      register_from_hash(
        {
          name: "#{module_names.join('-')}-#{module_method}",
          gateway: {
            verb: opts.dig(module_method, :gateway, :verb) || verb,
            path: opts.dig(module_method, :gateway, :path) || path
          },
          module: {
            name:   module_name,
            method: module_method.to_s,
            path:   module_names.join('/') # file name
          },
          wrapper:  opts.dig(module_method, :wrapper) || opts[:wrapper],
          env:      opts.dig(module_method, :env),
          settings: opts.dig(module_method, :settings)
        }
      )
    end
  end

  def set_env_values(lambda_def)
    # remove wrapper if already set
    %i(name method path).each{|key| ENV.delete("wrapper_#{key}")}

    # set env for each group
    %i(module gateway wrapper env).each do |group_key|
      lambda_def[group_key]&.each do |key, value|
        key = "#{group_key}_#{key}" if group_key != :env
        ENV[key.to_s] = value.to_s
      end
    end
  end

  def init_stack(app_name: Pathname.getwd.basename.to_s, s3_bucket:, **stack_opts)
    stack = StackBuilder.init({
        app_name:   app_name.camelize,
        s3_bucket:  s3_bucket,
      }.merge(stack_opts))

    # validate stack
    # puts 'Validating stack'
    # puts '- it is valid' if stack.valid?

    self.stack = stack
    generate_endoints if LAMBDAS.any?

    # return humidifier instance
    stack
  end

  def generate_endoints
    # add lambdas to stack
    puts 'Generating endpoints'
    LAMBDAS.each do |name, config|
      puts "- adding #{config.dig(:module, :name)}.#{config.dig(:module, :method)} to #{config.dig(:gateway, :path)}"
      stack.add_lambda_endpoint(
        gateway:  config[:gateway],
        mod:      config[:module],
        wrapper:  config[:wrapper]  || {},
        env:      config[:env]      || {},
        settings: config[:settings] || {}
      )
    end
  end
end
