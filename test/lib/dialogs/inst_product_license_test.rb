require_relative "../../test_helper"
require "y2packager/dialogs/inst_product_license"
require "y2packager/product"

describe Y2Packager::Dialogs::InstProductLicense do
  subject(:dialog) { described_class.new(product) }
  let(:product) do
    instance_double(
      Y2Packager::Product,
      label:                   "openSUSE",
      license:                  content,
      license_confirmed?:       confirmed?,
      :license_confirmation= => nil
    )
  end

  let(:language) { "en_US" }
  let(:confirmed?) { false }
  let(:content) { "content" }

  describe "#run" do
    before do
      allow(Yast::Language).to receive(:language).and_return(language)
      allow(Yast::Language).to receive(:GetLanguageItems).and_return([])
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

    context "license formatting" do
      before do
        allow(Yast::UI).to receive(:UserInput).and_return(:license_confirmation, :back)
      end

      context "when license content is richtext" do
        let(:content) { "<h1>title</h1>" }

        it "does not modify the text" do
          expect(subject).to receive(:RichText).with(Id(:license_content), content)
          dialog.run
        end
      end

      context "when license content is not richtext" do
        let(:content) { "SLE 15 > SLE 12" }

        it "converts to richtext" do
          expect(subject).to receive(:RichText)
            .with(Id(:license_content), "<pre>SLE 15 &gt; SLE 12</pre>")
          dialog.run
        end
      end
    end
  end
end
