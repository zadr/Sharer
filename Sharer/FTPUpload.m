#import "FTPUpload.h"

#include <CFNetwork/CFNetwork.h>

static NSUInteger const kSendBufferSize = 32768;

@interface FTPUpload () <NSStreamDelegate>
@property (atomic, copy, readwrite) NSString *source;

@property (atomic, strong, readwrite) NSOutputStream *networkStream;
@property (atomic, strong, readwrite) NSInputStream *fileStream;
@property (atomic, assign, readwrite) size_t bufferOffset;
@property (atomic, assign, readwrite) size_t bufferLimit;
@end

@implementation FTPUpload {
	uint8_t _buffer[kSendBufferSize];
}

@synthesize delegate;

+ (FTPUpload *) uploadFile:(NSString *) file {
	return nil;
}

#pragma mark - Status management

- (void) sendDidStopWithStatus:(NSString *) statusString {
	if (statusString == nil) {
		[self.delegate uploadDidFinish:self];
	} else {
		NSError *error = [NSError errorWithDomain:@"SErrorDomain" code:0 userInfo:@{ NSLocalizedDescriptionKey: statusString }];
		[self.delegate upload:self didFailWithError:error];
	}
}

#pragma mark - Networking

- (BOOL) isSending { 
	return (self.networkStream != nil);
}

- (BOOL) startOnQueue:(dispatch_queue_t) uploadQueue {
	if (self.isSending) {
		return NO;
	}

	self.fileStream = [NSInputStream inputStreamWithFileAtPath:self.source];

	[self.fileStream open];

//	self.networkStream = CFBridgingRelease(CFWriteStreamCreateWithFTPURL(NULL, (__bridge CFURLRef)self.destination));
//	assert(self.networkStream != nil);
//
//	if (self.credentials.user.length != 0) {
//		[self.networkStream setProperty:self.credentials.user forKey:(id)kCFStreamPropertyFTPUserName];
//	}
//	if (self.credentials.password.length != 0) {
//		[self.networkStream setProperty:self.credentials.password forKey:(id)kCFStreamPropertyFTPPassword];
//	}

	self.networkStream.delegate = self;
	[self.networkStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
	[self.networkStream open];

	[self.delegate uploadDidStart:self];

	return YES;
}

- (void) stop {
	[self stopSendWithStatus:nil notifyingDelegate:NO];
}

- (void) stopSendWithStatus:(NSString *) statusString {
	[self stopSendWithStatus:statusString notifyingDelegate:YES];
}

- (void) stopSendWithStatus:(NSString *) statusString notifyingDelegate:(BOOL) notifyingDelegate {
	if (self.networkStream != nil) {
		[self.networkStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
		self.networkStream.delegate = nil;

		[self.networkStream close];
		self.networkStream = nil;
	}
	if (self.fileStream != nil) {
		[self.fileStream close];
		self.fileStream = nil;
	}
	if (notifyingDelegate) {
		[self sendDidStopWithStatus:statusString];
	}
}

- (void) stream:(NSStream *) aStream handleEvent:(NSStreamEvent) eventCode {
	switch (eventCode) {
	case NSStreamEventHasBytesAvailable: {
		assert(NO); // should never happen for the output stream
	} break;
	case NSStreamEventHasSpaceAvailable: {
		// If we don't have any data buffered, go read the next chunk of data.
		if (self.bufferOffset == self.bufferLimit) {
			NSInteger bytesRead = [self.fileStream read:_buffer maxLength:kSendBufferSize];

			if (bytesRead == -1) {
				[self stopSendWithStatus:@"File read error"];
			} else if (bytesRead == 0) {
				[self stopSendWithStatus:nil];
			} else {
				self.bufferOffset = 0;
				self.bufferLimit = bytesRead;
			}
		}

		// If we're not out of data completely, send the next chunk.
		if (self.bufferOffset != self.bufferLimit) {
			NSInteger bytesWritten = [self.networkStream write:&_buffer[self.bufferOffset] maxLength:self.bufferLimit - self.bufferOffset];
			assert(bytesWritten != 0);
			if (bytesWritten == -1) {
				[self stopSendWithStatus:@"Network write error"];
			} else {
				self.bufferOffset += bytesWritten;
			}
		}
	} break;
	case NSStreamEventErrorOccurred: {
		[self stopSendWithStatus:@"Stream open error"];
	} break;
	case NSStreamEventOpenCompleted:
	case NSStreamEventNone:
	case NSStreamEventEndEncountered: {
		// ignore
	} break;
	}
}
@end
