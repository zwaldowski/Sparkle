//
//  SUCodeSigningVerifier.m
//  Sparkle
//
//  Created by Andy Matuschak on 7/5/12.
//
//

#import "SUCodeSigningVerifier.h"
#import "SULog.h"

@implementation SUCodeSigningVerifier {
	SecCodeRef _hostCode;
	SecRequirementRef _requirement;
}

- (void)dealloc
{
	if (_hostCode) CFRelease(_hostCode);
	if (_requirement) CFRelease(_requirement);
}

- (instancetype)init
{
	self = [super init];
	if (!self) return nil;

	OSStatus result;
	__block SecCodeRef hostCode = NULL;
	__block SecRequirementRef requirement = NULL;

	id(^cleanup)(void) = ^id{
		if (hostCode) {
			CFRelease(hostCode);
			hostCode = NULL;
		}

		if (requirement) {
			CFRelease(requirement);
			requirement = NULL;
		}

		return nil;
	};

	result = SecCodeCopySelf(kSecCSDefaultFlags, &hostCode);
	if (result != noErr) {
		SULog(@"Failed to copy host code %d", result);
		return (self = cleanup());
	}

	result = SecCodeCopyDesignatedRequirement(hostCode, kSecCSDefaultFlags, &requirement);
	if (result != noErr) {
		SULog(@"Failed to copy designated requirement %d", result);
		return (self = cleanup());
	}

	return self;
}

- (BOOL)verifyBundleAtURL:(NSURL *)URL error:(out NSError **)outError
{
	NSBundle *bundle = [NSBundle bundleWithURL:URL];
	return [self verifyBundle:bundle error:outError];
}

- (BOOL)verifyBundle:(NSBundle *)bundle error:(out NSError **)outError
{
	if (outError) *outError = nil;
	if (!bundle) return NO;

	OSStatus result;
	__block SecStaticCodeRef staticCode = NULL;
	__block CFErrorRef error = NULL;

	BOOL(^cleanup)(void) = ^{
		if (staticCode) CFRelease(staticCode);
		if (error) CFRelease(error);
		return NO;
	};

	result = SecStaticCodeCreateWithPath((__bridge CFURLRef)bundle.executableURL, kSecCSDefaultFlags, &staticCode);
	if (result != noErr) {
		SULog(@"Failed to get static code %d", result);
		return cleanup();
	}

	result = SecStaticCodeCheckValidityWithErrors(staticCode, kSecCSDefaultFlags | kSecCSCheckAllArchitectures, _requirement, &error);
	if (result != noErr) {
		if (outError) {
			*outError = CFRetain(error);
		}
		return cleanup();
	}

	cleanup();
	return YES;
}

@end
