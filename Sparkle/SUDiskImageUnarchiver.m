//
//  SUDiskImageUnarchiver.m
//  Sparkle
//
//  Created by Andy Matuschak on 6/16/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUDiskImageUnarchiver.h"
#import "SUUnarchiver_Private.h"
#import "NTSynchronousTask.h"
#import "SULog.h"
#include <CoreServices/CoreServices.h>

@implementation SUDiskImageUnarchiver

+ (BOOL)canUnarchivePath:(NSString *)path
{
    return [[path pathExtension] isEqualToString:@"dmg"];
}

// Called on a non-main thread.
- (void)extractDMG
{
	@autoreleasepool {
        [self extractDMGWithPassword:nil];
    }
}

// Called on a non-main thread.
- (void)extractDMGWithPassword:(NSString *)__unused password
{
	@autoreleasepool {
        __block BOOL mountedSuccessfully = NO;
        __block NSString *mountPoint = nil;
        
        void (^cleanup)(void) = ^{
            if (mountedSuccessfully)
                [NSTask launchedTaskWithLaunchPath:@"/usr/bin/hdiutil" arguments:@[@"detach", mountPoint, @"-force"]];
            else
                SULog(@"Can't mount DMG %@", self.archivePath);
        };
        
        void (^reportError)(void) = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [self notifyDelegateOfFailure];
            });
            
            cleanup();
        };

        SULog(@"Extracting %@ as a DMG", self.archivePath);

        // get a unique mount point path
        FSRef tmpRef;
        NSFileManager *manager;
        NSError *error;
        NSArray *contents;
        
		do
		{
            // Using NSUUID would make creating UUIDs be done in Cocoa,
            // and thus managed under ARC. Sadly, the class is in 10.8 and later.
            CFUUIDRef uuid = CFUUIDCreate(NULL);
			if (uuid)
			{
                NSString *uuidString = CFBridgingRelease(CFUUIDCreateString(NULL, uuid));
				if (uuidString)
				{
                    mountPoint = [@"/Volumes" stringByAppendingPathComponent:uuidString];
                }
                CFRelease(uuid);
            }
		}
		while (noErr == FSPathMakeRefWithOptions((UInt8 *)[mountPoint fileSystemRepresentation], kFSPathMakeRefDoNotFollowLeafSymlink, &tmpRef, NULL));

        NSData *promptData = nil;
        promptData = [NSData dataWithBytes:"yes\n" length:4];

        NSArray *arguments = @[@"attach", self.archivePath, @"-mountpoint", mountPoint, /*@"-noverify",*/ @"-nobrowse", @"-noautoopen"];

        NSData *output = nil;
        NSInteger taskResult = -1;
		@try
		{
            NTSynchronousTask *task = [[NTSynchronousTask alloc] init];

            [task run:@"/usr/bin/hdiutil" directory:@"/" withArgs:arguments input:promptData];

            taskResult = [task result];
            output = [[task output] copy];
        }
        @catch (NSException *)
        {
            reportError();
            return;
        }

		if (taskResult != 0)
		{
            NSString *resultStr = output ? [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding] : nil;
            SULog(@"hdiutil failed with code: %ld data: <<%@>>", (long)taskResult, resultStr);
            reportError();
            return;
        }
        mountedSuccessfully = YES;

        // Now that we've mounted it, we need to copy out its contents.
        manager = [[NSFileManager alloc] init];
        contents = [manager contentsOfDirectoryAtPath:mountPoint error:&error];
		if (error)
		{
            SULog(@"Couldn't enumerate contents of archive mounted at %@: %@", mountPoint, error);
            reportError();
            return;
        }

		for (NSString *item in contents)
		{
            NSString *fromPath = [mountPoint stringByAppendingPathComponent:item];
            NSString *toPath = [[self.archivePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:item];

            // We skip any files in the DMG which are not readable.
            if (![manager isReadableFileAtPath:fromPath]) {
                continue;
            }

            SULog(@"copyItemAtPath:%@ toPath:%@", fromPath, toPath);

			if (![manager copyItemAtPath:fromPath toPath:toPath error:&error])
			{
                SULog(@"Couldn't copy item: %@ : %@", error, error.userInfo ? error.userInfo : @"");
                reportError();
                return;
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self notifyDelegateOfSuccess];
        });
        
        cleanup();
    }
}

- (void)start
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		[self extractDMG];
    });
}

+ (void)load
{
    [self registerImplementation:self];
}

- (BOOL)isEncrypted:(NSData *)resultData
{
    BOOL result = NO;
	if(resultData)
	{
        NSString *data = [[NSString alloc] initWithData:resultData encoding:NSUTF8StringEncoding];

        if ((data != nil) && !NSEqualRanges([data rangeOfString:@"passphrase-count"], NSMakeRange(NSNotFound, 0)))
		{
            result = YES;
        }
    }
    return result;
}

@end
