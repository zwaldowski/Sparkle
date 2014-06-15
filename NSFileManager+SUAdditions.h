//
//  NSFileManager+SUAdditions.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/9/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSURL *SUUniqueURLInDirectory(NSURL *parent, NSString *prefix, NSString *extension);

@interface NSFileManager (SUAdditions)

- (BOOL)su_copyItemAtURLWithAuthentication:(NSURL *)srcURL toURL:(NSURL *)dstURL error:(out NSError **)error;

- (void)su_moveItemAtURLToTrash:(NSURL *)URL;

- (BOOL)su_removeItemAtURLWithAuthentication:(NSURL *)URL error:(out NSError **)error;

@end
