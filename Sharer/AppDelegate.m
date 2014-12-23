#import "AppDelegate.h"

#import "DraggableButton.h"
#import "SFTPUpload.h"
#import "FTPUpload.h"
#import "CQKeychain.h"

#import <NMSSH/NMSSH.h>

@interface AppDelegate () <DraggableDelegate, UploadDelegate>
@property (weak) IBOutlet NSWindow *window;
@property (strong) NSWindow *preferencesWindow;

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

	NSDictionary *defaults = [NSDictionary dictionaryWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"Defaults" ofType:@"plist"]];
	[[NSUserDefaults standardUserDefaults] registerDefaults:defaults];

	[[NSPasteboard generalPasteboard] declareTypes:@[ NSStringPboardType ] owner:nil];

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

- (NSMenu *) applicationDockMenu:(NSApplication *) sender {
	return self.menu;
}

#pragma mark -

- (void) button:(DraggableButton *) button didAcceptDragWithFileAtPath:(NSString *) path {
	[self uploadFileAtPath:path];
}

- (NSMenu *) menuForDraggableButton:(DraggableButton *) button {
	return self.menu;
}

#pragma mark -

- (BOOL) control:(NSControl *) control textShouldEndEditing:(NSText *) fieldEditor {
	[[NSUserDefaults standardUserDefaults] setObject:self.serverTextField.stringValue forKey:@"server"];
	[[NSUserDefaults standardUserDefaults] setObject:self.portTextField.stringValue forKey:@"port"];
	[[NSUserDefaults standardUserDefaults] setObject:self.remotePathTextField.stringValue forKey:@"remotePath"];
	[[NSUserDefaults standardUserDefaults] setObject:self.usernameTextField.stringValue forKey:@"username"];
	[[CQKeychain standardKeychain] setPassword:self.passwordTextField.stringValue forServer:@"password" area:@"sharer"];

	NSString *URLFormat = self.URLFormatTextField.stringValue;
	NSURL *URL = [NSURL URLWithString:URLFormat];
	if (URLFormat.length && !URL.scheme.length) {
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
	SFTPUpload *upload = [SFTPUpload uploadFile:path];
	upload.delegate = self;

	if ([upload startOnQueue:self.uploadQueue]) {
		[self.activeSessions addObject:upload];
	}
}

- (void) uploadDidStart:(id <Upload>) upload {
	[self startUpdatingButtonTitle];
}

- (void) uploadDidFinish:(id <Upload>) upload {
	[self.activeSessions removeObject:upload];
	[self stopUpdatingButtonTitle];

	NSString *URLFormat = [[NSUserDefaults standardUserDefaults] objectForKey:@"URLFormat"];
	NSURL *URL = [[NSURL URLWithString:URLFormat] URLByAppendingPathComponent:upload.source.lastPathComponent];

	[[NSPasteboard generalPasteboard] setString:URL.absoluteString forType:NSStringPboardType];

	NSUserNotification *notification = [[NSUserNotification alloc] init];
	notification.title = NSLocalizedString(@"Uploaded", @"Uploaded");
	notification.subtitle = [NSString stringWithFormat:NSLocalizedString(@"Finished uploading %@.", @"Finished uploading file notification"), upload.source.lastPathComponent];
	notification.soundName = NSUserNotificationDefaultSoundName;

	[[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];

	NSMutableArray *recentUploads = [[[NSUserDefaults standardUserDefaults] objectForKey:@"RecentUploads"] mutableCopy];
	if (!recentUploads) {
		recentUploads = [NSMutableArray array];
	}
	[recentUploads insertObject:@{ @"file": upload.source, @"url": URL.absoluteString } atIndex:0];

	while (recentUploads.count > [[NSUserDefaults standardUserDefaults] integerForKey:@"SRecentItems"]) {
		[recentUploads removeLastObject];
	}

	[[NSUserDefaults standardUserDefaults] setObject:recentUploads forKey:@"RecentUploads"];
}

- (void) upload:(id <Upload>) upload didFailWithError:(NSError *) error {
	[self.activeSessions removeObject:upload];
	[self stopUpdatingButtonTitle];

	NSUserNotification *notification = [[NSUserNotification alloc] init];
	notification.title = NSLocalizedString(@"Upload Failed", @"Upload Failed");
	notification.subtitle = [NSString stringWithFormat:NSLocalizedString(@"Unable to upload %@.", @"Unable to upload file notification"), upload.source.lastPathComponent];
	notification.soundName = NSUserNotificationDefaultSoundName;

	[[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
}


#pragma mark -

- (NSMenu *) menu {
	NSMenu *menu = [[NSMenu alloc] init];

	NSArray *recentUploads = [[NSUserDefaults standardUserDefaults] objectForKey:@"RecentUploads"];
	if (recentUploads.count) {
		[recentUploads enumerateObjectsUsingBlock:^(NSDictionary *upload, NSUInteger index, BOOL *stop) {
			NSString *file = upload[@"file"];
			NSMenuItem *item = nil;
			if (index < 10) {
				item = [[NSMenuItem alloc] initWithTitle:file.lastPathComponent action:@selector(copyItemToClipboard:) keyEquivalent:[NSString stringWithFormat:@"%tu", index]];
				item.keyEquivalentModifierMask = NSCommandKeyMask;
			} else {
				item = [[NSMenuItem alloc] initWithTitle:file.lastPathComponent action:@selector(copyItemToClipboard:) keyEquivalent:@""];
			}
			item.representedObject = upload[@"url"];
			[menu addItem:item];
		}];
		[menu addItem:[NSMenuItem separatorItem]];
	}

	NSMenuItem *preferencesItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Preferences", @"Preferences menu item") action:@selector(showPreferences:) keyEquivalent:@","];
	preferencesItem.keyEquivalentModifierMask = NSCommandKeyMask;
	[menu addItem:preferencesItem];

	NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Quit", @"Quit menu item") action:@selector(terminate:) keyEquivalent:@"q"];
	quitItem.keyEquivalentModifierMask = NSCommandKeyMask;
	[menu addItem:quitItem];

	return menu;
}

- (void) copyItemToClipboard:(NSMenuItem *) fromMenuItem {
	[[NSPasteboard generalPasteboard] setString:fromMenuItem.representedObject forType:NSStringPboardType];
}

#pragma mark -

- (void) startUpdatingButtonTitle {
	if (self.activeSessions.count > 1) {
		return;
	}

	NSProgressIndicator *indicator = [[NSProgressIndicator alloc] initWithFrame:self.statusItem.view.bounds];
	indicator.controlSize = NSMiniControlSize;
	indicator.style = NSProgressIndicatorSpinningStyle;
	[indicator startAnimation:nil];

	DraggableButton *button = (DraggableButton *)self.statusItem.view;
	button.title = nil;

	[button addSubview:indicator];
}

- (void) stopUpdatingButtonTitle {
	if (self.activeSessions.count) {
		return;
	}

	DraggableButton *button = (DraggableButton *)self.statusItem.view;
	[button.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
	[button setTitle:@"↑"];
}

@end
