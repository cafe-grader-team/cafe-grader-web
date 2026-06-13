module ContestsHelper
  def mode_to_class(mode = GraderConfiguration.get('system.mode'))
    case mode
    when 'standard'
      'success'
    when 'contest'
      'warning'
    when 'indv-contest'
      'warning'
    when 'analysis'
      'info'
    else
      'danger'
    end
  end

  def mode_to_text(mode = GraderConfiguration.get('system.mode'))
    case mode
    when 'standard'
      'Normal'
    when 'contest'
      'Contest'
    when 'indv-contest'
      'Individual Contest'
    when 'analysis'
      'Analysis'
    else
      'Unrecognized!!!'
    end
  end
end
