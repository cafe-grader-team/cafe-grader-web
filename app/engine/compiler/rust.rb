class Compiler::Rust < Compiler
  def build_compile_command(source, bin)
    cmd = [
      "#{Rails.configuration.worker[:compiler][:rust]}",
      "-o #{bin}",
      "-O",
      source
    ]
    return cmd.join ' '
  end
end
