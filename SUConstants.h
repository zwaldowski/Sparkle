//
//  SUConstants.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/16/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//


#ifndef SUCONSTANTS_H
#define SUCONSTANTS_H

// -----------------------------------------------------------------------------
//	Preprocessor flags:
// -----------------------------------------------------------------------------

// Turn off DSA signature check (practically invites man-in-the-middle attacks):
#define ENDANGER_USERS_WITH_INSECURE_UPDATES		0

// Sparkle usually doesn't allow downgrades as they're usually accidental, but
//	if your app has a downgrade function or URL handler, turn this on:
#define PERMIT_AUTOMATED_DOWNGRADES					0

// If your app file on disk is named "MyApp 1.1b4", Sparkle usually updates it
//	in place, giving you an app named 1.1b4 that is actually 1.2. Turn the
//	following on to always reset the name back to "MyApp":
#define NORMALIZE_INSTALLED_APP_NAME				0


#define TRY_TO_APPEND_VERSION_NUMBER				1

// -----------------------------------------------------------------------------
//	Compiler API macros
// -----------------------------------------------------------------------------

#ifndef SU_DESIGNATED_INITIALIZER
# if __has_attribute(objc_designated_initializer)
#  define SU_DESIGNATED_INITIALIZER __attribute__((objc_designated_initializer))
# else
#  define SU_DESIGNATED_INITIALIZER
# endif
#endif

#ifndef SU_REQUIRES_SUPER
# if __has_attribute(objc_requires_super)
#  define SU_REQUIRES_SUPER __attribute__((objc_requires_super))
# else
#  define SU_REQUIRES_SUPER
# endif
#endif

#ifndef SU_ALWAYS_INLINE
# if __has_attribute(always_inline) || defined(__GNUC__)
#  define SU_ALWAYS_INLINE static __inline__ __attribute__((always_inline))
# elif defined(__MWERKS__) || defined(__cplusplus)
#  define SU_ALWAYS_INLINE static inline
# elif defined(_MSC_VER)
#  define SU_ALWAYS_INLINE static __inline
# elif TARGET_OS_WIN32
#  define SU_ALWAYS_INLINE static __inline__
# endif
#endif

// -----------------------------------------------------------------------------
//	Notifications:
// -----------------------------------------------------------------------------

extern NSString *const SUTechnicalErrorInformationKey;

// -----------------------------------------------------------------------------
//	PList keys::
// -----------------------------------------------------------------------------

extern NSString *const SUFeedURLKey;
extern NSString *const SUHasLaunchedBeforeKey;
extern NSString *const SUShowReleaseNotesKey;
extern NSString *const SUSkippedVersionKey;
extern NSString *const SUScheduledCheckIntervalKey;
extern NSString *const SULastCheckTimeKey;
extern NSString *const SUPublicDSAKeyKey;
extern NSString *const SUPublicDSAKeyFileKey;
extern NSString *const SUAutomaticallyUpdateKey;
extern NSString *const SUAllowsAutomaticUpdatesKey;
extern NSString *const SUEnableAutomaticChecksKey;
extern NSString *const SUEnableAutomaticChecksKeyOld;
extern NSString *const SUEnableSystemProfilingKey;
extern NSString *const SUSendProfileInfoKey;
extern NSString *const SULastProfileSubmitDateKey;
extern NSString *const SUPromptUserOnFirstLaunchKey;
extern NSString *const SUFixedHTMLDisplaySizeKey;
extern NSString *const SUKeepDownloadOnFailedInstallKey;
extern NSString *const SUDefaultsDomainKey;

// -----------------------------------------------------------------------------
//	Errors:
// -----------------------------------------------------------------------------

extern NSString *const SUSparkleErrorDomain;
// Appcast phase errors.
extern OSStatus SUAppcastParseError;
extern OSStatus SUNoUpdateError;
extern OSStatus SUAppcastError;
extern OSStatus SURunningFromDiskImageError;

// Downlaod phase errors.
extern OSStatus SUTemporaryDirectoryError;

// Extraction phase errors.
extern OSStatus SUUnarchivingError;
extern OSStatus SUSignatureError;

// Installation phase errors.
extern OSStatus SUFileCopyFailure;
extern OSStatus SUAuthenticationFailure;
extern OSStatus SUMissingUpdateError;
extern OSStatus SUMissingInstallerToolError;
extern OSStatus SURelaunchError;
extern OSStatus SUInstallationError;
extern OSStatus SUDowngradeError;

// -----------------------------------------------------------------------------
//	Bundles and Strings
// -----------------------------------------------------------------------------

extern NSString *const SUBundleIdentifier;
extern NSString *const SULocalizedStringTableKey;

SU_ALWAYS_INLINE NSBundle *SUBundle(void)
{
	return [NSBundle bundleWithIdentifier:SUBundleIdentifier] ?: [NSBundle mainBundle];
}

#define SULocalizedString(key, comment) \
	[SUBundle() localizedStringForKey:(key) value:@"" table:SULocalizedStringTableKey]

#endif
