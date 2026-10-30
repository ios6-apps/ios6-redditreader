/* Just enough of UIKit for the Foundation-only parts of the app (RRFeed.m, RRText.m) to compile on the Mac. */
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@class UIColor, UIImage, UIFont;
typedef NS_ENUM(NSInteger, NSTextAlignment) { NSTextAlignmentLeft, NSTextAlignmentCenter, NSTextAlignmentRight };
