#! /usr/bin/env rspec

require_relative "test_helper"
require_relative "product_factory"

require "packager/product_patterns"

Yast.import "Pkg"

describe Yast::ProductPatterns do
  describe "#names" do
    it "returns empty list when there are no products" do
      expect(Yast::Pkg).to receive(:ResolvableProperties).with("", :product, "")
        .and_return([])

      expect(subject.names).to eq([])
    end

    it "returns empty list when there is no selected product" do
      expect(Yast::Pkg).to receive(:ResolvableProperties).with("", :product, "")
        .and_return([ProductFactory.create_product])

      expect(subject.names).to eq([])
    end

    it "returns empty list when the product release package is not found" do
      product = ProductFactory.create_product("status" => :selected,
        "product_package" => nil)

      expect(Yast::Pkg).to receive(:ResolvableProperties).with("", :product, "")
        .and_return([product])
      expect(Yast::Pkg).to receive(:ResolvableProperties).with(product["name"], :product, "")
        .and_return([product])

      expect(subject.names).to eq([])
    end

    it "returns the default pattern name from the release package" do
      default_pattern = "def_pattern"
      product_package_name = "product-release"
      product_package = { "name" => product_package_name, "status" => :selected,
         "deps" => [ {"requires" => "foo"}, {"provides" => "bar"},
           {"provides" => "defaultpattern(#{default_pattern})"} ] }
      product = ProductFactory.create_product("status" => :selected,
        "product_package" => product_package_name)

      expect(Yast::Pkg).to receive(:ResolvableProperties).with("", :product, "")
        .and_return([product])
      expect(Yast::Pkg).to receive(:ResolvableProperties).with(product["name"], :product, "")
        .and_return([product])
      expect(Yast::Pkg).to receive(:ResolvableDependencies).with(product_package_name, :package, "")
        .and_return([product_package])

      expect(subject.names).to eq([default_pattern])
    end

    it "returns the default patterns from all products" do
      default_pattern1 = "def_pattern1"
      product_package_name1 = "product-release1"
      product_package1 = { "name" => product_package_name1, "status" => :selected,
         "deps" => [ {"requires" => "foo"}, {"provides" => "bar"},
           {"provides" => "defaultpattern(#{default_pattern1})"} ] }
      product1 = ProductFactory.create_product("status" => :selected,
        "product_package" => product_package_name1)

      default_pattern2 = "def_pattern2"
      product_package_name2 = "product-release2"
      product_package2 = { "name" => product_package_name2, "status" => :selected,
         "deps" => [ {"requires" => "foo"}, {"provides" => "bar"},
           {"provides" => "defaultpattern(#{default_pattern2})"} ] }
      product2 = ProductFactory.create_product("status" => :selected,
        "product_package" => product_package_name2)

      expect(Yast::Pkg).to receive(:ResolvableProperties).with("", :product, "")
        .and_return([product1, product2])
      expect(Yast::Pkg).to receive(:ResolvableProperties).with(product1["name"], :product, "")
        .and_return([product1])
      expect(Yast::Pkg).to receive(:ResolvableProperties).with(product2["name"], :product, "")
        .and_return([product2])
      expect(Yast::Pkg).to receive(:ResolvableDependencies).with(product_package_name1, :package, "")
        .and_return([product_package1])
      expect(Yast::Pkg).to receive(:ResolvableDependencies).with(product_package_name2, :package, "")
        .and_return([product_package2])

      expect(subject.names.sort).to eq([default_pattern1, default_pattern2].sort)
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
