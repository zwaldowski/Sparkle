//
//  SUUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 5/7/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUUpdateDriver.h"
#import "SUHost.h"

NSString *const SUUpdateDriverFinishedNotification = @"SUUpdateDriverFinished";

@interface SUUpdateDriver ()

@property (weak) SUUpdater *updater;
@property (copy) NSURL *appcastURL;
@property (getter=isInterruptible) BOOL interruptible;

@end

@implementation SUUpdateDriver

@synthesize updater;
@synthesize host;
@synthesize interruptible;
@synthesize finished;
@synthesize appcastURL;

- (instancetype)initWithUpdater:(SUUpdater *)anUpdater
{
    if ((self = [super init])) {
        self.updater = anUpdater;
    }
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@ <%@, %@>", NSStringFromClass(self.class), self.host.bundleURL, self.host.installationURL];
}

- (void)checkForUpdatesAtURL:(NSURL *)URL host:(SUHost *)h
{
    self.appcastURL = URL;
    self.host = h;
}

- (void)abortUpdate
{
    [self setValue:@YES forKey:@"finished"];
    [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdateDriverFinishedNotification object:self];
}

@end
