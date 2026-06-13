module EngineResponse
  # Define the Struct class inside the module namespace.
  # We'll name it 'Result' to be used as ServiceResponse::Result.
  Result = Struct.new(:status,               # either :success or :error
                      :result_description,   # human readable explanation of the result, mostly we store error message here
                     ) do
    # You can add helper methods right here!

    # A simple factory method for successful results
    def self.success(result_description: nil)
      new(status: :success, result_description: result_description)
    end

    # A factory method for failed results
    # This requires error messages
    def self.failure(error:)
      new(status: :error, result_description: error)
    end

    # The instance method `success?` is already defined by the Struct's
    # attribute name, so we don't need to add it again.
  end

  # checker result
  CheckerResult = Struct.new(:result,   # can be any of Evaluation.results.keys.map(&:to_sym), e.g., :correct, :wrong, :time_limit, etc..
                             :score,    # the score from 0.00 to 1.00
                             :comment,  # additional comment (display to the user)
                            ) do
    def self.correct(score: 1.to_d, comment: nil)
      new(result: :correct, score: score, comment: comment)
    end

    def self.wrong(score: 0.to_d, comment: nil)
      new(result: :wrong, score: score, comment: comment)
    end

    def self.partial(score:, comment: nil)
      new(result: :partial, score: score, comment: comment)
    end

    def self.grader_error(comment:)
      new(result: :grader_error, score: nil, comment: comment)
    end

    def self.by_score(score:, comment: nil)
      if score.to_f == 1
        self.correct(comment: comment)
      elsif score.to_f == 0
        self.wrong(comment: comment)
      else
        self.partial(score: score, comment: comment)
      end
    end
  end
end
