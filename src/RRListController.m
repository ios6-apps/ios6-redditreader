#import "RRListController.h"
#import "RRPostController.h"
#import "RRChrome.h"
#import "RRStyle.h"
#import "RRMedia.h"
#import "RRViewer.h"
#import <MediaPlayer/MediaPlayer.h>

#define CARD_X 0
#define HEAD_H 50
#define ACT_H 44
#define PAD 14

@class RRPostView;

/* play disc, progress ring, badge and note bar: a separate transparent layer, so the picture below can stay a plain image view */
@interface RRPostOverlay : UIView
@property (nonatomic, weak) RRPostView *owner;
@end

@interface RRPostView : UIView
@property (nonatomic, strong) RRPost *post;
@property (nonatomic, strong) UIImage *image;
@property (nonatomic, strong) UIImageView *picture;
@property (nonatomic, strong) RRPostOverlay *overlay;
@property (nonatomic) float progress;               /* video preparation, <0 when idle */
@property (nonatomic, copy) NSString *note;
@property (nonatomic) BOOL saved;
@property (nonatomic, copy) void (^onTap)(int zone);   /* 0 post, 1 media, 2 save */
+ (CGFloat)heightForPost:(RRPost *)p width:(CGFloat)w;
@end

@implementation RRPostView
{ CGPoint _down; }

+ (UIFont *)titleFont { return [UIFont fontWithName:@"HelveticaNeue-Bold" size:15]; }
+ (UIFont *)bodyFont { return [UIFont fontWithName:@"HelveticaNeue" size:13]; }

+ (CGFloat)mediaHeightFor:(RRPost *)p cardWidth:(CGFloat)cw {
    switch (p.media) {
        case RRMediaImage: case RRMediaGif: case RRMediaVideo: case RRMediaGallery: return cw;
        case RRMediaLink: return p.thumb.length ? 170 : 0;
        default: return 0;
    }
}
+ (CGFloat)titleHeight:(RRPost *)p cardWidth:(CGFloat)cw { return RRTextHeight(p.title, [self titleFont], cw - 2 * PAD, 96); }
+ (CGFloat)bodyHeight:(RRPost *)p cardWidth:(CGFloat)cw { return p.text.length && p.media == RRMediaNone ? MIN(RRTextHeight(p.text, [self bodyFont], cw - 2 * PAD, 4000), 72) : 0; }

+ (CGFloat)heightForPost:(RRPost *)p width:(CGFloat)w {
    CGFloat cw = w - 2 * CARD_X;
    CGFloat body = [self bodyHeight:p cardWidth:cw];
    return 8 + HEAD_H + [self mediaHeightFor:p cardWidth:cw] + ACT_H + [self titleHeight:p cardWidth:cw] + (body ? body + 6 : 0) + 12;
}

- (id)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.opaque = YES; self.backgroundColor = [UIColor colorWithPatternImage:RRLinenImage()]; self.progress = -1;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.contentMode = UIViewContentModeRedraw;
        self.picture = [[UIImageView alloc] init];
        self.picture.contentMode = UIViewContentModeScaleAspectFill;
        self.picture.clipsToBounds = YES; self.picture.opaque = YES;
        self.picture.backgroundColor = [UIColor clearColor];
        [self addSubview:self.picture];
        self.overlay = [[RRPostOverlay alloc] init];
        self.overlay.owner = self; self.overlay.opaque = NO; self.overlay.backgroundColor = [UIColor clearColor];
        self.overlay.userInteractionEnabled = NO;
        [self addSubview:self.overlay];
    }
    return self;
}

- (void)setImage:(UIImage *)img { _image = img; self.picture.image = img; }

- (BOOL)overlayNeeded {
    RRPost *p = self.post;
    return p.media == RRMediaVideo || self.progress >= 0 || self.note.length || p.media == RRMediaGif || p.media == RRMediaGallery || (p.media == RRMediaLink && p.domain.length);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect mr = self.post ? [self mediaRect] : CGRectZero;
    self.picture.frame = mr; self.overlay.frame = mr;
    self.picture.hidden = mr.size.height <= 0;
    self.overlay.hidden = mr.size.height <= 0 || ![self overlayNeeded];
}

- (void)setNeedsDisplay { [super setNeedsDisplay]; [self setNeedsLayout]; [self.overlay setNeedsDisplay]; }

- (CGRect)mediaRect {
    CGFloat cw = self.bounds.size.width - 2 * CARD_X;
    return CGRectMake(CARD_X, 8 + HEAD_H, cw, [RRPostView mediaHeightFor:self.post cardWidth:cw]);
}

static UIColor *RRAvatarColor(NSString *s) {
    unsigned h = 7;
    for (NSUInteger i = 0; i < s.length; i++) h = h * 31 + [s characterAtIndex:i];
    CGFloat hue = (h % 360) / 360.0;
    return [UIColor colorWithHue:hue saturation:0.62 brightness:0.82 alpha:1];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGFloat w = self.bounds.size.width, cw = w - 2 * CARD_X;
    RRPost *p = self.post;
    CGRect card = CGRectMake(0, 8, w, self.bounds.size.height - 8);

    /* a full-width row on the pale table, with a soft shadow in the gap above it */
    RRFillGradient(c, CGRectMake(0, 0, w, 8), [UIColor colorWithWhite:0 alpha:0.0], [UIColor colorWithWhite:0 alpha:0.14]);
    CGContextSaveGState(c);
    CGContextClipToRect(c, card);
    RRDrawPanel(c, card);

    /* header: round avatar with the sub's first letter, name, time */
    CGRect av = CGRectMake(card.origin.x + 10, card.origin.y + 8, 34, 34);
    NSString *sub = p.sub.length ? p.sub : @"r";
    CGContextSaveGState(c);
    CGContextAddEllipseInRect(c, av); CGContextClip(c);
    UIColor *base = RRAvatarColor(sub);
    CGFloat hh, ss, bb, aa; [base getHue:&hh saturation:&ss brightness:&bb alpha:&aa];
    RRFillGradient(c, av, [UIColor colorWithHue:hh saturation:ss * 0.7 brightness:MIN(1, bb + 0.12) alpha:1], [UIColor colorWithHue:hh saturation:ss brightness:bb * 0.7 alpha:1]);
    RRFillGradient(c, CGRectMake(av.origin.x, av.origin.y, 34, 15), [UIColor colorWithWhite:1 alpha:0.35], [UIColor colorWithWhite:1 alpha:0.02]);
    CGContextRestoreGState(c);
    [[UIColor colorWithWhite:0 alpha:0.45] set]; CGContextSetLineWidth(c, 1); CGContextStrokeEllipseInRect(c, CGRectInset(av, 0.5, 0.5));
    RRDrawText([[sub substringToIndex:1] uppercaseString], CGRectMake(av.origin.x, av.origin.y + 6, 34, 22), [UIFont fontWithName:@"HelveticaNeue-Bold" size:18], [UIColor whiteColor], [UIColor colorWithWhite:0 alpha:0.5], -1, NSTextAlignmentCenter);
    CGFloat tx = CGRectGetMaxX(av) + 10;
    RRDrawText([@"r/" stringByAppendingString:sub], CGRectMake(tx, card.origin.y + 9, cw - 120, 17), [UIFont fontWithName:@"HelveticaNeue-Bold" size:14], RRInk(), [UIColor whiteColor], 1, NSTextAlignmentLeft);
    RRDrawText(p.author.length ? [@"u/" stringByAppendingString:p.author] : @"", CGRectMake(tx, card.origin.y + 26, cw - 120, 15), [UIFont fontWithName:@"HelveticaNeue" size:12], RRSoftInk(), [UIColor whiteColor], 1, NSTextAlignmentLeft);
    RRDrawText(RRTimeAgo(p.created), CGRectMake(CGRectGetMaxX(card) - 70, card.origin.y + 14, 60, 16), [UIFont fontWithName:@"HelveticaNeue" size:12], RRSoftInk(), [UIColor whiteColor], 1, NSTextAlignmentRight);

    /* the picture itself is an image view over this rect; only the placeholder and the edge lines are drawn here */
    CGRect mr = [self mediaRect];
    CGFloat y = CGRectGetMaxY(mr);
    if (mr.size.height > 0) {
        if (!self.image) {
            RRFillGradient(c, mr, RRRGB(96, 104, 120), RRRGB(60, 66, 80));
            RRDrawText(p.media == RRMediaLink ? @"↗" : @"…", CGRectMake(mr.origin.x, CGRectGetMidY(mr) - 20, mr.size.width, 40), [UIFont boldSystemFontOfSize:34], RRRGB(150, 158, 174), nil, 0, NSTextAlignmentCenter);
        }
        [[UIColor colorWithWhite:0 alpha:0.35] set]; CGContextFillRect(c, CGRectMake(mr.origin.x, mr.origin.y - 1, mr.size.width, 1));
        CGContextFillRect(c, CGRectMake(mr.origin.x, CGRectGetMaxY(mr), mr.size.width, 1));
    }

    /* action row: comments and save */
    CGRect bub = CGRectMake(card.origin.x + 14, y + 12, 24, 20);
    [RRRGB(86, 96, 114) set]; CGContextSetLineWidth(c, 2);
    {
        CGFloat x0 = bub.origin.x, y0 = bub.origin.y, x1 = CGRectGetMaxX(bub), y1 = CGRectGetMaxY(bub) - 4, rr = 6;
        CGContextMoveToPoint(c, x0 + rr, y0);
        CGContextAddArcToPoint(c, x1, y0, x1, y1, rr); CGContextAddArcToPoint(c, x1, y1, x0, y1, rr);
        CGContextAddLineToPoint(c, x0 + 11, y1); CGContextAddLineToPoint(c, x0 + 5, y1 + 5); CGContextAddLineToPoint(c, x0 + 5, y1);
        CGContextAddArcToPoint(c, x0, y1, x0, y0, rr); CGContextAddArcToPoint(c, x0, y0, x1, y0, rr);
        CGContextClosePath(c); CGContextStrokePath(c);
    }
    RRDrawText(@"Comments", CGRectMake(bub.origin.x + 32, y + 13, 90, 18), [UIFont fontWithName:@"HelveticaNeue-Bold" size:13], RRRGB(86, 96, 114), [UIColor whiteColor], 1, NSTextAlignmentLeft);
    CGPoint sc = CGPointMake(CGRectGetMaxX(card) - 34, y + 22);
    for (int i = 0; i < 10; i++) {
        CGFloat a = -M_PI / 2 + i * M_PI / 5, rad = (i % 2) ? 5.5 : 12;
        CGPoint pt = CGPointMake(sc.x + cos(a) * rad, sc.y + 1 + sin(a) * rad);
        if (i == 0) CGContextMoveToPoint(c, pt.x, pt.y); else CGContextAddLineToPoint(c, pt.x, pt.y);
    }
    CGContextClosePath(c);
    if (self.saved) { [RRRGB(250, 140, 40) setFill]; [RRRGB(170, 70, 0) setStroke]; CGContextSetLineJoin(c, kCGLineJoinRound); CGContextDrawPath(c, kCGPathFillStroke); }
    else { [RRRGB(86, 96, 114) setStroke]; CGContextSetLineJoin(c, kCGLineJoinRound); CGContextStrokePath(c); }
    y += ACT_H;

    /* caption */
    CGFloat th = [RRPostView titleHeight:p cardWidth:cw];
    RRDrawText(p.title, CGRectMake(card.origin.x + PAD, y - 2, cw - 2 * PAD, th), [RRPostView titleFont], RRInk(), [UIColor whiteColor], 1, NSTextAlignmentLeft);
    y += th + 4;
    CGFloat bh = [RRPostView bodyHeight:p cardWidth:cw];
    if (bh) RRDrawText(p.text, CGRectMake(card.origin.x + PAD, y, cw - 2 * PAD, bh), [RRPostView bodyFont], RRSoftInk(), [UIColor whiteColor], 1, NSTextAlignmentLeft);
    CGContextRestoreGState(c);
}

- (void)touchesBegan:(NSSet *)t withEvent:(UIEvent *)e { _down = [[t anyObject] locationInView:self]; }
- (void)touchesEnded:(NSSet *)t withEvent:(UIEvent *)e {
    CGPoint p = [[t anyObject] locationInView:self];
    if (fabs(p.x - _down.x) > 10 || fabs(p.y - _down.y) > 10) return;
    CGRect mr = [self mediaRect];
    int zone = 0;
    if (mr.size.height > 0 && CGRectContainsPoint(mr, p)) zone = 1;
    else if (p.y > CGRectGetMaxY(mr) && p.y < CGRectGetMaxY(mr) + ACT_H && p.x > self.bounds.size.width - 76) zone = 2;
    if (self.onTap) self.onTap(zone);
}
@end

@implementation RRPostOverlay
- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    RRPostView *v = self.owner; RRPost *p = v.post;
    if (!p) return;
    CGRect mr = self.bounds;
    BOOL play = p.media == RRMediaVideo;
    CGPoint m = CGPointMake(CGRectGetMidX(mr), CGRectGetMidY(mr));
    if (play || v.progress >= 0) {
        CGRect disc = CGRectMake(m.x - 33, m.y - 33, 66, 66);
        CGContextSaveGState(c);
        CGContextAddEllipseInRect(c, disc); CGContextClip(c);
        RRFillGradient(c, disc, [UIColor colorWithWhite:0.28 alpha:0.78], [UIColor colorWithWhite:0 alpha:0.85]);
        CGContextRestoreGState(c);
        [[UIColor colorWithWhite:1 alpha:0.9] set]; CGContextSetLineWidth(c, 2); CGContextStrokeEllipseInRect(c, CGRectInset(disc, 1, 1));
        if (v.progress >= 0) {
            CGContextSetLineWidth(c, 4); [RRRGB(246, 142, 62) set];
            CGContextAddArc(c, m.x, m.y, 27, -M_PI / 2, -M_PI / 2 + 2 * M_PI * MAX(0.03, MIN(1, v.progress)), 0);
            CGContextStrokePath(c);
        } else {
            [[UIColor whiteColor] setFill];
            CGContextMoveToPoint(c, m.x - 9, m.y - 15); CGContextAddLineToPoint(c, m.x + 16, m.y); CGContextAddLineToPoint(c, m.x - 9, m.y + 15); CGContextFillPath(c);
        }
    }
    NSString *tag = p.media == RRMediaGif ? @"GIF" : p.media == RRMediaGallery ? @"GALLERY" : p.media == RRMediaLink ? p.domain : nil;
    if (tag.length) {
        CGSize ts = [tag sizeWithFont:[UIFont boldSystemFontOfSize:11]];
        CGRect br = CGRectMake(mr.origin.x + 10, mr.origin.y + 10, MIN(ts.width + 18, mr.size.width - 20), 20);
        RRGlossRoundRect(c, br, 10, RRRGB(246, 142, 62), RRRGB(200, 70, 4), RRRGB(110, 36, 0));
        RRDrawText(tag, CGRectMake(br.origin.x, br.origin.y + 3, br.size.width, 14), [UIFont boldSystemFontOfSize:11], [UIColor whiteColor], [UIColor colorWithWhite:0 alpha:0.4], -1, NSTextAlignmentCenter);
    }
    if (v.note.length) {
        CGRect bar = CGRectMake(mr.origin.x, CGRectGetMaxY(mr) - 26, mr.size.width, 26);
        [[UIColor colorWithWhite:0 alpha:0.7] setFill]; CGContextFillRect(c, bar);
        RRDrawText(v.note, CGRectMake(bar.origin.x + 8, bar.origin.y + 5, bar.size.width - 16, 16), [UIFont boldSystemFontOfSize:12], [UIColor whiteColor], nil, 0, NSTextAlignmentCenter);
    }
}
@end

@interface RRPostCell : UITableViewCell
@property (nonatomic, strong) RRPostView *card;
@end
@implementation RRPostCell
- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    if ((self = [super initWithStyle:style reuseIdentifier:rid])) {
        self.backgroundColor = [UIColor clearColor]; self.contentView.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.card = [[RRPostView alloc] initWithFrame:self.contentView.bounds];
        [self.contentView addSubview:self.card];
    }
    return self;
}
@end

typedef NS_ENUM(NSInteger, RRListMode) { RRListFeed, RRListSaved, RRListSearch };

@interface RRListController () <RRScreen>
@property (nonatomic) RRListMode mode;
@property (nonatomic, copy) NSString *sub, *query, *after;
@property (nonatomic, strong) NSMutableArray *posts;
@property (nonatomic, strong) NSMutableArray *heights;
@property (nonatomic) CGFloat heightsWidth;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, strong) RRSegmented *seg;
@property (nonatomic) BOOL loading;
@property (nonatomic, copy) NSString *waitNote;
@property (nonatomic, strong) RRVideo *videoJob;
@property (nonatomic, copy) NSString *videoPid, *videoNote;
@property (nonatomic) float videoProgress;
@end

@implementation RRListController

- (id)initWithSub:(NSString *)sub {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        self.mode = RRListFeed; self.sub = sub;
        self.title = sub ? [@"r/" stringByAppendingString:sub] : @"Popular";
        self.posts = [NSMutableArray array]; self.heights = [NSMutableArray array];
    }
    return self;
}
- (id)initSaved {
    if ((self = [self initWithSub:nil])) { self.mode = RRListSaved; self.title = @"Saved"; }
    return self;
}
- (id)initSearch:(NSString *)q {
    if ((self = [self initWithSub:nil])) { self.mode = RRListSearch; self.query = q; self.title = q; }
    return self;
}

- (NSString *)rrTitle { return self.mode == RRListFeed ? nil : self.title; }
- (UIView *)rrTitleView { return self.mode == RRListFeed ? self.seg : nil; }

- (NSString *)sortName { return [[NSArray arrayWithObjects:@"hot", @"new", @"rising", @"top", nil] objectAtIndex:self.seg ? self.seg.selectedIndex : 0]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = [UIColor colorWithPatternImage:RRLinenImage()];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.allowsSelection = NO;
    if (self.mode == RRListFeed) {
        self.seg = [[RRSegmented alloc] initWithItems:[NSArray arrayWithObjects:@"Hot", @"New", @"Rising", @"Top", nil]];
        [self.seg addTarget:self action:@selector(sortChanged) forControlEvents:UIControlEventValueChanged];
    }
    if (self.mode != RRListSaved) {
        self.refreshControl = [[UIRefreshControl alloc] init];
        self.refreshControl.tintColor = RRRGB(84, 94, 112);
        [self.refreshControl addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];
    }
    self.status = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 320, 110)];
    self.status.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.status.backgroundColor = [UIColor clearColor];
    self.status.textAlignment = NSTextAlignmentCenter;
    self.status.numberOfLines = 5;
    self.status.font = [UIFont fontWithName:@"HelveticaNeue-Italic" size:15];
    self.status.textColor = RRRGB(84, 94, 112);
    self.status.shadowColor = [UIColor colorWithWhite:1 alpha:0.8];
    self.status.shadowOffset = CGSizeMake(0, 1);
    self.tableView.tableHeaderView = self.status;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(feedStatus:) name:RRFeedStatusNotification object:nil];
    [self load:NO more:NO];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)feedStatus:(NSNotification *)n {
    self.waitNote = [n.userInfo objectForKey:@"text"];
    if (self.loading && !self.posts.count) { self.status.text = self.waitNote ?: @"Loading…"; }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.posts.count && fabs(self.tableView.bounds.size.width - self.heightsWidth) > 0.5) [self remeasure];
}

- (void)rrWillShow { if (self.mode == RRListSaved && self.isViewLoaded) [self load:NO more:NO]; }

- (void)remeasure {
    CGFloat w = self.tableView.bounds.size.width;
    [self.heights removeAllObjects];
    for (RRPost *p in self.posts) [self.heights addObject:[NSNumber numberWithFloat:(float)[RRPostView heightForPost:p width:w]]];
    self.heightsWidth = w;
}

- (void)sortChanged { [self.posts removeAllObjects]; [self.heights removeAllObjects]; self.after = nil; [self.tableView reloadData]; [self load:NO more:NO]; }
- (void)refresh { [self load:YES more:NO]; }

- (void)show:(NSArray *)posts append:(BOOL)append {
    if (!append) [self.posts removeAllObjects];
    NSMutableSet *seen = [NSMutableSet set];
    for (RRPost *p in self.posts) [seen addObject:p.pid];
    for (RRPost *p in posts) if (![seen containsObject:p.pid]) [self.posts addObject:p];
    [self remeasure];
    self.status.text = self.mode == RRListSaved ? @"Nothing saved yet.\nTap the star on a post." : @"Nothing here yet.";
    self.tableView.tableHeaderView = self.posts.count ? nil : self.status;
    [self.tableView reloadData];
}

- (void)load:(BOOL)force more:(BOOL)more {
    if (self.mode == RRListSaved) { self.after = nil; [self show:[RRSaved posts] append:NO]; return; }
    if (self.loading) { if (!more) [self.refreshControl endRefreshing]; return; }
    self.loading = YES;
    if (!self.posts.count) { self.status.text = self.waitNote ?: @"Loading…"; self.tableView.tableHeaderView = self.status; }
    RRPostsBlock done = ^(NSArray *posts, NSString *after, NSString *err) {
        self.loading = NO;
        [self.refreshControl endRefreshing];
        if (err && !posts.count) {
            if (!self.posts.count) { self.status.text = [NSString stringWithFormat:@"Couldn't load posts.\n%@\nPull down to retry.", err]; self.tableView.tableHeaderView = self.status; }
            else [self.tableView reloadData];
            return;
        }
        self.after = after;
        [self show:posts append:more];
#ifdef RR_PREVIEW   /* simulator screenshots: RR_OPEN=n opens the nth post of the first list */
        static BOOL opened;
        if (getenv("RR_OPEN") && !opened && posts.count) {
            opened = YES;
            [[RRRootController shared] push:[[RRPostController alloc] initWithPost:[posts objectAtIndex:atoi(getenv("RR_OPEN"))]]];
        }
#endif
    };
    if (self.mode == RRListSearch) { [RRFeed searchQuery:self.query sort:@"relevance" done:done]; return; }
    NSString *path = [NSString stringWithFormat:@"r/%@/%@", self.sub ?: @"popular", [self sortName]];
    [RRFeed loadPath:path period:@"day" after:more ? self.after : nil force:force done:done];
}

#pragma mark table

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.posts.count + (self.after ? 1 : 0); }

- (CGFloat)tableView:(UITableView *)t heightForRowAtIndexPath:(NSIndexPath *)ip { return ip.row < (NSInteger)self.heights.count ? [[self.heights objectAtIndex:ip.row] floatValue] : 54; }

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.row >= (NSInteger)self.posts.count) {
        UITableViewCell *m = [t dequeueReusableCellWithIdentifier:@"more"];
        if (!m) {
            m = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"more"];
            m.backgroundColor = [UIColor clearColor]; m.selectionStyle = UITableViewCellSelectionStyleNone;
            m.textLabel.textAlignment = NSTextAlignmentCenter; m.textLabel.font = [UIFont fontWithName:@"HelveticaNeue-Italic" size:15];
            m.textLabel.textColor = RRRGB(84, 94, 112); m.textLabel.backgroundColor = [UIColor clearColor];
        }
        m.textLabel.text = self.loading ? (self.waitNote ?: @"Loading…") : @"Load more";
        if (!self.loading) [self performSelector:@selector(loadMore) withObject:nil afterDelay:0];
        return m;
    }
    RRPostCell *cell = [t dequeueReusableCellWithIdentifier:@"post"];
    if (!cell) cell = [[RRPostCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"post"];
    RRPost *p = [self.posts objectAtIndex:ip.row];
    [self configure:cell.card for:p];
    return cell;
}

/* the picture shown in the feed: the real image for picture posts, the preview picture for everything else */
- (NSString *)feedImageURL:(RRPost *)p { return p.media == RRMediaImage ? p.link : p.thumb; }

- (void)configure:(RRPostView *)card for:(RRPost *)p {
    card.post = p;
    card.saved = [RRSaved contains:p.pid];
    BOOL mine = [self.videoPid isEqualToString:p.pid];
    card.progress = mine ? self.videoProgress : -1;
    card.note = mine ? self.videoNote : nil;
    NSString *url = [self feedImageURL:p];
    card.image = [RRMedia cachedImage:url maxPixel:640];
    if (!card.image && url.length) {
        [RRMedia image:url maxPixel:640 done:^(UIImage *img, NSString *err) {
            if (img && card.post == p) card.image = img;
        }];
    }
    __unsafe_unretained RRListController *me = self;
    card.onTap = ^(int zone) { [me tapped:zone post:p card:card]; };
    [card setNeedsDisplay];
}

- (void)tapped:(int)zone post:(RRPost *)p card:(RRPostView *)card {
    if (zone == 2) { card.saved = [RRSaved toggle:p]; [card setNeedsDisplay]; if (self.mode == RRListSaved && !card.saved) [self load:NO more:NO]; return; }
    if (zone == 1) {
        switch (p.media) {
            case RRMediaImage: [[RRRootController shared] presentViewController:[[RRViewer alloc] initWithURL:p.link animated:NO placeholder:card.image] animated:YES completion:nil]; return;
            case RRMediaGif: [[RRRootController shared] presentViewController:[[RRViewer alloc] initWithURL:p.link animated:YES placeholder:nil] animated:YES completion:nil]; return;
            case RRMediaVideo: [self playVideo:p]; return;
            default: break;
        }
    }
    [[RRRootController shared] push:[[RRPostController alloc] initWithPost:p]];
}

- (void)refreshVideoCell {
    for (RRPostCell *c in self.tableView.visibleCells)
        if ([c isKindOfClass:[RRPostCell class]] && c.card.post && [c.card.post.pid isEqualToString:self.videoPid]) { c.card.progress = self.videoProgress; c.card.note = self.videoNote; [c.card setNeedsDisplay]; }
}

- (void)playVideo:(RRPost *)p {
    if (self.videoJob) {    /* tapping again while one is being prepared cancels it */
        BOOL same = [self.videoPid isEqualToString:p.pid];
        [self.videoJob cancel]; self.videoJob = nil;
        NSString *old = self.videoPid; self.videoPid = nil;
        self.videoProgress = -1; self.videoNote = nil;
        for (RRPostCell *c in self.tableView.visibleCells) if ([c isKindOfClass:[RRPostCell class]] && [c.card.post.pid isEqualToString:old]) { c.card.progress = -1; c.card.note = nil; [c.card setNeedsDisplay]; }
        if (same) return;
    }
    self.videoPid = p.pid; self.videoProgress = 0; self.videoNote = @"Downloading video — tap to cancel";
    [self refreshVideoCell];
    self.videoJob = [RRVideo prepare:p.mediaURL progress:^(float f, NSString *stage) {
        self.videoProgress = f; self.videoNote = [stage stringByAppendingString:@" — tap to cancel"]; [self refreshVideoCell];
    } done:^(NSString *path, NSString *err) {
        self.videoJob = nil;
        self.videoProgress = -1;
        self.videoNote = err ? [@"Couldn't play: " stringByAppendingString:err] : nil;
        [self refreshVideoCell];
        if (err) return;
        self.videoPid = nil; [self refreshVideoCell];
        MPMoviePlayerViewController *mp = [[MPMoviePlayerViewController alloc] initWithContentURL:[NSURL fileURLWithPath:path]];
        [[RRRootController shared] presentMoviePlayerViewControllerAnimated:mp];
    }];
}

- (void)loadMore { if (self.after && !self.loading && self.mode != RRListSearch) [self load:NO more:YES]; }

- (BOOL)tableView:(UITableView *)t canEditRowAtIndexPath:(NSIndexPath *)ip { return self.mode == RRListSaved && ip.row < (NSInteger)self.posts.count; }

- (void)tableView:(UITableView *)t commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)ip {
    if (style != UITableViewCellEditingStyleDelete) return;
    [RRSaved remove:[[self.posts objectAtIndex:ip.row] pid]];
    [self.posts removeObjectAtIndex:ip.row]; [self.heights removeObjectAtIndex:ip.row];
    [t deleteRowsAtIndexPaths:[NSArray arrayWithObject:ip] withRowAnimation:UITableViewRowAnimationFade];
    if (!self.posts.count) [self show:[NSArray array] append:NO];
}


@end
