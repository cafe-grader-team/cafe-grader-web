class Compiler::Pascal < Compiler
  def build_compile_command(source,bin)
    cmd = [
      "#{Rails.configuration.worker[:compiler][:pas]}",
      "-O1 -XS -dCONTEST",
      host_compiler_options('pas'),
      "-o#{bin}",
      source
    ]
    return cmd.join ' '
  end
end
