#
# Makefile.am for y2a_targetpkg/testsuite
#

SUBDIRS = ag_targetpkg.test config lib tests

AM_CXXFLAGS = -DY2LOG=\"agent-targetpkg\"

PACKAGE = ag_targetpkg
AUTOMAKE_OPTIONS = dejagnu

INCLUDES = -I$(includedir)

noinst_PROGRAMS = runag_targetpkg

runag_targetpkg_SOURCES = runag_targetpkg.cc

LDADD = -lscr -ly2 -lycp

LDFLAGS = -L$(libdir)				\
	-Xlinker --whole-archive		\
	$(plugindir)/libpy2stdio.la		\
	$(plugindir)/libpy2script.la		\
	$(srcdir)/../src/libpy2ag_targetpkg.la	\
	-Xlinker --no-whole-archive

CLEANFILES = tmp.* *.bak *.log *.sum

tmpclean:
	rm -f tmp.*

runag_targetpkg.o: $(srcdir)/../src/libpy2ag_targetpkg.la
