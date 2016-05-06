#!/usr/bin/env rspec

require_relative "test_helper"
require_relative "../src/clients/pkg_finish"

describe Yast::PkgFinishClient do
  Yast.import "Pkg"
  Yast.import "Installation"
  Yast.import "WFM"

  subject(:client) { Yast::PkgFinishClient.new }

  before do
    allow(Yast::WFM).to receive(:Args) { |n| n.nil? ? args : args[n] }
  end

  describe "Info" do
    let(:args) { ["Info"] }

    it "returns a hash describing the client" do
      allow(client).to receive(:_).and_return("title")
      expect(client.main).to eq({
          "steps" => 1,
          "title" => "title",
          "when" => [:installation, :update, :autoinst]})
    end
  end

  describe "Write" do
    let(:args) { ["Write"] }
    let(:destdir) { "/mnt" }
    let(:update) { false }

    before do
      allow(Yast::Installation).to receive(:destdir).and_return(destdir)
      allow(Yast::Mode).to receive(:update).and_return(update)
      allow(Yast::Stage).to receive(:initial).and_return(true)
    end

    context "during installation" do
      let(:update) { false }

      it "saves repository information" do
        expect(Yast::Pkg).to receive(:SourceSaveAll)
        expect(Yast::Pkg).to receive(:TargetFinish)
        expect(Yast::Pkg).to receive(:SourceCacheCopyTo).with(destdir)
        allow(Yast::WFM).to receive(:Execute)
        expect(client.main).to be_nil
      end

      it "copies failed_packages list under destination dir" do
        stub_const("Yast::Pkg", double("pkg").as_null_object)
        expect(Yast::WFM).to receive(:Execute).
          with(Yast::Path.new(".local.bash"),
            "test -f /var/lib/YaST2/failed_packages && "\
            "/bin/cp -a /var/lib/YaST2/failed_packages '#{destdir}/var/lib/YaST2/failed_packages'")
        client.main
      end
    end

    context "during update" do
      let(:update) { true }
      let(:tmpdir) { Pathname.new(__FILE__).dirname.join("tmp") }
      let(:repos_dir) { tmpdir.join("repos.d") }
      let(:vardir) { tmpdir.join("var") }

      before do
        allow(Yast::Directory).to receive(:vardir).and_return(vardir.to_s)
        allow(Yast::WFM).to receive(:call)
        stub_const("Yast::PkgFinishClient::REPOS_DIR", repos_dir.to_s)
        stub_const("Yast::Pkg", double("pkg").as_null_object)
      end

      around do |example|
        FileUtils.rm_rf(tmpdir)
        example.run
        FileUtils.rm_rf(tmpdir)
      end

      context "when repos.d exists and contains files" do
        before do
          FileUtils.mkdir_p(repos_dir)                 # Create repos.d
          FileUtils.touch(repos_dir.join("yast.repo")) # Add a 'repo'
        end

        it "saves the repositories at /etc/repos.d" do
          client.main

          # The backup exists
          file = Pathname.glob(vardir.join("*")).first
          expect(file.exist?).to eq(true)

          # The old repos are gone
          expect(Pathname.glob(repos_dir.join("*"))).to be_empty
        end

        it "logs an error if compression fails" do
          allow(Yast::SCR).to receive(:Execute).and_call_original
          allow(Yast::SCR).to receive(:Execute).
            with(Yast::Path.new(".target.bash_output"), /tar/).
            and_return("exit" => -1)
          expect(Yast::Builtins).to receive(:y2error).
            with(/Unable to backup/, /tar/, {"exit" => -1})
          client.main
        end
      end

      context "when repos.d does not exist" do
        it "logs an error" do
          expect(Yast::Builtins).to receive(:y2error).with(/doesn't exist/, repos_dir.to_s)
          client.main
        end
      end

      context "when repos.d is empty" do
        before do
          FileUtils.mkdir_p(repos_dir) # Create repos.d
        end

        it "logs a warning" do
          expect(Yast::Builtins).to receive(:y2warning).with(/no repos/, repos_dir.to_s)
          client.main
        end
      end

      it "calls inst_extrasources client" do
        expect(Yast::WFM).to receive(:call).with("inst_extrasources")
        client.main
      end
    end
  end
end
