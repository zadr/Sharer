#import "AppDelegate.h"

#import "DraggableButton.h"
#import "CQKeychain.h"

#import <NMSSH/NMSSH.h>

@interface AppDelegate () <DraggableDelegate>
@property (weak) IBOutlet NSWindow *window;
@property (weak) IBOutlet NSTextField *serverTextField;
@property (weak) IBOutlet NSTextField *remotePathTextField;
@property (weak) IBOutlet NSTextField *URLFormatTextField;
@property (weak) IBOutlet NSTextField *portTextField;
@property (weak) IBOutlet NSTextField *usernameTextField;
@property (weak) IBOutlet NSTextField *passwordTextField;

@property (strong) NSStatusItem *statusItem;

@property (strong) dispatch_queue_t uploadQueue;
@property (strong) NSMutableSet *activeSessions;
@end

#pragma mark -

@implementation AppDelegate
- (void) applicationWillFinishLaunching:(NSNotification *) notification {
//	[NMSSHLogger logger].enabled = NO;

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

#define SetValueOfTypeOnField(type, field, fromKeychain) \
	do { \
		NSString *value = nil; \
		if (fromKeychain) { \
			value = [[CQKeychain standardKeychain] passwordForServer:type area:@"sharer"]; \
		} else { \
			value = [[NSUserDefaults standardUserDefaults] objectForKey:type]; \
		} \
 \
		if (value.length) { \
			field.stringValue = value; \
		} \
	} while (0)

	SetValueOfTypeOnField(@"server", self.serverTextField, NO);
	SetValueOfTypeOnField(@"port", self.portTextField, NO);
	SetValueOfTypeOnField(@"remotePath", self.remotePathTextField, NO);
	SetValueOfTypeOnField(@"URLFormat", self.URLFormatTextField, NO);
	SetValueOfTypeOnField(@"username", self.usernameTextField, NO);
	SetValueOfTypeOnField(@"password", self.passwordTextField, YES);
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
	[[NSUserDefaults standardUserDefaults] setObject:self.serverTextField.stringValue forKey:@"server"];
	[[NSUserDefaults standardUserDefaults] setObject:self.portTextField.stringValue forKey:@"port"];
	[[NSUserDefaults standardUserDefaults] setObject:self.remotePathTextField.stringValue forKey:@"remotePath"];
	[[NSUserDefaults standardUserDefaults] setObject:self.usernameTextField.stringValue forKey:@"username"];
	[[CQKeychain standardKeychain] setPassword:self.passwordTextField.stringValue forServer:@"password" area:@"sharer"];

	NSString *URLFormat = self.URLFormatTextField.stringValue;
	if (URLFormat.length && !([URLFormat.lowercaseString hasPrefix:@"http://"] || [URLFormat.lowercaseString hasPrefix:@"https://"])) {
		URLFormat = [@"http://" stringByAppendingString:URLFormat];
	}
	[[NSUserDefaults standardUserDefaults] setObject:URLFormat forKey:@"URLFormat"];

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
		NSString *remotePath = [[NSUserDefaults standardUserDefaults] objectForKey:@"remotePath"];
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

				NSString *URLFormat = [[NSUserDefaults standardUserDefaults] objectForKey:@"URLFormat"];
				NSString *URLString = [URLFormat stringByAppendingPathComponent:path.lastPathComponent];
				[[NSPasteboard generalPasteboard] declareTypes:@[ NSStringPboardType ] owner:nil];
				[[NSPasteboard generalPasteboard] setString:URLString forType:NSStringPboardType];

				NSBeep();
			}
			return YES;
		}];
	});
}

#pragma mark -

- (void) startUpdatingButtonTitle {
	NSProgressIndicator *indicator = [[NSProgressIndicator alloc] initWithFrame:self.statusItem.view.bounds];
	indicator.controlSize = NSMiniControlSize;
	indicator.style = NSProgressIndicatorSpinningStyle;
	[indicator startAnimation:nil];

	DraggableButton *button = (DraggableButton *)self.statusItem.view;
	button.title = nil;

	[button addSubview:indicator];
}

- (void) stopUpdatingButtonTitle {
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateButtonTitle) object:nil];

	DraggableButton *button = (DraggableButton *)self.statusItem.view;
	[button.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
	[button setTitle:@"↑"];
}

@end
