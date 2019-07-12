module Y2Packager
  # This class represents a product located on a multi-repository medium,
  # libzypp reads the available products from /medium.1/products file.
  class ProductLocationDetails
    # @return [String] Product name (the zypp resolvable)
    attr_reader :product
    # @return [String] The product package (*-release RPM usually)
    attr_reader :product_package
    # @return [String] Product summary
    attr_reader :summary
    # @return [String] Product description
    attr_reader :description
    # @return [Integer,nil] Display order (nil if not specified)
    attr_reader :order
    # @return [Boolean] Base product flag (true if this is a base product)
    attr_reader :base
    # @return [Array<String>] The product dependencies, includes also the transitive
    #  (indirect) dependencies
    attr_reader :depends_on

    # Constructor
    #
    def initialize(product: nil, summary: nil, product_package: nil,
      order: nil, description: nil, base: nil, depends_on: nil)
      @product = product
      @summary = summary
      @description = description
      @order = order
      @base = base
      @depends_on = depends_on
      @product_package = product_package
    end
  end
end
