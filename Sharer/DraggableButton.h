#import <Cocoa/Cocoa.h>

@class DraggableButton;

@protocol DraggableDelegate <NSObject>
@required
- (void) button:(DraggableButton *) button didAcceptDragWithFileAtPath:(NSString *) path;
@end

@interface DraggableButton : NSButton
@property (weak) id <DraggableDelegate> delegate;
@end
