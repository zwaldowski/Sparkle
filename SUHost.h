//
//  SUHost.h
//  Sparkle
//
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUUpdater.h"
#import "SUAppcast.h"
#import "SUAppcastItem.h"
#import "SUVersionComparisonProtocol.h"

@interface SUHost : NSObject

+ (NSString *)systemVersionString;

- (instancetype)initWithBundle:(NSBundle *)aBundle;
@property (nonatomic, readonly) NSBundle *bundle;

@property (nonatomic, readonly) NSURL *bundleURL;
@property (nonatomic, readonly) NSURL *appSupportURL;
@property (nonatomic, readonly) NSURL *installationURL;
- (NSString *)name;
- (NSString *)version;
- (NSString *)displayVersion;
- (NSImage *)icon;
- (BOOL)isRunningOnReadOnlyVolume;
- (BOOL)isBackgroundApplication;
- (NSString *)publicDSAKey;
- (NSArray *)systemProfile;

- (id)objectForInfoDictionaryKey:(NSString *)key;
- (BOOL)boolForInfoDictionaryKey:(NSString *)key;
- (id)objectForUserDefaultsKey:(NSString *)defaultName;
- (void)setObject:(id)value forUserDefaultsKey:(NSString *)defaultName;
- (BOOL)boolForUserDefaultsKey:(NSString *)defaultName;
- (void)setBool:(BOOL)value forUserDefaultsKey:(NSString *)defaultName;
- (id)objectForKey:(NSString *)key;
- (BOOL)boolForKey:(NSString *)key;
@end
