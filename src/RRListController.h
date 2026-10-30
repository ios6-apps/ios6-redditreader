#import <UIKit/UIKit.h>
#import "RRFeed.h"

/* A list of posts drawn as paper strips on linen: a subreddit (or Popular), search results, or the saved posts. */
@interface RRListController : UITableViewController
- (id)initWithSub:(NSString *)sub;        /* nil: r/popular */
- (id)initSaved;
- (id)initSearch:(NSString *)query;
@end
