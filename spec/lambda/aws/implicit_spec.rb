require $spec_path.join 'test_app/pet.rb'

describe 'Handler with implicit definitions' do
  it 'registers lambda implicitly' do
    Modulator::LAMBDAS.clear
    Modulator.add_lambda(Pet)
    $aws_event.merge!('body' => {}, 'pathParameters' => {}, 'httpMethod' => 'POST')
  end

  it 'executes pet-create lambda' do
    Modulator.set_env Modulator::LAMBDAS['pet-create']
    payload = {id: 1, name: 'Bubi'}
    response = execute_lambda(event: $aws_event.merge('body' => payload.to_json), app_path: $app_path)
    expect(response[:statusCode]).to eq(200)
    expect(JSON.parse(response[:body])).to eq(payload.stringify_keys)
  end

  it 'executes pet-update lambda' do
    Modulator.set_env Modulator::LAMBDAS['pet-update']
    payload = {id: 1, name: 'Cleo'}
    response = execute_lambda(event: $aws_event.merge('body' => payload.to_json, 'pathParameters' => {id: '1'}), app_path: $app_path)
    expect(response[:statusCode]).to eq(200)
    expect(JSON.parse(response[:body])).to eq(payload.stringify_keys)
  end

  it 'executes pet-list lambda' do
    Modulator.set_env Modulator::LAMBDAS['pet-list']
    payload = {id: 1}
    response = execute_lambda(app_path: $app_path)
    expect(response[:statusCode]).to eq(200)
    expect(JSON.parse(response[:body])).to eq(Pet::PETS.stringify_keys)
  end

  it 'executes pet-show lambda' do
    Modulator.set_env Modulator::LAMBDAS['pet-show']
    response = execute_lambda(event: $aws_event.merge('pathParameters' => {id: '1'}), app_path: $app_path)
    expect(response[:statusCode]).to eq(200)
    expect(JSON.parse(response[:body])).to eq({id: 1, name: 'Cleo'}.stringify_keys)
  end

  it 'executes pet-delete lambda' do
    Modulator.set_env Modulator::LAMBDAS['pet-delete']
    response = execute_lambda(event: $aws_event.merge('pathParameters' => {id: '1'}), app_path: $app_path)
    expect(response[:statusCode]).to eq(200)
    expect(JSON.parse(response[:body])).to eq({id: 1, name: 'Cleo'}.stringify_keys)
  end

  it 'executes pet-delete lambda with 404 status' do
    response = execute_lambda(event: $aws_event.merge('pathParameters' => {id: '1'}), app_path: $app_path)
    expect(response[:statusCode]).to eq(404) # already deleted
    expect(JSON.parse(response[:body])).to eq(nil)
    Pet::PETS.clear
  end

  # it 'executes pet-delete lambda with wrapper' do
  #   Modulator.add_lambda(Pet, wrapper: {
  #       name: 'authorizer',
  #       method: 'call',
  #       path: 'authorizer'
  #     }
  #   )
  #   Modulator.set_env Modulator::LAMBDAS['pet-delete']
  #   response = execute_lambda(event: $aws_event.merge('pathParameters' => {id: '1'}, 'headers' => {'Authorization' => 'Simple block'}), app_path: $app_path)
  #   expect(response[:statusCode]).to eq(401)
  #   expect(JSON.parse(response[:body])).to eq({error: 'Invalid token'}.stringify_keys)
  # end
end
