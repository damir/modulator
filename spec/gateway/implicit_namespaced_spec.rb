require_relative '../test_app/calculator/algebra'

describe 'Gateway with implicit definition for namespaced module' do
  it 'GET to Calculator::Algebra.sum with namespaced path' do
    Gateway.opts[:app_dir] = 'spec/test_app'
    Modulator.register(Calculator::Algebra)

    get 'calculator/algebra/1/2/sum'
    expect(status).to eq(200)
    expect(response).to eq({x: 1, y: 2, z: 0, sum: 3}.stringify_keys)
  end
end
