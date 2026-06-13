class Compiler::Postgres < Compiler
  # postgres requires config file
  # this error happens when a user submits to non-postgreSQL problem
  # but accidentally select postgres as the programming language,
  # which trigger compilation as postgres
  def validate
    #unless @prob_config_file && File.exists?(@prob_config_file)
    #  raise GraderError.new("Compiling as PostgreSQL but the Problem does not have PostgreSQL config file.",
    #                        submission_id: @sub.id)
    #end
    super()
  end

  def pre_compile
    sql = File.read(@source_file)
    sql = "\\set ON_ERROR_STOP\nEXPLAIN " + sql;
    @explain_file = @source_path + "explain.sql"
    File.write(@explain_file,sql)

  end

  def build_compile_command(source,bin)
    # this basically is no-op, which always pass
    cmd = [
      "/usr/bin/echo "
    ]
    return cmd.join ' '

    # parse the options
    config = YAML.load_file(@prob_config_file,symbolize_names: true)
    dbname = config[:database_name]
    user = config[:run_database_user]
    password = config[:run_database_password]
    cmd = [
      "/usr/bin/psql",
      "postgres://#{user}:#{password}@127.0.0.1/#{dbname}",
      "-f",
      @isolate_source_path + "explain.sql"
    ]
    return cmd.join ' '
  end

  # for Postgres, we build another script that runs the user SQL
  # the SQL is gsubbed to change the table name to matched the one
  # that is in the worker machine
  # finally the SQL is send to PSQL via stdin
  def post_compile
    # read required info
    source_text = File.read(@source_file)

    # parse the options
    config = YAML.load_file(@prob_config_file,symbolize_names: true)

    # a script is a ruby script
    bin_text = <<~BINARY
    #!#{Rails.configuration.worker[:compiler][:ruby]}
    require 'open3'
    sql = <<-SQL
      #{source_text}
    SQL
    table_name_translation = %w(#{config[:table_name_translation].join ' '})
    testcase_id = ARGV[0]

    #do the table name translation
    table_name_translation.each { |from| sql.gsub!(/\#{from}/i,from+'_'+testcase_id.to_s) }

    cmd = '/usr/bin/psql postgres://#{config[:run_database_user]}:#{config[:run_database_password]}@127.0.0.1/#{config[:database_name]} --csv'

    out,err,status = Open3.capture3(cmd, stdin_data: sql)
    puts out
    BINARY

    File.write(@exec_file,bin_text)
  end
end
