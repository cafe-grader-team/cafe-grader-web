# test/engine/problem_round_trip_test.rb
require "test_helper"
require "tmpdir"

class ProblemRoundTripTest < ActiveSupport::TestCase
  EXAMPLES = Rails.root.join("test", "problem_examples")

  PROBLEM_FIELDS = %w[full_name description markdown submission_filename
                      task_type compilation_type permitted_lang].freeze
  DATASET_FIELDS = %w[time_limit memory_limit score_type evaluation_type
                      score_param main_filename initializer_filename].freeze
  TESTCASE_FIELDS = %w[code_name num group group_name weight].freeze

  def import_dir(dir, name)
    pi = ProblemImporter.new
    pi.import_dataset_from_dir(dir.to_s, name, user: users(:admin))
    pi.problem.reload
  end

  test "import -> export -> re-import preserves the portable package" do
    original = import_dir(EXAMPLES.join("rich"), "rt_original")

    Dir.mktmpdir do |dump|
      pe = ProblemExporter.new
      pe.export_problem_to_dir(original, base_dir: dump, zip: false)
      exported_dir = File.join(dump, original.name.parameterize)

      copy = import_dir(exported_dir, "rt_copy")

      PROBLEM_FIELDS.each do |f|
        assert_equal original.send(f), copy.send(f), "Problem##{f} lost in round-trip"
      end
      assert_equal original.tags.pluck(:name).sort, copy.tags.pluck(:name).sort
      assert_equal original.statement.download, copy.statement.download
      assert_equal original.attachment.download, copy.attachment.download

      ods, cds = original.live_dataset, copy.live_dataset
      DATASET_FIELDS.each do |f|
        assert_equal ods.send(f), cds.send(f), "Dataset##{f} lost in round-trip"
      end
      assert_equal ods.checker.download, cds.checker.download
      %w[managers initializers data_files].each do |coll|
        assert_equal ods.send(coll).map { |a| a.filename.to_s }.sort,
                     cds.send(coll).map { |a| a.filename.to_s }.sort,
                     "Dataset##{coll} filenames lost in round-trip"
      end

      assert_equal ods.testcases.count, cds.testcases.count
      ods.testcases.order(:num).zip(cds.testcases.order(:num)).each do |o, c|
        TESTCASE_FIELDS.each { |f| assert_equal o.send(f), c.send(f), "Testcase##{f} differs (#{o.code_name})" }
        assert_equal o.inp_file.download, c.inp_file.download
        assert_equal o.ans_file.download, c.ans_file.download
      end

      # model solutions re-exportable: copy has a :model-tagged submission
      assert_equal 1, copy.submissions.where(tag: :model).count
    end
  end

  test "dump_problems does not crash (zip default typo)" do
    import_dir(EXAMPLES.join("rich"), "rt_dump")
    Dir.mktmpdir do |dump|
      assert_nothing_raised do
        ProblemExporter.dump_problems(Problem.where(name: "rt_dump"), dump)
      end
    end
  end

  test "exported statement file is named statement.pdf" do
    p = import_dir(EXAMPLES.join("rich"), "rt_stmt")
    Dir.mktmpdir do |dump|
      ProblemExporter.new.export_problem_to_dir(p, base_dir: dump, zip: false)
      assert File.exist?(File.join(dump, p.name.parameterize, "statement.pdf")),
             "expected statement.pdf in the exported package"
    end
  end
end
