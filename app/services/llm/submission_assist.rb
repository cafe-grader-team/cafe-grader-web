module Llm
  class SubmissionAssist
    attr_reader :submission, :problem, :error

    # convenience method, this simply init and then call the service from the class
    # To use this class just do SASC.call(submission: sub, comment: comment, -- any other options --)
    # where
    #   SASC is a subclass of SubmissionAssistant
    #   sub is the submission that request assistant
    #   comment is the Comment record (saved to the database with initial data)
    #
    # This now accepts any set of keyword arguments (`**args`) and passes
    # them directly to the `new` method. This is the key change.
    def self.call(**args)
      new(**args).call
    end

    def initialize(submission:, **args)
      @submission = submission
      @problem = submission.problem
      @error = nil
      @other_args = args

      # Create a placeholder comment
      @record = @other_args[:comment]
      raise ArgumentError.new("Comment object is needed") unless @record
    end

    # This is the "template method". The ActiveJob will call this method (via self.call)
    # This will invoke other methods that must be implemented by the subclass
    def call
      data = prepare_data               # need to be implemented by the subclass
      response = execute_call(data)     # need to be implemented by the subclass
      handle_response(response)
    rescue Faraday::Error => e
      @error = "API Communication Error: #{e.message}"
      handle_error
      nil
    rescue RuntimeError => e
      @error = "Error: #{e.message}"
      handle_error
      nil
    end

    private

    # To be implemented by subclasses
    # prepare any data that is required by the call function
    def prepare_data
      raise NotImplementedError, "#{self.class} must implement #prepare_data"
    end

    # the execute_call is the one that call the LLM API with the data provided by the
    # prepare_data
    def execute_call(data)
      raise NotImplementedError, "#{self.class} must implement #execute_call"
    end

    # for parsing the response into a additional data
    # This must return a hash that will be merged with @record
    # and save to the comments of the submission
    #
    # May use @parsed_body
    def parse_response
      raise NotImplementedError, "#{self.class} must implement #parse_response"
    end

    # Can be a common implementation or overridden
    def handle_response(response)
      unless response&.success?
        @error = "API returned HTTP #{response&.status}: #{response&.body&.truncate(500)}"
        handle_error
        return nil
      end

      # prepare the @parsed_body for the parse_response of the subclasses
      @parsed_body = JSON.parse(response.body)
      validate_response_body! 

      @record.cost = 10
      @record.llm_response = response.body
      @record.status = 'ok'
      @record.update(parse_response)             # subclass must implement parse_response
    rescue JSON::ParseError => e
      @error = "Invalid JSON from #{provider_name}: #{e.message}"
      handle_error
      nil      
    end

    def handle_error
      @record.title = "Assistant Error"
      @record.body += "* Request finished at `#{Time.zone.now}`\n"
      @record.body += "<div class='alert alert-danger'> <h5>Request failed</h5> #{error} </div>"
      @record.status = 'error'
      @record.save
    end

    def provider_name
      raise NotImplementedError, "#{self.class} must implement #provider_name"
    end

    # retrieve all prompts from the llm_prompt tag of the problem
    def get_prompts_from_problem_tags
      @submission.problem.tags.where(kind: 'llm_prompt').map { |tag| tag.params }
    end

    # Centralized connection method
    def self.connection(api_base_url)
      Faraday.new(url: api_base_url) do |f|
        # Set the total time to allow for the request.
        f.options.timeout = 300 # 5 minutes

        # Set the time to wait for the initial connection to be opened.
        # This can usually be short.
        f.options.open_timeout = 10 # 10 seconds

        # Set the time to wait for a chunk of the response to be read.
        # This is the most important one for slow, generative APIs.
        f.options.read_timeout = 300 # 5 minutes

        f.request :json
        f.response :raise_error
        f.adapter Faraday.default_adapter
      end
    end
  end
end
