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

  test 'refuses to overwrite a non-viva problem with the same name' do
    Problem.create!(name: 'vk_alpha', full_name: 'coding alpha', full_score: 100)
    refute run_import(apply: true)
    assert_match(/ERROR\s+problem 'vk_alpha' exists but is not a viva_exam/, @out.string)
    assert_equal 'coding alpha', Problem.find_by!(name: 'vk_alpha').full_name
    assert_nil Problem.find_by(name: 'vk_beta')
  end
end
