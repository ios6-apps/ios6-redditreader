#import "RRChrome.h"
#import "RRStyle.h"
#import "RRListController.h"
#import "RRSubsController.h"

#define NAV_H 44
#define TAB_H 49

#pragma mark - small controls

@interface RRBackButton : UIControl
@property (nonatomic, copy) NSString *label;
@end

@implementation RRBackButton
- (void)setHighlighted:(BOOL)h { [super setHighlighted:h]; [self setNeedsDisplay]; }
- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    /* one path: a rounded body with a pointed left end */
    CGContextMoveToPoint(c, 12, 0.5);
    CGContextAddLineToPoint(c, w - 5.5, 0.5);
    CGContextAddArcToPoint(c, w - 0.5, 0.5, w - 0.5, 5.5, 5);
    CGContextAddLineToPoint(c, w - 0.5, h - 5.5);
    CGContextAddArcToPoint(c, w - 0.5, h - 0.5, w - 5.5, h - 0.5, 5);
    CGContextAddLineToPoint(c, 12, h - 0.5);
    CGContextAddLineToPoint(c, 0.5, h / 2);
    CGContextClosePath(c);
    CGPathRef path = CGContextCopyPath(c);
    CGContextSaveGState(c);
    CGContextClip(c);
    BOOL d = self.highlighted;
    RRFillGradient(c, self.bounds, d ? RRRGB(52, 62, 82) : RRRGB(152, 166, 190), d ? RRRGB(40, 50, 68) : RRRGB(76, 90, 118));
    RRFillGradient(c, CGRectMake(0, 0, w, h / 2), [UIColor colorWithWhite:1 alpha:d ? 0.08 : 0.26], [UIColor colorWithWhite:1 alpha:0.02]);
    CGContextRestoreGState(c);
    CGContextAddPath(c, path); CGPathRelease(path);
    [RRRGB(24, 30, 44) set]; CGContextSetLineWidth(c, 1); CGContextStrokePath(c);
    RRDrawText(self.label, CGRectMake(13, 7, w - 17, 16), [UIFont fontWithName:@"HelveticaNeue-Bold" size:12.5],
               [UIColor whiteColor], [UIColor colorWithWhite:0 alpha:0.5], -1, NSTextAlignmentCenter);
}
@end

@implementation RRActionButton
- (id)initWithFrame:(CGRect)f { if ((self = [super initWithFrame:f])) { self.backgroundColor = [UIColor clearColor]; } return self; }
- (void)setHighlighted:(BOOL)h { [super setHighlighted:h]; [self setNeedsDisplay]; }
- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    BOOL d = self.highlighted;
    RRGlossRoundRect(c, self.bounds, 5, d ? RRRGB(52, 62, 82) : RRRGB(152, 166, 190), d ? RRRGB(40, 50, 68) : RRRGB(76, 90, 118), RRRGB(24, 30, 44));
    CGFloat cx = self.bounds.size.width / 2, cy = self.bounds.size.height / 2;
    [[UIColor whiteColor] set];
    CGContextSetLineWidth(c, 2);
    CGContextSetShadowWithColor(c, CGSizeMake(0, 1), 0, [UIColor colorWithWhite:0 alpha:0.4].CGColor);
    /* box with an arrow leaving it */
    CGContextMoveToPoint(c, cx - 1, cy - 6); CGContextAddLineToPoint(c, cx - 6, cy - 6); CGContextAddLineToPoint(c, cx - 6, cy + 6);
    CGContextAddLineToPoint(c, cx + 6, cy + 6); CGContextAddLineToPoint(c, cx + 6, cy + 1);
    CGContextStrokePath(c);
    CGContextMoveToPoint(c, cx - 2, cy + 2); CGContextAddLineToPoint(c, cx + 6, cy - 6); CGContextStrokePath(c);
    CGContextMoveToPoint(c, cx + 1, cy - 7); CGContextAddLineToPoint(c, cx + 7, cy - 7); CGContextAddLineToPoint(c, cx + 7, cy - 1); CGContextStrokePath(c);
}
@end

@implementation RRStarButton
- (id)initWithFrame:(CGRect)f { if ((self = [super initWithFrame:f])) { self.backgroundColor = [UIColor clearColor]; } return self; }
- (void)setOn:(BOOL)on { _on = on; [self setNeedsDisplay]; }
- (void)setHighlighted:(BOOL)h { [super setHighlighted:h]; [self setNeedsDisplay]; }
- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    BOOL d = self.highlighted;
    RRGlossRoundRect(c, self.bounds, 5, d ? RRRGB(52, 62, 82) : RRRGB(152, 166, 190), d ? RRRGB(40, 50, 68) : RRRGB(76, 90, 118), RRRGB(24, 30, 44));
    CGFloat cx = self.bounds.size.width / 2, cy = self.bounds.size.height / 2 + 0.5, R = 9.5, r = 4.2;
    for (int i = 0; i < 10; i++) {
        CGFloat a = -M_PI / 2 + i * M_PI / 5, rad = (i % 2) ? r : R;
        CGPoint pt = CGPointMake(cx + cos(a) * rad, cy + sin(a) * rad);
        if (i == 0) CGContextMoveToPoint(c, pt.x, pt.y); else CGContextAddLineToPoint(c, pt.x, pt.y);
    }
    CGContextClosePath(c);
    CGContextSetShadowWithColor(c, CGSizeMake(0, 1), 0, [UIColor colorWithWhite:0 alpha:0.4].CGColor);
    if (self.on) { [RRRGB(255, 176, 90) setFill]; CGContextFillPath(c); }
    else { [[UIColor whiteColor] setStroke]; CGContextSetLineWidth(c, 1.8); CGContextSetLineJoin(c, kCGLineJoinRound); CGContextStrokePath(c); }
}
@end

@interface RRSegmented ()
@property (nonatomic, strong) NSArray *items;
@property (nonatomic, strong) NSMutableArray *disabled;
@end

@implementation RRSegmented
- (id)initWithItems:(NSArray *)items {
    if ((self = [super initWithFrame:CGRectMake(0, 0, items.count <= 2 ? 148 : MIN(300, items.count * 72), 30)])) {
        self.items = items;
        self.disabled = [NSMutableArray array];
        for (NSUInteger i = 0; i < items.count; i++) [self.disabled addObject:[NSNumber numberWithBool:NO]];
        self.backgroundColor = [UIColor clearColor];
    }
    return self;
}
- (void)setSelectedIndex:(NSInteger)i { _selectedIndex = i; [self setNeedsDisplay]; }
- (void)setEnabled:(BOOL)on forIndex:(NSInteger)i { [self.disabled replaceObjectAtIndex:i withObject:[NSNumber numberWithBool:!on]]; [self setNeedsDisplay]; }

- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGRect b = self.bounds;
    CGFloat sw = b.size.width / self.items.count;
    /* recessed track with glassy segments */
    CGContextSaveGState(c);
    RRRoundRectPath(c, CGRectInset(b, 0.5, 0.5), 6); CGContextClip(c);
    RRFillGradient(c, b, RRRGB(28, 34, 46), RRRGB(54, 62, 80));
    for (NSUInteger i = 0; i < self.items.count; i++) {
        CGRect seg = CGRectMake(i * sw, 0, sw, b.size.height);
        BOOL sel = (NSInteger)i == self.selectedIndex;
        if (sel) {
            RRFillGradient(c, CGRectInset(seg, 0, 1), RRRGB(168, 180, 202), RRRGB(98, 112, 140));
            RRFillGradient(c, CGRectMake(seg.origin.x, 1, sw, b.size.height / 2 - 1), [UIColor colorWithWhite:1 alpha:0.30], [UIColor colorWithWhite:1 alpha:0.03]);
            [[UIColor colorWithWhite:0 alpha:0.35] set]; CGContextFillRect(c, CGRectMake(seg.origin.x, b.size.height - 2, sw, 1));
        } else {
            RRFillGradient(c, seg, RRRGB(104, 116, 140), RRRGB(62, 72, 94));
            RRFillGradient(c, CGRectMake(seg.origin.x, 0, sw, b.size.height / 2), [UIColor colorWithWhite:1 alpha:0.16], [UIColor colorWithWhite:1 alpha:0.01]);
        }
        if (i > 0) { [RRRGB(26, 32, 46) set]; CGContextFillRect(c, CGRectMake(seg.origin.x, 0, 1, b.size.height)); [[UIColor colorWithWhite:1 alpha:0.12] set]; CGContextFillRect(c, CGRectMake(seg.origin.x + 1, 0, 1, b.size.height)); }
    }
    CGContextRestoreGState(c);
    RRRoundRectPath(c, CGRectInset(b, 0.5, 0.5), 6);
    [RRRGB(20, 26, 38) set]; CGContextSetLineWidth(c, 1); CGContextStrokePath(c);
    for (NSUInteger i = 0; i < self.items.count; i++) {
        BOOL off = [[self.disabled objectAtIndex:i] boolValue], sel = (NSInteger)i == self.selectedIndex;
        UIColor *col = off ? [UIColor colorWithWhite:1 alpha:0.35] : (sel ? RRRGB(24, 30, 44) : [UIColor whiteColor]);
        UIColor *sh = sel ? [UIColor colorWithWhite:1 alpha:0.55] : [UIColor colorWithWhite:0 alpha:0.6];
        RRDrawText([[self.items objectAtIndex:i] uppercaseString], CGRectMake(i * sw, 8, sw, 16), [UIFont fontWithName:@"HelveticaNeue-Bold" size:12], col, sh, sel ? 1 : -1, NSTextAlignmentCenter);
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)e {
    CGPoint p = [[touches anyObject] locationInView:self];
    NSInteger i = MIN((NSInteger)self.items.count - 1, MAX(0, (NSInteger)(p.x / (self.bounds.size.width / self.items.count))));
    if ([[self.disabled objectAtIndex:i] boolValue] || i == self.selectedIndex) return;
    self.selectedIndex = i;
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}
@end

#pragma mark - bars

@interface RRShadowView : UIView
@property (nonatomic) BOOL flip;
@end
@implementation RRShadowView
- (id)initWithFrame:(CGRect)f { if ((self = [super initWithFrame:f])) { self.backgroundColor = [UIColor clearColor]; self.userInteractionEnabled = NO; } return self; }
- (void)drawRect:(CGRect)r {
    RRFillGradient(UIGraphicsGetCurrentContext(), self.bounds, [UIColor colorWithWhite:0 alpha:self.flip ? 0 : 0.4], [UIColor colorWithWhite:0 alpha:self.flip ? 0.4 : 0]);
}
@end

@interface RRNavBar : UIView
@property (nonatomic, strong) RRBackButton *back;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIView *titleView, *rightView;
- (void)setTitle:(NSString *)t titleView:(UIView *)tv rightView:(UIView *)rv showBack:(BOOL)b;
@end

@implementation RRNavBar
- (id)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.backgroundColor = [UIColor clearColor];
        self.back = [[RRBackButton alloc] initWithFrame:CGRectMake(6, 7, 58, 30)];
        self.back.backgroundColor = [UIColor clearColor];
        self.back.label = @"Back";
        [self addSubview:self.back];
        self.titleLabel = [[UILabel alloc] init];
        self.titleLabel.backgroundColor = [UIColor clearColor];
        self.titleLabel.textColor = [UIColor whiteColor];
        self.titleLabel.font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:19];
        self.titleLabel.textAlignment = NSTextAlignmentCenter;
        self.titleLabel.shadowColor = [UIColor colorWithWhite:0 alpha:0.5];
        self.titleLabel.shadowOffset = CGSizeMake(0, -1);
        [self addSubview:self.titleLabel];
    }
    return self;
}
- (void)setTitle:(NSString *)t titleView:(UIView *)tv rightView:(UIView *)rv showBack:(BOOL)b {
    if (self.titleView != tv) { [self.titleView removeFromSuperview]; self.titleView = tv; if (tv) [self addSubview:tv]; }
    if (self.rightView != rv) { [self.rightView removeFromSuperview]; self.rightView = rv; if (rv) [self addSubview:rv]; }
    self.titleLabel.text = t;
    self.titleLabel.hidden = tv != nil;
    self.back.hidden = !b;
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    CGFloat w = self.bounds.size.width;
    self.titleLabel.frame = CGRectMake(72, 0, w - 144, NAV_H - 2);
    self.titleView.center = CGPointMake(w / 2, NAV_H / 2 - 1);
    CGRect r = self.rightView.bounds;
    self.rightView.frame = CGRectMake(w - 8 - r.size.width, (NAV_H - r.size.height) / 2 - 1, r.size.width, r.size.height);
}
- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGRect b = self.bounds;
    RRDrawBar(c, CGRectMake(0, 0, b.size.width, NAV_H));
}
@end

@interface RRTabBar : UIView
@property (nonatomic) NSInteger selected;
@property (nonatomic, copy) void (^onSelect)(NSInteger);
@end

@implementation RRTabBar
- (id)initWithFrame:(CGRect)f { if ((self = [super initWithFrame:f])) { self.opaque = YES; } return self; }
- (void)setSelected:(NSInteger)s { _selected = s; [self setNeedsDisplay]; }

- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGRect b = self.bounds;
    CGFloat w = b.size.width;
    RRDrawBar(c, b);
    NSArray *names = [NSArray arrayWithObjects:@"Front Page", @"Subreddits", @"Search", @"Saved", nil];
    CGFloat iw = w / 4;
    for (int i = 0; i < 4; i++) {
        BOOL sel = i == self.selected;
        CGRect cell = CGRectMake(i * iw, 0, iw, TAB_H);
        if (i > 0 && !sel && i - 1 != self.selected) {   /* hairline dividers between idle tabs */
            [[UIColor colorWithWhite:0 alpha:0.4] set]; CGContextFillRect(c, CGRectMake(cell.origin.x - 1, 5, 1, TAB_H - 9));
            [[UIColor colorWithWhite:1 alpha:0.12] set]; CGContextFillRect(c, CGRectMake(cell.origin.x, 5, 1, TAB_H - 9));
        }
        if (sel) {   /* the active tab: a lit, lighter slot like a pressed key */
            CGRect slot = CGRectMake(cell.origin.x, 1, iw, TAB_H - 1);
            CGContextSaveGState(c);
            CGContextClipToRect(c, slot);
            RRFillGradient(c, slot, RRRGB(138, 150, 172), RRRGB(78, 90, 114));
            RRFillGradient(c, CGRectMake(slot.origin.x, slot.origin.y, iw, TAB_H / 2), [UIColor colorWithWhite:1 alpha:0.22], [UIColor colorWithWhite:1 alpha:0.02]);
            RRFillGradient(c, CGRectMake(slot.origin.x, slot.origin.y, iw, 5), [UIColor colorWithWhite:0 alpha:0.35], [UIColor colorWithWhite:0 alpha:0]);
            [[UIColor colorWithWhite:0 alpha:0.55] set];
            CGContextFillRect(c, CGRectMake(slot.origin.x, slot.origin.y, 1, slot.size.height));
            CGContextFillRect(c, CGRectMake(CGRectGetMaxX(slot) - 1, slot.origin.y, 1, slot.size.height));
            CGContextRestoreGState(c);
        }
        /* icon: gradient poured through the glyph's alpha mask, with a drop shadow */
        UIImage *ic = RRTabIcon(i);
        CGRect ir = CGRectMake(cell.origin.x + (iw - 24) / 2, 6, 24, 24);
        CGContextSaveGState(c);
        CGContextSetShadowWithColor(c, CGSizeMake(0, -1), 0, [UIColor colorWithWhite:0 alpha:0.6].CGColor);
        CGContextBeginTransparencyLayer(c, NULL);
        CGContextTranslateCTM(c, ir.origin.x, ir.origin.y + 24);
        CGContextScaleCTM(c, 1, -1);
        CGContextClipToMask(c, CGRectMake(0, 0, 24, 24), ic.CGImage);
        CGContextScaleCTM(c, 1, -1);
        CGContextTranslateCTM(c, -ir.origin.x, -(ir.origin.y + 24));
        if (sel) RRFillGradient(c, ir, RRRGB(255, 255, 255), RRRGB(214, 222, 238));
        else RRFillGradient(c, ir, RRRGB(206, 214, 228), RRRGB(122, 134, 158));
        CGContextEndTransparencyLayer(c);
        CGContextRestoreGState(c);
        RRDrawText([names objectAtIndex:i], CGRectMake(cell.origin.x, 32, iw, 13), [UIFont fontWithName:@"HelveticaNeue-Bold" size:9.5],
                   sel ? [UIColor whiteColor] : RRRGB(188, 198, 216), [UIColor colorWithWhite:0 alpha:0.7], -1, NSTextAlignmentCenter);
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)e {
    NSInteger i = MIN(3, MAX(0, (NSInteger)([[touches anyObject] locationInView:self].x / (self.bounds.size.width / 4))));
    if (self.onSelect) self.onSelect(i);
}
@end

#pragma mark - root controller

static __unsafe_unretained RRRootController *gRoot;

@interface RRRootController () {
    NSMutableArray *_stacks;
    NSInteger _tab;
    RRNavBar *_nav;
    UIView *_content, *_strip;
    RRTabBar *_tabs;
    RRShadowView *_shadowTop, *_shadowBottom;
    CGFloat _top;
}
@end

@implementation RRRootController

+ (RRRootController *)shared { return gRoot; }

- (id)init {
    if ((self = [super init])) {
        gRoot = self;
        _stacks = [NSMutableArray array];
        [_stacks addObject:[NSMutableArray arrayWithObject:[[RRListController alloc] initWithSub:nil]]];
        [_stacks addObject:[NSMutableArray arrayWithObject:[[RRSubsController alloc] init]]];
        [_stacks addObject:[NSMutableArray arrayWithObject:[[RRSearchController alloc] init]]];
        [_stacks addObject:[NSMutableArray arrayWithObject:[[RRListController alloc] initSaved]]];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    _strip = [[UIView alloc] init];
    _strip.backgroundColor = [UIColor blackColor];
    _content = [[UIView alloc] init];
    _content.clipsToBounds = YES;
    _content.backgroundColor = [UIColor colorWithPatternImage:RRLinenImage()];
    _nav = [[RRNavBar alloc] init];
    [_nav.back addTarget:self action:@selector(pop) forControlEvents:UIControlEventTouchUpInside];
    _tabs = [[RRTabBar alloc] init];
    __unsafe_unretained RRRootController *me = self;
    _tabs.onSelect = ^(NSInteger i) { [me selectTab:i]; };
    _shadowTop = [[RRShadowView alloc] init];
    _shadowBottom = [[RRShadowView alloc] init];
    _shadowBottom.flip = YES;
    for (UIView *v in [NSArray arrayWithObjects:_content, _shadowTop, _shadowBottom, _nav, _tabs, _strip, nil]) [self.view addSubview:v];
#ifdef RR_PREVIEW
    UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(0, 2, 320, 16)];
    t.text = @"9:41"; t.textAlignment = NSTextAlignmentCenter; t.backgroundColor = [UIColor clearColor];
    t.textColor = [UIColor whiteColor]; t.font = [UIFont boldSystemFontOfSize:12];
    [_strip addSubview:t];
#endif
    [self showTop];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    /* iOS 6 puts the root view below the status bar already; later systems extend it underneath (and the simulator preview offsets it) */
    CGRect inWindow = [self.view convertRect:self.view.bounds toView:nil];
    _top = fabs(inWindow.origin.y - 20) < 1 ? 0 : 20;   /* iOS 6: view starts at y=20 */
    CGFloat w = b.size.width, h = b.size.height;
    _strip.frame = CGRectMake(0, 0, w, _top);
    _nav.frame = CGRectMake(0, _top, w, NAV_H);
    _tabs.frame = CGRectMake(0, h - TAB_H, w, TAB_H);
    _content.frame = CGRectMake(0, _top + NAV_H, w, h - _top - NAV_H - TAB_H);
    _shadowTop.frame = CGRectMake(0, _top + NAV_H, w, 6);
    _shadowBottom.frame = CGRectMake(0, h - TAB_H - 6, w, 6);
    [_nav setNeedsDisplay]; [_tabs setNeedsDisplay];
    for (NSArray *st in _stacks) { UIViewController *vc = st.lastObject; if (vc.isViewLoaded && vc.view.superview) vc.view.frame = _content.bounds; }
}

- (NSMutableArray *)stack { return [_stacks objectAtIndex:_tab]; }

- (void)showTop {
    UIViewController *vc = [self stack].lastObject;
    if (vc.parentViewController != self) [self addChildViewController:vc];
    UIView *v = vc.view;
    v.frame = _content.bounds;
    v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_content addSubview:v];
    [vc didMoveToParentViewController:self];
    if ([vc respondsToSelector:@selector(rrWillShow)]) [(id<RRScreen>)vc rrWillShow];
    _tabs.selected = _tab;
    [self refreshBar];
}

- (void)refreshBar {
    UIViewController *vc = [self stack].lastObject;
    id<RRScreen> s = (id<RRScreen>)vc;
    NSString *t = [s respondsToSelector:@selector(rrTitle)] ? [s rrTitle] : nil;
    UIView *tv = [s respondsToSelector:@selector(rrTitleView)] ? [s rrTitleView] : nil;
    UIView *rv = [s respondsToSelector:@selector(rrRightView)] ? [s rrRightView] : nil;
    [_nav setTitle:t titleView:tv rightView:rv showBack:[self stack].count > 1];
}

- (void)selectTab:(NSInteger)tab {
    if (tab == _tab) {
        while ([self stack].count > 1) [self popImmediately];   /* tapping the active tab returns to its list */
        return;
    }
    [[[self stack].lastObject view] removeFromSuperview];
    _tab = tab;
    [self showTop];
}

- (void)popImmediately {
    NSMutableArray *st = [self stack];
    UIViewController *gone = st.lastObject;
    [gone willMoveToParentViewController:nil];
    [gone.view removeFromSuperview];
    [gone removeFromParentViewController];
    [st removeLastObject];
    [self showTop];
}

- (void)push:(UIViewController *)vc {
    NSMutableArray *st = [self stack];
    UIViewController *old = st.lastObject;
    CGFloat w = _content.bounds.size.width;
    [st addObject:vc];
    [self addChildViewController:vc];
    UIView *v = vc.view;
    v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    v.frame = CGRectOffset(_content.bounds, w, 0);
    [_content addSubview:v];
    [vc didMoveToParentViewController:self];
    [self refreshBar];
    [UIView animateWithDuration:0.3 animations:^{
        v.frame = self->_content.bounds;
        old.view.frame = CGRectOffset(self->_content.bounds, -w / 3, 0);
    } completion:^(BOOL f) {
        [old.view removeFromSuperview];
        old.view.frame = self->_content.bounds;
    }];
}

- (void)pop {
    NSMutableArray *st = [self stack];
    if (st.count < 2) return;
    UIViewController *gone = st.lastObject, *prev = [st objectAtIndex:st.count - 2];
    CGFloat w = _content.bounds.size.width;
    if ([prev respondsToSelector:@selector(rrWillShow)]) [(id<RRScreen>)prev rrWillShow];
    prev.view.frame = CGRectOffset(_content.bounds, -w / 3, 0);
    [_content insertSubview:prev.view belowSubview:gone.view];
    [st removeLastObject];
    [self refreshBar];
    [UIView animateWithDuration:0.3 animations:^{
        gone.view.frame = CGRectOffset(self->_content.bounds, w, 0);
        prev.view.frame = self->_content.bounds;
    } completion:^(BOOL f) {
        [gone willMoveToParentViewController:nil];
        [gone.view removeFromSuperview];
        [gone removeFromParentViewController];
    }];
}

- (BOOL)shouldAutorotate { return NO; }
- (NSUInteger)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }

@end
