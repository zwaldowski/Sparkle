//
//  NSFileManager+SUAdditions.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/9/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "NSFileManager+SUAdditions.h"
#include <sys/stat.h>
#include <sys/xattr.h>

#import "NSURL+SUAdditions.h"
#import "SULog.h"

// Now let's make sure we get a unique URL.
NSURL *SUUniqueURLInDirectory(NSURL *parent, NSString *prefix, NSString *extension) {
	int cnt = 2;
	NSURL *tempURL = [[parent URLByAppendingPathComponent:prefix] URLByAppendingPathExtension:extension];
	while ([tempURL checkResourceIsReachableAndReturnError:NULL] && cnt <= 9999) {
		NSString *name = [NSString stringWithFormat:@"%@ %d", prefix, cnt++];
		NSURL *withoutExt = [parent URLByAppendingPathComponent:name];
		tempURL = extension ? [withoutExt URLByAppendingPathExtension:extension] : withoutExt;
	}
	return tempURL;
}

static OSStatus su_AuthorizationExecuteWithPrivileges(AuthorizationRef authorization, const char *pathToTool, AuthorizationFlags flags, char *const *arguments)
{
	// flags are currently reserved
	if (flags != 0)
		return errAuthorizationInvalidFlags;

	char **(^argVector)(const char *, const char *, const char *, char *const *) = ^char **(const char *bTrampoline, const char *bPath,
																							const char *bMboxFdText, char *const *bArguments){
		int length = 0;
		if (bArguments) {
			for (char *const *p = bArguments; *p; p++)
				length++;
		}

		const char **args = (const char **)malloc(sizeof(const char *) * (length + 4));
		if (args) {
			args[0] = bTrampoline;
			args[1] = bPath;
			args[2] = bMboxFdText;
			if (bArguments)
				for (int n = 0; bArguments[n]; n++)
					args[n + 3] = bArguments[n];
			args[length + 3] = NULL;
			return (char **)args;
		}
		return NULL;
	};

	// externalize the authorization
	AuthorizationExternalForm extForm;
	OSStatus err;
	if ((err = AuthorizationMakeExternalForm(authorization, &extForm)))
		return err;

	// create the mailbox file
	FILE *mbox = tmpfile();
	if (!mbox)
		return errAuthorizationInternal;
	if (fwrite(&extForm, sizeof(extForm), 1, mbox) != 1) {
		fclose(mbox);
		return errAuthorizationInternal;
	}
	fflush(mbox);

	// make text representation of the temp-file descriptor
	char mboxFdText[20];
	snprintf(mboxFdText, sizeof(mboxFdText), "auth %d", fileno(mbox));

	// make a notifier pipe
	int notify[2];
	if (pipe(notify)) {
		fclose(mbox);
		return errAuthorizationToolExecuteFailure;
	}

	// do the standard forking tango...
	unsigned int delay = 1;
	for (int n = 5;; n--, delay *= 2) {
		switch (fork()) {
			case -1: { // error
				if (errno == EAGAIN) {
					// potentially recoverable resource shortage
					if (n > 0) {
						sleep(delay);
						continue;
					}
				}
				close(notify[0]); close(notify[1]);
				return errAuthorizationToolExecuteFailure;
			}

			default: {	// parent
				// close foreign side of pipes
				close(notify[1]);

				// close mailbox file (child has it open now)
				fclose(mbox);

				// get status notification from child
				OSStatus status;
				ssize_t rc = read(notify[0], &status, sizeof(status));
				status = ntohl(status);
				switch (rc) {
					default:				// weird result of read: post error
						status = errAuthorizationToolEnvironmentError;
						// fall through
					case sizeof(status):	// read succeeded: child reported an error
						close(notify[0]);
						return status;
					case 0:					// end of file: exec succeeded
						close(notify[0]);
						return noErr;
				}
			}

			case 0: { // child
				// close foreign side of pipes
				close(notify[0]);

				// fd 1 (stdout) holds the notify write end
				dup2(notify[1], 1);
				close(notify[1]);

				// fd 0 (stdin) holds either the comm-link write-end or /dev/null
				close(0);
				open("/dev/null", O_RDWR);

				// where is the trampoline?
				const char *trampoline = "/usr/libexec/security_authtrampoline";
				char **argv = argVector(trampoline, pathToTool, mboxFdText, arguments);
				if (argv) {
					execv(trampoline, argv);
					free(argv);
				}

				// execute failed - tell the parent
				OSStatus error = errAuthorizationToolExecuteFailure;
				error = htonl(error);
				write(1, &error, sizeof(error));
				_exit(1);
			}
		}
	}
}

// Authorization code based on generous contribution from Allan Odgaard. Thanks, Allan!
static BOOL su_AuthorizationExecuteWithPrivilegesAndWait(AuthorizationRef authorization, const char* executablePath, AuthorizationFlags options, const char* const* arguments)
{
	// *** MUST BE SAFE TO CALL ON NON-MAIN THREAD!

	sig_t oldSigChildHandler = signal(SIGCHLD, SIG_DFL);
	BOOL returnValue = YES;

	if (su_AuthorizationExecuteWithPrivileges(authorization, executablePath, options, (char* const*)arguments) == errAuthorizationSuccess)
	{
		int status;
		pid_t pid = wait(&status);
		if (pid == -1 || !WIFEXITED(status) || WEXITSTATUS(status) != 0)
			returnValue = NO;
	}
	else
		returnValue = NO;

	signal(SIGCHLD, oldSigChildHandler);
	return returnValue;
}

@implementation NSFileManager (SUPlainInstallerInternals)

#pragma mark - Internal

- (NSURL *)su_trashDirectoryForURL:(NSURL *)URL
{
	if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber10_7) {
		return [self URLForDirectory:NSTrashDirectory inDomain:NSUserDomainMask appropriateForURL:URL create:YES error:NULL];
	}

	FSCatalogInfo catInfo;
	FSRef trashRef, pathRef;
	FSVolumeRefNum vSrcRefNum;
	bzero(&catInfo, sizeof(FSCatalogInfo));

	if (!CFURLGetFSRef((__bridge CFURLRef)URL, &pathRef)) return nil;
	if (FSGetCatalogInfo(&pathRef, kFSCatInfoVolume, &catInfo, NULL, NULL, NULL) != noErr) return nil;
	vSrcRefNum = catInfo.volume;
	if (FSFindFolder(vSrcRefNum, kTrashFolderType, kCreateFolder, &trashRef ) != noErr) return nil;
	if (FSGetCatalogInfo(&trashRef, kFSCatInfoVolume, &catInfo, NULL, NULL, NULL) != noErr || vSrcRefNum != catInfo.volume) return nil;
	return (__bridge_transfer NSURL *)CFURLCreateFromFSRef(NULL, &trashRef);
}

- (BOOL)su_URLIsWritable:(NSURL *)URL
{
	if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber10_6) {
		NSNumber *value;
		[URL getResourceValue:&value forKey:NSURLIsWritableKey error:NULL];
		return [value boolValue];
	}
	return (access([URL su_fileSystemRepresentation], W_OK) == 0);
}

#pragma mark - Temporary files

- (NSURL *)su_temporaryCopyURL:(NSURL *)URL didFindTrash:(BOOL *)outDidFindTrash
{
	// *** MUST BE SAFE TO CALL ON NON-MAIN THREAD!
	NSURL *tempURL = [self su_trashDirectoryForURL:URL];
	if (outDidFindTrash)
		*outDidFindTrash = (tempURL != nil);

	if(!tempURL)
		tempURL = [URL URLByDeletingLastPathComponent];

	NSString *prefix = URL.lastPathComponent.stringByDeletingPathExtension;

	// Let's try to read the version number so the filename will be more meaningful.
#if TRY_TO_APPEND_VERSION_NUMBER
	NSString *postFix = nil;
	NSString *version = nil;
	if ((version = [[NSBundle bundleWithURL:URL] objectForInfoDictionaryKey:(__bridge id)kCFBundleVersionKey]) && ![version isEqualToString:@""]) {
		NSMutableCharacterSet *validCharacters = [NSMutableCharacterSet alphanumericCharacterSet];
		[validCharacters formUnionWithCharacterSet:[NSCharacterSet characterSetWithCharactersInString:@".-()"]];
		postFix = [version stringByTrimmingCharactersInSet:[validCharacters invertedSet]];
	} else {
		postFix = @"old";
	}
	prefix = [NSString stringWithFormat: @"%@ (%@)", prefix, postFix];
#endif

	return SUUniqueURLInDirectory(tempURL, prefix, URL.pathExtension);
}

#pragma mark - Copy

- (BOOL)su_copyItemAtURLWithForcedAuthentication:(NSURL *)src toURL:(NSURL *)dst temporaryURL:(NSURL *)tmp error:(out NSError **)error
{
	// *** MUST BE SAFE TO CALL ON NON-MAIN THREAD!

	const char* srcPath = src.su_fileSystemRepresentation;
	const char* tmpPath = tmp.su_fileSystemRepresentation;
	const char* dstPath = dst.su_fileSystemRepresentation;

	struct stat dstSB;
	if( stat(dstPath, &dstSB) != 0 )	// Doesn't exist yet, try containing folder.
	{
		const char*	dstDirPath = dst.URLByDeletingLastPathComponent.su_fileSystemRepresentation;
		if( stat(dstDirPath, &dstSB) != 0 )
		{
			NSString *errorMessage = [NSString stringWithFormat:@"Stat on %@ during authenticated file copy failed.", dst];
			if (error != NULL)
				*error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUFileCopyFailure userInfo:[NSDictionary dictionaryWithObject:errorMessage forKey:NSLocalizedDescriptionKey]];
			return NO;
		}
	}

	AuthorizationRef auth = NULL;
	OSStatus authStat = errAuthorizationDenied;
	while (authStat == errAuthorizationDenied) {
		authStat = AuthorizationCreate(NULL,
									   kAuthorizationEmptyEnvironment,
									   kAuthorizationFlagDefaults,
									   &auth);
	}

	BOOL res = (authStat == errAuthorizationSuccess);
	if (res) {
		char uidgid[42];
		snprintf(uidgid, sizeof(uidgid), "%u:%u",
				 dstSB.st_uid, dstSB.st_gid);

		// If the currently-running application is trusted, the new
		// version should be trusted as well.  Remove it from the
		// quarantine to avoid a delay at launch, and to avoid
		// presenting the user with a confusing trust dialog.
		//
		// This needs to be done after the application is moved to its
		// new home with "mv" in case it's moved across filesystems: if
		// that happens, "mv" actually performs a copy and may result
		// in the application being quarantined.  It also needs to be
		// done before "chown" changes ownership, because the ownership
		// change will almost certainly make it impossible to change
		// attributes to release the files from the quarantine.
		[self su_releaseItemAtURLFromQuarantine:src];

		const char* coParams[] = { "-R", uidgid, srcPath, NULL };
		res = su_AuthorizationExecuteWithPrivilegesAndWait( auth, "/usr/sbin/chown", kAuthorizationFlagDefaults, coParams );
		if( !res )
			SULog( @"chown -R %s %s failed.", uidgid, srcPath );

		BOOL	haveDst = [dst checkResourceIsReachableAndReturnError:NULL];
		if( res && haveDst )	// If there's something at our tmp path (previous failed update or whatever) delete that first.
		{
			const char*	rmParams[] = { "-rf", tmpPath, NULL };
			res = su_AuthorizationExecuteWithPrivilegesAndWait( auth, "/bin/rm", kAuthorizationFlagDefaults, rmParams );
			if( !res )
				SULog( @"rm failed" );
		}

		if( res && haveDst )	// Move old exe to tmp path.
		{
			const char* mvParams[] = { "-f", dstPath, tmpPath, NULL };
			res = su_AuthorizationExecuteWithPrivilegesAndWait( auth, "/bin/mv", kAuthorizationFlagDefaults, mvParams );
			if( !res )
				SULog( @"mv 1 failed" );
		}

		if( res )	// Move new exe to old exe's path.
		{
			const char* mvParams2[] = { "-f", srcPath, dstPath, NULL };
			res = su_AuthorizationExecuteWithPrivilegesAndWait( auth, "/bin/mv", kAuthorizationFlagDefaults, mvParams2 );
			if( !res )
				SULog( @"mv 2 failed" );
		}

		AuthorizationFree(auth, 0);

		// If the currently-running application is trusted, the new
		// version should be trusted as well.  Remove it from the
		// quarantine to avoid a delay at launch, and to avoid
		// presenting the user with a confusing trust dialog.
		//
		// This needs to be done after the application is moved to its
		// new home with "mv" in case it's moved across filesystems: if
		// that happens, "mv" actually performs a copy and may result
		// in the application being quarantined.
		if (res)
		{
			SULog(@"releaseFromQuarantine after installing");

			[self su_releaseItemAtURLFromQuarantine:dst];
		} else {
			// Something went wrong somewhere along the way, but we're not sure exactly where.
			if (error != nil) {
				NSString *errorMessage = [NSString stringWithFormat:@"Authenticated file copy from %@ to %@ failed.", src, dst];
				*error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUAuthenticationFailure userInfo:[NSDictionary dictionaryWithObject:errorMessage forKey:NSLocalizedDescriptionKey]];
			}
		}
	} else  {
		if (error != nil) {
			NSString *errorMessage = [NSString stringWithFormat:@"Couldn't get permission to authenticate."];
			*error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUAuthenticationFailure userInfo:[NSDictionary dictionaryWithObject:errorMessage forKey:NSLocalizedDescriptionKey]];
		}
	}
	return res;
}

- (BOOL)su_copyItemAtURLWithAuthentication:(NSURL *)srcURL toURL:(NSURL *)dstURL error:(out NSError **)error
{
	BOOL didFindTrash = NO;
	NSURL *tmpURL = [self su_temporaryCopyURL:dstURL didFindTrash:&didFindTrash];

	BOOL hadFileAtDest = [dstURL checkResourceIsReachableAndReturnError:NULL];

	if ((hadFileAtDest && ![self su_URLIsWritable:dstURL]) || ![self su_URLIsWritable:dstURL.URLByDeletingLastPathComponent] || (!hadFileAtDest && ![self su_URLIsWritable:dstURL.URLByDeletingLastPathComponent.URLByDeletingLastPathComponent])) {
		return [self su_copyItemAtURLWithForcedAuthentication:srcURL toURL:dstURL temporaryURL:tmpURL error:error];
	}

	if (hadFileAtDest && [tmpURL checkResourceIsReachableAndReturnError:NULL]) {
		NSError *localError = nil;
		if (![self moveItemAtURL:dstURL toURL:tmpURL error:&localError]) {
			if (error != NULL) {
				NSString *errorMessage = [NSString stringWithFormat:@"Couldn't move %@ to %@.", dstURL, tmpURL];
				*error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUFileCopyFailure userInfo:@{
					NSLocalizedDescriptionKey: errorMessage,
					NSUnderlyingErrorKey: localError
				}];
			}
			return NO;
		}
	}

	if ([srcURL checkResourceIsReachableAndReturnError:NULL]) {
		NSError *localError = nil;
		BOOL success;
		if (!(success = [self copyItemAtURL:srcURL toURL:dstURL error:&localError])) {
			if (hadFileAtDest)
				success = [self moveItemAtURL:tmpURL toURL:dstURL error:&localError];
			if (!success && error != NULL) {
				NSString *errorMessage = [NSString stringWithFormat:@"Couldn't move %@ to %@.", dstURL, tmpURL];
				*error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUFileCopyFailure userInfo:@{
					NSLocalizedDescriptionKey: errorMessage,
					NSUnderlyingErrorKey: localError
				}];
			}
			return NO;
		}
	}

	// If the currently-running application is trusted, the new
	// version should be trusted as well.  Remove it from the
	// quarantine to avoid a delay at launch, and to avoid
	// presenting the user with a confusing trust dialog.
	//
	// This needs to be done after the application is moved to its
	// new home in case it's moved across filesystems: if that
	// happens, the move is actually a copy, and it may result
	// in the application being quarantined.
	[self su_releaseItemAtURLFromQuarantine:dstURL];

	return YES;
}

#pragma mark - Move

- (BOOL)su_moveItemAtURLWithForcedAuthentication:(NSURL *)src toURL:(NSURL *)dst error:(out NSError **)error
{
	// *** MUST BE SAFE TO CALL ON NON-MAIN THREAD!
	const char* srcPath = src.su_fileSystemRepresentation;
	const char* dstPath = dst.su_fileSystemRepresentation;
	const char* dstContainerPath = dst.URLByDeletingLastPathComponent.su_fileSystemRepresentation;
	
	struct stat dstSB;
	stat(dstContainerPath, &dstSB);
	
	AuthorizationRef auth = NULL;
	OSStatus authStat = errAuthorizationDenied;
	while( authStat == errAuthorizationDenied )
	{
		authStat = AuthorizationCreate(NULL,
									   kAuthorizationEmptyEnvironment,
									   kAuthorizationFlagDefaults,
									   &auth);
	}
	
	BOOL res = (authStat == errAuthorizationSuccess);
	if (res)
	{
		char uidgid[42];
		snprintf(uidgid, sizeof(uidgid), "%d:%d", dstSB.st_uid, dstSB.st_gid);
		
		// Set permissions while it's still in source, so we have it with working and correct perms when it arrives at destination.
		const char* coParams[] = { "-R", uidgid, srcPath, NULL };
		res = su_AuthorizationExecuteWithPrivilegesAndWait( auth, "/usr/sbin/chown", kAuthorizationFlagDefaults, coParams );
		if( !res ) {
			SULog(@"Can't set permissions");
		}

		BOOL	haveDst = [dst checkResourceIsReachableAndReturnError:NULL];
		if( res && haveDst )	// If there's something at our tmp path (previous failed update or whatever) delete that first.
		{
			const char*	rmParams[] = { "-rf", dstPath, NULL };
			res = su_AuthorizationExecuteWithPrivilegesAndWait( auth, "/bin/rm", kAuthorizationFlagDefaults, rmParams );
			if( !res )
				SULog(@"Can't remove destination file");
		}
		
		if( res )	// Move!.
		{
			const char* mvParams[] = { "-f", srcPath, dstPath, NULL };
			res = su_AuthorizationExecuteWithPrivilegesAndWait( auth, "/bin/mv", kAuthorizationFlagDefaults, mvParams );
			if( !res )
				SULog(@"Can't move source file");
		}
		
		AuthorizationFree(auth, 0);
		
		if (!res)
		{
			// Something went wrong somewhere along the way, but we're not sure exactly where.
			NSString *errorMessage = [NSString stringWithFormat:@"Authenticated file move from %@ to %@ failed.", src, dst];
			if (error != NULL)
				*error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUAuthenticationFailure userInfo:[NSDictionary dictionaryWithObject:errorMessage forKey:NSLocalizedDescriptionKey]];
		}
	}
	else
	{
		if (error != NULL)
			*error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUAuthenticationFailure userInfo:[NSDictionary dictionaryWithObject:@"Couldn't get permission to authenticate." forKey:NSLocalizedDescriptionKey]];
	}
	return res;
}

#pragma mark - Remove

- (void)su_moveItemAtURLToTrash:(NSURL *)URL
{
	//SULog(@"Moving %@ to the trash.", path);
	[[NSWorkspace sharedWorkspace] recycleURLs:@[ URL ] completionHandler:^(NSDictionary *newURLs, NSError *error) {
		if (newURLs[URL]) return;

		NSFileManager *fm = [[NSFileManager alloc] init];
		BOOL didFindTrash = NO;
		NSURL *trashURL = [fm su_temporaryCopyURL:URL didFindTrash:&didFindTrash];
		if (didFindTrash) {
			NSError *err = nil;
			if (![fm su_moveItemAtURLWithForcedAuthentication:URL toURL:trashURL error:&err]) {
				SULog(@"Sparkle error: couldn't move %@ to the trash (%@). %@", URL, trashURL, err);
			}
		} else {
			SULog(@"Sparkle error: couldn't move %@ to the trash. This is often a sign of a permissions error.", URL);
		}
	}];
}

- (BOOL)su_removeItemAtURLWithForcedAuthentication:(NSURL *)src error:(out NSError **)error
{
	// *** MUST BE SAFE TO CALL ON NON-MAIN THREAD!
	const char* srcPath = src.su_fileSystemRepresentation;

	AuthorizationRef auth = NULL;
	OSStatus authStat = errAuthorizationDenied;
	while (authStat == errAuthorizationDenied) {
		authStat = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &auth);
	}

	BOOL res = NO;
	if (authStat == errAuthorizationSuccess) {
		// If there's something at our tmp path (previous failed update or whatever) delete that first.
		const char *rmParams[] = {"-rf", srcPath, NULL};
		res = su_AuthorizationExecuteWithPrivilegesAndWait(auth, "/bin/rm", kAuthorizationFlagDefaults, rmParams);
		if (!res) {
			SULog(@"Can't remove destination file");
		}

		AuthorizationFree(auth, 0);

		if (!res) {
			// Something went wrong somewhere along the way, but we're not sure exactly where.
			if (error != NULL) {
				NSString *errorMessage = [NSString stringWithFormat:@"Authenticated file remove from %@ failed.", src];
				*error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUAuthenticationFailure userInfo:@{
					NSLocalizedDescriptionKey: errorMessage
				}];
			}
		}
	} else {
		if (error != NULL) {
			NSString *errorMessage = [NSString stringWithFormat:@"Couldn't get permission to authenticate."];
			*error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUAuthenticationFailure userInfo:@{
					NSLocalizedDescriptionKey: errorMessage
				}];
		}
	}
	return res;
}

- (BOOL)su_removeItemAtURLWithAuthentication:(NSURL *)URL error:(out NSError **)error
{
	if (![self removeItemAtURL:URL error:error]) {
		return [self su_removeItemAtURLWithForcedAuthentication:URL error:error];
	}
	return YES;
}

#pragma mark - Extended Attributes

- (BOOL)su_removeExtendedAttribute:(const char*)name fromItemAtURL:(NSURL *)URL options:(int)options
{
	// *** MUST BE SAFE TO CALL ON NON-MAIN THREAD!
	const char *path = NULL;
	@try {
		path = [URL su_fileSystemRepresentation];
	}
	@catch (id exception) {
		// -[NSString fileSystemRepresentation] throws an exception if it's
		// unable to convert the string to something suitable.  Map that to
		// EDOM, "argument out of domain", which sort of conveys that there
		// was a conversion failure.
		errno = EDOM;
		return -1;
	}

	return (removexattr(path, name, options) == 0);
}

- (void)su_releaseItemAtURLFromQuarantine:(NSURL *)root
{
	// *** MUST BE SAFE TO CALL ON NON-MAIN THREAD!

	static const char *quarantineAttribute = "com.apple.quarantine";
	static const int removeXAttrOptions = XATTR_NOFOLLOW;

	[self su_removeExtendedAttribute:quarantineAttribute fromItemAtURL:root options:removeXAttrOptions];

	// Only recurse if it's actually a directory.  Don't recurse into a
	// root-level symbolic link.
	NSNumber *isDirectory;
	[root getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:NULL];
	if (!isDirectory.boolValue) {
		return;
	}

	for (NSURL *URL in [self enumeratorAtURL:root includingPropertiesForKeys:nil options:0 errorHandler:NULL]) {
		[self su_removeExtendedAttribute:quarantineAttribute fromItemAtURL:URL options:removeXAttrOptions];
	}
}

@end
