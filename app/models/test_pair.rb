class TestPair < ActiveRecord::Base
  belongs_to :problem

  def self.get_for(problem, is_private)
    return TestPair.where(:problem_id => problem.id,
                          :is_private => is_private).first
  end

  def grade(output)
    out_items = output.split("\n")
    sol_items = solution.split("\n")
    res = ''
    f = 0
    s = 0
    sol_items.length.times do |i|
      f += 1
      si = sol_items[i].chomp
      if out_items[i]
        oi = out_items[i].chomp
      else
        oi = ''
      end
      if oi == si
        res = res + 'P'
        s += 1
      else
        res = res + '-'
      end
    end
    return { :score => s, :full_score => f, :msg => res }
  end

end
