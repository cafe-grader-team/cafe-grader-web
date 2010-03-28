
require File.dirname(__FILE__) + '/../spec_helper'

describe Configuration, "when using cache" do

  before(:each) do
    Configuration.cache = true
    @int_config = mock(Configuration,
                       :id => 1,
                       :key => 'mode',
                       :value_type => 'integer',
                       :value => '30')

    @string_config = mock(Configuration,
                          :id => 2,
                          :key => 'title',
                          :value_type => 'string',
                          :value => 'Hello')

    @boolean_config = mock(Configuration,
                           :id => 3,
                           :key => 'single_user_mode',
                           :value_type => 'boolean',
                           :value => 'true')
  end

  after(:each) do
    Configuration.cache = false
  end
  
  it "should retrieve int config" do
    Configuration.should_receive(:find).once.with(:all).
      and_return([@int_config, @string_config, @boolean_config])

    Configuration.clear
    val = Configuration.get('mode')
    val.should == 30
  end

  it "should retrieve boolean config" do
    Configuration.should_receive(:find).once.with(:all).
      and_return([@int_config, @string_config, @boolean_config])

    Configuration.clear
    val = Configuration.get('single_user_mode')
    val.should == true
  end

  it "should retrieve string config" do
    Configuration.should_receive(:find).once.with(:all).
      and_return([@int_config, @string_config, @boolean_config])

    Configuration.clear
    val = Configuration.get('title')
    val.should == "Hello"
  end

  it "should retrieve config with []" do
    Configuration.should_receive(:find).once.with(:all).
      and_return([@int_config, @string_config, @boolean_config])

    Configuration.clear
    val = Configuration['title']
    val.should == "Hello"
  end

  it "should read config table once" do
    Configuration.should_receive(:find).once.with(:all).
      and_return([@int_config, @string_config, @boolean_config])

    Configuration.clear
    val = Configuration.get('title')
    val.should == "Hello"
    val = Configuration.get('single_user_mode')
    val.should == true
    val = Configuration.get('mode')
    val.should == 30
  end

  it "should be able to reload config" do
    Configuration.should_receive(:find).twice.with(:all).
      and_return([@int_config, @string_config, @boolean_config],
                 [mock(Configuration,
                       :key => 'title', :value_type => 'string',
                       :value => 'Goodbye')])

    Configuration.clear
    val = Configuration.get('title')
    val.should == "Hello"
    Configuration.reload
    val = Configuration.get('title')
    val.should == "Goodbye"
  end

end
