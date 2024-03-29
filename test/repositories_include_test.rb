#! /usr/bin/env rspec

require_relative "./test_helper"

require "y2packager/dialogs/addon_selector"

# just a wrapper class for the repositories_include.rb
module Yast
  class RepositoryIncludeTesterClass < Module
    extend Yast::I18n

    def main
      Yast.include self, "packager/repositories_include.rb"
    end
  end
end

RepositoryIncludeTester = Yast::RepositoryIncludeTesterClass.new
RepositoryIncludeTester.main

describe "PackagerRepositoriesIncludeInclude" do
  describe ".autorefresh_for?" do
    # local protocols
    ["cd", "dvd", "dir", "hd", "iso", "file"].each do |protocol|
      url = "#{protocol}://foo/bar"
      it "returns false for local '#{url}' URL" do
        expect(RepositoryIncludeTester.autorefresh_for?(url)).to eq(false)
      end
    end

    # remote protocols
    # see https://github.com/openSUSE/libzypp/blob/master/zypp/Url.cc#L464
    ["http", "https", "nfs", "nfs4", "smb", "cifs", "ftp", "sftp", "tftp"].each do |protocol|
      url = "#{protocol}://foo/bar"
      it "returns true for remote '#{url}' URL" do
        expect(RepositoryIncludeTester.autorefresh_for?(url)).to eq(true)
      end
    end

    it "handles uppercase URLs correctly" do
      expect(RepositoryIncludeTester.autorefresh_for?("FTP://FOO/BAR")).to eq(true)
      expect(RepositoryIncludeTester.autorefresh_for?("DVD://FOO/BAR")).to eq(false)
    end
  end

  describe ".createSource" do
    let(:url) { "cd://" }
    let(:plaindir) { false }
    let(:download) { false }
    let(:preferred_name) { "" }
    let(:repo_id) { 42 }
    let(:products_reader) do
      instance_double(Y2Packager::ProductSpecReaders::Full, products: products)
    end
    let(:products) { [] }

    before do
      allow(Yast::Wizard).to receive(:CreateDialog)
      allow(Yast::Wizard).to receive(:CloseDialog)
      allow(Yast::Progress).to receive(:New)
      allow(Yast::Progress).to receive(:NextStep)
      allow(Yast::Progress).to receive(:NextStage)
      allow(Yast::Pkg).to receive(:ExpandedUrl).with(url).and_return(url)
      allow(Yast::Pkg).to receive(:ServiceProbe).with(url).and_return("NONE")
      allow(Yast::Pkg).to receive(:RepositoryAdd).and_return(repo_id)
      allow(Yast::Pkg).to receive(:SourceReleaseAll)
      allow(Yast::Pkg).to receive(:SourceRefreshNow)
      allow(Yast::Pkg).to receive(:SourceGetCurrent).and_return([])
      allow(Yast::Mode).to receive(:auto).and_return(false)
      allow(Y2Packager::ProductSpecReaders::Full).to receive(:new).and_return(products_reader)
      allow(Yast::Pkg).to receive(:RepositoryProbe).and_return("YUM")
      allow(Yast::AddOnProduct).to receive(:AcceptedLicenseAndInfoFile).and_return(true)
      allow(Yast::Pkg).to receive(:SourceGeneralData).with(repo_id).and_return({})
    end

    it "returns :again symbol when URL is empty" do
      ret = RepositoryIncludeTester.createSource("", plaindir, download, preferred_name)
      expect(ret).to eq(:again)
    end

    context "if the URL cannot be expanded (is invalid)" do
      before do
        # URL expansion returns nil (bsc#1059744)
        allow(Yast::Pkg).to receive(:ExpandedUrl).with(url).and_return(nil)
        allow(Yast::Report).to receive(:Error)
      end

      it "returns :again symbol" do
        ret = RepositoryIncludeTester.createSource(url, plaindir, download, preferred_name)
        expect(ret).to eq(:again)
      end

      it "displays an error popup" do
        expect(Yast::Report).to receive(:Error).with(/Invalid URL/)
        RepositoryIncludeTester.createSource(url, plaindir, download, preferred_name)
      end
    end

    context "when the repository cannot be created" do
      before do
        allow(Yast::Pkg).to receive(:RepositoryProbe).and_return(nil)
      end

      context "and the user accepts to edit the URL" do
        before do
          allow(Yast::Popup).to receive(:YesNo).and_return(true)
        end

        it "returns :again symbol" do
          result = RepositoryIncludeTester.createSource(url, plaindir, download, preferred_name)

          expect(result).to eq(:again)
        end
      end

      context "and the user does not accept to edit the URL" do
        before do
          allow(Yast::Popup).to receive(:YesNo).and_return(false)
        end

        it "returns :next symbol" do
          result = RepositoryIncludeTester.createSource(url, plaindir, download, preferred_name)

          expect(result).to eq(:next)
        end
      end
    end

    it "creates the repository" do
      repo_props = { "enabled"     => true,
                     "autorefresh" => false,
                     "raw_name"    => "Repository",
                     "prod_dir"    => "/",
                     "alias"       => "Repository",
                     "base_urls"   => ["cd://"],
                     "type"        => "YUM" }

      expect(Yast::Pkg).to receive(:RepositoryAdd).with(repo_props).and_return(repo_id)
      expect(Yast::Pkg).to_not receive(:SourceDelete)

      RepositoryIncludeTester.createSource(url, plaindir, download, preferred_name)
    end

    it "returns :ok symbol on success" do
      ret = RepositoryIncludeTester.createSource(url, plaindir, download, preferred_name)
      expect(ret).to eq(:ok)
    end

    it "removes the repository if license is rejected" do
      expect(Yast::AddOnProduct).to receive(:AcceptedLicenseAndInfoFile)
        .with(repo_id).and_return(false)
      expect(Yast::Pkg).to receive(:SourceDelete).with(repo_id)

      RepositoryIncludeTester.createSource(url, plaindir, download, preferred_name)
    end

    context "more products available on the medium" do
      let(:product1) do
        Y2Packager::RepoProductSpec.new(
          name: "sle-basesystem-module", media_name: "SLE-15-Module-Basesystem 15.0-0",
          dir: "/Basesystem"
        )
      end
      let(:product2) do
        Y2Packager::RepoProductSpec.new(
          name: "sle-legacy-module", media_name: "SLE-15-Module-Legacy 15.0-0",
          dir: "/Legacy"
        )
      end
      let(:products) { [product1, product2] }

      let(:selected_products) { [product1] }

      before do
        allow_any_instance_of(Y2Packager::Dialogs::AddonSelector).to receive(:run)
      end

      it "displays a dialog for selecting the products to use" do
        expect_any_instance_of(Y2Packager::Dialogs::AddonSelector).to receive(:run)
        RepositoryIncludeTester.createSource(url, plaindir, download, preferred_name)
      end

      it "adds only the repositories for the selected products" do
        expect_any_instance_of(Y2Packager::Dialogs::AddonSelector).to receive(:run)
          .and_return(:next)
        expect_any_instance_of(Y2Packager::Dialogs::AddonSelector).to receive(:selected_products)
          .and_return(selected_products)
        expect(Yast::Pkg).to receive(:RepositoryAdd)
          .with(hash_including("prod_dir" => product1.dir))
        RepositoryIncludeTester.createSource(url, plaindir, download, preferred_name)
      end

      it "returns :next if nothing is selected" do
        expect_any_instance_of(Y2Packager::Dialogs::AddonSelector).to receive(:selected_products)
          .and_return([])
        expect_any_instance_of(Y2Packager::Dialogs::AddonSelector).to receive(:run)
          .and_return(:next)
        ret = RepositoryIncludeTester.createSource(url, plaindir, download, preferred_name)
        expect(ret).to eq(:next)
      end

      it "returns :abort if product selection is aborted" do
        expect_any_instance_of(Y2Packager::Dialogs::AddonSelector).to receive(:run)
          .and_return(:abort)
        ret = RepositoryIncludeTester.createSource(url, plaindir, download, preferred_name)
        expect(ret).to eq(:abort)
      end
    end
  end

  # the "propose_name" method is private so use send() in the tests
  describe ".propose_name" do
    context "user provided a repository name" do
      it "returns the name provided by user" do
        preferred_name = "my repository"
        url = "http://example.com"
        ret = RepositoryIncludeTester.send(:propose_name, preferred_name, url)
        expect(ret).to eq(preferred_name)
      end
    end

    context "no user provided repository name" do
      it "returns a name created from the last URL path element" do
        preferred_name = ""
        url = "http://example.com/Leap-15.3"
        ret = RepositoryIncludeTester.send(:propose_name, preferred_name, url)
        expect(ret).to eq("Leap-15.3")
      end

      it "returns a name created from the last non-empty URL path element" do
        preferred_name = ""
        url = "http://example.com/Leap-15.3/"
        ret = RepositoryIncludeTester.send(:propose_name, preferred_name, url)
        expect(ret).to eq("Leap-15.3")
      end

      it "returns an unescaped URL path" do
        preferred_name = ""
        url = "http://example.com/Leap%2015.3/"
        ret = RepositoryIncludeTester.send(:propose_name, preferred_name, url)
        # %20 (0x20) => " "
        expect(ret).to eq("Leap 15.3")
      end

      it "returns the fallback name if the path is root" do
        preferred_name = ""
        url = "http://example.com/"
        ret = RepositoryIncludeTester.send(:propose_name, preferred_name, url)
        expect(ret).to eq(Yast::Packages.fallback_name)
      end

      it "returns the fallback name if the path is empty" do
        preferred_name = ""
        url = "http://example.com"
        ret = RepositoryIncludeTester.send(:propose_name, preferred_name, url)
        expect(ret).to eq(Yast::Packages.fallback_name)
      end
    end
  end
end
