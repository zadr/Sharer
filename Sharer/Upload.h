#import <Foundation/Foundation.h>

@protocol Upload;
@protocol UploadDelegate <NSObject>
@required
- (void) uploadDidStart:(id <Upload>) upload;
- (void) uploadDidFinish:(id <Upload>) upload;
- (void) upload:(id <Upload>) upload didFailWithError:(NSError *) error;
@end

@protocol Upload <NSObject>
@required
+ (id <Upload>) uploadFile:(NSString *) file withRemoteName:(NSString *) name;

@property (atomic, weak) id <UploadDelegate> delegate;
@property (nonatomic, assign, readonly) BOOL isSending;
@property (atomic, copy, readonly) NSString *source;
@property (atomic, copy, readonly) NSString *destinationName;

- (BOOL) startOnQueue:(dispatch_queue_t) uploadQueue;
- (void) stop;
@end
