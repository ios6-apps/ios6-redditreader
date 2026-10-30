#import "RRStyle.h"

UIColor *RRRGB(int r, int g, int b) { return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1]; }
UIColor *RROrange(void) { return RRRGB(224, 96, 16); }
UIColor *RRDarkOrange(void) { return RRRGB(176, 62, 0); }

static void rgba(UIColor *c, CGFloat *out) {
    if (![c getRed:out green:out + 1 blue:out + 2 alpha:out + 3]) {
        CGFloat w, a;
        [c getWhite:&w alpha:&a];
        out[0] = out[1] = out[2] = w; out[3] = a;
    }
}

void RRFillGradient(CGContextRef c, CGRect r, UIColor *top, UIColor *bottom) {
    CGFloat comps[8];
    rgba(top, comps); rgba(bottom, comps + 4);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGGradientRef g = CGGradientCreateWithColorComponents(cs, comps, NULL, 2);
    CGContextSaveGState(c);
    CGContextClipToRect(c, r);
    CGContextDrawLinearGradient(c, g, CGPointMake(0, CGRectGetMinY(r)), CGPointMake(0, CGRectGetMaxY(r)), 0);
    CGContextRestoreGState(c);
    CGGradientRelease(g);
    CGColorSpaceRelease(cs);
}

void RRRoundRectPath(CGContextRef c, CGRect r, CGFloat rad) {
    CGFloat x0 = CGRectGetMinX(r), x1 = CGRectGetMaxX(r), y0 = CGRectGetMinY(r), y1 = CGRectGetMaxY(r);
    CGContextMoveToPoint(c, x0 + rad, y0);
    CGContextAddArcToPoint(c, x1, y0, x1, y1, rad);
    CGContextAddArcToPoint(c, x1, y1, x0, y1, rad);
    CGContextAddArcToPoint(c, x0, y1, x0, y0, rad);
    CGContextAddArcToPoint(c, x0, y0, x1, y0, rad);
    CGContextClosePath(c);
}

void RRDrawText(NSString *s, CGRect r, UIFont *font, UIColor *color, UIColor *shadow, CGFloat dy, NSTextAlignment align) {
    if (!s.length) return;
    /* a one-line box truncates instead of wrapping */
    NSLineBreakMode mode = r.size.height < font.lineHeight * 1.5 ? NSLineBreakByTruncatingTail : NSLineBreakByWordWrapping;
    if (shadow) {
        [shadow set];
        [s drawInRect:CGRectOffset(r, 0, dy) withFont:font lineBreakMode:mode alignment:align];
    }
    [color set];
    [s drawInRect:r withFont:font lineBreakMode:mode alignment:align];
}

CGFloat RRTextHeight(NSString *s, UIFont *font, CGFloat width, CGFloat maxHeight) {
    if (!s.length) return 0;
    CGSize sz = [s sizeWithFont:font constrainedToSize:CGSizeMake(width, maxHeight) lineBreakMode:NSLineBreakByWordWrapping];
    return ceil(sz.height);
}

UIColor *RRAccent(void) { return RRRGB(238, 84, 20); }
UIColor *RRInk(void) { return RRRGB(30, 34, 42); }
UIColor *RRSoftInk(void) { return RRRGB(108, 116, 130); }

/* fine woven texture, drawn once: light and dark diagonal threads plus speckle */
static UIImage *RRWeaveTile(void) {
    static UIImage *img;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(16, 16), NO, 0);
        CGContextRef c = UIGraphicsGetCurrentContext();
        srand(5);
        for (int y = 0; y < 16; y++)
            for (int x = 0; x < 16; x++) {
                int k = (x + y) % 4;
                if (k == 0) CGContextSetRGBFillColor(c, 1, 1, 1, 0.075);
                else if (k == 2) CGContextSetRGBFillColor(c, 0, 0, 0, 0.09);
                else CGContextSetRGBFillColor(c, 0, 0, 0, 0);
                CGContextFillRect(c, CGRectMake(x, y, 1, 1));
                if (rand() % 5 == 0) { CGContextSetRGBFillColor(c, rand() % 2, rand() % 2, rand() % 2, 0.05); CGContextFillRect(c, CGRectMake(x, y, 1, 1)); }
            }
        img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    });
    return img;
}

void RRDrawBar(CGContextRef c, CGRect r) {
    CGFloat half = r.size.height / 2;
    RRFillGradient(c, CGRectMake(r.origin.x, r.origin.y, r.size.width, half), RRRGB(112, 124, 146), RRRGB(84, 96, 118));
    RRFillGradient(c, CGRectMake(r.origin.x, r.origin.y + half, r.size.width, r.size.height - half), RRRGB(68, 80, 102), RRRGB(46, 56, 74));
    [[UIColor colorWithPatternImage:RRWeaveTile()] setFill];
    CGContextFillRect(c, r);
    [[UIColor colorWithWhite:1 alpha:0.42] set]; CGContextFillRect(c, CGRectMake(r.origin.x, r.origin.y, r.size.width, 1));
    [[UIColor colorWithWhite:0 alpha:0.55] set]; CGContextFillRect(c, CGRectMake(r.origin.x, CGRectGetMaxY(r) - 1, r.size.width, 1));
}

void RRDrawPanel(CGContextRef c, CGRect r) {
    RRFillGradient(c, r, RRRGB(255, 255, 255), RRRGB(240, 243, 248));
    [[UIColor colorWithWhite:1 alpha:1] set]; CGContextFillRect(c, CGRectMake(r.origin.x, r.origin.y, r.size.width, 1));
    [RRRGB(176, 184, 198) set]; CGContextFillRect(c, CGRectMake(r.origin.x, CGRectGetMaxY(r) - 1, r.size.width, 1));
}

/* the table background: pale cool-grey with a faint weave */
UIImage *RRLinenImage(void) {
    static UIImage *img;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(16, 16), YES, 0);
        CGContextRef c = UIGraphicsGetCurrentContext();
        [RRRGB(204, 210, 221) setFill];
        CGContextFillRect(c, CGRectMake(0, 0, 16, 16));
        [[UIColor colorWithPatternImage:RRWeaveTile()] setFill];
        CGContextSetAlpha(c, 0.55);
        CGContextFillRect(c, CGRectMake(0, 0, 16, 16));
        img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    });
    return img;
}

UIImage *RRTabIcon(int kind) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(30, 30), NO, 0);
    CGContextRef c = UIGraphicsGetCurrentContext();
    [[UIColor blackColor] set];
    if (kind == 0) {            /* newspaper */
        RRRoundRectPath(c, CGRectMake(4, 5, 22, 20), 2.5);
        CGContextSetLineWidth(c, 2);
        CGContextStrokePath(c);
        CGContextFillRect(c, CGRectMake(8, 9, 8, 6));
        CGContextFillRect(c, CGRectMake(18, 9, 5, 2));
        CGContextFillRect(c, CGRectMake(18, 13, 5, 2));
        CGContextFillRect(c, CGRectMake(8, 18, 15, 2));
    } else if (kind == 1) {     /* list */
        for (int i = 0; i < 3; i++) {
            CGContextFillEllipseInRect(c, CGRectMake(4, 7 + i * 7.5, 4, 4));
            CGContextFillRect(c, CGRectMake(11, 8 + i * 7.5, 15, 2.5));
        }
    } else if (kind == 3) {     /* star */
        for (int i = 0; i < 10; i++) {
            CGFloat a = -M_PI / 2 + i * M_PI / 5, rad = (i % 2) ? 5.8 : 13;
            CGPoint pt = CGPointMake(15 + cos(a) * rad, 16 + sin(a) * rad);
            if (i == 0) CGContextMoveToPoint(c, pt.x, pt.y); else CGContextAddLineToPoint(c, pt.x, pt.y);
        }
        CGContextClosePath(c);
        CGContextSetLineWidth(c, 2); CGContextSetLineJoin(c, kCGLineJoinRound);
        CGContextStrokePath(c);
    } else {                    /* magnifier */
        CGContextSetLineWidth(c, 2.6);
        CGContextStrokeEllipseInRect(c, CGRectMake(5, 5, 14, 14));
        CGContextSetLineCap(c, kCGLineCapRound);
        CGContextMoveToPoint(c, 17, 17); CGContextAddLineToPoint(c, 25, 25); CGContextStrokePath(c);
    }
    UIImage *i = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return i;
}

UIImage *RRLeatherImage(void) {
    static UIImage *img;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(64, 64), YES, 0);
        CGContextRef c = UIGraphicsGetCurrentContext();
        [RRRGB(66, 44, 32) setFill];
        CGContextFillRect(c, CGRectMake(0, 0, 64, 64));
        srand(11);
        for (int i = 0; i < 520; i++) {          /* pebbled grain: small dark dimples with a light rim */
            CGFloat x = rand() % 64, y = rand() % 64, r = 0.8 + (rand() % 10) / 10.0;
            CGContextSetRGBFillColor(c, 0.1, 0.05, 0.02, 0.28);
            CGContextFillEllipseInRect(c, CGRectMake(x, y, r, r));
            CGContextSetRGBFillColor(c, 1, 0.85, 0.7, 0.07);
            CGContextFillEllipseInRect(c, CGRectMake(x - 0.6, y - 0.6, r, r));
        }
        img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    });
    return img;
}

void RRGlossRoundRect(CGContextRef c, CGRect r, CGFloat rad, UIColor *top, UIColor *bot, UIColor *stroke) {
    CGContextSaveGState(c);
    RRRoundRectPath(c, r, rad); CGContextClip(c);
    RRFillGradient(c, r, top, bot);
    RRFillGradient(c, CGRectMake(r.origin.x, r.origin.y, r.size.width, r.size.height / 2), [UIColor colorWithWhite:1 alpha:0.30], [UIColor colorWithWhite:1 alpha:0.04]);
    CGContextRestoreGState(c);
    RRRoundRectPath(c, CGRectInset(r, 0.5, 0.5), rad);
    [stroke set]; CGContextSetLineWidth(c, 1); CGContextStrokePath(c);
}
