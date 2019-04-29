require $spec_path.join 'test_app/pet.rb'
require $spec_path.join 'test_app/calculator/algebra'

describe Modulator do
  $empty_defs = {env: {}, wrapper: {}, settings: {}}

  it 'registers lambda explicitly' do
    Modulator::LAMBDAS.clear
    lambda_config = $lambda_defs.dig(:pet, :create)
    Modulator.add_lambda(lambda_config)
    expect(Modulator::LAMBDAS).to eq(lambda_config[:name] => lambda_config.merge($empty_defs))
  end

  it 'registers module with namespace' do
    Modulator::LAMBDAS.clear
    Modulator.add_lambda(Calculator::Algebra)
    expect(Modulator::LAMBDAS['calculator-algebra-sum']).to eq(
      {:name=>"calculator-algebra-sum",
        :gateway=>{:verb=>"GET", :path=>"calculator/algebra/:x/:y/sum"},
        :module=>
         {:name=>"Calculator::Algebra",
          :method=>"sum",
          :path=>"calculator/algebra"}
      }.merge($empty_defs)
    )
  end

  it 'registers module with overriden path and verb' do
    Modulator::LAMBDAS.clear
    Modulator.add_lambda(Calculator::Algebra, sum: {
        gateway: {
          verb: 'POST',
          path: 'calc/:x/add/:y'
        }
      }
    )
    expect(Modulator::LAMBDAS['calculator-algebra-sum']).to eq(
      {:name=>"calculator-algebra-sum",
        :gateway=>{:verb=>"POST", :path=>"calc/:x/add/:y"},
        :module=>
        {:name=>"Calculator::Algebra",
          :method=>"sum",
          :path=>"calculator/algebra"}
      }.merge($empty_defs)
    )
  end

  it 'registers module with custom env' do
    Modulator::LAMBDAS.clear
    env = {abc: 123}
    Modulator.add_lambda(Calculator::Algebra, sum: {env: env})
    expect(Modulator::LAMBDAS['calculator-algebra-sum'][:env]).to eq(env)
  end

  it 'registers module with settings' do
    Modulator::LAMBDAS.clear
    settings = {timeout: 100}
    Modulator.add_lambda(Calculator::Algebra, sum: {settings: settings})
    expect(Modulator::LAMBDAS['calculator-algebra-sum'][:settings]).to eq(settings)
  end

  # verify settings form reflection on method signatures
  it 'registers multiple modules' do
    Modulator::LAMBDAS.clear
    Modulator.add_lambda(Pet)
    expect(Modulator::LAMBDAS.keys).to eq %w(pet-create pet-delete pet-list pet-show pet-update)
  end

  it 'registers module with wrapper' do
    Modulator::LAMBDAS.clear
    wrapper = {
      name: 'Wrapper',
      method: 'authorize',
      path: 'wrapper'
    }
    Modulator.add_lambda(Pet, wrapper: wrapper)

    # verify that all methods are wrapped
    Modulator::LAMBDAS.each do |name, _defs|
      expect(Modulator::LAMBDAS[name][:wrapper]).to eq(wrapper)
    end
  end

  it 'registers module as GET lambda without arguments' do
    Modulator.add_lambda(Pet)
    expect(Modulator::LAMBDAS['pet-list']).to eq({
      name: 'pet-list',
      :module => {:method=>"list", :name=>"Pet", :path=>"pet"},
      :gateway => {:path=>"pet/list", :verb=>"GET"}}.merge($empty_defs)
    )
  end

  it 'registers module as GET lambda with argument' do
    expect(Modulator::LAMBDAS['pet-show']).to eq({
      name: 'pet-show',
      :module => {:method=>"show", :name=>"Pet", :path=>"pet"},
      :gateway => {:path=>"pet/:id/show", :verb=>"GET"}}.merge($empty_defs)
    )
  end

  it 'registers module as DELETE lambda with argument' do
    expect(Modulator::LAMBDAS['pet-delete']).to eq({
      name: 'pet-delete',
      :module => {:method=>"delete", :name=>"Pet", :path=>"pet"},
      :gateway => {:path=>"pet/:id/delete", :verb=>"DELETE"}}.merge($empty_defs)
    )
  end

  it 'registers module as POST lambda without argument' do
    expect(Modulator::LAMBDAS['pet-create']).to eq({
      name: 'pet-create',
      :module => {:method=>"create", :name=>"Pet", :path=>"pet"},
      :gateway => {:path=>"pet/create", :verb=>"POST"}}.merge($empty_defs)
    )
  end

  it 'registers module as POST lambda with argument' do
    expect(Modulator::LAMBDAS['pet-update']).to eq({
      name: 'pet-update',
      :module => {:method=>"update", :name=>"Pet", :path=>"pet"},
      :gateway => {:path=>"pet/:id/update", :verb=>"POST"}}.merge($empty_defs)
    )
  end
end
