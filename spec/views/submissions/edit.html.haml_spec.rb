require 'spec_helper'

describe "submissions/edit" do
  before(:each) do
    @submission = assign(:submission, stub_model(Submission))
  end

  it "renders the edit submission form" do
    render

    # Run the generator again with the --webrat flag if you want to use webrat matchers
    assert_select "form[action=?][method=?]", submission_path(@submission), "post" do
    end
  end
end
