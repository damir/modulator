require 'roda'
require 'modulator'

class Gateway < Roda
  plugin :json
  plugin :hooks
  plugin :json_parser
  plugin :pass
  plugin :all_verbs
  plugin :multi_route
  plugin :default_headers, 'Content-Type'=>'application/json'

  my_dir = Pathname.new(__FILE__).dirname
  my_dir.glob('routes/*.rb').each{|file| require_relative file}
  DUMMY_AWS_EVENT = Utils.load_json my_dir.parent.join('../../spec/lambda/aws/event.json')

  before do
    @time = Time.now
    puts
    puts "Method: #{env['REQUEST_METHOD']}"
    puts "Path: #{request.path}"
    puts "Payload: #{request.params}" if request.params.any?
    puts "Query string: #{env['QUERY_STRING']}" unless env['QUERY_STRING'].size.zero?
    @headers = Hash[*env.select {|k,v| k.start_with? 'HTTP_'}
      .collect {|k,v| [k.sub(/^HTTP_/, ''), v]}
      .collect {|k,v| [k.split('_').collect(&:capitalize).join('-'), v]}
      .sort
      .flatten]
    puts "Headers: #{@headers}"
  end

  after do |res|
    puts "Matched path: #{request.matched_path}"
    puts "Status: #{response.status}"
    puts ("Took: #{Time.now - @time} seconds")
  end

  plugin :error_handler do |e|
    puts
    error = {error: e.class, message: e.message, backtrace: e.backtrace&.take(10)}
    puts "FAILED: #{error}"
    error
  end

  route do |r|
    r.root do
      {working_dir: Pathname.getwd}
    end

    r.multi_route # tools routes

    # process lambda configs
    Modulator::LAMBDAS.each do |lambda_name, lambda_config|
      # puts "* Registering #{lambda_name}"
      # pp lambda_config

      # module and wrapper config
      Modulator.set_env lambda_config

      # build route
      @path_params = {}
      build_route(r, ENV['gateway_verb'], ENV['gateway_path'].split('/'))
    end

    # return 404 if no route is found, the loop will return 200 otherwise
    r.halt
  end

  def build_route(r, verb, fragments)
    # end of path, tail is gone: [] -> nil
    return unless fragments

    # execute when all fragments are processed
    execute_lambda(r, verb) and return if fragments.empty?

    # traverse fragments
    fragment = fragments.first
    tail = fragments[1..-1] || []

    # dynamic fragment
    if fragment.start_with?(':')
      r.on String do |value|
        fragment = fragment[1..-1]
        @path_params[fragment] = value
        build_route(r, verb, tail)
        r.pass # continue loop
      end

    # static fragment
    else
      r.on fragment do
        build_route(r, verb, tail)
        r.pass # continue loop
      end
    end
  end

  def execute_lambda(r, verb)
    r.send(verb.downcase) do
      puts "Path params: #{@path_params}"

      # build aws event
      aws_event = DUMMY_AWS_EVENT.merge(
        'pathParameters' => @path_params,
        'queryStringParameters' => {},
        'headers' => @headers,
        'body' => request.params.to_json
      )

      # build aws context
      aws_context = {}

      # execute lambda
      result = Dir.chdir(opts[:app_dir] || '.') do
        AwsLambdaHandler.call(event: aws_event, context: aws_context)
      end

      # render
      response.status = result[:statusCode]
      result[:body]
    end
  end
end
