#import "AppDelegate.h"

#import "DraggableButton.h"
#import "CQKeychain.h"

#import <NMSSH/NMSSH.h>

@interface AppDelegate () <DraggableDelegate>
@property (weak) IBOutlet NSWindow *window;
@property (weak) IBOutlet NSTextField *serverTextField;
@property (weak) IBOutlet NSTextField *remotePathTextField;
@property (weak) IBOutlet NSTextField *portTextField;
@property (weak) IBOutlet NSTextField *usernameTextField;
@property (weak) IBOutlet NSTextField *passwordTextField;

@property (strong) NSStatusItem *statusItem;

@property (atomic) NSInteger numberOfDots;

@property (strong) dispatch_queue_t uploadQueue;
@property (strong) NSMutableSet *activeSessions;
@end

#pragma mark -

@implementation AppDelegate
- (void) applicationWillFinishLaunching:(NSNotification *) notification {
	self.uploadQueue = dispatch_queue_create("net.thisismyinter.upload", DISPATCH_QUEUE_CONCURRENT);
	self.activeSessions = [NSMutableSet set];

	self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];

	DraggableButton *button = [[DraggableButton alloc] initWithFrame:NSMakeRect(0., 0., 22., 22.)];
	[button setTitle:@"↑"];

	button.delegate = self;
	self.statusItem.view = button;
}

- (void) applicationDidFinishLaunching:(NSNotification *) notification {
	self.usernameTextField.placeholderString = NSUserName();

#define SetValueOfTypeOnField(type, field) \
	do { \
		NSString *value = [[CQKeychain standardKeychain] passwordForServer:type area:@"sharer"]; \
		if (value.length) { \
			field.stringValue = value; \
		} \
	} while (0)

	SetValueOfTypeOnField(@"server", self.serverTextField);
	SetValueOfTypeOnField(@"port", self.portTextField);
	SetValueOfTypeOnField(@"remotePath", self.remotePathTextField);
	SetValueOfTypeOnField(@"username", self.usernameTextField);
	SetValueOfTypeOnField(@"password", self.passwordTextField);
#undef SetValueOfTypeOnField
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

- (BOOL) control:(NSControl *) control textShouldEndEditing:(NSText *) fieldEditor {
	[[CQKeychain standardKeychain] setPassword:self.serverTextField.stringValue forServer:@"server" area:@"sharer"];
	[[CQKeychain standardKeychain] setPassword:self.portTextField.stringValue forServer:@"port" area:@"sharer"];
	[[CQKeychain standardKeychain] setPassword:self.remotePathTextField.stringValue forServer:@"remotePath" area:@"sharer"];
	[[CQKeychain standardKeychain] setPassword:self.usernameTextField.stringValue forServer:@"username" area:@"sharer"];
	[[CQKeychain standardKeychain] setPassword:self.passwordTextField.stringValue forServer:@"password" area:@"sharer"];

	return YES;
}

- (BOOL) control:(NSControl *) control isValidObject:(id) object {
	if (control == self.portTextField) {
		int port = [[object description] intValue];
		BOOL validPort = ![object length] || (port && port < 65536);
		if (!validPort) {
			NSAlert *alert = [[NSAlert alloc] init];
			alert.messageText = NSLocalizedString(@"Invalid Port", @"Invalid Port alert title");
			alert.informativeText = NSLocalizedString(@"Port must be between 1 and 65535.", @"Port must be between 1 and 65535 alert body");
			[alert addButtonWithTitle:NSLocalizedString(@"Okay", @"Okay")];
			[alert runModal];
		}
		return validPort;
	}
	return YES;
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

	NSString *server = [[CQKeychain standardKeychain] passwordForServer:@"server" area:@"sharer"];
	NSString *port = [[CQKeychain standardKeychain] passwordForServer:@"port" area:@"sharer"];
	if (!port.length) {
		port = @"22";
	}
	NSString *hostport = [NSString stringWithFormat:@"%@:%@", server, port];
	NSString *username = [[CQKeychain standardKeychain] passwordForServer:@"username" area:@"sharer"];
	NMSSHSession *session = [NMSSHSession connectToHost:hostport withUsername:username];
	if (session.isConnected) {
		NSString *password = [[CQKeychain standardKeychain] passwordForServer:@"password" area:@"sharer"];
		if (password.length) {
			[session authenticateByPassword:@"password"];
		}
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
		NSString *remotePath = [[CQKeychain standardKeychain] passwordForServer:@"remotePath" area:@"sharer"];
		if (!remotePath.length) {
			remotePath = @"";
		}
		[sftpSession writeStream:inputStream toFileAtPath:[remotePath stringByAppendingPathComponent:path.lastPathComponent] progress:^BOOL (NSUInteger progress) {
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
