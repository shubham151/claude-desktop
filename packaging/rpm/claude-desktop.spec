Name:           claude-desktop
Version:        0.0.0
Release:        1%{?dist}
Summary:        Claude Desktop for Linux (unofficial repackage)
License:        Proprietary
URL:            https://github.com/shubham151/claude-desktop
Requires:       electron, gtk3, libnotify, nss, libXScrnSaver, libXtst, xdg-utils
BuildArch:      x86_64

%description
Unofficial Linux repackage of Anthropic's Claude Desktop. The official
macOS app.asar is repacked with a Linux-compatible native-bindings
shim and launched via system Electron.

%install
# Files are staged into %{buildroot} by build.sh before rpmbuild runs.
# Nothing to do here.

%files
%defattr(-,root,root,-)
/usr/lib/claude-desktop/
/usr/bin/claude-desktop
/usr/share/applications/claude-desktop.desktop
/usr/share/icons/hicolor/

%changelog
