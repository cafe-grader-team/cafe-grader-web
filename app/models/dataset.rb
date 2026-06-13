class Dataset < ApplicationRecord
  include Auditable
  audited only: %i[problem_id name time_limit memory_limit
                   score_type evaluation_type score_param
                   main_filename initializer_filename]

  belongs_to :problem

  has_many :testcases, dependent: :destroy
  has_many :submissions

  # How a submission's output is judged against the expected answer.
  # Behavior of each value is documented in doc/dataset-scoring-and-evaluation.md
  # and consumed by app/engine/checker.rb (check_command, process_result).
  # Quick reference:
  #   default        diff -b -B -Z (ignores whitespace + blank lines)
  #   exact          diff -q (strict)
  #   relative       lib/checker/relative.rb (numbers compared with 1e-6)
  #   custom_cafe    user's checker; line1=CORRECT/INCORRECT/COMMENT, line2=score/10
  #   custom_cms     user's checker; CMS/Codeforces — score on stdout, comment on stderr
  #   postgres       lib/checker/postgres_checker.rb (CMS-style, strips CREATE/DROP VIEW)
  #   custom_cms_raw user's checker; raw decimal stdout. Pair with score_type :raw_sum.
  enum :evaluation_type, { default: 0,
                           exact: 1,
                           relative: 2,
                           custom_cafe: 3,
                           custom_cms: 4,
                           postgres: 5,
                           custom_cms_raw: 6}

  # How per-testcase scores aggregate into the submission's final grade.
  # Computed in app/engine/scorer.rb (sum_of_all_testcases, group_min, raw_sum).
  # Quick reference:
  #   sum         weighted sum / total weight × 100 (default)
  #   group_min   IOI/ICPC subtask style — a group earns only as much as its weakest case
  #   raw_sum     literal Σ of testcase scores. Pair with evaluation_type :custom_cms_raw.
  enum :score_type,      { sum: 0,
                           group_min: 1,
                           raw_sum: 2,
                         }, prefix: :st

  has_one_attached :checker
  has_many_attached :managers       # additional files for compile process (these files are VISIBLE to the user's submission)
  has_many_attached :initializers   # additional files for initialization of testcases
  has_many_attached :data_files     # additional files when running

  # Runs BEFORE validation so the presence check below sees the
  # auto-picked main_filename. update_main_filename: when managers
  # are attached, points main_filename at the first manager if the
  # current value isn't a member of the manager set (covers blank,
  # stale, and renamed-file cases). When managers are empty, clears
  # the field. See app/engine/compiler.rb:87/158, compiler/python.rb:33
  # for how main_filename is consumed at compile time.
  before_validation :update_main_filename

  # main_filename is the file the compiler will actually invoke
  # (compiler.rb:87 selects it via with_managers?). Letting a
  # with_managers dataset save without it produces opaque grader
  # errors at compile time — empty Pathname + nil, etc. — so we
  # block the save instead. The before_validation callback above
  # normally fills this in automatically when managers exist; this
  # validation just enforces the contract in case the callback was
  # bypassed (update_columns, raw SQL).
  validates :main_filename, presence: true,
            if: -> { problem&.with_managers? && managers.attached? }

  def set_default
    self.compilation_type ||= 'self_contained'
    self.evaluation_type ||= 'wdiff'
    self.score_type ||= 'sum'
    self.time_limit ||= 1
    self.memory_limit ||= 512
  end



  def get_name_for_dir
    return name unless name.blank?
    return id.to_s
  end

  def live?
    self.problem.live_dataset&.id == self.id
  end

  def set_weight(weight_param)
    tc_ids = testcases.display_order.ids
    idx = 0
    weight_param.each do |wp|
      count = 1
      if wp.is_a? Array
        count = wp[1].to_i
        w = wp[0].to_i
      else
        w = wp.to_i
      end
      # take next count ids
      ids = tc_ids[idx...(idx+count)]
      idx += count
      Testcase.where(id: ids).update(weight: w)
    end
  end

  # set testcases parameters *field* by array
  def set_by_array(field, array, can_use_cms_mode: true)
    tc_ids = testcases.display_order.ids
    idx = 0
    group = 0
    cms_mode = array[0].is_a?(Array) && can_use_cms_mode
    array.each do |config|
      count = 1
      group += 1
      if config.is_a? Array
        value = config[0]
        count = config[1].to_i
      else
        value = config
      end
      # take next count ids
      ids = tc_ids[idx...(idx+count)]
      idx += count
      hash = {}
      hash[field] = value
      hash['group'] = group if cms_mode
      Testcase.where(id: ids).update(hash)
    end
  end

  def set_by_hash(options)
    set_by_array(:weight, options[:weight], can_use_cms_mode: false) if options.has_key? :weight
    set_by_array(:group, options[:group], can_use_cms_mode: false) if options.has_key? :group
    set_by_array(:group_name, options[:group_name], can_use_cms_mode: false) if options.has_key? :group_name
  end

  # Drop workers' cached copy of this dataset so they re-download testcases
  # and managers. (Was `dataset_id: @dataset` — a nil ivar inside the model —
  # which matched nothing, so callers silently invalidated nothing.)
  def invalidate_worker
    WorkerDataset.where(dataset_id: id).delete_all
  end

  # set main_filename if null and should be set
  # also set to null of current value is invalid
  # this DOES not save, as it is set as called back on before_save
  # return true if change were made (which means that the record should be save)
  def update_main_filename
    if managers.attached?
      manager_filenames = self.managers.map { |x| x.filename.to_s }
      unless manager_filenames.include? main_filename
        self.main_filename = manager_filenames[0]
        return true
      end
    else
      unless self.main_filename.nil?
        self.main_filename = nil
        return true
      end
    end
    return false
  end

  protected
end
