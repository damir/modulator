# Modulator

Modulator is a tool for adding HTTP layer on top of your application using AWS Lambda and API Gateway services. You register the methods you want to publish and run the deploy script. CloudFormation engine will then provision the necessary infrastructure and deploy your application in seconds.

Because your application is isolated form HTTP handling you will write regular Ruby code without polluting it with framework or HTTP specific details. This is possible by reflecting on method signatures to construct API Gateway endpoints and consuming its events in predictable way.

Code is deployed in two lambda layers, one for the gems and one for the application code. You will need a writable bucket to store the files and ability to manage CloudFormation stacks.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'modulator', group: :development
```

And then execute:

    $ bundle

NOTE: do not put modulator entry outside the group, the tool will bundle default group for deployment and the gem is not required in lambda runtime

## Usage

### Quick example

Write Ruby application:

```ruby
# calculator/algebra.rb:

module Calculator
  module Algebra
    def self.sum(x, y)
      {
        x: x,
        y: y,
        sum: x + y
      }
    end

    def self.square(x, ip = nil)
      {
        x: x,
        ip: ip,
        square: x * x
      }
    end
  end
end
```

Add deploy script to working directory:

```ruby
# stack.rb

require 'modulator'
require_relative 'calculator/algebra'

# register module methods
Modulator.register(Calculator::Algebra)

# initialize and deploy the stack
stack = Modulator.init_stack s3_bucket: 'my-modulator-apps' # bucket for code and gems layers
puts stack.valid?
puts stack.to_cf(:yaml)
puts stack.deploy_and_wait capabilities: ['CAPABILITY_IAM'], parameters: [
  {parameter_key: 'AppEnvironment', parameter_value: 'development'},
  {parameter_key: 'ApiGatewayStageName', parameter_value: 'v1'}
]
```

Run the script then visit CloudFormation page in AWS console and navigate to created stack, click on Outputs tab and copy ApiGatewayInvokeURL:

- https://some-api-id.execute-api.us-east-1.amazonaws.com/v1

Then Invoke your methods using the browser or postman:

- https://some-api-id.execute-api.us-east-1.amazonaws.com/v1/algebra/2/square
- https://some-api-id.execute-api.us-east-1.amazonaws.com/v1/algebra/2/3/sum

These URLs are also available in lambda page when clicking on API Gateway icon:

```
ModulatorGatewayApp
arn:aws:execute-api:us-east-1:your-account-id:some-api-id/*/GET/calculator/algebra/*/square

Details
API endpoint: https://some-api-id.execute-api.us-east-1.amazonaws.com/v1/calculator/algebra/{x}/square
Authorization: NONE
Method: GET
Resource path: /calculator/algebra/{x}/square
Stage: v1
```

You can save CF template to a file by capturing output of stack.to\_cf(:yaml) or stack.to\_cf(:json.) 

### Wrapping the method to get data from lambda event and context

Data from the request can be extracted using wrapper method which will pass the values to wrapped method as optional arguments. This example will wrap Calculator::Algebra#square with Wrappers::Authorizer#call to autorize request and provide optional ip argument:

```ruby
# wrappers/authorizer.rb

module Wrappers
  module Authorizer
    module_function

    def call(event:, context:)
      token = event.dig('headers', 'Authorization').to_s.split(' ').last
      if token == 'block'
        {status: 401, body: {error: 'Blocking token'}}
      elsif token == 'pass'
        {ip: event.dig('requestContext', 'identity', 'sourceIp')}
      else
        # block with generic 403
      end
    end
  end
end
```

```ruby
# stack.rb
require_relative 'wrappers/authorizer'
Modulator.register(Calculator::Algebra).wrap_with(Wrappers::Authorizer, only: :square)
```

This method can be invoked only when Aurhorization header is set to 'pass', otherwise it will print explcit 401 with custom message when the value is 'block', or will default to 403 with generic message.

Available options are :only and :except where value is the method name or an array of names.

### Registering and configuring methods

Registering module will add configuration entry to Modulator::LAMBDAS. Each entry is a plain hash which can be overriden. From this configuration a CloudFormation template is generated with all necessary resources for API Gateway endpoints and their lambdas, including function policies and execution roles.

Consider this example:

```ruby
Modulator
  .register(Calculator::Algebra, sum: {
      gateway: {path: 'calc/:x/add/:y'},
      settings: {timeout: 1, memory_size: 256},
      env: {custom_var: 123}
    }
  )
  .wrap_with(Wrappers::Authorizer, only: [:square])
```

For that example Modulator::LAMBDAS will print this configuration:

```ruby
{"calculator-algebra-square"=>
  {:name=>"calculator-algebra-square",
   :gateway=>{:verb=>"GET", :path=>"calculator/algebra/:x/square"},
   :module=>
    {:name=>"Calculator::Algebra",
     :method=>"square",
     :path=>"calculator/algebra"},
   :wrapper=>
    {:name=>"Wrappers::Authorizer",
     :path=>"wrappers/authorizer",
     :method=>"call"},
   :env=>{},
   :settings=>{}},
 "calculator-algebra-sum"=>
  {:name=>"calculator-algebra-sum",
   :gateway=>{:verb=>"GET", :path=>"calc/:x/add/:y"},
   :module=>
    {:name=>"Calculator::Algebra",
     :method=>"sum",
     :path=>"calculator/algebra"},
   :wrapper=>{},
   :env=>{:custom_var=>123},
   :settings=>{:timeout=>1, :memory_size=>256}}}
```

- :gateway is used to construct API Gateway endpoint, it has :path key from which the URL is constructed and :verb which sets the HTTP method for that URL
- :wrapper defines wrapping method, :name is the module namespace, :method is the method name from that namespace and :path is the relative file path where the code is
- :settings holds lambda settings values, :timeout and :memory_size
- :env will add extra environment variables to lambda runtime

Any value can be changed manualy during or after the config is generated if you want to override defaults. For example you can change :verb from GET to DELETE or you can rearrange static and dynamic URL path fragments.

### Rules for mapping URL paths and HTTP methods to method signatures

- Methods will be invoked with GET unless:
	- the method name is delete, remove, or destroy for which DELETE is set
	- the method has optional key paramater for which POST is set and payload is passed as its value
- Required positional parameters are mapped as dinamic URL fragments, numbers are type casted to ruby classes
- Module namespace and method name are mapped as static URL fragments

For examples please check the spec folder and the sample application code there.

### Local API gateway for development

It is possible to run code locally as it would run in the cloud. You need to add config.ru and register some modules:

```ruby
# config.ru

require 'modulator/gateway/gateway'
require_relative 'calculator/algebra'
require_relative 'wrappers/authorizer'
Modulator.register(Calculator::Algebra).wrap_with(Wrappers::Authorizer, only: [:square])
```

Then start the server with this command:

	rerun -- puma gateway.ru

NOTE: rerun will restart the server when code changes.

Visiting localhost:9292/calculator/algebra/2/square should give this result:

```ruby
{
    "x": 2,
    "ip": "127.0.0.1",
    "square": 4
}
``` 

Server log will print detailed information about request and method invocation:

```
Method: GET
Path: /calculator/algebra/2/square
Headers: {
	"Accept"=>"*/*", "Accept-Encoding"=>"gzip, deflate", "Authorization"=>"pass",
	"Cache-Control"=>"no-cache", "Connection"=>"keep-alive", "Host"=>"localhost:9292",
	"Postman-Token"=>"8708ee60-a156-4ca2-9937-f1f408a568e2",
	"User-Agent"=>"PostmanRuntime/7.13.0", "Version"=>"HTTP/1.1"}
Path params: {"x"=>"2"}
Calling wrapper Wrappers::Authorizer.call
Resolving GET calculator/algebra/:x/square to Calculator::Algebra.square with [[:req, :x], [:opt, :ip]]
Matched path: /calculator/algebra/2/square
Status: 200
Took: 0.00117 seconds
```

Local gateway is implemented with [Roda](https://github.com/jeremyevans/roda).

### Manipulating generated CloudFormation template

Modulator#init_stack will return [Humidifier](https://github.com/kddeisz/humidifier) instance which allows for easy manipulation of generated CF template. If you need to add more resources or tweak existing ones please consult its documentation. 

One example of extending the template is Modulator#add_policy which adds extra policies to lambdas by passing optional values to init method:

```ruby
Modulator.init_stack(
  lambda_policies: [{name: :dynamo_db, prefixes: ['my-app']}],
)
```

This will give lambdas an access to DynamoDB tables prefixed by 'my-app'. Alternatively you could do it directly by providing your own policy:

```ruby
stack.resources['LambdaRole'].properties['policies'] << my_policy_template
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/damir/modulator. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Modulator project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/modulator/blob/master/CODE_OF_CONDUCT.md).
