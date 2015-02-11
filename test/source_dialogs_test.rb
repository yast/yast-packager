#! /usr/bin/env rspec

require_relative "./test_helper"

Yast.import "SourceDialogs"

describe Yast::SourceDialogs do
  subject { Yast::SourceDialogs }

  describe "#valid_scheme?" do

    it "returns true for 'https://' URL" do
      expect(subject.valid_scheme?("https://")).to eq(true)
    end

    it "returns false for empty URL and reports error" do
      expect(Yast::Report).to receive(:Error)
      expect(subject.valid_scheme?("")).to eq(false)
    end

    it "returns false for 'foo://' URL and reports error" do
      expect(Yast::Report).to receive(:Error)
      expect(subject.valid_scheme?("foo://")).to eq(false)
    end

    it "returns false for 'foo' URL and reports error" do
      expect(Yast::Report).to receive(:Error)
      expect(subject.valid_scheme?("foo")).to eq(false)
    end
  end

  describe "#PreprocessISOURL" do
    it "keeps additional URL parameter (workgroup)" do
      url = "iso:///?iso=openSUSE-12.2-DVD-i586.iso&workgroup=WORKGROUP&url=" \
        "smb://USERNAME:PASSWORD@192.168.1.66/install/images"
      converted = "smb://USERNAME:PASSWORD@192.168.1.66/install/images/" \
        "openSUSE-12.2-DVD-i586.iso?workgroup=WORKGROUP"

      expect(subject.PreprocessISOURL(url)).to eq(converted)
    end

    it "handles escaped URL parameter" do
      url = "iso:///?workgroup=WORKGROUP&iso=openSUSE-12.2-DVD-i586.iso&url=" \
        "smb%3A%2F%2FUSERNAME%3APASSWORD%40192.168.1.66%2Finstall%2Fimages"
      converted = "smb://USERNAME:PASSWORD@192.168.1.66/install/images/" \
        "openSUSE-12.2-DVD-i586.iso?workgroup=WORKGROUP"

      expect(subject.PreprocessISOURL(url)).to eq(converted)
    end
  end

  describe "#PostprocessISOURL" do
    it "keeps additional URL parameter (workgroup)" do
      converted = "smb://USERNAME:PASSWORD@192.168.1.66/install/images/" \
        "openSUSE-12.2-DVD-i586.iso?workgroup=WORKGROUP"
      url = "iso:///?workgroup=WORKGROUP&iso=openSUSE-12.2-DVD-i586.iso&url=" \
        "smb%3A%2F%2FUSERNAME%3APASSWORD%40192.168.1.66%2Finstall%2Fimages"

      expect(subject.PostprocessISOURL(converted)).to eq(url)
    end
  end
end
