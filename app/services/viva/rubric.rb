module Viva
  # Reads the machine-readable rubric out of a viva briefing (problems.viva_prompt)
  # and checks one grade's rubric scores against it — used by the contest's
  # Viva check page (VivaCheckReport); the contest checklist (doc/backlog.md)
  # will reuse it. The rubric is the "# Rubric" section, up to the next
  # heading of the same or a higher level, one item per line:
  #   - key (weight): what earns it          (key may be in backticks)
  module Rubric
    Result = Struct.new(:weights, keyword_init: true) do
      def readable?    = weights.any?
      def sum          = weights.values.sum
      def sums_to_100? = (sum - 100).abs < 0.001
    end

    HEADING = /\A(#+)\s+(.*?)\s*\z/
    ITEM    = /\A\s*[-*]\s+`?([A-Za-z0-9_]+)`?\s*\((\d+(?:\.\d+)?)\)/

    module_function

    def parse(text)
      weights = {}
      level = nil
      text.to_s.each_line do |raw|
        line = raw.chomp
        if (heading = HEADING.match(line))
          if level.nil?
            level = heading[1].size if heading[2].match?(/\ARubric\b/i)
            next
          end
          break if heading[1].size <= level

          next
        end
        next if level.nil?

        if (item = ITEM.match(line))
          weights[item[1]] = item[2].include?('.') ? item[2].to_f : item[2].to_i
        end
      end
      Result.new(weights: weights)
    end

    # What is wrong with one grade's rubric scores (viva_grades.score_json)
    # against `weights`; [] when the grade adds up. A score is a number; a
    # hash with a "score" or "points" field is read as that number.
    def grade_problems(weights, score_json, total)
      scores = begin
        JSON.parse(score_json.to_s)
      rescue JSON::ParserError
        nil
      end
      return ['rubric scores unreadable'] unless scores.is_a?(Hash) && scores.any?

      values  = scores.transform_values { |v| number(v) }
      out     = []
      unknown = scores.keys - weights.keys
      missing = weights.keys - scores.keys
      out << "not in the rubric: #{unknown.join(', ')}" if unknown.any?
      out << "missing: #{missing.join(', ')}" if missing.any?
      over = values.select { |k, v| v && weights[k] && v > weights[k] + 0.001 }
      out << "above maximum: #{over.map { |k, v| "#{k} #{fmt(v)}/#{fmt(weights[k])}" }.join(', ')}" if over.any?
      if values.values.any?(&:nil?)
        out << 'a rubric score is not a number'
      elsif total && (values.values.sum - total.to_f).abs > 0.01
        out << "items sum to #{fmt(values.values.sum)}, total is #{fmt(total.to_f)}"
      end
      out
    end

    def number(value)
      case value
      when Numeric then value.to_f
      when Hash    then number(value['score'] || value['points'])
      when String  then Float(value, exception: false)
      end
    end

    def fmt(x)
      (x.to_f % 1).zero? ? x.to_i.to_s : x.to_f.round(2).to_s
    end
  end
end
