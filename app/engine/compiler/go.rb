class Compiler::Go < Compiler
  def build_compile_command(source,bin)
    cmd = [
      "#{Rails.configuration.worker[:compiler][:go]}", 
      "build",
      "-o #{bin}",
      source
    ]
    return cmd.join ' '
  end
end
