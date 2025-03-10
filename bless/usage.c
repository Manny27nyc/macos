/*
 * Copyright (c) 2001-2007 Apple Inc. All Rights Reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. Please obtain a copy of the License at
 * http://www.opensource.apple.com/apsl/ and read it before using this
 * file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 * Please see the License for the specific language governing rights and
 * limitations under the License.
 * 
 * @APPLE_LICENSE_HEADER_END@
 */
/*
 *  usage.c
 *  bless
 *
 *  Created by Shantonu Sen <ssen@apple.com> on Wed Nov 14 2001.
 *  Copyright (c) 2001-2007 Apple Inc. All Rights Reserved.
 *
 *  $Id: usage.c,v 1.31 2005/12/05 12:59:30 ssen Exp $
 *
 */

#include <stdlib.h>
#include <stdio.h>

#include "bless.h"

#include "enums.h"
#include "structs.h"
#include "protos.h"

void usage(void) {
    BLPreBootEnvType firmwareType = getPrebootType();

    fprintf(stderr, "Usage: %s [options]\n", getprogname());

    if (firmwareType != kBLPreBootEnvType_iBoot) {
        fputs(
              "\t--help\t\tThis usage statement\n"
              "\n"
              "Info Mode:\n"
              "\t--info [dir]\tPrint blessing information for a specific volume, or the\n"
              "\t\t\tcurrently active boot volume if <dir> is not specified\n"
              "\t\t\t(For Apple Silicon, --info option is only supported for external devices)\n"
              "\t--getBoot\tSuppress normal output and print the active boot volume\n"
              "\t--version\tPrint bless version number\n"
              "\t--plist\t\tFor any output type, use a plist representation\n"
              "\t--verbose\tVerbose output\n"
              "\n"
              "File/Folder Mode:\n"
              "\t--file file\tSet <file> as the blessed boot file\n"
              "\t--folder dir\tSet <dir> as the blessed directory\n"
              "\t--bootefi [file]\tUse <file> to create a \"boot.efi\" file in the\n"
              "\t\t\tblessed dir\n"
              "\t--setBoot\tSet firmware to boot from this volume\n"
              "\t--create-snapshot\t Create an APFS snapshot of this volume\n"
              "\t--last-sealed-snapshot\t Revert back to the previously signed APFS snapshot\n"
              "\t--verbose\tVerbose output\n"
              "\n"
              "Mount Mode:\n"
              "\t--mount dir\tUse this mountpoint in conjunction with --setBoot\n"
              "\t--file file\tSet firmware to boot from <file>\n"
              "\t--setBoot\tSet firmware to boot from this volume\n"
              "\t--user\t Specify a user other than the one who invoked the tool\n"
              "\t--stdinpass\t Collect a local owner password from stdin without prompting.\n"
              "\t--passpromt\t Explicitly ask to be prompted for the password.\n"
              "\t--verbose\tVerbose output\n"
              "\n"
              "Device Mode:\n"
              "\t--device dev\tUse this block device in conjunction with --setBoot\n"
              "\t--setBoot\tSet firmware to boot from this volume\n"
              "\t--user\t Specify a user other than the one who invoked the tool\n"
              "\t--stdinpass\t Collect a local owner password from stdin without prompting.\n"
              "\t--passpromt\t Explicitly ask to be prompted for the password.\n"
              "\t--verbose\tVerbose output\n"
              "\n"
              "NetBoot Mode:\n"
              "\t--netboot\tSet firmware to boot from the network\n"
              "\t--server url\tUse BDSP to fetch boot parameters from <url>\n"
              "\t--verbose\tVerbose output\n",
              stderr);
    } else {
        fputs(
              "\t--help\t\tThis usage statement\n"
              "\n"
              "Info Mode:\n"
              "\t--info [dir]\tPrint blessing information for a specific volume, or the\n"
              "\t\t\tcurrently active boot volume if <dir> is not specified\n"
              "\t\t\t(For Apple Silicon, --info option is only supported for external devices)\n"
              "\t--getBoot\tSuppress normal output and print the active boot volume\n"
              "\t--version\tPrint bless version number\n"
              "\t--plist\t\tFor any output type, use a plist representation\n"
              "\t--verbose\tVerbose output\n"
              "\n"
              "File/Folder Mode: available only for external storage devices\n"
              "\t--file file\tSet <file> as the blessed boot file\n"
              "\t--folder dir\tSet <dir> as the blessed directory\n"
              "\t--setBoot\tSet firmware to boot from this volume\n"
              "\t--create-snapshot\t Create an APFS snapshot of this volume\n"
              "\t--last-sealed-snapshot\t Revert back to the previously signed APFS snapshot\n"
              "\t--verbose\tVerbose output\n"
              "\n"
              "Mount Mode:\n"
              "\t--mount dir\tUse this mountpoint in conjunction with --setBoot\n"
              "\t--file file\tSet firmware to boot from <file>\n"
              "\t--setBoot\tSet firmware to boot from this volume\n"
              "\t--verbose\tVerbose output\n"
              "\n"
              "Device Mode:\n"
              "\t--device dev\tUse this block device in conjunction with --setBoot\n"
              "\t--setBoot\tSet firmware to boot from this volume\n"
              "\t--verbose\tVerbose output\n"
              "\n"
              "Snapshot options:\n"
              "\t--create-snapshot\t Create an APFS snapshot of this volume\n"
              "\t--last-sealed-snapshot\t Revert back to the previously signed APFS snapshot\n"
              "\t--user\t Specify a user other than the one who invoked the tool\n"
              "\t--stdinpass\t Collect a local owner password from stdin without prompting.\n"
              "\t--passpromt\t Explicitly ask to be prompted for the password.\n"
              "\n",
              stderr);
    }
    exit(1);
}

/* Basically lifted from the man page */
void usage_short(void) {
    BLPreBootEnvType firmwareType = getPrebootType();

    fprintf(stderr, "Usage: %s [options]\n", getprogname());
    if (firmwareType != kBLPreBootEnvType_iBoot) {
        fputs(
              "bless --help\n"
              "\n"
              "bless --folder directory [--file file]\n"
"\t[--bootefi [file]]\n"
"\t[--setBoot]\n"
              "\t[--create-snapshot] [--last-sealed-snapshot] [--user] [--stdinpass] [--verbose]\n"
              "\n"
              "bless --mount directory [--file file] [--setBoot] [--user] [--stdinpass] [--verbose]\n"
              "\n"
              "bless --device device [--setBoot] [--user] [--stdinpass] [--verbose]\n"
              "\n"
              "bless --netboot --server url [--verbose]\n"
              "\n"
              "bless --info [directory] [--getBoot] [--plist] [--verbose] [--version]\n",
              stderr);
    } else {
        fputs(
              "bless --help\n"
              "\n"
              "\t(--folder option is supported for external devices only on apple silicon)\n"
              "\t(--file option is supported for external devices only on apple silicon)\n"
              "\n"
              "bless --mount volume \n"
              "\t[--create-snapshot] [--last-sealed-snapshot] [--user] [--stdinpass] [--verbose]\n"
              "\n"
              "bless --mount directory [--file file] [--setBoot] [--user] [--stdinpass] [--verbose]\n"
              "\n"
              "bless --device device [--setBoot] [--user] [--stdinpass] [--verbose]\n"
              "\n"
              "bless --info [directory] [--getBoot] [--plist] [--verbose] [--version]\n"
              "\t(For Apple Silicon, --info option is only supported for external devices)\n"
              "\n",
              stderr);
    }

    exit(1);
}
