#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, RRMediaKind) { RRMediaNone, RRMediaImage, RRMediaGif, RRMediaVideo, RRMediaGallery, RRMediaLink };

@interface RRPost : NSObject
@property (nonatomic, copy) NSString *pid, *title, *author, *sub, *link, *permalink, *thumb, *text, *domain;
@property (nonatomic) NSTimeInterval created;
@property (nonatomic) RRMediaKind media;
@property (nonatomic, copy, readonly) NSString *mediaURL;   /* what to download for the media: the image/gif file, or the v.redd.it base for video */
+ (RRPost *)postFromDict:(NSDictionary *)d;
- (NSDictionary *)dictionary;
@end

@interface RRComment : NSObject
@property (nonatomic, copy) NSString *author, *text;
@property (nonatomic) NSTimeInterval created;
@property (nonatomic) CGFloat height, heightWidth;
@end

typedef void (^RRPostsBlock)(NSArray *posts, NSString *after, NSString *error);
typedef void (^RRCommentsBlock)(RRPost *post, NSArray *comments, NSString *error);

extern NSString *const RRFeedStatusNotification;   /* userInfo @"text": what the feed is waiting for, nil when idle */

/* Reddit's logged-out Atom feeds. Reddit allows roughly one request per 40 seconds without an API key, so every request goes through one queue
   that waits for the reset time Reddit reports, and answers are kept on disk for a while. */
@interface RRFeed : NSObject
/* path: @"r/pics/hot", @"r/popular/hot", @"r/pics/top" ... ; period only matters for top (hour day week month year all) */
+ (void)loadPath:(NSString *)path period:(NSString *)period after:(NSString *)after force:(BOOL)force done:(RRPostsBlock)done;
+ (void)searchQuery:(NSString *)q sort:(NSString *)sort done:(RRPostsBlock)done;
+ (void)loadCommentsFor:(RRPost *)post done:(RRCommentsBlock)done;
+ (NSString *)cleanSubName:(NSString *)s;     /* "r/Pics/" -> "pics", nil when it is not a valid name */
@end

@interface RRSaved : NSObject
+ (NSArray *)posts;
+ (BOOL)contains:(NSString *)pid;
+ (BOOL)toggle:(RRPost *)p;
+ (void)remove:(NSString *)pid;
@end

@interface RRSubs : NSObject
+ (NSArray *)names;
+ (void)add:(NSString *)name;
+ (void)remove:(NSString *)name;
@end
