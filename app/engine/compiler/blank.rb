class Compiler::Blank < Compiler
  def build_compile_command(source, bin)
    # this basically is no-op
    cmd = [
      "/usr/bin/echo "
    ]
    return cmd.join ' '
  end

  def post_compile
    # do nothing
  end
end
