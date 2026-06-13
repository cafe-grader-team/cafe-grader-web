class Compiler::Python < Compiler
  def build_compile_command(isolate_source, isolate_bin)
    cmd = [
      "#{Rails.configuration.worker[:compiler][:python]}",
      "-c \"import py_compile; py_compile.compile('#{isolate_source}','#{isolate_bin}c')\"",
    ]
    return cmd.join ' '
  end

  def check_compile_result(out, err, status, meta)
    if File.exist?("#{@exec_file}c")
      # compiler finished successfully
      return EngineResponse::Result.success(result_description: out)
    else
      # compiler found some error
      return EngineResponse::Result.failure(error: err)
    end
  end

  # in managers mode, even though we have compiled the file,
  # we directly run the source file and also copy any managers
  def post_compile
    # also copy any managers
    if @sub.problem.with_managers?
      # in managers modes, we copy all managers and the submission source file
      # as the compiled result and create another script that runs the main file
      Dir.glob(@manager_path + '*').each do |fn|
        FileUtils.cp(fn, @compile_path)
      end
      FileUtils.cp(@source_file, @compile_path)

      bin_text = "#!/bin/sh\n" +
        "#{Rails.configuration.worker[:compiler][:python]} #{@isolate_bin_path + @working_dataset.main_filename}"
      File.write(@exec_file, bin_text)
    else
      # build script with shebang
      source_text = File.read(@source_file)
      bin_text = "#!#{Rails.configuration.worker[:compiler][:python]}\n"+source_text
      File.write(@exec_file, bin_text)
    end
  end
end
