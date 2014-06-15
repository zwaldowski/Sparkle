//
//  SUInstaller.m
//  Sparkle
//
//  Created by Andy Matuschak on 4/10/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUInstaller.h"
#import "SUPlainInstaller.h"
#import "SUPackageInstaller.h"
#import "SUHost.h"
#import "SULog.h"
#import "NSURL+SUAdditions.h"

@implementation SUInstaller

static NSURL *sUpdateFolder = nil;

+ (NSURL *)updateFolderURL
{
	return sUpdateFolder;
}

+ (NSURL *)installSourceURLInUpdateFolder:(NSURL *)updateFolder forHost:(SUHost *)host isPackage:(out BOOL *)outIsPackage
{
	NSURL *newAppDownloadURL, *fallbackPackageURL, *currentURL;
	NSString *bundleFileName = host.bundleURL.lastPathComponent, *alternateBundleFileName = [host.name stringByAppendingPathExtension:host.bundleURL.pathExtension];
	BOOL isPackage = NO;

	sUpdateFolder = updateFolder;

	NSDirectoryEnumerator *enumerator = [[[NSFileManager alloc] init] enumeratorAtURL:updateFolder includingPropertiesForKeys:@[ NSURLIsAliasFileKey ] options:0 errorHandler:NULL];
	while ((currentURL = enumerator.nextObject)) {
		if ([currentURL.lastPathComponent isEqual:bundleFileName] || [currentURL.lastPathComponent isEqual:alternateBundleFileName]) {
			isPackage = NO;
			newAppDownloadURL = currentURL;
			break;
		} else if ([currentURL.pathExtension isEqualToString:@"pkg"] || [currentURL.pathExtension isEqualToString:@"mpkg"]) {
			if ([currentURL.lastPathComponent.stringByDeletingPathExtension isEqual:bundleFileName.stringByDeletingPathExtension]) {
				isPackage = YES;
				newAppDownloadURL = currentURL;
				break;
			}

			// Remember any other non-matching packages we have seen should we need to use one of them as a fallback.
			fallbackPackageURL = currentURL;
		} else {
			// Try matching on bundle identifiers in case the user has changed the name of the host app
			if ([[[NSBundle bundleWithURL:currentURL] bundleIdentifier] isEqual:host.bundle.bundleIdentifier]) {
				isPackage = NO;
				newAppDownloadURL = currentURL;
				break;
			}
		}

		// Some DMGs have symlinks into /Applications! That's no good!
		NSNumber *isAliasValue;
		[currentURL getResourceValue:&isAliasValue forKey:NSURLIsAliasFileKey error:NULL];
		if ([isAliasValue boolValue]) {
			[enumerator skipDescendants];
		}
	}

	// We don't have a valid URL. Try to use the fallback package.
	if (newAppDownloadURL == nil && fallbackPackageURL != nil) {
		isPackage = YES;
		newAppDownloadURL = fallbackPackageURL;
	}

	if (outIsPackage) *outIsPackage = isPackage;
	return newAppDownloadURL;

	return nil;
}

+ (NSURL *)appURLInUpdateFolder:(NSURL *)updateFolder forHost:(SUHost *)host
{
	BOOL isPackage = NO;
	NSURL *URL = [self installSourceURLInUpdateFolder:updateFolder forHost:host isPackage:&isPackage];
	return isPackage ? nil : URL;
}

+ (void)installFromUpdateFolder:(NSURL *)updateFolder overHost:(SUHost *)host installationURL:(NSURL *)installationURL delegate:(id)delegate synchronously:(BOOL)synchronously versionComparator:(id<SUVersionComparison>)comparator
{
	BOOL isPackage = NO;
	NSURL *newAppDownloadURL = [self installSourceURLInUpdateFolder:updateFolder forHost:host isPackage:&isPackage];

	if (newAppDownloadURL == nil)
	{
		[self finishInstallationToURL:installationURL withResult:NO host:host error:[NSError errorWithDomain:SUSparkleErrorDomain code:SUMissingUpdateError userInfo:@{
			NSLocalizedDescriptionKey: @"Couldn't find an appropriate update in the downloaded package."
		}] delegate:delegate];
	}
	else
	{
		[(isPackage ? [SUPackageInstaller class] : [SUPlainInstaller class]) performInstallationToURL:installationURL fromURL:newAppDownloadURL host:host delegate:delegate synchronously:synchronously versionComparator:comparator];
	}
}

+ (void)mdimportInstallationURL:(NSURL *)installationURL
{
	// *** GETS CALLED ON NON-MAIN THREAD!

	SULog( @"mdimporting" );

	NSTask *mdimport = [[NSTask alloc] init];
	[mdimport setLaunchPath:@"/usr/bin/mdimport"];
	[mdimport setArguments:@[ @(installationURL.su_fileSystemRepresentation) ]];
	@try
	{
		[mdimport launch];
		[mdimport waitUntilExit];
	}
	@catch (NSException * launchException)
	{
		// No big deal.
		SULog(@"Sparkle Error: %@", [launchException description]);
	}
}

+ (void)finishInstallationToURL:(NSURL *)installationURL withResult:(BOOL)result host:(SUHost *)host error:(NSError *)error delegate:(id)delegate
{
	if (result)
	{
		[self mdimportInstallationURL:installationURL];
		if ([delegate respondsToSelector:@selector(installerFinishedForHost:)]) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[delegate installerFinishedForHost:host];
			});
		}
	}
	else
	{
		if ([delegate respondsToSelector:@selector(installerForHost:failedWithError:)]) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[delegate installerForHost:host failedWithError:error];
			});
		}
	}
}

@end
