/*
 * Copyright (c) 2013, 2015-2019, 2021 Apple Inc. All rights reserved.
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
 * IPMonitorControlPrefs.c
 * - definitions for accessing IPMonitor control preferences
 */

/*
 * Modification History
 *
 * January 14, 2013	Dieter Siegmund (dieter@apple)
 * - created
 */

//#include <TargetConditionals.h>
//#include <SystemConfiguration/SCPreferences.h>
//#include <SystemConfiguration/SCPrivate.h>
//#include <SystemConfiguration/scprefs_observer.h>
#include "IPMonitorControlPrefs.h"

/*
 * kIPMonitorControlPrefsID
 * - identifies the IPMonitor preferences file that contains 'Verbose'
 */
#define kIPMonitorControlPrefsIDStr	"com.apple.IPMonitor.control.plist"

/*
 * kVerbose
 * - indicates whether IPMonitor is verbose or not
 */
#define kVerbose			CFSTR("Verbose")

static _SCControlPrefsRef		S_control;

__private_extern__
_SCControlPrefsRef
IPMonitorControlPrefsInit(CFRunLoopRef			runloop,
			  IPMonitorControlPrefsCallBack	callback)
{
	_SCControlPrefsRef	control;

	control = _SCControlPrefsCreate(kIPMonitorControlPrefsIDStr, runloop, callback);
	return control;
}

/**
 ** Get
 **/
__private_extern__ Boolean
IPMonitorControlPrefsIsVerbose(void)
{
	Boolean	verbose	= FALSE;

	if (S_control == NULL) {
		S_control = IPMonitorControlPrefsInit(NULL, NULL);
	}
	if (S_control != NULL) {
		verbose = _SCControlPrefsGetBoolean(S_control, kVerbose);
	}
	return verbose;
}

/**
 ** Set
 **/
__private_extern__ Boolean
IPMonitorControlPrefsSetVerbose(Boolean verbose)
{
	Boolean	ok	= FALSE;

	if (S_control == NULL) {
		S_control = IPMonitorControlPrefsInit(NULL, NULL);
	}
	if (S_control != NULL) {
		ok = _SCControlPrefsSetBoolean(S_control, kVerbose, verbose);
	}
	return ok;
}

#ifdef TEST_IPMONITORCONTROLPREFS
int
main(int argc, char * argv[])
{
    Boolean	need_usage = FALSE;
    Boolean	success = FALSE;

    if (argc < 2) {
	need_usage = TRUE;
    }
    else if (strcasecmp(argv[1], "on") == 0) {
	success = IPMonitorControlPrefsSetVerbose(TRUE);
    }
    else if (strcasecmp(argv[1], "off") == 0) {
	success = IPMonitorControlPrefsSetVerbose(FALSE);
    }
    else {
	need_usage = TRUE;
    }
    if (need_usage) {
	fprintf(stderr, "usage: %s ( on | off )\n", argv[0]);
	exit(1);
    }
    if (!success) {
	fprintf(stderr, "failed to save prefs\n");
	exit(2);
    }
    exit(0);
    return (0);
}

#endif /* TEST_IPMONITORCONTROLPREFS */
