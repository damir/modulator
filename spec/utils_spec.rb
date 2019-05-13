describe 'Framework helpers for dev tools' do
  it 'underscores string' do
    expect('AbcDef-GHI.123'.underscore).to eq('abc_def_ghi.123')
  end

  it 'camelize string' do
    expect('abc_def-ghi.123'.camelize).to eq('AbcDefGhi.123')
  end

  it 'dasherize string' do
    expect('abc_def-Ghi.123'.dasherize).to eq('abc-def-ghi.123')
  end

  it 'stringify_keys in hash' do
    expect({a: [{b: {c: 123}}]}.stringify_keys).to eq({"a"=>[{"b"=>{"c"=>123}}]})
  end

  it 'symbolize_keys in hash' do
    expect({"a"=>[{"b"=>{"c"=>123}}]}.symbolize_keys).to eq({a: [{b: {c: 123}}]})
  end
end
