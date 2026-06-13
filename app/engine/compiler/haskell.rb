class Compiler::Haskell < Compiler
  def build_compile_command(source,bin)
    cmd = [
      "#{Rails.configuration.worker[:compiler][:haskell]}",
      "-odir /mybin",
      "-outputdir /mybin",
      "-o #{bin}",
      source
    ]
    return cmd.join ' '
  end
end
