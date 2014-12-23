#import <Cocoa/Cocoa.h>

@class DraggableButton;

@protocol DraggableDelegate <NSObject>
@required
- (void) button:(DraggableButton *) button didAcceptDragWithFileAtPath:(NSString *) path;
- (NSMenu *) menuForDraggableButton:(DraggableButton *) button;
@end

@interface DraggableButton : NSButton
@property (nonatomic, weak) id <DraggableDelegate> delegate;
@end
