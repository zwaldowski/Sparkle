//
//  SUPackageInstaller.m
//  Sparkle
//
//  Created by Andy Matuschak on 4/10/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUPackageInstaller.h"
#import "SUConstants.h"
#import "NSURL+SUAdditions.h"

@implementation SUPackageInstaller

+ (void)performInstallationToURL:(NSURL *)installationURL fromURL:(NSURL *)URL host:(SUHost *)host delegate:(id)delegate synchronously:(BOOL)synchronously versionComparator:(id<SUVersionComparison>)comparator
{
	NSString *command;
	NSArray *args;

	// Run installer using the "open" command to ensure it is launched in front of current application.
	// -W = wait until the app has quit.
	// -n = Open another instance if already open.
	// -b = app bundle identifier
	command = @"/usr/bin/open";
	args = [NSArray arrayWithObjects:@"-W", @"-n", @"-b", @"com.apple.installer", @(URL.su_fileSystemRepresentation), nil];

	if (![[NSFileManager defaultManager] fileExistsAtPath:command]) {
		NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUMissingInstallerToolError userInfo:[NSDictionary dictionaryWithObject:@"Couldn't find Apple's installer tool!" forKey:NSLocalizedDescriptionKey]];
		dispatch_async(dispatch_get_main_queue(), ^{
			[self finishInstallationToURL:installationURL withResult:NO host:host error:error delegate:delegate];
		});

		return;
	}

	void(^block)(void) = ^{ @autoreleasepool {
		NSTask *installer = [NSTask launchedTaskWithLaunchPath:command arguments:args];
		[installer waitUntilExit];

		// Known bug: if the installation fails or is canceled, Sparkle goes ahead and restarts, thinking everything is fine.
		dispatch_async(dispatch_get_main_queue(), ^{
			[self finishInstallationToURL:installationURL withResult:YES host:host error:nil delegate:delegate];
		});
	}};

	if (synchronously) {
		block();
	} else {
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), block);
	}
}

@end
