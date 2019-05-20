describe 'Handler with casted path params' do
  it 'executes Calculator.sum with path params converted to numbers' do
    Modulator.set_env_values $lambda_defs.dig(:calculator, :sum)
    response = execute_lambda(event: $aws_event.merge('pathParameters' => {x: '1', y: '2.3'}))
    expect(response[:statusCode]).to eq(200)
    expect(JSON.parse(response[:body])).to eq({x: 1, y: 2.3, z: 0, sum: 3.3}.stringify_keys)
  end
end



