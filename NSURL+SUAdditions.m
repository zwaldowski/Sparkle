//
//  NSURL+SUAdditions.m
//  Sparkle
//
//  Created by Zach Waldowski on 6/14/14.
//  Copyright (c) 2014 Big Nerd Ranch. All rights reserved.
//

#import "NSURL+SUAdditions.h"

static BOOL hasNativeFSR(void) {
	static BOOL hasNativeFSR = NO;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		hasNativeFSR = [NSURL respondsToSelector:@selector(fileSystemRepresentation)];
	});
	return hasNativeFSR;
}

@implementation NSURL (SUAdditions)

+ (NSURL *)su_fileURLWithFileSystemRepresentation:(const char *)path isDirectory:(BOOL)isDir relativeToURL:(NSURL *)baseURL
{
	if (hasNativeFSR()) return [self fileURLWithFileSystemRepresentation:path isDirectory:isDir relativeToURL:baseURL];
	return [[self alloc] su_initFileURLWithFileSystemRepresentation:path isDirectory:isDir relativeToURL:baseURL];
}

- (instancetype)su_initFileURLWithFileSystemRepresentation:(const char *)path isDirectory:(BOOL)isDir relativeToURL:(NSURL *)baseURL
{
	if (hasNativeFSR()) return (self = [self initFileURLWithFileSystemRepresentation:path isDirectory:isDir relativeToURL:baseURL]);
	if (!baseURL.isFileURL) {
		return (self = (__bridge_transfer NSURL *)CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)path, strlen(path), !!isDir));
	}
	return (self = (__bridge_transfer NSURL *)CFURLCreateFromFileSystemRepresentationRelativeToBase(NULL, (const UInt8 *)path, strlen(path), !!isDir, (__bridge CFURLRef)baseURL));
}

- (const char *)su_fileSystemRepresentation
{
	if (hasNativeFSR()) return [self fileSystemRepresentation];

	CFURLRef URL = (__bridge CFURLRef)self;

	__strong void *(^createBuf)(NSUInteger) = ^void *(NSUInteger len){
		void *buf = NSAllocateCollectable(len, 0);
		if (!buf) {
			[NSException raise:NSMallocException format:@"%@: unable to allocate memory for length (%ld)", NSStringFromClass(self.class), len];
		}

		return (void *)[[NSData dataWithBytesNoCopy:buf length:len] bytes];
	};

	static const NSUInteger baseLen = 1024;
	void *buf = createBuf(baseLen);

	if (!CFURLGetFileSystemRepresentation(URL, true, buf, baseLen)) {
		CFURLRef absoluteURL = CFURLCopyAbsoluteURL(URL);
		if (!absoluteURL) return NULL;

		CFStringRef str = CFURLCopyFileSystemPath(absoluteURL, 0);
		if (!str) {
			CFRelease(absoluteURL);
			return NULL;
		}

		CFIndex maxLen = CFStringGetMaximumSizeOfFileSystemRepresentation(str);
		CFRelease(str);
		if (maxLen == kCFNotFound) {
			CFRelease(absoluteURL);
			return NULL;
		}

		buf = createBuf((NSUInteger)maxLen);
		if (!CFURLGetFileSystemRepresentation(absoluteURL, true, buf, maxLen)) {
			[NSException raise:NSInvalidArgumentException format:@"%@: conversion failed for %@", NSStringFromClass(self.class), self];
		}
		CFRelease(absoluteURL);
	}
	return buf;
}

- (BOOL)su_getFileSystemRepresentation:(char *)buffer maxLength:(NSUInteger)maxBufferLength
{
	if (hasNativeFSR()) return [self getFileSystemRepresentation:buffer maxLength:maxBufferLength];

	CFURLRef URL = (__bridge CFURLRef)self;
	return !!CFURLGetFileSystemRepresentation(URL, YES, (UInt8 *)buffer, maxBufferLength);
}

@end
