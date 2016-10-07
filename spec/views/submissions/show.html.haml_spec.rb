require 'spec_helper'

describe "submissions/show" do
  before(:each) do
    @submission = assign(:submission, stub_model(Submission))
  end

  it "renders attributes in <p>" do
    render
    # Run the generator again with the --webrat flag if you want to use webrat matchers
  end
end
