#!/bin/sh
#
# CHAMPS - CHrooted Apache MySQL PHP System
# champs.sh - CHAMPS build/control utility
#

CHROOT="/chroot"
PRISON="${CHROOT}/prison"
JAIL="${CHROOT}/jail"
DATESTAMP=`date +%Y%m%d-%H%M`

GROUP=daemon
HTTPD_USER=apache
MYSQL_USER=mysql

usage()
{
	echo ""
	echo "Usage:"
	echo "	champ build PROGRAM"
	echo "	champ install PROGRAM"
	echo "  champ [start|stop|status|restart|graceful|configtest|mount] /cell"
	echo ""

	exit 0
}

add_passwd ()
{
	ID=$1
	TGT=$2
	if [ `egrep -e "^${ID}:" ${TGT} | wc -l` -lt 1 ]
	then
		egrep -e "^${ID}:" /etc/passwd >> ${TGT}
	fi
}


add_group ()
{
	ID=$1
	TGT=$2
	if [ `egrep -e "^${ID}:" ${TGT} | wc -l` -lt 1 ]
	then
		egrep -e "^${ID}:" /etc/group >> ${TGT}
	fi
}


build_httpd ()
{
	cd ${SOURCE}
	if [ ! -f httpd.spec ]; then
		fail "No spec file found"
	fi
	VERSION=`grep Version: httpd.spec | awk '{print $2}'`

	TARGET=${JAIL}/httpd-${VERSION}_${DATESTAMP}
	if [ -d ${TARGET} ]; then
		fail "${TARGET} should not exist, but it does"
	fi

	if [ -f Makefile ]; then
		echo "Resetting..."
		make distclean
	fi

	if [ ! -f configure ]; then
		fail "No configuration program found"
	fi
	echo "Configuring..."
	#./configure --prefix=/ --bindir=/bin --sbindir=/sbin --libexecdir=/libexec --datadir=/var/www --sysconfdir=/etc --localstatedir=/var --libdir=/lib -with-mm=prefork --enable-dav=static --enable-expires=static --enable-rewrite=static --enable-security=static --enable-so --enable-ssl=static --enable-proxy=static --enable-static-support \
	./configure --prefix=/ --bindir=/bin --sbindir=/sbin --libexecdir=/libexec --datadir=/var/www --sysconfdir=/etc --localstatedir=/var --libdir=/lib -with-mm=prefork --enable-mods-static=most --enable-static-support \
	--with-ssl=/chroot/jail/openssl-1.0.1g-20140527-2118 \
	--with-included-apr --with-pcre=/chroot/src/httpd-2.4.9/srclib/pcre
	#--with-module=proxy:mod_security.c

	echo "Making..."
	make || fail "Make failed"

	echo "Installing..."
	make DESTDIR=${TARGET} install

	sed -i "s|/var/www/build|${TARGET}/var/www/build|" ${TARGET}/bin/apxs

	CONF_MK=${TARGET}/var/www/build/config_vars.mk
	export CONF_MK
	echo "sbindir = ${TARGET}/sbin" >> $CONF_MK
	echo "includedir = ${TARGET}/include" >> $CONF_MK
	echo "APR_BINDIR = ${TARGET}/bin" >> $CONF_MK
	echo "APR_CONFIG = ${TARGET}/bin/apr-1-config" >> $CONF_MK
	echo "APU_BINDIR = ${TARGET}/bin" >> $CONF_MK
	echo "APU_CONFIG = ${TARGET}/bin/apu-1-config" >> $CONF_MK

	echo "Done:"
	echo ${TARGET}
}


build_mod_python()
{
	if [ ! -f ${HTTPD}/sbin/httpd ]; then
		fail "${HTTPD} does not contain sbin/httpd"
	fi

	cd ${SOURCE}

#	if [ ! -f main/php_version.h ]; then
#		fail "No version header file found"
#	fi
#	VERSION=`grep -m 1 PHP_VERSION main/php_version.h | awk '{print $3}' | sed 's/"//g'`

	TARGET=${JAIL}/mod_python-${VERSION}_${DATESTAMP}
	if [ -d ${TARGET} ]; then
		fail "${TARGET} should not exist, but it does"
	fi

	# need this so that apxs works... 
	LD_LIBRARY_PATH=${HTTPD}/lib:${LD_LIBRARY_PATH}
	export LD_LIBRARY_PATH

	if [ -f Makefile ]; then
		echo "Resetting..."
		make distclean
	fi

	if [ ! -f configure ]; then
		fail "No configuration program found"
	fi
	echo "Configuring..."
	./configure --prefix=/ --bindir=/bin --sbindir=/sbin --libexecdir=/libexec --datadir=/var/www --sysconfdir=/etc --localstatedir=/var --libdir=/lib --disable-cli --disable-cgi --enable-static=ALL --with-gd --with-jpeg-dir=/usr/lib --with-png-dir=/usr/lib --with-zlib-dir=/usr/lib --with-xpm-dir=/usr/X11R6/lib --enable-gd-native-ttf --with-dom --with-gettext --enable-bcmath --enable-exif --with-gmp --enable-mbstring=all --with-openssl --with-config-file-path=/etc --with-config-file-scan-dir=/etc --with-apxs2=${HTTPD}/bin/apxs --with-mysql=${MYSQL}
	
	echo "Making..."
	make || fail

	echo "Installing..."
	mkdir -p ${TARGET}/etc ${TARGET}/lib
	install -c -m 444 php.ini-production ${TARGET}/etc/php.ini
	install -c -m 555 ./libs/libphp5.so ${TARGET}/lib/
	INSTALL_ROOT=${TARGET} make install-build install-headers

	install -c -m 755 ./scripts/php-config ${TARGET}/bin/
}


build_mysql()
{
	cd ${SOURCE}
	if [ ! -f configure ]; then
		fail "No configuration program found"
	fi
	VERSION=`grep '^ VERSION=' configure | awk -F= '{print $2}'`

	TARGET=${JAIL}/mysql-${VERSION}_${DATESTAMP}
	if [ -d ${TARGET} ]; then
		fail "${TARGET} should not exist, but it does"
	fi

	if [ -f Makefile ]; then
		echo "Resetting..."
		make distclean
	fi

	echo "Configuring..."
	./configure --prefix=/ --libexecdir=/sbin --without-debug --without-docs --without-man --with-charset=latin1 --with-collation=latin1_general_ci --with-extra-charsets=complex --with-libwrap --enable-local-infile --enable-thread-safe-client --without-mysqlmanager 
	# --without-bench, --with-berkeley-db, --with-innodb, --without-extra-tools

	echo "Making..."
	make || fail

	echo "Installing..."
	make DESTDIR=${TARGET} install-strip
}


build_php()
{
	if [ ! -f ${HTTPD}/sbin/httpd ]; then
		fail "${HTTPD} does not contain sbin/httpd"
	fi

	if [ ! -f ${MYSQL}/sbin/mysqld ]; then
		fail "${MYSQL} does not contain sbin/mysqld"
	fi

	cd ${SOURCE}

	if [ ! -f main/php_version.h ]; then
		fail "No version header file found"
	fi
	VERSION=`grep -m 1 PHP_VERSION main/php_version.h | awk '{print $3}' | sed 's/"//g'`

	TARGET=${JAIL}/php-${VERSION}_${DATESTAMP}
	if [ -d ${TARGET} ]; then
		fail "${TARGET} should not exist, but it does"
	fi

	# need this so that apxs works... 
	LD_LIBRARY_PATH=${HTTPD}/lib:${LD_LIBRARY_PATH}
	export LD_LIBRARY_PATH

	if [ -f Makefile ]; then
		echo "Resetting..."
		make distclean
	fi

	if [ ! -f configure ]; then
		fail "No configuration program found"
	fi
	echo "Configuring..."
	./configure --prefix=/ --bindir=/bin --sbindir=/sbin --libexecdir=/libexec --datadir=/var/www --sysconfdir=/etc --localstatedir=/var --libdir=/lib --disable-cli --disable-cgi --enable-static=ALL --with-curl --with-dom --with-gd --with-jpeg-dir=/usr/lib --with-png-dir=/usr/lib --with-zlib-dir=/usr/lib --with-xpm-dir=/usr/X11R6/lib --enable-gd-native-ttf --with-gettext --with-mcrypt --enable-bcmath --enable-exif --with-gmp --enable-mbstring=all --with-openssl --with-config-file-path=/etc --with-config-file-scan-dir=/etc --with-apxs2=${HTTPD}/bin/apxs --with-mysql=${MYSQL} --with-pdo-mysql=${MYSQL} --with-freetype-dir=/usr/include/freetype2/freetype/ --enable-zip \
	--with-openssl=/chroot/jail/openssl-1.0.1g-20140527-2118 
	
	echo "Making..."
	make || fail

	echo "Installing..."
	mkdir -p ${TARGET}/etc ${TARGET}/lib
	install -c -m 444 php.ini-production ${TARGET}/etc/php.ini
	install -c -m 555 ./libs/libphp5.so ${TARGET}/lib/
	INSTALL_ROOT=${TARGET} make install-build install-headers

	install -c -m 755 ./scripts/php-config ${TARGET}/bin/
	perl -pi -e 's/prefix="\/"$/prefix="${TARGET}"/' ${TARGET}/bin/php-config

	sed -i "s|mysql.default_socket =|mysql.default_socket = /var/share/mysql/sock|" ${TARGET}/etc/php.ini
}


copy_libs()
{
	BIN=$1
	TGT=$2
	for i in `ldd ${BIN}|awk -F"=>" {'print $2'}|awk -F" " {'print $1'}|grep -v '^('`
	do
		install -c -g ${GROUP} -m 550 $i ${TGT}
	done

	for i in `ldd ${BIN}|awk -F" " {'print $1'}|grep "^/"`
	do
		install -c -g ${GROUP} -m 550 $i ${TGT}
	done
} 


fail ()
{
	echo $1
	exit 1
}


install_httpd()
{
	if [ ! -f ${SOURCE}/sbin/httpd ]; then
		fail "${SOURCE} does not contain sbin/httpd"
	fi

	if [ -f ${TARGET}/sbin/httpd ]; then
	# UPDATE ONLY
		echo "Updating binary files..."
		install -c -m 400 ${SOURCE}/etc/magic		${TARGET}/etc
		install -c -m 400 ${SOURCE}/etc/mime.types	${TARGET}/etc
		install -c -m 500 ${SOURCE}/sbin/httpd		${TARGET}/sbin

		echo "Updating library files..."
		copy_libs ${TARGET}/sbin/httpd ${TARGET}/lib
		install -c -g ${GROUP} -m 550 ${SOURCE}/lib/{libapr-1.so.0,libaprutil-1.so.0} ${TARGET}/lib
		install -c -g ${GROUP} -m 550 /lib/{libnss_dns.so.2,libnss_files.so.2,libnss_compat.so.2} ${TARGET}/lib

	else
	# NEW INSTALL
		echo "Creating directory structure for prison cell..."
		for i in bin dev etc lib sbin var/logs var/share var/www/error var/www/htdocs var/www/icons
		do
			make_dir ${TARGET}/$i
		done

		echo "Installing config files..."
		install -c -m 600 ${SOURCE}/etc/httpd.conf	${TARGET}/etc
		sed -i "s|User daemon|User ${HTTPD_USER}|"	${TARGET}/etc/httpd.conf
		sed -i "s|Group daemon|Group ${GROUP}|"		${TARGET}/etc/httpd.conf

		echo "Installing binary files..."
		install -c -m 400 ${SOURCE}/etc/magic		${TARGET}/etc
		install -c -m 400 ${SOURCE}/etc/mime.types	${TARGET}/etc
		install -c -m 500 ${SOURCE}/sbin/httpd		${TARGET}/sbin

		echo "Installing html/image files..."
		install -c -g ${GROUP} -m 550 ${SOURCE}/var/www/error/* ${TARGET}/var/www/error
		install -c -g ${GROUP} -m 550 ${SOURCE}/var/www/icons/* ${TARGET}/var/www/icons

		echo "CHAMPS, ${DATESTAMP}" > ${TARGET}/var/www/htdocs/index.html

		echo "Installing library files..."
		copy_libs ${TARGET}/sbin/httpd ${TARGET}/lib
		install -c -g ${GROUP} -m 550 ${SOURCE}/lib/{libapr-1.so.0,libaprutil-1.so.0} ${TARGET}/lib
		install -c -g ${GROUP} -m 550 /lib/{libnss_dns.so.2,libnss_files.so.2,libnss_compat.so.2} ${TARGET}/lib

		echo "Installing misc files..."
		install -c -g ${GROUP} -m 550 /bin/false ${TARGET}/bin
		install -c -g ${GROUP} -m 550 /etc/{localtime,nsswitch.conf,hosts} ${TARGET}/etc

		echo "Creating character devices..."
		mknod -m 666 ${TARGET}/dev/null c 1 3
		mknod -m 666 ${TARGET}/dev/random c 1 8
		mknod -m 444 ${TARGET}/dev/urandom c 1 9
		mknod -m 666 ${TARGET}/dev/zero c 1 5

		echo "Creating prison config files..."
		add_passwd root ${TARGET}/etc/passwd
		add_group root  ${TARGET}/etc/group

		add_passwd ${HTTPD_USER} ${TARGET}/etc/passwd
		add_group ${GROUP} ${TARGET}/etc/group

		echo "DONE!"
		echo "Please edit ${TARGET}/etc/httpd.conf"
	fi
}


install_mysql()
{
	if [ ! -f ${SOURCE}/sbin/mysqld ]; then
		fail "${SOURCE} does not contain sbin/mysqld"
	fi

	if [ -f ${TARGET}/sbin/mysqld ]; then
	# UPDATE ONLY
		echo "Updating binary files..."
		install -c -m 500 ${SOURCE}/sbin/mysqld ${TARGET}/sbin
		install -c -g ${GROUP} -m 550 ${SOURCE}/share/mysql/charsets/* ${TARGET}/share/mysql/charsets
		install -c -g ${GROUP} -m 550 ${SOURCE}/share/mysql/english/* ${TARGET}/share/mysql/

		echo "Updating library files..."
		copy_libs ${TARGET}/sbin/mysqld ${TARGET}/lib
		install -c -g ${GROUP} -m 550 /lib/{libnss_dns.so.2,libnss_files.so.2,libnss_compat.so.2} ${TARGET}/lib

	else
	# NEW INSTALL
		echo "Creating directory structure for prison cell..."
		for i in bin etc lib sbin share/mysql/charsets var/log var/mysql var/share/mysql var/tmp
		do
			make_dir ${TARGET}/$i
		done

		for i in var/log var/share/mysql var/tmp
		do
			chgrp ${GROUP} ${TARGET}/$i
			chmod 770 ${TARGET}/$i
		done

		chmod 700 ${TARGET}/var/mysql

		echo "Installing binary files..."
		install -c -m 500 ${SOURCE}/sbin/mysqld ${TARGET}/sbin
		install -c -g ${GROUP} -m 550 ${SOURCE}/share/mysql/charsets/* ${TARGET}/share/mysql/charsets
		install -c -g ${GROUP} -m 550 ${SOURCE}/share/mysql/english/* ${TARGET}/share/mysql/

		echo "Installing library files..."
		copy_libs ${TARGET}/sbin/mysqld ${TARGET}/lib
		install -c -g ${GROUP} -m 550 /lib/{libnss_dns.so.2,libnss_files.so.2,libnss_compat.so.2} ${TARGET}/lib

		echo "Installing misc files..."
		install -c -g ${GROUP} -m 550 /bin/false ${TARGET}/bin
		install -c -g ${GROUP} -m 550 /etc/{localtime,nsswitch.conf,hosts} ${TARGET}/etc

		echo "Installing config files..."
		add_passwd root ${TARGET}/etc/passwd
		add_group root ${TARGET}/etc/group

		add_passwd ${MYSQL_USER} ${TARGET}/etc/passwd
		add_group ${GROUP} ${TARGET}/etc/group

		echo "Installing permissions databases..."
		LOG=/tmp/mysql_install_db.`date +%s`.log
		${SOURCE}/bin/mysql_install_db --no-defaults --basedir=${SOURCE} --datadir=${TARGET}/var/mysql --tmpdir=/tmp --language=${TARGET}/share/mysql --character-sets-dir=${TARGET}/share/mysql/charsets --user=root > ${LOG} 2>&1

		if [ $? -gt 0 ]; then
			cat ${LOG}
			fail "FAILED! - See: ${LOG}"
		else
			chown -R ${MYSQL_USER}:${GROUP} ${TARGET}/var/mysql
			echo "DONE! Remember to set your MySQL root password (after starting)!"
			echo
			echo "This should do it:"
			echo "LD_LIBRARY_PATH=\${LD_LIBRARY_PATH}:${SOURCE}/lib/mysql/ ${SOURCE}/bin/mysqladmin --no-defaults --socket=${TARGET}/var/share/mysql/sock -u root password 'new-password'"
			rm ${LOG}
		fi
	fi
}


install_php()
{
	if [ ! -f ${SOURCE}/etc/php.ini ]; then
		fail "${SOURCE} does not contain etc/php.ini"
	fi
	
	if [ ! -f ${TARGET}/sbin/httpd ]; then
		fail "${TARGET} does not contain sbin/httpd"
	fi
	
	if [ ! -f ${TARGET}/etc/php.ini ]; then
		echo "Installing config file..."
		install -c -m 600 ${SOURCE}/etc/php.ini ${TARGET}/etc/php.ini
	fi

	echo "Installing library file..."
	install -c -m 550 ${SOURCE}/lib/libphp5.so ${TARGET}/lib

	echo "Installing library files..."
	copy_libs ${SOURCE}/lib/libphp5.so ${TARGET}/lib

	echo "DONE!"
	echo
	echo "Make sure that the following is in ${TARGET}/etc/httpd.conf:"
	echo
	echo "LoadModule php5_module lib/libphp5.so"
	echo "AddType application/x-httpd-php .php"
}


make_dir()
{
	DIR=$1
	if [ ! -d ${DIR} ]
	then
		mkdir -m 755 -p ${DIR}
	fi
}


mount_dirs()
{
	SOURCE=$1
	if [ -f ${SOURCE}/etc/mount ]
	then
		cat ${SOURCE}/etc/mount | while read path; do
			MSRC=`echo $path | awk '{print $1}'`
			MTGT=`echo $path | awk '{print $2}'`
			make_dir ${SOURCE}/${MTGT}
			echo "mount ${MSRC} ${SOURCE}/${MTGT}"
			mount --bind ${MSRC} ${SOURCE}/${MTGT}
		done
	fi
}


query_for_path ()
{
	echo $1
	RV=0

	while [ 1 ]
	do
		read RV
		if [ ! -d ${RV} ]
		then
			echo $1
		else
			break
		fi
	done
}


umount_dirs()
{
	SOURCE=$1
	if [ -f ${SOURCE}/etc/mount ]
	then
		cat ${SOURCE}/etc/mount | while read path; do
			umount ${SOURCE}/${path}
		done
	fi
}


case $1 in
'build')
	query_for_path "Where is the source?"
	SOURCE=${RV}

	case $2 in
	'httpd')
		build_httpd
	;;
	'mod_python')
		query_for_path "Where is the httpd build?"
		HTTPD=${RV}
	
		build_mod_python
	;;
	'mysql')
		build_mysql
	;;
	'php')
		query_for_path "Where is the httpd build?"
		HTTPD=${RV}
		query_for_path "Where is the mysql build?"
		MYSQL=${RV}
	
		build_php
	;;
	*)
		fail "Don't know how to build that"
	;;
	esac
;;
'configtest')
	if [ $# -ne 2 ]; then
		usage
	fi

	if [ ! -d $2 ]; then
		fail "$2 is not a directory"
	fi

	SOURCE=$2

	if [ -f ${SOURCE}/sbin/httpd ]; then
		chroot ${SOURCE} /sbin/httpd -t
	else
		fail "Don't know how to configtest ${SOURCE}"
	fi
;;
'graceful')
	if [ $# -ne 2 ]; then
		usage
	fi

	if [ ! -d $2 ]; then
		fail "$2 is not a directory"
	fi

	SOURCE=$2

	if [ -f ${SOURCE}/sbin/httpd ]; then
		chroot ${SOURCE} /sbin/httpd -k graceful
	else
		fail "Don't know how to graceful ${SOURCE}"
	fi
;;
'install')
	query_for_path "Where is the source?"
	SOURCE=${RV}
	query_for_path "Where is the target?"
	TARGET=${RV}

	case $2 in
	'httpd')
		install_httpd
	;;
	'mysql')
		install_mysql
	;;
	'php')
		install_php
	;;
	*)
		fail "Don't know how to install $2"
	;;
	esac
;;
'mount')
	mount_dirs ${2}
;;
'restart')
	if [ $# -ne 2 ]; then
		usage
	fi

	if [ ! -d $2 ]; then
		fail "$2 is not a directory"
	fi

	SOURCE=$2

	if [ -f ${SOURCE}/sbin/httpd ]; then
		chroot ${SOURCE} /sbin/httpd -k restart
	else
		fail "Don't know how to restart ${SOURCE}"
	fi
;;
'start')
	if [ $# -ne 2 ]; then
		usage
	fi

	if [ ! -d $2 ]; then
		fail "$2 is not a directory"
	fi

	SOURCE=$2
	APPNAME=`basename ${SOURCE}`
	mount_dirs ${SOURCE}

	if [ -f ${SOURCE}/sbin/httpd ]; then
		chroot ${SOURCE} /sbin/httpd -k start -D ${APPNAME}

	elif [ -f ${SOURCE}/sbin/mysqld ]; then
		chroot ${SOURCE} /sbin/mysqld --no-defaults --basedir=/ --datadir=/var/mysql --tmpdir=/var/tmp --character-sets-dir=/share/mysql/charsets --language=/share/mysql --log=/var/log/mysqld.log --pid-file=/var/mysql/pid --skip-locking --skip-networking --socket=/var/share/mysql/sock --user=${MYSQL_USER} >> /dev/null 2>&1 &
	else
		fail "Don't know how to start ${SOURCE}"
	fi
;;
'status')
	if [ ! -d $2 ]; then
		fail "$2 is not a directory"
	fi

	SOURCE=$2
	APPNAME=`basename ${SOURCE}`

	if [ -f ${SOURCE}/sbin/httpd ]; then
		fail "No status for httpd"

	elif [ -f ${SOURCE}/sbin/mysqld ]; then
		fail "No status for mysqld"

	else
		fail "Don't know how to start ${SOURCE}"
	fi
;;
'stop')
	if [ ! -d $2 ]; then
		fail "$2 is not a directory"
	fi

	SOURCE=$2
	APPNAME=`basename ${SOURCE}`
	umount_dirs ${SOURCE}

	if [ -f ${SOURCE}/sbin/httpd ]; then
		chroot ${SOURCE} /sbin/httpd -k stop

	elif [ -f ${SOURCE}/sbin/mysqld ]; then
		kill `cat ${SOURCE}/var/mysql/pid`
	else
		fail "Don't know how to stop ${SOURCE}"
	fi
;;
*)
	usage
;;
esac

exit 1
