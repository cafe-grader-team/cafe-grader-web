# Small, dependency-free statistics helpers shared by reports. Nearest-rank
# percentile (no interpolation) — matches the SQL-side percentile used in the
# 2026-09-12 exam analysis so the report and the postmortem agree.
module Stats
  module_function

  # q in [0.0, 1.0]. Returns nil for an empty collection.
  def percentile(values, q)
    return nil if values.nil? || values.empty?
    sorted = values.compact.sort
    return nil if sorted.empty?
    idx = (sorted.size * q).ceil - 1
    sorted[idx.clamp(0, sorted.size - 1)]
  end

  def mean(values)
    v = values&.compact
    return nil if v.nil? || v.empty?
    v.sum.to_f / v.size
  end
end
