class Testcase < ApplicationRecord
  include Auditable
  audited only:   %i[num group group_name code_name weight
                     dataset_id problem_id input sol],
          redact: %i[input sol]

  belongs_to :problem, optional: true
  belongs_to :dataset

  has_many :evaluations
  # attr_accessible :group, :input, :num, :score, :sol

  has_one_attached :inp_file
  has_one_attached :ans_file

  scope :display_order, ->  { order(:group, :num) }

  # The first +limit+ bytes of an attached file (testcase input/answer or a
  # dataset data file) for the preview tier of the testcase page and the API
  # (issue #59: the page used to pull every file whole into one HTML page).
  # Returns { text:, byte_size:, truncated: }; limit 0 (or nil) means the
  # whole file; nothing attached gives an empty text. Only the requested
  # range is read from storage.
  def self.preview_of(attachment, limit)
    # has_one_attached proxy (blob nil when nothing is attached) or one
    # ActiveStorage::Attachment of a has_many_attached (data files)
    blob = attachment&.blob
    return { text: '', byte_size: 0, truncated: false } unless blob
    size = blob.byte_size
    limit = limit.to_i
    if limit <= 0 || size <= limit
      { text: blob.download.force_encoding('UTF-8').scrub, byte_size: size, truncated: false }
    else
      { text: blob.download_chunk(0...limit).force_encoding('UTF-8').scrub, byte_size: size, truncated: true }
    end
  end

  def get_name_for_dir
    return code_name unless code_name.blank?
    return num.to_s
  end

  # we should rename score field into weight
  def get_weight
    return score
  end
end
