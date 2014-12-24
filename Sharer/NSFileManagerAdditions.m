#import "NSFileManagerAdditions.h"

#include <CoreFoundation/CoreFoundation.h>
#include <CommonCrypto/CommonDigest.h>
#include <CommonCrypto/CommonHMAC.h>

@implementation NSFileManager (Additions)
- (NSString *) sha1sumOfFileAtPath:(NSString *) path {
	CFStringRef filePath = (__bridge CFStringRef)path;
	CFURLRef fileURL = CFURLCreateWithFileSystemPath(NULL, filePath, kCFURLPOSIXPathStyle, false);
	if (!fileURL) {
		return nil;
	}

	CFReadStreamRef readStream = CFReadStreamCreateWithFile(kCFAllocatorDefault, (CFURLRef)fileURL);
	if (!readStream) {
		return nil;
	}

	if (!CFReadStreamOpen(readStream)) {
		return nil;
	}

	CC_SHA1_CTX hashObject;
	CC_SHA1_Init(&hashObject);

	bool hasMoreData = true;
	while (hasMoreData) {
		uint8_t buffer[4096];
		CFIndex readBytesCount = CFReadStreamRead(readStream, (UInt8 *)buffer, (CFIndex)sizeof(buffer));
		if (readBytesCount == -1) {
			break;
		}
		if (readBytesCount == 0) {
			hasMoreData = false;
			continue;
		}
		CC_SHA1_Update(&hashObject, (const void *)buffer, (CC_LONG)readBytesCount);
	}

	unsigned char digest[CC_SHA1_DIGEST_LENGTH];
	CC_SHA1_Final(digest, &hashObject);

	if (hasMoreData) {
		return nil;
	}

	NSMutableString *result = [NSMutableString stringWithCapacity:(2 * sizeof(digest))];
	for (size_t i = 0; i < sizeof(digest); ++i) {
		[result appendFormat:@"%02lx", (unsigned long)digest[i]];
	}

	if (readStream) {
		CFReadStreamClose(readStream);
		CFRelease(readStream);
	}

	if (fileURL) {
		CFRelease(fileURL);
	}

	return result;
}

- (NSString *) remoteNameForFileAtPath:(NSString *) path withOptionalSalt:(NSString *) salt {
	if (![[NSUserDefaults standardUserDefaults] boolForKey:@"SObsfucateURL"]) {
		return path.lastPathComponent;
	}

	NSString *sha1sum = [self sha1sumOfFileAtPath:path];

	const char *key  = [salt cStringUsingEncoding:NSASCIIStringEncoding];
	const char *data = [sha1sum cStringUsingEncoding:NSASCIIStringEncoding];
	unsigned char hmac[CC_SHA256_DIGEST_LENGTH];

	CCHmac(kCCHmacAlgSHA256, key, strlen(key), data, strlen(data), hmac);

	NSData *HMACData = [[NSData alloc] initWithBytes:hmac length:sizeof(hmac)];

	const unsigned char *buffer = (const unsigned char *)HMACData.bytes;

	NSMutableString *HMACString = [NSMutableString stringWithCapacity:(HMACData.length * 2)];
	for (NSUInteger i = 0; i < HMACData.length; ++i) {
		[HMACString appendFormat:@"%02lx", (unsigned long)buffer[i]];
	}

	return [HMACString stringByAppendingPathExtension:path.pathExtension];
}
@end
