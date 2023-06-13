Name:           rockpi-sata
Version:        0.14
Release:        1%{?dist}
Summary:        Rockpi SATA Hat
BuildArch:      noarch

License:        GPLv3
URL:            https://github.com/akgnah/rockpi-sata
Source0:        %{name}-%{version}.tar.gz

Requires:       python3
BuildRequires: systemd-rpm-macros

%description
Scripts for the Rockpi Quad Sata controller using overlays for Raspberry Pi 4

%prep
%setup -q

%install
rm -rf %{buildroot}

mkdir -p %{buildroot}%{_bindir}/rockpi-sata/fonts
mkdir -p %{buildroot}%{_unitdir}
mkdir -p %{buildroot}%{_sysconfdir}

install -m 0644 usr/bin/rockpi-sata/*.py %{buildroot}%{_bindir}/rockpi-sata/
install -m 0644 usr/bin/rockpi-sata/fonts/*.ttf %{buildroot}%{_bindir}/rockpi-sata/fonts/
install -m 0644 etc/rockpi-sata.conf %{buildroot}%{_sysconfdir}/
install -m 0644 lib/systemd/system/rockpi-sata.service %{buildroot}%{_unitdir}

%post
%systemd_post pigpiod.service
%systemd_post rockpi-sata.service

%preun
%systemd_preun rockpi-sata.service
%systemd_preun pigpiod.service
rm -rf /usr/bin/rockpi-sata/__pycache__/

%clean
rm -rf $RPM_BUILD_ROOT

%files
%{_bindir}/rockpi-sata/main.py
%{_bindir}/rockpi-sata/fan.py
%{_bindir}/rockpi-sata/misc.py
%{_bindir}/rockpi-sata/oled.py

%{_bindir}/rockpi-sata/fonts/DejaVuSansMono-Bold.ttf
%{_bindir}/rockpi-sata/fonts/DejaVuSansMono.ttf
%{_bindir}/rockpi-sata/fonts/NotoSansMono-Bold.ttf
%{_bindir}/rockpi-sata/fonts/NotoSansMono-Regular.ttf

%{_sysconfdir}/rockpi-sata.conf

%{_unitdir}/rockpi-sata.service
