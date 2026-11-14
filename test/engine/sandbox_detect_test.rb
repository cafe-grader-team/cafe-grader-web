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
    assert_equal [], d.problems(effective: ->(_) { "-p -d /etc/alternatives -d #{dir}" }, host: { java: "-d #{dir}" })
  end

  test 'a detected mount that no option provides is reported' do
    d = detect_needing('/etc/java-21-openjdk')
    found = d.problems(effective: ->(_) { '-p -d /etc/alternatives' }, host: {})
    assert_equal 1, found.size
    assert_match(%r{java: the sandbox does not mount /etc/java-21-openjdk}, found.first)
    assert_match(/engine:detect WRITE=1/, found.first)
  end

  test 'a worker.yml mount that is not on this host is reported (the state a JDK upgrade leaves)' do
    gone = (@root + 'java-17-openjdk').to_s
    found = detect.problems(effective: ->(_) { '' }, host: { java: "-d #{gone}" })
    assert_equal 1, found.size
    assert_match(/java: worker.yml mounts #{Regexp.escape(gone)}, which does not exist/, found.first)
  end

  test 'mount rules are read in every form isolate accepts; tmp and in-box rules have no host directory' do
    d = detect
    assert_equal %w[/a /out /out2 /etc/x],
                 d.send(:mount_sources, '-p -d /a -d /in=/out:rw --dir=/in2=/out2 --dir /etc/x:maybe -d /gocache:tmp --open-files=9')
  end
end
