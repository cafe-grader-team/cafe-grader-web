class Compiler::Java < Compiler
  def pre_compile
    @classname = nil
    new_source = []

    @sub.source.each_line do |line|
      line.encode!('UTF-8','UTF-8',invalid: :replace, replace: '')
      md = /\s*public\s*class\s*(\w*)/.match(line)
      if md
        @classname=md[1]
        judge_log "detect classname #{@classname}"
      end
      new_source << line unless line =~ /\s*package\s*[\w\.]+\s*\;/
    end

    if @classname
      @new_source_file = @source_path + "#{@classname}.java"
      File.write(@new_source_file,new_source.join("\n"))
      judge_log "writing new file to #{@new_source_file}"
    else
      raise GraderError.new("Cannot find a public class in the file",
                            submission_id: @sub.id)
    end

  end

  def build_compile_command(source,bin)
    cmd = [
      "#{Rails.configuration.worker[:compiler][:javac]}",
      "-encoding utf8",
      @isolate_source_path + "#{@classname}.java",
      "-d #{@isolate_bin_path}",
    ]
    return cmd.join ' '
  end

  # build a script that runs the java file
  def post_compile
    bin_text = "#!/bin/sh\njava -cp #{@isolate_bin_path} #{@classname}"
    File.write(@exec_file,bin_text)
  end
end
