#import "SFTPUpload.h"

#import "CQKeychain.h"
#import <NMSSH/NMSSH.h>

//@protocol UploadDelegate <NSObject>
//@required
//- (void) uploadDidStart:(id <Upload>) upload;
//- (void) upload:(id <Upload>) upload didFailWithError:(NSError *) error;
//@end

@interface SFTPUpload ()
@property (atomic, copy, readwrite) NSString *source;
@property (atomic, strong) NMSSHSession *session;
@property (atomic, strong) NMSFTP *sftpSession;
@end

@implementation SFTPUpload
@synthesize delegate;

+ (id <Upload>) uploadFile:(NSString *) file {
	SFTPUpload *upload = [[SFTPUpload alloc] init];
	upload.source = file;
	return upload;
}

- (BOOL) isSending {
	return NO;
}

- (BOOL) startOnQueue:(dispatch_queue_t) uploadQueue {
	NSInputStream *inputStream = [NSInputStream inputStreamWithFileAtPath:self.source];
	if (!inputStream) {
		NSLog(@"no input stream for %@", self.source);
		return NO;
	}

	NSString *server = [[NSUserDefaults standardUserDefaults] objectForKey:@"server"];
	NSString *port = [[NSUserDefaults standardUserDefaults] objectForKey:@"port"];
	if (!port.length) {
		port = @"22";
	}

	NSString *hostport = [NSString stringWithFormat:@"%@:%@", server, port];
	NSString *username = [[NSUserDefaults standardUserDefaults] objectForKey:@"username"];
	NMSSHSession *session = [NMSSHSession connectToHost:hostport withUsername:username];
	if (session.isConnected) {
		NSString *password = [[CQKeychain standardKeychain] passwordForServer:@"password" area:@"sharer"];
		[session authenticateByPassword:password];

		if (!session.isAuthorized) {
			// try with standard key pair
			NSString *defaultPubkeyPath = [@"~/.ssh/id_rsa.pub" stringByExpandingTildeInPath];
			NSString *defaultPrivkeyPath = [@"~/.ssh/id_rsa" stringByExpandingTildeInPath];
			if ([[NSFileManager defaultManager] fileExistsAtPath:defaultPubkeyPath] && [[NSFileManager defaultManager] fileExistsAtPath:defaultPrivkeyPath]) {
				[session authenticateByPublicKey:defaultPubkeyPath privateKey:defaultPrivkeyPath andPassword:password];
			}
		}
	} else {
		NSLog(@"Unable to connect");
		return NO;
	}

	if (!session.isAuthorized) {
		NSLog(@"Unable to authorize");
		return NO;
	}

	NMSFTP *sftpSession = [NMSFTP connectWithSession:session];
	if (!sftpSession) {
		NSLog(@"Unable to make an SFTP session");
		return NO;
	}

	self.session = session;
	self.sftpSession = sftpSession;

	__weak __typeof__((self)) weakSelf = self;
	dispatch_async(uploadQueue, ^{
		NSUInteger fileLength = [[[NSFileManager defaultManager] attributesOfItemAtPath:self.source error:nil] fileSize];
		NSString *remotePath = [[NSUserDefaults standardUserDefaults] objectForKey:@"remotePath"];
		if (!remotePath.length) {
			remotePath = @"";
		}

		__strong __typeof__((weakSelf)) strongSelf = weakSelf;
		__strong __typeof__((strongSelf.delegate)) strongDelegate = strongSelf.delegate;

		[strongDelegate uploadDidStart:strongSelf];

		NSString *fullRemotePath = [remotePath stringByAppendingPathComponent:strongSelf.source.lastPathComponent];
		BOOL wroteStream = [sftpSession writeStream:inputStream toFileAtPath:fullRemotePath progress:^BOOL(NSUInteger progress) {
			if (progress == fileLength) {
				dispatch_async(dispatch_get_main_queue(), ^{ // give the sftp session a chance to finish up any remaining work it has before we remove our references to it
					__strong __typeof__((weakSelf)) strongAsyncSelf = weakSelf;
					__strong __typeof__((strongAsyncSelf.delegate)) strongAsyncDelegate = strongAsyncSelf.delegate;

					[sftpSession disconnect];
					[session disconnect];

					[strongAsyncDelegate uploadDidFinish:strongAsyncSelf];

					strongAsyncSelf.sftpSession = nil;
					strongAsyncSelf.session = nil;
				});
			}
			
			return YES;
		}];

		if (!wroteStream) {
			[strongDelegate upload:strongSelf didFailWithError:nil]; // NMSSH doesn't bubble the error code up from libssh2
		}
	});

	return YES;
}

- (void) stop {
	[self.sftpSession disconnect];
	[self.session disconnect];
}
@end
