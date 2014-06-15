//
//  SUInstaller.h
//  Sparkle
//
//  Created by Andy Matuschak on 4/10/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#ifndef SUINSTALLER_H
#define SUINSTALLER_H

#import <Cocoa/Cocoa.h>
#import "SUVersionComparisonProtocol.h"

@class SUHost;

@interface SUInstaller : NSObject

+ (NSURL *)		appURLInUpdateFolder:(NSURL *)updateFolder forHost:(SUHost *)host;
+ (void)		installFromUpdateFolder:(NSURL *)updateFolder overHost:(SUHost *)host installationURL:(NSURL *)installationURL delegate:delegate synchronously:(BOOL)synchronously versionComparator:(id <SUVersionComparison>)comparator;
+ (void)		finishInstallationToURL:(NSURL *)installationURL withResult:(BOOL)result host:(SUHost *)host error:(NSError *)error delegate:delegate;
+ (NSURL *)		updateFolderURL;

@end

@interface NSObject (SUInstallerDelegateInformalProtocol)
- (void)installerFinishedForHost:(SUHost *)host;
- (void)installerForHost:(SUHost *)host failedWithError:(NSError *)error;
@end

#endif
