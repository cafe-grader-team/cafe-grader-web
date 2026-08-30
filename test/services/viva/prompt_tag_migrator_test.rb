require 'test_helper'

class Viva::PromptTagMigratorTest < ActiveSupport::TestCase
  def make_viva(name)
    Problem.create!(name: name, full_name: name, full_score: 100, compilation_type: :viva_exam)
  end

  setup do
    @out = StringIO.new
    @v1 = make_viva('viva-a')
    @v2 = make_viva('viva-b')
    @coding = Problem.create!(name: 'code-x', full_name: 'code-x', full_score: 100)
    @pseudo = Tag.create!(name: 'p1-prompt', kind: :llm_prompt, params: "# Rubric\nsolo")
    @shared = Tag.create!(name: 'ai_viva', kind: :llm_prompt, params: 'persona text')
    @dual   = Tag.create!(name: 'codey', kind: :llm_prompt, params: 'helper')
    @v1.tags << @pseudo
    @v1.tags << @shared
    @v2.tags << @shared
    @v2.tags << @dual
    @coding.tags << @dual
  end

  test 'dry run reports everything and changes nothing' do
    Viva::PromptTagMigrator.new(apply: false, io: @out).run
    report = @out.string
    assert_match(/MOVE\s+tag ##{@pseudo.id}/, report)
    assert_match(/RE-KIND\s+tag ##{@shared.id}/, report)
    assert_match(/DUAL-USE\s+tag ##{@dual.id}/, report)
    assert Tag.exists?(@pseudo.id)
    assert @shared.reload.llm_prompt?
    assert_nil @v1.reload.viva_prompt
  end

  test 'apply moves pseudo-tags, re-kinds shared, skips dual-use' do
    Viva::PromptTagMigrator.new(apply: true, io: @out).run
    assert_equal "# Rubric\nsolo", @v1.reload.viva_prompt
    refute Tag.exists?(@pseudo.id)
    assert @shared.reload.viva_conduct?
    assert_equal false, @shared.public
    assert @dual.reload.llm_prompt?, 'dual-use tag must be left alone'
    assert_includes @dual.problems.reload, @coding
  end

  test 'apply skips move when problem already has a different viva_prompt' do
    v3 = make_viva('viva-c')
    v3.update!(viva_prompt: "# Rubric\nexisting")
    conflicting = Tag.create!(name: 'p3-prompt', kind: :llm_prompt, params: "# Rubric\ndifferent")
    v3.tags << conflicting

    Viva::PromptTagMigrator.new(apply: true, io: @out).run

    assert_equal "# Rubric\nexisting", v3.reload.viva_prompt
    assert Tag.exists?(conflicting.id)
    assert conflicting.reload.llm_prompt?
    assert_includes conflicting.problems.reload, v3
    assert_match(/CONFLICT\s+tag ##{conflicting.id}/, @out.string)
  end
end
