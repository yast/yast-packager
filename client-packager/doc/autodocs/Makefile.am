#
# Makefile.am for packager/client-packager/doc/autodocs
#

htmldir = $(docdir)/packager/autodocs

html_DATA = index.html $(wildcard *.html)

CLEANFILES = $(html_DATA)

index.html: $(srcdir)/../../src/*.h
	cd $(srcdir)/../../src; @ybindir@/ydoc -p client-packager *.h
	mv -f $(srcdir)/../../src/*.html .
