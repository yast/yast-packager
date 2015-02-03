#! /usr/bin/env rspec

require_relative "./test_helper"

Yast.import "SourceDialogs"

describe Yast::SourceDialogs do
  describe "#valid_scheme?" do

    it "returns true for 'https://' URL" do
      expect(Yast::SourceDialogs.valid_scheme?("https://")).to eq(true)
    end

    it "returns false for empty URL and reports error" do
      expect(Yast::Report).to receive(:Error)
      expect(Yast::SourceDialogs.valid_scheme?("")).to eq(false)
    end

    it "returns false for 'foo://' URL and reports error" do
      expect(Yast::Report).to receive(:Error)
      expect(Yast::SourceDialogs.valid_scheme?("foo://")).to eq(false)
    end

    it "returns false for 'foo' URL and reports error" do
      expect(Yast::Report).to receive(:Error)
      expect(Yast::SourceDialogs.valid_scheme?("foo")).to eq(false)
    end
  end
end
