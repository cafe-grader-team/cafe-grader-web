# these are configs for judge engine
# Currently, most of them is about the filename and config keys of the problem .zip file
module OptionConst
  # YAML default options value
  DEFAULT = {
    dir: {
      testcases: 'testcases',
      attachment: 'attachment',
      checker: 'checker',
      managers: 'managers',
      model_sols: 'model_solutions',
      initializers: 'initializers'
    },
    file: {
      checker: 'checker',
      statement: 'statment.pdf'
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
      initializers: :initializers_dir
    },
    ds_name: :ds_name,
    tags: :tags,
    checker: :checker,
    managers_pattern: :managers_pattern,
    testcases: :testcases,
    testcases_pattern: :testcases_pattern,
    initializer: :initializer
  }
end
