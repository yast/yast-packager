#
# Makefile.am for packager/libpkg/doc/autodocs
#

htmldir = $(docdir)/autodocs

html_DATA = index.html $(wildcard *.html)

CLEANFILES = $(html_DATA)

index.html: $(srcdir)/../../src/include/*.h $(srcdir)/../../src/include/pkg/*.h
	cd $(srcdir)/../../src/include && @ybindir@/ydoc libpkg *.h pkg/*.h
	mv -f $(srcdir)/../../src/include/*.html .
