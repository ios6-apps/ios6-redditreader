#import <UIKit/UIKit.h>

/* Custom-drawn chrome (nav bar, back button, segmented control, leather tab bar) and a tiny navigation stack.
   UIKit's own bars are not used, so the app looks the same on every iOS version. */

@protocol RRScreen <NSObject>
@optional
- (NSString *)rrTitle;
- (UIView *)rrTitleView;    /* replaces the title (e.g. the Article / Comments control) */
- (UIView *)rrRightView;
- (void)rrWillShow;         /* the screen is about to become visible again */
@end

/* glossy segmented control for the nav bar */
@interface RRSegmented : UIControl
@property (nonatomic) NSInteger selectedIndex;
- (id)initWithItems:(NSArray *)items;
- (void)setEnabled:(BOOL)on forIndex:(NSInteger)i;
@end

/* round glossy "open in Safari" button */
@interface RRActionButton : UIControl
@end

/* glossy star button: filled when the story is saved */
@interface RRStarButton : UIControl
@property (nonatomic) BOOL on;
@end

@interface RRRootController : UIViewController
+ (RRRootController *)shared;
- (void)push:(UIViewController *)vc;
- (void)pop;
- (void)selectTab:(NSInteger)tab;
- (void)refreshBar;         /* call when a screen's title / right view changed */
@end
