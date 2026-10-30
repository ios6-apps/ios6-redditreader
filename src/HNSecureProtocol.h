#import <Foundation/Foundation.h>

/* Routes every https:// request of the app (Reddit's feeds and the picture and video hosts) through the bundled
   TLS stack instead of iOS 6's own. Call +install once at launch. (The HN prefix is historical: the TLS layer started in the author's Hacker News reader.) */
@interface HNSecureProtocol : NSURLProtocol
+ (void)install;
@end
