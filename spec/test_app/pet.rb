module Pet
  module_function

  PETS = {}

  # GET pets/1
  def show(id)
    PETS[id]
  end

  # GET pets
  def list
    PETS
  end

  # POST pets/create
  def create(name = nil, pet: {})
    return {status: 422, body: {error: 'Missing name'}} unless pet.dig(:name)
    raise 'error thrown' if pet[:error]
    pet[:name] = name if name
    PETS[pet[:id]] = pet
  end

  # POST pets/:id/update
  def update(id, pet: {})
    return unless PETS[id]
    PETS[id] = pet
  end

  # DELETE pets/:id
  def delete(id)
    PETS.delete(id)
  end
end
