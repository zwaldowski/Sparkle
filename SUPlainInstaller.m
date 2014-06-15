//
//  SUPlainInstaller.m
//  Sparkle
//
//  Created by Andy Matuschak on 4/10/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUPlainInstaller.h"
#import "SUHost.h"

#import "NSFileManager+SUAdditions.h"

@implementation SUPlainInstaller

+ (void)performInstallationToURL:(NSURL *)installationURL fromURL:(NSURL *)URL host:(SUHost *)host delegate:delegate synchronously:(BOOL)synchronously versionComparator:(id <SUVersionComparison>)comparator
{
	// Prevent malicious downgrades:
#if !PERMIT_AUTOMATED_DOWNGRADES
	NSString *version = [[NSBundle bundleWithURL:URL] objectForInfoDictionaryKey:(__bridge id)kCFBundleVersionKey];
	if ([comparator compareVersion:[host version] toVersion:version] == NSOrderedDescending)
	{
		NSString * errorMessage = [NSString stringWithFormat:@"Sparkle Updater: Possible attack in progress! Attempting to \"upgrade\" from %@ to %@. Aborting update.", host.version, version];
		NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUDowngradeError userInfo:[NSDictionary dictionaryWithObject:errorMessage forKey:NSLocalizedDescriptionKey]];
		[self finishInstallationToURL:installationURL withResult:NO host:host error:error delegate:delegate];
		return;
	}
#endif

	void(^block)(void) = ^{ @autoreleasepool {
		NSFileManager *fm = [[NSFileManager alloc] init];
		NSError *error = nil;

		NSURL *oldURL = host.bundleURL;

		BOOL result = [fm su_copyItemAtURLWithAuthentication:URL toURL:installationURL error:&error];
		if (result) {
			if ([oldURL checkResourceIsReachableAndReturnError:NULL] && ![oldURL isEqual: installationURL]) {
				[fm su_moveItemAtURLToTrash:oldURL];
			}
			error = nil;
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			[self finishInstallationToURL:installationURL withResult:result host:host error:error delegate:delegate];
		});
	}};

	if (synchronously) {
		block();
	} else {
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), block);
	}
}

@end
