require "spec_helper"

describe CFoundry::V2::Space do
  let(:client) { fake_client }

  describe 'summarization' do
    let(:myobject) { fake(:space) }
    let(:summary_attributes) { { :name => "fizzbuzz" } }

    subject { myobject }

    it_behaves_like 'a summarizeable model'
  end
end
