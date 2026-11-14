require 'test_helper'

# SandboxDetect works out the host-dependent isolate options that
# `bin/rails engine:detect` writes to worker.yml. The JDK layouts are built in
# a temp dir: <root>/jdk/bin/javac plus conf/ and lib/ entries, with <root>/etc
# standing in for the host's /etc.
class SandboxDetectTest < ActiveSupport::TestCase
  setup do
    @root = Pathname.new(Dir.mktmpdir('sandbox_detect')).realpath
    @jdk = @root + 'jdk'
    (@jdk + 'bin').mkpath
    (@jdk + 'conf/security').mkpath
    (@jdk + 'lib').mkpath
    FileUtils.touch(@jdk + 'bin/javac')
  end

  teardown { FileUtils.rm_rf(@root) }

  # the temp JDK itself counts as visible, the way /usr/lib/jvm is
  def detect(javac: (@jdk + 'bin/javac').to_s)
    SandboxDetect.new(compilers: { javac: javac }, visible: [@jdk.to_s])
  end

  def outside(relative)
    file = @root + relative
    file.dirname.mkpath
    FileUtils.touch(file)
    file
  end

  test 'a JDK whose conf files are real files needs no option' do
    FileUtils.touch(@jdk + 'conf/security/java.security')
    assert_equal [], detect.java_mounts
    assert_equal({}, detect.options)
  end

  test 'conf files symlinked outside the sandbox give one mount for the outside directory' do
    etc = @root + 'etc/java-21-openjdk'
    File.symlink(outside('etc/java-21-openjdk/security/java.security'), @jdk + 'conf/security/java.security')
    File.symlink(outside('etc/java-21-openjdk/net.properties'), @jdk + 'conf/net.properties')
    File.symlink(outside('etc/java-21-openjdk/jvm-amd64.cfg'), @jdk + 'lib/jvm.cfg')

    # the mount is the first two path components of the target; in the temp
    # tree that is the temp root's parent pair, on a real host /etc/java-21-openjdk
    expected = "/#{etc.to_s.split('/').reject(&:empty?).first(2).join('/')}"
    assert_equal [expected], detect.java_mounts
    assert_equal({ 'java' => "-d #{expected}" }, detect.options)
  end

  test 'on a real-looking layout the mount is /etc/java-<N>-openjdk' do
    # mount_for only does path arithmetic on the resolved target, so a fake
    # Pathname is enough to pin the /etc case without touching /etc
    link = Struct.new(:realpath).new(Pathname.new('/etc/java-21-openjdk/security/java.security'))
    assert_equal '/etc/java-21-openjdk', SandboxDetect.new(compilers: {}).send(:mount_for, link)
  end

  test 'symlinks that stay inside what the sandbox sees are ignored' do
    FileUtils.touch(@jdk + 'lib/real.cfg')
    File.symlink(@jdk + 'lib/real.cfg', @jdk + 'lib/alias.cfg')
    visible = Struct.new(:realpath).new(Pathname.new('/etc/alternatives/java'))
    assert_equal [], detect.java_mounts
    assert_nil SandboxDetect.new(compilers: {}).send(:mount_for, visible)
  end

  test 'a dangling symlink is ignored' do
    File.symlink(@root + 'etc/gone/java.security', @jdk + 'conf/security/java.security')
    assert_equal [], detect.java_mounts
  end

  test 'javac reached through a chain of symlinks resolves to the real JDK' do
    File.symlink(outside('etc/java-21-openjdk/security/java.security'), @jdk + 'conf/security/java.security')
    (@root + 'alternatives').mkpath
    File.symlink(@jdk + 'bin/javac', @root + 'alternatives/javac')
    File.symlink(@root + 'alternatives/javac', @root + 'javac')
    assert_equal 1, detect(javac: (@root + 'javac').to_s).java_mounts.size
  end

  test 'no javac configured, or a path that is not there, needs no option' do
    assert_equal({}, detect(javac: '').options)
    assert_equal({}, detect(javac: nil).options)
    assert_equal({}, detect(javac: (@root + 'nope/javac').to_s).options)
  end

  # --- problems: is what the graders use still right for this host? ---

  def detect_needing(dir)
    d = detect
    d.define_singleton_method(:options) { { 'java' => "-d #{dir}" } }
    d
  end

  test 'no problem when the effective options carry the detected mount' do
    dir = @root.to_s
    d = detect_needing(dir)
    assert_equal [], d.problems(effective: ->(_) { "-p -d /etc/alternatives -d #{dir}" }, host: { java: "-d #{dir}" }, compiler: {})
  end

  test 'a detected mount that no option provides is reported' do
    d = detect_needing('/etc/java-21-openjdk')
    found = d.problems(effective: ->(_) { '-p -d /etc/alternatives' }, host: {}, compiler: {})
    assert_equal 1, found.size
    assert_match(%r{java: the sandbox does not mount /etc/java-21-openjdk}, found.first)
    assert_match(/engine:detect WRITE=1/, found.first)
  end

  test 'a worker.yml mount that is not on this host is reported (the state a JDK upgrade leaves)' do
    gone = (@root + 'java-17-openjdk').to_s
    found = detect.problems(effective: ->(_) { '' }, host: { java: "-d #{gone}" }, compiler: {})
    assert_equal 1, found.size
    assert_match(/java: worker.yml mounts #{Regexp.escape(gone)}, which does not exist/, found.first)
  end

  test 'mount rules are read in every form isolate accepts; tmp and in-box rules have no host directory' do
    d = detect
    assert_equal %w[/a /out /out2 /etc/x],
                 d.send(:mount_sources, '-p -d /a -d /in=/out:rw --dir=/in2=/out2 --dir /etc/x:maybe -d /gocache:tmp --open-files=9')
  end

  # --- Pascal: the unit directory fpc cannot find without /etc/fpc.cfg ---

  # <root>/fpc/3.2.2/ppcx64 + units/x86_64-linux/rtl/system.ppu, the compiler
  # reached through <root>/bin/ppcx64, and a config file outside the sandbox
  def fpc_tree(config_visible: false, with_units: true)
    home = @root + 'fpc/3.2.2'
    (home + 'units/x86_64-linux/rtl').mkpath
    FileUtils.touch(home + 'units/x86_64-linux/rtl/system.ppu') if with_units
    FileUtils.touch(home + 'ppcx64')
    (@root + 'bin').mkpath
    FileUtils.touch(@root + 'bin/fpc')
    File.symlink(home + 'ppcx64', @root + 'bin/ppcx64')
    real_cfg = outside('etc/fpc-3.2.2.cfg')
    File.symlink(real_cfg, @root + 'fpc.cfg')
    answers = { '-PB' => (@root + 'bin/ppcx64').to_s, '-iTP' => 'x86_64', '-iTO' => 'linux' }
    SandboxDetect.new(compilers: { pas: (@root + 'bin/fpc').to_s },
                      visible: config_visible ? [@root.to_s] : [(@root + 'fpc').to_s],
                      fpc_config: (@root + 'fpc.cfg').to_s, fpc_query: ->(switch) { answers.fetch(switch) })
  end

  test 'fpc whose config file is outside the sandbox gets its unit directory as an -Fu flag' do
    d = fpc_tree
    units = (@root + 'fpc/3.2.2/units/x86_64-linux').to_s
    assert_equal units, d.pascal_unit_path
    assert_equal({ 'pas' => "-Fu#{units}/*" }, d.compiler_options)
    assert_equal({ 'compiler_options' => { 'pas' => "-Fu#{units}/*" } }, d.all)
  end

  test 'fpc whose config file the sandbox can see needs no flag' do
    assert_equal({}, fpc_tree(config_visible: true).compiler_options)
  end

  test 'no flag is invented when the units are not where the compiler binary says' do
    assert_equal({}, fpc_tree(with_units: false).compiler_options)
  end

  test 'no fpc configured, or no config file on the host, needs no flag' do
    assert_equal({}, SandboxDetect.new(compilers: {}).compiler_options)
    d = SandboxDetect.new(compilers: { pas: (@jdk + 'bin/javac').to_s }, fpc_config: (@root + 'nope.cfg').to_s,
                          fpc_query: ->(_) { flunk 'fpc must not be asked when there is no config file' })
    assert_equal({}, d.compiler_options)
  end

  test 'a detected compiler flag that worker.yml does not carry is reported' do
    d = fpc_tree
    found = d.problems(effective: ->(_) { '' }, host: {}, compiler: {})
    assert_equal 1, found.size
    assert_match(/pas: the compiler is not given -Fu.*engine:detect WRITE=1/, found.first)
    assert_equal [], d.problems(effective: ->(_) { '' }, host: {}, compiler: { pas: d.compiler_options['pas'] })
  end

  test 'a compiler_options unit directory that is not on this host is reported (after an fpc upgrade)' do
    found = detect.problems(effective: ->(_) { '' }, host: {}, compiler: { pas: '-Fu/usr/lib/fpc/9.9.9/units/x86_64-linux/*' })
    assert_equal 1, found.size
    assert_match(%r{pas: worker.yml compiler_options names /usr/lib/fpc/9.9.9/units/x86_64-linux, which does not exist}, found.first)
  end
end
