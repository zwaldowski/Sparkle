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
    if (result != 0) {
        SULog(@"Failed to copy host code %d", result);
		return cleanup();
    }
    
    result = SecCodeCopyDesignatedRequirement(hostCode, kSecCSDefaultFlags, &requirement);
    if (result != 0) {
        SULog(@"Failed to copy designated requirement %d", result);
		return cleanup();
    }
    
    NSBundle *newBundle = [NSBundle bundleWithPath:destinationPath];
    if (!newBundle) {
        SULog(@"Failed to load NSBundle for update");
		return cleanup();
    }
    
	result = SecStaticCodeCreateWithPath((CFURLRef)[newBundle executableURL], kSecCSDefaultFlags, &staticCode);
    if (result != 0) {
        SULog(@"Failed to get static code %d", result);
		return cleanup();
    }
    
	CFErrorRef error = NULL;
	result = SecStaticCodeCheckValidityWithErrors(staticCode, kSecCSDefaultFlags | kSecCSCheckAllArchitectures, requirement, &error);
	if (result != noErr) {
		if (outError) {
			*outError = [(NSError *)error autorelease];
		} else {
			CFRelease(error);
		}
	}

	cleanup();

	return (result == noErr);
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
