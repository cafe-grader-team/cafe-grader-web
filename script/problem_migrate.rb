Problem.all.each do |p|
  next unless p.description_filename
  basename, ext = p.description_filename.split('.')
  filename = "#{Problem.download_file_basedir}/#{p.id}/#{basename}.#{ext}"

  if File.exists? filename
    p.statement.attach io: File.open(filename), filename: "#{basename}.#{ext}"
    puts "#{p.id}: OK"
  else
    puts "#{p.id}: #{p.name} #{filename} ERROR"
  end

  d = Description.where(id: p.description_id).first
  if d
    p.description = d.body
    p.markdown = d.markdowned
  end
  p.save

  
end
