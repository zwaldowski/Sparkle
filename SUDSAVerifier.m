//
//  SUDSAVerifier.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/16/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "SUDSAVerifier.h"
#import <Cocoa/Cocoa.h>

#include <Security/cssm.h>

/* CDSA Specific */
static CSSM_CSP_HANDLE cdsaInit( void );
static void cdsaRelease( CSSM_CSP_HANDLE cspHandle );
static CSSM_KEY_PTR cdsaCreateKey(NSData *rawKey);
static void cdsaReleaseKey( CSSM_KEY_PTR key );
static BOOL cdsaVerifyKey( CSSM_CSP_HANDLE cspHandle, const CSSM_KEY_PTR key );
static BOOL cdsaVerifySignature( CSSM_CSP_HANDLE cspHandle, const CSSM_KEY_PTR key, NSData *msg, NSData *signature );
static NSData *cdsaCreateSHA1Digest( CSSM_CSP_HANDLE cspHandle, NSData *bytes );

/* Helper Functions */
static NSData *b64decode( NSString *str );
static NSData *rawKeyData( NSString *str );

@implementation SUDSAVerifier
#pragma mark -

+ (BOOL)validatePath:(NSString *)path withEncodedDSASignature:(NSString *)encodedSignature withPublicDSAKey:(NSString *)pkeyString
{
	if ( !encodedSignature || !pkeyString || !path ) return NO;

	__block CSSM_KEY_PTR pubKey = cdsaCreateKey(rawKeyData(pkeyString)); // Create the DSA key
	__block CSSM_CSP_HANDLE cspHandle = CSSM_INVALID_HANDLE;

	BOOL(^cleanup)(void) = ^{
		if (pubKey) {
			cdsaReleaseKey( pubKey );
			pubKey = NULL;
		}

		if (cspHandle) {
			cdsaRelease(cspHandle);
			cspHandle = NULL;
		}

		return NO;
	};

	NSData *pathData, *sigData, *hashData;
	if ( !pubKey ) return NO;
	if ( (cspHandle = cdsaInit()) == CSSM_INVALID_HANDLE ) { return cleanup(); }; // Init CDSA
	if ( !cdsaVerifyKey(cspHandle, pubKey) ) { return cleanup(); }; // Verify the key is valid
	if ( (pathData = [NSData dataWithContentsOfFile:path]) == nil ) { return cleanup(); }; // File data
	if ( (hashData = cdsaCreateSHA1Digest(cspHandle, pathData)) == nil) { return cleanup(); }; // Hash
	
	// Remove any line feeds from end of signature
	// (Not likely needed, but the verify _can_ fail if there is, so...)
	if ( [encodedSignature characterAtIndex:[encodedSignature length] - 1] == '\n' ) {
		NSMutableString *sig = [encodedSignature mutableCopy];
		while ( [sig characterAtIndex:[sig length] - 1] == '\n' )
			[sig deleteCharactersInRange:NSMakeRange([sig length] - 1, 1)];
		encodedSignature = sig;
	}
	if ( (sigData = b64decode(encodedSignature)) == nil ) { return cleanup(); }; // Decode signature
	
	// Verify the signature on the file
	BOOL result = cdsaVerifySignature( cspHandle, pubKey, hashData, sigData );
	cleanup();
	return result;
}

@end

#pragma mark -
#pragma mark Misc Helper Functions
#pragma mark -

static NSData *b64decode( NSString *str )
{
	if ( !str ) return nil;
	NSMutableData *retval = nil;
	NSData *input = [str dataUsingEncoding:NSUTF8StringEncoding];
	UInt8 *ibuf = (UInt8 *)[input bytes], *buf = NULL, *a = NULL;
	size_t len = [input length], i = 0, j = 0, size = ((len + 3) / 4) * 3;
	static UInt8 table[256] = {
        99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,  /* 00-0F */
        99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,  /* 10-1F */
        99,99,99,99,99,99,99,99,99,99,99,62,99,99,99,63,  /* 20-2F */
        52,53,54,55,56,57,58,59,60,61,99,99,99,99,99,99,  /* 30-3F */
        99, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9,10,11,12,13,14,  /* 40-4F */
        15,16,17,18,19,20,21,22,23,24,25,99,99,99,99,99,  /* 50-5F */
        99,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,  /* 60-6F */
        41,42,43,44,45,46,47,48,49,50,51,99,99,99,99,99,  /* 70-7F */
        99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,  /* 80-8F */
        99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,  /* 90-9F */
        99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,  /* A0-AF */
        99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,  /* B0-BF */
        99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,  /* C0-CF */
        99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,  /* D0-DF */
        99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,  /* E0-EF */
        99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99   /* F0-FF */
    };
	
	retval = [NSMutableData dataWithLength:size];
	buf = [retval mutableBytes];
	
	if ( (a = calloc(4, sizeof(UInt8))) == NULL ) return nil;
	
	do {
		size_t ai = 0;
		a[0] = a[1] = a[2] = a[3] = 0;
		do {
			UInt8 d = table[ibuf[i++]];
			if ( d != 99 ) {
				a[ai] = d;
				ai++;
				if ( ai == 4 ) break;
			}
		} while ( i < len );
		if ( ai >= 2 ) buf[j] = (a[0] << 2) | (a[1] >> 4);
		if ( ai >= 3 ) buf[j+1] = (a[1] << 4) | (a[2] >> 2);
		if ( ai >= 4 ) buf[j+2] = (a[2] << 6) | a[3];
		j += ai-1;
	} while ( i < len );
	
	free( a );
	if ( j < size ) [retval setLength:j];
	
	return retval;
}

static NSData *rawKeyData( NSString *key )
{
	if ( (key == nil) || ([key length] == 0) ) return nil;
	NSMutableString *t = [key mutableCopy];
	
	// Remove the PEM guards (if present)
	[t replaceOccurrencesOfString:@"-" withString:@"" options:NSLiteralSearch range:NSMakeRange(0, [t length])];
	[t replaceOccurrencesOfString:@"BEGIN PUBLIC KEY" withString:@"" options:NSLiteralSearch range:NSMakeRange(0, [t length])];
	[t replaceOccurrencesOfString:@"END PUBLIC KEY" withString:@"" options:NSLiteralSearch range:NSMakeRange(0, [t length])];
	
	// Remove any line feeds from the beginning of the key
	while ( [t characterAtIndex:0] == '\n' ) {
		[t deleteCharactersInRange:NSMakeRange(0, 1)];
	}
	
	// Remove any line feeds at the end of the key
	while ( [t characterAtIndex:[t length] - 1] == '\n' ) {
		[t deleteCharactersInRange:NSMakeRange([t length] - 1, 1)];
	}
	
	// Remove whitespace around each line of the key.
	NSMutableArray *pkeyTrimmedLines = [NSMutableArray array];
	NSCharacterSet *whiteSet = [NSCharacterSet whitespaceCharacterSet];
	for (NSString *pkeyLine in [t componentsSeparatedByString:@"\n"])
	{
		[pkeyTrimmedLines addObject:[pkeyLine stringByTrimmingCharactersInSet:whiteSet]];
	}
	key = [pkeyTrimmedLines componentsJoinedByString:@"\n"]; // Put them back together.
	
	// Base64 decode to return the raw key bits (DER format rather than PEM)
	return b64decode( key );
}

#pragma mark -
#pragma mark CDSA
#pragma mark -

/* Helper Functions */
SU_ALWAYS_INLINE CSSM_DATA su_createData(NSData * bytes);

/* Memory functions */
static void *su_malloc( CSSM_SIZE size, void *ref );
static void su_free( void *ptr, void *ref );
static void *su_realloc( void *ptr, CSSM_SIZE size, void *ref );
static void *su_calloc( uint32 num, CSSM_SIZE size, void *ref );

/* Constants & Typedefs */
static CSSM_VERSION vers = { 2, 0 };
static const CSSM_GUID su_guid = { 'S', 'p', 'a', { 'r', 'k', 'l', 'e', 0, 0, 0, 0 } };
static CSSM_BOOL cssmInited = CSSM_FALSE;
static const CSSM_DATA CSSM_DATA_EMPTY = { .Data = NULL, .Length = 0};

static CSSM_API_MEMORY_FUNCS SU_MemFuncs = {
	su_malloc,
	su_free,
	su_realloc,
	su_calloc,
	NULL
};

static CSSM_CSP_HANDLE cdsaInit( void )
{
	CSSM_CSP_HANDLE cspHandle = CSSM_INVALID_HANDLE;
	CSSM_RETURN crtn;
	
	if ( !cssmInited ) {
		CSSM_PVC_MODE pvcPolicy = CSSM_PVC_NONE;
		crtn = CSSM_Init( &vers, CSSM_PRIVILEGE_SCOPE_NONE, &su_guid, CSSM_KEY_HIERARCHY_NONE, &pvcPolicy, NULL );
		if ( crtn ) return CSSM_INVALID_HANDLE;
		cssmInited = CSSM_TRUE;
	}
	
	crtn = CSSM_ModuleLoad( &gGuidAppleCSP, CSSM_KEY_HIERARCHY_NONE, NULL, NULL );
	if ( crtn ) return CSSM_INVALID_HANDLE;
	
	crtn = CSSM_ModuleAttach( &gGuidAppleCSP, &vers, &SU_MemFuncs, 0, CSSM_SERVICE_CSP, 0, CSSM_KEY_HIERARCHY_NONE, NULL, 0, NULL, &cspHandle );
	if ( crtn ) return CSSM_INVALID_HANDLE;
	
	return cspHandle;
}

static void cdsaRelease( CSSM_CSP_HANDLE cspHandle )
{
	if ( CSSM_ModuleDetach(cspHandle) != CSSM_OK ) return;
	CSSM_ModuleUnload( &gGuidAppleCSP, NULL, NULL );
}

static CSSM_KEY_PTR cdsaCreateKey(NSData *rawKey)
{
	if ( !rawKey || !rawKey.length) return NULL;
	
	CSSM_KEY_PTR retval = NULL;

	if ( (retval = su_malloc(sizeof(CSSM_KEY), NULL)) == NULL ) return NULL;

	CSSM_KEYHEADER_PTR hdr = &(retval->KeyHeader);
	bzero(hdr, sizeof(CSSM_KEYHEADER));
	hdr->HeaderVersion = CSSM_KEYHEADER_VERSION;
	hdr->CspId = su_guid;
	hdr->BlobType = CSSM_KEYBLOB_RAW;
	hdr->Format = CSSM_KEYBLOB_RAW_FORMAT_X509;
	hdr->AlgorithmId = CSSM_ALGID_DSA;
	hdr->KeyClass = CSSM_KEYCLASS_PUBLIC_KEY;
	hdr->KeyAttr = CSSM_KEYATTR_EXTRACTABLE;
	hdr->KeyUsage = CSSM_KEYUSE_ANY;

	retval->KeyData = su_createData(rawKey);
	
	return retval;
}

static void cdsaReleaseKey( CSSM_KEY_PTR key )
{
	if ( key ) {
		if ( key->KeyData.Data ) su_free( key->KeyData.Data, NULL );
		su_free( key, NULL );
	}
}

BOOL cdsaVerifyKey( CSSM_CSP_HANDLE cspHandle, CSSM_KEY_PTR key )
{
	if ( key->KeyHeader.LogicalKeySizeInBits == 0 ) {
		CSSM_RETURN crtn;
		CSSM_KEY_SIZE keySize;
		
		/* This will fail if the key isn't valid */
		crtn = CSSM_QueryKeySizeInBits( cspHandle, CSSM_INVALID_HANDLE, key, &keySize );
		if ( crtn ) return NO;
		key->KeyHeader.LogicalKeySizeInBits = keySize.LogicalKeySizeInBits;
	}
	return YES;
}

static BOOL cdsaVerifySignature( CSSM_CSP_HANDLE cspHandle, const CSSM_KEY_PTR key, NSData *msg, NSData *signature )
{
	CSSM_CC_HANDLE ccHandle = CSSM_INVALID_HANDLE;
	CSSM_DATA plain = su_createData(msg), cipher = su_createData(signature);

	BOOL(^cleanup)(void) = ^{
		if ( ccHandle ) CSSM_DeleteContext( ccHandle );
		return NO;
	};
	
	if (CSSM_CSP_CreateSignatureContext(cspHandle, CSSM_ALGID_SHA1WithDSA, NULL, key, &ccHandle) != CSSM_OK) {
		return cleanup();
	}
	
	BOOL ret = ( CSSM_VerifyData(ccHandle, &plain, 1, CSSM_ALGID_NONE, &cipher) == CSSM_OK );
	cleanup();
	return ret;
}

static NSData *cdsaCreateSHA1Digest( CSSM_CSP_HANDLE cspHandle, NSData *bytes)
{
	if (!bytes) return nil;

	CSSM_CC_HANDLE ccHandle = CSSM_INVALID_HANDLE;
	CSSM_DATA data = su_createData(bytes), dgst = CSSM_DATA_EMPTY;

	id(^cleanup)(void) = ^id{
		if (ccHandle) CSSM_DeleteContext( ccHandle );
		return nil;
	};
	
	if ((CSSM_CSP_CreateDigestContext(cspHandle, CSSM_ALGID_SHA1, &ccHandle) != CSSM_OK)) {
		return cleanup();
	}

	NSData *ret = nil;
	if (CSSM_DigestData(ccHandle, &data, 1, &dgst) == CSSM_OK ) {
		ret = [NSData dataWithBytesNoCopy:dgst.Data length:dgst.Length freeWhenDone:YES];
	} else {
		if (dgst.Data) free(dgst.Data);
	}
	cleanup();
	return ret;
}

/* Memory Functions */
static void *su_malloc( CSSM_SIZE size, void *ref )
{
	return malloc( size );
}

static void su_free( void *ptr, void *ref )
{
	free( ptr );
}

static void *su_realloc( void *ptr, CSSM_SIZE size, void *ref )
{
	return realloc( ptr, size );
}

static void *su_calloc( uint32 num, CSSM_SIZE size, void *ref )
{
	return calloc( num, size );
}

/* Helper Functions */
SU_ALWAYS_INLINE CSSM_DATA su_createData(NSData * bytes)
{
	if (!bytes) return CSSM_DATA_EMPTY;
	return (CSSM_DATA){
		.Data = (UInt8 *)bytes.bytes,
		.Length = bytes.length
	};
}
