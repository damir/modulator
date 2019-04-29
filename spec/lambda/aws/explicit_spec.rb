describe Modulator do
  it 'executes pet-create lambda with 500 when exception is thrown' do
    Modulator.set_env $lambda_defs.dig(:pet, :create)
    payload = {id: 1, name: 'Bubi', error: true}
    response = execute_lambda(event: $aws_event.merge('body' => payload.to_json, 'pathParameters' => {}))
    expect(response[:statusCode]).to eq(500)
  end

  it 'executes pet-create lambda with custom status' do
    payload = {id: 1}
    response = execute_lambda(event: $aws_event.merge('body' => payload.to_json, 'pathParameters' => {}))
    expect(response[:statusCode]).to eq(422)
    expect(JSON.parse(response[:body])).to eq('error' => 'Missing name')
  end

  it 'executes pet-create lambda with default 200 status' do
    payload = {id: 1, name: 'Bubi'}
    response = execute_lambda(event: $aws_event.merge('body' => payload.to_json, 'pathParameters' => {}))
    expect(response[:statusCode]).to eq(200)
    expect(JSON.parse(response[:body])).to eq(payload.stringify_keys)
    Pet::PETS.clear
  end
end
