require "shellwords"

# encoding: utf-8
module Yast
  # Client for checking media integrity
  class InstCheckmediaClient < Client
    def main
      textdomain "packager"

      Yast.import "CheckMedia"
      Yast.import "String"

      # The main ()
      Builtins.y2milestone("Checkmedia-installation module started")
      Builtins.y2milestone("----------------------------------------")

      # main ui function
      @ret = :next

      # check whether we are using CD repository
      @instmode = Convert.to_string(SCR.Read(path(".etc.install_inf.InstMode")))
      Builtins.y2milestone("Installation mode: %1", @instmode)

      if @instmode == "cd" || @instmode == "dvd"
        @readycddrives = CheckMedia.GetReadyCDs
        Builtins.y2milestone("Ready CD drives: %1", @readycddrives)

        if Ops.greater_than(Builtins.size(@readycddrives), 0)
          @dotest = false

          # check whether "offer-extra-media-test" bit is present on any(!) medium
          Builtins.foreach(@readycddrives) do |drive|
            # read application area on the medium
            out = SCR.Execute(
              path(".target.bash_output"),
              "/bin/dd if=#{drive.shellescape} bs=1 skip=33651 count=512"
            )
            application_area = {}
            if Ops.get_integer(out, "exit", -1).zero?
              # parse application area
              app = Ops.get_string(out, "stdout", "")

              app = String.CutBlanks(app)
              Builtins.y2milestone("Read application area: %1", out)

              values = Builtins.splitstring(app, ";")

              if !values.nil?
                Builtins.foreach(values) do |val|
                  v = Builtins.splitstring(val, "=")
                  key = Ops.get(v, 0)
                  value = Ops.get(v, 1)
                  Ops.set(application_area, key, value) if !key.nil?
                end
              end
              Builtins.y2milestone(
                "Parsed application area: %1",
                application_area
              )
            end
            # test 'check' key
            if Ops.get(application_area, "check", "") == "1"
              @dotest = true
              # propagate device name to the check media client
              # (preselect the device in the combo box)
              CheckMedia.preferred_drive = drive
            end
          end

          if @dotest
            # start checkmedia client in forced mode
            Builtins.y2milestone("Found a medium with MD5 check request.")
            CheckMedia.forced_start = true
            @ret = WFM.CallFunction("checkmedia", WFM.Args)
            CheckMedia.forced_start = false
          else
            Builtins.y2milestone(
              "Skipping CD check - 'check' option is not set in the application area"
            )
            @ret = :auto
          end
        else
          Builtins.y2milestone("CD/DVD was not found")
          @ret = :auto
        end
      else
        Builtins.y2milestone("No CD repository found, skipping Media Check")
        @ret = :auto
      end

      # Finish
      Builtins.y2milestone("Checkmedia-installation finished")
      deep_copy(@ret)
    end
  end
end

Yast::InstCheckmediaClient.new.main
