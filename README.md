# OpenLDAP database backend migration script

[![reuse compliant](https://reuse.software/badge/reuse-compliant.svg)](https://reuse.software/) 
[![Trigger: Shell Check](https://github.com/DSI-Universite-Rennes2/certificate-tools/actions/workflows/main.yml/badge.svg?event=push)](https://github.com/DSI-Universite-Rennes2/certificate-tools/actions/workflows/main.yml)
[![License: CC-BY-NC-SA-4.0](https://img.shields.io/badge/License-CC%20BY--NC--SA%204.0-blue.svg)](https://creativecommons.org/licenses/by-nc-sa/4.0/)

This bash script migrate an OpenLDAP database from HDB/BDB to MDB format.

Warning : Don't be stupid. You MUST test and backup your data and configuration before run this...

This script have been tested on Debian 10 (buster).

This script :

- check needed dependencies
- load MDB module
- works directly on a copy of `/etc/ldap/slapd.d` to made needed changes to `cn=config` :
  - remove obsolete attributes
  - add olcDbMaxSize
  - remove old backend modules
  - rebuild CRC values with https://gogs.zionetrix.net/bn8/check_slapdd_crc32
- stop OpenLDAP
- dump all OpenLDAP data with slapcat
- delete OpenLDAP data file
- replace OpenLDAP cn=config with new one
- import data with slapadd
- start OpenLDAP

Some code & tips from : https://wiki.zionetrix.net/informatique:reseau:ldap:migration_bdb_hdb_mdb
So we publish this script with same License.
