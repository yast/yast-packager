#! /usr/bin/env rspec

require_relative "./test_helper"

Yast.import "AddOnProduct"

describe Yast::AddOnProduct do
  describe "#renamed?" do
    it "returns true if product has been renamed" do
      expect(Yast::AddOnProduct.renamed?("SUSE_SLES", "SLES")).to be_true
    end

    it "returns false if the product rename is not known" do
      expect(Yast::AddOnProduct.renamed?("foo", "bar")).to be_false
    end
  end

  describe "#add_rename" do
    it "adds a new product rename" do
      expect(Yast::AddOnProduct.renamed?("FOO", "BAR")).to be_false
      Yast::AddOnProduct.add_rename("FOO", "BAR")
      expect(Yast::AddOnProduct.renamed?("FOO", "BAR")).to be_true
    end

    it "keeps the existing renames" do
      # add new rename
      Yast::AddOnProduct.add_rename("SUSE_SLES", "SLES_NEW")
      # check the new rename
      expect(Yast::AddOnProduct.renamed?("SUSE_SLES", "SLES_NEW")).to be_true
      # check the already known rename
      expect(Yast::AddOnProduct.renamed?("SUSE_SLES", "SLES")).to be_true
    end
  end

end
