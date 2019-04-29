describe Utils do
  it 'underscores string' do
    expect('AbcDefGHI123'.underscore).to eq('abc_def_ghi123')
  end

  it 'camelize string' do
    expect('abc_def_ghi123'.camelize).to eq('AbcDefGhi123')
  end

  it 'dasherize string' do
    expect('abc_def_ghi123'.dasherize).to eq('abc-def-ghi123')
  end

  it 'stringify_keys hash' do
    expect({a: [{b: {c: 123}}]}.stringify_keys).to eq({"a"=>[{"b"=>{"c"=>123}}]})
  end

  it 'simbolize hash' do
    expect({"a"=>[{"b"=>{"c"=>123}}]}.symbolize_keys).to eq({a: [{b: {c: 123}}]})
  end
end
