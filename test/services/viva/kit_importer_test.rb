require 'test_helper'

class Viva::KitImporterTest < ActiveSupport::TestCase
  setup do
    @out = StringIO.new
    @kit = file_fixture('viva_kit').to_s
  end

  def run_import(dir = @kit, apply:)
    Viva::KitImporter.new(dir, apply: apply, io: @out).run
  end

  def copy_kit_to(tmp)
    FileUtils.cp_r(File.join(@kit, '.'), tmp)
    tmp
  end

  test 'dry run reports creates and changes nothing' do
    assert run_import(apply: false)
    report = @out.string
    assert_match(/CONDUCT\s+create tag 'fixture-viva-conduct'/, report)
    assert_match(/CREATE\s+problem 'vk_alpha'/, report)
    assert_match(/CREATE\s+problem 'vk_beta'/, report)
    assert_match(/GROUNDING create 'fixture-grounding'/, report)
    assert_match(/GROUNDING attach 'fixture-grounding' -> vk_alpha/, report)
    assert_nil Problem.find_by(name: 'vk_alpha')
    assert_nil Tag.find_by(name: 'fixture-viva-conduct')
    assert_nil GroundingMaterial.find_by(title: 'fixture-grounding')
  end

  test 'apply creates viva problems with dataset, caps, conduct link; re-run is a no-op' do
    assert run_import(apply: true)

    alpha = Problem.find_by!(name: 'vk_alpha')
    assert alpha.viva_exam?
    assert_equal 'Viva: Alpha', alpha.full_name
    assert_equal "# Alpha scenario\n\nDesign a thing.", alpha.description
    assert_match(/^# Rubric/, alpha.viva_prompt)
    assert_equal 8, alpha.viva_soft_cap
    assert_equal 12, alpha.viva_hard_cap
    assert_equal 5, alpha.viva_daily_limit
    assert_equal false, alpha.available
    assert alpha.live_dataset.present?, 'default live dataset created'
    assert_empty alpha.viva_setup_errors

    beta = Problem.find_by!(name: 'vk_beta')
    assert_equal 10, beta.viva_soft_cap
    assert_equal true, beta.available, 'per-problem available override honored on create'

    tag = Tag.find_by!(name: 'fixture-viva-conduct')
    assert tag.viva_conduct?
    assert_equal false, tag.public
    assert_equal [tag], alpha.viva_conduct_tags.to_a
    assert_equal [tag], beta.viva_conduct_tags.to_a

    gm = GroundingMaterial.find_by!(title: 'fixture-grounding')
    assert_equal "## Fixture reference\n\nUse `std::vector` for the alpha task.", gm.body
    assert_equal 'Fixture reference text', gm.description
    assert_equal [gm], alpha.grounding_materials.to_a, 'attached to the listed problem'
    assert_empty beta.grounding_materials, 'not attached to unlisted problems'

    @out.truncate(0)
    assert run_import(apply: true)
    assert_match(/CONDUCT\s+unchanged/, @out.string)
    assert_match(/GROUNDING unchanged 'fixture-grounding'/, @out.string)
    assert_match(/GROUNDING links unchanged 'fixture-grounding' \(1 problem/, @out.string)
    assert_equal 1, GroundingMaterial.where(title: 'fixture-grounding').count
    assert_match(/UNCHANGED problem 'vk_alpha'/, @out.string)
    assert_match(/UNCHANGED problem 'vk_beta'/, @out.string)
  end

  test 'apply updates changed briefing only and never touches available' do
    assert run_import(apply: true)
    Problem.find_by!(name: 'vk_alpha').update!(available: true)

    Dir.mktmpdir do |tmp|
      copy_kit_to(tmp)
      File.write(File.join(tmp, 'alpha.briefing.md'), "New model answer.\n\n# Rubric\n\n- design (100)\n")
      @out.truncate(0)
      assert run_import(tmp, apply: true)
    end

    assert_match(/UPDATE\s+problem 'vk_alpha' — viva_prompt$/, @out.string)
    alpha = Problem.find_by!(name: 'vk_alpha')
    assert_match(/^New model answer/, alpha.viva_prompt)
    assert_equal true, alpha.available, 'available must survive re-import'
  end

  test 'a briefing without a Rubric heading fails the whole import' do
    Dir.mktmpdir do |tmp|
      copy_kit_to(tmp)
      File.write(File.join(tmp, 'beta.briefing.md'), "no rubric here\n")
      refute run_import(tmp, apply: true)
    end
    assert_match(/ERROR\s+post-check problem 'vk_beta'/, @out.string)
    assert_nil Problem.find_by(name: 'vk_alpha'), 'transaction rolled back'
  end

  test 'grounding body change updates the material and keeps manual attachments' do
    assert run_import(apply: true)
    alpha = Problem.find_by!(name: 'vk_alpha')
    alpha.grounding_materials << grounding_materials(:gm_dijkstra)

    Dir.mktmpdir do |tmp|
      copy_kit_to(tmp)
      File.write(File.join(tmp, '_grounding.md'), "## Revised reference\n")
      @out.truncate(0)
      assert run_import(tmp, apply: true)
    end

    assert_match(/GROUNDING update 'fixture-grounding' — body/, @out.string)
    gm = GroundingMaterial.find_by!(title: 'fixture-grounding')
    assert_equal '## Revised reference', gm.body
    assert_equal [gm, grounding_materials(:gm_dijkstra)].sort_by(&:id), alpha.reload.grounding_materials.sort_by(&:id),
                 'import is add-only: the hand-attached material survives'
  end

  test 'grounding that names a problem outside the manifest fails the whole import' do
    Dir.mktmpdir do |tmp|
      copy_kit_to(tmp)
      manifest = File.join(tmp, 'manifest.yml')
      File.write(manifest, File.read(manifest).sub('problems: [vk_alpha]', 'problems: [vk_alpha, vk_gamma]'))
      refute run_import(tmp, apply: true)
    end
    assert_match(/ERROR\s+grounding 'fixture-grounding' names problems not in this manifest: vk_gamma/, @out.string)
    assert_nil Problem.find_by(name: 'vk_alpha'), 'transaction rolled back'
    assert_nil GroundingMaterial.find_by(title: 'fixture-grounding')
  end

  # Rewrites the fixture manifest's single `conduct_tag:` into a
  # `conduct_tags:` list (course profile + mode overlay) inside tmp.
  def with_two_conduct_tags(tmp, second_name: 'fixture-viva-conduct-practice')
    copy_kit_to(tmp)
    File.write(File.join(tmp, '_conduct_mode.md'), "# Mode: practice\n\nOne hint per topic.\n")
    manifest = File.join(tmp, 'manifest.yml')
    File.write(manifest, File.read(manifest).sub(
      "conduct_tag:\n  name: fixture-viva-conduct\n  file: _conduct.md\n",
      "conduct_tags:\n  - name: fixture-viva-conduct\n    file: _conduct.md\n" \
      "  - name: #{second_name}\n    file: _conduct_mode.md\n"
    ))
    tmp
  end

  test 'conduct_tags list creates every tag and links all of them to every problem, in name order' do
    Dir.mktmpdir do |tmp|
      with_two_conduct_tags(tmp)
      assert run_import(tmp, apply: true)
      report = @out.string
      assert_match(/CONDUCT\s+create tag 'fixture-viva-conduct'/, report)
      assert_match(/CONDUCT\s+create tag 'fixture-viva-conduct-practice' \(\d+ chars\)/, report)

      base = Tag.find_by!(name: 'fixture-viva-conduct')
      mode = Tag.find_by!(name: 'fixture-viva-conduct-practice')
      assert mode.viva_conduct?
      assert_equal "# Mode: practice\n\nOne hint per topic.", mode.params
      %w[vk_alpha vk_beta].each do |name|
        assert_equal [base, mode], Problem.find_by!(name: name).viva_conduct_tags.to_a,
                     "#{name} carries both tags, base first (name order)"
      end

      @out.truncate(0)
      assert run_import(tmp, apply: true)
      assert_match(/CONDUCT\s+unchanged tag 'fixture-viva-conduct'/, @out.string)
      assert_match(/CONDUCT\s+unchanged tag 'fixture-viva-conduct-practice'/, @out.string)
      assert_match(/UNCHANGED problem 'vk_alpha'/, @out.string)
      assert_match(/UNCHANGED problem 'vk_beta'/, @out.string)
    end
  end

  test 'adding an overlay to an already-imported kit links it and reports which tag' do
    assert run_import(apply: true)
    Dir.mktmpdir do |tmp|
      with_two_conduct_tags(tmp)
      @out.truncate(0)
      assert run_import(tmp, apply: true)
    end
    assert_match(/UPDATE\s+problem 'vk_alpha' — conduct linked: fixture-viva-conduct-practice$/, @out.string)
    assert_equal %w[fixture-viva-conduct fixture-viva-conduct-practice],
                 Problem.find_by!(name: 'vk_alpha').viva_conduct_tags.map(&:name)
  end

  test 'the same conduct tag named twice in a manifest fails the whole import' do
    Dir.mktmpdir do |tmp|
      with_two_conduct_tags(tmp, second_name: 'fixture-viva-conduct')
      refute run_import(tmp, apply: true)
    end
    assert_match(/ERROR\s+conduct tag named more than once in manifest: fixture-viva-conduct/, @out.string)
    assert_nil Problem.find_by(name: 'vk_alpha'), 'transaction rolled back'
    assert_nil Tag.find_by(name: 'fixture-viva-conduct')
  end

  test 'refuses to overwrite a non-viva problem with the same name' do
    Problem.create!(name: 'vk_alpha', full_name: 'coding alpha', full_score: 100)
    refute run_import(apply: true)
    assert_match(/ERROR\s+problem 'vk_alpha' exists but is not a viva_exam/, @out.string)
    assert_equal 'coding alpha', Problem.find_by!(name: 'vk_alpha').full_name
    assert_nil Problem.find_by(name: 'vk_beta')
  end
  test 'apply writes one audit row per updated problem, naming scenario and briefing' do
    assert run_import(apply: true)
    alpha = Problem.find_by!(name: 'vk_alpha')
    old_scenario = alpha.description

    Dir.mktmpdir do |tmp|
      copy_kit_to(tmp)
      File.write(File.join(tmp, 'alpha.scenario.md'), "# Alpha scenario v2\n\nDesign a better thing.")
      File.write(File.join(tmp, 'alpha.briefing.md'), "New model answer.\n\n# Rubric\n\n- design (100)\n")
      @out.truncate(0)
      Current.actor_note = 'Rake: viva:import test'
      assert_difference -> { AuditLog.for(alpha).where(action: 'update').count }, 1 do
        assert run_import(tmp, apply: true)
      end
    end
    assert_match(/UPDATE\s+problem 'vk_alpha' — description, viva_prompt/, @out.string)

    row = AuditLog.for(alpha).where(action: 'update').last
    assert_equal %w[description viva_prompt], row.object_changes.keys.sort
    assert_equal [old_scenario, "# Alpha scenario v2\n\nDesign a better thing."], row.object_changes['description'],
                 'the scenario text is stored (it is what students see, and small)'
    assert_equal [AuditLog::REDACTED, AuditLog::REDACTED], row.object_changes['viva_prompt'],
                 'the briefing stays redacted'
    assert_equal 'Rake: viva:import test', row.actor_note
  ensure
    Current.actor_note = nil
  end
end
