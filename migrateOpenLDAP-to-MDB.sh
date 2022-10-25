#!/bin/bash
#
# Some code & tips from : https://wiki.zionetrix.net/informatique:reseau:ldap:migration_bdb_hdb_mdb
#
# SPDX-License-Identifier: CC-BY-NC-SA-4.0
# License-Filename: LICENSE 
#
# vim: syntax=sh tabstop=4 shiftwidth=4 expandtab
LDIR="$( cd "$( dirname "$( readlink -f "${BASH_SOURCE[0]}" )" )" >/dev/null 2>&1 && pwd -P )"

echoerr() { echo "$@" 1>&2; }
TMPDIR=$(mktemp -d -t 'slapd-migrate-to-mdb.XXXXXX')
if [[ ! "$TMPDIR" || ! -d "$TMPDIR" ]]; then
    echoerr "Could not create temp dir"
    exit 1
fi
trap 'rm -rf "$TMPDIR"' EXIT

function checkDependencies () {
    local DEPENDENCIES=( 'sed' 'git' 'rsync' 'cat' 'grep' 'ldapmodify' 'slapschema' 'slaptest' 'slapcat' 'slapadd' )
    local MISSING_PKG=""
    for PACKAGE in "${DEPENDENCIES[@]}"
    do
        if ! command_exists "$PACKAGE"
        then
            MISSING_PKG="$MISSING_PKG $PACKAGE"
        fi
    done
    if [ -n "$MISSING_PKG" ]
    then
        echoerr ""
        echoerr "Missing commands : $MISSING_PKG"
        exit 1
    fi
}

function command_exists () {
    command -v "$1" >/dev/null 2>&1;
}

function patchCRC32 () {
    CRCBIN="$1"
    PATCHFILE="$TMPDIR/check_slapdd_crc32-python.patch"

cat << EOF > "$PATCHFILE"
diff --git a/check_slapdd_crc32 b/check_slapdd_crc32
index 0aea07c..0cc24b8 100755
--- a/check_slapdd_crc32
+++ b/check_slapdd_crc32
@@ -15,7 +15,7 @@ default_slapdd_path = '/etc/ldap/slapd.d'
 
 # Main
 parser = argparse.ArgumentParser(
-    description=f'{__doc__} (version: {version})'
+    description='{} (version: {})'.format(__doc__, version)
 )
 
 parser.add_argument(
@@ -56,7 +56,7 @@ parser.add_argument(
     action='store',
     type=str,
     dest='slapdd_path',
-    help=f'Default slapd.d directory path (default: {default_slapdd_path}',
+    help='Default slapd.d directory path (default: {}'.format(default_slapdd_path),
     default=default_slapdd_path
 )
 
@@ -66,8 +66,9 @@ options = parser.parse_args()
 # Initialize log
 log = logging.getLogger()
 logformat = logging.Formatter(
-    f'%(asctime)s - {os.path.basename(sys.argv[0])} - %(levelname)s - '
-    '%(message)s')
+    '%(asctime)s - {} - %(levelname)s - '
+    '%(message)s'.format(os.path.basename(sys.argv[0]))
+)
 
 if options.debug:
     log.setLevel(logging.DEBUG)
EOF
    patch "$CRCBIN" "$PATCHFILE"
    if patch -s -f --dry-run "$CRCBIN" "$PATCHFILE"
    then
        echoerr "Patching $CRCBIN failed"
        exit 1
    fi
}

echo -n "Begin process : "
date

checkDependencies

if ! command_exists "check_slapdd_crc32"
then
    if [ ! -x "$LDIR/check_slapdd_crc32/check_slapdd_crc32" ]
    then
        cd "$TMPDIR" || ( echoerr "$TMPDIR does not exists" && exit 1 )
        git clone https://gogs.zionetrix.net/bn8/check_slapdd_crc32.git
        export PATH="$PATH:$TMPDIR/check_slapdd_crc32"
        SLAPDDCRCBIN="$TMPDIR/check_slapdd_crc32/check_slapdd_crc32"
        if [ ! -e "$TMPDIR/check_slapdd_crc32/check_slapdd_crc32" ]
        then
            echoerr "Cannot git clone check_slapdd_crc32 project"
            exit 1
        fi
    else
        export PATH="$PATH:/usr/local/bin"
        SLAPDDCRCBIN="$LDIR/check_slapdd_crc32/check_slapdd_crc32"
    fi
else
    PATHLIST="${PATH//:/' '}"
    # shellcheck disable=SC2086
    SLAPDDCRCBIN=$(whereis -b -B $PATHLIST -f check_slapdd_crc32 | awk '{print $2}')
fi

if ! python3 -c 'import sys; assert sys.version_info >= (3,6)' > /dev/null
then
    # Patching for python3 < 3.6 (Because Debian 9 have python 3.5)
    patchCRC32 "$SLAPDDCRCBIN"
fi

# -------------------------------------
# Test if migration is needed
if [ -e "/etc/ldap/slapd.d/cn=config/olcDatabase={1}mdb" ]
then
    echoerr "OpenLDAP seems already configured with MDB backend..."
    exit 1
fi

# -------------------------------------
# Add MDB Backend to OpenLDAP config
if ! grep -q -E '^olcModuleLoad:.*back_mdb.la$' "/etc/ldap/slapd.d/cn=config/cn=module{0}.ldif"
then
    cat << EOF > "$TMPDIR/load-module.ldif"
dn: cn=module{0},cn=config
changetype: modify
add: olcModuleLoad
olcModuleLoad: back_mdb.la
EOF
    ldapmodify -Y EXTERNAL -H ldapi:/// -f "$TMPDIR/load-module.ldif" || exit 1
fi

# -------------------------------------
# Save config
rsync -av /etc/ldap/slapd.d/ /etc/ldap/slapd.d.bkp/
check_slapdd_crc32 -f
# Creating a copy of OpenLDAP configuration witch we working on
rsync -av /etc/ldap/slapd.d/ /etc/ldap/slapd.d.new/

# -------------------------------------
# migrate config BDB/HDB => MDB
cd '/etc/ldap/slapd.d.new/cn=config' || ( echoerr '/etc/ldap/slapd.d.new/cn=config does not exists' && exit 1 )
# HDB :
[ -e 'olcDatabase={1}hdb.ldif' ] && mv 'olcDatabase={1}hdb.ldif' 'olcDatabase={1}mdb.ldif'
[ -d 'olcDatabase={1}hdb' ] && mv 'olcDatabase={1}hdb' 'olcDatabase={1}mdb'
# BDB :
[ -e 'olcDatabase={1}bdb.ldif' ] && mv 'olcDatabase={1}bdb.ldif' 'olcDatabase={1}mdb.ldif'
[ -d 'olcDatabase={1}bdb' ] && mv 'olcDatabase={1}bdb' 'olcDatabase={1}mdb'

sed -i 's/{1}[hb]db/{1}mdb/' 'olcDatabase={1}mdb.ldif'
sed -i 's/olc[HB]dbConfig/olcMdbConfig/g' 'olcDatabase={1}mdb.ldif'

obsoleteAttributes='olcDbCacheFree olcDbCacheSize olcDbChecksum olcDbConfig olcDbCryptFile olcDbCryptKey olcDbDNcacheSize olcDbDirtyRead olcDbIDLcacheSize olcDbLinearIndex olcDbLockDetect olcDbPageSize olcDbShmKey'
for attr in $obsoleteAttributes
do
    sed -i "/^$attr:/d" 'olcDatabase={1}mdb.ldif'    
done

# Adding olcDbMaxSize
if ! grep -q '^olcDbMaxSize:' 'olcDatabase={1}mdb.ldif'
then
    sed -i '/^olcAccess: {0}/i olcDbMaxSize: 1000000000' 'olcDatabase={1}mdb.ldif'
fi

# Removing old backend modules if exists
sed -i '/^olcModuleLoad:.*back_hdb.la$/d' "cn=module{0}.ldif"
sed -i '/^olcModuleLoad:.*back_bdb.la$/d' "cn=module{0}.ldif"

if slaptest -u -Q -F "/etc/ldap/slapd.d.new/"
then
    if slapschema -F /etc/ldap/slapd.d.new/ -b 'cn=config'
    then
        echo "Ready, Migrating !"
    else
        echoerr "Erreur slapschema"
        exit 1
    fi
else
    echoerr "Erreur slaptest"
    exit 1
fi

echo -n "slapd stopped : "
date

DB_DIRECTORY=$( grep -iE '^olcDbDirectory: ' '/etc/ldap/slapd.d.new/cn=config/olcDatabase={1}mdb.ldif'|sed 's/^olcDbDirectory: //' )
echo "DB directory: $DB_DIRECTORY"
[ -n "$DB_DIRECTORY" ] && [ -d "$DB_DIRECTORY/" ] && \
systemctl stop slapd.service && \
slapcat -n1 > "$TMPDIR/ldif" && \
rsync -av --delete /etc/ldap/slapd.d.new/ /etc/ldap/slapd.d/ && \
check_slapdd_crc32 -f && \
rm -f "$DB_DIRECTORY"/*.bdb "$DB_DIRECTORY"/DB_CONFIG "$DB_DIRECTORY"/__db.* "$DB_DIRECTORY"/log.* "$DB_DIRECTORY"/alock && \
slapadd -n 1 -q -l "$TMPDIR/ldif" && \
chown openldap: -R "$DB_DIRECTORY" && \
chown openldap:openldap -R /etc/ldap/slapd.d
systemctl start slapd.service

echo "slapd started : "
date

