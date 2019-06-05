#! /usr/bin/env rspec

require_relative "./test_helper"

require "y2packager/product_location"
require "y2packager/dialogs/addon_selector"

describe Y2Packager::Dialogs::AddonSelector do
  let(:media_products) do
    prods = [["SLE-15-Module-Basesystem 15.0-0", "/Basesystem"],
             ["SLE-15-Module-Legacy 15.0-0", "/Legacy"]]
    prods.map { |r| Y2Packager::ProductLocation.new(r[0], r[1]) }
  end

  subject { described_class.new(media_products) }

  describe "#help_text" do
    it "returns a String" do
      expect(subject.help_text).to be_a(String)
    end
  end

  describe "#abort_handler" do
    it "returns :abort" do
      allow(Yast::Stage).to receive(:initial).and_return(false)
      expect(subject.abort_handler).to eq(:abort)
    end

    context "in installation" do
      before do
        expect(Yast::Stage).to receive(:initial).and_return(true)
      end

      it "asks for confirmation" do
        expect(Yast::Popup).to receive(:ConfirmAbort).and_return(true)
        subject.abort_handler
      end

      it "returns :abort when confirmed" do
        expect(Yast::Popup).to receive(:ConfirmAbort).and_return(true)
        expect(subject.abort_handler).to eq(:abort)
      end

      it "returns nil when not confirmed" do
        expect(Yast::Popup).to receive(:ConfirmAbort).and_return(false)
        expect(subject.abort_handler).to be_nil
      end
    end
  end

  describe "#next_handler" do
    context "an addon is selected" do
      before do
        expect(Yast::UI).to receive(:QueryWidget).with(Id(:addon_repos), :SelectedItems)
          .and_return(["/Basesystem"])
      end

      it "returns :next if an addon is selected" do
        expect(subject.next_handler).to eq(:next)
      end

      it "does not display any popup" do
        expect(Yast::Popup).to_not receive(:anything)
        subject.next_handler
      end
    end

    context "no addon is selected" do
      before do
        expect(Yast::UI).to receive(:QueryWidget).with(Id(:addon_repos), :SelectedItems)
          .and_return([])
      end

      it "displays a popup asking for confirmation" do
        expect(Yast::Popup).to receive(:ContinueCancel).with(/no product/i)
        subject.next_handler
      end

      it "returns :next if the popup is confirmed" do
        expect(Yast::Popup).to receive(:ContinueCancel).with(/no product/i).and_return(true)
        expect(subject.next_handler).to eq(:next)
      end

      it "returns nil if the popup is not confirmed" do
        expect(Yast::Popup).to receive(:ContinueCancel).with(/no product/i).and_return(false)
        expect(subject.next_handler).to be_nil
      end
    end
  end
end
