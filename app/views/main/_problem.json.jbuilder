json.extract! problem, :id, :name, :full_name, :difficulty, :permitted_lang
json.tags problem.tags.pluck(:name)
json.statement_url download_by_type_problem_path(problem, 'statement') if problem.statement.attached? && problem.pdf_visible_to_student?
json.attachment_url download_by_type_problem_path(problem, 'attachment') if problem.attachment.attached?
json.best_score score = @prob_submissions[problem.id][:max_score]
