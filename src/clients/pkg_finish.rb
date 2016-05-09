# encoding: utf-8

# File:
#  pkg_finish.ycp
#
# Module:
#  Step of base installation finish
#
# Authors:
#  Jiri Srain <jsrain@suse.cz>
#
# $Id$
#
require "packager/clients/pkg_finish"
Yast::PkgFinishClient.new.run
