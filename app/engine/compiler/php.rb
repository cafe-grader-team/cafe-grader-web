class Compiler::Php < Compiler
  def build_compile_command(source, bin)
    # -l for php is linting
    cmd = [
      "#{Rails.configuration.worker[:compiler][:php]}",
      "-l",
      source
    ]
    return cmd.join ' '
  end

  def check_compile_result(out, err, status, meta)
    if meta['exitcode'] == 0
      # compiler finished successfully
      return EngineResponse::Result.success(result_description: out)
    else
      # compiler found some error
      # php output there error into out, not err
      return EngineResponse::Result.failure(error: out)
    end
  end

  def post_compile
    source_text = File.read(@source_file)

    bin_text = "#!#{Rails.configuration.worker[:compiler][:php]}\n"+source_text
    File.write(@exec_file, bin_text)
  end
end
