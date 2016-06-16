#!/usr/bin/env rspec

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
        .and_return(zypp_repo_url)
      allow(Yast::Linuxrc).to receive(:InstallInf).with("ssl_verify")
        .and_return(ssl_verify)
    end

    context "when ZyppRepURL is defined in install.inf" do
      it "returns ZyppRepoURL" do
        expect(inst_url.installInf2Url("")).to eq(zypp_repo_url)
      end
    end

    context "when ZyppRepoURL is not defined" do
      let(:zypp_repo_url) { nil }

      it "returns cd:///" do
        expect(inst_url.installInf2Url("")).to eq("cd:///")
      end
    end

    context "when an extra_dir is given" do
      it "adds the extra_dir to the path" do
        expect(inst_url.installInf2Url("extra")).to eq("#{zypp_repo_url}/extra")
      end
    end

    context "when ssl verification is disabled" do
      let(:ssl_verify) { "no" }

      context "and a HTTPS URL is given" do
        let(:zypp_repo_url) { "https://opensuse.org/repo" }

        it "adds ssl_verify=no to the URL" do
          expect(inst_url.installInf2Url("")).to eq("#{zypp_repo_url}?ssl_verify=no")
        end
      end

      context "and a HTTPS URL with extra query parameters is given" do
        let(:zypp_repo_url) { "https://opensuse.org/repo?key1=val1&key2=val2" }

        it "adds ssl_verify=no to the URL" do
          expect(inst_url.installInf2Url("")).to eq("#{zypp_repo_url}&ssl_verify=no")
        end
      end
    end
  end
end
