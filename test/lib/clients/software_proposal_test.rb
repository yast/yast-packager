#!/usr/bin/env rspec

require_relative "../../test_helper"
require "packager/clients/software_proposal"

RSpec.shared_examples "Installation::ProposalClient" do
  describe "#description" do
    it "contains 3 string keys (or is nil or {})" do
      d = subject.description
      next if d.nil?
      expect(d).to be_a Hash
      expect(d["id"]).to be_a String
      expect(d["menu_title"]).to be_a String
      expect(d["rich_text_title"]).to be_a String
    end
  end

  describe "#ask_user" do
    it "returns a Hash with workflow_sequence" do
      r = subject.ask_user({})
      expect(r).to be_a Hash
      expect(r["workflow_sequence"]).to be_a Symbol
    end
  end
end

describe Yast::SoftwareProposalClient do
  before do
    allow(Yast::WFM).to receive(:CallFunction).and_return(:next)
  end

  include_examples "Installation::ProposalClient"

  describe "#ask_user(mediacheck)" do
    it "returns a Hash with workflow_sequence" do
      r = subject.ask_user({"chosen_id" => "mediacheck"})
      expect(r).to be_a Hash
      expect(r["workflow_sequence"]).to be_a Symbol
    end
  end
end
