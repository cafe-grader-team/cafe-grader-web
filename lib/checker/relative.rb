#!/usr/bin/env ruby

output_file = ARGV[1]
ans_file = ARGV[2]

if ARGV.count < 3 || File.exist?(output_file) == false || File.exist?(ans_file) == false
  exit 2
end

EPSILON = 0.000001

out_tokens = File.read(output_file).split
ans_tokens = File.read(ans_file).split

def is_float?(fl)
  !!Float(fl) rescue false
end

def report_wrong
  exit 1
end

def report_correct
  exit 0
end

report_wrong if out_tokens.length != ans_tokens.length

out_tokens.length.times do |i|
  if is_float?(out_tokens[i]) && is_float?(ans_tokens[i])
    out_value = out_tokens[i].to_f
    ans_value = ans_tokens[i].to_f
    if (out_value - ans_value).abs > EPSILON * [out_value.abs,ans_value.abs].max
      report_wrong
    end
  else
    report_wrong if out_tokens[i] != ans_tokens[i]
  end
end
report_correct
