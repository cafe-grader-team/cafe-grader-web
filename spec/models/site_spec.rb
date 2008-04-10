
require File.dirname(__FILE__) + '/../spec_helper'

describe Site do

  before(:each) do
    start_time = Time.local(2008,5,10,9,00)
    @site = Site.new({:name => 'Test site',
                       :started => true,
                       :start_time => start_time })
  end
  
  it "should report that the contest is not finished when the contest time limit is not set" do
    Configuration.should_receive(:[]).with('contest.time_limit').
      and_return('unlimit')
    Time.should_not_receive(:now)
    @site.finished?.should == false
  end

  it "should report that the contest is finished when the contest is over" do
    Configuration.should_receive(:[]).with('contest.time_limit').
      and_return('5:00')
    Time.should_receive(:now).and_return(Time.local(2008,5,10,14,01))
    @site.finished?.should == true
  end

  it "should report if the contest is finished correctly, when the contest is over, and the contest time contains some minutes" do
    Configuration.should_receive(:[]).twice.with('contest.time_limit').
      and_return('5:15')
    Time.should_receive(:now).
      and_return(Time.local(2008,5,10,14,14),Time.local(2008,5,10,14,16))
    @site.finished?.should == false
    @site.finished?.should == true
  end

  it "should report that the contest is not finished, when the time is exactly at the finish time" do
    Configuration.should_receive(:[]).with('contest.time_limit').
      and_return('5:00')
    Time.should_receive(:now).and_return(Time.local(2008,5,10,14,00))
    @site.finished?.should == false
  end

end
