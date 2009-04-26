
module Grader

  class Initializer

    def self.run(&block)
      config = Grader::Configuration.get_instance
      yield config
    end

  end

end
