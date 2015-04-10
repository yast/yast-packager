#! /usr/bin/env rspec

require_relative "./test_helper"

Yast.import "AddOnProduct"

describe Yast::AddOnProduct do
  describe "#renamed?" do
    it "returns true if product has been renamed" do
      expect(Yast::AddOnProduct.renamed?("SUSE_SLES", "SLES")).to eq(true)
    end

    it "returns false if the product rename is not known" do
      expect(Yast::AddOnProduct.renamed?("foo", "bar")).to eq(false)
    end
  end

  describe "#add_rename" do
    it "adds a new product rename" do
      expect(Yast::AddOnProduct.renamed?("FOO", "BAR")).to eq(false)
      Yast::AddOnProduct.add_rename("FOO", "BAR")
      expect(Yast::AddOnProduct.renamed?("FOO", "BAR")).to eq(true)
    end

    it "keeps the existing renames" do
      # add new rename
      Yast::AddOnProduct.add_rename("SUSE_SLES", "SLES_NEW")
      # check the new rename
      expect(Yast::AddOnProduct.renamed?("SUSE_SLES", "SLES_NEW")).to eq(true)
      # check the already known rename
      expect(Yast::AddOnProduct.renamed?("SUSE_SLES", "SLES")).to eq(true)
    end
  end

  describe "#RegisterAddOnProduct" do
    let(:repo_id) { 42 }

    context "the add-on requires registration" do
      before do
        expect(Yast::WorkflowManager).to receive(:WorkflowRequiresRegistration)
          .with(repo_id).and_return(true)
      end

      context "the registration client is installed" do
        before do
          expect(Yast::WFM).to receive(:ClientExists).with("inst_scc").and_return(true)
        end

        it "starts the registration client" do
          expect(Yast::WFM).to receive(:CallFunction).with("inst_scc", ["register_media_addon", repo_id])

          Yast::AddOnProduct.RegisterAddOnProduct(repo_id)
        end
      end

      context "the registration client is not installed" do
        before do
          expect(Yast::WFM).to receive(:ClientExists).with("inst_scc").and_return(false)
        end

        it "asks to install yast2-registration and starts registration if installed" do
          expect(Yast::Package).to receive(:Install).with("yast2-registration").and_return(true)
          expect(Yast::WFM).to receive(:CallFunction).with("inst_scc", ["register_media_addon", repo_id])

          Yast::AddOnProduct.RegisterAddOnProduct(repo_id)
        end

        it "asks to install yast2-registration and skips registration if not installed" do
          expect(Yast::Package).to receive(:Install).with("yast2-registration").and_return(false)
          expect(Yast::WFM).to_not receive(:CallFunction).with("inst_scc", ["register_media_addon", repo_id])

          Yast::AddOnProduct.RegisterAddOnProduct(repo_id)
        end
      end
    end

    context "the add-on does not require registration" do
      before do
        expect(Yast::WorkflowManager).to receive(:WorkflowRequiresRegistration)
          .with(repo_id).and_return(false)
      end

      it "add-on registration is skipped" do
        expect(Yast::WFM).to_not receive(:CallFunction).with("inst_scc", ["register_media_addon", repo_id])

        Yast::AddOnProduct.RegisterAddOnProduct(repo_id)
      end
    end
  end
end
