describe 'Handler with wrapped explicit definitions' do
  $payload = {id: 1, name: 'Bubi'}

  it 'early return when wrapper returns status' do
    Modulator.set_env $lambda_defs.dig(:pet, :create)
      .merge wrapper: {
        name: 'Wrapper',
        method: 'authorize',
        path: 'test_app/wrapper'
      }
    response = execute_lambda(event: $aws_event.merge('body' => $payload.to_json, 'pathParameters' => {}, 'headers' => {'Authorization' => 'block'}))
    expect(response[:statusCode]).to eq(401)
    expect(JSON.parse(response[:body])).to eq({error: 'Invalid token'}.stringify_keys)
  end

  it 'early return when wrapper returns nothing' do
    response = execute_lambda(event: $aws_event.merge('body' => $payload.to_json, 'pathParameters' => {}, 'headers' => {}))
    expect(response[:statusCode]).to eq(403)
    expect(JSON.parse(response[:body])).to eq({forbidden: 'Wrapper.authorize'}.stringify_keys)
  end

  it 'executes pet-create lambda without args from wrapper' do
    response = execute_lambda(event: $aws_event.merge('body' => $payload.to_json, 'pathParameters' => {}, 'headers' => {'Authorization' => 'pass'}))
    expect(response[:statusCode]).to eq(200)
    expect(JSON.parse(response[:body])).to eq($payload.stringify_keys)
  end

  it 'executes pet-create lambda with optional args from executor' do
    Modulator.set_env $lambda_defs.dig(:pet, :create)
      .merge wrapper: {
        name: 'Wrapper',
        method: 'rename',
        path: 'test_app/wrapper'
      }
    response = execute_lambda(event: $aws_event.merge('body' => $payload.to_json, 'pathParameters' => {}, 'headers' => {'Authorization' => 'pass'}))
    expect(response[:statusCode]).to eq(200)
    expect(JSON.parse(response[:body])).to eq({id: 1, name: 'Cleo'}.stringify_keys)
    Pet::PETS.clear
  end
end
