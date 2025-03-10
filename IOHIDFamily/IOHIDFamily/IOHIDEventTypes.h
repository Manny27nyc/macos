/*
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * Copyright (c) 1999-2003 Apple Computer, Inc.  All Rights Reserved.
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

#ifndef _IOKIT_IOHIDEVENTTYPES_H
#define _IOKIT_IOHIDEVENTTYPES_H /* { */

#include <TargetConditionals.h>

#if TARGET_OS_DRIVERKIT
#include <DriverKit/IOTypes.h>
#else
#include <IOKit/IOTypes.h>
#endif

#define IOHIDEventTypeMask(type) (1LL<<type)
#define IOHIDEventFieldBase(type) (type << 16)
#define IOHIDEventFieldOffsetOf(field) (field & 0xffff)
/*!
    @typedef IOHIDEventType
    @abstract The type of event represented by an IOHIDEventRef.
    @discussion It is possible that a single IOHIDEventRef can conform to
    multiple event types through the use of sub events.  For further information
    as to how to determine the type of event please reference IOHIDEventGetType 
    and IOHIDEventConformsTo.
    @constant kIOHIDEventTypeNULL
    @constant kIOHIDEventTypeVendorDefined
    @constant kIOHIDEventTypeButton
    @constant kIOHIDEventTypeKeyboard
    @constant kIOHIDEventTypeTranslation
    @constant kIOHIDEventTypeRotation
    @constant kIOHIDEventTypeScroll
    @constant kIOHIDEventTypeScale
    @constant kIOHIDEventTypeZoom
    @constant kIOHIDEventTypeVelocity
    @constant kIOHIDEventTypeOrientation
    @constant kIOHIDEventTypeDigitizer
    @constant kIOHIDEventTypeAmbientLightSensor
    @constant kIOHIDEventTypeAccelerometer
    @constant kIOHIDEventTypeProximity
    @constant kIOHIDEventTypeTemperature
    @constant kIOHIDEventTypeNavigationSwipe
    @constant kIOHIDEventTypePointer
    @constant kIOHIDEventTypeProgress
    @constant kIOHIDEventTypeMultiAxisPointer
    @constant kIOHIDEventTypeGyro
    @constant kIOHIDEventTypeCompass
    @constant kIOHIDEventTypeZoomToggle
    @constant kIOHIDEventTypeDockSwipe
    @constant kIOHIDEventTypeSymbolicHotKey
    @constant kIOHIDEventTypePower
    @constant kIOHIDEventTypeLED
    @constant kIOHIDEventTypeFluidTouchGesture
    @constant kIOHIDEventTypeBoundaryScroll
    @constant kIOHIDEventTypeBiometric
    @constant kIOHIDEventTypeUnicode
    @constant kIOHIDEventTypeAtmosphericPressure
    @constant kIOHIDEventTypeMotionActivity
    @constant kIOHIDEventTypeMotionGesture
    @constant kIOHIDEventTypeGameController
    @constant kIOHIDEventTypeHumidity
    @constant kIOHIDEventTypeCollection
    @constant kIOHIDEventTypeSwipe DEPRECATED
    @constant kIOHIDEventTypeMouse DEPRECATED

*/
enum {
    kIOHIDEventTypeNULL,                    // 0
    kIOHIDEventTypeVendorDefined,
    kIOHIDEventTypeButton,
    kIOHIDEventTypeKeyboard, 
    kIOHIDEventTypeTranslation,
    kIOHIDEventTypeRotation,                // 5
    kIOHIDEventTypeScroll,
    kIOHIDEventTypeScale,
    kIOHIDEventTypeZoom,
    kIOHIDEventTypeVelocity,
    kIOHIDEventTypeOrientation,             // 10
    kIOHIDEventTypeDigitizer,
    kIOHIDEventTypeAmbientLightSensor,
    kIOHIDEventTypeAccelerometer,
    kIOHIDEventTypeProximity,
    kIOHIDEventTypeTemperature,             // 15
    kIOHIDEventTypeNavigationSwipe,
    kIOHIDEventTypePointer,
    kIOHIDEventTypeProgress,
    kIOHIDEventTypeMultiAxisPointer,
    kIOHIDEventTypeGyro,                    // 20
    kIOHIDEventTypeCompass,
    kIOHIDEventTypeZoomToggle,
    kIOHIDEventTypeDockSwipe,               // just like kIOHIDEventTypeNavigationSwipe, but intended for consumption by Dock
    kIOHIDEventTypeSymbolicHotKey,
    kIOHIDEventTypePower,                   // 25
    kIOHIDEventTypeLED,
    kIOHIDEventTypeFluidTouchGesture,       // This will eventually supersede Navagation and Dock swipes
    kIOHIDEventTypeBoundaryScroll,
    kIOHIDEventTypeBiometric,
    kIOHIDEventTypeUnicode,                 // 30
    kIOHIDEventTypeAtmosphericPressure,
    kIOHIDEventTypeForce,
    kIOHIDEventTypeMotionActivity,
    kIOHIDEventTypeMotionGesture,
    kIOHIDEventTypeGameController,          // 35
    kIOHIDEventTypeHumidity,
    kIOHIDEventTypeCollection,
    kIOHIDEventTypeBrightness,
    kIOHIDEventTypeGenericGesture,
    kIOHIDEventTypeCount, // This should always be last
    
    
    // DEPRECATED:
    kIOHIDEventTypeSwipe = kIOHIDEventTypeNavigationSwipe,
    kIOHIDEventTypeMouse = kIOHIDEventTypePointer
};

typedef uint32_t IOHIDEventType;

typedef uint32_t IOHIDEventField;

typedef uint32_t IOHIDGenericGestureType;

typedef uint8_t IOHIDDigitizerOrientationType;

#if TARGET_OS_DRIVERKIT
#include <HIDDriverKit/IOHIDEventFieldDefs.h>
#else
#include <IOKit/hid/IOHIDEventFieldDefs.h>
#endif

enum  {
    kIOHIDGenericGestureTypeTap        = 0,
    kIOHIDGenericGestureTypeSwipe
};

enum {
    kIOHIDDigitizerOrientationTypeTilt = 0,
    kIOHIDDigitizerOrientationTypePolar,
    kIOHIDDigitizerOrientationTypeQuality
};

enum {
    kIOHIDEventFieldMultiAxisPointerButtonNumber        = kIOHIDEventFieldButtonNumber,
    kIOHIDEventFieldMultiAxisPointerButtonClickCount    = kIOHIDEventFieldButtonClickCount,
    kIOHIDEventFieldMultiAxisPointerButtonPressure      = kIOHIDEventFieldButtonPressure
};

enum {
    kIOHIDEventFieldPointerButtonNumber     = kIOHIDEventFieldButtonNumber,
    kIOHIDEventFieldPointerButtonClickCount = kIOHIDEventFieldButtonClickCount,
    kIOHIDEventFieldPointerButtonPressure   = kIOHIDEventFieldButtonPressure
};

/* DEPRECATED: use pointer field */
enum {
    kIOHIDEventFieldMouseX          = kIOHIDEventFieldPointerX,
    kIOHIDEventFieldMouseY          = kIOHIDEventFieldPointerY,
    kIOHIDEventFieldMouseZ          = kIOHIDEventFieldPointerZ,
    kIOHIDEventFieldMouseButtonMask = kIOHIDEventFieldPointerButtonMask,
    kIOHIDEventFieldMouseNumber     = kIOHIDEventFieldPointerButtonNumber,
    kIOHIDEventFieldMouseClickCount = kIOHIDEventFieldPointerButtonClickCount,
    kIOHIDEventFieldMousePressure   = kIOHIDEventFieldPointerButtonPressure
};

/* DEPRECATED: misspelled */
enum {
    kIOHIDEventFieldNavagationSwipeFlavor       = kIOHIDEventFieldNavigationSwipeFlavor
};

enum {
    kIOHIDEventFieldForceLean                   = kIOHIDEventFieldForceStagePressure,
    kIOHIDEventFieldForceTransitionProgress     = kIOHIDEventFieldForceProgress
};

enum  {
    kIOHIDEventFieldDigitizerEstimatedMask      =  (kIOHIDEventFieldDigitizerBase | 30)
};

/*!
 @typedef IOHIDMotionType
 @abstract  Type of Motion event triggered.
 @constant kIOHIDMotionTypeNormal
 @constant kIOHIDMotionTypeShake
 */
enum {
    kIOHIDMotionTypeNormal   = 0,
    kIOHIDMotionTypeShake    = 1,
    kIOHIDMotionTypePath     = 2
};
typedef uint32_t IOHIDMotionType;

/*!
 @typedef IOHIDMotionPath
 @abstract Type of Motion Path event triggered.
 @constant IOHIDMotionPathStart
 @constant IOHIDMotionPathEnd
 */
enum {
    kIOHIDMotionPathStart   = 0,
    kIOHIDMotionPathEnd     = 1,
};
typedef uint32_t IOHIDMotionPath;

// Legacy
enum {
    kIOHIDAccelerometerTypeNormal   = kIOHIDMotionTypeNormal,
    kIOHIDAccelerometerTypeShake    = kIOHIDMotionTypeShake,
    kIOHIDGyroTypeNormal            = kIOHIDMotionTypeNormal,
    kIOHIDGyroTypeShake             = kIOHIDMotionTypeShake,
};

typedef IOHIDMotionType IOHIDAccelerometerType;
typedef IOHIDMotionPath IOHIDAccelerometerSubType;


typedef IOHIDMotionType IOHIDGyroType;
typedef IOHIDMotionPath IOHIDGyroSubType;


typedef IOHIDMotionType IOHIDCompassType;
typedef IOHIDMotionPath IOHIDCompassSubType;


enum {
    kIOHIDKeyboardLongPress                     = 1,
    kIOHIDKeyboardLongPressBit                  = 0,
    kIOHIDKeyboardLongPressMask                 = (kIOHIDKeyboardLongPress << kIOHIDKeyboardLongPressBit),
};

enum {
    kIOHIDKeyboardClickSpeedNone                = 0,
    kIOHIDKeyboardClickSpeedSlow                = 1,
    kIOHIDKeyboardClickSpeedNormal              = 2,
    kIOHIDKeyboardClickSpeedFast                = 3,
    kIOHIDKeyboardClickSpeedStartBit            = 1,
    kIOHIDKeyboardClickSpeedMask                = (0x3 << kIOHIDKeyboardClickSpeedStartBit),
};

enum {
    kIOHIDKeyboardSlowKeyNone                  = 0,
    kIOHIDKeyboardSlowKeyPhaseStart            = 1,
    kIOHIDKeyboardSlowKeyPhaseAbort            = 2,
    kIOHIDKeyboardSlowKeyOn                    = 3,
    kIOHIDKeyboardSlowKeyPhaseBit              = 3,
    kIOHIDKeyboardSlowKeyPhaseMask             = (0x3 << kIOHIDKeyboardSlowKeyPhaseBit),
};

enum {
    kIOHIDKeyboardMouseKeyToggle                = 1,
    kIOHIDKeyboardMouseKeyToggleBit             = 5,
    kIOHIDKeyboardMouseKeyToggleMask            = (1 << kIOHIDKeyboardMouseKeyToggleBit),
};


/*!
 @typedef IOHIDPowerType
 @abstract Type of Power event triggered.
 @constant kIOHIDPowerTypePower
 @constant kIOHIDPowerTypeCurrent
 @constant kIOHIDPowerTypeVoltage
 */
enum {
    kIOHIDPowerTypePower    = 0,
    kIOHIDPowerTypeCurrent  = 1,
    kIOHIDPowerTypeVoltage  = 2
};
typedef uint32_t IOHIDPowerType;

/*!
 @typedef IOHIDPowerSubType
 @abstract Reserved
 @constant kIOHIDPowerSubTypeNormal
 @constant kIOHIDPowerSubTypeCumulative
 */
enum {
    kIOHIDPowerSubTypeNormal = 0,
    kIOHIDPowerSubTypeCumulative
};
typedef uint32_t IOHIDPowerSubType;


/*!
 @typedef IOHIDBiometricEventType
 @abstract Type of biometric event triggered.
 @constant kIOHIDBiometricEventTypeHumanProximity
 @constant kIOHIDBiometricEventTypeHumanTouch
 @constant kIOHIDBiometricEventTypeHumanForce
 @constant kIOHIDBiometricEventTypeHumanPresence
 */
enum {
    kIOHIDBiometricEventTypeHumanProximity = 0,
    kIOHIDBiometricEventTypeHumanTouch,
    kIOHIDBiometricEventTypeHumanForce,
    kIOHIDBiometricEventTypeHumanPresence
};

typedef uint32_t IOHIDBiometricEventType;





enum {
    kIOHIDUnicodeEncodingTypeUTF8,
    kIOHIDUnicodeEncodingTypeUTF16LE,
    kIOHIDUnicodeEncodingTypeUTF16BE,
    kIOHIDUnicodeEncodingTypeUTF32LE,
    kIOHIDUnicodeEncodingTypeUTF32BE,
};
typedef uint32_t IOHIDUnicodeEncodingType;


/*!
 @typedef IOHIDMotionActivityEventType
 @abstract Type of motion activity event triggered.
 @constant kIOHIDMotionActivityEventTypeUnknown
 @constant kIOHIDMotionActivityEventTypeStatic
 @constant kIOHIDMotionActivityEventTypeMoving
 @constant kIOHIDMotionActivityEventTypeSemiStationary
 @constant kIOHIDMotionActivityEventTypeWalking
 @constant kIOHIDMotionActivityEventTypeRunning
 @constant kIOHIDMotionActivityEventTypeCycling
 @constant kIOHIDMotionActivityEventTypeInVehicleStatic
 @constant kIOHIDMotionActivityEventTypeDriving
 */
enum {
    kIOHIDMotionActivityEventTypeUnknown = 0,
    kIOHIDMotionActivityEventTypeStatic,
    kIOHIDMotionActivityEventTypeMoving,
    kIOHIDMotionActivityEventTypeSemiStationary,
    kIOHIDMotionActivityEventTypeWalking,
    kIOHIDMotionActivityEventTypeRunning,
    kIOHIDMotionActivityEventTypeCycling,
    kIOHIDMotionActivityEventTypeInVehicleStatic,
    kIOHIDMotionActivityEventTypeDriving,
};

typedef uint32_t IOHIDMotionActivityEventType;


/*!
 @typedef IOHIDMotionGestureEventType
 @abstract Type of motion gesture event triggered.
 @constant kIOHIDMotionGestureEventTypeUnknown
 @constant kIOHIDMotionGestureEventTypeRaiseToListen
 @constant kIOHIDMotionGestureEventTypeRaiseToLook
*/
enum {
    kIOHIDMotionGestureEventTypeUnknown = 0,
    kIOHIDMotionGestureEventTypeRaiseToListen,
    kIOHIDMotionGestureEventTypeRaiseToLook,
};


/*!
    @typedef IOHIDSwipeMask
    @abstract Mask detailing the type of swipe detected.
    @constant kIOHIDSwipeUp
    @constant kIOHIDSwipeDown
    @constant kIOHIDSwipeLeft
    @constant kIOHIDSwipeRight
*/
enum {
    kIOHIDSwipeNone             = 0,
    kIOHIDSwipeUp               = 1<<0,
    kIOHIDSwipeDown             = 1<<1,
    kIOHIDSwipeLeft             = 1<<2,
    kIOHIDSwipeRight            = 1<<3,
    kIOHIDScaleExpand           = 1<<4,
    kIOHIDScaleContract         = 1<<5,
    kIOHIDRotateCW              = 1<<6,
    kIOHIDRotateCCW             = 1<<7,
};
typedef uint32_t IOHIDSwipeMask;

/*!
    @typedef IOHIDGestureMotion
    @abstract Motion gestures
    @constant kIOHIDGestureMotionNone
    @constant kIOHIDGestureMotionHorizontalX
    @constant kIOHIDGestureMotionVerticalY
    @constant kIOHIDGestureMotionScale
    @constant kIOHIDGestureMotionRotate
    @constant kIOHIDGestureMotionTap
    @constant kIOHIDGestureMotionDoubleTap
    @constant kIOHIDGestureMotionFromLeftEdge
    @constant kIOHIDGestureMotionOffLeftEdge
    @constant kIOHIDGestureMotionFromRightEdge
    @constant kIOHIDGestureMotionOffRightEdge
    @constant kIOHIDGestureMotionFromTopEdge
    @constant kIOHIDGestureMotionOffTopEdge
    @constant kIOHIDGestureMotionFromBottomEdge
    @constant kIOHIDGestureMotionOffBottomEdge
    @constant kIOHIDGestureMotionLongPress
    @constant kIOHIDGestureMotionTwoFingerLongPress

*/
enum {
    kIOHIDGestureMotionNone,
    kIOHIDGestureMotionHorizontalX,
    kIOHIDGestureMotionVerticalY,
    kIOHIDGestureMotionScale,
    kIOHIDGestureMotionRotate,
    kIOHIDGestureMotionTap,
    kIOHIDGestureMotionDoubleTap,
    kIOHIDGestureMotionFromLeftEdge,
    kIOHIDGestureMotionOffLeftEdge,
    kIOHIDGestureMotionFromRightEdge,
    kIOHIDGestureMotionOffRightEdge,
    kIOHIDGestureMotionFromTopEdge,
    kIOHIDGestureMotionOffTopEdge,
    kIOHIDGestureMotionFromBottomEdge,
    kIOHIDGestureMotionOffBottomEdge,
    kIOHIDGestureMotionLongPress,
    kIOHIDGestureMotionTwoFingerLongPress,
};
typedef uint16_t IOHIDGestureMotion;

/*!
    @typedef IOHIDGestureFlavor
    @abstract Gesture flavours
    @constant kIOHIDGestureFlavorNone
    @constant kIOHIDGestureFlavorNotificationCenterPrimary
    @constant kIOHIDGestureFlavorNotificationCenterSecondary
    @constant kIOHIDGestureFlavorDockPrimary
    @constant kIOHIDGestureFlavorDockSecondary
    @constant kIOHIDGestureFlavorNavagationPrimary
    @constant kIOHIDGestureFlavorNavagationSecondary
    @constant kIOHIDGestureFlavorControlCenterPrimary
    @constant kIOHIDGestureFlavorControlCenterSecondary
*/
enum {
    kIOHIDGestureFlavorNone,
    kIOHIDGestureFlavorNotificationCenterPrimary,
    kIOHIDGestureFlavorNotificationCenterSecondary,
    kIOHIDGestureFlavorDockPrimary,
    kIOHIDGestureFlavorDockSecondary,
    kIOHIDGestureFlavorNavagationPrimary,
    kIOHIDGestureFlavorNavagationSecondary,
    kIOHIDGestureFlavorControlCenterPrimary,
    kIOHIDGestureFlavorControlCenterSecondary,
};
typedef uint16_t IOHIDGestureFlavor;

/*!
    @typedef IOHIDProximityDetectionMask
    @abstract Proximity mask detailing the inputs that were detected.
    @constant kIOHIDProximityDetectionLargeBodyContact
    @constant kIOHIDProximityDetectionLargeBodyFarField
    @constant kIOHIDProximityDetectionIrregularObjects
    @constant kIOHIDProximityDetectionEdgeStraddling
    @constant kIOHIDProximityDetectionFlatFingerClasp
    @constant kIOHIDProximityDetectionFingerTouch
    @constant kIOHIDProximityDetectionReceiver
    @constant kIOHIDProximityDetectionSmallObjectsHovering
    @constant kIOHIDProximityDetectionReceiverCrude
    @constant kIOHIDProximityDetectionReceiverMonitoring
    @constant kIOHIDProximityDetectionReceiverCrudeMonitoring
*/
enum {
    kIOHIDProximityDetectionLargeBodyContact                = 1<<0,
    kIOHIDProximityDetectionLargeBodyFarField               = 1<<1,
    kIOHIDProximityDetectionIrregularObjects                = 1<<2,
    kIOHIDProximityDetectionEdgeStraddling                  = 1<<3,
    kIOHIDProximityDetectionFlatFingerClasp                 = 1<<4,
    kIOHIDProximityDetectionFingerTouch                     = 1<<5,
    kIOHIDProximityDetectionReceiver                        = 1<<6,
    kIOHIDProximityDetectionSmallObjectsHovering            = 1<<7,
    kIOHIDProximityDetectionReceiverCrude                   = 1<<8,
    kIOHIDProximityDetectionReceiverMonitoring              = 1<<9,
    kIOHIDProximityDetectionReceiverCrudeMonitoring         = 1<<10
};
typedef uint32_t IOHIDProximityDetectionMask;

/*!
    @typedef IOHIDDigitizerType
    @abstract The type of digitizer path initiating an event.
    @constant kIOHIDDigitizerTransducerTypeStylus
    @constant kIOHIDDigitizerTransducerTypePuck
    @constant kIOHIDDigitizerTransducerTypeFinger
    @constant kIOHIDDigitizerTransducerTypeHand
*/
enum {   
    kIOHIDDigitizerTransducerTypeStylus  = 0,
    kIOHIDDigitizerTransducerTypePuck,
    kIOHIDDigitizerTransducerTypeFinger,
    kIOHIDDigitizerTransducerTypeHand
};
typedef uint32_t IOHIDDigitizerTransducerType;

/*!
    @typedef IOHIDDigitizerEventMask
    @abstract Event mask detailing the events being dispatched by a digitizer.
    @discussion It is possible for digitizer events to contain child digitizer events, effectively, behaving as collections.  
    In the collection case, the child event mask field referenced by kIOHIDEventFieldDigitizerChildEventMask will detail the 
    cumulative event state of the child digitizer events.
    <br>
    <b>Please Note:</b>
    If you append a child digitizer event to a parent digitizer event, appropriate state will be transfered on to the parent.
    @constant kIOHIDDigitizerEventRange Issued when the range state has changed.
    @constant kIOHIDDigitizerEventTouch Issued when the touch state has changed.
    @constant kIOHIDDigitizerEventPosition Issued when the position has changed.
    @constant kIOHIDDigitizerEventStop Issued when motion has achieved a state of calculated non-movement.
    @constant kIOHIDDigitizerEventPeak Issues when new maximum values have been detected.
    @constant kIOHIDDigitizerEventIdentity Issued when the identity has changed.
    @constant kIOHIDDigitizerEventAttribute Issued when an attribute has changed.
    @constant kIOHIDDigitizerEventCancel
    @constant kIOHIDDigitizerEventResting
    @constant kIOHIDDigitizerEventFromEdgeFlat Issued when a digitizer approaches from the edge with flattened presentation
    @constant kIOHIDDigitizerEventFromEdgeTip Issued when a digitizer approaches from the edge with standard (i.e. un-flattened) presentation.
    @constant kIOHIDDigitizerEventFromCorner Issued when a digitizer approaches from a corner
    @constant kIOHIDDigitizerEventSwipePending Issued to indicate that an edge swipe is pending 
    @constant kIOHIDDigitizerEventFromEdgeForcePending Issued to indicate that edge press is pending
    @constant kIOHIDDigitizerEventFromEdgeForceActive Issued to indicate that edge press is active
    @constant kIOHIDDigitizerEventSwipeUp Issued when an up swipe has been detected.
    @constant kIOHIDDigitizerEventSwipeDown Issued when a down swipe has been detected.
    @constant kIOHIDDigitizerEventSwipeLeft Issued when a left swipe has been detected.
    @constant kIOHIDDigitizerEventSwipeRight Issued when a right swipe has been detected.
    @constant kIOHIDDigitizerEventSwipeMask Mask used to gather swipe events.
*/
enum {
    kIOHIDDigitizerEventRange                               = 1<<0,
    kIOHIDDigitizerEventTouch                               = 1<<1,
    kIOHIDDigitizerEventPosition                            = 1<<2,
    kIOHIDDigitizerEventStop                                = 1<<3,
    kIOHIDDigitizerEventPeak                                = 1<<4,
    kIOHIDDigitizerEventIdentity                            = 1<<5,
    kIOHIDDigitizerEventAttribute                           = 1<<6,
    kIOHIDDigitizerEventCancel                              = 1<<7,
    kIOHIDDigitizerEventStart                               = 1<<8,
    kIOHIDDigitizerEventResting                             = 1<<9,
    kIOHIDDigitizerEventFromEdgeFlat                        = 1<<10,
    kIOHIDDigitizerEventFromEdgeTip                         = 1<<11,
    kIOHIDDigitizerEventFromCorner                          = 1<<12,
    kIOHIDDigitizerEventSwipePending                        = 1<<13,
    kIOHIDDigitizerEventFromEdgeForcePending                = 1<<14,
    kIOHIDDigitizerEventFromEdgeForceActive                 = 1<<15,
    kIOHIDDigitizerEventTap                                 = 1<<17,
    kIOHIDDigitizerEventSwipeLocked                         = 1<<18,
    kIOHIDDigitizerEventSwipeUp                             = 1<<24,
    kIOHIDDigitizerEventSwipeDown                           = 1<<25,
    kIOHIDDigitizerEventSwipeLeft                           = 1<<26,
    kIOHIDDigitizerEventSwipeRight                          = 1<<27,
    kIOHIDDigitizerEventEstimatedAltitude                   = 1<<28,
    kIOHIDDigitizerEventEstimatedAzimuth                    = 1<<29,
    kIOHIDDigitizerEventEstimatedPressure                   = 1<<30,
    kIOHIDDigitizerEventSwipeMask                           = 0xF<<24,
};
typedef uint32_t IOHIDDigitizerEventMask;

/*!
 @typedef IOHIDDigitizerEventUpdateMask
 @abstract Bit mask detailing the fields that have or will change in a digitizer event
*/
enum {
    kIOHIDDigitizerEventUpdateXMask                         = 1<<IOHIDEventFieldOffsetOf(kIOHIDEventFieldDigitizerX),
    kIOHIDDigitizerEventUpdateYMask                         = 1<<IOHIDEventFieldOffsetOf(kIOHIDEventFieldDigitizerY),
    kIOHIDDigitizerEventUpdateZMask                         = 1<<IOHIDEventFieldOffsetOf(kIOHIDEventFieldDigitizerZ),
    kIOHIDDigitizerEventUpdateButtonMaskMask                = 1<<IOHIDEventFieldOffsetOf(kIOHIDEventFieldDigitizerButtonMask),
    kIOHIDDigitizerEventUpdateTypeMask                      = 1<<IOHIDEventFieldOffsetOf(kIOHIDEventFieldDigitizerType),
    kIOHIDDigitizerEventUpdateIndexMask                     = 1<<IOHIDEventFieldOffsetOf(kIOHIDEventFieldDigitizerIndex),
    kIOHIDDigitizerEventUpdateIdentityMask                  = 1<<IOHIDEventFieldOffsetOf(kIOHIDEventFieldDigitizerIdentity),
    kIOHIDDigitizerEventUpdateEventMaskMask                 = 1<<IOHIDEventFieldOffsetOf(kIOHIDEventFieldDigitizerEventMask),
    kIOHIDDigitizerEventUpdateRangeMask                     = 1<<IOHIDEventFieldOffsetOf(kIOHIDEventFieldDigitizerRange),
    kIOHIDDigitizerEventUpdateTouchMask                     = 1<<IOHIDEventFieldOffsetOf(kIOHIDEventFieldDigitizerTouch),
    kIOHIDDigitizerEventUpdatePressureMask                  = 1<<IOHIDEventFieldOffsetOf(kIOHIDEventFieldDigitizerPressure),
    kIOHIDDigitizerEventUpdateAuxiliaryPressureMask         = 1<<IOHIDEventFieldOffsetOf(kIOHIDEventFieldDigitizerAuxiliaryPressure),
    kIOHIDDigitizerEventUpdateTwistMask                     = 1<<IOHIDEventFieldOffsetOf(kIOHIDEventFieldDigitizerTwist),
    kIOHIDDigitizerEventUpdateTiltXMask                     = 1<<IOHIDEventFieldOffsetOf(kIOHIDEventFieldDigitizerTiltX),
    kIOHIDDigitizerEventUpdateTiltYMask                     = 1<<IOHIDEventFieldOffsetOf(kIOHIDEventFieldDigitizerTiltY),
    kIOHIDDigitizerEventUpdateAltitudeMask                  = 1<<IOHIDEventFieldOffsetOf(kIOHIDEventFieldDigitizerAltitude),
    kIOHIDDigitizerEventUpdateAzimuthMask                   = 1<<IOHIDEventFieldOffsetOf(kIOHIDEventFieldDigitizerAzimuth),
    kIOHIDDigitizerEventUpdateQualityMask                   = 1<<IOHIDEventFieldOffsetOf(kIOHIDEventFieldDigitizerQuality),
    kIOHIDDigitizerEventUpdateDensityMask                   = 1<<IOHIDEventFieldOffsetOf(kIOHIDEventFieldDigitizerDensity),
    kIOHIDDigitizerEventUpdateIrregularityMask              = 1<<IOHIDEventFieldOffsetOf(kIOHIDEventFieldDigitizerIrregularity),
    kIOHIDDigitizerEventUpdateMajorRadiusMask               = 1<<IOHIDEventFieldOffsetOf(kIOHIDEventFieldDigitizerMajorRadius),
    kIOHIDDigitizerEventUpdateMinorRadiusMask               = 1<<IOHIDEventFieldOffsetOf(kIOHIDEventFieldDigitizerMinorRadius),
    kIOHIDDigitizerEventUpdateCollectionMask                = 1<<IOHIDEventFieldOffsetOf(kIOHIDEventFieldDigitizerCollection),
    kIOHIDDigitizerEventUpdateChildEventMaskMask            = 1<<IOHIDEventFieldOffsetOf(kIOHIDEventFieldDigitizerChildEventMask),
    kIOHIDDigitizerEventUpdateIsDisplayIntegratedMask       = 1<<IOHIDEventFieldOffsetOf(kIOHIDEventFieldDigitizerIsDisplayIntegrated),
    kIOHIDDigitizerEventUpdateQualityRadiiAccuracyMask      = 1<<IOHIDEventFieldOffsetOf(kIOHIDEventFieldDigitizerQualityRadiiAccuracy),
};
typedef uint32_t IOHIDDigitizerEventUpdateMask;

/*!
    @typedef IOHIDEventOptionBits
    @abstract Event mask detailing the options for events of any type.
    @constant kIOHIDEventOptionNone No options set.
    @constant kIOHIDEventOptionIsAbsolute Event is in absolute units, not relative units.
    @constant kIOHIDEventOptionIsCollection Event is a collection of sub events.
    @constant kIOHIDEventOptionIsPixelUnits Event units are pixels.
    @constant kIOHIDEventOptionIsCenterOrigin Event unit coordinates are from the center of the space, not the top left corner.
    @constant kIOHIDEventOptionIsBuiltIn Event is treated as if it came from a built-in device.
    @constant kIOHIDEventOptionInterpolated Event is interpolated from hid reports.
    @constant kIOHIDEventOptionInjected Event is injected by a tool or filter.
    @constant kIOHIDEventOptionContinuousTime Event timestamp is continuous time, pulling the Absolute Time will trigger conversion that may change across sleeps.
    @constant kIOHIDEventOptionPixelUnits Alternate spelling of kIOHIDEventOptionIsPixelUnits, prefer using kIOHIDEventOptionIsPixelUnits instead.
*/
enum {
    kIOHIDEventOptionNone                                   = 0,
    kIOHIDEventOptionIsAbsolute                             = 1<<0,
    kIOHIDEventOptionIsCollection                           = 1<<1,
    kIOHIDEventOptionIsPixelUnits                           = 1<<2,
    kIOHIDEventOptionIsCenterOrigin                         = 1<<3,
    kIOHIDEventOptionIsBuiltIn                              = 1<<4,
    kIOHIDEventOptionInterpolated                           = 1<<5,
    kIOHIDEventOptionInjected                               = 1<<6,
    kIOHIDEventOptionContinuousTime                         = 1<<7,
    kIOHIDEventOptionReserved8                              = 1<<8,  // Multiple flags, see IOHIDEventServiceTypes.h
    kIOHIDEventOptionReserved9                              = 1<<9,  // See kIOHIDEventScrollMomentumWillBegin below
    kIOHIDEventOptionReserved10                             = 1<<10, // See kIOHIDEventScrollMomentumInterrupted below
    kIOHIDEventOptionReserved11                             = 1<<11, // Not currently used
    kIOHIDEventOptionReserved12                             = 1<<12, // Not currently used
    kIOHIDEventOptionReserved13                             = 1<<13, // Not currently used
    kIOHIDEventOptionReserved14                             = 1<<14, // Not currently used
    kIOHIDEventOptionReserved15                             = 1<<15, // Not currently used
    kIOHIDEventOptionReserved16                             = 1<<16, // Multiple flags, see IOHIDEventData.h
    kIOHIDEventOptionReserved17                             = 1<<17, // Multiple flags, see IOHIDEventData.h
    kIOHIDEventOptionReserved18                             = 1<<18, // Multiple flags, see IOHIDEventData.h
    kIOHIDEventOptionReserved19                             = 1<<19, // Multiple flags, see IOHIDEventData.h
    kIOHIDEventOptionReserved20                             = 1<<20, // Not currently used
    kIOHIDEventOptionReserved21                             = 1<<21, // See kIOHIDKeyboardStickyKeysOn in IOHIDEventData.h
    kIOHIDEventOptionReserved22                             = 1<<22, // See kIOHIDKeyboardStickyKeysOff in IOHIDEventData.h
    kIOHIDEventOptionReserved23                             = 1<<23, // See kIOHIDEventOptionIsZeroEvent in IOHIDEventData.h
    kIOHIDEventOptionReserved24                             = 1<<24, // See kIOHIDEventPhaseBegan below
    kIOHIDEventOptionReserved25                             = 1<<25, // See kIOHIDEventPhaseChanged below
    kIOHIDEventOptionReserved26                             = 1<<26, // See kIOHIDEventPhaseEnded below
    kIOHIDEventOptionReserved27                             = 1<<27, // See kIOHIDEventPhaseCancelled below
    kIOHIDEventOptionReserved28                             = 1<<28, // See kIOHIDEventScrollMomentumContinue below
    kIOHIDEventOptionReserved29                             = 1<<29, // See kIOHIDEventScrollMomentumStart below
    kIOHIDEventOptionReserved30                             = 1<<30, // See kIOHIDEventScrollMomentumEnd below
    kIOHIDEventOptionReserved31                             = 1<<31, // See kIOHIDEventPhaseMayBegin below

    // misspellings
    kIOHIDEventOptionPixelUnits                             = kIOHIDEventOptionIsPixelUnits,
};
typedef uint32_t IOHIDEventOptionBits;

enum {
    kIOHIDEventPhaseUndefined                               = 0,
    kIOHIDEventPhaseBegan                                   = 1<<0,
    kIOHIDEventPhaseChanged                                 = 1<<1,
    kIOHIDEventPhaseEnded                                   = 1<<2,
    kIOHIDEventPhaseCancelled                               = 1<<3,
    kIOHIDEventPhaseMayBegin                                = 1<<7,
    kIOHIDEventEventPhaseMask                               = 0xFF,
    kIOHIDEventEventOptionPhaseShift                        = 24,
};
typedef uint16_t IOHIDEventPhaseBits;

enum {
    kIOHIDEventScrollMomentumUndefined                      = 0,
    kIOHIDEventScrollMomentumContinue                       = (1<<0),
    kIOHIDEventScrollMomentumStart                          = (1<<1),
    kIOHIDEventScrollMomentumEnd                            = (1<<2),
    kIOHIDEventScrollMomentumWillBegin                      = (1<<3), // Lower bit
    // Deprecated, use kIOHIDEventScrollMomentumWillBegin
    kIOHIDEventScrollMomentumMayBegin                       = kIOHIDEventScrollMomentumWillBegin,
    kIOHIDEventScrollMomentumInterrupted                    = (1<<4), // Lower bit
    kIOHIDEventScrollMomentumMask                           = (kIOHIDEventScrollMomentumContinue | kIOHIDEventScrollMomentumStart | kIOHIDEventScrollMomentumEnd),
    kIOHIDEventScrollMomentumShift                          = (kIOHIDEventEventOptionPhaseShift + 4),
    kIOHIDEventScrollMomentumLowerMask                      = (kIOHIDEventScrollMomentumWillBegin | kIOHIDEventScrollMomentumInterrupted),
    kIOHIDEventScrollMomentumLowerShift                     = 6,
};
typedef uint8_t IOHIDEventScrollMomentumBits;


/*!
 @typedef IOHIDSymbolicHotKey
 @abstract Enumerated values for sending symbolic hot key events.
 @constant kIOHIDSymbolicHotKeyDictionaryApp    This will get translated into a kCGSDictionaryAppHotKey by CG.
 @constant kIOHIDSymbolicHotKeyIronwoodApp      This will get translated into a kCGSIronwoodHotKey by CG.
 @constant kIOHIDSymbolicHotKeyDictationApp     This will get translated into a kCGSDictationHotKey by CG.
 @constant kIOHIDSymbolicHotKeyOptionIsCGSHotKey
                                                This is an option flag to denote that the SymbolicHotKey value is
                                                actually from the enumeration in CGSHotKeys.h.
 */
enum {
    kIOHIDSymbolicHotKeyUndefined,
    kIOHIDSymbolicHotKeyDictionaryApp,
    kIOHIDSymbolicHotKeyIronwoodApp,
    kIOHIDSymbolicHotKeyDictationApp,
    
    // for kIOHIDSymbolicHotKeyOptionIsCGSHotKey, see IOHIDFamily/IOHIDEventData.h
};
typedef uint32_t IOHIDSymbolicHotKeyValue;

enum {
    kIOHIDOrientationTypePolar             = 0,
    kIOHIDOrientationTypeCMUsage           = 1,  // see kHIDUsage_AppleVendorMotion_DeviceOrientation* for possible options
    kIOHIDOrientationTypeTilt              = 2,
    kIOHIDOrientationTypeQuaternion        = 3,
};


enum {
    kIOHIDEventSenderIDUndefined                            = 0x0000000000000000LL,
};
typedef uint64_t IOHIDEventSenderID; // must be the same size as that returned from IORegistryEntry::getRegistryEntryID

typedef double IOHIDDouble;

#ifndef KERNEL
/*!
    @typedef IOHIDFloat
*/
#ifdef __LP64__
typedef double IOHIDFloat;
#else
typedef float IOHIDFloat;
#endif
/*!
    @typedef IOHID3DPoint
*/
typedef struct _IOHID3DPoint {
    IOHIDFloat  x;
    IOHIDFloat  y;
    IOHIDFloat  z;
} IOHID3DPoint; 
#endif

enum {
    kIOHIDEventColorSpaceUndefined                           = 0,
    kIOHIDEventColorSpaceXYZ                                 = 1
};
typedef uint8_t IOHIDEventColorSpace;

/*!
    @typedef IOHIDEventPerfData
*/
typedef struct {
    uint64_t    driverDispatchTime;
    uint64_t    eventSystemReceiveTime;
    uint64_t    eventSystemDispatchTime;
    uint64_t    eventSystemFilterTime;
    uint64_t    eventSystemClientDispatchTime;
} IOHIDEventPerfData;

enum {
    kIOHIDEventPerfDataPointDriverDispatch,
    kIOHIDEventPerfDataPointEventSystemReceive,
    kIOHIDEventPerfDataPointEventSystemDispatch,
    kIOHIDEventPerfDataPointEventSystemFilter,
    kIOHIDEventPerfDataPointEventSystemClientDispatch
};

enum {
    kIOHIDKeyboardStickyKeyPhaseDown    = 1,
    kIOHIDKeyboardStickyKeyPhaseLocked  = 2,
    kIOHIDKeyboardStickyKeyPhaseUp      = 3
};

enum {
    kIOHIDKeyboardStickyKeyToggleOn    = 1,
    kIOHIDKeyboardStickyKeyToggleOff   = 2
};

/*!
    @typedef IOHIDEventTimestampType
    @abstract Types for getting and setting timestamps on HID events.
    @constant kIOHIDEventTimestampTypeAbsolute Get or set the timestamp as mach_absolute_time, convert if necessary.
    @constant kIOHIDEventTimestampTypeContinuous Get or set the timestamp as mach_continuous_time, convert if necessary.
    @constant kIOHIDEventTimestampTypeDefault Get or set a raw timestamp, with no conversion.
*/

typedef enum {
    kIOHIDEventTimestampTypeAbsolute,
    kIOHIDEventTimestampTypeContinuous,
    kIOHIDEventTimestampTypeDefault,
} IOHIDEventTimestampType;

enum {
    kIOHIDProximityProximityTypeLevel = 0,
    kIOHIDProximityProximityTypeProbability
};

#endif /* _IOKIT_HID_IOHIDEVENTTYPES_H } */
