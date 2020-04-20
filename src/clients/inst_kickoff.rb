# encoding: utf-8

require "fileutils"
require "shellwords"

module Yast
  # Do various tasks before starting with installation of rpms.
  class InstKickoffClient < Client
    def main
      Yast.import "Pkg"
      textdomain "packager"

      Yast.import "Mode"
      Yast.import "Stage"
      Yast.import "Linuxrc"
      Yast.import "Installation"
      Yast.import "Popup"
      Yast.import "Directory"
      Yast.import "ModuleLoading"
      Yast.import "Kernel"
      Yast.import "Arch"
      Yast.import "FileUtils"
      Yast.import "String"
      Yast.import "Mtab"

      if !Mode.update
        # fake mtab on target system for rpm post-scripts
        Mtab.clone_to_target
      end

      # Disabling VPN, SSH,.... if the packages are not available
      Linuxrc.disable_remote(Packages.missing_remote_kind)

      # Feature #301903, bugzilla #244937
      # "/" means updating the running system, bugzilla #246389
      if Mode.update && Installation.destdir != "/"
        # Mount (bind) the current /dev/ to the /installed_system/dev/
        LocalCommand(
          Builtins.sformat(
            # try unmounting the /mnt/dev directory before the cleanup, usually there
            # is a bind mount /dev -> /mnt/dev which would remove the files also from /dev
            "/usr/bin/umount %1/dev/; /bin/rm -rf %1/dev/ && /bin/mkdir -p %1/dev/ && " \
              "/bin/mount -v --bind /dev/ %1/dev/",
            Installation.destdir.shellescape
          )
        )
      end

      # copy the credential files, libzypp loads them from target
      zypp_dir = "/etc/zypp"
      credentials_d = zypp_dir + "/credentials.d"

      if File.exist?(credentials_d) && Installation.destdir != "/"
        target_zypp = Installation.destdir + zypp_dir
        Builtins.y2milestone("Copying libzypp credentials to #{target_zypp}...")
        ::FileUtils.mkdir_p(target_zypp)
        ::FileUtils.cp_r(credentials_d, target_zypp)
      end

      # installation, for instance...
      if !Mode.update
        # make some directories
        SCR.Execute(
          path(".target.mkdir"),
          Ops.add(Installation.destdir, "/etc")
        )
        SCR.Execute(
          path(".target.mkdir"),
          Ops.add(Installation.destdir, Directory.logdir)
        )

        # fake mtab on target system
        Mtab.clone_to_target

        # F#302660: System installation and upgrade workflow: kernel %post
        # calling ins_bootloader write all config files for bootloader
        #	if (Stage::initial ())
        #    	{
        # call it always, it handles installation mode inside
        WFM.CallFunction("inst_bootloader", WFM.Args)
        #	}
      elsif Stage.normal
        Yast.import "Kernel"
        @kernel = Kernel.ComputePackage
        Kernel.SetInformAboutKernelChange(Pkg.IsSelected(@kernel))

        SCR.Execute(
          path(".target.mkdir"),
          Ops.add(Installation.destdir, Installation.update_backup_path)
        )
        backup_stuff
        createmdadm
      else
        # disable all repositories at the target
        Pkg.TargetDisableSources

        # make some directories
        SCR.Execute(
          path(".target.mkdir"),
          Ops.add(Installation.destdir, Directory.logdir)
        )
        SCR.Execute(
          path(".target.mkdir"),
          Ops.add(Installation.destdir, Installation.update_backup_path)
        )

        # backup some stuff
        backup_stuff

        # set update mode to yes
        SCR.Write(
          path(".target.string"),
          Ops.add(Installation.destdir, "/var/lib/YaST2/update_mode"),
          "YES"
        )
        SCR.Execute(
          path(".target.remove"),
          Ops.add(Installation.destdir, "/var/lib/YaST/update.inf")
        )

        # create /etc/mdadm.conf if it does not exist
        createmdadm

        # load all network modules
        load_network_modules

        # initialize bootloader
        # will return immediatly unless bootloader configuration was
        # proposed from scratch (bnc#899743)
        WFM.CallFunction("inst_bootloader", WFM.Args)
      end

      :next
    end

    #  Handle the backup.
    def backup_stuff
      if Installation.update_backup_modified
        Pkg.CreateBackups(true)
        Pkg.SetBackupPath(Installation.update_backup_path)
        SCR.Write(
          path(".target.string"),
          Ops.add(Installation.destdir, "/var/lib/YaST2/backup_path"),
          Installation.update_backup_path
        )
      else
        Pkg.CreateBackups(false)
        SCR.Execute(
          path(".target.remove"),
          Ops.add(Installation.destdir, "/var/lib/YaST2/backup_path")
        )
      end

      # Removing all old backups
      if Installation.update_remove_old_backups
        Builtins.y2milestone(
          "Removing old backups *-*-*.tar.{gz,bz2} from %1",
          Installation.update_backup_path
        )
        SCR.Execute(
          path(".target.bash"),
          "cd #{Installation.destdir.shellescape}; " \
            "/bin/rm -f #{Installation.update_backup_path.shellescape}/*-*-*.tar.{gz,bz2}"
        )
      end

      # timestamp
      date = Builtins.timestring("%Y%m%d", ::Time.now.to_i, false)

      # do not backup logs on running system (bsc#1166174)
      if Installation.destdir != "/"
        Builtins.y2milestone("Creating backup of %1", Directory.logdir)

        filename = ""
        num = 0

        while Ops.less_than(num, 42)
          filename = Ops.add(
            Ops.add(
              Ops.add(
                Ops.add(
                  Ops.add(Installation.update_backup_path, "/YaST2-"),
                  date
                ),
                "-"
              ),
              Builtins.sformat("%1", num)
            ),
            ".tar.gz"
          )
          if SCR.Read(
            path(".target.size"),
            Ops.add(Installation.destdir, filename)
          ) == -1
            break
          end

          num = Ops.add(num, 1)
        end

        if SCR.Execute(
          path(".target.bash"),
          "cd #{Shellwords.escape(Installation.destdir)}; " \
            "/bin/tar --ignore-failed-read -czf .#{Shellwords.escape(filename)} var/log/YaST2"
        ).nonzero?
          Builtins.y2error(
            "backup of %1 to %2 failed",
            Directory.logdir,
            filename
          )
          # an error popup
          Popup.Error(
            Builtins.sformat(
              _("Backup of %1 failed. See %2 for details."),
              Directory.logdir,
              Ops.add(Directory.logdir, "/y2log")
            )
          )
        else
          SCR.Execute(
            path(".target.bash"),
            "cd #{Installation.destdir.shellescape}; /bin/rm -rf var/log/YaST2/*"
          )
        end
      end

      if Installation.update_backup_sysconfig
        # backup /etc/sysconfig
        if Ops.greater_than(
          SCR.Read(
            path(".target.size"),
            File.join(Installation.destdir, "/etc/sysconfig")
          ),
          0
        )
          Builtins.y2milestone("backup of /etc/sysconfig")

          filename = ""
          num = 0

          while Ops.less_than(num, 42)
            filename = Ops.add(
              Ops.add(
                Ops.add(
                  Ops.add(
                    Ops.add(Installation.update_backup_path, "/etc.sysconfig-"),
                    date
                  ),
                  "-"
                ),
                Builtins.sformat("%1", num)
              ),
              ".tar.gz"
            )
            if SCR.Read(
              path(".target.size"),
              Ops.add(Installation.destdir, filename)
            ) == -1
              break
            end
            num = Ops.add(num, 1)
          end

          if SCR.Execute(
            path(".target.bash"),
            "cd #{Installation.destdir.shellescape}; " \
              "/bin/tar czf .#{filename.shellescape} etc/sysconfig"
          ).nonzero?
            Builtins.y2error(
              "backup of %1 to %2 failed",
              "/etc/sysconfig",
              filename
            )
            # an error popup
            Popup.Error(
              Builtins.sformat(
                _("Backup of %1 failed. See %2 for details."),
                "/etc/sysconfig",
                Ops.add(Directory.logdir, "/y2log")
              )
            )
          end
        # backup of /etc/rc.config*
        elsif Ops.greater_than(
          SCR.Read(
            path(".target.size"),
            Ops.add(Installation.destdir, "/etc/rc.config")
          ),
          0
        ) &&
            Ops.greater_than(
              SCR.Read(
                path(".target.size"),
                Ops.add(Installation.destdir, "/etc/rc.config.d")
              ),
              0
            )
          Builtins.y2milestone("backup of /etc/rc.config.d")

          filename = ""
          num = 0

          while Ops.less_than(num, 42)
            filename = Ops.add(
              Ops.add(
                Ops.add(
                  Ops.add(
                    Ops.add(Installation.update_backup_path, "/etc.rc.config-"),
                    date
                  ),
                  "-"
                ),
                Builtins.sformat("%1", num)
              ),
              ".tar.gz"
            )
            if SCR.Read(
              path(".target.size"),
              Ops.add(Installation.destdir, filename)
            ) == -1
              break
            end
            num = Ops.add(num, 1)
          end

          if SCR.Execute(
            path(".target.bash"),
            "cd #{Installation.destdir.shellescape}; " \
              "/bin/tar czf .#{filename} etc/rc.config etc/rc.config.d"
          ).nonzero?
            Builtins.y2error(
              "backup of %1 to %2 failed",
              "/etc/rc.config",
              filename
            )
            # an error popup
            Popup.Error(
              Builtins.sformat(
                _("Backup of %1 failed. See %2 for details."),
                "/etc/rc.config",
                Ops.add(Directory.logdir, "/y2log")
              )
            )
          end
        end
      end

      # Backup /etc/pam.d/ unconditionally
      # bnc #393066
      if Mode.update
        filename = ""
        num = 0

        while Ops.less_than(num, 42)
          filename = Ops.add(
            Ops.add(
              Ops.add(
                Ops.add(
                  Ops.add(Installation.update_backup_path, "/etc.pam.d-"),
                  date
                ),
                "-"
              ),
              Builtins.sformat("%1", num)
            ),
            ".tar.gz"
          )

          # avoid from filename conflicts
          break if !FileUtils.Exists(Ops.add(Installation.destdir, filename))
          num = Ops.add(num, 1)
        end

        what_to_backup = ["etc/pam.d", "etc/security", "etc/securetty", "etc/environment"]

        # enters the Installation::destdir
        # and creates backup of etc/pam.d directory in Installation::update_backup_path
        cmd = Builtins.sformat(
          "cd %1; /bin/tar --ignore-failed-read -czf .%2 %3",
          Installation.destdir.shellescape,
          filename.shellescape,
          what_to_backup.map(&:shellescape).join(" ")
        )

        Builtins.y2milestone(
          "Creating backup of %1 in %2",
          what_to_backup,
          Ops.add(Installation.destdir, filename)
        )

        if SCR.Execute(path(".target.bash"), cmd).nonzero?
          Builtins.y2error("backup command failed: %1", cmd)
          # an error popup
          Popup.Error(
            Builtins.sformat(
              _("Backup of %1 failed. See %2 for details."),
              "/etc/pam.d",
              Ops.add(Directory.logdir, "/y2log")
            )
          )
        end
      end

      nil
    end

    # Create /etc/mdadm.conf if it does not exist and it's needed
    # bugs: #169710 and #146304
    def createmdadm
      mdamd_configfile = Ops.add(Installation.destdir, "/etc/mdadm.conf")
      # File exists, no need to create it
      if FileUtils.Exists(mdamd_configfile)
        Builtins.y2milestone(
          "File /etc/mdadm.conf exists, skipping creation..."
        )
        return
      end

      # get the current raid configuration
      out = SCR.Execute(
        path(".target.bash_output"),
        "/usr/bin/chroot #{Installation.destdir.shellescape} mdadm -Ds"
      )
      if Ops.get_integer(out, "exit", -1).nonzero?
        Builtins.y2error(
          "Error occurred while getting raid configuration: %1",
          out
        )
        return
      end
      # There's no current raid configuration, no reason to create that file, bug #169710
      if Ops.get_string(out, "stdout", "") == ""
        Builtins.y2milestone(
          "No raid is currently configured, skipping file creation..."
        )
        return
      end

      # File format defined in bug #146304
      mdadm_content = Ops.add(
        Ops.add("DEV partitions\n", Ops.get_string(out, "stdout", "")),
        "\n"
      )

      Builtins.y2milestone("/etc/mdadm.conf doesn't exist, creating it")
      if !SCR.Write(path(".target.string"), mdamd_configfile, mdadm_content)
        Builtins.y2error(
          "Error occurred while creating /etc/mdadm.conf with content '%1'",
          mdadm_content
        )
      end

      nil
    end

    #  Load all network modules.  The package sysconfig requires this during
    #  update.
    def load_network_modules
      cards = Convert.convert(
        SCR.Read(path(".probe.netcard")),
        from: "any",
        to:   "list <map>"
      )

      Builtins.foreach(cards) do |card|
        drivers = Ops.get_list(card, "drivers", [])
        one_active = false
        Builtins.foreach(drivers) do |driver|
          one_active = true if Ops.get_boolean(driver, "active", false)
        end
        if !one_active
          name = Ops.get_string(drivers, [0, "modules", 0, 0], "")
          if name != ""
            ModuleLoading.Load(name, "", "Linux", "", Linuxrc.manual, true)
          end
        end
      end

      nil
    end

    # Calls a local command and returns if successful
    def LocalCommand(command)
      cmd = Convert.to_map(WFM.Execute(path(".local.bash_output"), command))
      Builtins.y2milestone("Command %1 returned: %2", command, cmd)

      return true if Ops.get_integer(cmd, "exit", -1).zero?

      if Ops.get_string(cmd, "stderr", "") != ""
        Builtins.y2error("Error: %1", Ops.get_string(cmd, "stderr", ""))
      end
      false
    end
  end
end

Yast::InstKickoffClient.new.main
