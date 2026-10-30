#import <UIKit/UIKit.h>

typedef void (^RRImageBlock)(UIImage *image, NSString *error);

/* Images and gifs: downloaded through the app's own TLS, kept on disk, decoded at a limited size so a 12-megapixel photo does not eat the iPhone 5's memory. */
@interface RRMedia : NSObject
+ (UIImage *)cachedImage:(NSString *)url maxPixel:(int)px;                                  /* memory only, nil if not decoded yet */
+ (void)image:(NSString *)url maxPixel:(int)px done:(RRImageBlock)done;                     /* first frame of a gif for gifs */
+ (void)animated:(NSString *)url maxPixel:(int)px done:(RRImageBlock)done;                  /* gif as an animated UIImage */
+ (NSString *)cachePathForURL:(NSString *)url;                                            /* where the downloaded file lives (may not exist yet) */
+ (void)sweepCaches;                                                                         /* drops the oldest cached files when over the size budget */
@end

/* A cancellable download to a file with progress. */
@interface RRDownload : NSObject
+ (RRDownload *)fetch:(NSString *)url toFile:(NSString *)path progress:(void (^)(float fraction))progress done:(void (^)(NSString *error))done;
- (void)cancel;
@end

/* v.redd.it posts come as separate fragmented video and audio files (DASH). This downloads both, joins them into one MP4 the iOS 6 player can open,
   and caches the result. Direct .mp4 links (imgur) are just downloaded. */
@interface RRVideo : NSObject
+ (RRVideo *)prepare:(NSString *)mediaURL progress:(void (^)(float fraction, NSString *stage))progress done:(void (^)(NSString *path, NSString *error))done;
- (void)cancel;
@end
