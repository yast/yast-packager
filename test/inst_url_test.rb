#!/usr/bin/rspec
require_relative "test_helper"

Yast.import "InstURL"
Yast.import "Linuxrc"

describe Yast::InstURL do
  subject(:inst_url)  { Yast::InstURL }
    
  describe "#installInf2Url" do
    let(:zypp_repo_url) { "http://opensuse.org/repo" }
    let(:ssl_verify) { "yes" }

    before do
      Yast::InstURL.main
      allow(Yast::Linuxrc).to receive(:InstallInf).with("ZyppRepoURL")
        .and_return(zypp_repo_url.clone)
      allow(Yast::Linuxrc).to receive(:InstallInf).with("ssl_verify")
        .and_return(ssl_verify)
    end

    it "returns ZyppRepoURL as defined in install.inf" do
      expect(inst_url.installInf2Url("")).to eq(zypp_repo_url)
    end

    context "when SSL verification is disabled" do
      let(:ssl_verify) { "no" }

      it "adds ssl_verify=no to the URL" do
        expect(inst_url.installInf2Url("")).to eq("#{zypp_repo_url}&ssl_verify=no")
      end
    end

    context "when extra_dir is specified" do
      it "ignores extra_dir" do # bug or feature?
        expect(inst_url.installInf2Url("extra")).to eq(zypp_repo_url)
      end
    end
  end

  describe "#is_network" do
    before do
      inst_url.main
      expect(inst_url).to receive(:installInf2Url).and_return(url)
    end

    context "when URL is of type cd://" do
      let(:url) { "cd:///?device=disk/by-id/ata-1" }

      it "returns false" do
        expect(inst_url.is_network).to eq(false)
      end
    end

    context "when URL is of type dvd://" do
      let(:url) { "dvd:///?device=disk/by-id/ata-1" }

      it "returns false" do
        expect(inst_url.is_network).to eq(false)
      end
    end

    context "when URL is of type hd://" do
      let(:url) { "hd:///?device=disk/by-id/ata-1" }

      it "returns false" do
        expect(inst_url.is_network).to eq(false)
      end
    end

    context "when URL is remote" do
      let(:url) { "http://download.opensuse.org/leap/DVD1" }

      it "returns true" do
        expect(inst_url.is_network).to eq(true)
      end
    end
  end
end
