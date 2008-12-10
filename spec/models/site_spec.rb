
require File.dirname(__FILE__) + '/../spec_helper'

describe Site do

  before(:each) do
    start_time = Time.local(2008,5,10,9,00).gmtime
    @site = Site.new({:name => 'Test site',
                       :started => true,
                       :start_time => start_time })
    @site.stub!(:start_time).
      any_number_of_times.
      and_return(start_time)
    @site.stub!(:started).any_number_of_times.and_return(true)
  end
  
  it "should report that the contest is not finished when the contest time limit is not set" do
    Configuration.should_receive(:[]).with('contest.time_limit').
      and_return('unlimit')
    @site.finished?.should == false
  end

  it "should report that the contest is finished when the contest is over" do
    Configuration.should_receive(:[]).with('contest.time_limit').
    and_return('5:00')
    Time.stub!(:now).
      and_return(Time.local(2008,5,10,14,01).gmtime)
    @site.finished?.should == true end

  it "should report if the contest is finished correctly, when the contest is over, and the contest time contains some minutes" do
    Configuration.should_receive(:[]).twice.with('contest.time_limit').
      and_return('5:15')
    Time.stub!(:now).
      and_return(Time.local(2008,5,10,14,14))
    @site.finished?.should == false
    Time.stub!(:now).
      and_return(Time.local(2008,5,10,14,16))
    @site.finished?.should == true
  end

  it "should report that the contest is not finished, when the time is exactly at the finish time" do
    Configuration.should_receive(:[]).with('contest.time_limit').
      and_return('5:00')
    Time.stub!(:now).and_return(Time.local(2008,5,10,14,00))
    @site.finished?.should == false
  end

end
