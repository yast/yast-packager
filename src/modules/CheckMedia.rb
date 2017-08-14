# encoding: utf-8

# File:
#   modules/CheckMedia.ycp
#
# Summary:
#   Module for checking media intergrity
#
# Authors:
#   Ladislav Slezak <lslezak@suse.cz>
#
# $Id$
#
# Input and output routines.
#
require "yast"

module Yast
  class CheckMediaClass < Module
    def main
      Yast.import "Linuxrc"
      Yast.import "Report"

      textdomain "packager"

      @checkmedia = "/usr/bin/checkmedia"

      @output = []
      @progress = 0
      @inprogress = false

      @preferred_drive = ""

      # true if module start was forced - check=1 was found in the application area,
      # effects UI a little
      @forced_start = false

      # cache .probe.cdrom value
      # avoid reprobind during installation
      @cd_cache = nil

      @process = nil
    end

    def DetectedCDDevices
      if @cd_cache.nil?
        # the cache is not initialied, do it now
        cds = Convert.convert(
          SCR.Read(path(".probe.cdrom")),
          from: "any",
          to:   "list <map>"
        )

        if cds.nil?
          # initialize to empty list
          cds = []
        end

        @cd_cache = deep_copy(cds)
      end

      deep_copy(@cd_cache)
    end

    def Start(device)
      # reset values
      @output = []
      @progress = 0
      @inprogress = false

      @process = Convert.to_integer(
        SCR.Execute(
          path(".process.start_shell"),
          Ops.add(Ops.add(@checkmedia, " "), device)
        )
      )
      true
    end

    def Stop
      ret = Convert.to_boolean(SCR.Execute(path(".process.kill"), @process))

      # wait for the process
      SCR.Execute(path(".process.close"), @process)

      # release the process from the agent
      SCR.Execute(path(".process.release"), @process)
      @process = nil

      ret
    end

    def Process
      return if @process.nil?

      if @inprogress
        # try to read whole lines
        out = Convert.to_string(SCR.Read(path(".process.read_line"), @process))

        if !out.nil?
          @output = Builtins.add(@output, out)

          out = Convert.to_string(SCR.Read(path(".process.read"), @process))

          if !out.nil?
            @output = Convert.convert(
              Builtins.merge(@output, Builtins.splitstring(out, "\n")),
              from: "list",
              to:   "list <string>"
            )
          end

          # finished
          @progress = 100
          @inprogress = false
        else
          # read progress status
          buffer = Convert.to_string(SCR.Read(path(".process.read"), @process))

          if !buffer.nil?
            Builtins.y2debug("buffer: %1", buffer)

            percent = Builtins.regexpsub(buffer, "([0-9]*)%.*$", "\\1")

            if !percent.nil?
              @progress = Builtins.tointeger(percent)
              Builtins.y2milestone("progress: %1%%", @progress)
            end
          end
        end
      else
        out = Convert.to_string(SCR.Read(path(".process.read_line"), @process))

        if !out.nil?
          @output = Builtins.add(@output, out)

          # check whether we need to switch to progress mode
          if Builtins.regexpmatch(out, "^ *pad: ")
            @inprogress = true
            Builtins.y2milestone("Switching into progress mode")
          end
        end
      end

      nil
    end

    def Running
      ret = Convert.to_boolean(SCR.Read(path(".process.running"), @process))

      ret
    end

    # Return information printed by checkmedia utility
    # @return [Array<String>] checkmedia output
    def Info
      ret = deep_copy(@output)
      @output = []
      deep_copy(ret)
    end

    def Progress
      @progress
    end

    # Return list of ready CD devices for installation. It works properly only
    # in the first installation stage - it reads content of /etc/install.inf
    # file. It returns the installation (boot) CD device if it's known or it
    # probes for all CD devices and returns ready devices (the devices which
    # contain a medium). If repository is not CD/DVD it returns
    # empty list.
    #
    # @return [Array<String>] List of CD/DVD device names
    def GetReadyCDs
      # check whether we are using CD repository
      instmode = Linuxrc.InstallInf("InstMode")
      Builtins.y2milestone("Installation mode: %1", instmode)

      readycddrives = []

      if instmode == "cd" || instmode == "dvd"
        # get CD device name
        bootcd = Linuxrc.InstallInf("Cdrom")

        if !bootcd.nil? && bootcd != ""
          readycddrives = [Builtins.sformat("/dev/%1", bootcd)]
        else
          Builtins.y2milestone("CD device device is not known, probing...")
          # booted from another location (network), test all CD drives
          cds = DetectedCDDevices()

          Builtins.foreach(cds) do |cd|
            devname = Ops.get_string(cd, "dev_name", "")
            # check whether the CD is ready
            if Ops.get_boolean(cd, "notready", false) == false && !devname.nil? &&
                devname != ""
              readycddrives = Builtins.add(readycddrives, devname)
            end
          end if !cds.nil?
        end

        Builtins.y2milestone("Ready CD drives: %1", readycddrives)
      end

      deep_copy(readycddrives)
    end

    # Release resources used by the subprocess
    def Release
      if !@process.nil?
        SCR.Execute(path(".process.release"), @process)
        @process = nil
      end

      nil
    end

    publish variable: :checkmedia, type: "const string"
    publish variable: :preferred_drive, type: "string"
    publish variable: :forced_start, type: "boolean"
    publish function: :DetectedCDDevices, type: "list <map> ()"
    publish function: :Start, type: "boolean (string)"
    publish function: :Stop, type: "boolean ()"
    publish function: :Process, type: "void ()"
    publish function: :Running, type: "boolean ()"
    publish function: :Info, type: "list <string> ()"
    publish function: :Progress, type: "integer ()"
    publish function: :GetReadyCDs, type: "list <string> ()"
    publish function: :Release, type: "void ()"
  end

  CheckMedia = CheckMediaClass.new
  CheckMedia.main
end
