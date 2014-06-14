//
//  SUPipedUnarchiver.m
//  Sparkle
//
//  Created by Andy Matuschak on 6/16/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUPipedUnarchiver.h"
#import "SUUnarchiver_Private.h"
#import "SULog.h"


@implementation SUPipedUnarchiver

+ (NSString *)commandConformingToTypeOfPath:(NSString *)path
{
	NSString *extractZIP = @"ditto -x -k - \"$DESTINATION\"";
	NSString *extractTAR = @"tar -xC \"$DESTINATION\"";
	NSString *extractTBZ = @"tar -jxC \"$DESTINATION\"";
	NSString *extractTGZ = @"tar -zxC \"$DESTINATION\"";
	
	NSDictionary *typeSelectorDictionary = @{
		@".zip": extractZIP,
		@".tar": extractTAR,
		@".tar.gz": extractTGZ,
		@".tgz": extractTGZ,
		@".tar.bz2": extractTBZ,
		@".tbz": extractTBZ
    };

	NSString *lastPathComponent = [path lastPathComponent];
	__block NSString *ret = NULL;
	[typeSelectorDictionary enumerateKeysAndObjectsUsingBlock:^(NSString *currentType, NSString *obj, BOOL *stop) {
		if ([currentType length] > [lastPathComponent length]) return;
		if ([[lastPathComponent substringFromIndex:[lastPathComponent length] - [currentType length]] isEqualToString:currentType]) {
			ret = obj;
			*stop = YES;
		}
	}];
	return ret;
}

- (void)start
{
	NSString *command = [[self class] commandConformingToTypeOfPath:archivePath];
	if (!command) return;

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		[self extractArchivePipingDataToCommand:command];
	});
}

+ (BOOL)canUnarchivePath:(NSString *)path
{
	return ([self commandConformingToTypeOfPath:path] != nil);
}

// This method abstracts the types that use a command line tool piping data from stdin.
- (void)extractArchivePipingDataToCommand:(NSString *)command
{
	// *** GETS CALLED ON NON-MAIN THREAD!!!
	

	@autoreleasepool {
		FILE *fp = NULL, *cmdFP = NULL;
		char *oldDestinationString = NULL;

		SULog(@"Extracting %@ using '%@'",archivePath,command);
    
		// Get the file size.
		NSNumber *fs = [[[NSFileManager defaultManager] attributesOfItemAtPath:archivePath error:nil] objectForKey:NSFileSize];
		if (fs == nil) goto reportError;

		// Thank you, Allan Odgaard!
		// (who wrote the following extraction alg.)
		fp = fopen([archivePath fileSystemRepresentation], "r");
		if (!fp) goto reportError;

		oldDestinationString = getenv("DESTINATION");
		setenv("DESTINATION", [[archivePath stringByDeletingLastPathComponent] fileSystemRepresentation], 1);
		cmdFP = popen([command fileSystemRepresentation], "w");
		size_t written;
		if (!cmdFP) goto reportError;

		char buf[32*1024];
		size_t len;
		while((len = fread(buf, 1, 32*1024, fp)))
		{
			written = fwrite(buf, 1, len, cmdFP);
			if( written < len )
			{
				pclose(cmdFP);
				goto reportError;
			}

			[self performSelectorOnMainThread:@selector(notifyDelegateOfExtractedLength:) withObject:[NSNumber numberWithUnsignedLong:len] waitUntilDone:NO];
		}
		pclose(cmdFP);

		if( ferror( fp ) )
			goto reportError;

		[self performSelectorOnMainThread:@selector(notifyDelegateOfSuccess) withObject:nil waitUntilDone:NO];
		goto finally;

reportError:
		[self performSelectorOnMainThread:@selector(notifyDelegateOfFailure) withObject:nil waitUntilDone:NO];

finally:
		if (fp)
			fclose(fp);

		if (oldDestinationString)
			setenv("DESTINATION", oldDestinationString, 1);
		else
			unsetenv("DESTINATION");
	}
}

+ (void)load
{
	[self registerImplementation:self];
}

@end
