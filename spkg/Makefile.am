#
# Makefile.am for modules/y2c_spkg
#

SUBDIRS = src doc

VERSION = $(shell cat $(srcdir)/VERSION)

RPMNAME = $(shell cat $(srcdir)/RPMNAME)

EXTRA_DIST = COPYRIGHT.english COPYRIGHT.french COPYRIGHT.german \
	VERSION README RPMNAME MAINTAINER $(RPMNAME).spec.in

AUTOMAKE_OPTIONS = foreign 

$(RPMNAME)-$(VERSION).tar.gz: dist

CLEANFILES = $(RPMNAME).kdoc

MAINTAINERCLEANFILES = package/$(RPMNAME)-$(VERSION).tar.gz package/$(RPMNAME).spec

package: $(RPMNAME)-$(VERSION).tar.gz
	mv $(RPMNAME)-$(VERSION).tar.gz package
