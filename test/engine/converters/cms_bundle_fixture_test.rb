require 'test_helper'

# Guards the committed CMS bundle fixture that the converter tests build on:
# valid JSON, expected versions, and no dangling digest references.
class CmsBundleFixtureTest < ActiveSupport::TestCase
  FIXTURE = Rails.root.join('test/cms_bundles/eatingfish_mini')

  test 'fixture task.json parses with expected versions and complete blobs' do
    data = JSON.parse(File.read(FIXTURE.join('task.json')))
    assert_equal 1, data['bundle_version']
    assert_equal 39, data['dump_version']
    objects = data['objects']
    task = objects[data['task_id']]
    assert_equal 'Task', task['_class']

    digests = []
    task['statements'].each_value  { |id| digests << objects[id]['digest'] }
    task['attachments'].each_value { |id| digests << objects[id]['digest'] }
    task['datasets'].each do |did|
      ds = objects[did]
      ds['managers'].each_value { |id| digests << objects[id]['digest'] }
      ds['testcases'].each_value do |id|
        digests << objects[id]['input'] << objects[id]['output']
      end
    end
    digests.uniq.each do |dig|
      assert FIXTURE.join('files', dig).exist?, "missing blob files/#{dig}"
    end
  end
end
