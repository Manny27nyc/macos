/*
 * Copyright (c) 2018 Apple Inc. All Rights Reserved.
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

#if __OBJC2__

#import <TargetConditionals.h>
#import <Foundation/Foundation.h>

#import "keychain/ot/OTClique.h"
#import "keychain/ot/OTClique+Private.h"
#import "keychain/ot/OTConstants.h"
#import "keychain/ot/OTDefines.h"
#import "keychain/SigninMetrics/OctagonSignPosts.h"

#import "utilities/SecCFWrappers.h"
#import "utilities/debugging.h"

#import "keychain/SecureObjectSync/SOSCloudCircle.h"
#import "KeychainCircle/PairingChannel.h"
#import <Security/SecBase.h>
#import "keychain/SecureObjectSync/SOSViews.h"
#import "keychain/SecureObjectSync/SOSInternal.h"

const NSString* kSecEntitlementPrivateOctagonEscrow = @"com.apple.private.octagon.escrow-content";
const NSString* kSecEntitlementPrivateOctagonSecureElement = @"com.apple.private.octagon.secureelement";

#if OCTAGON
#import <AuthKit/AuthKit.h>
#import <AuthKit/AuthKit_Private.h>
#import <SoftLinking/SoftLinking.h>
#import <CloudServices/SecureBackup.h>
#import <CloudServices/SecureBackupConstants.h>
#import "keychain/ot/OTControl.h"
#import "keychain/ckks/CKKSControl.h"
#import "keychain/ot/categories/OctagonEscrowRecoverer.h"

#import <Foundation/NSDistributedNotificationCenter.h>

SOFT_LINK_FRAMEWORK(PrivateFrameworks, KeychainCircle);
SOFT_LINK_OPTIONAL_FRAMEWORK(PrivateFrameworks, CloudServices);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wstrict-prototypes"
SOFT_LINK_CLASS(KeychainCircle, KCPairingChannel);
SOFT_LINK_CLASS(KeychainCircle, OTPairingChannel);
SOFT_LINK_CLASS(CloudServices, SecureBackup);
SOFT_LINK_CONSTANT(CloudServices, kSecureBackupErrorDomain, NSErrorDomain);
SOFT_LINK_CONSTANT(CloudServices, kSecureBackupAuthenticationAppleID, NSString*);
SOFT_LINK_CONSTANT(CloudServices, kSecureBackupAuthenticationPassword, NSString*);
SOFT_LINK_CONSTANT(CloudServices, kSecureBackupiCloudDataProtectionDeleteAllRecordsKey, NSString*);
SOFT_LINK_CONSTANT(CloudServices, kSecureBackupContainsiCDPDataKey, NSString*);
SOFT_LINK_CONSTANT(CloudServices, kSecureBackupRecoveryKeyKey, NSString*);
SOFT_LINK_CONSTANT(CloudServices, kSecureBackupUsesRecoveryKeyKey, NSString*);

#pragma clang diagnostic pop
#endif

OTCliqueCDPContextType OTCliqueCDPContextTypeNone = @"cdpContextTypeNone";
OTCliqueCDPContextType OTCliqueCDPContextTypeSignIn = @"cdpContextTypeSignIn";
OTCliqueCDPContextType OTCliqueCDPContextTypeRepair = @"cdpContextTypeRepair";
OTCliqueCDPContextType OTCliqueCDPContextTypeFinishPasscodeChange = @"cdpContextTypeFinishPasscodeChange";
OTCliqueCDPContextType OTCliqueCDPContextTypeRecoveryKeyGenerate = @"cdpContextTypeRecoveryKeyGenerate";
OTCliqueCDPContextType OTCliqueCDPContextTypeRecoveryKeyNew = @"cdpContextTypeRecoveryKeyNew";
OTCliqueCDPContextType OTCliqueCDPContextTypeUpdatePasscode = @"cdpContextTypeUpdatePasscode";
OTCliqueCDPContextType OTCliqueCDPContextTypeConfirmPasscodeCyrus = @"cdpContextTypeConfirmPasscodeCyrus";

NSString* OTCliqueStatusToString(CliqueStatus status)
{
    switch(status) {
        case CliqueStatusIn:
            return @"CliqueStatusIn";
        case CliqueStatusNotIn:
            return @"CliqueStatusNotIn";
        case CliqueStatusPending:
            return @"CliqueStatusPending";
        case CliqueStatusAbsent:
            return @"CliqueStatusAbsent";
        case CliqueStatusNoCloudKitAccount:
            return @"CliqueStatusNoCloudKitAccount";
        case CliqueStatusError:
            return @"CliqueStatusError";
    };
}
CliqueStatus OTCliqueStatusFromString(NSString* str)
{
    if([str isEqualToString: @"CliqueStatusIn"]) {
        return CliqueStatusIn;
    } else if([str isEqualToString: @"CliqueStatusNotIn"]) {
        return CliqueStatusNotIn;
    } else if([str isEqualToString: @"CliqueStatusPending"]) {
        return CliqueStatusPending;
    } else if([str isEqualToString: @"CliqueStatusAbsent"]) {
        return CliqueStatusAbsent;
    } else if([str isEqualToString: @"CliqueStatusNoCloudKitAccount"]) {
        return CliqueStatusNoCloudKitAccount;
    } else if([str isEqualToString: @"CliqueStatusError"]) {
        return CliqueStatusError;
    }

    return CliqueStatusError;
}

NSString* OTCDPStatusToString(OTCDPStatus status) {
    switch(status) {
        case OTCDPStatusUnknown:
            return @"unknown";
        case OTCDPStatusDisabled:
            return @"disabled";
        case OTCDPStatusEnabled:
            return @"enabled";
    }
}


@implementation OTConfigurationContext

- (BOOL)overrideEscrowCache
{
    return (self.escrowFetchSource == OTEscrowRecordFetchSourceCuttlefish);
}

- (void)setOverrideEscrowCache:(BOOL)overrideEscrowCache
{
    if (overrideEscrowCache) {
        self.escrowFetchSource = OTEscrowRecordFetchSourceCuttlefish;
    } else {
        self.escrowFetchSource = OTEscrowRecordFetchSourceDefault;
    }
}

- (OTControl* _Nullable)makeOTControl:(NSError**)error
{
#if OCTAGON
    if (self.otControl) {
        return self.otControl;
    }
    return [OTControl controlObject:true error:error];
#else
    return nil;
#endif
}

- (CKKSControl* _Nullable)makeCKKSControl:(NSError**)error
{
#if OCTAGON
    if(self.ckksControl) {
        return self.ckksControl;
    }
    return [CKKSControl CKKSControlObject:true error:error];
#else
    return nil;
#endif
}

- (instancetype)init
{
    if((self = [super init])) {
        _context = OTDefaultContext;
    }
    return self;
}
@end

@implementation OTBottleIDs
@end

@implementation OTOperationConfiguration

- (instancetype)init {
    if ((self = [super init]) == nil) {
        return nil;
    }
    _timeoutWaitForCKAccount = 10 * NSEC_PER_SEC;
    _qualityOfService = NSQualityOfServiceDefault;
    _discretionaryNetwork = NO;
    _useCachedAccountStatus = NO;
    return self;
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(nonnull NSCoder *)coder {
    [coder encodeObject:@(_timeoutWaitForCKAccount) forKey:@"timeoutWaitForCKAccount"];
    [coder encodeObject:@(_qualityOfService) forKey:@"qualityOfService"];
    [coder encodeObject:@(_discretionaryNetwork) forKey:@"discretionaryNetwork"];
    [coder encodeObject:@(_useCachedAccountStatus) forKey:@"useCachedAccountStatus"];
}

- (nullable instancetype)initWithCoder:(nonnull NSCoder *)coder {
    _timeoutWaitForCKAccount = [[coder decodeObjectOfClass:[NSNumber class] forKey:@"timeoutWaitForCKAccount"] unsignedLongLongValue];
    _qualityOfService = [[coder decodeObjectOfClass:[NSNumber class] forKey:@"qualityOfService"] integerValue];
    _discretionaryNetwork = [[coder decodeObjectOfClass:[NSNumber class] forKey:@"discretionaryNetwork"] boolValue];
    _useCachedAccountStatus = [[coder decodeObjectOfClass:[NSNumber class] forKey:@"useCachedAccountStatus"] boolValue];
    return self;
}

@end

@interface OTClique ()
@property (nonatomic, copy) NSString* cliqueMemberIdentifier;
@end

@implementation OTClique

+ (BOOL)platformSupportsSOS
{
    return (OctagonPlatformSupportsSOS() && OctagonIsSOSFeatureEnabled());
}

- (instancetype)initWithContextData:(OTConfigurationContext*)ctx
{
#if OCTAGON
    if ((self = [super init])) {
        _ctx = [[OTConfigurationContext alloc]init];
        _ctx.context = ctx.context ?: OTDefaultContext;
        _ctx.containerName = ctx.containerName;
        _ctx.dsid = [ctx.dsid copy];
        _ctx.altDSID = [ctx.altDSID copy];
        _ctx.otControl = ctx.otControl;
        _ctx.ckksControl = ctx.ckksControl;
        _ctx.escrowFetchSource = ctx.escrowFetchSource;
        _ctx.overrideForSetupAccountScript = ctx.overrideForSetupAccountScript;
    }
    return self;
#else
    NSAssert(false, @"OTClique is not implemented on this platform");

    // make the build analyzer happy
    if ((self = [super init])) {
    }
    return self;
#endif // OCTAGON
}

- (NSString*)description
{
    return [NSString stringWithFormat:@"<OTClique: altDSID:%@ contextID:%@ memberID:%@>", self.ctx.altDSID, self.ctx.context, self.cliqueMemberIdentifier];
}

- (NSString* _Nullable)cliqueMemberIdentifier
{
#if OCTAGON
    __block NSString* retPeerID = nil;
    __block bool subTaskSuccess = false;

    OctagonSignpost fetchEgoPeerSignPost = OctagonSignpostBegin(OctagonSignpostNameFetchEgoPeer);
    NSError* localError = nil;
    OTControl* control = [self makeOTControl:&localError];
    if(!control) {
        secerror("octagon: Failed to create OTControl: %@", localError);
        OctagonSignpostEnd(fetchEgoPeerSignPost, OctagonSignpostNameFetchEgoPeer, OctagonSignpostNumber1(OctagonSignpostNameFetchEgoPeer), (int)subTaskSuccess);
        return nil;
    }

    [control fetchEgoPeerID:[[OTControlArguments alloc] initWithConfiguration:self.ctx]
                      reply:^(NSString* peerID, NSError* error) {
                          if(error) {
                              secerror("octagon: Failed to fetch octagon peer ID: %@", error);
                          }
                          retPeerID = peerID;
                      }];
    secnotice("clique", "cliqueMemberIdentifier(octagon) received %@", retPeerID);

    if([OTClique platformSupportsSOS]) {
        CFErrorRef error = NULL;
        SOSPeerInfoRef me = SOSCCCopyMyPeerInfo(&error);
        retPeerID =  (NSString*)CFBridgingRelease(CFRetainSafe(SOSPeerInfoGetPeerID(me)));
        CFReleaseNull(me);
        CFBridgingRelease(error);
    }

    secnotice("clique", "cliqueMemberIdentifier complete: %@", retPeerID);
    subTaskSuccess = retPeerID ? true : false;
    OctagonSignpostEnd(fetchEgoPeerSignPost, OctagonSignpostNameFetchEgoPeer, OctagonSignpostNumber1(OctagonSignpostNameFetchEgoPeer), (int)subTaskSuccess);
    return retPeerID;
#else
    return nil;
#endif
}

#if OCTAGON
- (OTControl* _Nullable)makeOTControl:(NSError**)error
{
    return [self.ctx makeOTControl:error];
}

- (BOOL)establish:(NSError**)error
{
    secnotice("clique-establish", "establish started");
    OctagonSignpost establishSignPost = OctagonSignpostBegin(OctagonSignpostNameEstablish);
    bool subTaskSuccess = false;
    OTControl* control = [self makeOTControl:error];
    if(!control) {
        OctagonSignpostEnd(establishSignPost, OctagonSignpostNameEstablish, OctagonSignpostNumber1(OctagonSignpostNameEstablish), (int)subTaskSuccess);
        return false;
    }
    
    __block BOOL success = NO;
    __block NSError* localError = nil;

    //only establish
    [control establish:[[OTControlArguments alloc] initWithConfiguration:self.ctx] reply:^(NSError * _Nullable operationError) {
        if(operationError) {
            secnotice("clique-establish", "establish returned an error: %@", operationError);
        }
        success = operationError == nil;
        localError = operationError;
    }];
    
    if(localError && error) {
        *error = localError;
    }
    secnotice("clique-establish", "establish complete: %@", success ? @"YES" : @"NO");
    subTaskSuccess = success ? true : false;
    OctagonSignpostEnd(establishSignPost, OctagonSignpostNameEstablish, OctagonSignpostNumber1(OctagonSignpostNameEstablish), (int)subTaskSuccess);

    return success;
}

- (BOOL)resetAndEstablish:(CuttlefishResetReason)resetReason error:(NSError**)error
{
    secnotice("clique-resetandestablish", "resetAndEstablish started");
    bool subTaskSuccess = false;
    OctagonSignpost resetAndEstablishSignPost = OctagonSignpostBegin(OctagonSignpostNameResetAndEstablish);

    OTControl* control = [self makeOTControl:error];

    if(!control) {
        OctagonSignpostEnd(resetAndEstablishSignPost, OctagonSignpostNameResetAndEstablish, OctagonSignpostNumber1(OctagonSignpostNameResetAndEstablish), (int)subTaskSuccess);
        return NO;
    }

    __block BOOL success = NO;
    __block NSError* localError = nil;
    [control resetAndEstablish:[[OTControlArguments alloc] initWithConfiguration:self.ctx] resetReason:resetReason reply:^(NSError * _Nullable operationError) {
        if(operationError) {
            secnotice("clique-resetandestablish", "resetAndEstablish returned an error: %@", operationError);
        }
        success = operationError == nil;
        localError = operationError;
    }];

    if(localError && error) {
        *error = localError;
    }

    secnotice("clique-resetandestablish", "establish complete: %@", success ? @"YES" : @"NO");
    subTaskSuccess = success ? true : false;
    OctagonSignpostEnd(resetAndEstablishSignPost, OctagonSignpostNameResetAndEstablish, OctagonSignpostNumber1(OctagonSignpostNameResetAndEstablish), (int)subTaskSuccess);

    return success;
}
#endif // OCTAGON

+ (OTClique*)newFriendsWithContextData:(OTConfigurationContext*)data error:(NSError * __autoreleasing *)error
{
    return [OTClique newFriendsWithContextData:data resetReason:CuttlefishResetReasonUserInitiatedReset error:error];
}

+ (OTClique*)newFriendsWithContextData:(OTConfigurationContext*)data resetReason:(CuttlefishResetReason)resetReason error:(NSError * __autoreleasing *)error
{
#if OCTAGON
    secnotice("clique-newfriends", "makeNewFriends invoked using context: %@, dsid: %@", data.context, data.dsid);
    bool result = false;
    bool subTaskSuccess = false;
    OctagonSignpost newFriendsSignpost = OctagonSignpostBegin(OctagonSignpostNameMakeNewFriends);

    OTClique* clique = [[OTClique alloc] initWithContextData:data];

    NSError* localError = nil;
    [clique resetAndEstablish:resetReason error:&localError];

    if(localError) {
        secnotice("clique-newfriends", "account reset failed: %@", localError);
        if(error) {
            *error = localError;
        }
        OctagonSignpostEnd(newFriendsSignpost, OctagonSignpostNameMakeNewFriends, OctagonSignpostNumber1(OctagonSignpostNameMakeNewFriends), (int)subTaskSuccess);
        return nil;
    } else {
        secnotice("clique-newfriends", "Octagon account reset succeeded");
    }

    if([OTClique platformSupportsSOS]) {
        CFErrorRef resetError = NULL;
        result = SOSCCResetToOffering(&resetError);

        if(!result || resetError){
            secnotice("clique-newfriends", "newFriendsWithContextData: resetToOffering failed: %@", resetError);
            if(error) {
                *error = CFBridgingRelease(resetError);
            } else {
                CFBridgingRelease(resetError);
            }
            OctagonSignpostEnd(newFriendsSignpost, OctagonSignpostNameMakeNewFriends, OctagonSignpostNumber1(OctagonSignpostNameMakeNewFriends), (int)subTaskSuccess);
            return nil;
        }
        secnotice("clique-newfriends", "newFriendsWithContextData: reset the SOS circle");
    } else {
        secnotice("clique-newfriends", "newFriendsWithContextData: SOS disabled on this platform");
    }
    secnotice("clique-newfriends", "makeNewFriends complete");

    subTaskSuccess = true;
    OctagonSignpostEnd(newFriendsSignpost, OctagonSignpostNameMakeNewFriends, OctagonSignpostNumber1(OctagonSignpostNameMakeNewFriends), (int)subTaskSuccess);

    return clique;

#else // !OCTAGON
    if (error)
        *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecUnimplemented userInfo:nil];
    return NULL;
#endif
}

+ (BOOL)isCloudServicesAvailable
{
#if OCTAGON
    if (isCloudServicesAvailable()) {
        return YES;
    }

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        secnotice("octagon", "CloudServices is unavailable on this platform");
    });
    return NO;
#else
    return NO;
#endif
}

+ (OTClique* _Nullable)performEscrowRecoveryWithContextData:(OTConfigurationContext*)data
                                            escrowArguments:(NSDictionary*)sbdRecoveryArguments
                                                      error:(NSError**)error
{
#if OCTAGON
    if ([OTClique isCloudServicesAvailable] == NO) {
        if (error) {
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecUnimplemented userInfo:nil];
        }
        return nil;
    }

    OctagonSignpost performEscrowRecoverySignpost = OctagonSignpostBegin(OctagonSignpostNamePerformEscrowRecovery);
    bool subTaskSuccess = false;
    NSError* localError = nil;

    OTClique* clique = [[OTClique alloc] initWithContextData:data];

    // Attempt the recovery from sbd
    secnotice("clique-recovery", "attempting an escrow recovery for context:%@, altdsid:%@", data.context, data.altDSID);
    id<OctagonEscrowRecovererPrococol> sb = data.sbd ?: [[getSecureBackupClass() alloc] init];
    NSDictionary* recoveredInformation = nil;

    OctagonSignpost recoverFromSBDSignPost = OctagonSignpostBegin(OctagonSignpostNamePerformRecoveryFromSBD);
    NSError* recoverError = [sb recoverWithInfo:sbdRecoveryArguments results:&recoveredInformation];
    subTaskSuccess = (recoverError == nil) ? true : false;
    OctagonSignpostEnd(recoverFromSBDSignPost, OctagonSignpostNamePerformRecoveryFromSBD, OctagonSignpostNumber1(OctagonSignpostNamePerformRecoveryFromSBD), (int)subTaskSuccess);

    if(recoverError) {
        secnotice("clique-recovery", "sbd escrow recovery failed: %@", recoverError);
        if(recoverError.code == 17 /* kSecureBackupRestoringLegacyBackupKeychainError */ && [recoverError.domain isEqualToString:getkSecureBackupErrorDomain()]) { /* XXX */
            if([OTClique platformSupportsSOS]) {
                secnotice("clique-recovery", "Can't restore legacy backup with no keybag. Resetting SOS to offering");
                CFErrorRef blowItAwayError = NULL;
                bool successfulReset = SOSCCResetToOffering(&blowItAwayError);
                if(!successfulReset || blowItAwayError) {
                    secerror("clique-recovery: failed to reset to offering:%@", blowItAwayError);
                } else {
                    secnotice("clique-recovery", "resetting SOS circle successful");
                }
                CFBridgingRelease(blowItAwayError);
            } else {
                secnotice("clique-recovery", "Legacy restore failed on a non-SOS platform");
            }
        } else {
            if(error) {
                *error = recoverError;
            }
            subTaskSuccess = false;
            OctagonSignpostEnd(performEscrowRecoverySignpost, OctagonSignpostNamePerformEscrowRecovery, OctagonSignpostNumber1(OctagonSignpostNamePerformEscrowRecovery), (int)subTaskSuccess);
            return nil;
        }
    } else {
        if(OctagonPlatformSupportsSOS()) { // Join if the legacy restore is complete now.
            secnotice("clique-recovery", "attempting joinAfterRestore");
            BOOL joinAfterRestoreSuccess = [clique joinAfterRestore:&localError];
            secnotice("clique-recovery", "joinAfterRestore: %@", localError);
            if (!joinAfterRestoreSuccess) {
                secnotice("clique-recovery", "attempting reset to offering");
                CFErrorRef resetToOfferingError = NULL;
                bool successfulReset = SOSCCResetToOffering(&resetToOfferingError);
                if(!successfulReset || resetToOfferingError) {
                    secerror("clique-recovery: failed to reset to offering:%@", resetToOfferingError);
                } else {
                    secnotice("clique-recovery", "resetting SOS circle successful");
                }
                CFReleaseNull(resetToOfferingError);
            }
        }
    }

    NSString* recoveryKey = sbdRecoveryArguments[getkSecureBackupRecoveryKeyKey()];
    NSNumber* usesRecoveryKey = sbdRecoveryArguments[getkSecureBackupUsesRecoveryKeyKey()];

    if((recoveryKey != nil || [usesRecoveryKey boolValue] == YES)
       && [clique fetchCliqueStatus:&localError] == CliqueStatusIn) {
        secnotice("clique-recovery", "recovery key used during secure backup recovery, skipping bottle check");
        secnotice("clique-recovery", "recovery complete: %@", clique);

        subTaskSuccess = clique ? true : false;
        OctagonSignpostEnd(performEscrowRecoverySignpost, OctagonSignpostNamePerformEscrowRecovery, OctagonSignpostNumber1(OctagonSignpostNamePerformEscrowRecovery), (int)subTaskSuccess);

        return clique;
    }

    // look for OT Bottles
    OTControl* control = [clique makeOTControl:&localError];
    if (!control) {
        secnotice("clique-recovery", "unable to create otcontrol: %@", localError);
        if (error) {
            *error = localError;
        }
        subTaskSuccess = false;
        OctagonSignpostEnd(performEscrowRecoverySignpost, OctagonSignpostNamePerformEscrowRecovery, OctagonSignpostNumber1(OctagonSignpostNamePerformEscrowRecovery), (int)subTaskSuccess);
        return nil;
    }

    NSString *bottleID = recoveredInformation[@"bottleID"];
    NSString *isValid = recoveredInformation[@"bottleValid"];
    NSData *bottledPeerEntropy = recoveredInformation[@"EscrowServiceEscrowData"][@"BottledPeerEntropy"];
    bool shouldResetOctagon = false;
    
    if(bottledPeerEntropy && bottleID &&  [isValid isEqualToString:@"valid"]){
        secnotice("clique-recovery", "recovering from bottle: %@", bottleID);
        __block NSError* restoreBottleError = nil;

        OctagonSignpost bottleRecoverySignPost = OctagonSignpostBegin(OctagonSignpostNamePerformOctagonJoin);
        //restore bottle!
        [control restoreFromBottle:[[OTControlArguments alloc] initWithConfiguration:data]
                           entropy:bottledPeerEntropy
                          bottleID:bottleID
                             reply:^(NSError * _Nullable restoreError) {
            if(restoreError) {
                secnotice("clique-recovery", "restore bottle errored: %@", restoreError);
            } else {
                secnotice("clique-recovery", "restoring bottle succeeded");
            }
            restoreBottleError = restoreError;
        }];

        subTaskSuccess = (restoreBottleError == nil) ? true : false;
        OctagonSignpostEnd(bottleRecoverySignPost, OctagonSignpostNamePerformOctagonJoin, OctagonSignpostNumber1(OctagonSignpostNamePerformOctagonJoin), (int)subTaskSuccess);

        if(restoreBottleError) {
            if(error){
                *error = restoreBottleError;
            }
            subTaskSuccess = false;
            OctagonSignpostEnd(performEscrowRecoverySignpost, OctagonSignpostNamePerformEscrowRecovery, OctagonSignpostNumber1(OctagonSignpostNamePerformEscrowRecovery), (int)subTaskSuccess);
            return nil;
        }
    } else {
        shouldResetOctagon = true;
    }

    if(shouldResetOctagon) {
        secnotice("clique-recovery", "bottle %@ is not valid, resetting octagon", bottleID);
        NSError* resetError = nil;

        OctagonSignpost resetSignPost = OctagonSignpostBegin(OctagonSignpostNamePerformResetAndEstablishAfterFailedBottle);
        [clique resetAndEstablish:CuttlefishResetReasonNoBottleDuringEscrowRecovery error:&resetError];
        subTaskSuccess = (resetError == nil) ? true : false;
        OctagonSignpostEnd(resetSignPost, OctagonSignpostNamePerformResetAndEstablishAfterFailedBottle, OctagonSignpostNumber1(OctagonSignpostNamePerformResetAndEstablishAfterFailedBottle), (int)subTaskSuccess);

        if(resetError) {
            secnotice("clique-recovery", "failed to reset octagon: %@", resetError);
            if(error){
                *error = resetError;
            }
            OctagonSignpostEnd(performEscrowRecoverySignpost, OctagonSignpostNamePerformEscrowRecovery, OctagonSignpostNumber1(OctagonSignpostNamePerformEscrowRecovery), (int)subTaskSuccess);
            return nil;
        } else{
            secnotice("clique-recovery", "reset octagon succeeded");
        }
    }

    secnotice("clique-recovery", "recovery complete: %@", clique);

    subTaskSuccess = clique ? true : false;
    OctagonSignpostEnd(performEscrowRecoverySignpost, OctagonSignpostNamePerformEscrowRecovery, OctagonSignpostNumber1(OctagonSignpostNamePerformEscrowRecovery), (int)subTaskSuccess);

    return clique;
#else
    if (error) {
        *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecUnimplemented userInfo:nil];
    }
    return NULL;
#endif
}


- (KCPairingChannel *)setupPairingChannelAsInitiator:(KCPairingChannelContext *)ctx
{
#if OCTAGON
    if(ctx.altDSID == nil && self.ctx.altDSID != nil) {
        secnotice("octagon-account", "Configuring pairing channel with configured altDSID: %@", self.ctx.altDSID);
        ctx.altDSID = self.ctx.altDSID;
    } else if(ctx.altDSID != nil) {
        if([ctx.altDSID isEqualToString:self.ctx.altDSID]) {
            secnotice("octagon-account", "Pairing channel context already configured with altDSID: %@", ctx.altDSID);
        } else {
            secnotice("octagon-account", "Pairing channel context configured with altDSID (%@) which does not match Clique altDSID (%@), possible issues ahead", ctx.altDSID, self.ctx.altDSID);
        }
    }

    return [getKCPairingChannelClass() pairingChannelInitiator:ctx];
#else
    return NULL;
#endif
}

- (KCPairingChannel * _Nullable)setupPairingChannelAsInitator:(KCPairingChannelContext *)ctx error:(NSError * __autoreleasing *)error
{
    if (error) {
        *error = nil;
    }
    return [self setupPairingChannelAsInitiator:ctx];
}

- (KCPairingChannel *)setupPairingChannelAsAcceptor:(KCPairingChannelContext *)ctx
{
#if OCTAGON
    if(ctx.altDSID == nil && self.ctx.altDSID != nil) {
        secnotice("octagon-account", "Configuring pairing channel with configured altDSID: %@", self.ctx.altDSID);
        ctx.altDSID = self.ctx.altDSID;
    } else if(ctx.altDSID != nil) {
        if([ctx.altDSID isEqualToString:self.ctx.altDSID]) {
            secnotice("octagon-account", "Pairing channel context already configured with altDSID: %@", ctx.altDSID);
        } else {
            secnotice("octagon-account", "Pairing channel context configured with altDSID (%@) which does not match Clique altDSID (%@), possible issues ahead", ctx.altDSID, self.ctx.altDSID);
        }
    }

    return [getKCPairingChannelClass() pairingChannelAcceptor:ctx];
#else
    return NULL;
#endif
}

- (KCPairingChannel * _Nullable)setupPairingChannelAsAcceptor:(KCPairingChannelContext *)ctx error:(NSError * __autoreleasing *)error
{
    if (error) {
        *error = nil;
    }
    
    return [self setupPairingChannelAsAcceptor:ctx];
}


- (CliqueStatus)_fetchCliqueStatus:(OTOperationConfiguration *)configuration error:(NSError * __autoreleasing *)error
{
#if OCTAGON
    __block CliqueStatus octagonStatus = CliqueStatusError;
    bool subTaskSuccess = false;

    OctagonSignpost fetchCliqueStatusSignPost = OctagonSignpostBegin(OctagonSignpostNameFetchCliqueStatus);

    // Octagon is supreme.

    OTControl* control = [self makeOTControl:error];
    if(!control) {
        secnotice("clique-status", "cliqueStatus noOTControl");
        OctagonSignpostEnd(fetchCliqueStatusSignPost, OctagonSignpostNameFetchCliqueStatus, OctagonSignpostNumber1(OctagonSignpostNameFetchCliqueStatus), (int)subTaskSuccess);

        return CliqueStatusError;
    }

    __block NSError* localError = nil;
    [control fetchCliqueStatus:[[OTControlArguments alloc] initWithConfiguration:self.ctx]
                 configuration:configuration
                         reply:^(CliqueStatus cliqueStatus, NSError * _Nullable fetchError) {
        if(fetchError){
            octagonStatus = CliqueStatusError;
            localError = fetchError;
            secnotice("clique-status", "octagon clique status errored: %@", fetchError);
        } else {
            octagonStatus = cliqueStatus;
        }
    }];

    secnotice("clique-status", "cliqueStatus(%{public}scached)(context:%@, altDSID:%@) returning %@ (error: %@)",
              configuration.useCachedAccountStatus ? "" : "non-",
              self.ctx.context, self.ctx.altDSID,
              OTCliqueStatusToString(octagonStatus), localError);
    if (localError && error) {
        *error = localError;
        subTaskSuccess = false;
    } else {
        subTaskSuccess = true;
    }
    OctagonSignpostEnd(fetchCliqueStatusSignPost, OctagonSignpostNameFetchCliqueStatus, OctagonSignpostNumber1(OctagonSignpostNameFetchCliqueStatus), (int)subTaskSuccess);
    return octagonStatus;
#else // !OCTAGON
    if(error){
        *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecUnimplemented userInfo:nil];
    }
    return (CliqueStatus)kSOSCCError;
#endif
}

// Don't change rules for CoreCDP, and preserve legacy behavior for now
// preserve old behavior until CoreCDP can move to -fetchCliqueStatus:error:
#define LEGACY_WAITING_BEHAVIOR (TARGET_OS_OSX || TARGET_OS_IOS)

- (CliqueStatus)fetchCliqueStatus:(OTOperationConfiguration *)configuration error:(NSError * __autoreleasing * _Nonnull)error
{
    return [self _fetchCliqueStatus:configuration error:error];
}

- (CliqueStatus)fetchCliqueStatus:(NSError * __autoreleasing *)error
{
    OTOperationConfiguration *configuration = [[OTOperationConfiguration alloc] init];
#if LEGACY_WAITING_BEHAVIOR
    configuration.timeoutWaitForCKAccount = 0;
#endif
    return [self _fetchCliqueStatus:configuration error:error];
}

- (CliqueStatus)cachedCliqueStatus:(BOOL)usedCached error:(NSError * __autoreleasing *)error
{
    OTOperationConfiguration *configuration = [[OTOperationConfiguration alloc] init];
#if LEGACY_WAITING_BEHAVIOR
    configuration.timeoutWaitForCKAccount = 0;
#endif
    if (usedCached) {
        configuration.useCachedAccountStatus = YES;
    }
    return [self _fetchCliqueStatus:configuration error:error];
}


- (BOOL)removeFriendsInClique:(NSArray<NSString*>*)friendIdentifiers error:(NSError * __autoreleasing *)error
{
#if OCTAGON
    secnotice("clique-removefriends", "removeFriendsInClique invoked using context:%@, altdsid:%@", self.ctx.context, self.ctx.altDSID);
    OctagonSignpost removeFriendsSignPost = OctagonSignpostBegin(OctagonSignpostNameRemoveFriendsInClique);
    bool subTaskSuccess = false;

    // Annoying: we must sort friendIdentifiers into octagon/sos lists.
    NSMutableArray<NSString*>* octagonIdentifiers = [NSMutableArray array];
    NSMutableArray<NSString*>* sosIdentifiers = [NSMutableArray array];

    for(NSString* friendIdentifier in friendIdentifiers) {
        if([friendIdentifier hasPrefix:@"SHA256:"]) {
            [octagonIdentifiers addObject: friendIdentifier];
        } else {
            [sosIdentifiers addObject: friendIdentifier];
        }
    }

    if(!OctagonPlatformSupportsSOS() && sosIdentifiers.count > 0) {
        NSError *localError = [NSError errorWithDomain:NSOSStatusErrorDomain
                                                  code:errSecUnimplemented
                                              userInfo:@{NSLocalizedDescriptionKey: @"SOS is not available on this platform; can't distrust any SOS peers"}];
        secnotice("clique-removefriends", "removeFriendsInClique failed:%@", localError);
        if(error) {
            *error = localError;
        }
        OctagonSignpostEnd(removeFriendsSignPost, OctagonSignpostNameRemoveFriendsInClique, OctagonSignpostNumber1(OctagonSignpostNameRemoveFriendsInClique), (int)subTaskSuccess);
        return NO;
    }


    __block NSError* localError = nil;
    bool result = true;

    if(octagonIdentifiers.count > 0) {
        OTControl* control = [self makeOTControl:error];
        if(!control) {
            OctagonSignpostEnd(removeFriendsSignPost, OctagonSignpostNameRemoveFriendsInClique, OctagonSignpostNumber1(OctagonSignpostNameRemoveFriendsInClique), (int)subTaskSuccess);
            return NO;
        }

        secnotice("clique-removefriends", "octagon: removing octagon friends: %@", octagonIdentifiers);
        [control removeFriendsInClique:[[OTControlArguments alloc] initWithConfiguration:self.ctx]
                               peerIDs:octagonIdentifiers
                                 reply:^(NSError* replyError) {
            if(replyError) {
                secnotice("clique-removefriends", "removeFriendsInClique failed: unable to remove friends: %@", replyError);
                localError = replyError;
            } else {
                secnotice("clique-removefriends", "octagon: friends removed: %@", octagonIdentifiers);
            }
        }];
    }

    if([OTClique platformSupportsSOS] && sosIdentifiers.count >0) {
        CFErrorRef removeFriendError = NULL;

        secnotice("clique-removefriends", "removing sos friends: %@", sosIdentifiers);
        result = SOSCCRemovePeersFromCircle((__bridge CFArrayRef)friendIdentifiers, &removeFriendError);

        if(removeFriendError) {
            secnotice("clique-removefriends", "removeFriendsInClique failed: unable to remove friends: %@", removeFriendError);
            localError = CFBridgingRelease(removeFriendError);
        }
    }

    if(error && localError) {
        *error = localError;
    }
    secnotice("clique-removefriends", "removeFriendsInClique complete: %d", result);

    subTaskSuccess = result;
    OctagonSignpostEnd(removeFriendsSignPost, OctagonSignpostNameRemoveFriendsInClique, OctagonSignpostNumber1(OctagonSignpostNameRemoveFriendsInClique), (int)subTaskSuccess);

    return result && localError == nil;
#else // !OCTAGON
    return NO;
#endif
}

- (BOOL)leaveClique:(NSError * __autoreleasing *)error
{
#if OCTAGON
    secnotice("clique-leaveClique", "leaveClique invoked using context:%@, altdsid:%@", self.ctx.context, self.ctx.altDSID);
    CFErrorRef removeThisDeviceError = NULL;
    bool result = false;
    bool subTaskSuccess = false;

    OctagonSignpost leaveCliqueSignPost = OctagonSignpostBegin(OctagonSignpostNameLeaveClique);

    OTControl* control = [self makeOTControl:error];
    if(!control) {
        OctagonSignpostEnd(leaveCliqueSignPost, OctagonSignpostNameLeaveClique, OctagonSignpostNumber1(OctagonSignpostNameLeaveClique), (int)subTaskSuccess);
        return NO;
    }

    // We only want to issue a "leave" command if we're actively in a clique
    __block NSError* localError = nil;
    CliqueStatus currentStatus = [self fetchCliqueStatus:[[OTOperationConfiguration alloc] init]
                                                   error:&localError];

    if(localError) {
        secnotice("clique-leaveClique", "fetching current status errored: %@", localError);
        if(error) {
            *error = localError;
        }
        OctagonSignpostEnd(leaveCliqueSignPost, OctagonSignpostNameLeaveClique, OctagonSignpostNumber1(OctagonSignpostNameLeaveClique), (int)subTaskSuccess);
        return NO;
    }

    if(currentStatus == CliqueStatusNotIn) {
        secnotice("clique-leaveClique", "current status is Not In; no need to leave");
        subTaskSuccess = true;
        OctagonSignpostEnd(leaveCliqueSignPost, OctagonSignpostNameLeaveClique, OctagonSignpostNumber1(OctagonSignpostNameLeaveClique), (int)subTaskSuccess);
        return YES;
    }
    [control leaveClique:[[OTControlArguments alloc] initWithConfiguration:self.ctx] reply:^(NSError * _Nullable leaveError) {
        if(leaveError) {
            secnotice("clique-leaveClique", "leaveClique errored: %@", leaveError);
            localError = leaveError;
        } else {
            secnotice("clique-leaveClique", "leaveClique success.");
        }
    }];

    if(error) {
        *error = localError;
    }
    result = !localError;

    if([OTClique platformSupportsSOS]) {
        result &= SOSCCRemoveThisDeviceFromCircle(&removeThisDeviceError);
        if (error) {
            *error = (NSError*)CFBridgingRelease(removeThisDeviceError);
        } else {
            CFBridgingRelease(removeThisDeviceError);
        }
    }
    secnotice("clique-leaveClique", "leaveClique complete: %d", result);

    subTaskSuccess = result;
    OctagonSignpostEnd(leaveCliqueSignPost, OctagonSignpostNameLeaveClique, OctagonSignpostNumber1(OctagonSignpostNameLeaveClique), (int)subTaskSuccess);

    return result ? YES : NO;
#else // !OCTAGON
    return NO;
#endif
}

- (NSDictionary<NSString*,NSString*>* _Nullable)peerDeviceNamesByPeerID:(NSError * __autoreleasing *)error
{
#if OCTAGON
    secnotice("clique", "peerDeviceNamesByPeerID invoked using context:%@, altdsid:%@", self.ctx.context, self.ctx.altDSID);
    OctagonSignpost peerNamesSignPost = OctagonSignpostBegin(OctagonSignpostNamePeerDeviceNamesByPeerID);
    __block bool subTaskSuccess = false;
    NSMutableDictionary<NSString*, NSString*>* retPeers = [NSMutableDictionary dictionary];

    OTControl* control = [self makeOTControl:error];
    if(!control) {
        OctagonSignpostEnd(peerNamesSignPost, OctagonSignpostNamePeerDeviceNamesByPeerID, OctagonSignpostNumber1(OctagonSignpostNamePeerDeviceNamesByPeerID), (int)subTaskSuccess);
        return nil;
    }

    __block NSError* localError = nil;
    __block NSDictionary<NSString*, NSString*>* localPeers = nil;

    [control peerDeviceNamesByPeerID:[[OTControlArguments alloc] initWithConfiguration:self.ctx] reply:^(NSDictionary<NSString*,NSString*>* peers, NSError* controlError) {
        if(controlError) {
            secnotice("clique", "peerDeviceNamesByPeerID errored: %@", controlError);
        } else {
            secnotice("clique", "peerDeviceNamesByPeerID succeeded: %@", peers);
        }
        localError = controlError;
        localPeers = peers;
    }];

    if(error && localError) {
        *error = localError;
    }
    if(localError) {
        OctagonSignpostEnd(peerNamesSignPost, OctagonSignpostNamePeerDeviceNamesByPeerID, OctagonSignpostNumber1(OctagonSignpostNamePeerDeviceNamesByPeerID), (int)subTaskSuccess);
        return nil;
    }
    [retPeers addEntriesFromDictionary:localPeers];
    secnotice("clique", "Received %lu Octagon peers", (unsigned long)localPeers.count);

    if([OTClique platformSupportsSOS]) {
        CFErrorRef peerErrorRef = NULL;
        NSMutableDictionary<NSString*,NSString*>* peerMapping = [NSMutableDictionary dictionary];
        NSArray* arrayOfPeerRefs = CFBridgingRelease(SOSCCCopyPeerPeerInfo(&peerErrorRef));
        if(arrayOfPeerRefs){
            [arrayOfPeerRefs enumerateObjectsUsingBlock:^(id peerRef, NSUInteger idx, BOOL * stop) {
                SOSPeerInfoRef peer = (__bridge SOSPeerInfoRef)peerRef;
                if(peer){
                    [peerMapping setObject:(__bridge NSString*)SOSPeerInfoGetPeerName(peer) forKey:(__bridge NSString*)SOSPeerInfoGetPeerID(peer)];
                }
            }];
        }
        subTaskSuccess = (peerErrorRef == NULL || [retPeers count] == 0) ? true : false;

        if (error) {
            *error = (NSError*)CFBridgingRelease(peerErrorRef);
        } else {
            CFBridgingRelease(peerErrorRef);
        }
        [retPeers addEntriesFromDictionary:peerMapping];
        secnotice("clique", "Received %lu SOS peers", (unsigned long)peerMapping.count);
    }

    OctagonSignpostEnd(peerNamesSignPost, OctagonSignpostNamePeerDeviceNamesByPeerID, OctagonSignpostNumber1(OctagonSignpostNamePeerDeviceNamesByPeerID), (int)subTaskSuccess);
    return retPeers;
#else // !OCTAGON
    return NULL;
#endif
}

- (BOOL)joinAfterRestore:(NSError * __autoreleasing *)error
{
    secnotice("clique-recovery", "joinAfterRestore for context:%@, altdsid:%@", self.ctx.context, self.ctx.altDSID);
    OctagonSignpost joinAfterRestoreSignPost = OctagonSignpostBegin(OctagonSignpostNameJoinAfterRestore);
    bool subTaskSuccess = false;

    if([OTClique platformSupportsSOS]) {
        CFErrorRef restoreError = NULL;
        bool res = SOSCCRequestToJoinCircleAfterRestore(&restoreError);
        if (error) {
            *error = (NSError*)CFBridgingRelease(restoreError);
        } else {
            CFBridgingRelease(restoreError);
        }
        secnotice("clique-recovery", "joinAfterRestore complete: %d %@", res, error ? *error : @"no error pointer provided");

        subTaskSuccess = res;
        OctagonSignpostEnd(joinAfterRestoreSignPost, OctagonSignpostNameJoinAfterRestore, OctagonSignpostNumber1(OctagonSignpostNameJoinAfterRestore), (int)subTaskSuccess);

        return res ? YES : NO;
    } else {
        secnotice("clique-recovery", "SOS disabled for this platform, returning NO");
        if(error){
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                         code:errSecUnimplemented
                                     userInfo:@{NSLocalizedDescriptionKey: @"join after restore unimplemented"}];
        }
        OctagonSignpostEnd(joinAfterRestoreSignPost, OctagonSignpostNameJoinAfterRestore, OctagonSignpostNumber1(OctagonSignpostNameJoinAfterRestore), (int)subTaskSuccess);
        return NO;
    }
}

- (BOOL)safariPasswordSyncingEnabled:(NSError **)error
{
    return [self fetchUserControllableViewsSyncingEnabled:error];
}

- (BOOL)sosSafariPasswordSyncingEnabled:(NSError **)error
{
    secnotice("clique-safari", "safariPasswordSyncingEnabled for context:%@, altdsid:%@", self.ctx.context, self.ctx.altDSID);
    OctagonSignpost safariSyncingEnabledSignPost = OctagonSignpostBegin(OctagonSignpostNameSafariPasswordSyncingEnabled);
    bool subTaskSuccess = false;

    if([OTClique platformSupportsSOS]) {
        CFErrorRef viewErrorRef = NULL;

        SOSViewResultCode result = SOSCCView(kSOSViewAutofillPasswords, kSOSCCViewQuery, &viewErrorRef);
        subTaskSuccess = (viewErrorRef == NULL) ? true : false;

        BOOL viewMember = result == kSOSCCViewMember;
        if (error) {
            *error = (NSError*)CFBridgingRelease(viewErrorRef);
        } else {
            CFBridgingRelease(viewErrorRef);
        }
        OctagonSignpostEnd(safariSyncingEnabledSignPost, OctagonSignpostNameSafariPasswordSyncingEnabled, OctagonSignpostNumber1(OctagonSignpostNameSafariPasswordSyncingEnabled), (int)subTaskSuccess);

        secnotice("clique-safari", "safariPasswordSyncingEnabled complete: %@", viewMember ? @"YES" : @"NO");
        return viewMember;
    } else {
        secnotice("clique-safari", "SOS disabled for this platform, returning NO");
        if(error){
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                         code:errSecUnimplemented
                                     userInfo:@{NSLocalizedDescriptionKey: @"safari password syncing enabled unimplemented"}];
        }
        OctagonSignpostEnd(safariSyncingEnabledSignPost, OctagonSignpostNameSafariPasswordSyncingEnabled, OctagonSignpostNumber1(OctagonSignpostNameSafariPasswordSyncingEnabled), (int)subTaskSuccess);
        return NO;
    }
}

- (BOOL)setUserControllableViewsSyncStatus:(BOOL)enabled
                                     error:(NSError* __autoreleasing *)error
{
    if([OTClique platformSupportsSOS]) {
        // We either enable or disable this list of SOS views, taken from CDP.
        NSSet<NSString*>* sosViews = [NSSet setWithObjects:(__bridge id)kSOSViewWiFi,
                                      (__bridge id)kSOSViewAutofillPasswords,
                                      (__bridge id)kSOSViewSafariCreditCards,
                                      (__bridge id)kSOSViewOtherSyncable,
                                      nil];

        BOOL sosResult = NO;
        if(enabled) {
            sosResult = [self sosViewSet:sosViews disabledViews:[NSSet set]];
        } else {
            sosResult = [self sosViewSet:[NSSet set] disabledViews:sosViews];
        }

        if(sosResult == NO) {
            secnotice("clique-user-sync", "SOS view setting failed, but no error returned");
            if(error) {
                *error = [NSError errorWithDomain:(__bridge NSString*)kSOSErrorDomain
                                             code:kSOSErrorNotReady
                                         userInfo:@{
                                             NSLocalizedDescriptionKey: @"SOS reported failure, but no error given"
                                         }];
            }

            return NO;
        }
    }

    return [self setOctagonUserControllableViewsSyncEnabled:enabled
                                                      error:error];
}

- (BOOL)setOctagonUserControllableViewsSyncEnabled:(BOOL)enabled
                                             error:(NSError* __autoreleasing *)error
{
#if OCTAGON
    OTControl* control = [self makeOTControl:error];
    if(!control) {
        return NO;
    }

    __block NSError* localError = nil;

    secnotice("clique-user-sync", "setting user-controllable-sync status to %@", enabled ? @"enabled" : @"paused");

    [control setUserControllableViewsSyncStatus:[[OTControlArguments alloc] initWithConfiguration:self.ctx]
                                        enabled:enabled
                                          reply:^(BOOL nowSyncing, NSError* _Nullable fetchError) {
        if(fetchError) {
            secnotice("clique-user-sync", "setting user-controllable-sync status errored: %@", fetchError);
            localError = fetchError;
        } else {
            secnotice("clique-user-sync", "setting user-controllable-sync status succeeded, now : %@", nowSyncing ? @"enabled" : @"paused");
        }
    }];

    if(error && localError) {
        *error = localError;
    }

    return localError == nil;
#else
    if(error) {
        *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                     code:errSecUnimplemented
                                 userInfo:@{NSLocalizedDescriptionKey: @"setOctagonUserControllableViewSync unimplemented on this platform"}];
    }
    return NO;
#endif
}

- (BOOL)fetchUserControllableViewsSyncingEnabled:(NSError* __autoreleasing *)error
{
#ifndef OCTAGON
    // short circuit when we don't have octagon support compiled in
    if(![OTClique platformSupportsSOS]) {
        secnotice("clique-user-sync", "No syncing platforms enabled; views are not syncing");
        return NO;
    }
#endif

    __block BOOL octagonSyncing = NO;
    __block NSError* localError = nil;
#if OCTAGON
    OTControl* control = [self makeOTControl:error];
    if(!control) {
        return NO;
    }

    [control fetchUserControllableViewsSyncStatus:[[OTControlArguments alloc] initWithConfiguration:self.ctx]
                                            reply:^(BOOL nowSyncing, NSError* _Nullable fetchError) {
        if(fetchError) {
            secnotice("clique-user-sync", "fetching user-controllable-sync status errored: %@", fetchError);
        } else {
            secnotice("clique-user-sync", "fetched user-controllable-sync status as : %@", nowSyncing ? @"enabled" : @"paused");
        }
        octagonSyncing = nowSyncing;
        localError = fetchError;
    }];

    if(localError) {
        if(error) {
            *error = localError;
        }
        return octagonSyncing;
    }
#endif

    if([OTClique platformSupportsSOS]) {
        BOOL sosSafariEnabled = [self sosSafariPasswordSyncingEnabled:&localError];

        if(localError) {
            if(error) {
                *error = localError;
            }
            return sosSafariEnabled;
        }

        // Return the OR of this value, so that the UI checkbox will be on if any syncing is occurring
        return octagonSyncing || sosSafariEnabled;
    } else {
        return octagonSyncing;
    }
}


- (BOOL)isLastFriend:(NSError **)error
{
    secnotice("clique-isLastFriend", "is last friend");
    return NO;
}

- (BOOL)waitForInitialSync:(NSError *__autoreleasing*)error
{
    secnotice("clique-legacy", "waitForInitialSync for context:%@, altdsid:%@", self.ctx.context, self.ctx.altDSID);

    OctagonSignpost waitForInitialSyncSignPost = OctagonSignpostBegin(OctagonSignpostNameWaitForInitialSync);
    bool subTaskSuccess = false;

    if([OTClique platformSupportsSOS]) {
        CFErrorRef initialSyncErrorRef = NULL;
        BOOL initialSyncResult = SOSCCWaitForInitialSync(&initialSyncErrorRef) ? YES : NO;

        if (error) {
            *error = (NSError*)CFBridgingRelease(initialSyncErrorRef);
        } else {
            CFBridgingRelease(initialSyncErrorRef);
        }
        secnotice("clique-legacy", "waitForInitialSync waited: %d %@", initialSyncResult, error ? *error : @"no error pointer provided");

        subTaskSuccess = initialSyncResult ? true : false;
        OctagonSignpostEnd(waitForInitialSyncSignPost, OctagonSignpostNameWaitForInitialSync, OctagonSignpostNumber1(OctagonSignpostNameWaitForInitialSync), (int)subTaskSuccess);

        return initialSyncResult;
    } else {
        secnotice("clique-legacy", "SOS disabled for this platform, returning NO");
        if(error){
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                         code:errSecUnimplemented
                                     userInfo:@{NSLocalizedDescriptionKey: @"wait for initial sync unimplemented"}];
        }
        OctagonSignpostEnd(waitForInitialSyncSignPost, OctagonSignpostNameWaitForInitialSync, OctagonSignpostNumber1(OctagonSignpostNameWaitForInitialSync), (int)subTaskSuccess);
        return NO;
    }
}

- (NSArray* _Nullable)copyViewUnawarePeerInfo:(NSError *__autoreleasing*)error
{
    secnotice("clique-legacy", "copyViewUnawarePeerInfo for context:%@, altdsid:%@", self.ctx.context, self.ctx.altDSID);

    OctagonSignpost signPost = OctagonSignpostBegin(OctagonSignpostNameCopyViewUnawarePeerInfo);
    bool subTaskSuccess = false;

    if([OTClique platformSupportsSOS]) {
        CFErrorRef copyViewUnawarePeerInfoErrorRef = NULL;
        CFArrayRef peerListRef = SOSCCCopyViewUnawarePeerInfo(&copyViewUnawarePeerInfoErrorRef);

        NSArray* peerList = (peerListRef ? (NSArray*)(CFBridgingRelease(peerListRef)) : nil);
        if (error) {
            *error = (NSError*)CFBridgingRelease(copyViewUnawarePeerInfoErrorRef);
        } else {
            CFBridgingRelease(copyViewUnawarePeerInfoErrorRef);
        }
        subTaskSuccess = (peerList != nil) ? true : false;
        OctagonSignpostEnd(signPost, OctagonSignpostNameCopyViewUnawarePeerInfo, OctagonSignpostNumber1(OctagonSignpostNameCopyViewUnawarePeerInfo), (int)subTaskSuccess);

        return peerList;
    } else {
        secnotice("clique-legacy", "SOS disabled for this platform, returning NULL");
        if(error){
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                         code:errSecUnimplemented
                                     userInfo:@{NSLocalizedDescriptionKey: @"copy view unaware peer info unimplemented"}];
        }
        OctagonSignpostEnd(signPost, OctagonSignpostNameCopyViewUnawarePeerInfo, OctagonSignpostNumber1(OctagonSignpostNameCopyViewUnawarePeerInfo), (int)subTaskSuccess);
        return nil;
    }
}

- (BOOL)viewSet:(NSSet*)enabledViews disabledViews:(NSSet*)disabledViews
{
    bool enableUserViews = [enabledViews containsObject:(__bridge NSString*)kSOSViewAutofillPasswords];
    if(enableUserViews && SOSVisibleKeychainNotAllowed()) {
        secnotice("clique-legacy", "Cannot enable visible keychain views due to profile restrictions");
        return NO;
    }

    NSError* octagonError = nil;
    // This function should log its success or failure
    BOOL result = [self setOctagonUserControllableViewsSyncEnabled:enableUserViews error:&octagonError];
    if(!result) {
        return NO;
    }

    return [self sosViewSet:enabledViews disabledViews:disabledViews];
}

- (BOOL)sosViewSet:(NSSet*)enabledViews disabledViews:(NSSet*)disabledViews
{
    secnotice("clique-legacy", "viewSet for context:%@, altdsid:%@ enable:%@, disable:%@",
              self.ctx.context, self.ctx.altDSID, enabledViews, disabledViews);
    OctagonSignpost signPost = OctagonSignpostBegin(OctagonSignpostNameViewSet);
    bool subTaskSuccess = false;

    if([OTClique platformSupportsSOS]) {
        if(SOSVisibleKeychainNotAllowed() && enabledViews && [enabledViews count] && SOSViewSetIntersectsV0((__bridge CFSetRef)(enabledViews))) {
            secnotice("clique-legacy", "Cannot enable visible keychain views due to profile restrictions");
            enabledViews = nil;
        }

        BOOL viewSetResult = NO;
        if(enabledViews || disabledViews) {
            bool result = SOSCCViewSet((__bridge CFSetRef)enabledViews, (__bridge CFSetRef)disabledViews);
            viewSetResult = result ? YES : NO;
            subTaskSuccess = result;
        }
        OctagonSignpostEnd(signPost, OctagonSignpostNameViewSet, OctagonSignpostNumber1(OctagonSignpostNameViewSet), (int)subTaskSuccess);
        return viewSetResult;
    } else {
        secnotice("clique-legacy", "SOS disabled for this platform, returning NO");
        OctagonSignpostEnd(signPost, OctagonSignpostNameViewSet, OctagonSignpostNumber1(OctagonSignpostNameViewSet), (int)subTaskSuccess);
        return NO;
    }
}

- (BOOL)setUserCredentialsAndDSID:(NSString*)userLabel
                         password:(NSData*)userPassword
                            error:(NSError *__autoreleasing*)error
{
    secnotice("clique-legacy", "setUserCredentialsAndDSID for context:%@, altdsid:%@", self.ctx.context, self.ctx.altDSID);
    OctagonSignpost signPost = OctagonSignpostBegin(OctagonSignpostNameSetUserCredentialsAndDSID);
    bool subTaskSuccess = false;

    if([OTClique platformSupportsSOS]) {
        CFErrorRef setCredentialsErrorRef = NULL;
        bool result = SOSCCSetUserCredentialsAndDSID((__bridge CFStringRef)userLabel,
                                                     (__bridge CFDataRef)userPassword,
                                                     (__bridge CFStringRef)self.ctx.dsid,
                                                     &setCredentialsErrorRef);

        BOOL setCredentialsResult = result ? YES : NO;
        secnotice("clique-legacy", "setUserCredentialsAndDSID results: %d %@", setCredentialsResult, setCredentialsErrorRef);
        if (error) {
            *error = (NSError*)CFBridgingRelease(setCredentialsErrorRef);
        } else {
            CFBridgingRelease(setCredentialsErrorRef);
        }
        subTaskSuccess = result;
        OctagonSignpostEnd(signPost, OctagonSignpostNameSetUserCredentialsAndDSID, OctagonSignpostNumber1(OctagonSignpostNameSetUserCredentialsAndDSID), (int)subTaskSuccess);

        return setCredentialsResult;
    } else {
        secnotice("clique-legacy", "SOS disabled for this platform, returning NO");
        if(error){
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                         code:errSecUnimplemented
                                     userInfo:@{NSLocalizedDescriptionKey: @"set user credentials unimplemented"}];
        }
        OctagonSignpostEnd(signPost, OctagonSignpostNameSetUserCredentialsAndDSID, OctagonSignpostNumber1(OctagonSignpostNameSetUserCredentialsAndDSID), (int)subTaskSuccess);
        return NO;
    }
}

- (BOOL)tryUserCredentialsAndDSID:(NSString*)userLabel
                         password:(NSData*)userPassword
                            error:(NSError *__autoreleasing*)error
{
    secnotice("clique-legacy", "tryUserCredentialsAndDSID for context:%@, altdsid:%@", self.ctx.context, self.ctx.altDSID);
    OctagonSignpost signPost = OctagonSignpostBegin(OctagonSignpostNameTryUserCredentialsAndDSID);
    bool subTaskSuccess = false;

    if([OTClique platformSupportsSOS]) {
        CFErrorRef tryCredentialsErrorRef = NULL;
        bool result = SOSCCTryUserCredentialsAndDSID((__bridge CFStringRef)userLabel,
                                                     (__bridge CFDataRef)userPassword,
                                                     (__bridge CFStringRef)self.ctx.dsid,
                                                     &tryCredentialsErrorRef);

        BOOL tryCredentialsResult = result ? YES : NO;
        secnotice("clique-legacy", "tryUserCredentialsAndDSID results: %d %@", tryCredentialsResult, tryCredentialsErrorRef);
        if (error) {
            *error = (NSError*)CFBridgingRelease(tryCredentialsErrorRef);
        } else {
            CFBridgingRelease(tryCredentialsErrorRef);
        }
        subTaskSuccess = result;
        OctagonSignpostEnd(signPost, OctagonSignpostNameTryUserCredentialsAndDSID, OctagonSignpostNumber1(OctagonSignpostNameTryUserCredentialsAndDSID), (int)subTaskSuccess);
        return tryCredentialsResult;

    } else {
        secnotice("clique-legacy", "SOS disabled for this platform, returning NO");
        if(error){
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                         code:errSecUnimplemented
                                     userInfo:@{NSLocalizedDescriptionKey: @"try user credentials unimplemented"}];
        }
        OctagonSignpostEnd(signPost, OctagonSignpostNameTryUserCredentialsAndDSID, OctagonSignpostNumber1(OctagonSignpostNameTryUserCredentialsAndDSID), (int)subTaskSuccess);
        return NO;
    }
}

- (NSArray* _Nullable)copyPeerPeerInfo:(NSError *__autoreleasing*)error
{
    secnotice("clique-legacy", "copyPeerPeerInfo for context:%@, altdsid:%@", self.ctx.context, self.ctx.altDSID);
    OctagonSignpost signPost = OctagonSignpostBegin(OctagonSignpostNameCopyPeerPeerInfo);
    bool subTaskSuccess = false;

    if([OTClique platformSupportsSOS]) {
        CFErrorRef copyPeerErrorRef = NULL;
        CFArrayRef result = SOSCCCopyPeerPeerInfo(&copyPeerErrorRef);

        NSArray* peerList = (result ? (NSArray*)(CFBridgingRelease(result)) : nil);

        secnotice("clique-legacy", "copyPeerPeerInfo results: %@ (%@)", peerList, copyPeerErrorRef);
        if (error) {
            *error = (NSError*)CFBridgingRelease(copyPeerErrorRef);
        } else {
            CFBridgingRelease(copyPeerErrorRef);
        }
        subTaskSuccess = (peerList != nil) ? true : false;
        OctagonSignpostEnd(signPost, OctagonSignpostNameCopyPeerPeerInfo, OctagonSignpostNumber1(OctagonSignpostNameCopyPeerPeerInfo), (int)subTaskSuccess);
        return peerList;
    } else {
        secnotice("clique-legacy", "SOS disabled for this platform, returning NO");
        if(error){
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                         code:errSecUnimplemented
                                     userInfo:@{NSLocalizedDescriptionKey: @"copy peer peer info unimplemented"}];
        }
        OctagonSignpostEnd(signPost, OctagonSignpostNameCopyPeerPeerInfo, OctagonSignpostNumber1(OctagonSignpostNameCopyPeerPeerInfo), (int)subTaskSuccess);
        return nil;
    }
}

- (BOOL)peersHaveViewsEnabled:(NSArray<NSString*>*)viewNames error:(NSError *__autoreleasing*)error
{
    secnotice("clique-legacy", "peersHaveViewsEnabled for context:%@, altdsid:%@", self.ctx.context, self.ctx.altDSID);
    OctagonSignpost signPost = OctagonSignpostBegin(OctagonSignpostNamePeersHaveViewsEnabled);
    bool subTaskSuccess = false;

    if([OTClique platformSupportsSOS]) {
        CFErrorRef viewsEnabledErrorRef = NULL;
        BOOL viewsEnabledResult = NO;

        CFBooleanRef result = SOSCCPeersHaveViewsEnabled((__bridge CFArrayRef)viewNames, &viewsEnabledErrorRef);
        if(result){
            viewsEnabledResult = CFBooleanGetValue(result) ? YES : NO;
        }
        secnotice("clique-legacy", "peersHaveViewsEnabled results: %@ (%@)", viewsEnabledResult ? @"YES" : @"NO",
                  viewsEnabledErrorRef);
        if (error) {
            *error = (NSError*)CFBridgingRelease(viewsEnabledErrorRef);
        } else {
            CFBridgingRelease(viewsEnabledErrorRef);
        }
        subTaskSuccess = viewsEnabledResult ? true : false;
        OctagonSignpostEnd(signPost, OctagonSignpostNamePeersHaveViewsEnabled, OctagonSignpostNumber1(OctagonSignpostNamePeersHaveViewsEnabled), (int)subTaskSuccess);
        return viewsEnabledResult;
    } else {
        secnotice("clique-legacy", "SOS disabled for this platform, returning NO");
        if(error){
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                         code:errSecUnimplemented
                                     userInfo:@{NSLocalizedDescriptionKey: @"peers have views enabled unimplemented"}];
        }
        OctagonSignpostEnd(signPost, OctagonSignpostNamePeersHaveViewsEnabled, OctagonSignpostNumber1(OctagonSignpostNamePeersHaveViewsEnabled), (int)subTaskSuccess);
        return NO;
    }
}

- (BOOL)requestToJoinCircle:(NSError *__autoreleasing*)error
{
    bool result = false;
    bool subTaskSuccess = false;
    OctagonSignpost signPost = OctagonSignpostBegin(OctagonSignpostNameRequestToJoinCircle);

#if OCTAGON
    secnotice("clique-legacy", "requestToJoinCircle for context:%@, altdsid:%@", self.ctx.context, self.ctx.altDSID);

    // Sometimes, CoreCDP calls this to cause a circle creation to occur.
    // So, for Octagon, we might want to request a establish, but not a reset.

    // Fetch the current trust status, so we know if we should fire off the establish.
    NSError* localError = nil;
    CliqueStatus status = [self fetchCliqueStatus: &localError];

    if(localError) {
        secnotice("clique-legacy", "fetching clique status failed: %@", localError);
        if(error) {
            *error = localError;
        }
        OctagonSignpostEnd(signPost, OctagonSignpostNameRequestToJoinCircle, OctagonSignpostNumber1(OctagonSignpostNameRequestToJoinCircle), (int)subTaskSuccess);
        return NO;
    }

    if(status == CliqueStatusAbsent) {
        secnotice("clique-legacy", "clique status is %@; beginning an establish", OTCliqueStatusToString(status));
        [self establish:&localError];

        if(localError) {
            if(error) {
                *error = localError;
            }
            OctagonSignpostEnd(signPost, OctagonSignpostNameRequestToJoinCircle, OctagonSignpostNumber1(OctagonSignpostNameRequestToJoinCircle), (int)subTaskSuccess);
            return NO;
        } else {
            secnotice("clique-legacy", "establish succeeded");
        }
    } else {
        secnotice("clique-legacy", "clique status is %@; performing no Octagon actions", OTCliqueStatusToString(status));
    }

    // If we didn't early-exit, and we aren't going to invoke SOS below, we succeeded.
    if(!OctagonPlatformSupportsSOS()) {
        secnotice("clique-legacy", "requestToJoinCircle platform does not support SOS");
        subTaskSuccess = true;
        OctagonSignpostEnd(signPost, OctagonSignpostNameRequestToJoinCircle, OctagonSignpostNumber1(OctagonSignpostNameRequestToJoinCircle), (int)subTaskSuccess);
        return YES;
    }
#endif // OCTAGON

    if([OTClique platformSupportsSOS]) {
        CFErrorRef joinErrorRef = NULL;
        result = SOSCCRequestToJoinCircle(&joinErrorRef);
        secnotice("clique-legacy", "sos requestToJoinCircle complete: %d %@", result, joinErrorRef);
        if (error) {
            *error = (NSError*)CFBridgingRelease(joinErrorRef);
        } else {
            CFBridgingRelease(joinErrorRef);
        }
    }

    subTaskSuccess = result;
    OctagonSignpostEnd(signPost, OctagonSignpostNameRequestToJoinCircle, OctagonSignpostNumber1(OctagonSignpostNameRequestToJoinCircle), (int)subTaskSuccess);

    return result ? YES : NO;
}

- (BOOL)accountUserKeyAvailable
{
    secnotice("clique-legacy", "accountUserKeyAvailable for context:%@, altdsid:%@", self.ctx.context, self.ctx.altDSID);
    OctagonSignpost signPost = OctagonSignpostBegin(OctagonSignpostNameAccountUserKeyAvailable);
    bool subTaskSuccess = false;

    if([OTClique platformSupportsSOS]) {
        BOOL canAuthenticate = SOSCCCanAuthenticate(NULL) ? YES : NO;
        if (canAuthenticate == NO) {
            secnotice("clique-legacy", "Security requires credentials...");
        }
        subTaskSuccess = canAuthenticate ? true : false;
        OctagonSignpostEnd(signPost, OctagonSignpostNameAccountUserKeyAvailable, OctagonSignpostNumber1(OctagonSignpostNameAccountUserKeyAvailable), (int)subTaskSuccess);
        return canAuthenticate;
    } else {
        secnotice("clique-legacy", "SOS disabled for this platform, returning NO");
        OctagonSignpostEnd(signPost, OctagonSignpostNameAccountUserKeyAvailable, OctagonSignpostNumber1(OctagonSignpostNameAccountUserKeyAvailable), (int)subTaskSuccess);
        return NO;
    }
}

+ (NSArray<NSData*>* _Nullable)fetchEscrowRecordsInternal:(OTConfigurationContext*)configurationContext
                                                    error:(NSError**)error
{
#if OCTAGON
    secnotice("clique-fetchrecords", "fetching escrow records for context:%@, altdsid:%@", configurationContext.context, configurationContext.altDSID);

    __block NSError* localError = nil;
    __block NSArray<NSData*>* localRecords = nil;

    OTControl *control = [configurationContext makeOTControl:&localError];
    if (!control) {
        secnotice("clique-fetchrecords", "unable to create otcontrol: %@", localError);
        if (error) {
            *error = localError;
        }
        return nil;
    }
    [control fetchEscrowRecords:[[OTControlArguments alloc] initWithConfiguration:configurationContext]
                         source:configurationContext.escrowFetchSource
                          reply:^(NSArray<NSData*>* _Nullable records,
                                  NSError* _Nullable fetchError) {
        if (fetchError) {
            secnotice("clique-fetchrecords", "fetchEscrowRecords errored: %@", fetchError);
        } else {
            secnotice("clique-fetchrecords", "fetchEscrowRecords succeeded: %@", records);
        }
        localError = fetchError;
        localRecords = records;
    }];
    
    if(error && localError) {
        *error = localError;
    }

    secnotice("clique-fetchrecords", "fetchEscrowRecords complete");

    return localRecords;
#else // !OCTAGON
    if (error) {
        *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecUnimplemented userInfo:nil];
    }
    return NULL;
#endif
}

// MARK: SBD interfaces
+ (OTBottleIDs* _Nullable)findOptimalBottleIDsWithContextData:(OTConfigurationContext*)data
                                                        error:(NSError**)error
{
#if OCTAGON
    secnotice("clique-findbottle", "finding optimal bottles for context:%@, altdsid:%@", data.context, data.altDSID);
    OctagonSignpost signPost = OctagonSignpostBegin(OctagonSignpostNameFindOptimalBottleIDsWithContextData);
    bool subTaskSuccess = false;

    __block NSError* localError = nil;
    __block NSArray<NSString*>* localViableBottleIDs = nil;
    __block NSArray<NSString*>* localPartiallyViableBottleIDs = nil;

    OTControl *control = [data makeOTControl:&localError];
    if (!control) {
        secnotice("clique-findbottle", "unable to create otcontrol: %@", localError);
        if (error) {
            *error = localError;
        }
        OctagonSignpostEnd(signPost, OctagonSignpostNameFindOptimalBottleIDsWithContextData, OctagonSignpostNumber1(OctagonSignpostNameFindOptimalBottleIDsWithContextData), (int)subTaskSuccess);
        return nil;
    }
    [control fetchAllViableBottles:[[OTControlArguments alloc] initWithConfiguration:data]
                             reply:^(NSArray<NSString *> * _Nullable sortedBottleIDs,
                                     NSArray<NSString*> * _Nullable sortedPartialBottleIDs,
                                     NSError * _Nullable fetchError) {
        if(fetchError) {
            secnotice("clique-findbottle", "findOptimalBottleIDsWithContextData errored: %@", fetchError);
        } else {
            secnotice("clique-findbottle", "findOptimalBottleIDsWithContextData succeeded: %@, %@", sortedBottleIDs, sortedPartialBottleIDs);
        }
        localError = fetchError;
        localViableBottleIDs = sortedBottleIDs;
        localPartiallyViableBottleIDs = sortedPartialBottleIDs;
    }];

    if(error && localError) {
        *error = localError;
    }
    OTBottleIDs* bottleIDs = [[OTBottleIDs alloc] init];
    bottleIDs.preferredBottleIDs = localViableBottleIDs;
    bottleIDs.partialRecoveryBottleIDs = localPartiallyViableBottleIDs;

    secnotice("clique-findbottle", "findOptimalBottleIDsWithContextData complete");

    subTaskSuccess = (localError == nil) ? true : false;
    OctagonSignpostEnd(signPost, OctagonSignpostNameFindOptimalBottleIDsWithContextData, OctagonSignpostNumber1(OctagonSignpostNameFindOptimalBottleIDsWithContextData), (int)subTaskSuccess);
    return bottleIDs;
#else // !OCTAGON
    if (error) {
        *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecUnimplemented userInfo:nil];
    }
    return NULL;
#endif
}

+ (OTClique* _Nullable)recoverWithContextData:(OTConfigurationContext*)data
                                     bottleID:(NSString*)bottleID
                              escrowedEntropy:(NSData*)entropy
                                        error:(NSError**)error
{
#if OCTAGON
    secnotice("octagon", "replaced by performEscrowRecoveryWithContextData:escrowArguments:error: remove call");
    return nil;
#else // !OCTAGON
    if (error) {
        *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecUnimplemented userInfo:nil];
    }
    return NULL;
#endif
}

// used by sbd to fill in the escrow record
// TODO: what extra entitlement do you need to call this?
- (void)fetchEscrowContents:(void (^)(NSData* _Nullable entropy,
                                      NSString* _Nullable bottleID,
                                      NSData* _Nullable signingPublicKey,
                                      NSError* _Nullable error))reply
{
#if OCTAGON
    secnotice("clique-fetchescrow", "fetching entropy for bottling for context:%@, altdsid:%@", self.ctx.context, self.ctx.altDSID);
    OctagonSignpost signPost = OctagonSignpostBegin(OctagonSignpostNameFetchEscrowContents);
    __block bool subTaskSuccess = false;
    NSError* controlError = nil;
    OTControl* control = [self makeOTControl:&controlError];
    if (!control) {
        OctagonSignpostEnd(signPost, OctagonSignpostNameFetchEscrowContents, OctagonSignpostNumber1(OctagonSignpostNameFetchEscrowContents), (int)subTaskSuccess);
        reply(nil, nil, nil, controlError);
        return;
    }
    [control fetchEscrowContents:[[OTControlArguments alloc] initWithConfiguration:self.ctx]
                           reply:^(NSData * _Nullable entropy,
                                   NSString * _Nullable bottleID,
                                   NSData * _Nullable signingPublicKey,
                                   NSError * _Nullable error) {
        if(error){
            secnotice("clique-fetchescrow", "fetchEscrowContents errored: %@", error);
        } else{
            secnotice("clique-fetchescrow","fetchEscrowContents succeeded");
        }
        subTaskSuccess = (error == nil) ? true : false;
        OctagonSignpostEnd(signPost, OctagonSignpostNameFetchEscrowContents, OctagonSignpostNumber1(OctagonSignpostNameFetchEscrowContents), (int)subTaskSuccess);
        reply (entropy, bottleID, signingPublicKey, error);
    }];
#else // !OCTAGON
    reply(nil, nil, nil, [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecUnimplemented userInfo:nil]);
#endif
}

+ (void)setNewRecoveryKeyWithData:(OTConfigurationContext*)ctx
                      recoveryKey:(NSString*)recoveryKey reply:(nonnull void (^)(SecRecoveryKey *rk, NSError *error))reply
{
#if OCTAGON
    secnotice("octagon-setrecoverykey", "setNewRecoveryKeyWithData invoked for context: %@", ctx.context);
    //set the recovery key for SOS
    NSError* createRecoveryKeyError = nil;
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    NSError* retError = nil;
    OctagonSignpost signPost = OctagonSignpostBegin(OctagonSignpostNameSetNewRecoveryKeyWithData);
    __block bool subTaskSuccess = false;

    SecRecoveryKey *rk = SecRKCreateRecoveryKeyWithError(recoveryKey, &createRecoveryKeyError);
    if (rk == nil) {
        secerror("octagon-setrecoverykey, SecRKCreateRecoveryKeyWithError() failed: %@", createRecoveryKeyError);
        userInfo[NSLocalizedDescriptionKey] = @"SecRKCreateRecoveryKeyWithError() failed";
        userInfo[NSUnderlyingErrorKey] = createRecoveryKeyError;
        if ([OTClique isCloudServicesAvailable] == NO) {
            retError = [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecUnimplemented userInfo:userInfo];
        } else {
            retError = [NSError errorWithDomain:getkSecureBackupErrorDomain() code:kSecureBackupInternalError userInfo:userInfo];
        }
        OctagonSignpostEnd(signPost, OctagonSignpostNameSetNewRecoveryKeyWithData, OctagonSignpostNumber1(OctagonSignpostNameSetNewRecoveryKeyWithData), (int)subTaskSuccess);
        reply(nil, retError);
        return;
    }
    if([OTClique platformSupportsSOS]) {
        CFErrorRef registerError = nil;
        if (!SecRKRegisterBackupPublicKey(rk, &registerError)) {
            secerror("octagon-setrecoverykey, SecRKRegisterBackupPublicKey() failed: %@", registerError);
            NSError *underlyingError = CFBridgingRelease(registerError);
            userInfo[NSLocalizedDescriptionKey] = @"SecRKRegisterBackupPublicKey() failed";
            userInfo[NSUnderlyingErrorKey] = underlyingError;
            if ([OTClique isCloudServicesAvailable] == NO) {
                retError = [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecUnimplemented userInfo:userInfo];
            } else {
                retError = [NSError errorWithDomain:getkSecureBackupErrorDomain() code:kSecureBackupInternalError userInfo:userInfo];
            }
            OctagonSignpostEnd(signPost, OctagonSignpostNameSetNewRecoveryKeyWithData, OctagonSignpostNumber1(OctagonSignpostNameSetNewRecoveryKeyWithData), (int)subTaskSuccess);
            reply(nil,retError);
            return;
        } else {
            secnotice("octagon-setrecoverykey", "successfully registered recovery key for SOS");
        }
    }

    //set the recovery key for Octagon
    NSError* controlError = nil;
    OTControl* control = [ctx makeOTControl:&controlError];
    if(!control) {
        secnotice("octagon-setrecoverykey", "failed to fetch OTControl object: %@", controlError);
        OctagonSignpostEnd(signPost, OctagonSignpostNameSetNewRecoveryKeyWithData, OctagonSignpostNumber1(OctagonSignpostNameSetNewRecoveryKeyWithData), (int)subTaskSuccess);
        reply(nil, controlError);
        return;
    }
    [control createRecoveryKey:[[OTControlArguments alloc] initWithConfiguration:ctx] recoveryKey:recoveryKey reply:^(NSError * createError) {
        if(createError){
            secerror("octagon-setrecoverykey, failed to create octagon recovery key");
            OctagonSignpostEnd(signPost, OctagonSignpostNameSetNewRecoveryKeyWithData, OctagonSignpostNumber1(OctagonSignpostNameSetNewRecoveryKeyWithData), (int)subTaskSuccess);
            reply(nil, createError);
            return;
        } else {
            secnotice("octagon-setrecoverykey", "successfully set octagon recovery key");
            subTaskSuccess = true;
            OctagonSignpostEnd(signPost, OctagonSignpostNameSetNewRecoveryKeyWithData, OctagonSignpostNumber1(OctagonSignpostNameSetNewRecoveryKeyWithData), (int)subTaskSuccess);
            reply(rk, nil);
            return;
        }
    }];
#else // !OCTAGON
    reply(nil, [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecUnimplemented userInfo:nil]);
#endif
}

+ (void)recoverOctagonUsingData:(OTConfigurationContext*)ctx
                    recoveryKey:(NSString*)recoveryKey
                          reply:(void(^)(NSError* _Nullable error))reply
{
    [self recoverOctagonUsingData:ctx recoveryKey:recoveryKey sosSuccess:YES reply:reply];
}

+ (void)recoverOctagonUsingData:(OTConfigurationContext*)ctx
                    recoveryKey:(NSString*)recoveryKey
                     sosSuccess:(BOOL)sosSuccess
                          reply:(void(^)(NSError* _Nullable error))reply
{
#if OCTAGON
    OctagonSignpost signpost = OctagonSignpostBegin(OctagonSignpostNameRecoverOctagonUsingData);
    __block bool subTaskSuccess = false;

    NSError* controlError = nil;
    OTControl* control = [ctx makeOTControl:&controlError];

    secnotice("clique-recoverykey", "join using recovery key");

    if(!control) {
        secnotice("clique-recoverykey", "failed to fetch OTControl object: %@", controlError);
        OctagonSignpostEnd(signpost, OctagonSignpostNameRecoverOctagonUsingData, OctagonSignpostNumber1(OctagonSignpostNameRecoverOctagonUsingData), (int)subTaskSuccess);
        reply(controlError);
        return;
    }
    [control joinWithRecoveryKey:[[OTControlArguments alloc] initWithConfiguration:ctx] recoveryKey:recoveryKey sosSuccess:sosSuccess reply:^(NSError *joinError) {
        if(joinError){
            secnotice("clique-recoverykey", "failed to join using recovery key: %@", joinError);
            OctagonSignpostEnd(signpost, OctagonSignpostNameRecoverOctagonUsingData, OctagonSignpostNumber1(OctagonSignpostNameRecoverOctagonUsingData), (int)subTaskSuccess);
            reply(joinError);
            return;
        }
        secnotice("clique-recoverykey", "successfully joined using recovery key");
        subTaskSuccess = true;
        OctagonSignpostEnd(signpost, OctagonSignpostNameRecoverOctagonUsingData, OctagonSignpostNumber1(OctagonSignpostNameRecoverOctagonUsingData), (int)subTaskSuccess);
        reply(nil);
    }];
#else // !OCTAGON
    reply([NSError errorWithDomain:NSOSStatusErrorDomain code:errSecUnimplemented userInfo:nil]);
#endif
}

+ (void)createCustodianRecoveryKey:(OTConfigurationContext*)ctx
                              uuid:(NSUUID *_Nullable)uuid
                             reply:(void (^)(OTCustodianRecoveryKey *_Nullable crk, NSError *_Nullable error))reply
{
#if OCTAGON
    secnotice("octagon-createcustodianrecoverykey", "createCustodianRecoveryKey invoked for context: %@", ctx.context);
    OctagonSignpost signPost = OctagonSignpostBegin(OctagonSignpostNameCreateCustodianRecoveryKey);
    __block bool subTaskSuccess = false;

    //set the recovery key for Octagon
    NSError* controlError = nil;
    OTControl* control = [ctx makeOTControl:&controlError];
    if(!control) {
        secnotice("octagon-createcustodianrecoverykey", "failed to fetch OTControl object: %@", controlError);
        OctagonSignpostEnd(signPost, OctagonSignpostNameCreateCustodianRecoveryKey, OctagonSignpostNumber1(OctagonSignpostNameCreateCustodianRecoveryKey), (int)subTaskSuccess);
        reply(nil, controlError);
        return;
    }
    [control createCustodianRecoveryKey:[[OTControlArguments alloc] initWithConfiguration:ctx] uuid:uuid reply:^(OTCustodianRecoveryKey *_Nullable crk, NSError *_Nullable error) {
            if(error) {
                secerror("octagon-createcustodianrecoverykey, failed to create octagon custodian recovery key");
                OctagonSignpostEnd(signPost, OctagonSignpostNameCreateCustodianRecoveryKey, OctagonSignpostNumber1(OctagonSignpostNameCreateCustodianRecoveryKey), (int)subTaskSuccess);
                reply(nil, error);
                return;
            } else {
                secnotice("octagon-createcustodianrecoverykey", "successfully created octagon custodian recovery key");
                subTaskSuccess = true;
                OctagonSignpostEnd(signPost, OctagonSignpostNameCreateCustodianRecoveryKey, OctagonSignpostNumber1(OctagonSignpostNameCreateCustodianRecoveryKey), (int)subTaskSuccess);
                reply(crk, nil);
                return;
            }
        }];
#else // !OCTAGON
    reply(nil, [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecUnimplemented userInfo:nil]);
#endif
}

+ (void)recoverOctagonUsingCustodianRecoveryKey:(OTConfigurationContext*)ctx
                           custodianRecoveryKey:(OTCustodianRecoveryKey *)crk
                                          reply:(void(^)(NSError* _Nullable error)) reply
{
#if OCTAGON
    OctagonSignpost signpost = OctagonSignpostBegin(OctagonSignpostNameRecoverOctagonUsingCustodianRecoveryKey);
    __block bool subTaskSuccess = false;

    NSError* controlError = nil;
    OTControl* control = [ctx makeOTControl:&controlError];

    secnotice("clique-custodianrecoverykey", "join using custodian recovery key");

    if(!control) {
        secnotice("clique-custodianrecoverykey", "failed to fetch OTControl object: %@", controlError);
        OctagonSignpostEnd(signpost, OctagonSignpostNameRecoverOctagonUsingCustodianRecoveryKey, OctagonSignpostNumber1(OctagonSignpostNameRecoverOctagonUsingCustodianRecoveryKey), (int)subTaskSuccess);
        reply(controlError);
        return;
    }
    [control joinWithCustodianRecoveryKey:[[OTControlArguments alloc] initWithConfiguration:ctx] custodianRecoveryKey:crk reply:^(NSError *joinError) {
        if(joinError){
            secnotice("clique-custodianrecoverykey", "failed to join using custodian recovery key: %@", joinError);
            OctagonSignpostEnd(signpost, OctagonSignpostNameRecoverOctagonUsingCustodianRecoveryKey, OctagonSignpostNumber1(OctagonSignpostNameRecoverOctagonUsingCustodianRecoveryKey), (int)subTaskSuccess);
            reply(joinError);
            return;
        }
        secnotice("clique-custodianrecoverykey", "successfully joined using custodian recovery key");
        subTaskSuccess = true;
        OctagonSignpostEnd(signpost, OctagonSignpostNameRecoverOctagonUsingCustodianRecoveryKey, OctagonSignpostNumber1(OctagonSignpostNameRecoverOctagonUsingCustodianRecoveryKey), (int)subTaskSuccess);
        reply(nil);
    }];

#else
    reply([NSError errorWithDomain:NSOSStatusErrorDomain code:errSecUnimplemented userInfo:nil]);
#endif
}

+ (void)preflightRecoverOctagonUsingCustodianRecoveryKey:(OTConfigurationContext*)ctx
                                    custodianRecoveryKey:(OTCustodianRecoveryKey *)crk
                                                   reply:(void(^)(NSError* _Nullable error)) reply
{
#if OCTAGON
    OctagonSignpost signpost = OctagonSignpostBegin(OctagonSignpostNamePreflightRecoverOctagonUsingCustodianRecoveryKey);
    __block bool subTaskSuccess = false;

    NSError* controlError = nil;
    OTControl* control = [ctx makeOTControl:&controlError];

    secnotice("clique-custodianrecoverykey", "preflight join using custodian recovery key");

    if(!control) {
        secnotice("clique-custodianrecoverykey", "failed to fetch OTControl object: %@", controlError);
        OctagonSignpostEnd(signpost, OctagonSignpostNamePreflightRecoverOctagonUsingCustodianRecoveryKey, OctagonSignpostNumber1(OctagonSignpostNamePreflightRecoverOctagonUsingCustodianRecoveryKey), (int)subTaskSuccess);
        reply(controlError);
        return;
    }
    [control preflightJoinWithCustodianRecoveryKey:[[OTControlArguments alloc] initWithConfiguration:ctx] custodianRecoveryKey:crk reply:^(NSError *joinError) {
        if(joinError){
            secnotice("clique-custodianrecoverykey", "failed to preflight join using custodian recovery key: %@", joinError);
            OctagonSignpostEnd(signpost, OctagonSignpostNamePreflightRecoverOctagonUsingCustodianRecoveryKey, OctagonSignpostNumber1(OctagonSignpostNamePreflightRecoverOctagonUsingCustodianRecoveryKey), (int)subTaskSuccess);
            reply(joinError);
            return;
        }
        secnotice("clique-custodianrecoverykey", "successful preflight join using custodian recovery key");
        subTaskSuccess = true;
        OctagonSignpostEnd(signpost, OctagonSignpostNamePreflightRecoverOctagonUsingCustodianRecoveryKey, OctagonSignpostNumber1(OctagonSignpostNamePreflightRecoverOctagonUsingCustodianRecoveryKey), (int)subTaskSuccess);
        reply(nil);
    }];

#else
    reply([NSError errorWithDomain:NSOSStatusErrorDomain code:errSecUnimplemented userInfo:nil]);
#endif
}

// Remove a custodian recovery key.
+ (void)removeCustodianRecoveryKey:(OTConfigurationContext*)ctx
          custodianRecoveryKeyUUID:(NSUUID *)uuid
                             reply:(void (^)(NSError *_Nullable error))reply
{
#if OCTAGON
    secnotice("octagon-removecustodianrecoverykey", "removeCustodianRecoveryKey invoked for context: %@", ctx.context);
    OctagonSignpost signPost = OctagonSignpostBegin(OctagonSignpostNameRemoveCustodianRecoveryKey);
    __block bool subTaskSuccess = false;

    NSError* controlError = nil;
    OTControl* control = [ctx makeOTControl:&controlError];
    if(!control) {
        secnotice("octagon-removecustodianrecoverykey", "failed to fetch OTControl object: %@", controlError);
        OctagonSignpostEnd(signPost, OctagonSignpostNameRemoveCustodianRecoveryKey, OctagonSignpostNumber1(OctagonSignpostNameRemoveCustodianRecoveryKey), (int)subTaskSuccess);
        reply(controlError);
        return;
    }
    [control removeCustodianRecoveryKey:[[OTControlArguments alloc] initWithConfiguration:ctx] uuid:uuid reply:^(NSError *_Nullable error) {
            if(error) {
                secerror("octagon-removecustodianrecoverykey, failed to create remove custodian recovery key");
                OctagonSignpostEnd(signPost, OctagonSignpostNameRemoveCustodianRecoveryKey, OctagonSignpostNumber1(OctagonSignpostNameRemoveCustodianRecoveryKey), (int)subTaskSuccess);
                reply(error);
                return;
            } else {
                secnotice("octagon-removecustodianrecoverykey", "successfully removed custodian recovery key");
                subTaskSuccess = true;
                OctagonSignpostEnd(signPost, OctagonSignpostNameRemoveCustodianRecoveryKey, OctagonSignpostNumber1(OctagonSignpostNameRemoveCustodianRecoveryKey), (int)subTaskSuccess);
                reply(nil);
                return;
            }
        }];
    
#else
    reply([NSError errorWithDomain:NSOSStatusErrorDomain code:errSecUnimplemented userInfo:nil]);
#endif
}

+ (void)createInheritanceKey:(OTConfigurationContext*)ctx
                        uuid:(NSUUID *_Nullable)uuid
                       reply:(void (^)(OTInheritanceKey *_Nullable ik, NSError *_Nullable error)) reply
{
#if OCTAGON
    secnotice("octagon-createinheritancekey", "createInheritanceKey invoked for context: %@", ctx.context);
    OctagonSignpost signPost = OctagonSignpostBegin(OctagonSignpostNameCreateInheritanceKey);
    __block bool subTaskSuccess = false;

    NSError* controlError = nil;
    OTControl* control = [ctx makeOTControl:&controlError];
    if(!control) {
        secnotice("octagon-createinheritancekey", "failed to fetch OTControl object: %@", controlError);
        OctagonSignpostEnd(signPost, OctagonSignpostNameCreateInheritanceKey, OctagonSignpostNumber1(OctagonSignpostNameCreateInheritanceKey), (int)subTaskSuccess);
        reply(nil, controlError);
        return;
    }
    [control createInheritanceKey:[[OTControlArguments alloc] initWithConfiguration:ctx] uuid:uuid reply:^(OTInheritanceKey *_Nullable ik, NSError *_Nullable error) {
            if(error) {
                secerror("octagon-createinheritancekey, failed to create octagon inheritance recovery key");
                OctagonSignpostEnd(signPost, OctagonSignpostNameCreateInheritanceKey, OctagonSignpostNumber1(OctagonSignpostNameCreateInheritanceKey), (int)subTaskSuccess);
                reply(nil, error);
                return;
            } else {
                secnotice("octagon-createinheritancekey", "successfully created octagon inheritance recovery key");
                subTaskSuccess = true;
                OctagonSignpostEnd(signPost, OctagonSignpostNameCreateInheritanceKey, OctagonSignpostNumber1(OctagonSignpostNameCreateInheritanceKey), (int)subTaskSuccess);
                reply(ik, nil);
                return;
            }
        }];
#else // !OCTAGON
    reply(nil, [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecUnimplemented userInfo:nil]);
#endif
}

+ (void)generateInheritanceKey:(OTConfigurationContext*)ctx
                        uuid:(NSUUID *_Nullable)uuid
                       reply:(void (^)(OTInheritanceKey *_Nullable ik, NSError *_Nullable error)) reply
{
#if OCTAGON
    secnotice("octagon-generateinheritancekey", "generateInheritanceKey invoked for context: %@", ctx.context);
    OctagonSignpost signPost = OctagonSignpostBegin(OctagonSignpostNameGenerateInheritanceKey);
    __block bool subTaskSuccess = false;

    NSError* controlError = nil;
    OTControl* control = [ctx makeOTControl:&controlError];
    if(!control) {
        secnotice("octagon-generateinheritancekey", "failed to fetch OTControl object: %@", controlError);
        OctagonSignpostEnd(signPost, OctagonSignpostNameGenerateInheritanceKey, OctagonSignpostNumber1(OctagonSignpostNameGenerateInheritanceKey), (int)subTaskSuccess);
        reply(nil, controlError);
        return;
    }
    [control generateInheritanceKey:[[OTControlArguments alloc] initWithConfiguration:ctx] uuid:uuid reply:^(OTInheritanceKey *_Nullable ik, NSError *_Nullable error) {
            if(error) {
                secerror("octagon-generateinheritancekey, failed to generate octagon inheritance recovery key");
                OctagonSignpostEnd(signPost, OctagonSignpostNameGenerateInheritanceKey, OctagonSignpostNumber1(OctagonSignpostNameGenerateInheritanceKey), (int)subTaskSuccess);
                reply(nil, error);
                return;
            } else {
                secnotice("octagon-generateinheritancekey", "successfully generated octagon inheritance recovery key");
                subTaskSuccess = true;
                OctagonSignpostEnd(signPost, OctagonSignpostNameGenerateInheritanceKey, OctagonSignpostNumber1(OctagonSignpostNameGenerateInheritanceKey), (int)subTaskSuccess);
                reply(ik, nil);
                return;
            }
        }];
#else // !OCTAGON
    reply(nil, [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecUnimplemented userInfo:nil]);
#endif
}

+ (void)storeInheritanceKey:(OTConfigurationContext*)ctx
                         ik:(OTInheritanceKey*)ik
                      reply:(void (^)(NSError *_Nullable error)) reply
{
#if OCTAGON
    secnotice("octagon-storeinheritancekey", "storeInheritanceKey invoked for context: %@", ctx.context);
    OctagonSignpost signPost = OctagonSignpostBegin(OctagonSignpostNameStoreInheritanceKey);
    __block bool subTaskSuccess = false;

    NSError* controlError = nil;
    OTControl* control = [ctx makeOTControl:&controlError];
    if(!control) {
        secnotice("octagon-storeinheritancekey", "failed to fetch OTControl object: %@", controlError);
        OctagonSignpostEnd(signPost, OctagonSignpostNameStoreInheritanceKey, OctagonSignpostNumber1(OctagonSignpostNameStoreInheritanceKey), (int)subTaskSuccess);
        reply(controlError);
        return;
    }
    [control storeInheritanceKey:[[OTControlArguments alloc] initWithConfiguration:ctx] ik:ik reply:^(NSError *_Nullable error) {
            if(error) {
                secerror("octagon-storeinheritancekey, failed to store octagon inheritance recovery key");
                OctagonSignpostEnd(signPost, OctagonSignpostNameStoreInheritanceKey, OctagonSignpostNumber1(OctagonSignpostNameStoreInheritanceKey), (int)subTaskSuccess);
                reply(error);
                return;
            } else {
                secnotice("octagon-storeinheritancekey", "successfully stored octagon inheritance recovery key");
                subTaskSuccess = true;
                OctagonSignpostEnd(signPost, OctagonSignpostNameStoreInheritanceKey, OctagonSignpostNumber1(OctagonSignpostNameStoreInheritanceKey), (int)subTaskSuccess);
                reply(nil);
                return;
            }
        }];
#else // !OCTAGON
    reply([NSError errorWithDomain:NSOSStatusErrorDomain code:errSecUnimplemented userInfo:nil]);
#endif
}

// Join using an inheritance key.
+ (void)recoverOctagonUsingInheritanceKey:(OTConfigurationContext*)ctx
                           inheritanceKey:(OTInheritanceKey *)ik
                                    reply:(void(^)(NSError* _Nullable error)) reply
{
#if OCTAGON
    OctagonSignpost signpost = OctagonSignpostBegin(OctagonSignpostNameRecoverOctagonUsingInheritanceKey);
    __block bool subTaskSuccess = false;

    NSError* controlError = nil;
    OTControl* control = [ctx makeOTControl:&controlError];

    secnotice("clique-inheritancekey", "join using inheritance key");

    if(!control) {
        secnotice("clique-inheritancekey", "failed to fetch OTControl object: %@", controlError);
        OctagonSignpostEnd(signpost, OctagonSignpostNameRecoverOctagonUsingInheritanceKey, OctagonSignpostNumber1(OctagonSignpostNameRecoverOctagonUsingInheritanceKey), (int)subTaskSuccess);
        reply(controlError);
        return;
    }
    [control joinWithInheritanceKey:[[OTControlArguments alloc] initWithConfiguration:ctx] inheritanceKey:ik reply:^(NSError *joinError) {
        if(joinError){
            secnotice("clique-inheritancekey", "failed to join using inheritance key: %@", joinError);
            OctagonSignpostEnd(signpost, OctagonSignpostNameRecoverOctagonUsingInheritanceKey, OctagonSignpostNumber1(OctagonSignpostNameRecoverOctagonUsingInheritanceKey), (int)subTaskSuccess);
            reply(joinError);
            return;
        }
        secnotice("clique-inheritancekey", "successfully joined using inheritance key");
        subTaskSuccess = true;
        OctagonSignpostEnd(signpost, OctagonSignpostNameRecoverOctagonUsingInheritanceKey, OctagonSignpostNumber1(OctagonSignpostNameRecoverOctagonUsingInheritanceKey), (int)subTaskSuccess);
        reply(nil);
    }];

#else
    reply([NSError errorWithDomain:NSOSStatusErrorDomain code:errSecUnimplemented userInfo:nil]);
#endif
}

// Preflight join using an inheritance key.
+ (void)preflightRecoverOctagonUsingInheritanceKey:(OTConfigurationContext*)ctx
                                    inheritanceKey:(OTInheritanceKey *)ik
                                             reply:(void(^)(NSError* _Nullable error)) reply
{
#if OCTAGON
    OctagonSignpost signpost = OctagonSignpostBegin(OctagonSignpostNamePreflightRecoverOctagonUsingInheritanceKey);
    __block bool subTaskSuccess = false;

    NSError* controlError = nil;
    OTControl* control = [ctx makeOTControl:&controlError];

    secnotice("clique-inheritancekey", "preflight join using inheritance key");

    if(!control) {
        secnotice("clique-inheritancekey", "failed to fetch OTControl object: %@", controlError);
        OctagonSignpostEnd(signpost, OctagonSignpostNamePreflightRecoverOctagonUsingInheritanceKey, OctagonSignpostNumber1(OctagonSignpostNamePreflightRecoverOctagonUsingInheritanceKey), (int)subTaskSuccess);
        reply(controlError);
        return;
    }
    [control preflightJoinWithInheritanceKey:[[OTControlArguments alloc] initWithConfiguration:ctx] inheritanceKey:ik reply:^(NSError *joinError) {
        if(joinError){
            secnotice("clique-inheritancekey", "failed to preflight join using inheritance key: %@", joinError);
            OctagonSignpostEnd(signpost, OctagonSignpostNamePreflightRecoverOctagonUsingInheritanceKey, OctagonSignpostNumber1(OctagonSignpostNamePreflightRecoverOctagonUsingInheritanceKey), (int)subTaskSuccess);
            reply(joinError);
            return;
        }
        secnotice("clique-inheritancekey", "successful preflight join using inheritance key");
        subTaskSuccess = true;
        OctagonSignpostEnd(signpost, OctagonSignpostNamePreflightRecoverOctagonUsingInheritanceKey, OctagonSignpostNumber1(OctagonSignpostNamePreflightRecoverOctagonUsingInheritanceKey), (int)subTaskSuccess);
        reply(nil);
    }];

#else
    reply([NSError errorWithDomain:NSOSStatusErrorDomain code:errSecUnimplemented userInfo:nil]);
#endif
}

// Remove an inheritance key.
+ (void)removeInheritanceKey:(OTConfigurationContext*)ctx
          inheritanceKeyUUID:(NSUUID *)uuid
                       reply:(void (^)(NSError *_Nullable error))reply
{
#if OCTAGON
    secnotice("octagon-removeinheritancekey", "removeInheritanceKey invoked for context: %@", ctx.context);
    OctagonSignpost signPost = OctagonSignpostBegin(OctagonSignpostNameRemoveInheritanceKey);
    __block bool subTaskSuccess = false;

    NSError* controlError = nil;
    OTControl* control = [ctx makeOTControl:&controlError];
    if(!control) {
        secnotice("octagon-removeinheritancekey", "failed to fetch OTControl object: %@", controlError);
        OctagonSignpostEnd(signPost, OctagonSignpostNameRemoveInheritanceKey, OctagonSignpostNumber1(OctagonSignpostNameRemoveInheritanceKey), (int)subTaskSuccess);
        reply(controlError);
        return;
    }
    [control removeInheritanceKey:[[OTControlArguments alloc] initWithConfiguration:ctx] uuid:uuid reply:^(NSError *_Nullable error) {
            if(error) {
                secerror("octagon-removeinheritancekey, failed to create remove inheritance key");
                OctagonSignpostEnd(signPost, OctagonSignpostNameRemoveInheritanceKey, OctagonSignpostNumber1(OctagonSignpostNameRemoveInheritanceKey), (int)subTaskSuccess);
                reply(error);
                return;
            } else {
                secnotice("octagon-removeinheritancekey", "successfully removed inerhitance key");
                subTaskSuccess = true;
                OctagonSignpostEnd(signPost, OctagonSignpostNameRemoveInheritanceKey, OctagonSignpostNumber1(OctagonSignpostNameRemoveInheritanceKey), (int)subTaskSuccess);
                reply(nil);
                return;
            }
        }];
    
#else
    reply([NSError errorWithDomain:NSOSStatusErrorDomain code:errSecUnimplemented userInfo:nil]);
#endif
}


- (void)performedCDPStateMachineRun:(OTCliqueCDPContextType)type
                            success:(BOOL)success
                              error:(NSError * _Nullable)error
                              reply:(void(^)(NSError* _Nullable error))reply
{
#if OCTAGON
    OctagonSignpost signPost = OctagonSignpostBegin(OctagonSignpostNamePerformedCDPStateMachineRun);
    NSError* controlError = nil;
    __block bool subTaskSuccess = false;

    OTControl* control = [self makeOTControl:&controlError];
    if(!control) {
        secnotice("clique-cdp-sm", "octagon, failed to fetch OTControl object: %@", controlError);
        OctagonSignpostEnd(signPost, OctagonSignpostNamePerformedCDPStateMachineRun, OctagonSignpostNumber1(OctagonSignpostNamePerformedCDPStateMachineRun), (int)subTaskSuccess);
        reply(controlError);
        return;
    }

    [control postCDPFollowupResult:[[OTControlArguments alloc] initWithConfiguration:self.ctx] success:success type:type error:error reply:^(NSError *postError) {
        if(postError){
            secnotice("clique-cdp-sm", "failed to post %@ result: %@ ", type, postError);
            OctagonSignpostEnd(signPost, OctagonSignpostNamePerformedCDPStateMachineRun, OctagonSignpostNumber1(OctagonSignpostNamePerformedCDPStateMachineRun), (int)subTaskSuccess);
            reply(postError);
            return;
        }
        if (success) {
            secnotice("clique-cdp-sm", "posted success: %@", type);
        } else {
            secnotice("clique-cdp-sm", "posted error: %@:  %@", type, error);
        }
        subTaskSuccess = success ? true : false;
        OctagonSignpostEnd(signPost, OctagonSignpostNamePerformedCDPStateMachineRun, OctagonSignpostNumber1(OctagonSignpostNamePerformedCDPStateMachineRun), (int)subTaskSuccess);
        reply(nil);
    }];
#else // !OCTAGON
    reply([NSError errorWithDomain:NSOSStatusErrorDomain code:errSecUnimplemented userInfo:nil]);
#endif
}

- (BOOL)waitForOctagonUpgrade:(NSError** _Nullable)error
{
#if OCTAGON
    OTControl* control = nil;
    OctagonSignpost signPost = OctagonSignpostBegin(OctagonSignpostNameWaitForOctagonUpgrade);
    __block bool subTaskSuccess = false;

    NSError *controlError = nil;
    control = [self makeOTControl:&controlError];
    if (!control) {
        secnotice("clique-waitforoctagonupgrade", "octagon, failed to fetch OTControl object: %@", controlError);
        if (error) {
            *error = controlError;
        }
        OctagonSignpostEnd(signPost, OctagonSignpostNameWaitForOctagonUpgrade, OctagonSignpostNumber1(OctagonSignpostNameWaitForOctagonUpgrade), (int)subTaskSuccess);
        return NO;
    }

    __block BOOL ret = NO;
    __block NSError* blockError = nil;

    [control waitForOctagonUpgrade:[[OTControlArguments alloc] initWithConfiguration:self.ctx] reply:^(NSError *postError) {
        if(postError){
            secnotice("clique-waitforoctagonupgrade", "error from control: %@", postError);
            blockError = postError;
            ret = NO;
        } else {
            secnotice("clique-waitforoctagonupgrade", "successfully upgraded to octagon");
            ret = YES;
        }
    }];

    if (blockError && error) {
        *error = blockError;
    }
    subTaskSuccess = ret ? true : false;
    OctagonSignpostEnd(signPost, OctagonSignpostNameWaitForOctagonUpgrade, OctagonSignpostNumber1(OctagonSignpostNameWaitForOctagonUpgrade), (int)subTaskSuccess);
    return ret;
#else // !OCTAGON
    if(error) {
        *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecUnimplemented userInfo:nil];
    }
    return NO;
#endif
}

- (void)performedFailureCDPStateMachineRun:(OTCliqueCDPContextType)type
                                     error:(NSError * _Nullable)error
                                     reply:(void(^)(NSError* _Nullable error))reply
{
    [self performedCDPStateMachineRun:type success:NO error:error reply:reply];
}

- (void)performedSuccessfulCDPStateMachineRun:(OTCliqueCDPContextType)type
                                        reply:(void(^)(NSError* _Nullable error))reply
{
    [self performedCDPStateMachineRun:type success:YES error:nil reply:reply];
}

+ (BOOL)setCDPEnabled:(OTConfigurationContext*)arguments
                error:(NSError* __autoreleasing*)error
{
#if OCTAGON
    NSError *controlError = nil;
    OTControl* control = [arguments makeOTControl:&controlError];
    if (!control) {
        secerror("octagon-setcdpenabled: failed to fetch OTControl object: %@", controlError);
        if (error) {
            *error = controlError;
        }
        return NO;
    }

    __block NSError* reterror = nil;

    [control setCDPEnabled:[[OTControlArguments alloc] initWithConfiguration:arguments]
                     reply:^(NSError * _Nullable resultError) {
        if(resultError) {
            secnotice("octagon-setcdpenabled", "failed to set CDP bit: %@", resultError);
            reterror = resultError;
        } else {
            secnotice("octagon-setcdpenabled", "successfully set CDP bit");
        }
    }];

    if(reterror && error) {
        *error = reterror;
    }

    return (reterror == nil);
#else // !OCTAGON
    if(error) {
        *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecUnimplemented userInfo:nil];
    }
    return NO;
#endif
}

+ (OTCDPStatus)getCDPStatus:(OTConfigurationContext*)arguments
                      error:(NSError* __autoreleasing *)error
{
#if OCTAGON
    NSError *controlError = nil;
    OTControl* control = [arguments makeOTControl:&controlError];
    if (!control) {
        secerror("octagon-cdp-status: failed to fetch OTControl object: %@", controlError);
        if (error) {
            *error = controlError;
        }
        return OTCDPStatusUnknown;
    }

    __block NSError* reterror = nil;
    __block OTCDPStatus retcdpstatus = OTCDPStatusUnknown;

    [control getCDPStatus:[[OTControlArguments alloc] initWithConfiguration:arguments]
                    reply:^(OTCDPStatus status, NSError * _Nullable resultError) {
        if(resultError) {
            secnotice("octagon-cdp-status", "failed to fetch CDP status: %@", resultError);
            reterror = resultError;

        } else {
            secnotice("octagon-cdp-status", "successfully fetched CDP status as %@", OTCDPStatusToString(status));
            retcdpstatus = status;
        }
    }];

    if(reterror && error) {
       *error = reterror;
    }

    return retcdpstatus;
#else // !OCTAGON
    if(error) {
        *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecUnimplemented userInfo:nil];
    }
    return OTCDPStatusDisabled;
#endif
}

+ (OTClique* _Nullable)resetProtectedData:(OTConfigurationContext*)data error:(NSError**)error
{
#if OCTAGON
    if ([OTClique isCloudServicesAvailable] == NO) {
        if (error) {
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecUnimplemented userInfo:nil];
        }
        return nil;
    }
    NSError *controlError = nil;
    OTControl *control = [data makeOTControl:&controlError];
    if (!control) {
        secerror("clique-reset-protected-data: unable to create otcontrol: %@", controlError);
        if (error) {
            *error = controlError;
        }
        return nil;
    }

    __block NSError* localError = nil;
    
    //delete all records
    id<OctagonEscrowRecovererPrococol> sb = data.sbd ?: [[getSecureBackupClass() alloc] init];

    if (!data.authenticationAppleID) {
        secerror("clique-reset-protected-data: authenticationAppleID not set on configuration context");
        return nil;
    }
    if (!data.passwordEquivalentToken) {
        secerror("clique-reset-protected-data: passwordEquivalentToken not set on configuration context");
        return nil;
    }
    
    NSDictionary* deletionInformation = @{ getkSecureBackupAuthenticationAppleID() : data.authenticationAppleID,
                                           getkSecureBackupAuthenticationPassword() : data.passwordEquivalentToken,
                                           getkSecureBackupiCloudDataProtectionDeleteAllRecordsKey() : @YES,
                                           getkSecureBackupContainsiCDPDataKey() : @YES};

    NSError* sbError = [sb disableWithInfo:deletionInformation];
    if(sbError) {
        secerror("clique-reset-protected-data: secure backup escrow record deletion failed: %@", sbError);
        if(error) {
            *error = sbError;
        }
        return nil;
    } else {
        secnotice("clique-reset-protected-data", "sbd disableWithInfo succeeded");
    }

    //reset sos
    if(OctagonPlatformSupportsSOS()) {
        //reset SOS
        CFErrorRef sosError = NULL;
        bool resetSuccess = SOSCCResetToOffering(&sosError);

        if(sosError || !resetSuccess) {
            secerror("clique-reset-protected-data: sos reset failed: %@", sosError);
            if(error) {
                *error = (NSError*)CFBridgingRelease(sosError);
            }
            return nil;
        } else {
            secnotice("clique-reset-protected-data", "sos reset succeeded");
        }
    } else {
        secnotice("clique-reset-protected-data", "platform does not support sos");
    }

    //reset octagon
    OTClique* clique = [[OTClique alloc] initWithContextData:data];
    [clique resetAndEstablish:CuttlefishResetReasonUserInitiatedReset error:&localError];

    if(localError) {
        secerror("clique-reset-protected-data: account reset failed: %@", localError);
        if(error) {
            *error = localError;
        }
        return nil;
    } else {
        secnotice("clique-reset-protected-data", "Octagon account reset succeeded");
        // sending a notification so transparencyd can fix up opted-in accounts
        [[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"com.apple.security.resetprotecteddata.complete"
                                                                       object:nil
                                                                     userInfo:nil
                                                           deliverImmediately:YES];
    }
    
    return clique;
#else // !OCTAGON
    if(error) {
        *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecUnimplemented userInfo:nil];
    }
    return nil;
#endif

}

@end

#endif /* OBJC2 */
