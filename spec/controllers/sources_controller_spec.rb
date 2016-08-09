require 'spec_helper'

describe SourcesController do

  describe "GET 'direct_edit'" do
    it "returns http success" do
      get 'direct_edit'
      response.should be_success
    end
  end

end
