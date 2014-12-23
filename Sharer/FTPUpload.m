#import "FTPUpload.h"

#import "CQKeychain.h"

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
	FTPUpload *upload = [[FTPUpload alloc] init];
	upload.source = file;
	return upload;
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

	NSURL *url = nil;
	NSString *port = [[NSUserDefaults standardUserDefaults] objectForKey:@"port"];
	if (!port.length) {
		port = @"21";
	}
	NSString *host = [[NSUserDefaults standardUserDefaults] objectForKey:@"server"];
	if (!([host.lowercaseString hasPrefix:@"ftp://"] || [host.lowercaseString hasPrefix:@"ftps://"])) {
		url = [NSURL URLWithString:[NSString stringWithFormat:@"ftp://%@:%@", host, port]];
	} else {
		url = [NSURL URLWithString:[NSString stringWithFormat:@"%@:%@", host, port]];
	}
	if (!url) {
		return NO;
	}

	NSString *remotePath = [[NSUserDefaults standardUserDefaults] objectForKey:@"remotePath"];
	if (remotePath.length) {
		url = [url URLByAppendingPathComponent:remotePath];
		if (!url) {
			return NO;
		}
	}

	url = [url URLByAppendingPathComponent:self.source.lastPathComponent];
	if (!url) {
		return NO;
	}	
	self.fileStream = [NSInputStream inputStreamWithFileAtPath:self.source];
  	if (!self.fileStream) {
  		return NO;
  	}
   
   [self.fileStream open];
   
	self.networkStream = CFBridgingRelease(CFWriteStreamCreateWithFTPURL(NULL, (__bridge CFURLRef) url));
	if (!self.networkStream) {
		return NO;
	}
	self.networkStream.delegate = self;

	NSString *username = [[NSUserDefaults standardUserDefaults] objectForKey:@"username"];
	if ([username length] != 0) {
		[self.networkStream setProperty:username forKey:(id)kCFStreamPropertyFTPUserName];
	}
	NSString *password = [[CQKeychain standardKeychain] passwordForServer:@"password" area:@"sharer"];
	if ([password length] != 0) {
		[self.networkStream setProperty:password forKey:(id)kCFStreamPropertyFTPPassword];
	}

	[self.networkStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
	[self.networkStream open];

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
	case NSStreamEventOpenCompleted: {
		[self.delegate uploadDidStart:self];
	} break;
	case NSStreamEventHasSpaceAvailable: {
		// If we don't have any data buffered, find some on disk
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

		// If we found data on disk to read, send write it back out to the network
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
		NSLog(@"%@: %@", aStream, aStream.streamError);
		[self stopSendWithStatus:@"Stream open error"];
	} break;
	case NSStreamEventHasBytesAvailable:
	case NSStreamEventNone:
	case NSStreamEventEndEncountered: {
		// ignore
	} break;
	}
}
@end
