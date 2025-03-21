#!/bin/sh

#
# Check and optionally reformat source files using uncrustify.
# Usage: ./tools/uncrustify.sh
#

UNCRUSTIFY=`xcrun -find uncrustify`
CONF_FILE="./tools/xnu-uncrustify.cfg"
REPLACE="--replace"

declare -a dirs=(
	"kext"
	"kext/gss"
	"kext/iokit"
	"mount_nfs"
	"ncctl"
	"nfs4mapid"
	"nfs_acl"
	"nfsclntTests"
	"nfsd"
	"nfsiod"
	"nfsstat"
	"rpc.lockd"
	"rpc.rquotad"
	"rpc.statd"
	"showmount"
	)

for dir in "${dirs[@]}"
do
	$UNCRUSTIFY -c $CONF_FILE --no-backup $REPLACE $dir/*.[chm] $dir/*.[ch]pp 2>&1 | grep -v -e  "Failed to load"
done
