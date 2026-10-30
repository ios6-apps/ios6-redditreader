#import <UIKit/UIKit.h>
#import "RRFeed.h"

/* One post: title, its picture / gif / video, the text, and the comments below as paper cards. */
@interface RRPostController : UIViewController
- (id)initWithPost:(RRPost *)post;
@end

/* plain web page, for posts that link to an article */
@interface RRWebController : UIViewController
- (id)initWithURL:(NSURL *)url title:(NSString *)title;
@end
