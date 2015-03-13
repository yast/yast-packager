#
# spec file for package yast2-packager
#
# Copyright (c) 2013 SUSE LINUX Products GmbH, Nuernberg, Germany.
#
# All modifications and additions to the file contributed by third parties
# remain the property of their copyright owners, unless otherwise agreed
# upon. The license for this file, and modifications and additions to the
# file, is the same license as for the pristine package itself (unless the
# license for the pristine package is not an Open Source License, in which
# case the license is the MIT License). An "Open Source License" is a
# license that conforms to the Open Source Definition (Version 1.9)
# published by the Open Source Initiative.

# Please submit bugfixes or comments via http://bugs.opensuse.org/
#


Name:           yast2-packager
Version:        3.1.64
Release:        0

BuildRoot:      %{_tmppath}/%{name}-%{version}-build
Source0:        %{name}-%{version}.tar.bz2

Url:            https://github.com/kobliha/yast-packager
Group:	        System/YaST
License:        GPL-2.0+
BuildRequires:	yast2-country-data yast2-xml update-desktop-files yast2-testsuite
BuildRequires:  yast2-devtools >= 3.1.10
BuildRequires:  yast2-storage
BuildRequires:  yast2_theme
BuildRequires:  rubygem(rspec)

# HwDetection
BuildRequires: yast2 >= 3.1.19

# "growonly" in Pkg::SetTargetDU()
BuildRequires:	yast2-pkg-bindings >= 3.1.19

# Newly added RPM
Requires:	yast2-country-data >= 2.16.3

# "growonly" in Pkg::SetTargetDU()
Requires:	yast2-pkg-bindings >= 3.1.19

# Fixed .proc.cmdline agent
Requires: yast2 >= 3.1.89

# unzipping license file
Requires:	unzip

# HTTP, FTP, HTTPS modules (inst_productsources.ycp)
Requires:	yast2-transfer

# XML module (inst_productsources.ycp)
Requires:	yast2-xml

# Bugzilla #305503 - storing/checking MD5 of licenses
Requires:	/usr/bin/md5sum

# .process agent
Requires: 	yast2-core >= 2.16.35

# setenv() builtin
Conflicts:	yast2-core < 2.15.10

# NotEnoughMemory-related functions moved to misc.ycp import-file
Conflicts:	yast2-add-on < 2.15.15

# One of libyui-qt-pkg, libyui-ncurses-pkg, libyui-gtk-pkg
Requires:	libyui_pkg

# ensure that 'checkmedia' is on the medium
Recommends:	checkmedia

Provides:	yast2-config-package-manager
Obsoletes:	yast2-config-package-manager
Provides:	y2t_spkg y2t_inst-packages y2pkginf y2c_spkg
Obsoletes:	y2t_spkg y2t_inst-packages y2pkginf y2c_spkg
Provides:	yast2-trans-package-manager yast2-trans-inst-packages
Obsoletes:	yast2-trans-package-manager yast2-trans-inst-packages
# force *-webpin subpackage removal at upgrade
Obsoletes:      yast2-packager-webpin < %version

Requires:       yast2-ruby-bindings >= 1.0.0
Summary:	YaST2 - Package Library


%package devel-doc
Requires:       yast2-packager = %version
Group:          System/YaST
Summary:        YaST2 - Development Documentation

%description
This package contains the libraries and modules for software management.

%description devel-doc
This package contains development documentation for using the API
provided by yast2-packager package.

%prep
%setup -n %{name}-%{version}

%build
%yast_build

%install
%yast_install

%suse_update_desktop_file yast2-packager

%post
%desktop_database_post

%postun
%desktop_database_postun


%files
%defattr(-,root,root)
%dir %{yast_yncludedir}/checkmedia
%dir %{yast_yncludedir}/packager
%{yast_yncludedir}/checkmedia/*
%{yast_yncludedir}/packager/*
%{yast_clientdir}/*.rb
%{yast_moduledir}/*
%{yast_desktopdir}/*.desktop
%{_datadir}/applications/*.desktop
%{yast_scrconfdir}/*
%{yast_execcompdir}/servers_non_y2/ag_*
%dir %{yast_docdir}
%doc %{yast_docdir}/COPYING

%files devel-doc
%doc %{yast_docdir}/autodocs


