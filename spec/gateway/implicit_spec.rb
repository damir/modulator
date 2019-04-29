require_relative '../test_app/pet'

describe Pet do
  before(:each) do
    Gateway.opts[:app_dir] = 'spec/test_app'
    Modulator.add_lambda(Pet)
  end

  it 'POST to Pet.create' do
    payload = {id: 1, name: 'Bubi'}
    post '/pet/create', payload
    expect(status).to eq(200)
    expect(response).to eq(payload.stringify_keys)
  end

  it 'POST to Pet.create for custom 422' do
    post '/pet/create', {id: 1, no_name: 'Bubi'}
    expect(status).to eq(422)
    expect(response).to eq({error: 'Missing name'}.stringify_keys)
  end

  it 'POST to Pet.update' do
    payload = {id: 1, name: 'Cleo'}
    post '/pet/1/update', payload
    expect(status).to eq(200)
    expect(response).to eq(payload.stringify_keys)
  end

  it 'GET to Pet.list' do
    get '/pet/list'
    expect(status).to eq(200)
    expect(response).to eq(Pet::PETS.stringify_keys)
  end

  it 'GET to Pet.show' do
    get '/pet/1/show'
    expect(status).to eq(200)
    expect(response).to eq(Pet::PETS[1].stringify_keys)
  end

  it 'DELETE to Pet.delete' do
    delete '/pet/1/delete'
    expect(status).to eq(200)
    expect(response).to eq({id: 1, name: 'Cleo'}.stringify_keys)
  end

  it 'DELETE to Pet.delete for 404' do
    delete '/pet/1/delete'
    expect(status).to eq(404)
    expect(response).to eq(nil)
  end
end
