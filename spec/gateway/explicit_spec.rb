describe 'Gateway with explicit definitions' do
  before(:each) do
    Gateway.opts[:app_dir] = 'spec'
  end

  it 'POST to unknown path' do
    post '/unknown', {}
    expect(status).to eq(404)
  end

  it 'POST to pets/create' do
    Modulator.add_lambda($lambda_defs.dig(:pet, :create))
    payload = {id: 1, name: 'Bubi'}
    post '/pets/create', payload
    expect(status).to eq(200)
    expect(response).to eq(payload.stringify_keys)
  end

  it 'POST to pets/create for custom 422' do
    post '/pets/create', {id: 1, no_name: 'Bubi'}
    expect(status).to eq(422)
    expect(response).to eq({error: 'Missing name'}.stringify_keys)
  end

  it 'POST to pets/update' do
    Modulator.add_lambda($lambda_defs.dig(:pet, :update))
    payload = {id: 1, name: 'Cleo'}
    post '/pets/1/update', payload
    expect(status).to eq(200)
    expect(response).to eq(payload.stringify_keys)
  end

  it 'GET to pets/list' do
    Modulator.add_lambda($lambda_defs.dig(:pet, :list))
    get '/pets/list'
    expect(status).to eq(200)
    expect(response).to eq(Pet::PETS.stringify_keys)
  end

  it 'GET to pets/1/show' do
    Modulator.add_lambda($lambda_defs.dig(:pet, :show))
    get '/pets/1/show'
    expect(status).to eq(200)
    expect(response).to eq(Pet::PETS[1].stringify_keys)
  end

  it 'DELETE to pets/1/delete' do
    Modulator.add_lambda($lambda_defs.dig(:pet, :delete))
    delete '/pets/1/delete'
    expect(status).to eq(200)
    expect(response).to eq({id: 1, name: 'Cleo'}.stringify_keys)
  end

  it 'DELETE to pets/1/delete for 404' do
    delete '/pets/1/delete'
    expect(status).to eq(404)
    expect(response).to eq(nil)
  end
end
