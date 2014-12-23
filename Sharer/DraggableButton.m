#import "DraggableButton.h"

@implementation DraggableButton
- (id) initWithFrame:(NSRect) frameRect {
	if (!(self = [super initWithFrame:frameRect]))
		return nil;

	[self registerForDraggedTypes:@[ NSFilenamesPboardType ]];

	self.alignment = NSLeftTextAlignment;
	self.bordered = NO;
	self.bezelStyle = 0;

	return self;
}

- (NSDragOperation) draggingEntered:(id <NSDraggingInfo>) sender {
	return NSDragOperationCopy;
}

- (void) mouseDown:(NSEvent *) theEvent {
	// do nothing
}

- (BOOL) performDragOperation:(id <NSDraggingInfo>) sender {
	if ([sender.draggingPasteboard.types containsObject:NSFilenamesPboardType]) {
		for (NSString *file in [sender.draggingPasteboard propertyListForType:NSFilenamesPboardType]) {
			[self.delegate button:self didAcceptDragWithFileAtPath:file];
		}
	}

	return YES;
}
@end

