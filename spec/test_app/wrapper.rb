module Wrapper
  module_function

  def authorize(event:, context:)
    token = event.dig('headers', 'Authorization').to_s.split(' ').last
    if token == 'block'
      {status: 401, body: {error: 'Invalid token'}}
    elsif token == 'pass'
      true # pass
    else
      # block with generic 403
      # false
    end
  end

  def rename(event:, context:)
    {name: 'Cleo'}
  end
end
