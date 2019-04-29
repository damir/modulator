module Calculator
  module Algebra
    def self.sum(x, y, z = 0)
      {
        x: x,
        y: y,
        z: z,
        sum: x + y + z
      }
    end
  end
end
