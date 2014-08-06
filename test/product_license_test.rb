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

  end
end
