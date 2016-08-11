#! /usr/bin/env rspec

require_relative "./test_helper"

Yast.import "AddOnProduct"

describe Yast::AddOnProduct do
  subject { Yast::AddOnProduct }

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
        allow(Yast::WorkflowManager).to receive(:WorkflowRequiresRegistration)
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
        allow(Yast::WorkflowManager).to receive(:WorkflowRequiresRegistration)
          .with(repo_id).and_return(false)
      end

      it "add-on registration is skipped" do
        expect(Yast::WFM).to_not receive(:CallFunction).with("inst_scc", ["register_media_addon", repo_id])

        Yast::AddOnProduct.RegisterAddOnProduct(repo_id)
      end
    end
  end

  describe "#AddPreselectedAddOnProducts" do
    BASE_URL = "cd:/?devices=/dev/disk/by-id/ata-QEMU_DVD-ROM_QM00001".freeze
    ADDON_REPO = {
      "path" => "/foo", "priority" => 50, "url" => "cd:/?alias=Foo"
    }.freeze

    let(:repo) { ADDON_REPO }
    let(:filelist) do
      [{ "file" => "/add_on_products.xml", "type" => "xml" }]
    end

    before do
      subject.SetBaseProductURL(BASE_URL)
      allow(subject).to receive(:ParseXMLBasedAddOnProductsFile).and_return([repo])
      subject.add_on_products = []
    end

    context "when filelist is empty" do
      let(:filelist) { [] }

      it "just returns true" do
        expect(subject).to_not receive(:GetBaseProductURL)
        subject.AddPreselectedAddOnProducts(filelist)
      end
    end

    context "when filelist is nil" do
      let(:filelist) { nil }

      it "just returns true" do
        expect(subject).to_not receive(:GetBaseProductURL)
        subject.AddPreselectedAddOnProducts(filelist)
      end
    end

    context "when filelist contains XML files" do
      it "parses the XML file" do
        expect(subject).to receive(:ParseXMLBasedAddOnProductsFile).and_return([])
        subject.AddPreselectedAddOnProducts(filelist)
      end
    end

    context "when filelist contains plain-text files" do
      let(:filelist) do
        [{ "file" => "/add_on_products.xml", "type" => "plain" }]
      end

      it "parses the plain file" do
        expect(subject).to receive(:ParsePlainAddOnProductsFile).and_return([])
        subject.AddPreselectedAddOnProducts(filelist)
      end
    end

    context "when filelist contains unsupported file types" do
      let(:filelist) do
        [{ "file" => "/add_on_products.xml", "type" => "unsupported" }]
      end

      it "logs the error" do
        expect(subject.log).to receive(:error).with(/Unsupported/)
        subject.AddPreselectedAddOnProducts(filelist)
      end
    end

    context "when the add-on is on a CD/DVD" do
      let(:repo_id) { 1 }
      let(:cd_url) { "cd:///?device=/dev/sr0" }

      before do
        allow(subject).to receive(:AcceptedLicenseAndInfoFile).and_return(true)
        allow(Yast::Pkg). to receive(:SourceProductData).with(repo_id)
        allow(subject).to receive(:InstallProductsFromRepository)
        allow(subject).to receive(:ReIntegrateFromScratch)
        allow(subject).to receive(:Integrate)
      end

      context "and no product name was given" do
        let(:repo) { ADDON_REPO }

        it "adds the repository" do
          expect(subject).to receive(:AddRepo).with(repo["url"], repo["path"], repo["priority"])
            .and_return(repo_id)
          subject.AddPreselectedAddOnProducts(filelist)
          expect(subject.add_on_products).to_not be_empty
        end

        it "asks for the CD/DVD if the repo could not be added" do
          allow(subject).to receive(:AddRepo).with(repo["url"], repo["path"], repo["priority"])
            .and_return(nil)
          expect(subject).to receive(:AskForCD).and_return(cd_url)
          expect(subject).to receive(:AddRepo).with(cd_url, repo["path"], repo["priority"])
            .and_return(repo_id)
          subject.AddPreselectedAddOnProducts(filelist)
          expect(subject.add_on_products).to_not be_empty
        end

        it "does not add the repository if user cancels the dialog" do
          allow(subject).to receive(:AddRepo).with(repo["url"], repo["path"], repo["priority"])
            .and_return(nil)
          allow(subject).to receive(:AskForCD).and_return(nil)

          subject.AddPreselectedAddOnProducts(filelist)
          expect(subject.add_on_products).to be_empty
        end
      end

      context "and a network scheme is used" do
        let(:repo) { ADDON_REPO.merge("url" => "http://example.net/repo") }

        it "checks whether the network is working" do
          allow(subject).to receive(:AddRepo).and_return(nil)
          expect(Yast::WFM).to receive(:CallFunction).with("inst_network_check", [])
          subject.AddPreselectedAddOnProducts(filelist)
        end
      end

      context "and a product name was given" do
        let(:repo) { ADDON_REPO.merge("name" => "Foo") }
        let(:matching_product) { { "label" => repo["name"] } }
        let(:other_product) { { "label" => "other" } }
        let(:other_repo_id) { 2 }

        context "and the product is found in the CD/DVD" do
          before do
            allow(Yast::Pkg).to receive(:SourceProductData).with(repo_id)
              .and_return(matching_product)
          end

          it "adds the product without asking" do
            expect(subject).to_not receive(:AskForCD)
            expect(subject).to receive(:AddRepo).with(repo["url"], anything, anything)
              .and_return(repo_id)
            subject.AddPreselectedAddOnProducts(filelist)
          end
        end

        context "and the product is not found in the CD/DVD" do
          before do
            allow(Yast::Pkg).to receive(:SourceProductData).with(repo_id)
              .and_return(matching_product)
            allow(Yast::Pkg).to receive(:SourceProductData).with(other_repo_id)
              .and_return(other_product)
          end

          it "does not add the repository if the user cancels the dialog" do
            allow(subject).to receive(:AddRepo).with(repo["url"], anything, anything)
              .and_return(other_repo_id)
            allow(subject).to receive(:AskForCD).and_return(nil)

            expect(Yast::Pkg).to receive(:SourceDelete).with(other_repo_id)
            expect(subject).to_not receive(:Integrate).with(other_repo_id)
            subject.AddPreselectedAddOnProducts(filelist)
            expect(subject.add_on_products).to be_empty
          end

          it "adds the product if the user points to a valid CD/DVD" do
            allow(subject).to receive(:AddRepo).with(repo["url"], repo["path"], repo["priority"])
              .and_return(other_repo_id)
            allow(subject).to receive(:AskForCD).and_return(cd_url)
            allow(subject).to receive(:AddRepo).with(cd_url, repo["path"], repo["priority"])
              .and_return(repo_id)

            expect(Yast::Pkg).to receive(:SourceDelete).with(other_repo_id)
            expect(Yast::Pkg).to_not receive(:SourceDelete).with(repo_id)
            expect(subject).to receive(:Integrate).with(repo_id)
            subject.AddPreselectedAddOnProducts(filelist)
            expect(subject.add_on_products).to_not be_empty
          end

          context "and check_name option is disabled" do
            let(:repo) { ADDON_REPO.merge("check_name" => true) }
            it "adds the repository" do
              allow(subject).to receive(:AddRepo).with(repo["url"], repo["path"], repo["priority"])
                .and_return(other_repo_id)

              subject.AddPreselectedAddOnProducts(filelist)
              expect(subject.add_on_products).to_not be_empty
            end
          end
        end
      end

      it "removes the product is the license is not accepted" do
        allow(subject).to receive(:AddRepo).with(repo["url"], repo["path"], repo["priority"])
          .and_return(repo_id)
        expect(subject).to receive(:AcceptedLicenseAndInfoFile).and_return(false)
        expect(Yast::Pkg).to receive(:SourceDelete).with(repo_id)
        subject.AddPreselectedAddOnProducts(filelist)
        expect(subject.add_on_products).to be_empty
      end
    end
  end
end
