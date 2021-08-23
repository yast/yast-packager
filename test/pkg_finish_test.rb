#!/usr/bin/env rspec

require_relative "test_helper"
require "packager/clients/pkg_finish"
require "y2packager/repository"
require "uri"
require "tmpdir"
require "fileutils"

describe Yast::PkgFinishClient do
  Yast.import "Pkg"
  Yast.import "Installation"
  Yast.import "WFM"
  Yast.import "ProductFeatures"

  FAILED_PKGS_PATH = "/var/lib/YaST2/failed_packages".freeze

  subject(:client) { Yast::PkgFinishClient.new }
  let(:repositories) { [] }
  let(:minimalistic_libzypp_config) { false }
  let(:second_stage_required) { false }

  before do
    allow(Yast::WFM).to receive(:Args).and_return(args)
    allow(::Y2Packager::Repository).to receive(:enabled).and_return(repositories)
    allow(::Y2Packager::Repository).to receive(:all).and_return(repositories)
    allow(Yast::ProductFeatures)
      .to receive(:GetBooleanFeature)
      .and_call_original
    allow(Yast::ProductFeatures).to receive(:GetBooleanFeature)
      .with("software", "minimalistic_libzypp_config")
      .and_return(minimalistic_libzypp_config)
    allow(Yast::InstFunctions).to receive(:second_stage_required?).and_return(second_stage_required)
  end

  describe "Info" do
    let(:args) { ["Info"] }

    it "returns a hash describing the client" do
      allow(client).to receive(:_).and_return("title")
      expect(client.run).to eq("steps" => 1,
                               "title" => "title",
                               "when"  => [:installation, :update, :autoinst])
    end
  end

  describe "Write" do
    let(:args) { ["Write"] }
    let(:destdir) { "/mnt" }
    let(:update) { false }
    let(:zypp_conf) { double("zypp_conf", load: true, save: true, set_minimalistic!: true) }
    let(:base_products) { [] }

    before do
      allow(Yast::Installation).to receive(:destdir).and_return(destdir)
      allow(Yast::Mode).to receive(:update).and_return(update)
      allow(Yast::Stage).to receive(:initial).and_return(true)
      allow(Yast::Pkg).to receive(:SourceLoad)
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(FAILED_PKGS_PATH).and_return(false)
      allow(Yast::Packager::CFA::ZyppConf)
        .to receive(:new).and_return(zypp_conf)
      allow(Y2Packager::Product).to receive(:available_base_products)
        .and_return(base_products)
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
      let(:repositories) { [local_repo, local_dvd_repo, remote_repo] }
      let(:base_products) { [sles_product, sled_product] }

      let(:local_repo) do
        Y2Packager::Repository.new(repo_id: 1, name: "SLE-12-SP2-0", enabled: true,
          url: URI("hd:/?devices=/dev/sda"), autorefresh: false, repo_alias: "SLE-12-SP2-0")
      end

      let(:remote_repo) do
        Y2Packager::Repository.new(repo_id: 2, name: "SLE-12-SP2-Pool", enabled: true,
          url: URI("http://download.suse.com/sle-12-sp2"), autorefresh: true,
          repo_alias: "SLE-12-SP2-Pool")
      end

      let(:local_dvd_repo) do
        Y2Packager::Repository.new(repo_id: 3, name: "SLE-15-SP1-0", enabled: true,
          url: URI("dvd:///?devices=/dev/sr0"), autorefresh: false, repo_alias: "SLE-15-SP1-0")
      end

      let(:sles_product) do
        instance_double(Y2Packager::Product, name: "SLES", installed?: true)
      end

      let(:sled_product) do
        instance_double(Y2Packager::Product, name: "SLED", installed?: false)
      end

      let(:sles_ha_product) do
        instance_double(Y2Packager::Product, name: "SLESHA")
      end

      before do
        allow(local_repo).to receive(:products).and_return([sles_product, sled_product])
        allow(local_dvd_repo).to receive(:products).and_return([sles_product, sled_product])
      end

      context "if installed base products are available through other repos" do
        before do
          allow(remote_repo).to receive(:products).and_return([sles_product])
        end

        context "second stage will not be called" do
          before do
            allow(Yast::Stage).to receive(:cont).and_return(false)
          end

          it "disables the local repository" do
            expect(local_repo).to receive(:disable!)
            client.run
          end
        end

        context "second stage will be called due AutoYaST" do
          let(:second_stage_required) { true }

          context "in first installation stage" do
            before do
              allow(Yast::Stage).to receive(:cont).and_return(false)
            end

            it "does not disable the local repository" do
              expect(local_repo).not_to receive(:disable!)
              client.run
            end
          end

          context "in second installation stage" do
            before do
              allow(Yast::Stage).to receive(:cont).and_return(true)
            end

            it "disables the local repository" do
              expect(local_repo).to receive(:disable!)
              client.run
            end
          end
        end
      end

      context "when control file option disable_media_repo is enabled" do
        before(:each) do
          allow(Yast::ProductFeatures)
            .to receive(:GetBooleanFeature)
            .with("software", "disable_media_repo")
            .and_return(true)
        end

        context "dvd repo is disabled even if base products aren't available using other repos" do
          before do
            allow(remote_repo).to receive(:products).and_return([])
          end

          it "disables the local repository if set in the control file" do
            expect(local_dvd_repo).to receive(:disable!)

            client.run
          end
        end

        context "if installed base products are not available through other repos" do
          before do
            allow(remote_repo).to receive(:products).and_return([])
          end

          it "disables local dvd repo" do
            expect(local_dvd_repo).to receive(:disable!)
            client.run
          end

          it "does not disable the local repository if not CD / DVD" do
            expect(local_repo).to_not receive(:disable!)
            client.run
          end
        end
      end

      context "if (non base) products are not available through other repos" do
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

    context "if the fallback repo was used" do
      let(:repositories) { [fallback_repo, remote_repo] }
      let(:base_products) { [sles_product, sled_product] }

      let(:fallback_repo) do
        Y2Packager::Repository.new(repo_id: 4, name: "dir-a1234", enabled: true,
          url: URI("dir:///var/lib/fallback-repo"), autorefresh: false, repo_alias: "dir-a1234")
      end

      let(:remote_repo) do
        Y2Packager::Repository.new(repo_id: 2, name: "SLE-12-SP2-Pool", enabled: true,
          url: URI("http://download.suse.com/sle-12-sp2"), autorefresh: true,
          repo_alias: "SLE-12-SP2-Pool")
      end

      let(:sles_product) do
        instance_double(Y2Packager::Product, name: "SLES", installed?: true)
      end

      let(:sled_product) do
        instance_double(Y2Packager::Product, name: "SLED", installed?: false)
      end

      before do
        allow(fallback_repo).to receive(:products).and_return([sles_product, sled_product])
        allow(remote_repo).to receive(:products).and_return(remote_products)
      end

      context "and the products are also defined in the remote repos" do
        let(:remote_products) { [sles_product, sled_product] }

        it "removes the fallback repository" do
          expect(Yast::Pkg).to receive(:SourceDelete).with fallback_repo.repo_id
          client.run
        end
      end

      context "and the products are defined only in the fallback repo" do
        let(:remote_products) { [] }

        it "removes the fallback repository" do
          expect(Yast::Pkg).to receive(:SourceDelete).with fallback_repo.repo_id
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
          expect(Yast::SCR).to receive(:Execute)
            .with(Yast::Path.new(".target.bash_output"), /tar/)
            .and_return("exit" => -1)
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
        let(:minimalistic_libzypp_config) { true }
        let(:destdir) { tmpdir }

        before do
          conf_file = File.join(tmpdir, Yast::Packager::CFA::ZyppConf::PATH)
          FileUtils.mkdir_p(File.dirname(conf_file))
          FileUtils.touch(conf_file)
        end

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
