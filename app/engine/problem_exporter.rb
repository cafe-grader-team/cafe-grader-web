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

  def export_testcases_to(ds, dir, opts)
    tc_dir = dir + OptionConst::DEFAULT[:dir][:testcases]
    tc_dir.mkpath
    tc_options = {}
    ds.testcases.each do |tc|
      basename = tc.code_name || tc.num
      tc_options[basename] = { group: tc.group, group_name: tc.group_name, weight: tc.weight }
      File.open(tc_dir + "#{basename}.#{@inp_ext}", 'w:ASCII-8BIT') { |f| tc.inp_file.download { |c| f.write(c) } }
      File.open(tc_dir + "#{basename}.#{@ans_ext}", 'w:ASCII-8BIT') { |f| tc.ans_file.download { |c| f.write(c) } }
    end
    opts[OptionConst::YAML_KEY[:testcases_pattern]] = '*'
    opts[OptionConst::YAML_KEY[:dir][:testcases]] = OptionConst::DEFAULT[:dir][:testcases]
    opts[OptionConst::YAML_KEY[:testcases]] = tc_options
  end

  def export_managers_checker_to(ds, dir, opts)
    manager_dir = dir + OptionConst::DEFAULT[:dir][:managers]
    manager_dir.mkpath
    ds.managers.each do |mng|
      File.open(manager_dir + mng.filename.to_s, 'w:ASCII-8BIT') { |f| mng.download { |c| f.write c } }
      opts[OptionConst::YAML_KEY[:managers_pattern]] = '*'
    end

    return unless ds.checker.attached?

    checker_dir = dir + OptionConst::DEFAULT[:dir][:checker]
    checker_dir.mkpath
    checker_fn = checker_dir + OptionConst::DEFAULT[:file][:checker]
    File.open(checker_fn, 'w:ASCII-8BIT') { |f| ds.checker.download { |c| f.write c } }
    opts[OptionConst::YAML_KEY[:checker]] = checker_fn.basename.to_s
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

  def export_initializers_to(ds, dir)
    init_dir = dir + OptionConst::DEFAULT[:dir][:initializers]
    init_dir.mkpath
    ds.initializers.each { |m| File.open(init_dir + m.filename.to_s, 'w:ASCII-8BIT') { |f| m.download { |c| f.write c } } }
  end

  def export_description
    return if @problem.description.blank?
    File.write(@main_dir + OptionConst::DEFAULT[:file][:description], @problem.description)
  end

  def export_data_files_to(ds, dir)
    df_dir = dir + OptionConst::DEFAULT[:dir][:data_files]
    df_dir.mkpath
    ds.data_files.each { |df| File.open(df_dir + df.filename.to_s, 'w:ASCII-8BIT') { |f| df.download { |c| f.write c } } }
  end

  # Write all of `ds`'s dataset-scoped files under `dir` and populate `opts`
  # with that dataset's config (testcases, dir keys, dataset fields, ds_name).
  def export_dataset_files(ds, dir, opts)
    export_testcases_to(ds, dir, opts)
    export_managers_checker_to(ds, dir, opts)
    export_initializers_to(ds, dir)
    export_data_files_to(ds, dir)

    OptionConst::DATASET_OPTION_FIELDS.each do |opt|
      value = ds.send(opt)
      next if value.blank?
      value = value.to_f if value.is_a?(BigDecimal)
      opts[opt] = value
    end
    opts[OptionConst::YAML_KEY[:ds_name]] = ds.name
    opts[OptionConst::YAML_KEY[:dir][:managers]] = OptionConst::DEFAULT[:dir][:managers]
    opts[OptionConst::YAML_KEY[:dir][:checker]] = OptionConst::DEFAULT[:dir][:checker]
    opts[OptionConst::YAML_KEY[:dir][:initializers]] = OptionConst::DEFAULT[:dir][:initializers]
    opts[OptionConst::YAML_KEY[:dir][:data_files]] = OptionConst::DEFAULT[:dir][:data_files]
  end

  # Problem-scoped options + write the root config.yml. Dataset fields/testcases
  # for the live dataset are already in @options via export_dataset_files.
  def export_root_options
    p_options = [:name] + OptionConst::PROBLEM_OPTION_FIELDS
    p_options.each do |opt|
      value = @problem.send(opt)
      next if value.blank?
      value = value.to_f if value.is_a?(BigDecimal)
      @options[opt] = value
    end
    @options[:markdown] = !!@problem.markdown if @problem.description.present?
    @options[OptionConst::YAML_KEY[:dir][:model_sols]] = OptionConst::DEFAULT[:dir][:model_sols]
    @options[OptionConst::YAML_KEY[:tags]] = @problem.tags.pluck(:name) if @problem.tags.count.positive?

    File.write(@main_dir + OptionConst::YAML_FILENAME, @options.deep_stringify_keys.to_yaml)
  end

  # A filesystem-safe, unique subdir name for a dataset (parameterized name,
  # de-duplicated against names already used in this export).
  def unique_ds_dirname(ds, taken)
    base = ds.name.to_s.parameterize
    base = 'dataset' if base.blank?
    name = base
    i = 2
    while taken.include?(name)
      name = "#{base}-#{i}"
      i += 1
    end
    name
  end

  # this export the problem and its live dataset to a dir
  # with the name of the problem into *base_dir*
  # when zip is true, "#{problem.name}.zip" is also generated and saved to *base_dir*
  def export_problem_to_dir(problem, base_dir: Rails.root.join('../judge/dump'), zip: false, all_datasets: false)
    result = {}
    @problem = problem
    @ds = @problem.live_dataset
    raise 'No live dataset' unless @ds

    @main_dir = Pathname.new(base_dir) + problem.name.parameterize

    # clean the directory
    FileUtils.rm_rf(@main_dir)

    # export everything

    @options = {}
    export_pdf
    export_attachment
    export_description
    export_dataset_files(@ds, @main_dir, @options)   # live dataset -> root

    if all_datasets
      taken = []
      @problem.datasets.where.not(id: @ds.id).order(:id).each do |ds|
        dirname = unique_ds_dirname(ds, taken)
        taken << dirname
        sub = @main_dir + 'datasets' + dirname
        frag = {}
        export_dataset_files(ds, sub, frag)
        File.write(sub + OptionConst::YAML_FILENAME, frag.deep_stringify_keys.to_yaml)
      end
      @options[OptionConst::YAML_KEY[:additional_datasets]] = taken unless taken.empty?
    end

    export_root_options
    export_solutions
    result[:status] = :ok

    if zip
      zip_name = "#{problem.name.parameterize}.zip"
      zip_path = Pathname.new(base_dir) + zip_name

      # remove old file, if exists
      FileUtils.rm(zip_path) if File.exist?(zip_path)

      out, err, status = Open3.capture3('zip', "../#{zip_name}", '-r', '.', chdir: @main_dir.to_s)
      @log << out

      result[:zip] = zip_path
      if !status.success?
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
  def self.dump_problems(probs = Problem.available, base_dir = Rails.root.join('../judge/dump'), all_datasets: false)
    probs.each do |p|
      ProblemExporter.new.export_problem_to_dir(p, base_dir: base_dir, all_datasets: all_datasets)
      puts "dump '#{p.name}' to #{base_dir}"
    end
  end
end
