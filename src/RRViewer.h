#import <UIKit/UIKit.h>

/* Full-screen picture viewer: pinch and double-tap to zoom, drag to look around, Save puts the picture in the photo library. */
@interface RRViewer : UIViewController
- (id)initWithURL:(NSString *)url animated:(BOOL)gif placeholder:(UIImage *)placeholder;
@end
