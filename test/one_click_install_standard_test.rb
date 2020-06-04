#!/usr/bin/env rspec

require_relative "test_helper"

require "tempfile"

Yast.import "OneClickInstallStandard"

# note partially covered also by test/lib/clients/inst_productsources_test.rb
describe "Yast::OneClickInstallStandard" do
  subject { Yast::OneClickInstallStandard }

  let(:file) do
    File.expand_path("data/_openSUSE_Leap_15.0_Default.xml", __dir__)
  end

  describe "#GetRepositoriesFromXML" do
    it "returns empty array if file does not exist" do
      expect(subject.GetRepositoriesFromXML("/dev/null/non-existing")).to eq []
    end

    it "returns empty array if file is empty" do
      Tempfile.create do |f|
        f.write("\n")
        f.close
        expect(subject.GetRepositoriesFromXML(f.path)).to eq []
      end
    end

    it "returns array of repository hashes" do
      expect(subject.GetRepositoriesFromXML(file)).to have_attributes(size: 8, class: ::Array)
      expect(subject.GetRepositoriesFromXML(file)).to be_all(::Hash)
    end

    it "fills distversion from group to repository hash" do
      expect(subject.GetRepositoriesFromXML(file).first).to(
        include("distversion" => "openSUSE Main Repository")
      )
    end

    it "fills url to repository hash" do
      expect(subject.GetRepositoriesFromXML(file).first).to(
        include("url" => "http://download.opensuse.org/distribution/leap/15.0/repo/oss/")
      )
    end

    it "fills format to repository hash" do
      expect(subject.GetRepositoriesFromXML(file).first).to(
        include("format" => "yast")
      )
    end

    it "fills alias to repository hash" do
      expect(subject.GetRepositoriesFromXML(file).first).to(
        include("alias" => "main")
      )
    end

    it "fills recommended to repository hash" do
      expect(subject.GetRepositoriesFromXML(file).first).to(
        include("recommended" => true)
      )
    end

    it "fills localized name to repository hash" do
      expect(subject.GetRepositoriesFromXML(file).first["localized_name"]).to(
        include("cs" => "Hlavní repozitář (OSS)")
      )
    end

    it "fills localized summary to repository hash" do
      expect(subject.GetRepositoriesFromXML(file).first["localized_summary"]).to(
        include("cs" => "Hlavní repozitář openSUSE Leap obsahující pouze Open source software")
      )
    end

    it "fills localized description to repository hash" do
      expect(subject.GetRepositoriesFromXML(file).first["localized_description"]).to(
        include("cs" => "Velký repozitář s Open source softwarem pro openSUSE Leap, který " \
          "vám zpřístupní tisíce balíčků spravovaných komunitou openSUSE.")
      )
    end

    it "fills name to repository hash" do
      expect(subject.GetRepositoriesFromXML(file).first).to(
        include("name" => "Main Repository (OSS)")
      )
    end

    it "fills summary to repository hash" do
      expect(subject.GetRepositoriesFromXML(file).first).to(
        include("summary" => "Main repository of openSUSE Leap including only Open Source Software")
      )
    end

    it "fills description to repository hash" do
      expect(subject.GetRepositoriesFromXML(file).first).to(
        include("description" => "The big Open Source Software (OSS) repository for openSUSE " \
          "Leap, giving you access to thousands of packages maintained by the openSUSE community.")
      )
    end
  end
end
