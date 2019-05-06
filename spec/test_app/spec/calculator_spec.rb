require_relative '../calculator/algebra'

describe 'Test app Calculator module' do
  it 'calculates sum without optional positional and optional key args' do
    result = Calculator::Algebra.sum(1, 2)
    expect(result).to eq({x: 1, y: 2, z: 0, sum: 3})
  end

  it 'calculates sum without optional key arg' do
    result = Calculator::Algebra.sum(1, 2, 3)
    expect(result).to eq({x: 1, y: 2, z: 3, sum: 6})
  end
end
