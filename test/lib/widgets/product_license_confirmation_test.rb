#!/usr/bin/env rspec

require_relative "../../test_helper"
require "cwm/abstract_widget"
require "cwm/rspec"
require "y2packager/widgets/product_license_confirmation"
require "y2packager/product"

describe Y2Packager::Widgets::ProductLicenseConfirmation do
  include_examples "CWM::AbstractWidget"

  subject(:widget) { described_class.new(product) }

  let(:license_confirmed?) { false }
  let(:confirmation_required?) { false }
  let(:product) do
    instance_double(
      Y2Packager::Product,
      license_confirmed?:             license_confirmed?,
      license_confirmation_required?: confirmation_required?
    )
  end

  before do
    allow(product).to receive(:license_confirmation=)
  end

  describe "#init" do
    context "when product license is unconfirmed" do
      let(:license_confirmed?) { false }

      it "sets value to false" do
        expect(widget).to receive(:uncheck)
        widget.init
      end
    end

    context "when product license is confirmed" do
      let(:license_confirmed?) { true }

      it "sets value to true" do
        expect(widget).to receive(:check)
        widget.init
      end
    end
  end

  describe "#store" do
    before do
      allow(widget).to receive(:value).and_return(value)
    end

    context "when widget's value is true" do
      let(:value) { true }

      context "and product license is unconfirmed" do
        let(:license_confirmed?) { false }

        it "sets the license as confirmed" do
          expect(product).to receive(:license_confirmation=).with(true)
          widget.store
        end
      end

      context "and product license is confirmed" do
        let(:license_confirmed?) { true }

        it "does not modify product's license confirmation" do
          expect(product).to_not receive(:license_confirmation=)
          widget.store
        end
      end
    end

    context "when widget's value is false" do
      let(:value) { false }

      context "and product license is unconfirmed" do
        let(:license_confirmed?) { false }

        it "does not modify product's license confirmation" do
          expect(product).to_not receive(:license_confirmation=)
          widget.store
        end
      end

      context "and product license is confirmed" do
        let(:license_confirmed?) { true }

        it "sets the license as unconfirmed" do
          expect(product).to receive(:license_confirmation=).with(false)
          widget.store
        end
      end
    end
  end

  describe "#handle" do
    it "calls #store" do
      expect(widget).to receive(:store)
      widget.handle
    end
  end

  describe "#validate" do
    context "when license confirmation is not needed" do
      let(:confirmation_required?) { false }

      it "returns true" do
        expect(widget.validate).to eq(true)
      end
    end

    context "when license confirmation is required" do
      let(:confirmation_required?) { true }

      context "and license is confirmed" do
        let(:license_confirmed?) { true }

        it "returns true" do
          expect(widget.validate).to eq(true)
        end
      end

      context "and license is still unconfirmed" do
        let(:license_confirmed?) { false }

        it "returns false" do
          expect(widget.validate).to eq(false)
        end
      end
    end

    context "when validation is disabled" do
      let(:confirmation_required?) { true }
      let(:license_confirmed?) { false }

      subject(:widget) { described_class.new(product, skip_validation: true) }

      it "returns true" do
        expect(widget.validate).to eq(true)
      end
    end
  end
end
