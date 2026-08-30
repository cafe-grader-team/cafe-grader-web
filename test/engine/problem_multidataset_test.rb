# test/engine/problem_multidataset_test.rb
require "test_helper"
require "tmpdir"

class ProblemMultidatasetTest < ActiveSupport::TestCase
  EXAMPLES = Rails.root.join("test", "problem_examples")

  def import_rich(name)
    pi = ProblemImporter.new
    pi.import_dataset_from_dir(EXAMPLES.join("rich").to_s, name, user: users(:admin))
    pi.problem.reload
  end

  def parsed_config(dir)
    YAML.safe_load(File.read(File.join(dir, "config.yml")), symbolize_names: true)
  end

  # relative paths of every file under `dir`, sorted
  def file_tree(dir)
    Dir.glob("#{dir}/**/*", File::FNM_DOTMATCH).select { |f| File.file?(f) }
       .map { |f| f.sub("#{dir}/", "") }.sort
  end

  test "live-only export produces a config with the expected keys and file tree" do
    p = import_rich("md_char")
    Dir.mktmpdir do |dump|
      ProblemExporter.new.export_problem_to_dir(p, base_dir: dump, zip: false)
      dir = File.join(dump, p.name.parameterize)
      cfg = parsed_config(dir)

      # problem + dataset fields present, no multi-dataset key
      assert_equal "md_char", cfg[:name]
      assert_equal "with_managers", cfg[:compilation_type]
      assert_equal "group_min", cfg[:score_type]
      assert cfg.key?(:testcases), "testcases hash present"
      refute cfg.key?(:additional_datasets), "no additional_datasets in a live-only export"

      tree = file_tree(dir)
      assert_includes tree, "config.yml"
      assert(tree.any? { |f| f.start_with?("testcases/") }, "has testcases/")
      assert(tree.none? { |f| f.start_with?("datasets/") }, "no datasets/ dir in live-only")
    end
  end

  test "all_datasets export writes each non-live dataset under datasets/ with a fragment" do
    p = import_rich("md_all")
    # add a second, non-live dataset with its own testcase
    ds2 = Dataset.create!(problem: p, name: "Alt DS", time_limit: 3, memory_limit: 128, score_type: :sum)
    tc = Testcase.new(code_name: "9", num: 1, group: 1, weight: 5)
    tc.inp_file.attach(io: StringIO.new("9 9\n"), filename: "input.txt", content_type: "text/plain")
    tc.ans_file.attach(io: StringIO.new("18\n"), filename: "answer.txt", content_type: "text/plain")
    ds2.testcases << tc
    ds2.save!

    Dir.mktmpdir do |dump|
      ProblemExporter.new.export_problem_to_dir(p, base_dir: dump, zip: false, all_datasets: true)
      dir = File.join(dump, p.name.parameterize)
      cfg = parsed_config(dir)

      assert_equal ["alt-ds"], cfg[:additional_datasets]
      sub = File.join(dir, "datasets", "alt-ds")
      assert File.directory?(sub), "datasets/alt-ds/ exists"
      frag = YAML.safe_load(File.read(File.join(sub, "config.yml")), symbolize_names: true)
      assert_equal "Alt DS", frag[:ds_name]
      assert_equal 3.0, frag[:time_limit]
      assert frag[:testcases].key?("9".to_sym) || frag[:testcases].key?("9"), "fragment has the testcase weight entry"
      assert File.exist?(File.join(sub, "testcases", "9.in")), "additional dataset testcase exported"
      refute frag.key?(:name), "fragment carries no problem-level fields"
    end
  end

  test "all_datasets de-duplicates colliding parameterized dataset dir names" do
    p = import_rich("md_collide")
    ["Same Name", "same name"].each_with_index do |nm, i|
      ds = Dataset.create!(problem: p, name: nm, time_limit: 1, memory_limit: 64, score_type: :sum)
      tc = Testcase.new(code_name: "1", num: 1, group: 1, weight: 1)
      tc.inp_file.attach(io: StringIO.new("#{i}\n"), filename: "i", content_type: "text/plain")
      tc.ans_file.attach(io: StringIO.new("#{i}\n"), filename: "a", content_type: "text/plain")
      ds.testcases << tc; ds.save!
    end
    Dir.mktmpdir do |dump|
      ProblemExporter.new.export_problem_to_dir(p, base_dir: dump, zip: false, all_datasets: true)
      dir = File.join(dump, p.name.parameterize)
      subs = Dir.children(File.join(dir, "datasets")).sort
      assert_equal ["same-name", "same-name-2"], subs, "colliding names get distinct suffixed dirs"
      assert_equal ["same-name", "same-name-2"], parsed_config(dir)[:additional_datasets].sort
    end
  end

  test "import reads additional datasets from datasets/ into non-live datasets" do
    src = import_rich("md_imp_src")
    ds2 = Dataset.create!(problem: src, name: "Extra DS", time_limit: 2, memory_limit: 64, score_type: :sum)
    tc = Testcase.new(code_name: "7", num: 1, group: 1, weight: 3)
    tc.inp_file.attach(io: StringIO.new("7\n"), filename: "input.txt", content_type: "text/plain")
    tc.ans_file.attach(io: StringIO.new("7\n"), filename: "answer.txt", content_type: "text/plain")
    ds2.testcases << tc
    ds2.save!
    live_name = src.live_dataset.name

    Dir.mktmpdir do |dump|
      ProblemExporter.new.export_problem_to_dir(src, base_dir: dump, zip: false, all_datasets: true)
      exported = File.join(dump, src.name.parameterize)

      pi = ProblemImporter.new
      pi.import_dataset_from_dir(exported, "md_imp_dst", user: users(:admin))
      dst = pi.problem.reload

      assert_equal 2, dst.datasets.count, "both datasets imported"
      extra = dst.datasets.find_by(name: "Extra DS")
      assert extra, "additional dataset created by name"
      refute_equal extra.id, dst.live_dataset.id, "additional dataset is NOT live"
      assert_equal 2.0, extra.time_limit.to_f
      assert_equal 1, extra.testcases.count
      assert_equal "7\n", extra.testcases.first.inp_file.download
      # live dataset still imported as today
      assert dst.live_dataset.testcases.count.positive?
    end
  end

  test "re-importing all-datasets onto the same problem does not duplicate additional datasets" do
    src = import_rich("md_idem_src")
    Dataset.create!(problem: src, name: "Once DS", time_limit: 1, memory_limit: 64, score_type: :sum).tap do |d|
      tc = Testcase.new(code_name: "1", num: 1, group: 1, weight: 1)
      tc.inp_file.attach(io: StringIO.new("1\n"), filename: "i", content_type: "text/plain")
      tc.ans_file.attach(io: StringIO.new("1\n"), filename: "a", content_type: "text/plain")
      d.testcases << tc; d.save!
    end
    Dir.mktmpdir do |dump|
      ProblemExporter.new.export_problem_to_dir(src, base_dir: dump, zip: false, all_datasets: true)
      exported = File.join(dump, src.name.parameterize)
      ProblemImporter.new.import_dataset_from_dir(exported, "md_idem_dst", user: users(:admin))
      ProblemImporter.new.import_dataset_from_dir(exported, "md_idem_dst", user: users(:admin))
    end
    dst = Problem.find_by(name: "md_idem_dst")
    assert_equal 1, dst.datasets.where(name: "Once DS").count, "additional dataset matched by name, not duplicated"
  end

  test "export(all) -> import round-trips EVERY dataset field-by-field" do
    src = import_rich("md_rt_src")
    ds2 = Dataset.create!(problem: src, name: "Second", time_limit: 4, memory_limit: 77,
                          score_type: :group_min, evaluation_type: :exact)
    %w[1-1 2-1].each_with_index do |cn, i|
      tc = Testcase.new(code_name: cn, num: i + 1, group: i + 1, group_name: "g#{i + 1}", weight: (i + 1) * 5)
      tc.inp_file.attach(io: StringIO.new("#{i}\n"), filename: "i", content_type: "text/plain")
      tc.ans_file.attach(io: StringIO.new("#{i}\n"), filename: "a", content_type: "text/plain")
      ds2.testcases << tc
    end
    ds2.save!

    Dir.mktmpdir do |dump|
      ProblemExporter.new.export_problem_to_dir(src, base_dir: dump, zip: false, all_datasets: true)
      exported = File.join(dump, src.name.parameterize)
      ProblemImporter.new.import_dataset_from_dir(exported, "md_rt_dst", user: users(:admin))
    end
    dst = Problem.find_by(name: "md_rt_dst").reload

    assert_equal src.datasets.count, dst.datasets.count
    s2 = src.datasets.find_by(name: "Second")
    d2 = dst.datasets.find_by(name: "Second")
    assert d2, "additional dataset present by name"
    %w[time_limit memory_limit score_type evaluation_type].each do |f|
      assert_equal s2.send(f), d2.send(f), "Second##{f} round-trips"
    end
    assert_equal s2.testcases.count, d2.testcases.count
    s2.testcases.order(:num).zip(d2.testcases.order(:num)).each do |a, b|
      %w[code_name group group_name weight].each { |f| assert_equal a.send(f), b.send(f), "tc##{f}" }
      assert_equal a.inp_file.download, b.inp_file.download
      assert_equal a.ans_file.download, b.ans_file.download
    end
    # live dataset also intact
    ls = src.live_dataset
    ld = dst.live_dataset
    assert_equal ls.testcases.count, ld.testcases.count
    assert_equal ls.score_type, ld.score_type, "live dataset score_type intact"
    ls.testcases.order(:num).zip(ld.testcases.order(:num)).each do |a, b|
      assert_equal a.code_name, b.code_name, "live tc code_name intact"
      assert_equal a.inp_file.download, b.inp_file.download, "live tc input intact"
    end
  end

  test "do_additional_datasets:false imports only the live dataset" do
    src = import_rich("md_noadd_src")
    Dataset.create!(problem: src, name: "Skip Me", time_limit: 1, memory_limit: 64, score_type: :sum).tap do |d|
      tc = Testcase.new(code_name: "1", num: 1, group: 1, weight: 1)
      tc.inp_file.attach(io: StringIO.new("1\n"), filename: "i", content_type: "text/plain")
      tc.ans_file.attach(io: StringIO.new("1\n"), filename: "a", content_type: "text/plain")
      d.testcases << tc; d.save!
    end
    Dir.mktmpdir do |dump|
      ProblemExporter.new.export_problem_to_dir(src, base_dir: dump, zip: false, all_datasets: true)
      exported = File.join(dump, src.name.parameterize)
      pi = ProblemImporter.new
      pi.import_dataset_from_dir(exported, "md_noadd_dst", user: users(:admin), do_additional_datasets: false)
      assert_equal 1, pi.problem.reload.datasets.count, "additional datasets skipped when flag is false"
    end
  end

  test "additional dataset with a grader does not corrupt problem submission_filename" do
    src = import_rich("md_subf_src")
    src.update!(submission_filename: "custom_sub.h")
    ds2 = Dataset.create!(problem: src, name: "Grader DS", time_limit: 1, memory_limit: 64, score_type: :sum)
    ds2.managers.attach(io: StringIO.new("int main(){}\n"), filename: "grader.cpp", content_type: "text/plain")
    tc = Testcase.new(code_name: "1", num: 1, group: 1, weight: 1)
    tc.inp_file.attach(io: StringIO.new("1\n"), filename: "i", content_type: "text/plain")
    tc.ans_file.attach(io: StringIO.new("1\n"), filename: "a", content_type: "text/plain")
    ds2.testcases << tc; ds2.save!

    Dir.mktmpdir do |dump|
      ProblemExporter.new.export_problem_to_dir(src, base_dir: dump, zip: false, all_datasets: true)
      exported = File.join(dump, src.name.parameterize)
      ProblemImporter.new.import_dataset_from_dir(exported, "md_subf_dst", user: users(:admin))
    end
    dst = Problem.find_by(name: "md_subf_dst")
    assert_equal "custom_sub.h", dst.submission_filename, "additional dataset's grader must not clobber problem submission_filename"
  end

  test "Problem#export forwards all_datasets" do
    p = import_rich("md_pexport")
    Dataset.create!(problem: p, name: "X DS", time_limit: 1, memory_limit: 64, score_type: :sum).tap do |d|
      tc = Testcase.new(code_name: "1", num: 1, group: 1, weight: 1)
      tc.inp_file.attach(io: StringIO.new("1\n"), filename: "i", content_type: "text/plain")
      tc.ans_file.attach(io: StringIO.new("1\n"), filename: "a", content_type: "text/plain")
      d.testcases << tc; d.save!
    end
    Dir.mktmpdir do |dump|
      res = p.export(all_datasets: true, base_dir: dump, zip: false)
      assert_equal :ok, res[:status]
      assert File.directory?(File.join(dump, p.name.parameterize, "datasets", "x-ds"))
    end
  end
end
