//
//  SUCodeSigningVerifier.h
//  Sparkle
//
//  Created by Andy Matuschak on 7/5/12.
//
//

#ifndef SUCODESIGNINGVERIFIER_H
#define SUCODESIGNINGVERIFIER_H

#import <Foundation/Foundation.h>

@interface SUCodeSigningVerifier : NSObject

- (BOOL)verifyBundleAtURL:(NSURL *)URL error:(out NSError **)outError;
- (BOOL)verifyBundle:(NSBundle *)bundle error:(out NSError **)outError;

@end

#endif
