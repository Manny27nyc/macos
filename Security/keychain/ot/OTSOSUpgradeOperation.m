
#if OCTAGON

#import <TargetConditionals.h>
#import <CloudKit/CloudKit_Private.h>
#import <Security/SecKey.h>
#import <Security/SecKeyPriv.h>
#import "keychain/categories/NSError+UsefulConstructors.h"

#include "keychain/SecureObjectSync/SOSAccount.h"
#import "keychain/escrowrequest/Framework/SecEscrowRequest.h"
#import "keychain/ot/ErrorUtils.h"
#import "keychain/ot/OTCuttlefishAccountStateHolder.h"
#import "keychain/ot/OTFetchViewsOperation.h"
#import "keychain/ot/OTOperationDependencies.h"
#import "keychain/ot/OTSOSUpgradeOperation.h"
#import "keychain/ot/OTUpdateTrustedDeviceListOperation.h"
#import "keychain/ot/ObjCImprovements.h"
#import "keychain/TrustedPeersHelper/TrustedPeersHelperProtocol.h"
#import "keychain/ot/categories/OTAccountMetadataClassC+KeychainSupport.h"
#import "keychain/ot/OTFetchCKKSKeysOperation.h"
#import "keychain/ot/OTAuthKitAdapter.h"
#import "keychain/ckks/CKKSAnalytics.h"
#import "keychain/ckks/CKKSKeychainView.h"
#import "keychain/ckks/CloudKitCategories.h"
#import <AuthKit/AKError.h>
#import <os/feature_private.h>


@interface OTSOSUpgradeOperation ()
@property OTOperationDependencies* deps;
@property OTDeviceInformation* deviceInfo;

@property OctagonState* ckksConflictState;

// Since we're making callback based async calls, use this operation trick to hold off the ending of this operation
@property NSOperation* finishedOp;

@property OTUpdateTrustedDeviceListOperation* updateOp;

@property (nullable) NSArray<NSData*>* peerPreapprovedSPKIs;
@end

@implementation OTSOSUpgradeOperation
@synthesize nextState = _nextState;
@synthesize intendedState = _intendedState;

- (instancetype)initWithDependencies:(OTOperationDependencies*)dependencies
                       intendedState:(OctagonState*)intendedState
                   ckksConflictState:(OctagonState*)ckksConflictState
                          errorState:(OctagonState*)errorState
                          deviceInfo:(OTDeviceInformation*)deviceInfo
                      policyOverride:(TPPolicyVersion* _Nullable)policyOverride
{
    if((self = [super init])) {
        _deps = dependencies;

        _intendedState = intendedState;
        _nextState = errorState;
        _ckksConflictState = ckksConflictState;

        _deviceInfo = deviceInfo;
        _policyOverride = policyOverride;
    }
    return self;
}

- (NSData *)persistentKeyRef:(SecKeyRef)secKey error:(NSError **)error
{
    CFDataRef cfEncryptionKeyPersistRef = NULL;
    OSStatus status;

    status = SecKeyCopyPersistentRef(secKey, &cfEncryptionKeyPersistRef);
    if(status) {
        if (error) {
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        }
    } else if (cfEncryptionKeyPersistRef) {
        if (error) {
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecItemNotFound userInfo:nil];
        }
    }

    return CFBridgingRelease(cfEncryptionKeyPersistRef);
}

- (void)groupStart
{
    WEAKIFY(self);

    if(!self.deps.sosAdapter.sosEnabled) {
        secnotice("octagon-sos", "SOS not enabled on this platform?");
        self.nextState = OctagonStateBecomeUntrusted;
        return;
    }

    secnotice("octagon-sos", "Attempting SOS upgrade");

    NSError* error = nil;
    SOSCCStatus sosCircleStatus = [self.deps.sosAdapter circleStatus:&error];
    if(error || sosCircleStatus == kSOSCCError) {
        secnotice("octagon-sos", "Error fetching circle status: %@", error);
        self.nextState = OctagonStateBecomeUntrusted;
        return;
    }

    // Now that we have some non-error SOS status, write down that we attempted an SOS Upgrade (and make sure the CDP bit is on)
    NSError* persistError = nil;
    BOOL persisted = [self.deps.stateHolder persistAccountChanges:^OTAccountMetadataClassC * _Nonnull(OTAccountMetadataClassC * _Nonnull metadata) {
        metadata.attemptedJoin = OTAccountMetadataClassC_AttemptedAJoinState_ATTEMPTED;
        metadata.cdpState = OTAccountMetadataClassC_CDPState_ENABLED;
        return metadata;
    } error:&persistError];
    if(!persisted || persistError) {
        secerror("octagon: failed to save 'attempted join' state: %@", persistError);
    }

    if(sosCircleStatus != kSOSCCInCircle) {
        secnotice("octagon-sos", "Device is not in SOS circle (state: %@), quitting SOS upgrade", SOSAccountGetSOSCCStatusString(sosCircleStatus));
        self.nextState = OctagonStateBecomeUntrusted;
        return;
    }

    id<CKKSSelfPeer> sosSelf = [self.deps.sosAdapter currentSOSSelf:&error];
    if(!sosSelf || error) {
        secnotice("octagon-sos", "Failed to get the current SOS self: %@", error);
        [self handlePrepareErrors:error nextExpectedState:OctagonStateBecomeUntrusted];
        return;
    }

    // Fetch the persistent references for our signing and encryption keys
    NSData* signingKeyPersistRef = [self persistentKeyRef:sosSelf.signingKey.secKey error:&error];
    if (signingKeyPersistRef == NULL) {
        secnotice("octagon-sos", "Failed to get the persistent ref for our SOS signing key: %@", error);
        [self handlePrepareErrors:error nextExpectedState:OctagonStateBecomeUntrusted];
        return;
    }

    NSData* encryptionKeyPersistRef = [self persistentKeyRef:sosSelf.encryptionKey.secKey error:&error];
    if (encryptionKeyPersistRef == NULL) {
        secnotice("octagon-sos", "Failed to get the persistent ref for our SOS encryption key: %@", error);
        [self handlePrepareErrors:error nextExpectedState:OctagonStateBecomeUntrusted];
        return;
    }

    self.finishedOp = [NSBlockOperation blockOperationWithBlock:^{
        STRONGIFY(self);

        if(self.error) {
            if ([self.error isRetryable]) {
                NSTimeInterval delay = [self.error retryInterval];
                secnotice("octagon-sos", "SOS upgrade error is not fatal: requesting retry in %0.2fs: %@", delay, self.error);
                [self.deps.flagHandler handlePendingFlag:[[OctagonPendingFlag alloc] initWithFlag:OctagonFlagAttemptSOSUpgrade
                                                                                   delayInSeconds:delay]];
            } else {
                secnotice("octagon-sos", "SOS upgrade error is: %@; not retrying", self.error);
            }
        }
    }];
    [self dependOnBeforeGroupFinished:self.finishedOp];

    NSError* accountError = nil;
    OTAccountMetadataClassC* account = [self.deps.stateHolder loadOrCreateAccountMetadata:&accountError];
    if (account == nil) {
        if (accountError == nil) {
            accountError = [NSError errorWithDomain:(__bridge NSString *)kSecErrorDomain code:errSecInternalError userInfo:nil];
        }
        secerror("failed to retrieve account object: %@", accountError);
        self.error = accountError;
        [self runBeforeGroupFinished:self.finishedOp];
        return;
    }

    TPPBSecureElementIdentity* existingSecureElementIdentity = [account parsedSecureElementIdentity];
   
    OTAccountSettings* settings = nil;
    
    if (account.hasSettings) {
        settings = [[OTAccountSettings alloc]init];
        
#if APPLE_FEATURE_WALRUS
        if ([account.settings hasW]) {
            OTWalrus* walrus = [[OTWalrus alloc]init];
            walrus.enabled = account.settings.w ? YES : NO;
            settings.walrus = walrus;
        }
#else
        if ([account.settings hasW]) {
            OTTag1* w = [[OTTag1 alloc]init];
            w.enabled = account.settings.w ? YES : NO;
            settings.tag1 = w;
        }
#endif
#if APPLE_FEATURE_WALRUS_UI
        if ([account.settings hasWebAccess]) {
            OTWebAccess* webAccess = [[OTWebAccess alloc]init];
            webAccess.enabled = account.settings.webAccess ? YES : NO;
            settings.webAccess = webAccess;
        }
#endif
    }
    
    secnotice("octagon-sos", "Fetching trusted peers from SOS");

    NSError* sosPreapprovalError = nil;
    self.peerPreapprovedSPKIs = [OTSOSAdapterHelpers peerPublicSigningKeySPKIsForCircle:self.deps.sosAdapter error:&sosPreapprovalError];

    if(self.peerPreapprovedSPKIs) {
        secnotice("octagon-sos", "SOS preapproved keys are %@", self.peerPreapprovedSPKIs);
    } else {
        secnotice("octagon-sos", "Unable to fetch SOS preapproved keys: %@", sosPreapprovalError);
        self.error = sosPreapprovalError;
        [self runBeforeGroupFinished:self.finishedOp];
        return;
    }

    NSString* altDSID = self.deps.activeAccount.altDSID;
    if(altDSID == nil) {
        secnotice("authkit", "No configured altDSID: %@", self.deps.activeAccount);
        self.error = [NSError errorWithDomain:OctagonErrorDomain
                                         code:OctagonErrorNoAppleAccount
                                  description:@"No altDSID configured"];
        [self runBeforeGroupFinished:self.finishedOp];
        return;
    }

    NSString* bottleSalt = altDSID;

    NSError* sosViewError = nil;
    BOOL safariViewEnabled = [self.deps.sosAdapter safariViewSyncingEnabled:&sosViewError];
    if(sosViewError) {
        secnotice("octagon-sos", "Unable to check safari view status: %@", sosViewError);
    }

    secnotice("octagon-sos", "Safari view is: %@", safariViewEnabled ? @"enabled" : @"disabled");

    [self.deps.cuttlefishXPCWrapper prepareWithSpecificUser:self.deps.activeAccount
                                                      epoch:self.deviceInfo.epoch
                                                  machineID:self.deviceInfo.machineID
                                                 bottleSalt:bottleSalt
                                                   bottleID:[NSUUID UUID].UUIDString
                                                    modelID:self.deviceInfo.modelID
                                                 deviceName:self.deviceInfo.deviceName
                                               serialNumber:self.self.deviceInfo.serialNumber
                                                  osVersion:self.deviceInfo.osVersion
                                              policyVersion:self.policyOverride
                                              policySecrets:nil
                                  syncUserControllableViews:safariViewEnabled ?
      TPPBPeerStableInfoUserControllableViewStatus_ENABLED :
     TPPBPeerStableInfoUserControllableViewStatus_DISABLED
                                      secureElementIdentity:existingSecureElementIdentity
                                                    setting:settings
                                signingPrivKeyPersistentRef:signingKeyPersistRef
                                    encPrivKeyPersistentRef:encryptionKeyPersistRef
                                                      reply:^(NSString * _Nullable peerID,
                                                              NSData * _Nullable permanentInfo,
                                                              NSData * _Nullable permanentInfoSig,
                                                              NSData * _Nullable stableInfo,
                                                              NSData * _Nullable stableInfoSig,
                                                              TPSyncingPolicy* _Nullable syncingPolicy,
                                                              NSError * _Nullable error) {
            STRONGIFY(self);

            [[CKKSAnalytics logger] logResultForEvent:OctagonEventUpgradePrepare hardFailure:true result:error];

            if(error) {
                secerror("octagon-sos: Error preparing identity: %@", error);
                self.error = error;
                [self handlePrepareErrors:error nextExpectedState:OctagonStateBecomeUntrusted];

                [self runBeforeGroupFinished:self.finishedOp];
                return;
            }

            secnotice("octagon-sos", "Prepared: %@ %@ %@", peerID, permanentInfo, permanentInfoSig);

            NSError* localError = nil;
            BOOL persisted = [self.deps.stateHolder persistAccountChanges:^OTAccountMetadataClassC * _Nullable(OTAccountMetadataClassC * _Nonnull metadata) {
                [metadata setTPSyncingPolicy:syncingPolicy];
                return metadata;
            } error:&localError];

            if(!persisted || localError) {
                secerror("octagon-ckks: Error persisting new views and policy: %@", localError);
                self.error = localError;
                [self handlePrepareErrors:localError nextExpectedState:OctagonStateBecomeUntrusted];
                [self runBeforeGroupFinished:self.finishedOp];
                return;
            }

            [self.deps.ckks setCurrentSyncingPolicy:syncingPolicy];

            [self afterPrepare];
        }];
}

- (void)afterPrepare
{
    WEAKIFY(self);
    [self.deps.cuttlefishXPCWrapper preflightPreapprovedJoinWithSpecificUser:self.deps.activeAccount
                                                             preapprovedKeys:self.peerPreapprovedSPKIs
                                                                       reply:^(BOOL launchOkay, NSError * _Nullable error) {
        STRONGIFY(self);

        [[CKKSAnalytics logger] logResultForEvent:OctagonEventUpgradePreflightPreapprovedJoin hardFailure:true result:error];
        if(error) {
            secerror("octagon-sos: preflightPreapprovedJoin failed: %@", error);

            self.error = error;
            self.nextState = OctagonStateBecomeUntrusted;
            [self runBeforeGroupFinished:self.finishedOp];
            return;
        }

        if(!launchOkay) {
            secnotice("octagon-sos", "TPH believes a preapprovedJoin will fail; aborting.");
            self.nextState = OctagonStateBecomeUntrusted;
            [self runBeforeGroupFinished:self.finishedOp];
            return;
        }

        secnotice("octagon-sos", "TPH believes a preapprovedJoin might succeed; continuing.");
        [self afterPreflight];
    }];
}

- (void)afterPreflight
{
    WEAKIFY(self);
    self.updateOp = [[OTUpdateTrustedDeviceListOperation alloc] initWithDependencies:self.deps
                                                                       intendedState:OctagonStateReady
                                                                    listUpdatesState:OctagonStateReady
                                                            authenticationErrorState:OctagonStateLostAccountAuth
                                                                          errorState:OctagonStateError
                                                                           retryFlag:nil];
    self.updateOp.logForUpgrade = YES;
    [self runBeforeGroupFinished:self.updateOp];

    CKKSResultOperation* afterUpdate = [CKKSResultOperation named:@"after-update"
                                                      withBlock:^{
        STRONGIFY(self);
        [self afterUpdate];
    }];
    [afterUpdate addDependency:self.updateOp];
    [self runBeforeGroupFinished:afterUpdate];
}

- (void)handlePrepareErrors:(NSError *)error nextExpectedState:(OctagonState*)nextState
{
    secnotice("octagon-sos", "handling prepare error: %@", error);

    if ([self.deps.lockStateTracker isLockedError:error]) {
        self.nextState = OctagonStateWaitForUnlock;
    } else {
        self.nextState = nextState;
    }
    self.error = error;
}

- (void)afterUpdate
{
    if (self.updateOp.error) {
        [self handlePrepareErrors:self.updateOp.error nextExpectedState:self.nextState];
        [self runBeforeGroupFinished:self.finishedOp];
        return;
    }
    secnotice("octagon-sos", "Successfully saved machineID allow-list");
    [self afterSuccessfulAllowList];
}

- (void)requestSilentEscrowUpdate
{
    NSError* error = nil;
    id<SecEscrowRequestable> request = [self.deps.escrowRequestClass request:&error];
    if(!request || error) {
        secnotice("octagon-sos", "Unable to acquire a EscrowRequest object: %@", error);
        return;
    }

    [request triggerEscrowUpdate:@"octagon-sos" error:&error];
    [[CKKSAnalytics logger] logResultForEvent:OctagonEventUpgradeSilentEscrow hardFailure:true result:error];

    if(error) {
        secnotice("octagon-sos", "Unable to request silent escrow update: %@", error);
    } else{
        secnotice("octagon-sos", "Requested silent escrow update");
    }
}

- (void)afterSuccessfulAllowList
{
    WEAKIFY(self);

    OTFetchCKKSKeysOperation* fetchKeysOp = [[OTFetchCKKSKeysOperation alloc] initWithDependencies:self.deps
                                                                                     refetchNeeded:NO];
    [self runBeforeGroupFinished:fetchKeysOp];
    
    secnotice("octagon-sos", "Fetching keys from CKKS");
    CKKSResultOperation* proceedWithKeys = [CKKSResultOperation named:@"sos-upgrade-with-keys"
                                                                withBlock:^{
            STRONGIFY(self);
            [self proceedWithKeys:fetchKeysOp.viewKeySets pendingTLKShares:fetchKeysOp.pendingTLKShares];
        }];
    [proceedWithKeys addDependency:fetchKeysOp];
    [self runBeforeGroupFinished:proceedWithKeys];
}

- (void)proceedWithKeys:(NSArray<CKKSKeychainBackedKeySet*>*)viewKeySets pendingTLKShares:(NSArray<CKKSTLKShare*>*)pendingTLKShares
{
    WEAKIFY(self);

    secnotice("octagon-sos", "Beginning SOS upgrade with %d key sets and %d SOS peers", (int)viewKeySets.count, (int)self.peerPreapprovedSPKIs.count);

    [self.deps.cuttlefishXPCWrapper attemptPreapprovedJoinWithSpecificUser:self.deps.activeAccount
                                                                  ckksKeys:viewKeySets
                                                                 tlkShares:pendingTLKShares
                                                           preapprovedKeys:self.peerPreapprovedSPKIs
                                                                     reply:^(NSString * _Nullable peerID,
                                                                             NSArray<CKRecord*>* keyHierarchyRecords,
                                                                             TPSyncingPolicy* _Nullable syncingPolicy,
                                                                             NSError * _Nullable error) {
        STRONGIFY(self);

        [[CKKSAnalytics logger] logResultForEvent:OctagonEventUpgradePreapprovedJoin hardFailure:true result:error];
        if(error) {
            secerror("octagon-sos: attemptPreapprovedJoin failed: %@", error);

            if ([error isCuttlefishError:CuttlefishErrorKeyHierarchyAlreadyExists]) {
                secnotice("octagon-ckks", "A CKKS key hierarchy is out of date; requesting reset");
                self.nextState = self.ckksConflictState;
            } else {
                self.error = error;
                self.nextState = OctagonStateBecomeUntrusted;
            }
            [self runBeforeGroupFinished:self.finishedOp];
            return;
        }

        [self requestSilentEscrowUpdate];

        secerror("octagon-sos: attemptPreapprovedJoin succeded");
        [self.deps.ckks setCurrentSyncingPolicy:syncingPolicy];

        NSError* localError = nil;
        BOOL persisted = [self.deps.stateHolder persistAccountChanges:^OTAccountMetadataClassC *  _Nonnull(OTAccountMetadataClassC * _Nonnull metadata) {
            metadata.trustState = OTAccountMetadataClassC_TrustState_TRUSTED;
            metadata.peerID = peerID;

            [metadata setTPSyncingPolicy:syncingPolicy];
            return metadata;
        } error:&localError];

        if(!persisted || localError) {
            secnotice("octagon-sos", "Couldn't persist results: %@", localError);
            self.error = localError;
            self.nextState = OctagonStateError;
            [self runBeforeGroupFinished:self.finishedOp];
            return;
        }

        self.nextState = self.intendedState;

        // Tell CKKS about our shiny new records!
        secnotice("octagon-ckks", "Providing ck records (from sos upgrade) to %@", self.deps.ckks);
        [self.deps.ckks receiveTLKUploadRecords:keyHierarchyRecords];

        [self runBeforeGroupFinished:self.finishedOp];
    }];
}

@end

#endif // OCTAGON
