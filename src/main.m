#import <UIKit/UIKit.h>
#import "RRChrome.h"
#import "HNSecureProtocol.h"
#import "RRMedia.h"
#import "RRFeed.h"
#import "RRPostController.h"
#import "RRListController.h"

@interface RRAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation RRAppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    [HNSecureProtocol install];
    [RRMedia sweepCaches];
    [app setStatusBarStyle:UIStatusBarStyleBlackOpaque];
    RRRootController *root = [[RRRootController alloc] init];
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.rootViewController = root;
    [self.window makeKeyAndVisible];
#ifdef RR_PREVIEW   /* simulator only: RR_TAB=0..3 picks a tab, RR_SUB=name opens that subreddit (see also RR_OPEN and RR_PLAY) */
    if (getenv("RR_TAB")) [root selectTab:atoi(getenv("RR_TAB"))];
    if (getenv("RR_SUB")) [root push:[[RRListController alloc] initWithSub:[NSString stringWithUTF8String:getenv("RR_SUB")]]];
#endif
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([RRAppDelegate class]));
    }
}
