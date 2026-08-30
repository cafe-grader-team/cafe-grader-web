module OptionConst
  # YAML default options value
  DEFAULT = {
    dir: {
      testcases: 'testcases',
      attachment: 'attachment',
      checker: 'checker',
      managers: 'managers',
      model_sols: 'model_solutions',
      initializers: 'initializers',
      data_files: 'data_files'
    },
    file: {
      checker: 'checker',
      statement: 'statement.pdf',
      description: 'description.md'
    }
  }

  # the config filename
  YAML_FILENAME = 'config.yml'

  # these are keys of the Option hash, MUST BE SYMBOL
  YAML_KEY = {
    dir: {
      testcases: :testcases_dir,
      attachment: :attachment_dir,
      checker: :checker_dir,
      managers: :managers_dir,
      model_sols: :solutions_dir,
      initializers: :initializers_dir,
      data_files: :data_files_dir
    },
    ds_name: :ds_name,
    additional_datasets: :additional_datasets,
    tags: :tags,
    checker: :checker,
    managers_pattern: :managers_pattern,
    testcases: :testcases,
    testcases_pattern: :testcases_pattern,
    initializer: :initializer
  }

  # Problem / live-Dataset attributes carried in config.yml.
  # Single source of truth for ProblemImporter#read_options and
  # ProblemExporter#export_root_options / #export_dataset_files —
  # do not redefine lists there.
  PROBLEM_OPTION_FIELDS = %i[full_name submission_filename task_type
                             compilation_type permitted_lang markdown]
  DATASET_OPTION_FIELDS = %i[time_limit memory_limit score_type
                             evaluation_type score_param main_filename
                             initializer_filename]
end
