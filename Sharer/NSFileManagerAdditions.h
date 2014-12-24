#import <Foundation/Foundation.h>

@interface NSFileManager (Additions)
- (NSString *) remoteNameForFileAtPath:(NSString *) path withOptionalSalt:(NSString *) salt;
@end
