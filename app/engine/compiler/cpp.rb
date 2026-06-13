class Compiler::Cpp < Compiler
  def build_compile_command(source, bin)
    sources = [ source ]

    glob_dir = [
      [@source_path, @isolate_source_path],
      [@manager_path, @isolate_source_manager_path],
    ]

    glob_dir.each do |dir|
      # find all .c or .cpp in the manager path
      base_pathname = Pathname.new(dir[0])
      # The glob pattern is updated to find both .c and .cpp files.
      # No special flag is needed.
      base_pathname.glob('**/*.cpp').each do |pn|
        relative_pn = pn.relative_path_from(dir[0])
        isolate_fn = dir[1] + relative_pn.to_s
        sources << isolate_fn unless sources.include? isolate_fn
      end
    end

    cmd = [
      "#{Rails.configuration.worker[:compiler][:cpp]}",
      "-o #{bin}",
      "-iquote #{@isolate_source_path}",
      "-iquote #{@isolate_source_manager_path}",
      "-DEVAL -std=gnu++17 -O2 -pipe -s -static",
      sources.join(' ')
    ]
    return cmd.join ' '
  end
end
