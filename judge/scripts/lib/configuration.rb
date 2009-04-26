module Grader

  # This singleton class holds basic configurations for grader.  When
  # running in each mode, grader uses resources from different
  # directories and outputs differently.  Usually the attributes name
  # are descriptive; below we explain more on each attributes.
  class Configuration
    # Rails' environment: "development", "production"
    attr_accessor :rails_env

    # Grader looks for problem [prob] in problem_dir/[prob], and store
    # execution results for submission [x] of user [u] in directory
    # user_result_dir/[u]/[x]
    attr_accessor :problems_dir
    attr_accessor :user_result_dir

    # If report_grader=true, the grader would add a row in model
    # GraderProcess.  It would report itself with grader_hostname and
    # process id.
    attr_accessor :report_grader
    attr_accessor :grader_hostname    

    # If talkative=true, grader would report status to console.  If
    # logging=true, grader would report status to a log file located
    # in log_dir, in a file name mode.options.pid.  TODO: defined
    # log file naming.
    attr_accessor :talkative
    attr_accessor :logging
    attr_accessor :log_dir

    # These are directories related to the test interface.
    attr_accessor :test_request_input_base_dir
    attr_accessor :test_request_output_base_dir
    attr_accessor :test_request_problem_templates_dir

    # Comment received from the grading script will be filtered
    # through Configuration#report_comment.  How this method behave
    # depends on this option; right now only two formats, :short and
    # :long
    attr_accessor :comment_report_style

    def report_comment(comment)
      case comment_report_style
      when :short
        if comment.chomp =~ /^[\[\]P]+$/    # all P's
          'passed'
        elsif comment.chomp =~ /[Cc]ompil.*[Ee]rror/
          'compilation error'
        else
          'failed'
        end
        
      when :full
        comment.chomp
      end
    end

    # Codes for singleton
    private_class_method :new

    @@instance = nil

    def self.get_instance
      if @@instance==nil
        @@instance = new
      end
      @@instance
    end
    
    private
    def initialize
      @talkative = false
      @log_file = nil
      @report_grader = false
      @grader_hostname = `hostname`.chomp

      @rails_env = 'development'
      
      @comment_report_style = :full
    end

  end

end
