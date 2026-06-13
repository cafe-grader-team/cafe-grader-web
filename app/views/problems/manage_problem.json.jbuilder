# for data table
json.data do
  json.array! @problems do |prob|
    json.extract! prob, :id, :name, :full_name, :difficulty, :permitted_lang, :date_added
    json.extract! prob, :available, :view_testcase
    json.tags prob.tags.pluck(:name)
    json.statement_attached prob.statement.attached?
    json.statement_path download_by_type_problem_path(prob, 'statement')
    json.attachment_attached prob.attachment.attached?
    json.attachment_path download_by_type_problem_path(prob, 'attachment')
  end
end
