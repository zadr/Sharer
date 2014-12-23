#import "DraggableButton.h"

static NSMenu *defaultMenu = nil;

@implementation DraggableButton
- (id) initWithFrame:(NSRect) frameRect {
	if (!(self = [super initWithFrame:frameRect]))
		return nil;

	[self registerForDraggedTypes:@[ NSFilenamesPboardType ]];

	self.bordered = NO;
	self.bezelStyle = 0;

	return self;
}

#pragma mark -

- (void) setDelegate:(id<DraggableDelegate>) delegate {
	_delegate = delegate;

	defaultMenu = [self.delegate menuForDraggableButton:self];
}

- (NSDragOperation) draggingEntered:(id <NSDraggingInfo>) sender {
	return NSDragOperationCopy;
}

- (BOOL) performDragOperation:(id <NSDraggingInfo>) sender {
	if ([sender.draggingPasteboard.types containsObject:NSFilenamesPboardType]) {
		for (NSString *file in [sender.draggingPasteboard propertyListForType:NSFilenamesPboardType]) {
			[self.delegate button:self didAcceptDragWithFileAtPath:file];
		}
	}

	return YES;
}

#pragma mark -

- (void) mouseDown:(NSEvent *) theEvent {
	NSPoint point = [self convertPoint:[self bounds].origin toView:nil];
	point.y -= NSHeight( [self frame] ) + 2.;
	theEvent = [NSEvent mouseEventWithType:[theEvent type] location:point modifierFlags:[theEvent modifierFlags] timestamp:[theEvent timestamp] windowNumber:[[theEvent window] windowNumber] context:[theEvent context] eventNumber:[theEvent eventNumber] clickCount:[theEvent clickCount] pressure:[theEvent pressure]];

	[NSMenu popUpContextMenu:[self.delegate menuForDraggableButton:self] withEvent:theEvent forView:self];

	[super mouseDown:theEvent];
}
@end

