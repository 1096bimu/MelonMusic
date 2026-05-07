#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TaglibWrapper : NSObject

+ (nullable NSMutableDictionary *)getMetadata:(NSString *)path;
+ (nullable NSData *)getAlbumArtwork:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
