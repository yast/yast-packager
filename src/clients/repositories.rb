# encoding: utf-8

# Module: 		repositories.ycp
#
# Author:		Cornelius Schumacher <cschum@suse.de>
#			Ladislav Slezak <lslezak@suse.cz>
#
# Purpose:
# Adding, removing and prioritizing of repositories for packagemanager.
#
# $Id$
#

require "packager/clients/repositories"
Yast::RepositoriesClient.new.main
