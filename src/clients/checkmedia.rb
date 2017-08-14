# encoding: utf-8

# File:
#   clients/checkmedia.ycp
#
# Summary:
#   Client for checkig media integrity
#
# Authors:
#   Ladislav Slezak <lslezak@suse.cz>
#
# $Id$
#
module Yast
  class CheckmediaClient < Client
    def main
      Yast.import "Pkg"
      Yast.import "UI"

      textdomain "packager"

      Yast.import "CommandLine"

      Yast.include self, "checkmedia/ui.rb"

      # The main ()
      Builtins.y2milestone("Checkmedia module started")
      Builtins.y2milestone("----------------------------------------")
      Builtins.y2milestone("arguments: %1", WFM.Args)

      # main ui function
      @ret = nil

      # Command line definition - minimal command line support
      @cmdline = {
        # module description
        "help"       => _(
          "Check CD or DVD media integrity"
        ),
        "id"         => "checkmedia",
        "guihandler" => fun_ref(method(:MainSequence), "any ()")
      }

      @ret = CommandLine.Run(@cmdline)

      Builtins.y2debug("ret == %1", @ret)

      # Finish
      Builtins.y2milestone("Checkmedia module finished")
      deep_copy(@ret)
    end
  end
end

Yast::CheckmediaClient.new.main
