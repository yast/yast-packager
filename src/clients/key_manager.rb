# encoding: utf-8
module Yast
  # Manages GPG keys in the package manager
  class KeyManagerClient < Client
    def main
      Yast.import "Pkg"
      Yast.import "UI"
      textdomain "packager"

      Yast.import "PackageCallbacks"
      Yast.import "Wizard"
      Yast.import "Label"
      Yast.import "Report"
      Yast.import "CommandLine"
      Yast.import "Popup"
      Yast.import "PackageLock"
      Yast.import "KeyManager"
      Yast.import "Installation"
      Yast.import "Sequencer"

      Yast.include self, "packager/key_manager_dialogs.rb"

      @cmdline_description = {
        "id"         => "key_mgmgt",
        "guihandler" => fun_ref(method(:Main), "symbol ()")
      }

      CommandLine.Run(@cmdline_description)
    end

    def Read
      if !Ops.get_boolean(PackageLock.Connect(false), "connected", false)
        # SW management is already in use, access denied
        # the yast module cannot be started
        Wizard.CloseDialog
        return :abort
      end

      # init the target - read the keys
      if !Pkg.TargetInitialize(Installation.destdir)
        Builtins.y2error("The target cannot be initialized, aborting...")
        return :abort
      end

      # read the current keys
      if !KeyManager.Read
        Builtins.y2error("The key configuration cannot be read, aborting...")
        return :abort
      end

      :next
    end

    def Write
      KeyManager.Write ? :next : :abort
    end

    # main function - start the workflow
    def Main
      Wizard.CreateDialog
      Wizard.SetDesktopIcon("org.openSUSE.YaST.Security")
      # dialog caption
      Wizard.SetContents(_("Initializing..."), Empty(), "", false, true)

      aliases = {
        "read"  => -> { Read() },
        "edit"  => -> { RunGPGKeyMgmt(true) },
        "write" => -> { Write() }
      }

      sequence = {
        "ws_start" => "read",
        "read"     => { next: "edit" },
        "edit"     => { abort: :abort, next: "write" },
        "write"    => { next: :next, abort: :abort }
      }

      Builtins.y2milestone("Starting the key management sequence")
      ret = Sequencer.Run(aliases, sequence)

      Wizard.CloseDialog
      ret
    end
  end
end

Yast::KeyManagerClient.new.main
