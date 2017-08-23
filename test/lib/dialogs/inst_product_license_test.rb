require_relative "../../test_helper"
require "y2packager/dialogs/inst_product_license"
require "y2packager/product"

describe Y2Packager::Dialogs::InstProductLicense do
  subject(:dialog) { described_class.new(product) }
  let(:product) do
    instance_double(
      Y2Packager::Product,
      label:                   "openSUSE",
      license:                 "content",
      license_confirmed?:       confirmed?,
      :license_confirmation= => nil
    )
  end

  let(:language) { "en_US" }
  let(:confirmed?) { false }

  describe "#run" do
    before do
      allow(Yast::Language).to receive(:language).and_return(language)
    end

    context "when user accepts the license" do
      before do
        allow(Yast::UI).to receive(:QueryWidget).with(Id(:license_confirmation), :Value)
          .and_return(true)
        allow(Yast::UI).to receive(:UserInput).and_return(:license_confirmation, button)
      end

      context "and clicks :next" do
        let(:button) { :next }

        it "confirms the license" do
          expect(product).to receive(:license_confirmation=).with(true)
          dialog.run
        end

        it "returns :next" do
          expect(dialog.run).to eq(:next)
        end
      end

      context "and clicks :back" do
        let(:button) { :back }

        it "confirms the license" do
          expect(product).to receive(:license_confirmation=).with(true)
          dialog.run
        end

        it "returns :back" do
          expect(dialog.run).to eq(:back)
        end
      end
    end

    context "when user does not accept the license" do
      context "and clicks :next" do
        before do
          allow(Yast::UI).to receive(:UserInput).and_return(:next, :back)
        end

        it "shows a message" do
          expect(Yast::Report).to receive(:Message)
          dialog.run
        end
      end

      context "and clicks :back" do
        before do
          allow(Yast::UI).to receive(:UserInput).and_return(:back)
        end

        it "returns :back" do
          expect(dialog.run).to eq(:back)
        end

        it "does not confirm the license" do
          expect(product).to_not receive(:license_confirmation=)
          dialog.run
        end
      end
    end

    context "when the user set as unconfirmed a previously confirmed license" do
      let(:confirmed?) { true }

      before do
        allow(Yast::UI).to receive(:QueryWidget).with(Id(:license_confirmation), :Value)
          .and_return(false)
      end

      context "and clicks :next" do
        before do
          allow(Yast::UI).to receive(:UserInput).and_return(:license_confirmation, :next, :back)
        end

        it "confirms the license" do
          expect(product).to receive(:license_confirmation=).with(false)
          dialog.run
        end

        it "shows a message" do
          expect(Yast::Report).to receive(:Message)
          dialog.run
        end
      end

      context "and clicks :back" do
        let(:button) { :back }

        before do
          allow(Yast::UI).to receive(:UserInput).and_return(:license_confirmation, button)
        end

        it "set as unconfirmed a license" do
          expect(product).to receive(:license_confirmation=).with(false)
          dialog.run
        end

        it "returns :back" do
          expect(dialog.run).to eq(:back)
        end
      end
    end
  end
end
