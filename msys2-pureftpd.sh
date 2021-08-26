#!/usr/bin/bash

flog=/var/log/ftpd.log
FTPD=pure-ftpd
ip=192.168.0.1,21
[ ! -z ${ip} ] && ip=-S${ip}
FTPDa="-4 -A -c8 -D -fnone -g/var/run/${FTPD}.pid -H -lpuredb:/etc/pureftpd.pdb -u1 ${ip}"
kill -sigterm `cat /var/run/${FTPD}.pid`
pacman -Sy
cd ~
if [ "$MSYSTEM" == "MSYS" ] ; then
 pacman -S cygrunsrv --needed 
 pacman -S git --needed
 pacman -S base-devel --needed
 pacman -S libcrypt-devel --needed
 pacman -S libiconv-devel --needed
 pacman -S openssl-devel --needed
 pacman -S libgnutls-devel --needed
 if [ ! -d libsodium ] ; then
  git clone https://github.com/proftpd/proftpd.git
  cd libsodium
  ./autogen.sh
  ./configure&&make&&make install
  cd ~
 fi
 if [ -d ${FTPD} ] ; then
  cd ${FTPD}
  git pull
 else
  git clone https://github.com/jedisct1/pure-ftpd.git
  cd ${FTPD}
 fi
 ./autogen.sh
 make clean
 tls=--with-tls
 ssl=" -lssl -lcrypto -lz"
 [ -z ${tls} ] && ssl=
 env LDFLAGS="-static -s ${ssl}"  ./configure --sbindir=/usr/bin\
 --without-inetd --without-iplogging --without-humor --without-pam\
 --with-nonroot --with-minimal --with-rfc2640 --with-puredb --with-virtualchroot ${tls}&&make install-strip
 if [ ! -f /etc/pureftpd.pdb ]; then 
  pure-pw useradd ${USER} -d ${HOME} -m
 fi
 echo Please test ${FTPD} then run mingw32.exe or mingw64.exe as Administrator and run this $0 for install ${FTPD} as Windows service 
 ${FTPD} ${FTPDa}&
else
 echo Installation
 pacman -S ${MINGW_PACKAGE_PREFIX}-editrights --needed 
 pacman -S ${MINGW_PACKAGE_PREFIX}-iconv --needed 
 #exit of error
 set -e
 echo Configuration
 PRIV_USER=ftpd_server
 PRIV_NAME="Privileged user for ftpd"
 UNPRIV_USER=ftp
 UNPRIV_NAME="Privilege separation user for ftpd"
 EMPTY_DIR=/var/empty
 if [ "${LANG:0:3}" == "en_" ]; then
  log="cat ${flog}"
 else
  log="iconv -f $(cmd /c chcp|tr -dc [:digit:]) -t $(echo $LANG|sed -e 's/^[^.]*.//') ${flog}"
 fi
 echo Check installation sanity
 if ! ${MSYSTEM_PREFIX}/bin/editrights -h >/dev/null; then
  echo "ERROR: Missing 'editrights'. Try: pacman -S ${MINGW_PACKAGE_PREFIX}-editrights."
  exit 1
 fi
 if ! cygrunsrv -v >/dev/null; then
  echo "ERROR: Missing 'cygrunsrv'. Try: run this $0 from msys2_shell.cmd then run mingw32.exe or mingw64.exe as Administrator and run this $0 for install ${FTPD} as Windows service"
  exit 1
 fi
 if ! ${FTPD} -h >/dev/null; then
  echo "ERROR: Missing ${FTPD}. Try: run this $0 from msys2_shell.cmd then run mingw32.exe or mingw64.exe as Administrator and run this $0 for install ${FTPD} as Windows service"
  exit 1
 fi
 # Some random password; this is only needed internally by cygrunsrv and
 # is limited to 14 characters by Windows (lol)
 tmp_pass="$(tr -dc 'a-zA-Z0-9' < /dev/urandom | dd count=14 bs=1 2>/dev/null)"
 echo "Add or update user ${PRIV_USER}"|tee ${flog}
 add="$(if ! net user "${PRIV_USER}" >/dev/null; then echo "//add"; fi)"
 if ! net user "${PRIV_USER}" "${tmp_pass}" ${add} //fullname:"${PRIV_NAME}" \
    //homedir:"$(cygpath -w ${EMPTY_DIR})" //yes >>${flog} 2>&1; then
  ${log}
  echo "ERROR: Unable to create Windows user ${PRIV_USER}"|tee -a ${flog}
  exit 1
 fi
 echo "Add user ${PRIV_USER} to the Administrators group if necessary"|tee -a ${flog}
 admingroup="$(mkgroup -l | awk -F: '{if ($2 == "S-1-5-32-544") print $1;}')"
 if ! (net localgroup "${admingroup}" | grep -q '^'"${PRIV_USER}"'$'); then
  if ! net localgroup "${admingroup}" "${PRIV_USER}" //add >>${flog} 2>&1; then
   ${log}
   echo "ERROR: Unable to add user ${PRIV_USER} to group ${admingroup}"|tee -a ${flog}
   exit 1
  fi
 fi
 if [ ! -z ${add} ]; then
  echo Infinite passwd expiry
  #passwd -e "${PRIV_USER}"
  wmic UserAccount where Name="'${PRIV_USER}'" set PasswordExpires=False
 fi
 echo "Set required privileges fo user ${PRIV_USER}"|tee -a ${flog}
 for flag in SeAssignPrimaryTokenPrivilege SeCreateTokenPrivilege \
     SeTcbPrivilege SeDenyRemoteInteractiveLogonRight SeServiceLogonRight; do
  if ! ${MSYSTEM_PREFIX}/bin/editrights -a "${flag}" -u "${PRIV_USER}"; then
   echo "ERROR: Unable to give ${flag} rights to user ${PRIV_USER}"|tee -a ${flog}
   exit 1
  fi
 done
 net user "${PRIV_USER}" >>${flog} 2>&1
 echo "Add or update user ${UNPRIV_USER}"|tee -a ${flog}
 add="$(if ! net user "${UNPRIV_USER}" >/dev/null; then echo "//add"; fi)"
 if ! net user "${UNPRIV_USER}" ${add} //fullname:"${UNPRIV_NAME}" \
    //homedir:"$(cygpath -w ${EMPTY_DIR})" //active:no >>${flog} 2>&1; then
  ${log}
  echo "ERROR: Unable to create Windows user ${PRIV_USER}"|tee -a ${flog}
  exit 1
 fi
 net user "${UNPRIV_USER}" >>${flog} 2>&1
 echo Add or update /etc/passwd entries
 if [ ! -f /etc/passwd ]; then
  # First run. Add current user to passwd and group
  mkpasswd -c > /etc/passwd
  mkgroup -c >  /etc/group
  mkgroup -l >> /etc/group
 fi
 for u in "${PRIV_USER}" "${UNPRIV_USER}"; do
  sed -i -e '/^'"${u}"':/d' /etc/passwd
  SED='/^'"${u}"':/s?^\(\([^:]*:\)\{5\}\).*?\1'"${EMPTY_DIR}"':/bin/false?p'
  mkpasswd -l -u "${u}" | sed -e 's/^[^:]*+//' | sed -ne "${SED}" >> /etc/passwd
 done
 echo Finally, register service with cygrunsrv and start it
 cygrunsrv -R ftpd || true
 cygrunsrv -I ftpd -d "MSYS2 ftpd" -p \
           /usr/bin/${FTPD}.exe -a "${FTPDa}" -y tcpip -u "${PRIV_USER}" -w "${tmp_pass}"
 echo "The FTP service should start automatically when Windows is rebooted. You can"|tee -a ${flog}
 echo "manually restart the service by running 'net stop ftpd&net start ftpd'"|tee -a ${flog}
 if ! net start ftpd >>${flog} 2>&1; then
  ${log}
  echo "ERROR: Unable to start ftpd service"|tee -a ${flog}
  exit 1
 fi
 ${log}
fi