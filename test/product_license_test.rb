#! /usr/bin/env rspec

require_relative "./test_helper"

Yast.import "ProductLicense"
Yast.import "UI"
Yast.import "Wizard"
Yast.import "Popup"
Yast.import "Stage"

describe Yast::ProductLicense do
  describe "#HandleLicenseDialogRet" do
    let(:user_input) { :next }
    let(:licenses_ref) { Yast::ArgRef.new({}) }
    let(:base_product) { nil }
    let(:cancel_action) { nil }

    before do
      allow(Yast::UI).to receive(:UserInput).and_return(*user_input)
    end

    context "while changing a license language" do
      let(:user_input) { ["license_language_pt_BR", :back] }

      it "updates the UI with new license translation" do
        expect(Yast::ProductLicense).to receive(:UpdateLicenseContent).and_return(nil)

        described_class.HandleLicenseDialogRet(licenses_ref, base_product, cancel_action)
      end
    end

    context "while adjusting EULA agreement buttons" do
      let(:user_input) { ["eula_some_ID", :next] }

      before do
        allow(Yast::ProductLicense).to receive(:AllLicensesAcceptedOrDeclined)
          .and_return(all_licenses_accepted_or_declined)
      end

      context "and all licenses accepted or declined" do
        let(:all_licenses_accepted_or_declined) { true }

        it "enables the [Next] button" do
          expect(Yast::Wizard).to receive(:EnableNextButton)

          described_class.HandleLicenseDialogRet(licenses_ref, base_product, cancel_action)
        end
      end

      context "but not all licenses accpeted or declined" do
        let(:all_licenses_accepted_or_declined) { false }

        it "enables the [Next] button" do
          expect(Yast::Wizard).to_not receive(:EnableNextButton)

          described_class.HandleLicenseDialogRet(licenses_ref, base_product, cancel_action)
        end
      end
    end

    context "while user wants to abort from the License Agreement dialog" do
      context "in inst-sys" do
        before do
          allow(Yast::Stage).to receive(:stage).and_return("initial")
          allow(Yast::Popup).to receive(:ConfirmAbort).and_return(confirm_abort)
        end

        context "and the user confirms to abort" do
          let(:user_input) { :abort }
          let(:confirm_abort) { true }

          it "returns :abort" do
            result = described_class.HandleLicenseDialogRet(licenses_ref, base_product, cancel_action)

            expect(result).to eq(:abort)
          end
        end

        context "and the user does not confirm to abort" do
          let(:user_input) { [:abort, :back] }
          let(:confirm_abort) { false }

          it "does not return :abort" do
            result = described_class.HandleLicenseDialogRet(licenses_ref, base_product, cancel_action)

            expect(result).to_not eq(:abort)
          end
        end
      end

      context "in a running system" do
        before do
          allow(Yast::Stage).to receive(:stage).and_return("normal")
          allow(Yast::Popup).to receive(:YesNo).and_return(confirm_abort)
        end

        context "and the user confirms to abort" do
          let(:user_input) { :abort }
          let(:confirm_abort) { true }

          it "returns :abort" do
            result = described_class.HandleLicenseDialogRet(licenses_ref, base_product, cancel_action)

            expect(result).to eq(:abort)
          end
        end

        context "and the user does not confirm to abort" do
          let(:user_input) { [:abort, :back] }
          let(:confirm_abort) { false }

          it "does not return :abort" do
            result = described_class.HandleLicenseDialogRet(licenses_ref, base_product, cancel_action)

            expect(result).to_not eq(:abort)
          end
        end
      end
    end

    context "while going back to previous dialog" do
      let(:user_input) { :back }

      it "returns :back" do
        result = described_class.HandleLicenseDialogRet(licenses_ref, base_product, cancel_action)

        expect(result).to eq(:back)
      end
    end

    context "while going to the next dialog" do
      let(:licenses_accepted) { false }

      before(:each) do
        allow(Yast::ProductLicense).to receive(:AllLicensesAccepted).and_return(licenses_accepted)
      end

      context "when license(s) have been accepted" do
        let(:licenses_accepted) { true }

        it "returns :accepted" do
          result = described_class.HandleLicenseDialogRet(licenses_ref, base_product, cancel_action)

          expect(result).to eq(:accepted)
        end
      end

      context "when some license(s) have not been accepted" do
        context "but using 'continue' as cancel action" do
          let(:cancel_action) { "continue" }

          it "returns :accepted" do
            result = described_class.HandleLicenseDialogRet(licenses_ref, base_product, cancel_action)

            expect(result).to eq(:accepted)
          end
        end

        context "and is handling the license of a base product" do
          let(:base_product) { "Fake base product" }
          let(:user_input) { [:next, :back] }

          it "displays a message" do
            expect(Yast::Popup).to receive(:Message)

            described_class.HandleLicenseDialogRet(licenses_ref, base_product, cancel_action)
          end
        end

        context "and is handling an not base product license" do
          let(:base_product) { nil }
          let(:refuse_license) { true }

          before do
            allow(Yast::Popup).to receive(:YesNo).and_return(refuse_license)
          end

          it "asks user if really want to refuse it" do
            expect(Yast::Popup).to receive(:YesNo)

            described_class.HandleLicenseDialogRet(licenses_ref, base_product, cancel_action)
          end

          context "but users does not confirm to decline the license" do
            let(:refuse_license) { false }
            let(:user_input) { [:next, :back] }

            it "does not decline it" do
              result = described_class.HandleLicenseDialogRet(licenses_ref, base_product, cancel_action)

              expect(result).to eq(:back)
            end
          end

          context "and the user confirms that really wants to decline it" do
            let(:refuse_license) { true }

            context "using 'abort' as cancel action" do
              let(:cancel_action) { "abort" }

              it "returns :abort" do
                result = described_class.HandleLicenseDialogRet(licenses_ref, base_product, cancel_action)

                expect(result).to eq(:abort)
              end
            end

            context "using 'refuse' as cancel action" do
              let(:cancel_action) { "refuse" }

              it "returns :refuse" do
                result = described_class.HandleLicenseDialogRet(licenses_ref, base_product, cancel_action)

                expect(result).to eq(:refused)
              end
            end

            context "using 'halt' as cancel action" do
              let(:cancel_action) { "halt" }
              let(:halt_confirmation) { true }

              before do
                allow(Yast::Popup).to receive(:TimedOKCancel).and_return(halt_confirmation)
              end

              it "displays a timed popup to continue or cancel halting the system" do
                expect(Yast::Popup).to receive(:TimedOKCancel)

                described_class.HandleLicenseDialogRet(licenses_ref, base_product, cancel_action)
              end

              context "and the user agrees halting the system" do
                let(:halt_confirmation) { true }

                it "returns :halt" do
                  result = described_class.HandleLicenseDialogRet(licenses_ref, base_product, cancel_action)

                  expect(result).to eq(:halt)
                end
              end

              context "and the user does not agree halting the system" do
                let(:halt_confirmation) { false }
                let(:user_input) { [:next, :back] }

                it "does not return :halt" do
                  result = described_class.HandleLicenseDialogRet(licenses_ref, base_product, cancel_action)

                  expect(result).to_not eq(:halt)
                end
              end
            end

            context "using an unknown cancel action" do
              let(:cancel_action) { "not_known_action" }

              it "returns :abort" do
                result = described_class.HandleLicenseDialogRet(licenses_ref, base_product, cancel_action)

                expect(result).to eq(:abort)
              end
            end
          end
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
      end

      context "when licenses exists" do
        before do
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

      context "when no license exists" do
        before do
          # Tarball with licenses does not exist
          allow(Yast::FileUtils).to receive(:Exists).with(/license.tar.gz/).and_return(false)
          # Info file does not exist
          allow(Yast::FileUtils).to receive(:Exists).with(/info.txt/).and_return(false)
        end

        it "do not blame that there is no license directory" do
           # This call is needed for checking the cache_license_acceptance_needed function
           expect(Yast::ProductLicense.AcceptanceNeeded(base_product_id)).to eq(true)
           Yast::ProductLicense.SetAcceptanceNeeded(add_on_product_id, false)

           expect(Yast::ProductLicense.AcceptanceNeeded(add_on_product_id)).to eq(false)
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
