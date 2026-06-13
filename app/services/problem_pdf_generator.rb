require "open3"
require "tempfile"

class ProblemPdfGenerator
  # We initialize the service with the object it needs to operate on.
  def initialize(problem)
    @problem = problem
    @description = problem.description
  end

  # The main public method, often called `call` or a more descriptive name.
  def call
    return Result.new(success: false, message: "Description is blank.") unless @description.present?

    begin
      Tempfile.create(["problem_statement_", ".pdf"]) do |pdf_tempfile|
        # --- All the Pandoc logic is now cleanly encapsulated here ---
        pandoc_command = [
          "pandoc", "-s", "--pdf-engine=xelatex",
          "-f", "markdown",
          "-V", "mainfont=Sarabun Light",
          "-V", "monofont=Sarabun Light",
          "-V", "mathfont=Latin Modern Math",
          "-M", "lang=th",
          "-o", pdf_tempfile.path
        ]

        _stdout_str, stderr_str, status = Open3.capture3(pandoc_command.shelljoin, stdin_data: @description)

        if status.success?
          attach_pdf(pdf_tempfile)
          Result.new(success: true)
        else
          error_message = "Pandoc PDF generation failed for Problem ##{@problem.id}: #{stderr_str}"
          Rails.logger.error error_message
          Result.new(success: false, message: error_message)
        end
      end
    rescue StandardError => e
      error_message = "Error during PDF generation/attachment for Problem ##{@problem.id}: #{e.message}"
      Rails.logger.error error_message
      Result.new(success: false, message: error_message)
    end
  end

  # A private helper class for returning a clear result from the service.
  Result = Struct.new(:success, :message, keyword_init: true)

  private

  def attach_pdf(pdf_tempfile)
    @problem.generated_statement.detach if @problem.generated_statement.attached?
    @problem.generated_statement.attach(
      io: File.open(pdf_tempfile.path),
      filename: "problem_statement_#{@problem.id}.pdf",
      content_type: "application/pdf"
    )
  end
end
