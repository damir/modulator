require_relative '../pet'

describe Pet do
  it 'creates pet' do
    pet = {id: 1, name: 'Bubi'}
    Pet.create pet: pet
    expect(Pet::PETS).to eq(pet[:id] => pet)
  end

  it 'shows pet' do
    pet = Pet.show(1)
    expect(pet).to eq(Pet::PETS[1])
  end

  it 'lists pet' do
    list = Pet.list
    expect(list).to eq(Pet::PETS)
  end

  it 'updates pet' do
    pet = {id: 1, name: 'Cleo'}
    Pet.update 1, pet: pet
    expect(Pet::PETS).to eq(pet[:id] => pet)
  end

  it 'deletes pet' do
    Pet.delete(1)
    expect(Pet.list).to eq({})
    Pet::PETS.clear
  end
end
