# Sets one `isolate_options: <language>:` line in config/worker.yml as a text
# edit. worker.yml is a per-host, untracked file with ERB and hand-written
# comments, so it is never parsed and re-dumped: every other line stays
# byte-for-byte as it was. Used by `bin/rails engine:detect WRITE=1`.
#
#   shared:
#     ...
#     isolate_options:
#       java: "-d /etc/java-21-openjdk"
class WorkerConfigPatch
  SECTION = 'isolate_options'

  # Returns the new file text; `value` nil removes the language's line (and
  # the section header when that leaves it empty).
  def self.apply(text, language, value)
    lines = text.lines
    header = lines.index { |l| l =~ /\A  #{SECTION}:\s*(#.*)?\z/ }
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
      lines.delete_at(header) unless lines[header + 1] =~ /\A {4,}\S/
    elsif entry
      lines = insert_section(lines, entry)
    end
    lines.join
  end

  # A new section goes at the end of `shared:`, before the next top-level key.
  def self.insert_section(lines, entry)
    shared = lines.index { |l| l =~ /\Ashared:/ } or raise ArgumentError, 'worker.yml has no `shared:` section'
    nxt = (shared + 1...lines.size).find { |i| lines[i] =~ /\A[^\s#]/ } || lines.size
    nxt -= 1 while nxt > shared + 1 && lines[nxt - 1].strip.empty?
    lines[nxt - 1] = "#{lines[nxt - 1]}\n" unless lines[nxt - 1].end_with?("\n")
    block = ["\n",
             "  # extra isolate options this host needs, per language; written by\n",
             "  # `bin/rails engine:detect WRITE=1` (see worker.yml.SAMPLE)\n",
             "  #{SECTION}:\n",
             entry]
    lines[0...nxt] + block + lines[nxt..]
  end
end
