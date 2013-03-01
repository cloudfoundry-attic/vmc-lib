require "spec_helper"

describe CFoundry::V2::Organization do
  let(:client) { fake_client }

  describe 'summarization' do
    let(:myobject) { fake(:organization) }
    let(:summary_attributes) { { :name => "fizzbuzz" } }

    subject { myobject }

    it_behaves_like 'a summarizeable model'
  end
end
