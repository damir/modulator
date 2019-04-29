pet_defs = {
  pet: {
    create:  {
      name: 'pet-create',
      gateway: {
        verb: 'POST',
        path: 'pets/create'
      },
      module: {
        name: 'Pet',
        method: 'create',
        path: 'test_app/pet'
      }
    },
    show:  {
      name: 'pet-show',
      gateway: {
        verb: 'GET',
        path: 'pets/:id/show'
      },
      module: {
        name: 'Pet',
        method: 'show',
        path: 'test_app/pet'
      }
    },
    update:  {
      name: 'pet-update',
      gateway: {
        verb: 'POST',
        path: 'pets/:id/update'
      },
      module: {
        name: 'Pet',
        method: 'update',
        path: 'test_app/pet'
      }
    },
    list:  {
      name: 'pet-list',
      gateway: {
        verb: 'GET',
        path: 'pets/list'
      },
      module: {
        name: 'Pet',
        method: 'list',
        path: 'test_app/pet'
      }
    },
    delete:  {
      name: 'pet-delete',
      gateway: {
        verb: 'DELETE',
        path: 'pets/:id/delete'
      },
      module: {
        name: 'Pet',
        method: 'delete',
        path: 'test_app/pet'
      }
    }
  }
}

calculator_defs = {
  calculator: {
    sum:  {
      name: 'calculator-algebra-sum',
      gateway: {
        verb: 'GET',
        path: 'calculator/algebra/:x/:y/sum'
      },
      module: {
        name: 'Calculator::Algebra',
        method: 'sum',
        path: 'test_app/calculator/algebra'
      }
    }
  }
}

$lambda_defs = pet_defs.merge(calculator_defs)
