class Compiler::Digital < Compiler
  SUBMIT_DIGITAL_FILENAME = 'submitted.dig'
  def build_compile_command(source,bin)
    # this basically is no-op
    cmd = [
      "/usr/bin/echo "
    ]
    return cmd.join ' '
  end

  def post_compile
    # running script
    digital_jar = Rails.configuration.worker[:compiler][:digital]
    bin_text = "#!/bin/sh\njava -cp /my_lib/Digital.jar " +
      "CLI test " +
      "-circ #{@isolate_bin_path}/#{SUBMIT_DIGITAL_FILENAME} " +
      "-tests #{@isolate_input_file}\n"
    File.write(@exec_file,bin_text)

    # the submitted file
    FileUtils.cp(@source_file,@compile_path + SUBMIT_DIGITAL_FILENAME)
  end
end
