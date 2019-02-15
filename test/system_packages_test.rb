#!/usr/bin/env rspec

require_relative "test_helper"
require "y2packager/system_packages"

describe Y2Packager::SystemPackages do
  Yast.import "Pkg"

  let(:repo_url) { "http://example.com/repo" }
  let(:repos) { [repo_url] }
  let(:source_id) { 42 }
  let(:system_package) { "system_package" }

  subject do
    Y2Packager::SystemPackages.new(repos)
  end

  describe "#packages" do
    it "returns the packages from the new repository" do
      allow(Yast::Pkg).to receive(:SourceGetCurrent).and_return([source_id])
      allow(Yast::Pkg).to receive(:SourceGeneralData).and_return("url" => repo_url)
      allow(Yast::Pkg).to receive(:GetSolverFlags)
      allow(Yast::Pkg).to receive(:PkgSolve)
      allow(Yast::Pkg).to receive(:SetSolverFlags)
      allow(Yast::Pkg).to receive(:ResolvableProperties).and_return(
        [
          "name"        => system_package,
          "source"      => source_id,
          "status"      => :selected,
          "transact_by" => :solver
        ]
      )

      expect(subject.packages).to eq(["system_package"])
    end

    it "returns empty list if repository list is empty" do
      expect(Y2Packager::SystemPackages.new([]).packages).to eq([])
    end
  end

  describe "#select" do
    it "selects the system packages to install" do
      allow(subject).to receive(:packages).and_return([system_package])
      expect(Yast::Pkg).to receive(:PkgInstall).with(system_package)

      subject.select
    end
  end

end
