require_relative '../test_app/calculator/algebra'

describe 'Gateway with implicit definition with overrides' do
  it 'POST to Calculator::Algebra.sum with rearranged path and extra env' do
    Gateway.opts[:app_dir] = 'spec/test_app'
    Modulator.add_lambda(Calculator::Algebra,
      sum: {
        gateway: {
          verb: 'POST',
          path: 'calc/:x/add/:y',
        },
        env: {
          abc: 123
        }
      }
    )
    post 'calc/1/add/2', {}
    expect(status).to eq(200)
    expect(response).to eq({x: 1, y: 2, z: 0, sum: 3}.stringify_keys)
    expect(ENV['abc']).to eq('123')
  end
end
