
require File.dirname(__FILE__) + '/../spec_helper'

describe GraderMessage do

  def add_submission_with_id(id)
    submission = stub(Submission, :id => id)
    GraderMessage.create_grade_submission("exam",submission)
  end

  before(:each) do 
    GraderMessage.destroy_all
  end

  it "should return nil when there is no messages to me" do
    GraderMessage.create_message(1,0)
    GraderMessage.get_message_for(2).should == nil
  end
  
  it "should return a messages directed to me" do
    GraderMessage.create_message(1,0)
    GraderMessage.get_message_for(2).should == nil
  end
  
  it "should return a messages directed to me, in order of creation" do
    msg1 = GraderMessage.create_message(1,0)
    msg2 = GraderMessage.create_message(2,2)
    msg3 = GraderMessage.create_message(1,2)
    GraderMessage.get_message_for(1).id.should == msg1.id
    GraderMessage.get_message_for(1).id.should == msg3.id
  end
  
  it "should not return a messages directed to me if the command is not on my list of accepting commands" do
    msg1 = GraderMessage.create_message(1,GraderMessage::GRADE_SUBMISSION)
    msg2 = GraderMessage.create_message(1,GraderMessage::STOP)
    GraderMessage.get_message_for(1,[GraderMessage::GRADE_TEST_REQUEST]).should == nil
  end
  
  it "should return a messages directed to me if the command is on my list of accepting commands" do
    msg1 = GraderMessage.create_message(1,0)
    msg2 = GraderMessage.create_message(1,2)
    msg3 = GraderMessage.create_message(2,2) 
    GraderMessage.get_message_for(1,[2]).id.should == msg2.id
    GraderMessage.get_message_for(1,[2]).should == nil
  end
  
  it "should return a message directed to anyone when I'm requesting" do
    msg1 = GraderMessage.create_message(:any,0)
    GraderMessage.get_message_for(1).id.should == msg1.id
  end

  it "should return a messages directed to anyone only if the command is on my list of accepting commands" do
    msg1 = GraderMessage.create_message(:any,0)
    GraderMessage.get_message_for(1,[1]).should == nil
    msg2 = GraderMessage.create_message(:any,1)
    GraderMessage.get_message_for(1,[1]).id.should == msg2.id
  end

  it "should return messages directed to anyone to many graders in order of requests" do
    msg1 = GraderMessage.create_message(:any,0)
    msg2 = GraderMessage.create_message(:any,2)
    msg3 = GraderMessage.create_message(:any,2) 
    GraderMessage.get_message_for(1).id.should == msg1.id
    GraderMessage.get_message_for(2).id.should == msg2.id
    GraderMessage.get_message_for(1).id.should == msg3.id
  end
  
  it "should return messages directed to anyone to graders accepting those commands in order of requests" do
    msg1 = GraderMessage.create_message(:any,0)
    msg2 = GraderMessage.create_message(:any,1)
    msg3 = GraderMessage.create_message(:any,2) 
    msg4 = GraderMessage.create_message(:any,2) 
    msg5 = GraderMessage.create_message(:any,3) 
    GraderMessage.get_message_for(1).id.should == msg1.id
    GraderMessage.get_message_for(2,[2]).id.should == msg3.id
    GraderMessage.get_message_for(1,[3]).id.should == msg5.id
    GraderMessage.get_message_for(2).id.should == msg2.id
    GraderMessage.get_message_for(1).id.should == msg4.id
 end

  it "should get all messages dispatched when there are many concurrent processes" do
    n = 100
    msg = []
    n.times do |i|
      msg << GraderMessage.create_message(:any,i)
    end

    #puts "#{n} messages created"

    t = 10  # use 10 threads
    ths = []
    t.times do |i|
      fork do
        #puts "I'm the #{i+1}-th process."
        begin
          m = GraderMessage.get_message_for(i)
          #puts "#{i+1} got #{m.id}" if m
          sleep 0.1
        end while m!=nil
        #puts "The #{i+1}-th process terminated."
        exit 0
      end
    end

    t.times do
      Process.wait
    end

    # for some reason the connection is lost at this point.
    GraderMessage.connection.reconnect!

    # check that all messages have been processed
    GraderMessage.find(:all) do |msg|
      msg.taken_grader_process.should != nil
    end

  end
  
end
