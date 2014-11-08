//
//  NSURL+SUAdditions.h
//  Sparkle
//
//  Created by Zach Waldowski on 6/14/14.
//  Copyright (c) 2014 Big Nerd Ranch. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSURL (SUAdditions)

- (instancetype)su_initFileURLWithFileSystemRepresentation:(const char *)path isDirectory:(BOOL)isDir relativeToURL:(NSURL *)baseURL __attribute__((objc_method_family(init)));
+ (NSURL *)su_fileURLWithFileSystemRepresentation:(const char *)path isDirectory:(BOOL) isDir relativeToURL:(NSURL *)baseURL __attribute__((objc_method_family(new)));

@property (readonly) const char *su_fileSystemRepresentation NS_RETURNS_INNER_POINTER;
- (BOOL)su_getFileSystemRepresentation:(char *)buffer maxLength:(NSUInteger)maxBufferLength;

@end
