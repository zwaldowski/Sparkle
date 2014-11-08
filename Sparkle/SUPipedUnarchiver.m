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

static const CFStringRef SUTypeTarArchive = CFSTR("public.tar-archive");

+ (NSString *)commandForURL:(NSURL *)URL
{
    NSString *UTI = nil;
    if (![URL getResourceValue:&UTI forKey:NSURLTypeIdentifierKey error:NULL]) {
        return nil;
    }
    return UTI;
}

+ (NSString *)commandConformingToType:(NSString *)UTI
{
    static dispatch_once_t onceToken;
    static NSDictionary *commandDictionary;
    dispatch_once(&onceToken, ^{
        commandDictionary = @{
            (__bridge id)kUTTypeZipArchive: @"ditto -x -k - \"$DESTINATION\"",
            (__bridge id)kUTTypeBzip2Archive: @"tar -jxC \"$DESTINATION\"",
            (__bridge id)kUTTypeGNUZipArchive: @"tar -zxC \"$DESTINATION\"",
            (__bridge id)SUTypeTarArchive: @"tar -xC \"$DESTINATION\""
        };
    });
    
    __block NSString *ret = nil;
    if ((ret = commandDictionary[UTI])) {
        return ret;
    }
    
    [commandDictionary enumerateKeysAndObjectsUsingBlock:^(NSString *type, NSString *command, BOOL *stop) {
        if (!UTTypeConformsTo((__bridge CFStringRef)UTI, (__bridge CFStringRef)type)) {
            return;
        }
        
        ret = command;
        *stop = YES;
    }];
    
    return ret;
}

+ (SEL)selectorConformingToTypeOfPath:(NSString *)path DEPRECATED_ATTRIBUTE
{
    static NSDictionary *typeSelectorDictionary;
    if (!typeSelectorDictionary)
        typeSelectorDictionary = @{ @".zip": @"extractZIP",
                                    @".tar": @"extractTAR",
                                    @".tar.gz": @"extractTGZ",
                                    @".tgz": @"extractTGZ",
                                    @".tar.bz2": @"extractTBZ",
                                    @".tbz": @"extractTBZ" };

    NSString *lastPathComponent = [path lastPathComponent];
	for (NSString *currentType in typeSelectorDictionary)
	{
		if ([currentType length] > [lastPathComponent length]) continue;
        if ([[lastPathComponent substringFromIndex:[lastPathComponent length] - [currentType length]] isEqualToString:currentType])
            return NSSelectorFromString(typeSelectorDictionary[currentType]);
    }
    return NULL;
}

- (void)start
{
    NSURL *URL = [NSURL fileURLWithPath:self.archivePath];
    NSString *command = [self.class commandForURL:URL];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self extractArchivePipingDataToCommand:command];
    });
}

+ (BOOL)canUnarchivePath:(NSString *)path
{
    NSURL *URL = [NSURL fileURLWithPath:path];
    return ([self commandForURL:URL] != nil);
}

// This method abstracts the types that use a command line tool piping data from stdin.
- (void)extractArchivePipingDataToCommand:(NSString *)command
{
    // *** GETS CALLED ON NON-MAIN THREAD!!!
	@autoreleasepool {
        FILE *fp = NULL, *cmdFP = NULL;
        char *oldDestinationString = NULL;
        // We have to declare these before a goto to prevent an error under ARC.
        // No, we cannot have them in the dispatch_async calls, as the goto "jump enters
        // lifetime of block which strongly captures a variable"
        dispatch_block_t delegateSuccess = ^{
            [self notifyDelegateOfSuccess];
        };
        dispatch_block_t delegateFailure = ^{
            [self notifyDelegateOfFailure];
        };

        SULog(@"Extracting %@ using '%@'", self.archivePath, command);

        // Get the file size.
        NSNumber *fs = [[NSFileManager defaultManager] attributesOfItemAtPath:self.archivePath error:nil][NSFileSize];
		if (fs == nil) goto reportError;

        // Thank you, Allan Odgaard!
        // (who wrote the following extraction alg.)
        fp = fopen([self.archivePath fileSystemRepresentation], "r");
		if (!fp) goto reportError;

        oldDestinationString = getenv("DESTINATION");
        setenv("DESTINATION", [[self.archivePath stringByDeletingLastPathComponent] fileSystemRepresentation], 1);
        cmdFP = popen([command fileSystemRepresentation], "w");
        size_t written;
		if (!cmdFP) goto reportError;

        char buf[32 * 1024];
        size_t len;
		while((len = fread(buf, 1, 32*1024, fp)))
		{
            written = fwrite(buf, 1, len, cmdFP);
			if( written < len )
			{
                pclose(cmdFP);
                goto reportError;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
				[self notifyDelegateOfExtractedLength:len];
            });
        }
        pclose(cmdFP);

        if (ferror(fp)) {
            goto reportError;
        }

        dispatch_async(dispatch_get_main_queue(), delegateSuccess);
        goto finally;

    reportError:
        dispatch_async(dispatch_get_main_queue(), delegateFailure);

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
