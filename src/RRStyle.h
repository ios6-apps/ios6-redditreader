#import <UIKit/UIKit.h>

/* Drawing helpers for the iOS 6 skeuomorphic look: linen, paper, glossy bars, embossed text. Everything is drawn in code, no image assets. */

UIColor *RRRGB(int r, int g, int b);
UIColor *RROrange(void);
UIColor *RRDarkOrange(void);

/* palette: slate denim bars, cool light paper, orangered accent */
UIColor *RRAccent(void);
UIColor *RRInk(void);        /* main text */
UIColor *RRSoftInk(void);    /* secondary text */
void RRDrawBar(CGContextRef c, CGRect r);                       /* textured slate bar (nav and tab bar) */
void RRDrawPanel(CGContextRef c, CGRect r);                     /* a full-width light row with top highlight and bottom edge */
UIImage *RRLinenImage(void);
UIImage *RRTabIcon(int kind);   /* 0 front page (newspaper), 1 subreddits (list), 2 search, 3 saved (star) */
UIImage *RRLeatherImage(void);
void RRGlossRoundRect(CGContextRef c, CGRect r, CGFloat radius, UIColor *top, UIColor *bottom, UIColor *stroke);

void RRFillGradient(CGContextRef c, CGRect r, UIColor *top, UIColor *bottom);
void RRRoundRectPath(CGContextRef c, CGRect r, CGFloat radius);
void RRDrawText(NSString *s, CGRect r, UIFont *font, UIColor *color, UIColor *shadow, CGFloat shadowDY, NSTextAlignment align);
CGFloat RRTextHeight(NSString *s, UIFont *font, CGFloat width, CGFloat maxHeight);

NSString *RRTimeAgo(NSTimeInterval t);
NSString *RRPlainText(NSString *html);
