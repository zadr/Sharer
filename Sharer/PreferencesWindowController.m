#import "PreferencesWindowController.h"

#import "AppDelegate.h"

typedef NS_OPTIONS(NSInteger, AppVisibility) {
	AppVisibilityStatusItemOnly = 1 << 0,
	AppVisibilityDockIconOnly = 1 << 1,
	AppVisibilityStatusItemAndDockIcon = (AppVisibilityStatusItemOnly | AppVisibilityDockIconOnly)
};
@interface PreferencesWindowController ()
@property (weak) IBOutlet NSPopUpButton *statusItemOrDockButton;
@property (weak) IBOutlet NSTextField *recentItemsTextField;
@property (weak) IBOutlet NSButton *obsfucateURLsButton;
@end

@implementation PreferencesWindowController
- (id) init {
	return (self = [super initWithWindowNibName:@"Preferences"]);
}

- (void) windowDidLoad {
	[super windowDidLoad];

	BOOL showDockIcon = [[NSUserDefaults standardUserDefaults] boolForKey:@"SShowDockIcon"];
	BOOL showStatusItem = [[NSUserDefaults standardUserDefaults] boolForKey:@"SShowStatusItem"];
	AppVisibility visiblility;
	if (showDockIcon && showStatusItem) {
		visiblility = AppVisibilityStatusItemAndDockIcon;
	} else if (showStatusItem) {
		visiblility = AppVisibilityStatusItemOnly;
	} else if (showDockIcon) {
		visiblility = AppVisibilityDockIconOnly;
	}

	[self.statusItemOrDockButton selectItemAtIndex:(visiblility - 1)];

	NSDictionary *defaults = [NSDictionary dictionaryWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"Defaults" ofType:@"plist"]];
	NSNumber *recentItems = [[NSUserDefaults standardUserDefaults] objectForKey:@"SRecentItems"];
	if (![recentItems isEqual:defaults[@"SRecentItems"]]) {
		self.recentItemsTextField.objectValue = recentItems;
	}

	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"SObsfucateURL"])
		self.obsfucateURLsButton.state = NSOnState;
	else self.obsfucateURLsButton.state = NSOffState;
}

#pragma mark -

- (IBAction) visibilityChanged:(NSPopUpButton *) button {
	AppVisibility visibility;
	if (button.indexOfSelectedItem == 0) {
		visibility = AppVisibilityStatusItemOnly;
	} else if (button.indexOfSelectedItem == 1) {
		visibility = AppVisibilityDockIconOnly;
	} else if (button.indexOfSelectedItem == 2) {
		visibility = AppVisibilityStatusItemAndDockIcon;
	}

	[[NSUserDefaults standardUserDefaults] setBool:((visibility & AppVisibilityStatusItemOnly) == AppVisibilityStatusItemOnly) forKey:@"SShowStatusItem"];
	[[NSUserDefaults standardUserDefaults] setBool:((visibility & AppVisibilityDockIconOnly) == AppVisibilityDockIconOnly) forKey:@"SShowDockIcon"];

	AppDelegate *appDelegate = (AppDelegate *)[[NSApplication sharedApplication] delegate];
	[appDelegate updateUIElements];
}

- (IBAction) recentItemsChanged:(NSTextField *) textField {
	[[NSUserDefaults standardUserDefaults] setInteger:textField.integerValue forKey:@"SRecentItems"];

	AppDelegate *appDelegate = (AppDelegate *)[[NSApplication sharedApplication] delegate];
	[appDelegate updateRecentItems];
}

- (IBAction) obsfucateURLsChanged:(NSButton *) button {
	[[NSUserDefaults standardUserDefaults] setBool:(button.state == NSOnState) forKey:@"SObsfucateURL"];
}
@end
