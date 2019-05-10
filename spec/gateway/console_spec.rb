describe 'Gateway console' do

  require_relative '../test_app/pet'
  require_relative '../test_app/calculator/algebra'
  Modulator.add_lambda(Pet)
  Modulator.add_lambda(Calculator::Algebra)

  $template_keys = %w[AWSTemplateFormatVersion Outputs Parameters Resources]

  it 'GET lists of lambdas' do
    get '/console/lambdas/list'
    expect(status).to eq(200)
    pp response
    expect(response).to eq(Modulator::LAMBDAS.stringify_keys)
  end

  it 'POST to stack/init for JSON' do
    post '/console/stack/init/json', {}
    expect(status).to eq(200)
    expect(response.keys).to eq($template_keys)
  end

  it 'POST to stack/init for YAML' do
    post '/console/stack/init', {}
    expect(status).to eq(200)
    template = Psych.load(response)
    expect(template.keys).to eq($template_keys)
  end
end
