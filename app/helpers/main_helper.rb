module MainHelper

  def link_to_description_if_any(name, problem, options={})
    if !problem.url.blank?
      return link_to name, problem.url, options
    elsif !problem.description_filename.blank?
      basename, ext = problem.description_filename.split('.')
      options[:controller] = 'tasks'
      options[:action] = 'download'
      options[:id] = problem.id
      options[:file] = basename
      options[:ext] = ext
      return link_to name, options
    else
      return ''
    end
  end

end
