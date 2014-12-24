#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate, NSControlTextEditingDelegate, NSMenuDelegate>
- (void) updateUIElements;
- (void) updateRecentItems;
@end
