class NameFormatValidator < ActiveModel::EachValidator
  # validates if name is a machine readable
  def validate_each(record, attribute, value)
    unless value =~ /\A[a-zA-Z\d\-\_\[\]()]+\z/
      record.errors.add(attribute, :name_format)
    end
  end
end
