# Makefile.am for packager/src/modules

YCPCFLAGS = -I . -M .

module_DATA = $(wildcard [A-Z]*.ycp [A-Z]*.pm)
EXTRA_DIST = $(module_DATA)

packager:
	ln -sf ../include packager

ycpchook = packager

include $(top_srcdir)/Makefile.am.common
