class CreateProblemPdfJob < ApplicationJob
  queue_as :default

  def perform(problem)
    ProblemPdfGenerator.new(problem).call
  end
end
