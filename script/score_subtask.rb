def display_manual
  puts <<-USAGE
    subtask_score problem last_submision_id sub1_score,sub2_score,sub3_score,....
    example:
      rails runner subtask_score.rb o64_may26_train 102983 10,15,18,18,39
  USAGE
end

def process_options
  res = {}
  if ARGV.length == 0
    display_manual
    exit(1)
  end

  res[:prob] = ARGV[0]
  res[:last_sub_id] = ARGV[1].to_i
  res[:score] = ARGV[2].split(',').map {|x| x.to_i}
  return res
end

def process_subtask(st)
  return true if /^P+$/.match(st)
  return false
end

def process_comment(st)
  res = []
  loop do
    break if st.length == 0
    if st[0] == '['
      #subtask
      subtask = st.slice!(0..(st.index(']')))
      res << process_subtask(subtask[1..-2])
    else #not subtask
      res << process_subtask(st[0])
      st.slice!(0)
    end
  end
  return res
end

options = process_options
scoring = options[:score]
puts "doing problem #{options[:prob]}"
puts "  consider only submission with id not more than #{options[:last_sub_id]}"
scoring.each.with_index { |x,i| puts "  subtask#{i}: #{x}" }

res = {}

p = Problem.where(name: options[:prob]).first
unless p
  puts "Problem #{options[:prob]} not found"
  exit(2)
end

p.submissions.where('id <= ?',options[:last_sub_id]).order(:id).each do |sub|
  unless sub.graded_at
    puts "skip ungraded submission #{sub.id}"
    next
  end
  if sub.grader_comment == "compilation error"
    puts "skip uncompilable submission #{sub.id}"
    next
  end

  comment = sub.grader_comment.clone
  comment_result = process_comment(comment)
  if comment_result.length != scoring.length
    puts "ERROR!!! subtask of submission #{sub.id} does not match scoring input"
  end

  puts "processing submission #{sub.id} with comment = #{sub.grader_comment} result is #{comment_result}"
  current = res[sub.user.login] || [false] * scoring.length
  current.each.with_index do |x,i|
    if !x && comment_result[i]
      puts "  user #{sub.user.login} just got subtask #{i+1} from this submission"
      current[i] = true
    end
  end
  res[sub.user.login] = current
end

puts "----summary-----"
res.each do |u,r|
  score = scoring.clone
  r.each.with_index { |pass,i| score[i] = 0 unless pass }
  puts "#{u} #{score.sum} [#{score.join(',')}]"
end
