# Works out the isolate options that depend on this HOST rather than on the
# language, so they can be written to worker.yml (`isolate_options:`) instead
# of being guessed while grading. Entry point: `bin/rails engine:detect`
# (lib/tasks/engine.rake). The grader never calls this — it only reads
# worker.yml (JudgeBase#isolate_options_by_lang) — so what a box uses is
# always a plain line in that file.
#
# Only Java needs it today. Debian/Ubuntu's OpenJDK replaces the files under
# <jdk>/conf (and a few under <jdk>/lib) with symlinks into
# /etc/java-<N>-openjdk; the sandbox sees /usr but not /etc, so javac dies at
# start with "InternalError: Error loading java.security file" (every Java
# submission on cp-grader from 2025-08 to 2026-11). The directory name changes
# with the JDK major version; a JDK unpacked from a tarball has real files and
# needs nothing.
class SandboxDetect
  # What a sandbox sees without any host option: isolate's default rules plus
  # the `-d /etc/alternatives` the built-in Java options already carry.
  VISIBLE = %w[/usr /bin /lib /lib64 /etc/alternatives].freeze

  # Languages #options can return an entry for. engine:detect owns the
  # worker.yml line of these and of no other language.
  LANGUAGES = %w[java].freeze

  def initialize(compilers: Rails.configuration.worker[:compiler] || {}, visible: VISIBLE)
    @compilers = compilers
    @visible = visible
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

  # Human-readable problems with the options this host has in effect:
  #   - a mount detection says is needed but no option provides;
  #   - a mount worker.yml asks for that is not on this host (isolate refuses
  #     to start a sandbox with a missing directory — the state a JDK upgrade
  #     leaves an old `-d /etc/java-<N>-openjdk` line in).
  # `effective` maps a language name to the full option string a grader uses.
  def problems(effective:, host: Rails.configuration.worker[:isolate_options] || {})
    found = []
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
    return nil if @visible.any? { |dir| target == dir || target.start_with?("#{dir}/") }
    parts = target.split('/').reject(&:empty?)
    parts.size > 2 ? "/#{parts.first(2).join('/')}" : nil
  rescue Errno::ENOENT
    nil
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
