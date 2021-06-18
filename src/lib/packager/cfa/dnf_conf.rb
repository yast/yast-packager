require "cfa/base_model"
require "cfa/augeas_parser"
require "cfa/matcher"

module Yast
  module Packager
    module CFA
      # Represents a dnf configuration file.
      class DnfConf < ::CFA::BaseModel
        # Configuration parser
        PARSER = ::CFA::AugeasParser.new("puppet.lns")
        # Path to configuration file
        PATH = "/etc/dnf/dnf.conf".freeze

        def initialize(file_handler: nil)
          super(PARSER, PATH, file_handler: file_handler)
        end

        # Set options to keep a minimalistic package selection
        def set_minimalistic!
          tree = data["main"]
          if !tree
            tree = ::CFA::AugeasTree.new
            data["main"] = tree
          end
          generic_set("install_weak_deps", "False", tree)
          generic_set("tsflags", "nodocs", tree)
        end

        def section(name)
          data[name]
        end
      end
    end
  end
end
