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
  let(:ntp) { double("Yast::NtpClient", modified: false) }

  before do
    stub_const("Yast::NtpClient", ntp)
    allow(Yast::WFM).to receive(:CallFunction).and_return(:next)
  end

  include_examples "Installation::ProposalClient"

  describe "#ask_user(mediacheck)" do
    it "returns a Hash with workflow_sequence" do
      r = subject.ask_user("chosen_id" => "mediacheck")
      expect(r).to be_a Hash
      expect(r["workflow_sequence"]).to be_a Symbol
    end
  end

  describe "#make_proposal" do
    before do
      allow(Yast::Packages).to receive(:PackagesProposalChanged).and_return false
    end

    it "reports solver problems if partitioning unchanged" do
      expect(subject).to receive(:adjust_locales).and_return true
      expect(subject).to receive(:partitioning_changed?).and_return false
      expect(Yast::Packages).to receive(:Proposal).and_return(foo: :bar)
      expect(Yast::Packages).to receive(:solve_errors).and_return(1)

      expect(subject.make_proposal({})).to include("warning_level" => :blocker)
    end

    it "reports solver problems if partitioning changed" do
      expect(subject).to receive(:adjust_locales).and_return false
      expect(subject).to receive(:partitioning_changed?).and_return true
      expect(Yast::Packages).to receive(:Summary).and_return(foo: :bar)
      expect(Yast::Packages).to receive(:solve_errors).and_return(1)

      expect(subject.make_proposal({})).to include("warning_level" => :blocker)
    end

    context "AutoYaST mode" do
      before do
        allow(Yast::Mode).to receive(:auto).and_return(true)
        allow(subject).to receive(:adjust_locales).and_return false
        allow(subject).to receive(:partitioning_changed?).and_return true
        allow(Yast::Packages).to receive(:Summary).and_return(foo: :bar)
        allow(Yast::Packages).to receive(:solve_errors).and_return(0)
      end

      it "returns warning message if second stage is not possible" do
        # Note that translated errors can be frozen strings
        error_message1 = "first_error".freeze
        error_message2 = "second_error".freeze

        allow(Yast::Packages).to receive(:check_remote_installation_packages)
          .and_return(error_message1)

        allow(Yast::AutoinstData).to receive(:autoyast_second_stage_error)
          .and_return(error_message2)

        expect(subject.make_proposal({})["warning"]).to include(error_message2)
      end

      it "returns no warning if second stage is possible" do
        expect(Yast::AutoinstData).to receive(:autoyast_second_stage_error).and_return("")
        expect(subject.make_proposal({})).to_not have_key("warning")
      end
    end
  end
end
