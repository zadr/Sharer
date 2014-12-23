#import "AppDelegate.h"

#import "DraggableButton.h"

#import <NMSSH/NMSSH.h>

@interface AppDelegate () <DraggableDelegate>
@property (weak) IBOutlet NSWindow *window;
@property (strong) NSStatusItem *statusItem;

@property (atomic) NSInteger numberOfDots;

@property (strong) dispatch_queue_t uploadQueue;
@property (strong) NSMutableSet *activeSessions;
@end

@implementation AppDelegate
- (void) applicationDidFinishLaunching:(NSNotification *) notification {
	self.uploadQueue = dispatch_queue_create("net.thisismyinter.upload", DISPATCH_QUEUE_CONCURRENT);
	self.activeSessions = [NSMutableSet set];

	self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];

	DraggableButton *button = [[DraggableButton alloc] initWithFrame:NSMakeRect(0., 0., 22., 22.)];
	[button setTitle:@"↑"];

	button.delegate = self;
	self.statusItem.view = button;
}

- (BOOL) application:(NSApplication *) sender openFile:(NSString *) filename {
	[self uploadFileAtPath:filename];
	return YES;
}

- (void) application:(NSApplication *) sender openFiles:(NSArray *) filenames {
	for (NSString *filename in filenames) {
		[self uploadFileAtPath:filename];
	}
}

#pragma mark -

- (void) button:(DraggableButton *) button didAcceptDragWithFileAtPath:(NSString *) path {
	[self uploadFileAtPath:path];
}

#pragma mark -

- (void) uploadFileAtPath:(NSString *) path {
	[self startUpdatingButtonTitle];

	NSInputStream *inputStream = [NSInputStream inputStreamWithFileAtPath:path];
	if (!inputStream) {
		[self stopUpdatingButtonTitle];
		NSLog(@"no input stream for %@", path);
		return;
	}

	NMSSHSession *session = [NMSSHSession connectToHost:@"your.domain:22" withUsername:@"username"];
	if (session.isConnected) {
		[session authenticateByPassword:@"password"];
	} else {
		[self stopUpdatingButtonTitle];
		NSLog(@"Unable to connect");
		return;
	}

	if (!session.isAuthorized) {
		[self stopUpdatingButtonTitle];
		NSLog(@"Unable to authorize");
		return;
	}

	NMSFTP *sftpSession = [NMSFTP connectWithSession:session];
	if (!sftpSession) {
		[self stopUpdatingButtonTitle];
		NSLog(@"Unable to make an SFTP session");
		return;
	}

	[self.activeSessions addObject:session];
	[self.activeSessions addObject:sftpSession];

	__weak __typeof__((self)) weakSelf = self;
	dispatch_async(self.uploadQueue, ^{
		NSUInteger fileLength = [[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil] fileSize];
		[sftpSession writeStream:inputStream toFileAtPath:[NSString stringWithFormat:@"/var/www/path/to/folder/%@", path.lastPathComponent] progress:^BOOL (NSUInteger progress) {
			if (progress == fileLength) {
				dispatch_async(dispatch_get_main_queue(), ^{ // give the sftp session a chance to finish up any remaining work it has before we remove our references to it
					__strong __typeof__((weakSelf)) strongSelf = weakSelf;

					[sftpSession disconnect];
					[session disconnect];

					[strongSelf.activeSessions removeObject:sftpSession];
					[strongSelf.activeSessions removeObject:session];

					if (!strongSelf.activeSessions.count) {
						[strongSelf stopUpdatingButtonTitle];
					}
				});

				NSString *remoteString = [NSString stringWithFormat:@"http://your.domain/path/%@", path.lastPathComponent];
				[[NSPasteboard generalPasteboard] declareTypes:@[ NSStringPboardType ] owner:nil];
				[[NSPasteboard generalPasteboard] setString:remoteString forType:NSStringPboardType];

				NSBeep();
			}
			return YES;
		}];
	});
}

#pragma mark -

- (void) startUpdatingButtonTitle {
	self.numberOfDots = 0;

	[self updateButtonTitle];
}

- (void) updateButtonTitle {
	DraggableButton *button = (DraggableButton *)self.statusItem.view;
	// ⎡⎤⎦⎣ ⌊⌋⌈⌉
	if (self.numberOfDots == 3) {
		[button setTitle:@"⌈"];
		[button setAlignment:NSLeftTextAlignment];
	} else if (self.numberOfDots == 2) {
		[button setTitle:@"⌉"];
		[button setAlignment:NSRightTextAlignment];
	} else if (self.numberOfDots == 1) {
		[button setTitle:@"⌋"];
		[button setAlignment:NSRightTextAlignment];
	} else if (self.numberOfDots == 0) {
		[button setTitle:@"⌊"];
		[button setAlignment:NSLeftTextAlignment];
	}

	self.numberOfDots++;
	if (self.numberOfDots > 4) {
		self.numberOfDots = 0;
	}

	[self performSelector:_cmd withObject:nil afterDelay:.25];
}

- (void) stopUpdatingButtonTitle {
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateButtonTitle) object:nil];

	DraggableButton *button = (DraggableButton *)self.statusItem.view;
	[button setTitle:@"↑"];
}

@end
