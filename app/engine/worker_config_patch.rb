# Sets one `<section>: <language>:` line in config/worker.yml (the sections
# are `isolate_options` and `compiler_options`) as a text
# edit. worker.yml is a per-host, untracked file with ERB and hand-written
# comments, so it is never parsed and re-dumped: every other line stays
# byte-for-byte as it was. Used by `bin/rails engine:detect WRITE=1`.
#
#   shared:
#     ...
#     isolate_options:
#       java: "-d /etc/java-21-openjdk"
class WorkerConfigPatch
  # section name => the comment written above a newly created section
  SECTIONS = {
    'isolate_options' => 'extra isolate options this host needs, per language',
    'compiler_options' => 'extra compiler command-line options this host needs, per language',
    'compiler' => 'compiler paths'
  }.freeze

  # Returns the new file text; `value` nil removes the language's line (and
  # the section header when that leaves it empty).
  def self.apply(text, language, value, section: 'isolate_options')
    raise ArgumentError, "unknown worker.yml section #{section}" unless SECTIONS.key?(section)
    lines = text.lines
    header = lines.index { |l| l =~ /\A  #{section}:\s*(#.*)?\z/ }
    entry = value && %(    #{language}: "#{value}"\n)

    if header
      # the section's entries: the 4-space-indented lines right under the header
      last = header
      last += 1 while lines[last + 1] =~ /\A {4,}\S/
      existing = (header + 1..last).find { |i| lines[i] =~ /\A    #{Regexp.escape(language)}:/ }
      if existing
        entry ? lines[existing] = entry : lines.delete_at(existing)
      elsif entry
        lines.insert(header + 1, entry)
      end
      remove_section(lines, header) unless lines[header + 1] =~ /\A {4,}\S/
    elsif entry
      lines = insert_section(lines, section, entry)
    end
    lines.join
  end

  # Takes an emptied section out again together with the comment block and
  # blank line insert_section put above it, so write-then-remove leaves the
  # file as it was. A header a person wrote has no such comment and loses
  # only its own line.
  def self.remove_section(lines, header)
    lines.delete_at(header)
    generated = [/\A  # .*; written by\n\z/, /\A  # `bin\/rails engine:detect WRITE=1`/]
    if header >= 2 && lines[header - 2] =~ generated[0] && lines[header - 1] =~ generated[1]
      lines.slice!(header - 2, 2)
      header -= 2
      lines.delete_at(header - 1) if header >= 1 && lines[header - 1].strip.empty? && (lines[header].nil? || lines[header].strip.empty?)
    end
  end

  # A new section goes at the end of `shared:`, before the next top-level key.
  def self.insert_section(lines, section, entry)
    shared = lines.index { |l| l =~ /\Ashared:/ } or raise ArgumentError, 'worker.yml has no `shared:` section'
    nxt = (shared + 1...lines.size).find { |i| lines[i] =~ /\A[^\s#]/ } || lines.size
    nxt -= 1 while nxt > shared + 1 && lines[nxt - 1].strip.empty?
    lines[nxt - 1] = "#{lines[nxt - 1]}\n" unless lines[nxt - 1].end_with?("\n")
    block = ["\n",
             "  # #{SECTIONS.fetch(section)}; written by\n",
             "  # `bin/rails engine:detect WRITE=1` (see worker.yml.SAMPLE)\n",
             "  #{section}:\n",
             entry]
    lines[0...nxt] + block + lines[nxt..]
  end
end
