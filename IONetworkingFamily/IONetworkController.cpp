/*
 * Copyright (c) 1998-2008 Apple Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * The contents of this file constitute Original Code as defined in and
 * are subject to the Apple Public Source License Version 1.1 (the
 * "License").  You may not use this file except in compliance with the
 * License.  Please obtain a copy of the License at
 * http://www.apple.com/publicsource and read it before using this file.
 * 
 * This Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON-INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 * 
 * @APPLE_LICENSE_HEADER_END@
 */
/*
 * IONetworkController.cpp
 *
 * HISTORY
 * 9-Dec-1998       Joe Liu (jliu) created.
 *
 */

#include <IOKit/assert.h>
#include <IOKit/IOCommandGate.h>
#include <IOKit/network/IONetworkController.h>
#include <IOKit/network/IOEthernetController.h>
#include <IOKit/network/IOOutputQueue.h>
#include <IOKit/network/IONetworkMedium.h>
#include <IOKit/IOMessage.h>
#include "IONetworkControllerPrivate.h"
#include "IONetworkDebug.h"

// IONetworkController (and its subclasses) needs to know about mbufs,
// but it shall have no further dependencies on BSD networking.
//
extern "C" {
#include <sys/param.h>  // mbuf limits defined here.
#include <sys/mbuf.h>
#include <sys/kdebug.h>
#include <machine/machine_routines.h>
}

#ifndef kIOMessageDeviceSignaledWakeup
#define kIOMessageDeviceSignaledWakeup  iokit_common_msg(0x350)
#endif

//-------------------------------------------------------------------------
// Macros.

#define super IOService

OSDefineMetaClassAndAbstractStructors( IONetworkController, IOService )
OSMetaClassDefineReservedUsed( IONetworkController,  0); // getDebuggerLinkStatus
OSMetaClassDefineReservedUsed( IONetworkController,  1); // setDebuggerMode
OSMetaClassDefineReservedUsed( IONetworkController,  2); // outputStart
OSMetaClassDefineReservedUsed( IONetworkController,  3); // setInputPacketPollingEnable
OSMetaClassDefineReservedUsed( IONetworkController,  4); // pollInputPackets
OSMetaClassDefineReservedUsed( IONetworkController,  5); // networkInterfaceNotification
OSMetaClassDefineReservedUsed( IONetworkController,  6); // allocatePacketNoWait
OSMetaClassDefineReservedUnused( IONetworkController,  7);
OSMetaClassDefineReservedUnused( IONetworkController,  8);
OSMetaClassDefineReservedUnused( IONetworkController,  9);
OSMetaClassDefineReservedUnused( IONetworkController, 10);
OSMetaClassDefineReservedUnused( IONetworkController, 11);
OSMetaClassDefineReservedUnused( IONetworkController, 12);
OSMetaClassDefineReservedUnused( IONetworkController, 13);
OSMetaClassDefineReservedUnused( IONetworkController, 14);
OSMetaClassDefineReservedUnused( IONetworkController, 15);
OSMetaClassDefineReservedUnused( IONetworkController, 16);
OSMetaClassDefineReservedUnused( IONetworkController, 17);
OSMetaClassDefineReservedUnused( IONetworkController, 18);
OSMetaClassDefineReservedUnused( IONetworkController, 19);
OSMetaClassDefineReservedUnused( IONetworkController, 20);
OSMetaClassDefineReservedUnused( IONetworkController, 21);
OSMetaClassDefineReservedUnused( IONetworkController, 22);
OSMetaClassDefineReservedUnused( IONetworkController, 23);
OSMetaClassDefineReservedUnused( IONetworkController, 24);
OSMetaClassDefineReservedUnused( IONetworkController, 25);
OSMetaClassDefineReservedUnused( IONetworkController, 26);
OSMetaClassDefineReservedUnused( IONetworkController, 27);
OSMetaClassDefineReservedUnused( IONetworkController, 28);
OSMetaClassDefineReservedUnused( IONetworkController, 29);
OSMetaClassDefineReservedUnused( IONetworkController, 30);
OSMetaClassDefineReservedUnused( IONetworkController, 31);

static bool isPowerOfTwo(UInt32 num)
{
    return (num == (num & ~(num - 1)));
}

#define MEDIUM_LOCK     IOTakeLock(_mediumLock);
#define MEDIUM_UNLOCK   IOUnlock(_mediumLock);

#define RELEASE(x) do { if (x) { (x)->release(); (x) = 0; } } while (0)

// OSSymbols for frequently used keys.
//
static const OSSymbol * gIOActiveMediumKey;
static const OSSymbol * gIOCurrentMediumKey;
static const OSSymbol * gIODefaultMediumKey;
static const OSSymbol * gIONullMediumName;
static const OSSymbol * gIOLinkDataKey;
static const OSSymbol * gIOControllerEnabledKey;
static const OSData   * gIONullLinkData;

// Global symbols.
//
__exported const OSSymbol * gIONetworkFilterGroup;
__exported const OSSymbol * gIOEthernetWakeOnLANFilterGroup;
__exported const OSSymbol * gIOEthernetDisabledWakeOnLANFilterGroup;

uint32_t         gIONetworkDebugFlags = 0;
#ifdef __x86_64__
OSArray *        gIONetworkMbufCursorKexts;
IOLock *         gIONetworkMbufCursorLock;
IORegistryEntry *gIONetworkMbufCursorEntry;
#endif

// Constants for handleCommand().
//
enum {
    kCommandEnable       = 1,
    kCommandDisable      = 2,
    kCommandPrepare      = 3,
    kCommandInitDebugger = 4
};

class IONetworkControllerGlobals
{
public:
    IONetworkControllerGlobals();
    ~IONetworkControllerGlobals();

    inline bool isValid() const;
};

static IONetworkControllerGlobals gIONetworkControllerGlobals;

IONetworkControllerGlobals::IONetworkControllerGlobals()
{
    gIOActiveMediumKey  = OSSymbol::withCStringNoCopy(kIOActiveMedium); 
    gIOCurrentMediumKey = OSSymbol::withCStringNoCopy(kIOSelectedMedium);
    gIODefaultMediumKey = OSSymbol::withCStringNoCopy(kIODefaultMedium);
    gIONullMediumName   = OSSymbol::withCStringNoCopy("");
    gIOLinkDataKey      = OSSymbol::withCStringNoCopy(kIOLinkData);
    gIONullLinkData     = OSData::withCapacity(0);
    
    gIONetworkFilterGroup =
        OSSymbol::withCStringNoCopy(kIONetworkFilterGroup);
    
    gIOEthernetWakeOnLANFilterGroup =
        OSSymbol::withCStringNoCopy(kIOEthernetWakeOnLANFilterGroup);

    gIOEthernetDisabledWakeOnLANFilterGroup =
        OSSymbol::withCStringNoCopy(kIOEthernetDisabledWakeOnLANFilterGroup);

    gIOControllerEnabledKey = 
        OSSymbol::withCStringNoCopy("IOControllerEnabled");

#ifdef __x86_64__
    gIONetworkMbufCursorKexts = OSArray::withCapacity(4);
    gIONetworkMbufCursorLock  = IOLockAlloc();
    gIONetworkMbufCursorEntry = 0;
#endif

    uint32_t flags;
    if (PE_parse_boot_argn("ionetwork_debug", &flags, sizeof(flags)))
        gIONetworkDebugFlags |= flags;
}

IONetworkControllerGlobals::~IONetworkControllerGlobals()
{
    RELEASE( gIOActiveMediumKey );
    RELEASE( gIOCurrentMediumKey );
    RELEASE( gIODefaultMediumKey );
    RELEASE( gIONullMediumName );
    RELEASE( gIOLinkDataKey );
    RELEASE( gIONullLinkData );
    RELEASE( gIONetworkFilterGroup );
    RELEASE( gIOEthernetWakeOnLANFilterGroup );
    RELEASE( gIOEthernetDisabledWakeOnLANFilterGroup );
    RELEASE( gIOControllerEnabledKey );

#ifdef __x86_64__
    RELEASE( gIONetworkMbufCursorKexts );
    if (gIONetworkMbufCursorLock)
    {
        IOLockFree(gIONetworkMbufCursorLock);
        gIONetworkMbufCursorLock = 0;
    }
#endif
}

bool IONetworkControllerGlobals::isValid() const
{
    return ( gIOActiveMediumKey    &&
             gIOCurrentMediumKey   &&
             gIODefaultMediumKey   &&
             gIONullMediumName     &&
             gIOLinkDataKey        &&
             gIONullLinkData       &&
             gIONetworkFilterGroup &&
             gIOEthernetWakeOnLANFilterGroup &&
             gIOEthernetDisabledWakeOnLANFilterGroup &&
             gIOControllerEnabledKey );
}

//---------------------------------------------------------------------------
// Initialize the IONetworkController instance. Instance variables are 
// set to their default values, then super::init() is called.
//
// properties: A dictionary object containing a property table
//             associated with this instance.
//
// Returns true on success, false otherwise.

bool IONetworkController::init(OSDictionary * properties)
{
    // Initialize instance variables.
    //
    _workLoop               = 0;
    _cmdGate                = 0;
    _outputQueue            = 0;
    _clientSet              = 0;
    _clientSetIter          = 0;
    _cmdClient              = 0;
    _propertiesPublished    = false;
    _mediumLock             = 0;
    _lastLinkData           = gIONullLinkData;
    _lastActiveMediumName   = gIONullMediumName;
    _lastCurrentMediumName  = gIONullMediumName;

    if ( super::init(properties) == false )
    {
        DLOG("IONetworkController: super::init() failed\n");
        return false;
    }

    if ( gIONetworkControllerGlobals.isValid() == false )
    {
        return false;
    }

    return true;
}

//-------------------------------------------------------------------------
// Called after the controller driver was successfully matched to a provider,
// to start running. IONetworkController will allocate resources and gather
// controller properties. No I/O will be performed until the subclass 
// attaches a client object from its start() method. Subclasses must override 
// this method and call super::start() at the beginning of its implementation. 
// Then check the return value to make sure the superclass was started 
// successfully before continuing. The resources allocated by 
// IONetworkController include:
//
// - An IOCommandGate object to handle client commands.
// - An OSSet to track our clients.
// - An optional IOOutputQueue object for output queueing.
//
// Tasks that are usually performed by a typical network driver in start
// include:
//
// - Resource allocation
// - Hardware initialization
// - Allocation of IOEventSources and attaching them to an IOWorkLoop object.
// - Publishing a medium dictionary.
// - And finally, attaching an interface object after the driver is ready
//   to handle client requests.
//
// provider: The provider that the controller was matched
//           (and attached) to.
//
// Returns true on success, false otherwise.

bool IONetworkController::start(IOService * provider)
{
    // Most drivers will probably want to wait for BSD due to their
    // dependency on mbufs, which is not available until BSD is
    // initialized.

    if ((getFeatures() & kIONetworkFeatureNoBSDWait) == 0)
        waitForService(resourceMatching( "IOBSD" ));

    // Start our superclass.

    if (!super::start(provider))
        return false;

    // Create an OSSet to store our clients.

    _clientSet = OSSet::withCapacity(2);
    if (_clientSet == 0)
        return false;

    _clientSetIter = OSCollectionIterator::withCollection(_clientSet);
    if (_clientSetIter == 0)
        return false;

    // Initialize link status properties.

    if (!setProperty(gIOActiveMediumKey, (OSSymbol *) gIONullMediumName) ||
	    !setProperty(gIOCurrentMediumKey, (OSSymbol *) gIONullMediumName))
		return false;

    _linkStatus = OSNumber::withNumber((UInt64) 0, 32);
    if (!_linkStatus || !setProperty(kIOLinkStatus, _linkStatus))
    {
    	return false;
    }

    _linkSpeed = OSNumber::withNumber((UInt64) 0, 64);
    if (!_linkSpeed || !setProperty(kIOLinkSpeed, _linkSpeed))
    {
    	return false;
    }

    // Allocate a mutex lock to serialize access to the medium dictionary.

    _mediumLock = IOLockAlloc();
    if (!_mediumLock)
        return false;
    IOLockInitWithState(_mediumLock, kIOLockStateUnlocked);

    // Tell the driver that now is the time to create a work loop
    // (if it wants one).

    if ( createWorkLoop() != true )
    {
        DLOG("%s: createWorkLoop() error\n", getName());
        return false;
    }

	// Get the workloop.

    _workLoop = getWorkLoop();
    if ( _workLoop == 0 )
    {
        DLOG("%s: IOWorkLoop allocation failed\n", getName());
        return false;
    }
    _workLoop->retain();

    if (_workLoop != provider->getWorkLoop())
    {
        ml_thread_policy( _workLoop->getThread(), MACHINE_GROUP, 
                          (MACHINE_NETWORK_GROUP|MACHINE_NETWORK_WORKLOOP) );
    }

    // Create a 'private' IOCommandGate object and attach it to
    // our workloop created above. This is used by executeCommand().

    _cmdGate = IOCommandGate::commandGate(this);
    if (!_cmdGate ||
        (_workLoop->addEventSource(_cmdGate) != kIOReturnSuccess))
    {
        DLOG("%s: IOCommandGate initialization failed\n", getName());
        return false;
    }

    // Try to allocate an IOOutputQueue instance. This is optional and
    // _outputQueue may be 0.

    _outputQueue = createOutputQueue();

    // Query the controller's mbuf buffer restrictions.

    IOPacketBufferConstraints constraints;
    getPacketBufferConstraints(&constraints);
    if ((constraints.alignStart  > kIOPacketBufferAlign32) ||
        (constraints.alignLength > kIOPacketBufferAlign32) ||
        !isPowerOfTwo(constraints.alignStart) ||
        !isPowerOfTwo(constraints.alignLength))
    {
        IOLog("%s: Invalid alignment: start:%d, length:%d\n",
            getName(),
            (uint32_t) constraints.alignStart,
            (uint32_t) constraints.alignLength);
        return false;
    }

    // Make it easier to satisfy both constraints.

    if (constraints.alignStart < constraints.alignLength)
        constraints.alignStart = constraints.alignLength;
    
    // Convert to alignment masks.

    _alignStart  = (constraints.alignStart) ? constraints.alignStart - 1 : 0;
    _alignLength = (constraints.alignLength) ? constraints.alignLength - 1 : 0;
    _alignPadding = _alignStart + _alignLength;

    // Called by a policy-maker to initialize itself for power-management.
    // IONetworkController is the policy-maker.

    PMinit();

    // Called by a policy-maker on its nub, to be attached into the
    // power management hierarchy.
    
    provider->joinPMtree(this);

    return true;
}

//---------------------------------------------------------------------------
// The opposite of start(). The controller has been instructed to stop running.
// This method should release resources and undo actions performed by start().
// Subclasses must override this method and call super::stop() at the end of 
// its implementation.
//
// provider: The provider that the controller was matched
//           (and attached) to.

void IONetworkController::stop(IOService * provider)
{
    // Called by a policy-maker to resign its responsibilities as the
    // policy-maker.

    PMstop();

    super::stop(provider);
}   

//---------------------------------------------------------------------------
// Power-management hooks for subclasses.

IOReturn IONetworkController::registerWithPolicyMaker(IOService * policyMaker)
{
    // An opportunity for subclasses to call
    // policyMaker->registerPowerDriver(...)
    // and other future PM requirements.
    return kIOReturnUnsupported;
}

//---------------------------------------------------------------------------
// Catch calls to createWorkLoop() for drivers that choose not implement this
// method.

bool IONetworkController::createWorkLoop()
{
    return true;
}

//---------------------------------------------------------------------------
// Get the IOCommandGate object created by IONetworkController.
// An IOCommandGate is created and attached to the internal workloop by
// the start() method.
// This IOCommandGate object is used to handle client commands sent to
// executeCommand(). Subclasses that need an IOCommandGate should use the
// object returned by this method, rather than creating
// a new instance. See IOCommandGate.
//
// Returns the IOCommandGate object created by IONetworkController.
    
IOCommandGate * IONetworkController::getCommandGate() const
{
    return _cmdGate;
}

//---------------------------------------------------------------------------
// Get the address of the method designated to handle output packets.
//
// Returns the address of the outputPacket() method.

IOOutputAction IONetworkController::getOutputHandler() const
{
    return (IOOutputAction) &IONetworkController::outputPacket;
}

//---------------------------------------------------------------------------
// Create a new interface object and attach it to the controller.
// The createInterface() method is called to perform the allocation and
// initialization, followed by a call to configureInterface() to configure
// the interface. Subclasses can override those methods to customize the 
// interface client attached. Drivers will usually call this method from
// their start() implementation, after they are ready to process client
// requests.
//
// interfaceP: If successful (return value is true), then the interface
//             object will be written to the handle provided.
//
// doRegister: If true, then registerService() is called to register
//             the interface, which will trigger the matching process,
//             and cause the interface to become registered with the network
//             layer. For drivers that wish to delay the registration, and
//             hold off servicing requests and data packets from the network
//             layer, set doRegister to false and call registerService() on
//             the interface object when the controller becomes ready.
//             This allows the driver to attach an interface but without
//             making it available to the rest of the system.
//
// Returns true on success, false otherwise.

bool
IONetworkController::attachInterface(IONetworkInterface ** interfaceP,
                                     bool  doRegister)
{
    IONetworkInterface * netif;

    *interfaceP = 0;

    // We delay some initialization until the first time that
    // attachInterface() is called by the subclass.

    if (executeCommand(this, &IONetworkController::handleCommand,
                       this, (void *) kCommandPrepare) != kIOReturnSuccess)
    {
        return false;
    }

    do {
        // Allocate a concrete subclass of IONetworkInterface
        // by calling createInterface().

        netif = createInterface();
        if (!netif)
            break;

        // Configure the interface instance by calling 
        // configureInterface(), then attach it as our client.

        if ( !configureInterface(netif) || !netif->attach(this) )
        {
            netif->release();
            break;
        }

        *interfaceP = netif;

        // Register the interface nub. Spawns a matching thread.

        if (doRegister)
            netif->registerService();

        return true;    // success
    }
    while (0);

    return false;   // failure
}

//---------------------------------------------------------------------------
// Detach the interface object. This method will check that the object
// provided is indeed an IONetworkInterface, and if so its terminate()
// method is called. Note that a registered interface object will close
// and detach from its controller only after the network layer has removed
// all references to the data structures exposed by the interface.
//
// interface: An interface object to be detached.
// sync:      If true, the interface is terminated synchronously.
//            Note that this may cause detachInterface() to block
//            for an indeterminate of time.

void
IONetworkController::detachInterface(IONetworkInterface * interface,
                                     bool                 sync)
{
    IOOutputQueue * outQueue = getOutputQueue();
    IOOptionBits    options  = kIOServiceRequired;

    if (OSDynamicCast(IONetworkInterface, interface) == 0)
        return;

    if (outQueue)
    {
        // Remove output queue stats to allow the queue to safely
        // go away while interface is detaching.
        IONetworkData * statsData = outQueue->getStatisticsData();
        if (statsData)
        {
            statsData->setNotificationTarget(0, 0);
            interface->removeNetworkData(statsData->getKey());
        }
    }

    if (sync)
        options |= kIOServiceSynchronous;

    interface->terminate(options);
}

//---------------------------------------------------------------------------
// This method is called by attachInterface() or attachDebuggerClient() on
// the workloop context, to prepare the controller before attaching the client
// object. This method will call publishProperties() to publish controller
// capabilities and properties that may be used by client objects. However,
// publishProperties() will be called only once, even if prepare() is called
// multiple times.
//
// kIOReturnSuccess on success, or an error code otherwise.
// Returning an error will cause the client attach to fail.

IOReturn IONetworkController::prepare()
{
	IOReturn ret = kIOReturnSuccess;

	if ( _propertiesPublished == false )
	{
		if ( publishProperties() == true )
		{
            _propertiesPublished = true;
            
            if (pm_vars != 0)
            {
                if ( registerWithPolicyMaker( this ) != kIOReturnSuccess )
                {
                    // Detach the policy maker from the PM tree.
                    // For PCI devices, this will prevent the sleep code in
                    // platform expert from wrongly assuming that the device
                    // is power managed.

                    PMstop();
                }
            }
        }
        else
        {
            ret = kIOReturnError;
        }
	}

	return ret;
}

//---------------------------------------------------------------------------
// Handle a client open on the controller object. IOService calls this method 
// with the arbitration lock held. Subclasses are not expected to override
// this method.
//
//   client: The client that is attempting to open the controller.
//  options: See IOService.
// argument: See IOService.
//
// Returns true to accept the client open, false to refuse it.

bool IONetworkController::handleOpen(IOService *  client,
                                     IOOptionBits options,
                                     void *       argument)
{
    assert(client);
    return _clientSet->setObject(client);
}

//---------------------------------------------------------------------------
// Handle a close from one of the client objects. IOService calls this method
// with the arbitration lock held. Subclasses are not expected to override this 
// method.
//
//  client: The client that is closing the controller.
// options: See IOService.

void IONetworkController::handleClose(IOService * client, IOOptionBits options)
{
    _clientSet->removeObject(client);
}

//---------------------------------------------------------------------------
// This method is always called by IOService with the arbitration lock held. 
// Subclasses should not override this method.
//
// Returns true if the specified client, or any client if none is
// specified, presently has an open on this object.

bool IONetworkController::handleIsOpen(const IOService * client) const
{
    if (client)
        return _clientSet->containsObject(client);
    else
        return (_clientSet->getCount() > 0);
}

//---------------------------------------------------------------------------
// Free the IONetworkController instance by releasing all allocated resources,
// then call super::free().

void IONetworkController::free()
{
    // We should have no clients at this point. If we do,
    // then something is very wrong! It means that a client
    // has an open on us, and yet we are being freed.

    if (_clientSet) assert(_clientSet->getCount() == 0);

    RELEASE( _outputQueue   );
    if( _cmdGate )
	{
		if(_workLoop) _workLoop->removeEventSource(_cmdGate);
		_cmdGate->release();
		_cmdGate = 0;
	}
    RELEASE( _workLoop      );
    RELEASE( _clientSetIter );
    RELEASE( _clientSet     );
    RELEASE( _linkStatus    );
    RELEASE( _linkSpeed     );

    if (_mediumLock) { IOLockFree(_mediumLock); _mediumLock = 0; }

    super::free();
}

//---------------------------------------------------------------------------
// Handle an enable request from a client.

IOReturn IONetworkController::enable(IOService * client)
{
    if (OSDynamicCast(IONetworkInterface, client))
        return enable((IONetworkInterface *) client);
    
    if (OSDynamicCast(IOKernelDebugger, client))
        return enable((IOKernelDebugger *) client);

    IOLog("%s::%s Unknown client type\n", getName(), __FUNCTION__);
    return kIOReturnBadArgument;
}

//---------------------------------------------------------------------------
// Handle a disable request from a client.

IOReturn IONetworkController::disable(IOService * client)
{
    if (OSDynamicCast(IONetworkInterface, client))
        return disable((IONetworkInterface *) client);
    
    if (OSDynamicCast(IOKernelDebugger, client))
        return disable((IOKernelDebugger *) client);

    IOLog("%s::%s Unknown client type\n", getName(), __FUNCTION__);
    return kIOReturnBadArgument;
}

//---------------------------------------------------------------------------
// Called by an interface client to enable the controller.

IOReturn IONetworkController::enable(IONetworkInterface * interface)
{
    IOLog("IONetworkController::%s\n", __FUNCTION__);
    return kIOReturnUnsupported;
}

//---------------------------------------------------------------------------
// Called by an interface client to disable the controller.

IOReturn IONetworkController::disable(IONetworkInterface * interface)
{
    IOLog("IONetworkController::%s\n", __FUNCTION__);
    return kIOReturnUnsupported;
}

//---------------------------------------------------------------------------
// Discover and publish controller capabilities to the property table.
// This method is called by prepare() on the workloop context.
//
// Returns true if all capabilities were discovered and published
// successfully, false otherwise. Returning false will prevent client
// objects from attaching to the controller since a vital property that
// a client requires may be missing.

bool IONetworkController::publishProperties()
{
    bool              ret = false;
    const OSString *  string;
    UInt32            num;
    OSDictionary *    dict = 0;
    OSNumber *        numObj = 0;

    do {
        bool status;

        string = newVendorString();
        if (string) {
            status = setProperty(kIOVendor, (OSObject *) string);
            string->release();
            if (status != true) break;
        }

        string = newModelString();
        if (string) {
            status = setProperty(kIOModel, (OSObject *) string);
            string->release();
            if (status != true) break;
        }

        string = newRevisionString();
        if (string) {
            status = setProperty(kIORevision, (OSObject *) string);
            string->release();
            if (status != true) break;
        }

        // Publish controller feature flags.

        num = getFeatures();
        if ( !setProperty(kIOFeatures, num, sizeof(num) * 8) )
            break;

        // Publish max/min packet size.

        if ( ( getMaxPacketSize(&num) != kIOReturnSuccess ) ||
             ( !setProperty(kIOMaxPacketSize, num, sizeof(num) * 8) ) )
            break;
        
        if ( ( getMinPacketSize(&num) != kIOReturnSuccess ) ||
             ( !setProperty(kIOMinPacketSize, num, sizeof(num) * 8) ) )
            break;

        // Publish supported packet filters.

        if (getPacketFilters(gIONetworkFilterGroup, &num) != kIOReturnSuccess)
            break;

        dict   = OSDictionary::withCapacity(1);
        numObj = OSNumber::withNumber(num, sizeof(num) * 8);
        if ( (dict == 0) || (numObj == 0) ) break;

        if ( !dict->setObject(gIONetworkFilterGroup, numObj)  ||
             !setProperty(kIOPacketFilters, dict) )
            break;

        ret = true;
    }
    while (false);

    if (ret == false) {
        DLOG("IONetworkController::%s error\n", __FUNCTION__);
    }
    if ( dict )   dict->release();
    if ( numObj ) numObj->release();

    return ret;
}

//---------------------------------------------------------------------------
// Send a network event to all attached interface objects.

bool IONetworkController::_broadcastEvent(UInt32 type, void * data)
{
    IONetworkInterface * netif;

    lockForArbitration();   // locks open/close/state changes.

    if (_clientSet->getCount())
    {
        _clientSetIter->reset();

        while ((netif = (IONetworkInterface *)_clientSetIter->getNextObject()))
        {
            if (OSDynamicCast(IONetworkInterface, netif) == 0)
                continue;   // only send events to IONetworkInterface objects.
            netif->inputEvent(type, data);
        }
    }

    unlockForArbitration();

    return true;
}

//---------------------------------------------------------------------------
// A client request for the controller to change to a new MTU size.

IOReturn IONetworkController::setMaxPacketSize(UInt32 maxSize)
{
    return kIOReturnUnsupported;
}

//---------------------------------------------------------------------------
// Transmit a packet mbuf.

UInt32 IONetworkController::outputPacket(mbuf_t m, void * param)
{
    // The implementation here is simply a sink-hole, all packets are
    // dropped.

    if (m) freePacket(m);
    return 0;
}

//---------------------------------------------------------------------------
// Report features supported by the controller and/or driver.

UInt32 IONetworkController::getFeatures() const
{
    return 0;
}

//---------------------------------------------------------------------------
// Create default description strings.

const OSString * IONetworkController::newVendorString() const
{
    return 0;
}

const OSString * IONetworkController::newModelString() const
{
    return 0;
}

const OSString * IONetworkController::newRevisionString() const
{
    return 0;
}

//---------------------------------------------------------------------------
// Encode a client command received by executeCommand().

struct cmdStruct {
    OSObject *                   client;
    void *                       target;
    IONetworkController::Action  action;
    void *                       param0;
    void *                       param1;
    void *                       param2;
    void *                       param3;
    IOReturn                     ret;
};

//---------------------------------------------------------------------------
// Get the command client object.

OSObject * IONetworkController::getCommandClient() const
{
    return ( _workLoop->inGate() ? _cmdClient : 0 );
}

//---------------------------------------------------------------------------
// Configure an interface object created through createInterface().
// IONetworkController will register its output handler with the interface 
// object provided. After the interface is registered and opened by its
// client, it will refuse requests to change its properties through its
// public methods. Since this method is called before the interface object
// is published and registered, subclasses of IONetworkController may override
// this method to configure and customize the interface object.
//
// interface: The interface object to be configured.
//
// Returns true if configuration was successful, false otherwise (this
// will cause attachInterface() to fail).

bool IONetworkController::configureInterface(IONetworkInterface * interface)
{
    IOOutputAction  handler;
    OSObject *      target;
    bool            ret;
    IONetworkData * stats;

    if (!OSDynamicCast(IONetworkInterface, interface))
        return false;

    IOOutputQueue * outQueue = getOutputQueue();

    // Must register an output handler with the interface object.
    // The interface will send output packets, to its registered
    // output handler. If we allocated an output queue, then we
    // register the queue as the output handler, otherwise, we
    // become the output handler.

    if (outQueue)
    {
        target  = outQueue;
        handler = outQueue->getOutputHandler();
    
        stats   = outQueue->getStatisticsData();
        interface->addNetworkData(stats);
    }
    else
    {
        target  = this;
        handler = getOutputHandler();
    }
    ret = interface->registerOutputHandler(target, handler);

    return ret;
}

//---------------------------------------------------------------------------
// Called by start() to create an optional IOOutputQueue instance to handle
// output queueing. The default implementation will always return 0, hence
// no output queue will be created. A driver may override this method and 
// return a subclass of IOOutputQueue. IONetworkController will keep a 
// reference to the queue created, and will release the object when 
// IONetworkController is freed. Also see getOutputQueue().
//
// Returns a newly allocated and initialized IOOutputQueue instance.

IOOutputQueue * IONetworkController::createOutputQueue()
{
    return 0;
}

//---------------------------------------------------------------------------
// Return the output queue allocated though createOutputQueue().

IOOutputQueue * IONetworkController::getOutputQueue() const
{
    return _outputQueue;
}

//---------------------------------------------------------------------------
// Called by start() to obtain the constraints on the memory buffer
// associated with each mbuf allocated through allocatePacket().
// Drivers can override this method to specify their buffer constraints
// imposed by their bus master hardware. Note that outbound packets,
// those that originate from the network stack, are not subject
// to the constraints reported here.
//
// constraintsP: A pointer to an IOPacketBufferConstraints structure
//               that that this method is expected to initialize.
//               See IOPacketBufferConstraints structure definition.

void IONetworkController::getPacketBufferConstraints(
                          IOPacketBufferConstraints * constraintsP) const
{
    assert(constraintsP);
    constraintsP->alignStart  = kIOPacketBufferAlign1;
    constraintsP->alignLength = kIOPacketBufferAlign1;
}

static mbuf_t getPacket( UInt32 size,
                         UInt32 how,
                         UInt32 smask,
                         UInt32 lmask )
{
    mbuf_t          packet;
	UInt32          reqSize = size + smask + lmask; 	// we over-request so we can fulfill alignment needs.
    const uint32_t  minSize = mbuf_get_minclsize();

    //as protection from drivers that incorrectly assume they always get a single-mbuf packet
    //we force kernel to give us a cluster instead of chained small mbufs.

	if ((reqSize > mbuf_get_mhlen()) && (reqSize <= minSize))
		reqSize = minSize + 1;

	if( 0 == mbuf_allocpacket(how, reqSize, NULL, &packet))
	{
		mbuf_t m = packet;
		mbuf_pkthdr_setlen(packet, size);
		//run the chain and apply alignment
		
		while(size && m)
		{
			uintptr_t alignedStart, originalStart;
			
			originalStart = (uintptr_t)mbuf_data(m);
			alignedStart = (originalStart + smask) & ~((uintptr_t)smask);
			mbuf_setdata(m,  (caddr_t)alignedStart, (mbuf_maxlen(m) - (alignedStart - originalStart)) & ~lmask);
			
			if(mbuf_len(m) > size)
				mbuf_setlen(m, size); //truncate to remaining portion of packet

			size -= mbuf_len(m);
			m = mbuf_next(m);
		}
		return packet;
	}
	else
		return NULL;
}

mbuf_t IONetworkController::allocatePacket( UInt32 size )
{
    return getPacket( size, MBUF_WAITOK, _alignStart, _alignLength );
}

mbuf_t IONetworkController::allocatePacketNoWait( UInt32 size )
{
    return getPacket( size, MBUF_DONTWAIT, _alignStart, _alignLength );
}

//---------------------------------------------------------------------------
// Release the mbuf back to the free pool.

void IONetworkController::freePacket(mbuf_t m, IOOptionBits options)
{
    assert(m);

    if ( options & kDelayFree )
    {
        mbuf_setnextpkt(m, _freeList);
        _freeList = m;
    }
    else
    {
        mbuf_freem_list(m);
    }
}

UInt32 IONetworkController::releaseFreePackets()
{
    UInt32 count = 0;

	count =	mbuf_freem_list( _freeList );
	_freeList = 0;
    return count;
}

static inline bool IO_COPY_MBUF(
    mbuf_t src,
    mbuf_t       dst,
    int                 length)
{
    caddr_t src_dat, dst_dat;
    int dst_len, src_len;
	
    assert(src && dst);

	// dupe the header to pick up internal things like csums and vlan tags
	mbuf_copy_pkthdr(dst, src);
	mbuf_pkthdr_setheader(dst, NULL); //otherwise it could be pointing into src's data
	
    dst_len = (int)mbuf_len(dst);
    dst_dat = (caddr_t)mbuf_data(dst);

    while (src) {

        src_len = (int)mbuf_len( src );
        src_dat = (caddr_t)mbuf_data( src );

        if (src_len > length)
            src_len = length;

        while (src_len) {
        
            if (dst_len >= src_len) {
                // copy entire src mbuf to dst mbuf.

                bcopy(src_dat, dst_dat, src_len);               
                length -= src_len;
                dst_len -= src_len;
                dst_dat += src_len;
                src_len = 0;
            }
            else {
                // fill up dst mbuf with some portion of the data in
                // the src mbuf.

                bcopy(src_dat, dst_dat, dst_len);       // dst_len = 0?             
                length -= dst_len;
                dst_len = 0;
                src_len -= dst_len;         
            }
            
            // Go to the next destination mbuf segment.
            
            if (dst_len == 0) {
                if (!(dst = mbuf_next(dst)))
                    return (length == 0);
                dst_len = (int)mbuf_len(dst);
                dst_dat = (caddr_t)mbuf_data(dst);
            }

        } /* while (src_len) */

        src = mbuf_next(src);

    } /* while (src) */
    return (length == 0);   // returns true on success.
}

//---------------------------------------------------------------------------
// Replace the mbuf pointed by the given pointer with another mbuf.
// Drivers can call this method to replace a mbuf before passing the
// original mbuf, which contains a received frame, to the network layer.
//
// mp:   A pointer to the original mbuf that shall be updated by this
//       method to point to the new mbuf.
// size: If size is 0, then the new mbuf shall have the same size
//       as the original mbuf that is being replaced. Otherwise, the new
//       mbuf shall have the size specified here.
//
// If mbuf allocation was successful, then the replacement will
// take place and the original mbuf will be returned. Otherwise,
// a NULL is returned.

mbuf_t IONetworkController::replacePacket(mbuf_t * mp,
                                                 UInt32 size)
{   
    assert((mp != NULL) && (*mp != NULL));

    mbuf_t  m = *mp;

    // If size is zero, then size is taken from the source mbuf.

    if (size == 0) size = (UInt32)mbuf_pkthdr_len(m);
    
    // Allocate a new packet to replace the current packet.

    if ( (*mp = getPacket(size, MBUF_DONTWAIT, _alignStart, _alignLength)) == 0 )
    {
        *mp = m; m = 0;
    }

    return m;
}

//---------------------------------------------------------------------------
// Make a copy of a mbuf, and return the copy. The source mbuf is not modified.
//
// m:    The source mbuf.
// size: The number of bytes to copy. If set to 0, then the entire
//       source mbuf is copied.
//
// Returns a new mbuf created from the source packet.

mbuf_t IONetworkController::copyPacket(mbuf_t m,
                                              UInt32 size)
{
	mbuf_t mn;

    assert(m != NULL);

    // If size is zero, then size is taken from the source mbuf.

    if (size == 0) size = (UInt32)mbuf_pkthdr_len(m);
	
    // Copy the current mbuf to the new mbuf, and return the new mbuf.
    // The input mbuf is left intact.

    if ( (mn = getPacket(size, MBUF_DONTWAIT, _alignStart, _alignLength)) == 0 )
        return 0;

    if (!IO_COPY_MBUF(m, mn, size))
    {
        freePacket(mn); mn = 0;
    }

    return mn;
}

//---------------------------------------------------------------------------
// Either replace or copy the source mbuf given depending on the amount of
// data in the source mbuf. This method will either perform a copy or replace 
// the source mbuf, whichever is more time efficient. If replaced, then the
// original mbuf is returned, and a new mbuf is allocated to take its place.
// If copied, the source mbuf is left intact, while a copy is returned that
// is just big enough to hold all the data from the source mbuf.
//
// mp:        A pointer to the source mbuf that may be updated by this
//            method to point to the new mbuf if replaced.
// rcvlen:    The number of data bytes in the source mbuf.
// replacedP: Pointer to a bool that is set to true if the
//            source mbuf was replaced, or set to false if the
//            source mbuf was copied.
//
// Returns a replacement or a copy of the source mbuf, 0 if mbuf
// allocation failed.

mbuf_t IONetworkController::replaceOrCopyPacket(mbuf_t *mp,
                                                       UInt32 rcvlen,
                                                       bool * replacedP)
{
    mbuf_t m;

    assert((mp != NULL) && (*mp != NULL));
        
    if ( (rcvlen + _alignPadding) > mbuf_get_mhlen() )
    {
        // Large packet, it is more efficient to allocate a new mbuf
        // to replace the original mbuf than to make a copy. The new
        // packet shall have exactly the same size as the original
        // mbuf being replaced.

        m = *mp;

        if ( (*mp = getPacket( (UInt32)mbuf_pkthdr_len(m), MBUF_DONTWAIT,
                               _alignStart, _alignLength)) == 0 )
        {
            *mp = m; m = 0;  // error recovery
        }

        *replacedP = true;
    }
    else
    {
        // The copy will fit within a header mbuf. Fine, make a copy
        // of the original mbuf instead of replacing it. We only copy
        // the rcvlen bytes, not the entire source mbuf.

        if ( (m = getPacket( rcvlen, MBUF_DONTWAIT,
                             _alignStart, _alignLength )) == 0 ) return 0;

        if (!IO_COPY_MBUF(*mp, m, rcvlen))
        {
            freePacket(m); m = 0;
        }

        *replacedP = false;
    }

    return m;
}

//---------------------------------------------------------------------------
// Get hardware support of network/transport layer checksums.

IOReturn
IONetworkController::getChecksumSupport( UInt32 * checksumMask,
                                         UInt32   checksumFamily,
                                         bool     isOutput )
{
    return kIOReturnUnsupported;
}

//---------------------------------------------------------------------------
// Update a mbuf with the result from the hardware checksum engine.

#define kTransportLayerPartialChecksums \
        ( kChecksumTCPNoPseudoHeader |  \
          kChecksumUDPNoPseudoHeader |  \
          kChecksumTCPSum16 )

#define kTransportLayerFullChecksums    \
        ( kChecksumTCP | kChecksumUDP | kChecksumTCPIPv6 | kChecksumUDPIPv6 )

//PWC add kpi version when 3731343 is ready
void
IONetworkController::getChecksumDemand( const mbuf_t mt,
                                        UInt32              checksumFamily,
                                        UInt32 *            demandMask,
                                        void *              param0,
                                        void *              param1 )
{
    mbuf_csum_request_flags_t request;
	u_int32_t value;
	
	*demandMask = 0; 
	
	
	if ( checksumFamily != kChecksumFamilyTCPIP )
    {
        return;
    }
	
	mbuf_get_csum_requested(mt, &request, &value);
	
	// In theory we should be converting bits here from BSD->IOKit, however
	// the IONetworkingFamily definitions of checksum bits are the same as BSD's but do not
	// have to be.  Previously the family used them interchangeably, although it was not
	// technically correct to do so.  Now with KPIs it seems pretty safe to do it since the
	// bits have been defined as part of the KPI and can't change- but it's still not
	// "correct". (but it avoids a bunch of conversion logic)
	
    *demandMask = request & ( kChecksumIP       |
							  kChecksumTCP      |
							  kChecksumUDP      |
							  kChecksumTCPSum16 |
                              kChecksumTCPIPv6  |
                              kChecksumUDPIPv6 );
	
    if ( request & kChecksumTCPSum16 )
    {
        // param0 is start offset  (XXX - range?)
        // param1 is stuff offset  (XXX - range?)
		
        if (param0)
            *((UInt16 *) param0) = (UInt16) (value);
        if (param1)
            *((UInt16 *) param1) = (UInt16) (value >> 16);  
    }
}

bool
IONetworkController::setChecksumResult( mbuf_t mt,
                                        UInt32        family,
                                        UInt32        result,
                                        UInt32        valid,
                                        UInt32        param0,
                                        UInt32        param1 )
{
    mbuf_csum_performed_flags_t performed;
	u_int32_t value;
	// Reporting something that is valid without checking for it
    // is forbidden.
    valid &= result;
	
    // Initialize checksum result fields in the packet.
	
	performed = value = 0;
	
    if ( family != kChecksumFamilyTCPIP )
    {
        return false;
    }
	
    // Set the result for the network layer (IP) checksum.
	
    if ( result & kChecksumIP )
    {
        performed |= MBUF_CSUM_DID_IP;
        if ( valid & kChecksumIP )
            performed |= MBUF_CSUM_IP_GOOD;
    }
	
    // Now examine the transport layer checksum flags.
	
	if ( valid & kTransportLayerFullChecksums )
	{
        // Excellent, hardware did account for the pseudo-header
        // and no "partial" checksum value is required.
		
		performed |= ( MBUF_CSUM_DID_DATA | MBUF_CSUM_PSEUDO_HDR );
        value = 0xffff; // fake a valid checksum value
	}
	else if ( result & kTransportLayerPartialChecksums )
    {
        // Hardware does not account for the pseudo-header.
        // Driver must pass up the partial TCP/UDP checksum,
        // and the transport layer must adjust for the missing
        // 12-byte pseudo-header.
		
        performed |= MBUF_CSUM_DID_DATA;
        value   = (UInt16) param0;
		
        if ( result & kChecksumTCPSum16 )
        {
            // A very simple engine that only computes a ones complement
            // sum of 16-bit words (UDP/TCP style checksum), from a fixed
            // offset, without the ability to scan for the IP or UDP/TCP
            // headers. Must pass up the offset to the packet data where
            // the checksum computation started from.
            performed |= MBUF_CSUM_TCP_SUM16;
			value  |= (((UInt16) param1) << 16);
        }
    }
	mbuf_set_csum_performed(mt, performed, value);
    return true;
}

#if 0
//---------------------------------------------------------------------------
// Used for debugging only. Log the mbuf fields.

static void _logMbuf(struct mbuf * m)
{
    if (!m) {
        IOLog("logMbuf: NULL mbuf\n");
        return;
    }
    
    while (m) {
        IOLog("m_next   : %08x\n", (UInt) m->m_next);
        IOLog("m_nextpkt: %08x\n", (UInt) m->m_nextpkt);
        IOLog("m_len    : %d\n",   (UInt) m->m_len);
        IOLog("m_data   : %08x\n", (UInt) m->m_data);
        IOLog("m_type   : %08x\n", (UInt) m->m_type);
        IOLog("m_flags  : %08x\n", (UInt) m->m_flags);
        
        if (m->m_flags & MBUF_PKTHDR)
            IOLog("m_pkthdr.len  : %d\n", (UInt) m->m_pkthdr.len);

        if (m->m_flags & MBUF_EXT) {
            IOLog("m_ext.ext_buf : %08x\n", (UInt) m->m_ext.ext_buf);
            IOLog("m_ext.ext_size: %d\n", (UInt) m->m_ext.ext_size);
        }
        
        m = m->m_next;
    }
    IOLog("\n");
}
#endif /* 0 */

//---------------------------------------------------------------------------
// Allocate and attach a new IOKernelDebugger client object.
//
// debuggerP: A handle that is updated by this method
//            with the allocated IOKernelDebugger instance.
//
// Returns true on success, false otherwise.

bool IONetworkController::attachDebuggerClient(IOKernelDebugger ** debugger)
{
    IOKernelDebugger * client;
    bool               ret = false;
	UInt32 debugArg=0;

	// don't attach any debugger if kernel debugging isn't even enabled.
	PE_parse_boot_argn( "debug", &debugArg, sizeof (debugArg) );
	if(debugArg == 0)
	{
		*debugger = 0;
		return false;
	}
	
    // Prepare the controller.

    if (executeCommand(this, &IONetworkController::handleCommand,
                       this, (void *) kCommandPrepare) != kIOReturnSuccess)
    {
        return false;
    }

    // Create a debugger client nub and register the static
    // member functions as the polled-mode handlers.

    client = IOKernelDebugger::debugger( this,
                                         &debugTxHandler,
                                         &debugRxHandler,
                                         &debugLinkStatusHandler,
                                         &debugSetModeHandler);

    if ( client && !client->attach(this) )
    {
        // Unable to attach the client object.
        client->terminate( kIOServiceRequired | kIOServiceSynchronous );
        client->release();
        client = 0;
    }

    *debugger = client;    

    if ( client )
    {
        executeCommand( this, &IONetworkController::handleCommand,
                        this, (void *) kCommandInitDebugger,
                              (void *) client );

        client->registerService();
        ret = true;
    }

    return ret;
}

//---------------------------------------------------------------------------
// Detach and terminate the IOKernelDebugger client object provided.
// A synchronous termination is issued, and this method returns after
// the debugger client has been terminated.
//
// debugger: The IOKernelDebugger instance to be detached and terminated.
//           If the argument provided is NULL or is not an IOKernelDebugger,
//           this method will return immediately.

void IONetworkController::detachDebuggerClient(IOKernelDebugger * debugger)
{
    if (OSDynamicCast(IOKernelDebugger, debugger) == 0)
        return;

    // Terminate the debugger client and return after the client has
    // been terminated.

    debugger->terminate(kIOServiceRequired | kIOServiceSynchronous);
}

//---------------------------------------------------------------------------
// An enable request from an IOKernelDebugger client.

IOReturn IONetworkController::enable(IOKernelDebugger * debugger)
{
    return kIOReturnSuccess;
}

//---------------------------------------------------------------------------
// A disable request from an IOKernelDebugger client.

IOReturn IONetworkController::disable(IOKernelDebugger * debugger)
{
    return kIOReturnSuccess;
}

//---------------------------------------------------------------------------
// Take and release the debugger lock.

void IONetworkController::reserveDebuggerLock()
{
    if ( _debugLockCount++ == 0 )
    {
        _debugLockState = IODebuggerLock( this );
    }
}

void IONetworkController::releaseDebuggerLock()
{
    if ( --_debugLockCount == 0 )
    {
        IODebuggerUnlock( _debugLockState );
    }
    assert( _debugLockCount >= 0 );
}

//---------------------------------------------------------------------------
// This static C++ member function is registered by attachDebuggerClient()
// as the debugger receive handler. IOKernelDebugger will call this
// function when KDP is polling for a received packet. This function will
// in turn will call the receivePacket() member function implemented by
// a driver with debugger support.

void IONetworkController::debugRxHandler(IOService * handler,
                                         void *      buffer,
                                         UInt32 *    length,
                                         UInt32      timeout)
{
    ((IONetworkController *) handler)->receivePacket(buffer,
                                                     length,
                                                     timeout);   
}

//---------------------------------------------------------------------------
// This static C++ member function is registered by attachDebuggerClient()
// as the debugger transmit handler. IOKernelDebugger will call this
// function when KDP sends an outgoing packet. This function will in turn
// call the sendPacket() member function implemented by a driver with
// debugger support.

void IONetworkController::debugTxHandler(IOService * handler,
                                         void *      buffer,
                                         UInt32      length)
{
    ((IONetworkController *) handler)->sendPacket(buffer, length);
}

//---------------------------------------------------------------------------
// This static C++ member function is registered by attachDebuggerClient()
// as the debugger link status handler. IOKernelDebugger will call this
// function to check the link status. This function will in turn
// call the getDebuggerLinkStatus() member function implemented by a driver with
// debugger support.

UInt32 IONetworkController::debugLinkStatusHandler(IOService * handler)
{
    return ((IONetworkController *) handler)->getDebuggerLinkStatus();
}

//---------------------------------------------------------------------------
// This static C++ member function is registered by
// attachDebuggerClient() as the debugger set mode
// handler. IOKernelDebugger will call this function to inform the
// driver whether or not the debugger is active. This function will in
// turn call the setDebuggerMode() member function implemented by a
// driver with debugger support.
bool IONetworkController::debugSetModeHandler(IOService * handler,
                                              bool active)
{
    return ((IONetworkController *) handler)->setDebuggerMode(active);
}

//---------------------------------------------------------------------------
// This method must be implemented by a driver that supports kernel debugging.
// After a debugger client is attached through attachDebuggerClient(), this
// method will be called by the debugger client to poll for a incoming packet
// when the debugger session is active. This method may be called from the
// primary interrupt context, implementation must avoid any memory allocation,
// and must never block. The receivePacket() method in IONetworkController is
// used as a placeholder and should not be called. A driver that attaches
// a debugger client must override this method.
//
// pkt:     Pointer to a receive buffer where the received packet should
//          be stored to. The buffer has enough space for 1518 bytes.
// pkt_len: The length of the received packet must be written to the
//          integer pointed by pkt_len.
// timeout: The maximum amount of time in milliseconds to poll for
//          a packet to arrive before this method must return.

void IONetworkController::receivePacket(void *   /*pkt*/,
                                        UInt32 * /*pkt_len*/,
                                        UInt32   /*timeout*/)
{
    IOLog("IONetworkController::%s()\n", __FUNCTION__);
}

//---------------------------------------------------------------------------
// Debugger polled-mode transmit handler. This method must be implemented
// by a driver that supports kernel debugging. After a debugger client is 
// attached through attachDebuggerClient(), this method will be called by the
// debugger to send an outbound packet when the kernel debugger is active.
// This method may be called from the primary interrupt context, and the
// implementation must avoid any memory allocation, and must never block.
// sendPacket() method in IONetworkController is used as a placeholder
// and should not be called. A driver that attaches a debugger client
// must override this method.
//
// pkt:     Pointer to a transmit buffer containing the packet to be sent.
// pkt_len: The amount of data in the transmit buffer.

void IONetworkController::sendPacket(void * /*pkt*/, UInt32 /*pkt_len*/)
{
    IOLog("IONetworkController::%s()\n", __FUNCTION__);
}

//---------------------------------------------------------------------------
// Debugger polled-mode link status handler. This method must be
// implemented by a driver that supports early access kernel
// debugging. After a debugger client is attached through
// attachDebuggerClient(), this method will be called by the debugger
// to determine link status when the kernel debugger is active.  This
// method may be called from the primary interrupt context, and the
// implementation must avoid any memory allocation, must not spin, and
// must never block. getDebuggerLinkStatus() method in IONetworkController
// is used as a placeholder. A driver that attaches a debugger client and
// wishes to enable early kernel debugging should override this method.
//
UInt32 IONetworkController::getDebuggerLinkStatus(void)
{
    return _linkStatus->unsigned32BitValue() | kIONetworkLinkValid | kIONetworkLinkActive;
}

//---------------------------------------------------------------------------
// Debugger polled-mode active/inactive handler. After a debugger
// client is attached through attachDebuggerClient(), this method will
// be called by the debugger to inform the driver whether or not the
// kernel debugger is active.  This method may be called from the
// primary interrupt context, and the implementation must avoid any
// memory allocation, must not spin, and must never block.  The
// setDebuggerMode() method in IONetworkController is used as a
// placeholder.  A driver that attaches a debugger client and wishes
// to enable/disable features dependent upon being in the kernel
// debugger should override this method.
//
// active: true if entering/in KDP. false if leaving KDP.

bool IONetworkController::setDebuggerMode(__unused bool active)
{
    return true;
}

//---------------------------------------------------------------------------
// Report the link status and the active medium.

bool IONetworkController::setLinkStatus(
    UInt32                  linkStatus,
    const IONetworkMedium * activeMedium,
    UInt64                  linkSpeed,
    OSData *                linkData )
{
    bool                    success   = true;
    UInt32                  linkEvent = 0;
    UInt32                  oldLinkStatus;
    const OSSymbol *        linkName  = gIONullMediumName;
    IONetworkLinkEventData  linkEventData;

    if (linkData == 0)
        linkData = (OSData *) gIONullLinkData;

    bzero(&linkEventData, sizeof(linkEventData));
    if (activeMedium)
    {
        linkName = activeMedium->getName();
        linkEventData.linkType = activeMedium->getType();
        if (!linkSpeed) linkSpeed = activeMedium->getSpeed();
    }

    MEDIUM_LOCK;

    // Update kIOActiveMedium property.
	if (linkName != _lastActiveMediumName)
    {
        if (setProperty(gIOActiveMediumKey, (OSObject *) linkName))
            _lastActiveMediumName = linkName;
        else
            success = false;
    }

	// Update kIOLinkData property.
    if (linkData != _lastLinkData)
    {
        if (setProperty(gIOLinkDataKey, linkData))
            _lastLinkData = linkData;
        else
            success = false;
    }

    // Update kIOLinkSpeed property.
	if (linkSpeed != _linkSpeed->unsigned64BitValue())
	{
		_linkSpeed->setValue(linkSpeed);
        linkEvent = kIONetworkEventTypeLinkSpeedChange;
        linkEventData.linkSpeed = linkSpeed;
    }

	// Update kIOLinkStatus property.
    oldLinkStatus = _linkStatus->unsigned32BitValue();
	if (linkStatus != oldLinkStatus)
	{
        if ((linkStatus ^ oldLinkStatus) &
            (kIONetworkLinkActive | kIONetworkLinkValid |
             kIONetworkLinkNoNetworkChange))
        {
            // Send link UP event when the link is up, or its state is unknown
            if ((linkStatus & kIONetworkLinkActive) ||
                !(linkStatus & kIONetworkLinkValid))
                linkEvent = kIONetworkEventTypeLinkUp;
            else
                linkEvent = kIONetworkEventTypeLinkDown;

            linkEventData.linkStatus = linkStatus;
            linkEventData.linkSpeed = _linkSpeed->unsigned64BitValue();
        }
        DLOG("%s: set link status 0x%x\n", getName(), (uint32_t) linkStatus);
        _linkStatus->setValue(linkStatus);
	}

    MEDIUM_UNLOCK;

    // Broadcast a link event to interface objects.
    if (linkEvent)
        _broadcastEvent(linkEvent, &linkEventData);

    return success;
}

//---------------------------------------------------------------------------
// Returns the medium dictionary published by the driver through
// publishMediumDictionary(). Use copyMediumDictionary() to get a copy
// of the medium dictionary.
//
// Returns the published medium dictionary, or 0 if the driver has not
// yet published a medium dictionary through publishMediumDictionary().

const OSDictionary * IONetworkController::getMediumDictionary() const
{
    return (OSDictionary *) getProperty(kIOMediumDictionary);
}

//---------------------------------------------------------------------------
// Returns a copy of the medium dictionary published by the driver.
// The caller is responsible for releasing the dictionary object returned.
// Use getMediumDictionary() to get a reference to the published medium
// dictionary instead of creating a copy.
//
// Returns a copy of the medium dictionary, or 0 if the driver has not
// published a medium dictionary through publishMediumDictionary().

OSDictionary * IONetworkController::copyMediumDictionary() const
{
    const OSDictionary * mediumDict;
    OSDictionary *       copy = 0;

    MEDIUM_LOCK;

    mediumDict = getMediumDictionary();

    if (mediumDict)
    {
        copy = OSDictionary::withDictionary(mediumDict,
                                            mediumDict->getCount());
    }

    MEDIUM_UNLOCK;

    return copy;
}

//---------------------------------------------------------------------------
// A client request to change the media selection.

IOReturn IONetworkController::selectMedium(const IONetworkMedium * medium)
{
    return kIOReturnUnsupported;
}

//---------------------------------------------------------------------------
// Private function to lookup a key in the medium dictionary and call 
// setMedium() if a match is found. This function is called by our
// clients to change the medium selection by passing a name for the desired
// medium.

IOReturn IONetworkController::selectMediumWithName(const OSSymbol * mediumName)
{
    OSSymbol *        currentMediumName;
    IONetworkMedium * newMedium = 0;
    bool              doChange  = true;
    IOReturn          ret       = kIOReturnSuccess;

    if (OSDynamicCast(OSSymbol, mediumName) == 0)
        return kIOReturnBadArgument;

    MEDIUM_LOCK;

    do {
        const OSDictionary * mediumDict = getMediumDictionary();
        if (!mediumDict)
        {
        	// no medium dictionary, bail out.
            ret = kIOReturnUnsupported;
            break;
        }

        // Lookup the new medium in the dictionary.

        newMedium = (IONetworkMedium *) mediumDict->getObject(mediumName);
        if (!newMedium)
        {
            ret = kIOReturnBadArgument;
            break;          // not found, invalid mediumName.
        }

        newMedium->retain();

        // Lookup the current medium key to avoid unnecessary
        // medium changes.

        currentMediumName = (OSSymbol *) getProperty(gIOCurrentMediumKey);

        // Is change necessary?

        if (currentMediumName && mediumName->isEqualTo(currentMediumName))
            doChange = false;
    }
    while (0);

    MEDIUM_UNLOCK;

    if (newMedium)
    {
        // Call the driver's selectMedium() without holding the medium lock.
    
        if (doChange)
            ret = selectMedium(newMedium);

        // Remove the earlier retain.

        newMedium->release();
    }

    return ret;
}

//---------------------------------------------------------------------------
// Designate an entry in the published medium dictionary as
// the current selected medium.

bool IONetworkController::setSelectedMedium(const IONetworkMedium * medium)
{
    bool  success = true;
    bool  changed = false;
    const OSSymbol * name = medium ? medium->getName() : gIONullMediumName;

    MEDIUM_LOCK;

    if (name != _lastCurrentMediumName)
	{
		if ( setProperty(gIOCurrentMediumKey, (OSSymbol *) name) )
	    {
			changed                = true;
			_lastCurrentMediumName = name;
		}
		else
			success = false;
	}

    MEDIUM_UNLOCK;

#if 0
    if (changed)
        _broadcastEvent(kIONetworkEventTypeLinkChange);
#endif

    return success;
}

//---------------------------------------------------------------------------
// Get the current selected medium.

const IONetworkMedium * IONetworkController::getSelectedMedium() const
{
    IONetworkMedium * medium = 0;
    OSSymbol *        mediumName;

    MEDIUM_LOCK;

    do {
        const OSDictionary * mediumDict = getMediumDictionary();
        if (!mediumDict)    // no medium dictionary, bail out.
            break;

        // Fetch the current medium name from the property table.

        mediumName = (OSSymbol *) getProperty(gIOCurrentMediumKey);

        // Make sure the current medium name points to an entry in
        // the medium dictionary.

        medium = (IONetworkMedium *) mediumDict->getObject(mediumName);

        // Invalid current medium, try the default medium.

        if ( medium == 0 )
        {
            OSString * aString;

            // This comes from the driver's property list.
            // More checking is done to avoid surprises.

            aString = OSDynamicCast( OSString,
                                     getProperty(gIODefaultMediumKey) );
            if ( aString )
                medium = (IONetworkMedium *) mediumDict->getObject(aString);
        }
    }
    while (0);

    MEDIUM_UNLOCK;

    return medium;
}

//---------------------------------------------------------------------------
// A private function to verify a medium dictionary. Returns true if the
// dictionary is OK.

static bool verifyMediumDictionary(const OSDictionary * mediumDict)
{
    OSCollectionIterator * iter;
    bool                   verifyOk = true;
    OSSymbol *             key;

    if (!OSDynamicCast(OSDictionary, mediumDict))
        return false;   // invalid argument

    if (mediumDict->getCount() == 0)
        return false;   // empty dictionary

    iter = OSCollectionIterator::withCollection((OSDictionary *) mediumDict);
    if (!iter)
        return false;   // cannot allocate iterator

    while ((key = (OSSymbol *) iter->getNextObject()))
    {
        if ( !OSDynamicCast(IONetworkMedium, mediumDict->getObject(key)) )
        {
            verifyOk = false;   // non-medium object in dictionary
            break;
        }
    }

    iter->release();
    
    return verifyOk;
}

//---------------------------------------------------------------------------
// Publish a dictionary of IONetworkMedium objects.

bool
IONetworkController::publishMediumDictionary(const OSDictionary * mediumDict)
{
    OSDictionary *   cloneDict;
    bool             ret = false;

    if (!verifyMediumDictionary(mediumDict))
        return false;   // invalid dictionary

    // Create a clone of the source dictionary. This prevents the driver
    // from adding/removing entries after the medium dictionary is added
    // to the property table.

    cloneDict = OSDictionary::withDictionary(mediumDict,
                                             mediumDict->getCount());
    if (!cloneDict)
        return false;  // unable to create a copy

    MEDIUM_LOCK;                            

    // Add the dictionary to the property table.

    if (setProperty(kIOMediumDictionary, cloneDict))
    {
        const OSSymbol * mediumName;

        // Update kIOSelectedMedium property.

        mediumName = (OSSymbol *) getProperty(gIOCurrentMediumKey);
        if (cloneDict->getObject(mediumName) == 0)
        {
            mediumName = gIONullMediumName;
        }
        setProperty(gIOCurrentMediumKey, (OSSymbol *) mediumName);
        _lastCurrentMediumName = mediumName;

        // Update kIOActiveMedium property.

        mediumName = (OSSymbol *) getProperty(gIOActiveMediumKey);
        if (cloneDict->getObject(mediumName) == 0)
        {
            mediumName = gIONullMediumName;
        }
        setProperty(gIOActiveMediumKey, (OSSymbol *) mediumName);
        _lastActiveMediumName = mediumName;

        ret = true;
    }

    MEDIUM_UNLOCK;

    // Retained by the property table. drop our retain count.

    cloneDict->release();

#if 0
    // Broadcast a link change event.

    _broadcastEvent(kIONetworkEventTypeLinkChange);
#endif

    return ret;
}

//---------------------------------------------------------------------------
// Static function called by the internal IOCommandGate object to
// handle a runAction() request invoked by executeCommand().

IOReturn IONetworkController::executeCommandAction(OSObject * owner,
                                                   void *     arg0,
                                                   void *  /* arg1 */,
                                                   void *  /* arg2 */,
                                                   void *  /* arg3 */)
{
    IONetworkController * self = (IONetworkController *) owner;
    cmdStruct *           cmdP = (cmdStruct *) arg0;
    IOReturn              ret  = kIOReturnSuccess;
    OSObject *            oldClient;

    assert(cmdP && self);

    oldClient = self->_cmdClient;

    self->_cmdClient = cmdP->client;

    cmdP->ret = (*cmdP->action)( cmdP->target,
                                 cmdP->param0,
                                 cmdP->param1,
                                 cmdP->param2,
                                 cmdP->param3 );

    self->_cmdClient = oldClient;

    return ret;
}

//---------------------------------------------------------------------------
// Perform an "action" that is synchronized by the command gate.

IOReturn IONetworkController::executeCommand(OSObject * client,
                                             Action     action,
                                             void *     target,
                                             void *     param0,
                                             void *     param1,
                                             void *     param2,
                                             void *     param3)
{
    cmdStruct  cmd;
    IOReturn   ret;

    cmd.client  = client;
    cmd.action  = action;
    cmd.target  = target;
    cmd.param0  = param0;
    cmd.param1  = param1;
    cmd.param2  = param2;
    cmd.param3  = param3;

    // Execute the client command through the command gate. Client commands
    // are thus synchronized with the workloop returned by getWorkLoop().

    ret = _cmdGate->runAction( (IOCommandGate::Action)
                               &IONetworkController::executeCommandAction,
                               (void *) &cmd );    /* arg0 - cmdStruct */

    // If executeCommandAction() executed successfully, then return the
    // status from the client command that was executed.

    if (ret == kIOReturnSuccess)
        ret = cmd.ret;

    return ret;
}

//---------------------------------------------------------------------------
// Called by executeCommand() to handle the client command on the
// workloop context.

void countBSDEnablesApplier( IOService * client, void * context )
{
    if ( OSDynamicCast( IONetworkInterface, client ) &&
         client->getProperty( gIOControllerEnabledKey ) == kOSBooleanTrue )
        (*(UInt32 *)context)++;
}

IOReturn IONetworkController::handleCommand(void * target,
                                            void * param0,
                                            void * param1,
                                            void * param2,
                                            void * param3)
{

    IONetworkController * self    = (IONetworkController *) target;
    UInt32                command = (UInt32)((uintptr_t) param0);
    IOService *           client  = (IOService *) param1;
    IOReturn              ret     = kIOReturnSuccess;
    UInt32                count   = 0;

    switch ( command )
    {
        case kCommandEnable:
            if (( ret = self->enable(client) ) == kIOReturnSuccess )
            {
                // Record the client enable, and send messages to inform
                // interested clients.

                client->setProperty( gIOControllerEnabledKey, kOSBooleanTrue );
                if ( OSDynamicCast( IONetworkInterface, client ) )
                {
                    self->applyToClients( countBSDEnablesApplier, &count );
                    if ( count == 1 )
                        self->messageClients(kMessageControllerWasEnabledForBSD);
                }
                self->messageClients(kMessageControllerWasEnabled, client);
            }
            break;

        case kCommandDisable:
            if (( ret = self->disable(client) ) == kIOReturnSuccess )
            {
                // Record the client disable, and send messages to inform
                // interested clients.

                client->setProperty( gIOControllerEnabledKey, kOSBooleanFalse );
                if ( OSDynamicCast( IONetworkInterface, client ) )
                {
                    self->applyToClients( countBSDEnablesApplier, &count );
                    if ( count == 0 )
                        self->messageClients(kMessageControllerWasDisabledForBSD);
                }
                self->messageClients(kMessageControllerWasDisabled, client);
            }
            break;

        case kCommandPrepare:
            ret = self->prepare();
            break;

        case kCommandInitDebugger:
            // Send a message to the debugger to announce the controller's
            // enable/disable state when the debugger is first attached as
            // a client. This eliminate problems with lost messages if the
            // debugger is attached after the BSD client has attached and
            // enabled the controller, and early debugging is not active.

            self->applyToClients( countBSDEnablesApplier, &count );
            if ( count )
                client->message( kMessageControllerWasEnabledForBSD, self );
            break;

        default:
            ret = kIOReturnUnsupported;
            break;
    }

    return ret;
}

//---------------------------------------------------------------------------
// Issue an kCommandEnable command to handleCommand().

IOReturn IONetworkController::doEnable(IOService * client)
{
	return executeCommand( client,
                           &IONetworkController::handleCommand,
                           this,
                           (void *) kCommandEnable,
                           (void *) client);
}

//---------------------------------------------------------------------------
// Issue an kCommandDisable command to handleCommand().

IOReturn IONetworkController::doDisable(IOService * client)
{
	return executeCommand( client,
                           &IONetworkController::handleCommand,
                           this,
                           (void *) kCommandDisable,
                           (void *) client);
}

//---------------------------------------------------------------------------
// Inlined functions pulled from header file to ensure
// binary compatibility with drivers built with gcc2.95.

const IONetworkMedium * IONetworkController::getCurrentMedium() const
{
    return getSelectedMedium();
}

bool IONetworkController::setCurrentMedium(const IONetworkMedium * medium)
{
    return setSelectedMedium(medium);
}

//---------------------------------------------------------------------------

void IONetworkController::systemWillShutdown( IOOptionBits specifier )
{
    if (specifier == kIOMessageSystemWillPowerOff ||
        specifier == kIOMessageSystemWillRestart)
    {
        messageClients(kMessageControllerWillShutdown);
    }

    super::systemWillShutdown(specifier);
}

//---------------------------------------------------------------------------

IOReturn IONetworkController::setAggressiveness(
    unsigned long type, unsigned long newLevel )
{
    // Tell interface object(s) that WOMP support has changed.

    if ((kPMEthernetWakeOnLANSettings == type) && _clientSetIter)
    {
        _broadcastEvent( kIONetworkEventWakeOnLANSupportChanged );
    }    

    return super::setAggressiveness(type, newLevel);
}

//---------------------------------------------------------------------------

IOReturn IONetworkController::message(
    UInt32 type, IOService * provider, void * argument )
{
    if (kIOMessageDeviceSignaledWakeup == type)
    {
        return provider->callPlatformFunction(
                    "IOPlatformDeviceSignaledWakeup",
                    false,
                    (void *) this, 0, 0, 0);
    }

    return super::message(type, provider, argument);
}

//---------------------------------------------------------------------------

IOReturn IONetworkController::outputStart(
    IONetworkInterface *    interface,
    IOOptionBits            options )
{
    return kIOReturnUnsupported;
}

IOReturn IONetworkController::setInputPacketPollingEnable(
    IONetworkInterface *    interface,
    bool                    enabled )
{
    return kIOReturnUnsupported;
}

void IONetworkController::pollInputPackets(
    IONetworkInterface *    interface,
    uint32_t                maxCount,
    IOMbufQueue *           pollQueue,
    void *                  context )
{
}

//------------------------------------------------------------------------------

IOMbufServiceClass IONetworkController::getMbufServiceClass( mbuf_t mbuf )
{
    mbuf_svc_class_t    mbufSC = mbuf_get_service_class(mbuf);
    IOMbufServiceClass  ioSC;

    switch (mbufSC)
    {
        default:
        case MBUF_SC_BE:     ioSC = kIOMbufServiceClassBE;  break;
        case MBUF_SC_BK_SYS: ioSC = kIOMbufServiceClassBKSYS; break;
        case MBUF_SC_BK:     ioSC = kIOMbufServiceClassBK;  break;
        case MBUF_SC_RD:     ioSC = kIOMbufServiceClassRD;  break;
        case MBUF_SC_OAM:    ioSC = kIOMbufServiceClassOAM; break;
        case MBUF_SC_AV:     ioSC = kIOMbufServiceClassAV;  break;
        case MBUF_SC_RV:     ioSC = kIOMbufServiceClassRV;  break;
        case MBUF_SC_VI:     ioSC = kIOMbufServiceClassVI;  break;
        case MBUF_SC_VO:     ioSC = kIOMbufServiceClassVO;  break;
        case MBUF_SC_CTL:    ioSC = kIOMbufServiceClassCTL; break;
    }

    return ioSC;
}

//------------------------------------------------------------------------------

IOReturn IONetworkController::networkInterfaceNotification(
    IONetworkInterface *    interface,
    uint32_t                type,
    void *                  argument )
{
    return kIOReturnUnsupported;
}

//------------------------------------------------------------------------------

IOReturn IONetworkController::attachAuxiliaryDataToPacket(
    mbuf_t          packet,
    const void *    data,
    IOByteCount     length,
    uint32_t        family,
    uint32_t        subFamily )
{
    errno_t error;
    void *  data_p = 0;

    if (!packet || !data || !length)
        return kIOReturnBadArgument;

    error = mbuf_add_drvaux(packet, MBUF_WAITOK, family, subFamily,
                            (size_t) length, &data_p);
    if (error)
    {
        return IONetworkInterface::errnoToIOReturn(error);
    }

    if (data_p)
        bcopy(data, data_p, length);

    return kIOReturnSuccess;
}

void IONetworkController::removeAuxiliaryDataFromPacket(
    mbuf_t      packet )
{
    mbuf_del_drvaux(packet);
}
