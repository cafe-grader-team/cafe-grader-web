# Compiles and runs one tiny built-in program per language in the real
# sandbox of this host, to answer "does language X grade here?" without a
# problem, a dataset, a submission row or the web server. Entry point:
# `bin/rails engine:langcheck` (lib/tasks/engine.rake).
#
# Why it exists: engine:smoke regrades an existing C++/C/Python submission, so
# a language nobody had a passing submission in could stay broken unnoticed —
# Java failed every compile on cp-grader for 15 months (a host-dependent
# sandbox mount, see SandboxDetect), Pascal and PHP never compiled at all.
#
# It drives the same sandbox calls as real grading — Compiler#compile_in_sandbox
# with the language's own Compiler subclass, and Evaluator#run_isolate_args —
# so a pass here means the compiler path, the isolate options and the run
# script all work. It does not cover the dataset download, the upload of the
# compiled files, or the checker; engine:smoke does.
class LangCheck
  # language name => [key of the compiler path in worker.yml, source]
  # Every program reads two integers and prints their sum.
  PROGRAMS = {
    'cpp' => [:cpp, <<~SRC],
      #include <iostream>
      int main() { long long a, b; std::cin >> a >> b; std::cout << a + b << std::endl; }
    SRC
    'c' => [:c, <<~SRC],
      #include <stdio.h>
      int main() { long long a, b; if (scanf("%lld %lld", &a, &b) != 2) return 1; printf("%lld\\n", a + b); return 0; }
    SRC
    'python' => [:python, <<~SRC],
      a, b = map(int, input().split())
      print(a + b)
    SRC
    'ruby' => [:ruby, <<~SRC],
      a, b = $stdin.gets.split.map(&:to_i)
      puts a + b
    SRC
    'java' => [:javac, <<~SRC],
      import java.util.Scanner;
      public class Main {
        public static void main(String[] args) {
          Scanner sc = new Scanner(System.in);
          System.out.println(sc.nextLong() + sc.nextLong());
        }
      }
    SRC
    'haskell' => [:haskell, <<~SRC],
      main :: IO ()
      main = interact $ \\s -> show (sum (map read (words s) :: [Integer])) ++ "\\n"
    SRC
    'rust' => [:rust, <<~SRC],
      use std::io::Read;
      fn main() {
          let mut s = String::new();
          std::io::stdin().read_to_string(&mut s).unwrap();
          let sum: i64 = s.split_whitespace().map(|x| x.parse::<i64>().unwrap()).sum();
          println!("{}", sum);
      }
    SRC
    'go' => [:go, <<~SRC],
      package main

      import "fmt"

      func main() {
      	var a, b int64
      	fmt.Scan(&a, &b)
      	fmt.Println(a + b)
      }
    SRC
    'pas' => [:pas, <<~SRC],
      var a, b: int64;
      begin
        read(a, b);
        writeln(a + b);
      end.
    SRC
    'php' => [:php, <<~SRC]
      <?php
      fscanf(STDIN, "%d %d", $a, $b);
      echo $a + $b, "\\n";
    SRC
  }.freeze

  INPUT = "20 22\n"
  EXPECTED = '42'
  RUN_TIME_LIMIT = 5     # seconds; a cold JVM needs most of one
  RUN_MEMORY_LIMIT = 512 # MB

  # verdict: :pass, :fail or :not_configured. phase: :config, :compile or :run.
  Result = Struct.new(:language, :verdict, :phase, :detail, :options, keyword_init: true)

  Lang = Struct.new(:name, :ext) do
    def default_submission_filename = "submission.#{ext}"
  end

  # Stands in for a Submission and its Problem: a plain, non-manager problem.
  Sub = Struct.new(:id, :source, :language) do
    def problem = self
    def with_managers? = false
    def submission_filename = nil
    def exec_filename(language) = Problem.new.exec_filename(language)
  end

  # Mixed into one Compiler-subclass instance and one Evaluator instance.
  module Standalone
    def langcheck_compile(sub)
      @sub = sub
      need_cg = isolate_need_cg_by_lang(sub.language.name)
      setup_isolate(@box_id, need_cg)
      begin
        prepare_submission_directory(sub)
        [@source_path, @compile_path].each { |dir| FileUtils.rm_rf(dir.children) }
        @source_file = @source_path + sub.language.default_submission_filename
        @isolate_source_file = @isolate_source_path + sub.language.default_submission_filename
        @isolate_main_file = @isolate_source_file
        File.write(@source_file, sub.source)
        out, err, status, meta = compile_in_sandbox(need_cg)
      ensure
        cleanup_isolate(need_cg)
      end
      result = check_compile_result(out, err, status, meta)
      post_compile if result.status == :success
      [result, [err, out].map(&:to_s).reject(&:empty?).join("\n")]
    end

    # Runs what langcheck_compile left in @compile_path; returns
    # [program output, isolate stderr, meta].
    def langcheck_run(sub, input_text)
      @sub = sub
      need_cg = isolate_need_cg_by_lang(sub.language.name)
      setup_isolate(@box_id, need_cg)
      begin
        prepare_submission_directory(sub)
        io_path = @submission_path + 'langcheck'
        input_path = io_path + 'input'
        output_path = io_path + 'output'
        [input_path, output_path].each(&:mkpath)
        output_path.chmod(0777)
        File.write(input_path + JudgeBase::INPUT_FILENAME, input_text)
        output_file = output_path + JudgeBase::STDOUT_FILENAME
        FileUtils.rm_f(output_file)
        # the files the compiler wrote belong to the sandbox user and were made
        # 0777 inside it; the run script post_compile wrote is ours and is not
        FileUtils.chmod('a+x', @compile_path.children.select { |f| f.file? && f.owned? })

        executable = @isolate_bin_path + sub.problem.exec_filename(sub.language)
        output = { "#{@isolate_output_path}": output_path }
        _out, err, _status, meta = run_isolate("#{executable} 0",
                                               input: { "#{@isolate_input_path}": input_path,
                                                        "#{@isolate_bin_path}": @compile_path.cleanpath },
                                               output: output,
                                               isolate_args: run_isolate_args(sub.language.name),
                                               meta: io_path + 'meta.txt',
                                               time_limit: RUN_TIME_LIMIT, mem_limit: RUN_MEMORY_LIMIT, cg: need_cg)
        run_isolate("/usr/bin/chmod 0666 #{@isolate_stdout_file}", output: output, meta: nil, cg: need_cg)
      ensure
        cleanup_isolate(need_cg)
      end
      [output_file.exist? ? File.read(output_file) : '', err, meta]
    end
  end

  def initialize(box_id: 99, worker_id: Rails.configuration.worker[:worker_id],
                 compilers: Rails.configuration.worker[:compiler] || {})
    @box_id = box_id
    @worker_id = worker_id
    @compilers = compilers
  end

  def self.languages = PROGRAMS.keys

  def run(languages = self.class.languages)
    languages.map { |name| check(name) }
  end

  def check(name)
    key, source = PROGRAMS.fetch(name) { return Result.new(language: name, verdict: :fail, phase: :config, detail: "langcheck has no program for '#{name}' (it knows #{PROGRAMS.keys.join(', ')})") }
    path = @compilers[key].to_s
    return not_configured(name, "no compiler path: worker.yml has no `compiler: #{key}:`, or the compiler is not installed (`bin/rails engine:detect` shows what can be added)") if path.empty?
    return not_configured(name, "compiler path #{path} (worker.yml `compiler: #{key}:`) does not exist") unless File.exist?(path)

    language = Language.find_by(name: name) || Lang.new(name, name)
    sub = Sub.new("langcheck_#{name}", source, Lang.new(name, language.ext))
    options = Compiler.new(@worker_id, @box_id).isolate_options_by_lang(name)

    compiler = Compiler.get_compiler(sub).new(@worker_id, @box_id).extend(Standalone)
    compiled, messages = compiler.langcheck_compile(sub)
    unless compiled.status == :success
      # some compilers (fpc, php) report on stdout, and isolate's own line
      # ("Exited with error status 1") says little without it
      said = [compiled.result_description, messages].flat_map { |t| t.to_s.lines }.map(&:strip).reject(&:empty?).uniq
      return Result.new(language: name, verdict: :fail, phase: :compile, options: options,
                        detail: said.empty? ? 'the compiler failed with no message' : said.first(3).join(' | ').truncate(300))
    end

    output, err, meta = Evaluator.new(@worker_id, @box_id).extend(Standalone).langcheck_run(sub, INPUT)
    if meta['status'].present?
      detail = "isolate status #{meta['status']}: #{meta['message']} #{first_line(output.presence || err)}".strip
      return Result.new(language: name, verdict: :fail, phase: :run, detail: detail, options: options)
    end
    unless output.strip == EXPECTED
      return Result.new(language: name, verdict: :fail, phase: :run, options: options,
                        detail: "expected #{EXPECTED.inspect}, the program printed #{first_line(output).inspect}")
    end
    Result.new(language: name, verdict: :pass, options: options)
  rescue => e
    Result.new(language: name, verdict: :fail, phase: :config, detail: "#{e.class}: #{first_line(e.message)}", options: options)
  end

  private

  def not_configured(name, detail)
    Result.new(language: name, verdict: :not_configured, phase: :config, detail: detail)
  end

  def first_line(text)
    text.to_s.lines.map(&:strip).reject(&:empty?).first.to_s.truncate(200)
  end
end
