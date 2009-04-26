module GraderEngineHelperMethods

  def clear_sandbox
    config = Grader::Configuration.get_instance
    clear_cmd = "rm -rf #{config.test_sandbox_dir}/*"
    system(clear_cmd)
  end

  def init_sandbox
    config = Grader::Configuration.get_instance
    clear_sandbox
    FileUtils.mkdir_p config.user_result_dir
    cp_cmd = "cp -R #{config.test_data_dir}/ev #{config.test_sandbox_dir}"
    system(cp_cmd)
  end

  def create_submission_from_file(id, user, problem, 
                                  source_fname, language=nil)

    language = stub(Language, :name => 'c', :ext => 'c') if language==nil

    config = Grader::Configuration.get_instance
    source = File.open(config.test_data_dir + "/" + source_fname).read
    stub(Submission,
         :id => id, :user => user, :problem => problem,
         :source => source, :language => language)
  end

end

