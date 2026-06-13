require 'pathname'
require 'net/http'

class Compiler
  include IsolateRunner
  include JudgeBase
  include Rails.application.routes.url_helpers

  # Each language-specific sub-class MAY implement this method
  # this is used to check pre-condition of compilation
  # if implemented, the overridden function must call super()
  # -- this is rarely used --
  # -- see postgres for example --
  def validate
    raise GraderError.new("Sub ##{@sub.id} cannot find dataset ",
                          submission_id: @sub.id) unless @working_dataset
  end

  # Each language specific sub-class MUST implement this method
  # it should return shell command that do the compilation
  #   [isolate_source] is a full pathname to the source file (in isolate env.) to be compiled
  #   [isolate_bin] is a full pathname to the source file (in isolate env.) to store the compiled file
  def build_compile_command(isolate_source, isolate_bin)
  end

  # Each language specific sub-class MAY implement this method
  # it will be run BEFORE a compilation is success
  # normal use case is for java when we have to detect the classname of the file
  def pre_compile
  end

  # Each language specific sub-class MAY implement this method
  # it will be run after a compilation is success
  # normal use case is for scripting language
  # where compilation is actually linting and
  # post compile is to modify the source by adding shebang
  # or add any other script
  #   @exec_file is the compiled file
  def post_compile
  end

  # Each language specific sub-class MAY override this method
  # This should return {success: true, compiler_message: xxx}
  #   out = stdout
  #   err = stderr
  #   status = status text from isolate
  #   meta = meta object from isolate
  def check_compile_result(out, err, status, meta)
    if meta['exitcode'] == 0
      # compiler finished successfully
      return EngineResponse::Result.success(result_description: out)
    else
      # compiler found some error
      return EngineResponse::Result.failure(error: err)
    end
  end

  # main compile function
  # return EngineResponse::Result
  def compile(submission, dataset)
    @sub = submission
    @working_dataset = dataset
    # validate the pre-condition
    validate

    # init isolate
    need_cg = isolate_need_cg_by_lang(@sub.language.name)
    setup_isolate(@box_id, need_cg)

    begin

    # prepare source file
    prepare_submission_directory(@sub)
    prepare_files_for_compile

    # running any precompile script
    @exec_file = @compile_path + @sub.problem.exec_filename(@sub.language)
    pre_compile

    # ------ run the compilation ------
    # output file
    compile_meta = @compile_result_path + Grader::COMPILE_RESULT_META_FILENAME
    compile_stdout_file = @compile_result_path + Grader::COMPILE_RESULT_STDOUT_FILENAME
    compile_stderr_file = @compile_result_path + Grader::COMPILE_RESULT_STDERR_FILENAME

    # isolate filename for source to be compiled (considering self_contain? or task's main file)
    isolate_source_file = @sub.problem.with_managers? ?  @isolate_main_file : @isolate_source_file

    # isolate pathname for executable after compiled
    isolate_bin_file = @isolate_bin_path + @sub.problem.exec_filename(@sub.language)

    # calling language specific method to get cmd for compiling
    cmd_string = build_compile_command(isolate_source_file, isolate_bin_file)

    # prepare params for isolate
    isolate_args = %w[-p -E PATH]
    isolate_args << isolate_options_by_lang(@sub.language.name)
    output = { "#{@isolate_bin_path}": @compile_path.cleanpath}
    input = {"#{@isolate_source_path}": @source_path.cleanpath, "/source_manager": @manager_path.cleanpath}
    out, err, status, meta = run_isolate(cmd_string,
                       time_limit: 10,
                       input: input,
                       output: output,
                       isolate_args: isolate_args,
                       meta: compile_meta,
                       cg: need_cg)

    # save result
    File.write(compile_stdout_file, out)
    File.write(compile_stderr_file, err)

    # chmod the compile result
    run_isolate("/usr/bin/chmod -R 0777 #{@isolate_bin_path}", output: output)

    ensure
      cleanup_isolate(need_cg)
    end

    # call language-specific checking of compilation
    compile_result = check_compile_result(out, err, status, meta)

    if compile_result.status == :success
      # run any post compilation
      begin
        post_compile
      rescue => e
        raise GraderError.new("Error during post_compile of Sub ##{@sub.id} (Language = #{@sub.language.name}), msg = #{e.message}  ",
                              submission_id: @sub.id)
      end

      # the result should be at @bin_path
      begin
        upload_compiled_files
      rescue Net::HTTPExceptions => he
        raise GraderError.new("Error upload compiled file to server \"#{he}\"", submission_id: @sub.id)
      end

      @sub.update(status: :compilation_success, compiler_message: compile_result.result_description.truncate(15000))
      judge_log rb_sub(@sub) + Rainbow(' compilation completed successfully').color(COLOR_COMPILE_SUCCESS)
      return EngineResponse::Result.success(result_description: 'Compiled successfully')
    else
      # error in compilation
      judge_log rb_sub(@sub) + Rainbow(' compilation completed with error').color(COLOR_COMPILE_ERROR)
      @sub.update(status: :compilation_error, compiler_message: compile_result.result_description.truncate(15000),
                 points: 0, grader_comment: 'Compilation error', graded_at: Time.zone.now)
      return EngineResponse::Result.success(result_description: 'Compilation error')
    end
  end

  # Download (or save from db) source file and any manager files to their respective directory
  def prepare_files_for_compile
    # prepare the manager files
    # prepare_worker_dataset(@working_dataset,:managers_only)
    prepare_worker_dataset(@working_dataset, :all)

    # setup pathname
    @source_file = @source_path + self.get_submission_filename
    @source_main_file = @manager_path + (@working_dataset.main_filename || '')
    @isolate_source_file = @isolate_source_path + self.get_submission_filename
    @isolate_main_file = @isolate_source_manager_path + (@working_dataset.main_filename || '')

    # write student files
    File.write(@source_file.cleanpath, @sub.source)
    judge_log "Save contestant file to #{@source_file.cleanpath}"
  end

  def upload_compiled_files
    uri = URI(Rails.configuration.worker[:hosts][:web]+worker_compiled_submission_path(@sub))
    hostname = uri.hostname
    port = uri.port

    req = Net::HTTP::Post.new(uri) # => #<Net::HTTP::Post POST>
    req['x-api-key'] = Rails.configuration.worker[:worker_passcode]
    files = []

    # load files
    Dir.glob(@compile_path + '*').each do |fn|
      files << ['compiled_files[]', File.open(fn)]
      judge_log "Bundling compiled files #{fn}"
    end

    # upload compiled files to server
    req.set_form files, 'multipart/form-data'
    res = Net::HTTP.start(hostname, port) do |http|
      resp = http.request(req)
      if resp.kind_of?(Net::HTTPSuccess)
        judge_log "Successful uploading of compiled files to the server"
      else
        judge_log "Error uploading compiled file to the server"
        # raise the exception
        resp.value
      end
    end
  end

  # calculate the filename of the contestant submission to be saved to a source dir
  # for problem having "with managers" type, the submission_filename MUST exists
  def get_submission_filename
    if @sub.problem.with_managers? && @sub.problem.submission_filename.blank?
      raise GraderError.new("Manager Error: no submission filename",
                            submission_id: @sub.id)

    end

    if @sub.problem.submission_filename.blank?
      @sub.language.default_submission_filename
    else
      @sub.problem.submission_filename
    end
  end

  def self.get_compiler(sub)
    # TODO: should return appropriate compiler class
    case sub.language.name
    when 'cpp'
      return Compiler::Cpp
    when 'c'
      return Compiler::C
    when 'python'
      return Compiler::Python
    when 'ruby'
      return Compiler::Ruby
    when 'java'
      return Compiler::Java
    when 'digital'
      return Compiler::Digital
    when 'haskell'
      return Compiler::Haskell
    when 'php'
      return Compiler::Php
    when 'pas'
      return Compiler::Pascal
    when 'rust'
      return Compiler::Rust
    when 'go'
      return Compiler::Go
    when 'postgres'
      return Compiler::Postgres
    when 'archive'
      return Compiler::Blank
    when 'text'
      return Compiler::Blank
    else
      raise GraderError.new("Unsupported language (#{sub.language.name})",
                            submission_id: sub.id)
    end
  end
end
