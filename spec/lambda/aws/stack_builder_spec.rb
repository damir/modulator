describe 'CloudFormation template from AwsStackBuilder' do
  it 'builds ApiGatewayRestApi' do
    Dir.chdir('spec/test_app')

    # provide your own bucket via env
    $s3_bucket = ENV['S3BUCKET'] || 'modulator-lambdas'

    # stack settings
    $timeout = 20
    $memory_size = 256
    $app_envs = %w(development test production)

    # init stack
    $stack = AwsStackBuilder.init(
      app_name: 'DemoApp',
      bucket: $s3_bucket,
      timeout: $timeout,
      memory_size: $memory_size,
      app_envs: $app_envs
    )

    # add some stack parameters
    # $stack.add_parameter('Env', description: 'The deploy environment', type: 'String')

    # generated template
    template = JSON.parse($stack.to_cf(:json))

    # verify structure
    expect(template.keys).to eq(%w[AWSTemplateFormatVersion Outputs Parameters Resources])
    expect(template['Resources'].keys).to eq(%w[ApiGateway ApiGatewayDeployment LambdaRole DemoAppGemsLayer DemoAppLayer])

    # verify version
    expect(template['AWSTemplateFormatVersion']).to eq('2010-09-09')

    # verify parameters
    expect(template['Parameters']).to eq(
      {"ApiGatewayStageName"=>
        {"Type"=>"String", "Default"=>"v1", "Description"=>"Gateway deployment stage"},
       "AppEnvironment"=>
        {"AllowedValues"=>$app_envs, "Description"=>"Application environment", "Type"=>"String"}},
    )

    # verify Outputs
    expect(template['Outputs']).to eq(
      {"ApiGatewayInvokeURL"=>
        {"Value"=>
          {"Fn::Sub"=>
            "https://${ApiGateway}.execute-api.${AWS::Region}.amazonaws.com/${ApiGatewayStageName}"},
         "Description"=>"API root url",
         "Export"=>{"Name"=>"DemoAppRootUrl"}}}
    )

    # verify AWS::ApiGateway::RestApi
    expect(template.dig('Resources', 'ApiGateway')).to eq(
      {"Type"=>"AWS::ApiGateway::RestApi",
        "Properties"=>{"Name"=>"DemoApp", "Description"=>"DemoApp API"}},
    )

    # verify AWS::ApiGateway::Deployment
    expect(template.dig('Resources', 'ApiGatewayDeployment')).to eq(
      {"DependsOn"=>[],
        "Type"=>"AWS::ApiGateway::Deployment",
        "Properties"=>
         {"RestApiId"=>{"Ref"=>"ApiGateway"},
          "StageName"=>{"Ref"=>"ApiGatewayStageName"}}}
    )

    # verify AWS::IAM::Role
    expect(template.dig('Resources', 'LambdaRole')).to eq(
      {"Type"=>"AWS::IAM::Role",
        "Properties"=>
         {"AssumeRolePolicyDocument"=>
           {"Version"=>"2012-10-17",
            "Statement"=>
             [{"Action"=>["sts:AssumeRole"],
               "Effect"=>"Allow",
               "Principal"=>{"Service"=>["lambda.amazonaws.com"]}}]},
          "Policies"=>
           [{"PolicyDocument"=>
              {"Version"=>"2012-10-17",
               "Statement"=>
                [{"Action"=>["logs:CreateLogStream", "logs:PutLogEvents"],
                  "Effect"=>"Allow",
                  "Resource"=>
                   {"Fn::Sub"=>
                     "arn:aws:logs:${AWS::Region}:${AWS::AccountId}:*"}},
                 {"Action"=>["logs:CreateLogGroup"],
                  "Effect"=>"Allow",
                  "Resource"=>"*"}]},
             "PolicyName"=>"cloud-watch-access"}]}}
    )
  end

  it 'adds a lambda endpoint' do
    lambda_def = $lambda_defs.dig(:calculator, :sum)
    lambda_def[:mod] = lambda_def[:module]
    $stack.add_lambda_endpoint(env: {'abc' => '123'}, **lambda_def.slice(:gateway, :mod, :wrapper))
    template = JSON.parse($stack.to_cf(:json))

    # verify AWS::Lambda::Function
    expect(template.dig('Resources', 'LambdaCalculatorAlgebraSum')).to eq(
      {"Type"=>"AWS::Lambda::Function",
        "Properties"=>
         {"Description"=>"Lambda for Calculator::Algebra.sum",
          "FunctionName"=>"demo-app-calculator-algebra-sum",
          "Handler"=>"lambda-handler.AwsLambdaHandler.call",
          "Environment"=>
           {"Variables"=>
             {"abc"=>"123",
              "gateway_verb"=>"GET",
              "gateway_path"=>"calculator/algebra/:x/:y/sum",
              "module_name"=>"Calculator::Algebra",
              "module_method"=>"sum",
              "module_path"=>"test_app/calculator/algebra",
              "GEM_PATH"=>"/opt/ruby/2.5.0",
              "app_dir"=>"test_app",
              "app_env"=>{"Ref"=>"AppEnvironment"}}},
          "MemorySize"=>$memory_size,
          "Role"=>{"Fn::GetAtt"=>["LambdaRole", "Arn"]},
          "Timeout"=>$timeout,
          "Runtime"=>"ruby2.5",
          "Code"=>
           {"S3Bucket"=>$s3_bucket, "S3Key"=>"lambda-handler.rb.zip"},
          "Layers"=>[{"Ref"=>"DemoAppLayer"}, {"Ref"=>"DemoAppGemsLayer"}]}},
    )

    # verify AWS::Lambda::Permission
    expect(template.dig('Resources', 'LambdaPermission')).to eq(
      {"Type"=>"AWS::Lambda::Permission",
        "Properties"=>
         {"Action"=>"lambda:InvokeFunction",
          "FunctionName"=>{"Fn::GetAtt"=>["LambdaCalculatorAlgebraSum", "Arn"]},
          "Principal"=>"apigateway.amazonaws.com",
          "SourceArn"=>
           {"Fn::Sub"=>
             "arn:aws:execute-api:${AWS::Region}:${AWS::AccountId}:${ApiGateway}/*/GET/calculator/algebra/*/*/sum"}}}
    )

    # verify AWS::ApiGateway::Resource
    expect(template.dig('Resources', 'Calculator')).to eq(
      {"Type"=>"AWS::ApiGateway::Resource",
        "Properties"=>
         {"RestApiId"=>{"Ref"=>"ApiGateway"},
          "ParentId"=>{"Fn::GetAtt"=>["ApiGateway", "RootResourceId"]},
          "PathPart"=>"calculator"}}
    )
    expect(template.dig('Resources', 'CalculatorAlgebra')).to eq(
      {"Type"=>"AWS::ApiGateway::Resource",
        "Properties"=>
         {"RestApiId"=>{"Ref"=>"ApiGateway"},
          "ParentId"=>{"Ref"=>"Calculator"},
          "PathPart"=>"algebra"}},
    )
    expect(template.dig('Resources', 'CalculatorAlgebraX')).to eq(
      {"Type"=>"AWS::ApiGateway::Resource",
        "Properties"=>
         {"RestApiId"=>{"Ref"=>"ApiGateway"},
          "ParentId"=>{"Ref"=>"CalculatorAlgebra"},
          "PathPart"=>"{x}"}}
    )
    expect(template.dig('Resources', 'CalculatorAlgebraXY')).to eq(
      {"Type"=>"AWS::ApiGateway::Resource",
        "Properties"=>
         {"RestApiId"=>{"Ref"=>"ApiGateway"},
          "ParentId"=>{"Ref"=>"CalculatorAlgebraX"},
          "PathPart"=>"{y}"}}
    )
    expect(template.dig('Resources', 'CalculatorAlgebraXYSum')).to eq(
      {"Type"=>"AWS::ApiGateway::Resource",
        "Properties"=>
         {"RestApiId"=>{"Ref"=>"ApiGateway"},
          "ParentId"=>{"Ref"=>"CalculatorAlgebraXY"},
          "PathPart"=>"sum"}}
    )

    # verify AWS::ApiGateway::Method
    expect(template.dig('Resources', 'EndpointForCalculatorAlgebraXYSum')).to eq(
      {"Type"=>"AWS::ApiGateway::Method",
        "Properties"=>
         {"AuthorizationType"=>"NONE",
          "HttpMethod"=>"GET",
          "Integration"=>
           {"IntegrationHttpMethod"=>"POST",
            "Type"=>"AWS_PROXY",
            "Uri"=>
             {"Fn::Sub"=>
               ["arn:aws:apigateway:${AWS::Region}:lambda:path/2015-03-31/functions/${lambdaArn}/invocations",
                {"lambdaArn"=>{"Fn::GetAtt"=>["LambdaCalculatorAlgebraSum", "Arn"]}}]}},
          "RestApiId"=>{"Ref"=>"ApiGateway"},
          "ResourceId"=>{"Ref"=>"CalculatorAlgebraXYSum"}}}
    )

    # verify AWS::Lambda::LayerVersion
    gems_layer = template.dig('Resources', 'DemoAppGemsLayer')
    gems_layer['Properties']['Content']['S3ObjectVersion'] = 'dynamic' # s3 version_id
    expect(gems_layer).to eq(
      {"Type"=>"AWS::Lambda::LayerVersion",
        "Properties"=>
         {"CompatibleRuntimes"=>["ruby2.5"],
          "LayerName"=>"DemoAppGems",
          "Description"=>"App gems",
          "Content"=>
           {"S3Bucket"=>$s3_bucket,
            "S3Key"=>"test_app_gems.zip",
            "S3ObjectVersion"=>"dynamic"}}}
    )

    app_layer = template.dig('Resources', 'DemoAppLayer')
    checksum = Pathname.getwd.join(AwsStackBuilder.app_path, '.modulator', 'app_checksum').read
    app_layer['Properties']['Content']['S3ObjectVersion'] = 'dynamic'
    expect(app_layer).to eq(
      {"Type"=>"AWS::Lambda::LayerVersion",
        "Properties"=>
         {"CompatibleRuntimes"=>["ruby2.5"],
          "LayerName"=>"DemoApp",
          "Description"=>"App source. MD5: #{checksum}",
          "Content"=>
           {"S3Bucket"=>$s3_bucket,
            "S3Key"=>"test_app.zip",
            "S3ObjectVersion"=>"dynamic"}}}
    )
  end
end
