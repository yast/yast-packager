#! /usr/bin/env rspec

require_relative "test_helper"
require_relative "product_factory"

require "packager/product_patterns"

Yast.import "Pkg"

describe Yast::ProductPatterns do
  describe "#names" do
    it "returns empty list when there are no products" do
      expect(Y2Packager::Resolvable).to receive(:find).with(kind: :product)
        .and_return([])

      expect(subject.names).to eq([])
    end

    it "returns empty list when there is no selected product" do
      expect(Y2Packager::Resolvable).to receive(:find).with(kind: :product)
        .and_return([Y2Packager::Resolvable.new(ProductFactory.create_product)])

      expect(subject.names).to eq([])
    end

    it "returns empty list when the product release package is not found" do
      product = Y2Packager::Resolvable.new(
        ProductFactory.create_product("status"          => :selected,
          "product_package" => nil))

      expect(Y2Packager::Resolvable).to receive(:find).with(kind: :product)
        .and_return([product])
      expect(Y2Packager::Resolvable).to receive(:find).with(name: product["name"], kind: :product)
        .and_return([product])

      expect(subject.names).to eq([])
    end

    it "returns the default pattern name from the release package" do
      pattern_name, package_name, package, product =
        ProductFactory.create_product_packages(product_name: "product1")

      expect(Y2Packager::Resolvable).to receive(:find).with(kind: :product)
        .and_return([product])
      expect(Y2Packager::Resolvable).to receive(:find).with(name: product["name"], kind: :product)
        .and_return([product])
      expect(Y2Packager::Resolvable).to receive(:find).with(name: package_name, kind: :package)
        .and_return([package])

      expect(subject.names).to eq([pattern_name])
    end

    it "returns the default patterns from all products" do
      pattern_name_first, package_name_first, package_first, product_first =
        ProductFactory.create_product_packages(product_name: "product_first")

      pattern_name_second, package_name_second, package_second, product_second =
        ProductFactory.create_product_packages(product_name: "product_second")

      expect(Y2Packager::Resolvable).to receive(:find).with(kind: :product)
        .and_return([product_first, product_second])
      expect(Y2Packager::Resolvable).to receive(:find).with(name: product_first["name"], kind: :product)
        .and_return([product_first])
      expect(Y2Packager::Resolvable).to receive(:find).with(name: product_second["name"], kind: :product)
        .and_return([product_second])
      expect(Y2Packager::Resolvable).to receive(:find).with(name: package_name_first, kind: :package)
        .and_return([package_first])
      expect(Y2Packager::Resolvable).to receive(:find).with(name: package_name_second, kind: :package)
        .and_return([package_second])

      expect(subject.names.sort).to eq([pattern_name_first, pattern_name_second].sort)
    end

    context "repository parameter has been set" do
      # get the default patterns only from the repository with id 2
      subject { Yast::ProductPatterns.new(src: 2) }

      it "returns the default patterns only from the selected repository" do
        _pattern_name_other, package_name_other, _package_other, product_other =
          ProductFactory.create_product_packages(product_name: "product_other", src: 1)

        pattern_name_selected, package_name_selected, package_selected, product_selected =
          ProductFactory.create_product_packages(product_name: "product_selected", src: 2)

        expect(Y2Packager::Resolvable).to receive(:find).with(kind: :product)
          .and_return([product_other, product_selected])
        expect(Y2Packager::Resolvable).to receive(:find)
          .with(name: product_other["name"], kind: :product)
          .and_return([product_other])
        expect(Y2Packager::Resolvable).to receive(:find)
          .with(name: product_selected["name"], kind: :product)
          .and_return([product_selected])
        # the product_other package should not be checked, it's in different repo
        expect(Y2Packager::Resolvable).to_not receive(:find)
          .with(name: package_name_other, kind: :package)
        expect(Y2Packager::Resolvable).to receive(:find)
          .with(name: package_name_selected, kind: :package)
          .and_return([package_selected])

        expect(subject.names).to eq([pattern_name_selected])
      end
    end
  end

  describe "#select" do
    context "no default pattern found" do
      before do
        expect(subject).to receive(:names).and_return([])
      end

      it "does not select anything to install" do
        expect(Yast::Pkg).to_not receive(:ResolvableInstall)

        subject.select
      end

      it "returns true (success)" do
        expect(subject.select).to eq(true)
      end
    end

    context "default patterns found" do
      before do
        expect(subject).to receive(:names).and_return(["pattern1", "pattern2"])
      end

      it "selects the default patterns to install" do
        expect(Yast::Pkg).to receive(:ResolvableInstall).with("pattern1", :pattern)
        expect(Yast::Pkg).to receive(:ResolvableInstall).with("pattern2", :pattern)

        subject.select
      end

      it "returns true if all default patterns were selected" do
        expect(Yast::Pkg).to receive(:ResolvableInstall).with("pattern1", :pattern)
          .and_return(true)
        expect(Yast::Pkg).to receive(:ResolvableInstall).with("pattern2", :pattern)
          .and_return(true)

        expect(subject.select).to eq(true)
      end

      it "returns false if any default pattern could not be selected" do
        expect(Yast::Pkg).to receive(:ResolvableInstall).with("pattern1", :pattern)
          .and_return(true)
        expect(Yast::Pkg).to receive(:ResolvableInstall).with("pattern2", :pattern)
          .and_return(false)

        expect(subject.select).to eq(false)
      end
    end
  end
end
