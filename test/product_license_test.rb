#! /usr/bin/env rspec

require_relative "./test_helper"

Yast.import "ProductLicense"
Yast.import "UI"
Yast.import "Wizard"
Yast.import "Popup"
Yast.import "Stage"

describe Yast::ProductLicense do
  describe "#HandleLicenseDialogRet" do
    before(:each) do
      # By default, always exit the dialog with :accepted (all licenses accepted)
      allow(Yast::ProductLicense).to receive(:AllLicensesAccepted).and_return(true)

      # Make sure that Yast::UI.:UserInput always returns a symbol as the last item
      # to exit from the while loop, :back is a safe default
      allow(Yast::UI).to receive(:UserInput).and_return(:back)
    end

    licenses_ref = Yast::ArgRef.new({})

    context "while changing a license language" do
      it "updates the UI with new license translation" do
        expect(Yast::UI).to receive(:UserInput).and_return("license_language_pt_BR", :next)
        expect(Yast::ProductLicense).to receive(:UpdateLicenseContent).and_return(nil)
        expect(Yast::ProductLicense.HandleLicenseDialogRet(licenses_ref, "base_prod", "abort")).to eq(:accepted)
      end
    end

    context "while adjusting EULA agreement buttons" do
      it "enables the [Next] button" do
        expect(Yast::UI).to receive(:UserInput).and_return("eula_some_ID", :next)
        expect(Yast::ProductLicense).to receive(:AllLicensesAcceptedOrDeclined).and_return(true)
        expect(Yast::Wizard).to receive(:EnableNextButton).and_return(true)
        expect(Yast::ProductLicense.HandleLicenseDialogRet(licenses_ref, "base_prod", "abort")).to eq(:accepted)
      end
    end

    context "while user wants to abort from the License Agreement dialog" do
      context "in inst-sys" do
        before(:each) do
          expect(Yast::Stage).to receive(:stage).and_return("initial")
        end

        context "user confirms the aborting" do
          it "returns :abort" do
            expect(Yast::UI).to receive(:UserInput).and_return(:abort)
            expect(Yast::Popup).to receive(:ConfirmAbort).and_return(true)
            expect(Yast::ProductLicense.HandleLicenseDialogRet(licenses_ref, "base_prod", "abort")).to eq(:abort)
          end
        end

        context "user declines the aborting" do
          it "continues handling the user input" do
            expect(Yast::UI).to receive(:UserInput).and_return(:abort, :next)
            expect(Yast::Popup).to receive(:ConfirmAbort).and_return(false)
            expect(Yast::ProductLicense.HandleLicenseDialogRet(licenses_ref, "base_prod", "abort")).to eq(:accepted)
          end
        end
      end

      context "on running system" do
        before(:each) do
          expect(Yast::Stage).to receive(:stage).and_return("normal")
        end

        context "user confirms the aborting" do
          it "returns :abort" do
            expect(Yast::UI).to receive(:UserInput).and_return(:abort)
            expect(Yast::Popup).to receive(:YesNo).and_return(true)
            expect(Yast::ProductLicense.HandleLicenseDialogRet(licenses_ref, "base_prod", "abort")).to eq(:abort)
          end
        end

        context "user declines the aborting" do
          it "continues handling the user input" do
            expect(Yast::UI).to receive(:UserInput).and_return(:abort, :next)
            expect(Yast::Popup).to receive(:YesNo).and_return(false)
            expect(Yast::ProductLicense.HandleLicenseDialogRet(licenses_ref, "base_prod", "abort")).to eq(:accepted)
          end
        end
      end
    end

    context "while going back to previous dialog" do
      it "returns :back" do
        expect(Yast::UI).to receive(:UserInput).and_return(:back)
        expect(Yast::ProductLicense.HandleLicenseDialogRet(licenses_ref, "base_prod", "abort")).to eq(:back)
      end
    end

    context "while going to the next dialog" do
      before(:each) do
        expect(Yast::UI).to receive(:UserInput).and_return(:next).at_least(:once)
        # Confirm that I do not agree with the license
        allow(Yast::Popup).to receive(:YesNo).and_return(true)
      end

      context "while all licenses have been accepted" do
        it "returns :accepted" do
          expect(Yast::ProductLicense).to receive(:AllLicensesAccepted).and_return(true)
          expect(Yast::ProductLicense.HandleLicenseDialogRet(licenses_ref, "base_prod", "abort")).to eq(:accepted)
        end
      end

      context "while some license(s) have not been accepted" do
        it "returns symbol :abort, :accepted, :halt according to the third function parameter" do
          expect(Yast::ProductLicense).to receive(:AllLicensesAccepted).and_return(false).at_least(:once)
          # :halt case
          allow(Yast::ProductLicense).to receive(:TimedOKCancel).and_return(true)

          expect(Yast::ProductLicense.HandleLicenseDialogRet(licenses_ref, "base_prod", "abort")).to eq(:abort)
          expect(Yast::ProductLicense.HandleLicenseDialogRet(licenses_ref, "base_prod", "continue")).to eq(:accepted)
          expect(Yast::ProductLicense.HandleLicenseDialogRet(licenses_ref, "base_prod", "halt")).to eq(:halt)
          expect(Yast::ProductLicense.HandleLicenseDialogRet(licenses_ref, "base_prod", "unknown")).to eq(:abort)
        end
      end
    end

    describe "#location_is_url?" do
      it "returns true for http, https and ftp URL (case insensitive)" do
        expect(Yast::ProductLicense.send(:location_is_url?, "http://example.com")).to eq(true)
        expect(Yast::ProductLicense.send(:location_is_url?, "https://example.com")).to eq(true)
        expect(Yast::ProductLicense.send(:location_is_url?, "ftp://example.com")).to eq(true)
        expect(Yast::ProductLicense.send(:location_is_url?, "HTTP://example.com")).to eq(true)
        expect(Yast::ProductLicense.send(:location_is_url?, "HTTPS://example.com")).to eq(true)
        expect(Yast::ProductLicense.send(:location_is_url?, "FTP://example.com")).to eq(true)
      end

      it "returns false for other URL schema" do
        expect(Yast::ProductLicense.send(:location_is_url?, "file:///foo/bar")).to eq(false)
      end

      it "returns false for non URL string" do
        expect(Yast::ProductLicense.send(:location_is_url?, "/foo/bar")).to eq(false)
      end

      it "returns false for non String values" do
        expect(Yast::ProductLicense.send(:location_is_url?, 42)).to eq(false)
      end

      it "returns false for nil" do
        expect(Yast::ProductLicense.send(:location_is_url?, nil)).to eq(false)
      end
    end

  end

  describe "#AcceptanceNeeded" do
    let(:base_product_id) { 0 }
    let(:add_on_product_id) { 1 }

    before do
      # Downloading and unpacking licenses is expensive, so we cache all values
      # and thus we need to reinit all caches for testing with different values
      Yast::ProductLicense.initialize_default_values

      allow(Yast::ProductLicense).to receive(:base_product_id).and_return(base_product_id)
    end

    context "when called in the initial stage of installation" do
      before do
        # Initial installation
        allow(Yast::Stage).to receive(:initial).and_return(true)
        allow(Yast::Mode).to receive(:installation).and_return(true)

        # Tarball with licenses exists
        allow(Yast::FileUtils).to receive(:Exists).with(/license.tar.gz/).and_return(true)
        # Info file exists
        allow(Yast::FileUtils).to receive(:Exists).with(/info.txt/).and_return(true)
      end

      context "when called for base-product" do
        before do
          expect(Yast::ProductLicense).to receive(:GetSourceLicenseDirectory).and_call_original
          expect(Yast::ProductLicense).to receive(:SetAcceptanceNeeded).and_call_original
          expect(Yast::ProductLicense).to receive(:UnpackLicenseTgzFileToDirectory).and_return(true)
        end

        it "returns that acceptance is needed if no-acceptance-needed file is not found" do
          expect(Yast::FileUtils).to receive(:Exists).with(/no-acceptance-needed/).and_return(false)
          expect(Yast::ProductLicense.AcceptanceNeeded(base_product_id)).to eq(true)
        end

        it "returns that acceptance is not needed if the no-acceptance-needed file is found" do
          expect(Yast::FileUtils).to receive(:Exists).with(/no-acceptance-needed/).and_return(true)
          expect(Yast::ProductLicense.AcceptanceNeeded(base_product_id)).to eq(false)
        end
      end

      context "when called for add-on product" do
        context "when value has not been stored yet" do
          it "returns the safe default true" do
            expect(Yast::ProductLicense.AcceptanceNeeded(add_on_product_id)).to eq(true)
          end
        end

        context "when value has been already stored" do
          it "returns the stored value" do
            Yast::ProductLicense.SetAcceptanceNeeded(add_on_product_id, false)
            expect(Yast::ProductLicense.AcceptanceNeeded(add_on_product_id)).to eq(false)
          end
        end
      end
    end

    context "when not called in initial installation" do
      before do
        allow(Yast::Stage).to receive(:initial).and_return(false)
        allow(Yast::Mode).to receive(:installation).and_return(false)
      end

      context "when called for base-product" do
        context "returns the safe default true" do
          it "throws an error" do
            expect(Yast::ProductLicense.AcceptanceNeeded(base_product_id)).to eq(true)
          end
        end

        context "when value has been already stored" do
          it "returns the stored value" do
            Yast::ProductLicense.SetAcceptanceNeeded(base_product_id, false)
            expect(Yast::ProductLicense.AcceptanceNeeded(base_product_id)).to eq(false)
          end
        end
      end

      context "when called for add-on product" do
        context "when value has not been stored yet" do
          it "returns the safe default true" do
            expect(Yast::ProductLicense.AcceptanceNeeded(add_on_product_id)).to eq(true)
          end
        end

        context "when value has been already stored" do
          it "returns the stored value" do
            Yast::ProductLicense.SetAcceptanceNeeded(add_on_product_id, true)
            expect(Yast::ProductLicense.AcceptanceNeeded(add_on_product_id)).to eq(true)
          end
        end
      end
    end
  end

end
