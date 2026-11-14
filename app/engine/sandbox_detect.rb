# Works out the options that depend on this HOST rather than on the language
# — extra isolate options (worker.yml `isolate_options:`) and extra compiler
# flags (`compiler_options:`) — so they can be written to worker.yml instead
# of being guessed while grading. Entry point: `bin/rails engine:detect`
# (lib/tasks/engine.rake). The grader never calls this — it only reads
# worker.yml (JudgeBase#isolate_options_by_lang) — so what a box uses is
# always a plain line in that file.
#
# Java (isolate option). Debian/Ubuntu's OpenJDK replaces the files under
# <jdk>/conf (and a few under <jdk>/lib) with symlinks into
# /etc/java-<N>-openjdk; the sandbox sees /usr but not /etc, so javac dies at
# start with "InternalError: Error loading java.security file" (every Java
# submission on cp-grader from 2025-08 to 2026-11). The directory name changes
# with the JDK major version; a JDK unpacked from a tarball has real files and
# needs nothing.
#
# Pascal (compiler flag). fpc learns where its units are from /etc/fpc.cfg,
# which on Debian/Ubuntu is a link chain ending at /etc/fpc-<version>.cfg. A
# single file cannot be mounted (isolate binds directories only), so without
# it fpc stops with "Can't find unit system used by Program". The unit
# directory is passed as an -Fu flag instead; it depends on the fpc version,
# the CPU and the distribution's library layout.
class SandboxDetect
  # What a sandbox sees without any host option: isolate's default rules plus
  # the `-d /etc/alternatives` the built-in Java options already carry.
  VISIBLE = %w[/usr /bin /lib /lib64 /etc/alternatives].freeze

  # worker.yml section => the languages engine:detect owns a line for in it.
  # A line for any other language is a person's and is never touched.
  OWNED = { 'isolate_options' => %w[java], 'compiler_options' => %w[pas] }.freeze

  FPC_CONFIG = '/etc/fpc.cfg'

  # fpc_query runs the configured fpc with one info switch (-iV, -iTP, -iTO,
  # -PB) and returns its output; tests pass a lambda.
  def initialize(compilers: Rails.configuration.worker[:compiler] || {}, visible: VISIBLE,
                 fpc_config: FPC_CONFIG, fpc_query: nil)
    @compilers = compilers
    @visible = visible
    @fpc_config = fpc_config
    @fpc_query = fpc_query || ->(switch) { IO.popen([@compilers[:pas].to_s, switch], err: File::NULL, &:read).to_s.strip }
  end

  # { section => { language => option string } } — everything engine:detect
  # would write; a section or language that needs nothing is absent.
  def all
    { 'isolate_options' => options, 'compiler_options' => compiler_options }.reject { |_, langs| langs.empty? }
  end

  # { language name => option string }, only for languages that need one.
  def options
    java = java_mounts
    java.empty? ? {} : { 'java' => java.map { |dir| "-d #{dir}" }.join(' ') }
  end

  # Directories outside the sandbox that the JDK behind the configured javac
  # reaches through symlinks in <jdk>/conf/** and <jdk>/lib/*.
  def java_mounts
    javac = @compilers[:javac].to_s
    return [] if javac.empty? || !File.exist?(javac)

    home = Pathname.new(File.realpath(javac)).parent.parent
    links = Pathname.glob(home + 'conf/**/*') + Pathname.glob(home + 'lib/*')
    links.select(&:symlink?).filter_map { |link| mount_for(link) }.uniq.sort
  end

  # { language name => compiler flags }, only for languages that need some.
  def compiler_options
    units = pascal_unit_path
    units ? { 'pas' => "-Fu#{units}/*" } : {}
  end

  # The directory of fpc's compiled units (it holds rtl/system.ppu), when fpc
  # cannot find it by itself inside the sandbox: its config file exists on the
  # host but resolves to somewhere the sandbox does not see. nil when fpc is
  # not configured, the config is visible anyway, or the units are not where
  # the compiler binary says (then engine:langcheck shows the real error).
  def pascal_unit_path
    fpc = @compilers[:pas].to_s
    return nil if fpc.empty? || !File.exist?(fpc)
    return nil unless File.exist?(@fpc_config)
    return nil if visible?(File.realpath(@fpc_config))

    binary = @fpc_query.call('-PB') # e.g. /usr/bin/ppcx64, a link into the fpc tree
    return nil if binary.empty? || !File.exist?(binary)
    units = Pathname.new(File.realpath(binary)).parent + 'units' + "#{@fpc_query.call('-iTP')}-#{@fpc_query.call('-iTO')}"
    (units + 'rtl' + 'system.ppu').exist? ? units.to_s : nil
  end

  # Human-readable problems with the options this host has in effect:
  #   - a mount detection says is needed but no option provides;
  #   - a mount worker.yml asks for that is not on this host (isolate refuses
  #     to start a sandbox with a missing directory — the state a JDK upgrade
  #     leaves an old `-d /etc/java-<N>-openjdk` line in).
  # `effective` maps a language name to the full option string a grader uses.
  # `compiler` is worker.yml's compiler_options.
  def problems(effective:, host: Rails.configuration.worker[:isolate_options] || {},
               compiler: Rails.configuration.worker[:compiler_options] || {})
    compiler = compiler.to_h.transform_keys(&:to_s)
    found = []
    compiler_options.each do |lang, wanted|
      next if compiler[lang].to_s.split.include?(wanted)
      found << "#{lang}: the compiler is not given #{wanted} — run `bin/rails engine:detect WRITE=1`"
    end
    compiler.each do |lang, opts|
      gone = opts.to_s.scan(/-Fu(\S+)/).flatten.map { |dir| dir.sub(%r{/\*\z}, '') }.reject { |dir| File.exist?(dir) }
      next if gone.empty?
      found << "#{lang}: worker.yml compiler_options names #{gone.join(', ')}, which does not exist on this host — run `bin/rails engine:detect WRITE=1`"
    end
    options.each do |lang, wanted|
      have = mount_sources(effective.call(lang))
      missing = mount_sources(wanted) - have
      next if missing.empty?
      found << "#{lang}: the sandbox does not mount #{missing.join(', ')} — run `bin/rails engine:detect WRITE=1`"
    end
    host.each do |lang, opts|
      gone = mount_sources(opts.to_s).reject { |dir| File.exist?(dir) }
      next if gone.empty?
      found << "#{lang}: worker.yml mounts #{gone.join(', ')}, which does not exist on this host — run `bin/rails engine:detect WRITE=1`"
    end
    found
  end

  private

  # The top of the outside tree a symlink leads to: /etc/java-21-openjdk for
  # /etc/java-21-openjdk/security/java.security. nil when the target is
  # already visible in the sandbox, or is dangling.
  def mount_for(link)
    target = link.realpath.to_s
    return nil if visible?(target)
    parts = target.split('/').reject(&:empty?)
    parts.size > 2 ? "/#{parts.first(2).join('/')}" : nil
  rescue Errno::ENOENT
    nil
  end

  def visible?(path)
    @visible.any? { |dir| path == dir || path.start_with?("#{dir}/") }
  end

  # Host-side directories of every `-d` / `--dir` rule in an option string:
  # `-d /a`, `-d /in=/out`, `--dir=/in=/out:rw`. Rules without a host
  # directory (`:tmp`, a bare `/in=`) are skipped.
  def mount_sources(option_string)
    rules = option_string.to_s.scan(/(?:-d\s+|--dir[=\s])(\S+)/).flatten
    rules.filter_map do |rule|
      path, *flags = rule.split(':')
      next if flags.include?('tmp')
      inside, outside = path.split('=', 2)
      dir = outside.nil? ? inside : outside
      dir.to_s.start_with?('/') ? dir : nil
    end
  end
end
