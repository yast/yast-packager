#!/usr/bin/env rspec

require_relative "test_helper"
require "packager/clients/pkg_finish"
require "packages/repository"
require "uri"
require "tmpdir"
require "fileutils"

describe Yast::PkgFinishClient do
  Yast.import "Pkg"
  Yast.import "Installation"
  Yast.import "WFM"
  Yast.import "ProductFeatures"

  FAILED_PKGS_PATH = "/var/lib/YaST2/failed_packages"

  subject(:client) { Yast::PkgFinishClient.new }
  let(:repositories) { [] }
  let(:minimalistic_configuration) { false }

  before do
    allow(Yast::WFM).to receive(:Args).and_return(args)
    allow(::Packages::Repository).to receive(:enabled).and_return(repositories)
    allow(Yast::ProductFeatures).to receive(:GetBooleanFeature).with("software", "minimalistic_configuration")
      .and_return(minimalistic_configuration)
  end

  describe "Info" do
    let(:args) { ["Info"] }

    it "returns a hash describing the client" do
      allow(client).to receive(:_).and_return("title")
      expect(client.run).to eq({
          "steps" => 1,
          "title" => "title",
          "when" => [:installation, :update, :autoinst]})
    end
  end

  describe "Write" do
    let(:args) { ["Write"] }
    let(:destdir) { "/mnt" }
    let(:update) { false }
    let(:zypp_conf) { double("zypp_conf", load: true, save: true, :set_minimalistic! => true) }

    before do
      allow(Yast::Installation).to receive(:destdir).and_return(destdir)
      allow(Yast::Mode).to receive(:update).and_return(update)
      allow(Yast::Stage).to receive(:initial).and_return(true)
      allow(Yast::Pkg).to receive(:SourceLoad)
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(FAILED_PKGS_PATH).and_return(false)
      allow(Yast::Packager::CFA::ZyppConf)
        .to receive(:new).and_return(zypp_conf)
    end

    it "saves repository information" do
      expect(Yast::Pkg).to receive(:SourceLoad)
      expect(Yast::Pkg).to receive(:SourceSaveAll)
      expect(Yast::Pkg).to receive(:TargetFinish)
      expect(Yast::Pkg).to receive(:SourceCacheCopyTo).with(destdir)
      allow(Yast::WFM).to receive(:Execute)
      expect(client.run).to be_nil
    end

    it "copies failed_packages list under destination dir" do
      stub_const("Yast::Pkg", double("pkg").as_null_object)
      expect(File).to receive(:exist?).with(FAILED_PKGS_PATH)
        .and_return(true)
      expect(FileUtils).to receive(:cp)
        .with(FAILED_PKGS_PATH, "#{destdir}#{FAILED_PKGS_PATH}", preserve: true)
      client.run
    end

    context "given some local repository" do
      let(:repositories) { [local_repo, remote_repo] }

      let(:local_repo) do
        Packages::Repository.new(repo_id: 1, name: "SLE-12-SP2-0", enabled: true,
          url: URI("cd://dev/sr0"), autorefresh: false)
      end

      let(:remote_repo) do
        Packages::Repository.new(repo_id: 2, name: "SLE-12-SP2-Pool", enabled: true,
          url: URI("http://download.suse.com/sle-12-sp2"), autorefresh: true)
      end

      let(:sles_product) do
        Packages::Product.new(name: "SLES", version: "12.2",
          arch: "x86_64", category: "base", status: :available, vendor: "SUSE")
      end

      let(:sles_ha_product) do
        Packages::Product.new(name: "SLESHA", version: "12.2",
          arch: "x86_64", category: "base", status: :available, vendor: "SUSE")
      end

      before do
        allow(local_repo).to receive(:products).and_return([sles_product.clone])
      end

      context "if their products are available through other repos" do
        before do
          allow(remote_repo).to receive(:products).and_return([sles_product.clone])
        end

        it "disables the local repository" do
          expect(local_repo).to receive(:disable!)
          client.run
        end
      end

      context "if their products are not available through other repos" do
        before do
          allow(remote_repo).to receive(:products).and_return([sles_ha_product])
        end

        it "does not disable the local repository" do
          expect(local_repo).to_not receive(:disable!)
          client.run
        end
      end

      context "if does not contain any product" do
        before do
          allow(local_repo).to receive(:products).and_return([])
        end

        it "does not disable the local repository" do
          allow(client.log).to receive(:info).and_call_original
          expect(local_repo).to_not receive(:disable!)
          expect(client.log).to receive(:info).with(/ignored/)
          client.run
        end
      end
    end

    context "during update" do
      let(:update) { true }
      let(:tmpdir) do
        dir = Dir.mktmpdir
        FileUtils.remove_entry(dir)
        Pathname(dir)
      end
      let(:repos_dir) { tmpdir.join("repos.d") }
      let(:vardir) { tmpdir.join("var") }

      before do
        allow(Yast::Directory).to receive(:vardir).and_return(vardir.to_s)
        allow(Yast::WFM).to receive(:call)
        stub_const("Yast::PkgFinishClient::REPOS_DIR", repos_dir.to_s)
        stub_const("Yast::Pkg", double("pkg").as_null_object)
      end

      context "when repos.d exists and contains files" do
        before do
          FileUtils.mkdir_p(repos_dir)                 # Create repos.d
          FileUtils.touch(repos_dir.join("yast.repo")) # Add a 'repo'
        end

        it "saves the repositories at /etc/repos.d" do
          client.run

          # The backup exists
          file = Pathname.glob(vardir.join("*")).first
          expect(file.exist?).to eq(true)

          # The old repos are gone
          expect(Pathname.glob(repos_dir.join("*"))).to be_empty
        end

        it "logs an error if compression fails" do
          allow(Yast::SCR).to receive(:Execute).and_call_original
          expect(Yast::SCR).to receive(:Execute).
            with(Yast::Path.new(".target.bash_output"), /tar/).
            and_return("exit" => -1)
          expect(client.log).to receive(:error)
            .with(/Unable to backup/)
          client.run
        end
      end

      context "when repos.d does not exist" do
        it "logs an error" do
          expect(client.log).to receive(:error).with(/#{repos_dir} doesn't exist/)
          client.run
        end
      end

      context "when repos.d is empty" do
        before do
          FileUtils.mkdir_p(repos_dir) # Create repos.d
        end

        it "logs a warning" do
          expect(client.log).to receive(:warn).with(/no repos in #{repos_dir}/)
          client.run
        end
      end

      it "calls inst_extrasources client" do
        expect(Yast::WFM).to receive(:call).with("inst_extrasources")
        client.run
      end

      context "if libzypp's minimalistic configuration is enabled" do
        let(:minimalistic_configuration) { true }

        it "sets libzypp configuration to be minimalistic" do
          expect(zypp_conf).to receive(:set_minimalistic!)
          client.run
        end
      end

      it "does not set libzypp configuration to be minimalistic" do
        expect(zypp_conf).to_not receive(:set_minimalistic!)
        client.run
      end
    end
  end
end
