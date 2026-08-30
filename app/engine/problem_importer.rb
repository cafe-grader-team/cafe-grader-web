class ProblemImporter
  attr_reader :problem, :log, :errors, :got, :dataset

  RESERVED_DATASETS_DIRNAME = 'datasets'

  require 'open3'
  def initialize
    @got = []
    @log = []
    @options = {}
    @errors = []
  end

  def read_testcase(input_pattern, sol_pattern, code_name_regex, group_name_regex)
    # glob testcase filename and build hash of key: testcase codename, value: {input: input_file, output: output_file}
    @tc = Hash.new { |h, k| h[k] = Hash.new }
    Dir["#{@base_dir}/**/#{input_pattern}"].select { |fn| outside_reserved_datasets?(fn) }.each do |fn|
      # input_fn = Pathname.new(@base_dir) + fn
      input_fn = Pathname.new(fn)
      regex = Regexp.new input_pattern.gsub('*', '(.+)')

      # try to match the codename with the regex
      mc = input_fn.basename.to_s.match regex
      next unless mc
      name = mc[1]


      # default codename, use the part that match the wildcard
      codename = name

      # parse codename according to regex
      codename_mc = name.match code_name_regex
      codename = codename_mc[1] if codename_mc

      @tc[codename][:input] = input_fn.cleanpath
    end
    Dir["#{@base_dir}/**/#{sol_pattern}"].select { |fn| outside_reserved_datasets?(fn) }.each do |fn|
      sol_fn = Pathname.new(fn)
      regex = Regexp.new sol_pattern.gsub('*', '(.+)')

      # try to match the codename with the regex
      mc = sol_fn.basename.to_s.match regex
      next unless mc
      name = mc[1]

      # default codename, use the part that match the wildcard
      codename = name

      # parse codename according to regex
      codename_mc = name.match code_name_regex
      codename = codename_mc[1] if codename_mc

      @tc[codename][:sol] = sol_fn.cleanpath
    end

    # load into dataset and testcase
    num = @dataset.testcases.count + 1
    group = 1
    group_hash = {}

    # we sort the filename by their natural sort order
    natural_order_sorted = @tc.keys.sort_by { |s| s.split(/[^\d]+/).map { |e| Integer(e, 10) rescue 0 } }
    natural_order_sorted.each do |codename|
      if @tc[codename].count >= 2
        # we found both the input and sol
        # the codename is the key of the hash

        # default weight
        weight = 1


        # parse group_name and build group number
        group_name = group_hash.count + 1
        mg = @tc[codename][:input].basename.to_s.match group_name_regex
        group_name = mg[1] if mg # if match, we will use the captured pattern

        if group_hash.has_key? group_name
          group = group_hash[group_name]
        else
          group = group_hash.count + 1
          group_hash[group_name] = group
        end

        # overwrite with options if exists
        if @options.has_key?(OptionConst::YAML_KEY[:testcases]) && @options[OptionConst::YAML_KEY[:testcases]].has_key?(codename.to_sym)
          weight = @options[OptionConst::YAML_KEY[:testcases]][codename.to_sym][:weight]
          group = @options[OptionConst::YAML_KEY[:testcases]][codename.to_sym][:group]
          group_name = @options[OptionConst::YAML_KEY[:testcases]][codename.to_sym][:group_name]
        end

        # create new testcase
        new_tc = @dataset.testcases.where(code_name: codename).first
        if new_tc
          @log << "replace existing testcase with codename #{codename} (num,weight,group,group_name are #{[num, weight, group, group_name].join ','})"
          new_tc.weight = weight
          new_tc.group = group
          new_tc.group_name = group_name
        else
          @log << "add a testcase #{num} with codename #{codename} (num,weight,group,group_name are #{[num, weight, group, group_name].join ','})"
          new_tc = Testcase.new(code_name: codename, num: num, group: group, weight: weight, group_name: group_name)
          num +=1
        end
        input = File.read(@tc[codename][:input]).gsub(/\r$/, '')
        ans = File.read(@tc[codename][:sol]).gsub(/\r$/, '')
        new_tc.inp_file.attach(io: StringIO.new(input), filename: 'input.txt', content_type: 'text/plain',  identify: false)
        new_tc.ans_file.attach(io: StringIO.new(ans),   filename: 'answer.txt', content_type: 'text/plain',  identify: false)
        @dataset.testcases << new_tc
        @log << "  #{@tc[codename][:input]} is the input"
        @log << "  #{@tc[codename][:sol]} is the sol"
      end
    end

    @problem.save
  end

  def load_options
    yaml, fn = get_content_of_first_match('config.yml')
    if yaml
      @options = YAML.safe_load(yaml, symbolize_names: true)
    end
  end

  def read_options
    # process options for dataset
    p_options = OptionConst::PROBLEM_OPTION_FIELDS
    p_options.each do |opt|
      if @options.has_key? opt
        @log << "problem.#{opt} is set to '#{@options[opt]}' by options file"
        @problem.write_attribute(opt, @options[opt]) if @options.has_key? opt
      end
    end

    # live dataset fields
    d_options = OptionConst::DATASET_OPTION_FIELDS
    d_options.each do |opt|
      if @options.has_key? opt
        @log << "dataset.#{opt} is set to '#{@options[opt]}' by options file"
        # Through the writer, not write_attribute: Dataset#evaluation_type=
        # normalizes the pre-rev-2047 names (custom_cms, custom_cms_raw) that
        # packages exported by older versions still carry.
        @dataset.public_send("#{opt}=", @options[opt])
      end
    end

    # tags
    if @options[OptionConst::YAML_KEY[:tags]]
      # calculate non-existing tags
      non_exists = @options[OptionConst::YAML_KEY[:tags]] - Tag.where(name: @options[OptionConst::YAML_KEY[:tags]]).pluck(:name)
      non_exists.each { |name| Tag.create(name: name) }

      @problem.tags = Tag.where(name: @options[OptionConst::YAML_KEY[:tags]])
      @log << "set tags to [#{@options[OptionConst::YAML_KEY[:tags]].join(', ')}]"
    end
  end

  # CMS semantics: a group has ONE weight; scorer.rb's group_min uses the
  # minimum weight found in the group. Mixed weights are an authoring error.
  # Shares Dataset#mixed_weight_groups with the dataset edit UI warning so the
  # two can never disagree on what counts as "mixed".
  def warn_mixed_group_weights
    @dataset.mixed_weight_groups.each do |g, weights|
      @log << "WARNING: group #{g} has mixed testcase weights (#{weights.join(', ')}); group_min uses one weight per group (the minimum, #{weights.first}). Fix the weights in the package."
    end
  end

  # Import any datasets listed under the root config's additional_datasets key,
  # each from datasets/<name>/, as NON-live datasets on @problem. Reuses the
  # existing dataset-scoped read methods by pointing them at the subdir.
  def import_additional_datasets(input_pattern = '*.in', sol_pattern = '*.sol',
                                 code_name_regex = /(.*)/, group_name_regex = /^(\d+)-/)
    names = @options[OptionConst::YAML_KEY[:additional_datasets]]
    return unless names.is_a?(Array)

    outer_base, outer_dataset, outer_options = @base_dir, @dataset, @options
    problem = outer_dataset.problem
    # Snapshot from @problem (not the local `problem`/`outer_dataset.problem`):
    # read_cpp_extras purges+reloads @dataset for manager-file housekeeping, and
    # a reloaded association returns a *fresh* Problem instance on the next
    # `.problem` call — divorced from @problem's in-memory state (which may
    # carry not-yet-saved corrections from the root import's read_options).
    # @problem is the one consistent reference the whole import saves at the end.
    saved_compilation_type = @problem.compilation_type
    saved_submission_filename = @problem.submission_filename
    begin
      names.each do |dirname|
        subdir = Pathname.new(outer_base) + RESERVED_DATASETS_DIRNAME + dirname.to_s
        unless subdir.exist?
          @log << "WARNING: additional dataset dir missing: #{subdir}"
          next
        end

        cfg = subdir + OptionConst::YAML_FILENAME
        @options = cfg.exist? ? YAML.safe_load(File.read(cfg), symbolize_names: true) : {}
        @base_dir = subdir.to_s
        display_name = @options[OptionConst::YAML_KEY[:ds_name]] || dirname
        @dataset = problem.datasets.where(name: display_name).first ||
                   Dataset.new(name: display_name, problem: problem)
        @dataset.save

        read_testcase(input_pattern, sol_pattern, code_name_regex, group_name_regex)
        read_checker
        read_cpp_extras
        read_initializers
        read_data_files
        read_options   # applies this dataset's fields (fragment carries no problem-level keys)
        @dataset.save
        @log << "WARNING: additional dataset '#{display_name}' imported with 0 testcases" if @dataset.testcases.count.zero?
        @log << "Imported additional dataset '#{display_name}'"
      end
    ensure
      @base_dir, @dataset, @options = outer_base, outer_dataset, outer_options
      if @problem.compilation_type != saved_compilation_type || @problem.submission_filename != saved_submission_filename
        @problem.update_columns(compilation_type: saved_compilation_type,
                                submission_filename: saved_submission_filename)
      end
    end
  end

  def read_statement
    # pdf
    pdf, fn = get_content_of_first_match('*.pdf')
    if pdf
      @problem.statement.attach(io: StringIO.new(pdf), filename: fn.basename)
      @log << "Found a pdf statement [#{fn}]"
      @got << fn
    else
      @log << "no pdf file is given as a statement"
    end

    # additional description
    md, fn = get_content_of_first_match('*.md')
    if md
      @problem.description = md
      # config.yml's :markdown (applied later in read_options) wins;
      # legacy packages without the key: a .md present means markdown
      @problem.markdown = true unless @options.has_key?(:markdown)
      @problem.save
      @log << "Found addtional Markdown file [#{fn}]"
      @got << fn
    end
  end

  def read_attachment
    # pdf
    path = @options[OptionConst::YAML_KEY[:dir][:attachment]] || OptionConst::DEFAULT[:dir][:attachment]
    file, fn = get_content_of_first_match('*', path: path)
    if file
      @problem.attachment.attach(io: StringIO.new(file), filename: fn.basename)
      @log << "Found an attachment [#{fn}]"
      @got << fn
    end
  end

  def read_cpp_extras
    # main
    main_filename = ['main.cpp', 'main_grader.cpp', 'grader.cpp']
    main_filename = @options[:main] if @options.has_key?(:main)
    path = @options[OptionConst::YAML_KEY[:dir][:managers]] || ''
    main, fn = get_content_of_first_match(main_filename, path: path)
    if main
      @log << "Found the main file [#{fn}]"
      @got << fn
      # delete existing
      @dataset.managers.each { |f| f.purge if f.filename == Pathname.new(fn).basename }
      @dataset.reload

      # add new file
      @dataset.managers.attach(io: File.open(fn), filename: Pathname.new(fn).basename)
      @dataset.main_filename = Pathname.new(fn).basename   # may be overwritten in read_options
      @problem.compilation_type = 'with_managers'          # may be overwritten in read_options
      @problem.submission_filename = 'student.h'           # may be overwritten in read_options
      @problem.save
      @dataset.save
    end

    # any .h or manager
    managers = @options[OptionConst::YAML_KEY[:managers_pattern]] || '*.h'
    pattern = build_glob(managers, path: @options[OptionConst::YAML_KEY[:dir][:managers]] || '')
    managers_fn = {}
    Dir.glob(pattern).each do |fn|
      @log << "Found an additional manager file [#{fn}]"
      @got << fn
      basename = Pathname.new(fn).basename
      if managers_fn.has_key? basename
        @log << "  ERROR: multiple managers of the same name #{basename}"
      else
        managers_fn[basename] = true
        # delete existing
        @dataset.managers.each { |f| f.purge if f.filename == basename }
        @dataset.reload

        @dataset.managers.attach(io: File.open(fn), filename: basename)
      end
    end
    @dataset.save
  end

  # take any checker_pattern file as a checker
  def read_checker
    # glob checker
    checker_path = @options[OptionConst::YAML_KEY[:dir][:checker]] || ''
    checker_pattern = @options[OptionConst::YAML_KEY[:checker]] || OptionConst::DEFAULT[:file][:checker]
    checker, fn = get_content_of_first_match(checker_pattern, path: checker_path)
    if checker
      @log << "Found a custom checker file [#{fn}]"
      @got << fn
      @dataset.checker.attach(io: StringIO.new(checker), filename: fn.basename)
    end
  end

  def read_initializers
    # any initializers
    initializers = @options[OptionConst::YAML_KEY[:initializers_pattern]] || '*'
    path = @options[OptionConst::YAML_KEY[:dir][:initializers]] || OptionConst::DEFAULT[:dir][:initializers]
    pattern = build_glob(initializers, path: path)
    initializers_fn = {}
    Dir.glob(pattern).each do |fn|
      @log << "Found an additional initializers file [#{fn}]"
      @got << fn
      basename = Pathname.new(fn).basename
      if initializers_fn.has_key? basename
        @log << "  ERROR: multiple initializers of the same name #{basename}"
      else
        initializers_fn[basename] = true
        # delete existing
        @dataset.initializers.each { |f| f.purge if f.filename == basename }
        @dataset.reload

        @dataset.initializers.attach(io: File.open(fn), filename: basename)
      end
    end

    # set the main initializer
    initializer_filename = @options[OptionConst::YAML_KEY[:initializer]]
    if initializer_filename
      @dataset.initializer_filename = initializer_filename
      @log << "  main initializer is set to #{initializer_filename}"
    end
    @dataset.save
  end

  def read_data_files
    path = @options[OptionConst::YAML_KEY[:dir][:data_files]] || OptionConst::DEFAULT[:dir][:data_files]
    pattern = build_glob('*', path: path)
    seen = {}
    Dir.glob(pattern).each do |fn|
      pn = Pathname.new(fn)
      next if pn.directory?

      @log << "Found a data file [#{fn}]"
      @got << fn
      basename = pn.basename
      if seen.has_key? basename
        @log << "  ERROR: multiple data files of the same name #{basename}"
      else
        seen[basename] = true
        @dataset.data_files.each { |f| f.purge if f.filename == basename }
        @dataset.reload
        @dataset.data_files.attach(io: File.open(fn), filename: basename)
      end
    end
    @dataset.save
  end

  # Root-level recursive reads must not descend into the reserved datasets/
  # subtree — it holds additional datasets, imported separately by
  # import_additional_datasets.
  def outside_reserved_datasets?(path)
    reserved = File.join(@base_dir.to_s, RESERVED_DATASETS_DIRNAME) + '/'
    !path.to_s.start_with?(reserved)
  end

  def get_content_of_first_match(glob_pattern, recursive: true, path: '')
    pattern = build_glob(glob_pattern, recursive: recursive, path: path)
    files = Dir.glob(pattern).select { |p| File.file?(p) && outside_reserved_datasets?(p) }
    if files.count > 0
      if files.count > 1
        @log << "ERROR: Found multiples of #{glob_pattern} while we expected one"
        return
      end

      full_path = Pathname.new(files[0])
      return File.read(full_path.cleanpath), full_path.cleanpath
    end

    # match none
    return nil
  end

  # build glob pattern array from glob_patterns
  # add recursive path if needed
  def build_glob(glob_patterns, recursive: false, path: '')
    glob_patterns = [glob_patterns] unless glob_patterns.is_a? Array
    result = glob_patterns.map do |p|
      pattern = @base_dir.to_s + '/'
      pattern += path + '/' unless path.blank?
      pattern += '**/' if recursive
      pattern += p
      pattern
    end
    return result
  end

  def read_solutions(user: nil)
    user ||= User.first
    solutions_dir = @options[OptionConst::YAML_KEY[:dir][:model_sols]] || OptionConst::DEFAULT[:dir][:model_sols]
    pattern = build_glob('*', recursive: true, path: solutions_dir)
    Dir.glob(pattern).each do |fn|
      pn = Pathname.new(fn)
      next if pn.directory?

      @log << "Found a model solution file [#{fn}]"
      # filename convention: <language>_<original_filename>, e.g. cpp_fibo.cpp
      lang_name, sep, source_name = pn.basename.to_s.partition('_')
      if sep.empty?
        @log << "  ERROR: solution filename '#{pn.basename}' has no <lang>_ prefix; skipped"
        next
      end

      language = Language.where(name: lang_name).first
      # explicit guard: save!(validate: false) below skips must_specify_language,
      # so an unknown <lang>_ prefix must be rejected here, not silently saved
      if language.nil?
        @log << "  ERROR: unknown language prefix '#{lang_name}' in '#{pn.basename}'; skipped"
        next
      end
      sub =  Submission.new(user: user,
                            problem: @problem,
                            submitted_at: Time.zone.now,
                            language: language,
                            source_filename: source_name,
                            tag: :model)
      sub.source = File.open(fn, 'r:UTF-8', &:read)
      sub.source.encode!('UTF-8', 'UTF-8', invalid: :replace, replace: '')

      # validate: false — trusted server-side import; the submitting user is an
      # arbitrary stand-in (User.first) and the problem is typically still a
      # draft, so must_have_valid_problem would wrongly reject model solutions.
      # Same bypass as the repair/replay engines. before_save still assigns the
      # next submission number.
      begin
        sub.save!(validate: false)
        sub.add_judge_job
      rescue ActiveRecord::ActiveRecordError => e
        @log << "  ERROR: could not save solution: #{e.message}"
      end
    end
  end

  # import dataset in the dir into a problem,
  # might also set it as a live dataset
  # If the problem with the same name exist, this will add another dataset
  # if *dataset* is nil, this will be imported to a new dataset
  # if not, it will override the given dataset "without deleting anything of that dataset"
  #    a testcase with the same codename will be replaced
  def import_dataset_from_dir(dir, name,
    full_name: name,      # required keyword
    dataset: nil,         # if nil, we will create a new dataset
    delete_existing: false,
    input_pattern: '*.in',
    sol_pattern: '*.sol',
    code_name_regex: /(.*)/,       # how we get code_name from the matched wildcard
    group_name_regex: /^(\d+)-/,   # how we extract group name from codename
    memory_limit: 512,
    time_limit: 1,
    do_testcase: true,
    do_statement: true,
    do_checker: true,
    do_cpp_extras: true,
    do_attachment: true,
    do_solutions: true,
    do_initializers: true,
    do_data_files: true,
    do_additional_datasets: true,
    user: nil             # attributed owner of imported model solutions
  )
    @log = []
    @base_dir = dir
    unless Pathname.new(dir).exist?
      @log << "ERROR: cannot find path #{dir}"
      puts @log
      return @log
    end

    # read any options
    begin
      load_options
    rescue => errors
      puts "Parsing 'config.yml' failed: #{errors}"
      return false
    end
    name = @options[:name] unless name

    # init problem and dataset
    @problem = Problem.find_or_create_by(name: name)

    @log << "Found existing problem with the same name ('#{name}') !!! This import will UPDATE the existing problem." if @problem.id
    @problem.date_added = Time.zone.now unless @problem.date_added
    @problem.available = false if @problem.available.nil?
    @problem.full_name = full_name.presence || name
    @problem.set_default_value unless @problem.id
    if dataset && dataset.problem == @problem
      @dataset = dataset
      @log << "This import will REMOVE any existing dataset!!!"
    else
      @dataset = Dataset.new(name: @problem.get_next_dataset_name, problem: @problem)
      @log << "This import will create a new Dataset named '#{@dataset.name}'"
    end
    @problem.datasets.where.not(id: @dataset.id).each { |ds| ds.destroy } if delete_existing
    @problem.datasets.reload

    @dataset.memory_limit = memory_limit
    @dataset.time_limit = time_limit
    @problem.live_dataset = @dataset if delete_existing || @problem.live_dataset.nil?
    @dataset.save
    unless @problem.save
      @errors += @problem.errors.full_messages
      puts @errors
      return nil
    end

    @log << "Importing dataset for problem '#{@problem.name}' (#{@problem.id})"

    read_testcase(input_pattern, sol_pattern, code_name_regex, group_name_regex) if do_testcase
    read_statement if do_statement
    read_attachment if do_attachment
    read_checker if do_checker
    read_cpp_extras if do_cpp_extras
    read_initializers if do_initializers
    read_data_files if do_data_files
    read_options # options is put to last, it will override any defaults
    warn_mixed_group_weights
    import_additional_datasets(input_pattern, sol_pattern, code_name_regex, group_name_regex) if do_additional_datasets
    read_solutions(user: user) if do_solutions
    @problem.save
    @dataset.save
    @log << "Done successfully"

    return @log
  end


  def unzip_to_dir(file, name, dir)
    Pathname.new(dir).mkpath
    safe_name = name.to_s.parameterize
    safe_name = 'problem' if safe_name.blank?
    pn  = Pathname.new(dir) + safe_name
    num = 1
    while pn.exist?
      pn  = Pathname.new(dir) + "#{safe_name}.#{num}"
      num += 1
    end

    destination = pn.cleanpath

    out, err, status = Open3.capture3('unzip', file.to_s, '-d', destination.to_s)
    unless status.exitstatus == 0
      @errors << err
      return nil
    end
    return nil unless validate_containment!(destination)
    destination
  end

  # Zip-slip defense: every extracted entry (and every symlink target) must
  # resolve inside the extraction dir, regardless of unzip version behavior.
  def validate_containment!(destination)
    base = File.realpath(destination.to_s)
    Dir.glob("#{destination}/**/*", File::FNM_DOTMATCH).each do |entry|
      next if ['.', '..'].include?(File.basename(entry))
      resolved =
        if File.symlink?(entry)
          entry_dir = (File.realpath(File.dirname(entry)) rescue nil)
          entry_dir && File.expand_path(File.readlink(entry), entry_dir)
        else
          (File.realpath(entry) rescue nil)
        end
      next if resolved&.start_with?("#{base}/") || resolved == base
      @errors << "Archive entry '#{File.basename(entry)}' escapes the extraction directory; import aborted"
      FileUtils.rm_rf(destination)
      return false
    end
    true
  end

  def self.import_all_from_dir(base_dir, skip_existing: true)
    pi = ProblemImporter.new
    Dir["#{base_dir}/*"].each do |fn|
      puts "found #{fn}"
      name = Pathname.new(fn).basename.to_s
      p = Problem.where(name: name).first
      if !skip_existing || p.nil?
        puts pi.import_dataset_from_dir(fn, name).join("\n")
      end
    end
  end

  def self.import_from_dir(problem_dir, skip_existing: true)
    pi = ProblemImporter.new
    name = Pathname.new(problem_dir).basename.to_s
    p = Problem.where(name: name).first
    if !skip_existing || p.nil?
      puts pi.import_dataset_from_dir(problem_dir, name).join("\n")
      puts @log
    end
  end
end
