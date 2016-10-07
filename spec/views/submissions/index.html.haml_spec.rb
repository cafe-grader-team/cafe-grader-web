require 'spec_helper'

describe "submissions/index" do
  before(:each) do
    assign(:submissions, [
      stub_model(Submission),
      stub_model(Submission)
    ])
  end

  it "renders a list of submissions" do
    render
    # Run the generator again with the --webrat flag if you want to use webrat matchers
  end
end
