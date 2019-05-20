require $spec_path.join 'test_app/pet.rb'

describe 'Wrappers for implicit definitions' do
  $payload = {id: 1, name: 'Bubi'}

  it 'executes pet-create with common wrapper for the module' do
    Modulator.register(Pet,
      wrapper: {
        name: 'Wrapper',
        method: 'authorize',
        path: 'wrapper'
      }
    )
    Modulator.set_env_values Modulator::LAMBDAS['pet-create']

    response = execute_lambda(
      event: $aws_event.merge(
        'body' => $payload.to_json,
        'pathParameters' => {},
        'headers' => {'Authorization' => 'pass'}
      ),
      app_path: $app_path
    )
    expect(response[:statusCode]).to eq(200)
    expect(JSON.parse(response[:body])).to eq($payload.stringify_keys)
  end

  it 'executes pet-create with wrapper for the method' do
    Modulator.register(Pet,
      wrapper: {
        name: 'other',
        method: 'other',
        path: 'other'
      },
      create: {
        wrapper: {
          name: 'Wrapper',
          method: 'authorize',
          path: 'wrapper'
        }
      }
    )
    Modulator.set_env_values Modulator::LAMBDAS['pet-create']

    response = execute_lambda(
      event: $aws_event.merge(
        'body' => $payload.to_json,
        'pathParameters' => {},
        'headers' => {'Authorization' => 'pass'}
      ),
      app_path: $app_path
    )
    expect(response[:statusCode]).to eq(200)
    expect(JSON.parse(response[:body])).to eq($payload.stringify_keys)
    Pet::PETS.clear
  end
end
