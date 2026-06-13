#!/usr/bin/env ruby

#this use CMS style

output_file = ARGV[1]
ans_file = ARGV[2]

# check if the arguments are present and the files exist
if ARGV.count < 3 || File.exist?(output_file) == false || File.exist?(ans_file) == false
  exit 2
end


#read contestant and answer and ignore DROP VIEW or CREATE VIEW line
out_lines = File.readlines(output_file).map{|x| x.chomp}.reject{ |x| ["DROP VIEW","CREATE VIEW"].include? x.strip.upcase}
ans_lines = File.readlines(ans_file).map{|x| x.chomp}.reject{ |x| ["DROP VIEW","CREATE VIEW"].include? x.strip.upcase}


def report_wrong
  puts 0
  exit 0
end

def report_correct
  puts 1
  exit 0
end

# used when the output is OK but the first line (header) is not correct
def report_wrong_header
  puts 0.8
  STDERR.puts "Column names are not correct"
  exit 0
end

# if the number of lines is not equal, reject
report_wrong if out_lines.length != ans_lines.length

out_header = out_lines[0].split(',').map{ |x| x.strip}
ans_header = ans_lines[0].split(',').map{ |x| x.strip}

header_correctness = out_header == ans_header


[1..out_lines.count-1].each do |ln|
  report_wrong if out_lines[ln] != ans_lines[ln]
end

# check correct header
if header_correctness
  report_correct
else
  report_wrong_header
end

