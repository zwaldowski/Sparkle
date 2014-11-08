//
//  SUCodeSigningVerifier.m
//  Sparkle
//
//  Created by Andy Matuschak on 7/5/12.
//
//

#include <Security/CodeSigning.h>
#include <Security/SecCode.h>
#import "SUCodeSigningVerifier.h"
#import "SULog.h"

@implementation SUCodeSigningVerifier

+ (BOOL)codeSignatureIsValidAtPath:(NSString *)destinationPath error:(out NSError **)outError
{
    OSStatus result;
    __block SecRequirementRef requirement = NULL;
    __block SecStaticCodeRef staticCode = NULL;
    __block SecCodeRef hostCode = NULL;
    __block CFErrorRef error = NULL;
    NSBundle *newBundle = nil;

    if (outError) {
        *outError = nil;
    }

    BOOL(^cleanup)(void) = ^{
        if (requirement) {
            CFRelease(requirement);
            requirement = NULL;
        }
        
        if (staticCode) {
            CFRelease(staticCode);
            staticCode = NULL;
        }
        
        if (hostCode) {
            CFRelease(hostCode);
            hostCode = NULL;
        }

        return NO;
    };

    result = SecCodeCopySelf(kSecCSDefaultFlags, &hostCode);
    if (result != noErr) {
        SULog(@"Failed to copy host code %d", result);
        return cleanup();
    }

    result = SecCodeCopyDesignatedRequirement(hostCode, kSecCSDefaultFlags, &requirement);
    if (result != noErr) {
        SULog(@"Failed to copy designated requirement. Code Signing OSStatus code: %d", result);
        return cleanup();
    }

    newBundle = [NSBundle bundleWithPath:destinationPath];
    if (!newBundle) {
        SULog(@"Failed to load NSBundle for update");
        result = -1;
        return cleanup();
    }

    result = SecStaticCodeCreateWithPath((__bridge CFURLRef)[newBundle executableURL], kSecCSDefaultFlags, &staticCode);
    if (result != noErr) {
        SULog(@"Failed to get static code %d", result);
        return cleanup();
    }

    result = SecStaticCodeCheckValidityWithErrors(staticCode, kSecCSDefaultFlags | kSecCSCheckAllArchitectures, requirement, &error);

    if (result != noErr) {
        if (outError) {
            *outError = CFBridgingRelease(error);
        } else {
            CFRelease(error);
        }
        
        if (result == errSecCSUnsigned) {
            SULog(@"The host app is signed, but the new version of the app is not signed using Apple Code Signing. Please ensure that the new app is signed and that archiving did not corrupt the signature.");
        }
        if (result == errSecCSReqFailed) {
            CFStringRef requirementString = nil;
            if (SecRequirementCopyString(requirement, kSecCSDefaultFlags, &requirementString) == noErr) {
                SULog(@"Code signature of the new version doesn't match the old version: %@. Please ensure that old and new app is signed using exactly the same certificate.", requirementString);
                CFRelease(requirementString);
            }

            [self logSigningInfoForCode:hostCode label:@"host info"];
            [self logSigningInfoForCode:staticCode label:@"new info"];
        }
    }
    
    cleanup();
    
    return YES;
}

static id valueOrNSNull(id value) {
    return value ? value : [NSNull null];
}

+ (void)logSigningInfoForCode:(SecStaticCodeRef)code label:(NSString*)label {
    CFDictionaryRef signingInfo = nil;
    const SecCSFlags flags = kSecCSSigningInformation | kSecCSRequirementInformation | kSecCSDynamicInformation | kSecCSContentInformation;
    if (SecCodeCopySigningInformation(code, flags, &signingInfo) == noErr) {
        NSDictionary *signingDict = CFBridgingRelease(signingInfo);
        NSMutableDictionary *relevantInfo = [NSMutableDictionary dictionary];
        for (NSString *key in @[@"format", @"identifier", @"requirements", @"teamid", @"signing-time"]) {
            relevantInfo[key] = valueOrNSNull(signingDict[key]);
        }
        NSDictionary *infoPlist = signingDict[@"info-plist"];
        relevantInfo[@"version"] = valueOrNSNull(infoPlist[@"CFBundleShortVersionString"]);
        relevantInfo[@"build"] = valueOrNSNull(infoPlist[(__bridge NSString *)kCFBundleVersionKey]);
        SULog(@"%@: %@", label, relevantInfo);
    }
}

+ (BOOL)hostApplicationIsCodeSigned
{
    OSStatus result;
    SecCodeRef hostCode = NULL;
    result = SecCodeCopySelf(kSecCSDefaultFlags, &hostCode);
    if (result != 0) return NO;

    SecRequirementRef requirement = NULL;
    result = SecCodeCopyDesignatedRequirement(hostCode, kSecCSDefaultFlags, &requirement);
    if (hostCode) CFRelease(hostCode);
    if (requirement) CFRelease(requirement);
    return (result == 0);
}

@end
