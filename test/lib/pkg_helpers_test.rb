#! /usr/bin/env rspec

require_relative "../test_helper"
require "y2packager/pkg_helpers"

describe Y2Packager::PkgHelpers do
  subject(:pkg_helpers) { Y2Packager::PkgHelpers }

  let(:url) { "http://download.opensuse.org/$releasever/repo/oss/" }
  let(:expanded_url) { "http://download.opensuse.org/leap/15.0/repo/oss/" }

  before do
    allow(Yast::Pkg).to receive(:ExpandedUrl).with(url).and_return(expanded_url)
  end

  describe ".repository_probe" do
    it "calls RepositoryProbe using the expanded URL" do
      expect(Yast::Pkg).to receive(:RepositoryProbe).with(expanded_url, "/")
      subject.repository_probe(url, "/")
    end
  end

  describe ".expand_url" do
    it "expands the URL replacing variables" do
      expect(subject.expand_url(url)).to eq(expanded_url)
    end

    context "when an alias is given" do
      it "adds the alias to the URL" do
        expect(subject.expand_url(url, alias_name: "non-oss"))
          .to eq("#{expanded_url}?alias=non-oss")
      end
    end

    context "when a name is given" do
      it "handles name"
    end
  end

  describe ".source_create" do
    let(:src_id) { 1 }

    before do
      allow(Yast::Pkg).to receive(:SourceCreate).and_return(src_id)
    end

    it "registers the repository using the expanded URL" do
      expect(Yast::Pkg).to receive(:SourceCreate).with(expanded_url, "/")
        .and_return(src_id)
      subject.source_create(url, "/")
    end

    it "adjusts the repository URL to use the original one" do
      expect(Yast::Pkg).to receive(:SourceChangeUrl).with(src_id, url)
      subject.source_create(url, "/")
    end

    it "returns the repository id" do
      expect(subject.source_create(url, "/")).to eq(src_id)
    end

    context "when adding the repository fails with -1" do
      let(:src_id) { -1 }

      it "returns -1" do
        expect(subject.source_create(url, "/")).to eq(-1)
      end

      it "does not try to adjust the URL" do
        expect(Yast::Pkg).to_not receive(:SourceChangeUrl)
        subject.source_create(url, "/")
      end
    end

    context "when adding the repository fails with nil" do
      let(:src_id) { nil }

      it "returns nil" do
        expect(subject.source_create(url, "/")).to be_nil
      end

      it "does not try to adjust the URL" do
        expect(Yast::Pkg).to_not receive(:SourceChangeUrl)
        subject.source_create(url, "/")
      end
    end
  end

  describe ".source_create_type" do
    let(:src_id) { 1 }

    before do
      allow(Yast::Pkg).to receive(:SourceCreateType).and_return(src_id)
    end

    it "registers the repository using the expanded URL" do
      expect(Yast::Pkg).to receive(:SourceCreateType).with(expanded_url, "/", "Plaindir")
        .and_return(src_id)
      subject.source_create_type(url, "/", "Plaindir")
    end

    it "adjusts the repository URL to use the original one" do
      expect(Yast::Pkg).to receive(:SourceChangeUrl).with(src_id, url)
      subject.source_create_type(url, "/", "Plaindir")
    end

    it "returns the repository id" do
      expect(subject.source_create_type(url, "/", "Plaindir")).to eq(src_id)
    end

    context "when adding the repository fails with -1" do
      let(:src_id) { -1 }

      it "returns -1" do
        expect(subject.source_create_type(url, "/", "Plaindir")).to eq(-1)
      end

      it "does not try to adjust the URL" do
        expect(Yast::Pkg).to_not receive(:SourceChangeUrl)
        subject.source_create_type(url, "/", "Plaindir")
      end
    end

    context "when adding the repository fails with nil" do
      let(:src_id) { nil }

      it "returns nil" do
        expect(subject.source_create_type(url, "/", "Plaindir")).to be_nil
      end

      it "does not try to adjust the URL" do
        expect(Yast::Pkg).to_not receive(:SourceChangeUrl)
        subject.source_create_type(url, "/", "Plaindir")
      end
    end
  end

  describe ".repository_add" do
    let(:repo) { { "name" => "Leap 15.0 (OSS)", "alias" => "oss", "base_urls" => [url] } }

    it "adds a repository using expanded URLs" do
      expect(Yast::Pkg).to receive(:RepositoryAdd)
        .with(repo.merge("base_urls" => [expanded_url]))
      subject.repository_add(repo)
    end
  end
end
