#
# Makefile.am for y2a_targetpkg/src
#

plugin_LTLIBRARIES = libpy2ag_targetpkg.la
lib_LTLIBRARIES = liby2ag_targetpkg.la

liby2ag_targetpkg_la_SOURCES = 			\
	RpmDb.cc RpmDb.h			\
	TargetpkgAgentCalls.cc \
	TargetpkgAgent.cc TargetpkgAgent.h
liby2ag_targetpkg_la_LDFLAGS = -version-info 2:0

libpy2ag_targetpkg_la_SOURCES =			\
	$(liby2ag_targetpkg_la_SOURCES)		\
	Y2CCtargetpkgAgent.cc
libpy2ag_targetpkg_la_LDFLAGS = -version-info 2:0

INCLUDES = -I$(includedir)

