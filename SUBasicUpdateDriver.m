//
//  SUBasicUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 4/23/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUBasicUpdateDriver.h"

#import "SUHost.h"
#import "SUDSAVerifier.h"
#import "SUInstaller.h"
#import "SUStandardVersionComparator.h"
#import "SULog.h"
#import "SUBinaryDeltaCommon.h"
#import "SUCodeSigningVerifier.h"
#import "SUUpdater_Private.h"

#import "NSFileManager+SUAdditions.h"
#import "NSURL+SUAdditions.h"

#ifdef FINISH_INSTALL_TOOL_NAME
    // FINISH_INSTALL_TOOL_NAME expands to unquoted finish_install
    #define QUOTE_NS_STRING2(str) @"" #str
    #define QUOTE_NS_STRING1(str) QUOTE_NS_STRING2(str)
    #define FINISH_INSTALL_TOOL_NAME_STRING QUOTE_NS_STRING1(FINISH_INSTALL_TOOL_NAME)
#else
    #error FINISH_INSTALL_TOOL_NAME not defined
#endif

@implementation SUBasicUpdateDriver {
	SUAppcast *appcast;
	SUUnarchiver *unarchiver;
	BOOL _restartPostponed;

	NSFileManager *_fileManager;
	NSURL *_tempURL;
	NSURL *_relaunchURL;
}

- initWithUpdater:(SUUpdater *)theUpdater {
	self = [super initWithUpdater:theUpdater];
	if (!self) return nil;

	_fileManager = [[NSFileManager alloc] init];

	return self;
}

- (void)checkForUpdatesAtURL:(NSURL *)URL host:(SUHost *)aHost
{	
	[super checkForUpdatesAtURL:URL host:aHost];
	if ([aHost isRunningOnReadOnlyVolume])
	{
		[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURunningFromDiskImageError userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:SULocalizedString(@"%1$@ can't be updated when it's running from a read-only volume like a disk image or an optical drive. Move %1$@ to your Applications folder, relaunch it from there, and try again.", nil), [aHost name]] forKey:NSLocalizedDescriptionKey]]];
		return;
	}	
	
	appcast = [[SUAppcast alloc] init];
	[appcast setDelegate:self];
	[appcast setUserAgentString:[updater userAgentString]];
	[appcast fetchAppcastFromURL:URL];
}

- (id <SUVersionComparison>)versionComparator
{
	id <SUVersionComparison> comparator = nil;
	
	// Give the delegate a chance to provide a custom version comparator
	if ([[updater delegate] respondsToSelector:@selector(versionComparatorForUpdater:)])
		comparator = [[updater delegate] versionComparatorForUpdater:updater];
	
	// If we don't get a comparator from the delegate, use the default comparator
	if (!comparator)
		comparator = [SUStandardVersionComparator defaultComparator];
	
	return comparator;	
}

- (BOOL)isItemNewer:(SUAppcastItem *)ui
{
	return [[self versionComparator] compareVersion:[host version] toVersion:[ui versionString]] == NSOrderedAscending;
}

- (BOOL)hostSupportsItem:(SUAppcastItem *)ui
{
	if (([ui minimumSystemVersion] == nil || [[ui minimumSystemVersion] isEqualToString:@""]) && 
        ([ui maximumSystemVersion] == nil || [[ui maximumSystemVersion] isEqualToString:@""])) { return YES; }
    
    BOOL minimumVersionOK = TRUE;
    BOOL maximumVersionOK = TRUE;
    
    // Check minimum and maximum System Version
    if ([ui minimumSystemVersion] != nil && ![[ui minimumSystemVersion] isEqualToString:@""]) {
        minimumVersionOK = [[SUStandardVersionComparator defaultComparator] compareVersion:[ui minimumSystemVersion] toVersion:[SUHost systemVersionString]] != NSOrderedDescending;
    }
    if ([ui maximumSystemVersion] != nil && ![[ui maximumSystemVersion] isEqualToString:@""]) {
        maximumVersionOK = [[SUStandardVersionComparator defaultComparator] compareVersion:[ui maximumSystemVersion] toVersion:[SUHost systemVersionString]] != NSOrderedAscending;
    }
    
    return minimumVersionOK && maximumVersionOK;
}

- (BOOL)itemContainsSkippedVersion:(SUAppcastItem *)ui
{
	NSString *skippedVersion = [host objectForUserDefaultsKey:SUSkippedVersionKey];
	if (skippedVersion == nil) { return NO; }
	return [[self versionComparator] compareVersion:[ui versionString] toVersion:skippedVersion] != NSOrderedDescending;
}

- (BOOL)itemContainsValidUpdate:(SUAppcastItem *)ui
{
	return [self hostSupportsItem:ui] && [self isItemNewer:ui] && ![self itemContainsSkippedVersion:ui];
}

- (void)appcastDidFinishLoading:(SUAppcast *)ac
{
	if ([[updater delegate] respondsToSelector:@selector(updater:didFinishLoadingAppcast:)])
		[[updater delegate] updater:updater didFinishLoadingAppcast:ac];
	
	NSDictionary *userInfo = (ac != nil) ? @{SUUpdaterAppcastNotificationKey : ac} : nil;
	[[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidFinishLoadingAppCastNotification object:updater userInfo:userInfo];
    
    SUAppcastItem *item = nil;
    
	// Now we have to find the best valid update in the appcast.
	if ([[updater delegate] respondsToSelector:@selector(bestValidUpdateInAppcast:forUpdater:)]) // Does the delegate want to handle it?
	{
		item = [[updater delegate] bestValidUpdateInAppcast:ac forUpdater:updater];
	}
	else // If not, we'll take care of it ourselves.
	{
		// Find the first update we can actually use.
		NSEnumerator *updateEnumerator = [[ac items] objectEnumerator];
		do {
			item = [updateEnumerator nextObject];
		} while (item && ![self hostSupportsItem:item]);

		if (binaryDeltaSupported()) {        
			SUAppcastItem *deltaUpdateItem = [[item deltaUpdates] objectForKey:[host version]];
			if (deltaUpdateItem && [self hostSupportsItem:deltaUpdateItem]) {
				nonDeltaUpdateItem = item;
				item = deltaUpdateItem;
			}
		}
	}
    
	updateItem = item;
	appcast = nil;
	if (updateItem == nil) { [self didNotFindUpdate]; return; }
	
	if ([self itemContainsValidUpdate:updateItem])
		[self didFindValidUpdate];
	else
		[self didNotFindUpdate];
}

- (void)appcast:(SUAppcast *)ac failedToLoadWithError:(NSError *)error
{
	appcast = nil;
	[self abortUpdateWithError:error];
}

- (void)didFindValidUpdate
{
	if ([[updater delegate] respondsToSelector:@selector(updater:didFindValidUpdate:)])
		[[updater delegate] updater:updater didFindValidUpdate:updateItem];
	NSDictionary *userInfo = (updateItem != nil) ? @{SUUpdaterAppcastItemNotificationKey : updateItem} : nil;
	[[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidFindValidUpdateNotification object:updater userInfo:userInfo];
	[self downloadUpdate];
}

- (void)didNotFindUpdate
{
	if ([[updater delegate] respondsToSelector:@selector(updaterDidNotFindUpdate:)])
		[[updater delegate] updaterDidNotFindUpdate:updater];
	[[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidNotFindUpdateNotification object:updater];
	
	[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUNoUpdateError userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:SULocalizedString(@"You already have the newest version of %@.", nil), [host name]] forKey:NSLocalizedDescriptionKey]]];
}

- (void)downloadUpdate
{
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[updateItem fileURL]];
	[request setValue:[updater userAgentString] forHTTPHeaderField:@"User-Agent"];
	download = [[NSURLDownload alloc] initWithRequest:request delegate:self];
}

- (void)download:(NSURLDownload *)d decideDestinationWithSuggestedFilename:(NSString *)name
{
	NSString *downloadFileName = [NSString stringWithFormat:@"%@ %@", [host name], [updateItem versionString]];

	NSURL *tempURL = SUUniqueURLInDirectory(host.appSupportURL, downloadFileName, nil);

    // Create the temporary directory if necessary.
	BOOL success = [_fileManager createDirectoryAtPath:tempURL.path withIntermediateDirectories:YES attributes:nil error:NULL];
	if (!success)
	{
		// Okay, something's really broken with this user's file structure.
		[download cancel];
		[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUTemporaryDirectoryError userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Can't make a temporary directory for the update download at %@.", tempURL] forKey:NSLocalizedDescriptionKey]]];
	}

	_tempURL = tempURL;
	downloadPath = [tempURL.path stringByAppendingPathComponent:name];
	[download setDestination:downloadPath allowOverwrite:YES];
}

- (BOOL)validateUpdateDownloadedToURL:(NSURL *)downloadedURL extractedToURL:(NSURL *)extractedURL DSASignature:(NSData *)DSASignature publicDSAKey:(NSString *)publicDSAKey
{
	NSURL *newBundleURL = [SUInstaller appURLInUpdateFolder:extractedURL forHost:host];
	if (newBundleURL)
	{
		NSError *error = nil;
		if ([SUCodeSigningVerifier.new verifyBundleAtURL:newBundleURL error:&error]) {
			return YES;
		} else {
			SULog(@"Code signature check on update failed: %@", error);
		}
	}

	return [[[SUDSAVerifier alloc] initWithPublicKeyString:publicDSAKey] verifyURL:downloadedURL signature:DSASignature];
}

- (void)downloadDidFinish:(NSURLDownload *)d
{
	[self extractUpdate];
}

- (void)download:(NSURLDownload *)download didFailWithError:(NSError *)error
{
	[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURelaunchError userInfo:[NSDictionary dictionaryWithObjectsAndKeys:SULocalizedString(@"An error occurred while downloading the update. Please try again later.", nil), NSLocalizedDescriptionKey, [error localizedDescription], NSLocalizedFailureReasonErrorKey, nil]]];
}

- (BOOL)download:(NSURLDownload *)download shouldDecodeSourceDataOfMIMEType:(NSString *)encodingType
{
	// We don't want the download system to extract our gzips.
	// Note that we use a substring matching here instead of direct comparison because the docs say "application/gzip" but the system *uses* "application/x-gzip". This is a documentation bug.
	return ([encodingType rangeOfString:@"gzip"].location == NSNotFound);
}

- (void)extractUpdate
{	
	unarchiver = [SUUnarchiver unarchiverForPath:downloadPath updatingHost:host];
	if (!unarchiver)
	{
		SULog(@"Sparkle Error: No valid unarchiver for %@!", downloadPath);
		[self unarchiverDidFail:nil];
		return;
	}
	[unarchiver setDelegate:self];
	[unarchiver start];
}

- (void)failedToApplyDeltaUpdate
{
	// When a delta update fails to apply we fall back on updating via a full install.
	updateItem = nonDeltaUpdateItem;
	nonDeltaUpdateItem = nil;

	[self downloadUpdate];
}

- (void)unarchiverDidFinish:(SUUnarchiver *)ua
{
	unarchiver = nil;

	[self installWithToolAndRelaunch:YES];
}

- (void)unarchiverDidFail:(SUUnarchiver *)ua
{
	unarchiver = nil;

	if ([updateItem isDeltaUpdate]) {
		[self failedToApplyDeltaUpdate];
		return;
	}

	[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:[NSDictionary dictionaryWithObject:SULocalizedString(@"An error occurred while extracting the archive. Please try again later.", nil) forKey:NSLocalizedDescriptionKey]]];
}

- (BOOL)shouldInstallSynchronously { return NO; }

- (void)installWithToolAndRelaunch:(BOOL)relaunch
{
	// Perhaps a poor assumption but: if we're not relaunching, we assume we shouldn't be showing any UI either. Because non-relaunching installations are kicked off without any user interaction, we shouldn't be interrupting them.
	[self installWithToolAndRelaunch:relaunch displayingUserInterface:relaunch];
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
- (void)installWithToolAndRelaunch:(BOOL)relaunch displayingUserInterface:(BOOL)showUI
{
	NSFileManager *fm = [[NSFileManager alloc] init];
	NSURL *downloadURL = [NSURL fileURLWithPath:downloadPath];

#if !ENDANGER_USERS_WITH_INSECURE_UPDATES
    if (![self validateUpdateDownloadedToURL:downloadURL extractedToURL:_tempURL DSASignature:updateItem.DSASignature publicDSAKey:host.publicDSAKey]) {
        [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUSignatureError userInfo:[NSDictionary dictionaryWithObjectsAndKeys:SULocalizedString(@"An error occurred while extracting the archive. Please try again later.", nil), NSLocalizedDescriptionKey, @"The update is improperly signed.", NSLocalizedFailureReasonErrorKey, nil]]];
        return;
	}
#endif
    
    if (![updater mayUpdateAndRestart])
    {
        [self abortUpdate];
        return;
    }
    
    // Give the host app an opportunity to postpone the install and relaunch.
	if (!_restartPostponed) {
		if ([[updater delegate] respondsToSelector:@selector(updater:shouldPostponeRelaunchForUpdate:completionHandler:)]) {
			_restartPostponed = YES;

			if ([[updater delegate] updater:updater shouldPostponeRelaunchForUpdate:updateItem completionHandler:^{
				[self installWithToolAndRelaunch:NO];
			}]) {
				return;
			}
		} else if ([[updater delegate] respondsToSelector:@selector(updater:shouldPostponeRelaunchForUpdate:untilInvoking:)]) {
			NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[[self class] instanceMethodSignatureForSelector:@selector(installWithToolAndRelaunch:)]];
			[invocation setSelector:@selector(installWithToolAndRelaunch:)];
			[invocation setArgument:&relaunch atIndex:2];
			[invocation setTarget:self];
			_restartPostponed = YES;
			if ([[updater delegate] updater:updater shouldPostponeRelaunchForUpdate:updateItem untilInvoking:invocation])
				return;
		}
    }
    
	if ([[updater delegate] respondsToSelector:@selector(updater:willInstallUpdate:)])
		[[updater delegate] updater:updater willInstallUpdate:updateItem];

    NSString *const finishInstallToolName = FINISH_INSTALL_TOOL_NAME_STRING;

	// Copy the relauncher into a temporary directory so we can get to it after the new version's installed.
	// Only the paranoid survive: if there's already a stray copy of relaunch there, we would have problems.
	NSURL *relaunchURLToCopy = [SUBundle() URLForResource:finishInstallToolName withExtension:@"app"];
	if (relaunchURLToCopy != nil)
	{
		NSURL *targetParentURL = host.appSupportURL;
		NSURL *targetURL = [targetParentURL URLByAppendingPathComponent:relaunchURLToCopy.lastPathComponent];

		NSError *error = nil;
		[fm createDirectoryAtPath:targetParentURL.path withIntermediateDirectories:YES attributes:nil error:&error];

		if ([fm su_copyItemAtURLWithAuthentication:relaunchURLToCopy toURL:targetURL error:&error]) {
			_relaunchURL = targetURL;
		} else {
			[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURelaunchError userInfo:@{
				NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while extracting the archive. Please try again later.", nil),
				NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:@"Couldn't copy relauncher (%@) to temporary URL (%@)! %@", relaunchURLToCopy, targetURL, (error ? [error localizedDescription] : @"")],
			}]];
		}
	}

    [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterWillRestartNotification object:self];
    if ([[updater delegate] respondsToSelector:@selector(updaterWillRelaunchApplication:)])
        [[updater delegate] updaterWillRelaunchApplication:updater];

    if ([_relaunchURL checkResourceIsReachableAndReturnError:NULL])
    {
        // Note that we explicitly use the host app's name here, since updating plugin for Mail relaunches Mail, not just the plugin.
		[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURelaunchError userInfo:@{
			NSLocalizedDescriptionKey: [NSString stringWithFormat:SULocalizedString(@"An error occurred while relaunching %1$@, but the new version will be available next time you run %1$@.", nil), [host name]],
			NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:@"Couldn't find the relauncher (expected to find it at %@)", _relaunchURL]
		}]];
        // We intentionally don't abandon the update here so that the host won't initiate another.
        return;
    }

	NSURL *URLToRelaunch = host.bundleURL;
	if ([[updater delegate] respondsToSelector:@selector(URLToRelaunchForUpdater:)])
		URLToRelaunch = [[updater delegate] URLToRelaunchForUpdater:updater];
	else if ([[updater delegate] respondsToSelector:@selector(pathToRelaunchForUpdater:)])
		URLToRelaunch = [NSURL fileURLWithPath:[[updater delegate] pathToRelaunchForUpdater:updater]];

	NSString *relaunchToolPath = [[NSBundle bundleWithURL:_relaunchURL] pathForAuxiliaryExecutable:finishInstallToolName];

	[NSTask launchedTaskWithLaunchPath: relaunchToolPath arguments:@[
																	@(host.bundleURL.su_fileSystemRepresentation),
																	@(URLToRelaunch.su_fileSystemRepresentation),
																	[NSString stringWithFormat:@"%d", NSProcessInfo.processInfo.processIdentifier],
																	@(_tempURL.su_fileSystemRepresentation),
																	relaunch ? @"1" : @"0",
																	showUI ? @"1" : @"0",
																	]];

    [NSApp terminate:self];
}
#pragma clang diagnostic pop

- (void)cleanUpDownload
{
    if (_tempURL != nil)	 // tempURL contains downloadPath, so we implicitly delete both here.
	{
        NSError	*error = nil;
		if(![_fileManager removeItemAtURL:_tempURL error:&error]) {
			[NSWorkspace.sharedWorkspace recycleURLs:@[ _tempURL ] completionHandler:NULL];
		}
	}
}

- (void)installerForHost:(SUHost *)aHost failedWithError:(NSError *)error
{
	if (aHost != host) { return; }
	NSError	*	dontThrow = nil;
	[[NSFileManager defaultManager] removeItemAtURL: _relaunchURL error: &dontThrow]; // Clean up the copied relauncher
	[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:[NSDictionary dictionaryWithObjectsAndKeys:SULocalizedString(@"An error occurred while installing the update. Please try again later.", nil), NSLocalizedDescriptionKey, [error localizedDescription], NSLocalizedFailureReasonErrorKey, nil]]];
}

- (void)abortUpdate
{
    [self cleanUpDownload];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[super abortUpdate];
}

- (void)abortUpdateWithError:(NSError *)error
{
	if ([error code] != SUNoUpdateError) // Let's not bother logging this.
		SULog(@"Sparkle Error: %@", [error localizedDescription]);
	if ([error localizedFailureReason])
		SULog(@"Sparkle Error (continued): %@", [error localizedFailureReason]);
	if (download)
		[download cancel];
	[self abortUpdate];
}

@end
