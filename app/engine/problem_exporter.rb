class ProblemExporter
  require 'open3'

  INP_EXT = 'in'
  ANS_EXT = 'sol'

  attr_reader :problem, :log, :errors, :got, :dataset


  def initialize
    @log = []
    @options = {}
    @inp_ext = INP_EXT
    @ans_ext = ANS_EXT
  end

  def export_pdf
    return unless @problem.statement.attached?
    @statement_filename = @main_dir + OptionConst::DEFAULT[:file][:statement]
    @statement_filename.dirname.mkpath

    File.open(@statement_filename, 'w:ASCII-8BIT') do |f|
      @problem.statement.download { |chunk| f.write(chunk) }
    end
  end

  def export_attachment
    return unless @problem.attachment.attached?
    @attachment_filename = @main_dir + OptionConst::DEFAULT[:dir][:attachment] + @problem.attachment.filename.to_s
    @attachment_filename.dirname.mkpath

    File.open(@attachment_filename, 'w:ASCII-8BIT') do |f|
      @problem.attachment.download { |chunk| f.write(chunk) }
    end
  end

  def export_testcases
    @testcase_dir = @main_dir + OptionConst::DEFAULT[:dir][:testcases]
    @testcase_dir.mkpath
    tc_options = {}
    @ds.testcases.each do |tc|
      basename = tc.code_name || tc.num
      inp_fn = @testcase_dir + "#{basename}.#{@inp_ext}"
      ans_fn = @testcase_dir + "#{basename}.#{@ans_ext}"
      tc_options[basename] = {
        group: tc.group,
        group_name: tc.group_name,
        weight: tc.weight
      }

      File.open(inp_fn, 'w:ASCII-8BIT') do |f|
        tc.inp_file.download { |chunk| f.write(chunk) }
      end
      File.open(ans_fn, 'w:ASCII-8BIT') do |f|
        tc.ans_file.download { |chunk| f.write(chunk) }
      end
    end
    @options[OptionConst::YAML_KEY[:testcases_pattern]] = '*'
    @options[OptionConst::YAML_KEY[:dir][:testcases]] = OptionConst::DEFAULT[:dir][:testcases]
    @options[OptionConst::YAML_KEY[:testcases]] = tc_options
  end

  def export_managers_checker
    @manager_dir = @main_dir + OptionConst::DEFAULT[:dir][:managers]
    @manager_dir.mkpath
    @ds.managers.each do |mng|
      filename = @manager_dir + mng.filename.to_s
      File.open(filename, 'w:ASCII-8BIT') { |f| mng.download { |chunk| f.write chunk } }
      @options[OptionConst::YAML_KEY[:managers_pattern]] = '*'
    end

    if @ds.checker.attached?
      @checker_dir = @main_dir + OptionConst::DEFAULT[:dir][:checker]
      @checker_dir.mkpath
      @checker_filename = @checker_dir + OptionConst::DEFAULT[:file][:checker]
      File.open(@checker_filename, 'w:ASCII-8BIT') { |f| @ds.checker.download { |chunk| f.write chunk } }
      @options[OptionConst::YAML_KEY[:checker]] = @checker_filename.basename.to_s
      @options[OptionConst::YAML_KEY[:dir][:checker]] = @checker_filename.dirname.to_s
    end
  end

  def export_solutions
    @sol_dir = @main_dir + OptionConst::DEFAULT[:dir][:model_sols]
    @sol_dir.mkpath
    @problem.submissions.where(tag: :model).each do |sub|
      sub_dir = @sol_dir + sub.id.to_s
      sub_dir.mkpath
      fn = sub_dir + "#{sub.language.name}_#{sub.source_filename}"
      File.write(fn, sub.source)
    end
  end

  def export_initializers
    @initializer_dir = @main_dir + OptionConst::DEFAULT[:dir][:initializers]
    @initializer_dir.mkpath
    @ds.initializers.each do |mng|
      filename = @initializer_dir + mng.filename.to_s
      File.open(filename, 'w:ASCII-8BIT') { |f| mng.download { |chunk| f.write chunk } }
    end
  end

  # save the @options hash into a YAML file
  def export_options
    # problem fields
    # MUST MATCH ONES IN problem_importer.rb + "name"
    p_options = %i[name full_name submission_filename task_type compilation_type permitted_lang]
    p_options.each do |opt|
      @options[opt] = @problem.send(opt) unless @problem.send(opt).blank?
      @options[opt] = @options[opt].to_f if @options[opt].is_a? BigDecimal
    end

    # live dataset fields
    # MUST MATCH ONES IN problem_importer.rb
    d_options = %i[time_limit memory_limit score_type evaluation_type main_filename initializer_filename]
    d_options.each do |opt|
      @options[opt] = @ds.send(opt) unless @ds.send(opt).blank?
      @options[opt] = @options[opt].to_f if @options[opt].is_a? BigDecimal
    end
    @options[OptionConst::YAML_KEY[:ds_name]] = @ds.name

    # managers, checker, initializers
    @options[OptionConst::YAML_KEY[:dir][:managers]] = OptionConst::DEFAULT[:dir][:managers]
    @options[OptionConst::YAML_KEY[:dir][:checker]] = OptionConst::DEFAULT[:dir][:checker]
    @options[OptionConst::YAML_KEY[:dir][:model_sols]] = OptionConst::DEFAULT[:dir][:model_sols]
    @options[OptionConst::YAML_KEY[:dir][:initializers]] = OptionConst::DEFAULT[:dir][:initializers]

    # tags
    @options[OptionConst::YAML_KEY[:tags]] = @problem.tags.pluck :name if @problem.tags.count > 0

    # allowed_
    config_filename = @main_dir + OptionConst::YAML_FILENAME
    # we need to stringify, else the YAML.safe_load won't work directly
    File.write(config_filename, @options.deep_stringify_keys.to_yaml)
  end

  # this export the problem and its live dataset to a dir
  # with the name of the problem into *base_dir*
  # when zip is true, "#{problem.name}.zip" is also generated and saved to *base_dir*
  def export_problem_to_dir(problem, base_dir: Rails.root.join('../judge/dump'), zip: fasle)
    result = {}
    @problem = problem
    @ds = @problem.live_dataset
    raise 'No live dataset' unless @ds

    @main_dir = Pathname.new(base_dir) + problem.name.parameterize

    # clean the directory
    FileUtils.rm_rf(@main_dir)

    # export everything

    export_pdf
    export_attachment
    export_testcases
    export_managers_checker
    export_initializers
    export_options
    export_solutions
    result[:status] = :ok

    if zip
      zip_name = "#{problem.name.parameterize}.zip"
      zip_path = Pathname.new(base_dir) + zip_name

      # remove old file, if exists
      FileUtils.rm(zip_path) if File.exist?(zip_path)

      cmd = "zip ../#{zip_name} -r *"
      out, err, status = Open3.capture3(cmd, chdir: @main_dir)
      @log << out

      result[:zip] = zip_path
      if status != 0
        result[:status] = :error
        result[:error] = err
      end
    end

    result[:log] = @log.clone
    return result
  end


  # dump all problem in *probs* to base_dir
  # Usage
  #   ProblemExporter.dump_problems(Problem.where(id: 123), base_dir = '/home/user/dump')
  def self.dump_problems(probs = Problem.available, base_dir = Rails.root.join('../judge/dump'))
    probs.each do |p|
      pe = ProblemExporter.new
      pe.export_problem_to_dir(p, base_dir: base_dir)
      puts "dump '#{p.name}' to #{base_dir}"
    end
  end
end
