#import "RRPostController.h"
#import "RRChrome.h"
#import "RRStyle.h"
#import "RRMedia.h"
#import "RRViewer.h"
#import "RRFeed.h"
#import <MediaPlayer/MediaPlayer.h>

#define SIDE 10
#define PAPER_W (320 - 2 * SIDE)

#pragma mark - comment card

@interface RRCommentView : UIView
@property (nonatomic, strong) RRComment *comment;
+ (UIFont *)bodyFont;
+ (CGFloat)heightFor:(RRComment *)c width:(CGFloat)w;
@end

@implementation RRCommentView
+ (UIFont *)bodyFont { return [UIFont fontWithName:@"HelveticaNeue" size:14]; }
+ (CGFloat)heightFor:(RRComment *)c width:(CGFloat)w { return 30 + RRTextHeight(c.text, [self bodyFont], w - 28, 1400) + 14; }
- (id)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) { self.opaque = NO; self.backgroundColor = [UIColor clearColor]; self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; }
    return self;
}
- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGFloat w = self.bounds.size.width;
    CGRect row = self.bounds;
    RRFillGradient(c, row, RRRGB(255, 255, 255), RRRGB(243, 246, 250));
    [RRRGB(206, 212, 224) set]; CGContextFillRect(c, CGRectMake(0, row.size.height - 1, w, 1));
    RRComment *cm = self.comment;
    RRDrawText(cm.author, CGRectMake(14, 10, w - 100, 16), [UIFont fontWithName:@"HelveticaNeue-Bold" size:12], RRAccent(), nil, 0, NSTextAlignmentLeft);
    RRDrawText(RRTimeAgo(cm.created), CGRectMake(w - 86, 10, 72, 16), [UIFont fontWithName:@"HelveticaNeue" size:12], RRSoftInk(), nil, 0, NSTextAlignmentRight);
    CGFloat th = RRTextHeight(cm.text, [RRCommentView bodyFont], w - 28, 1400);
    RRDrawText(cm.text, CGRectMake(14, 30, w - 28, th), [RRCommentView bodyFont], RRInk(), nil, 0, NSTextAlignmentLeft);
}
@end

@interface RRCommentCell : UITableViewCell
@property (nonatomic, strong) RRCommentView *card;
@end
@implementation RRCommentCell
- (id)initWithStyle:(UITableViewCellStyle)s reuseIdentifier:(NSString *)r {
    if ((self = [super initWithStyle:s reuseIdentifier:r])) {
        self.backgroundColor = [UIColor clearColor]; self.contentView.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.card = [[RRCommentView alloc] initWithFrame:self.contentView.bounds];
        [self.contentView addSubview:self.card];
    }
    return self;
}
@end

#pragma mark - media block

/* the picture area of a post: thumbnail or full picture, a play badge for video, a progress bar while a video is prepared */
@interface RRMediaView : UIControl
@property (nonatomic, strong) UIImage *image;
@property (nonatomic) RRMediaKind kind;
@property (nonatomic) float progress;       /* <0: idle */
@property (nonatomic, copy) NSString *caption;
@end

@implementation RRMediaView
- (id)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) { self.backgroundColor = [UIColor clearColor]; self.progress = -1; self.contentMode = UIViewContentModeRedraw; }
    return self;
}
- (void)setImage:(UIImage *)i { _image = i; [self setNeedsDisplay]; }
- (void)setProgress:(float)p { _progress = p; [self setNeedsDisplay]; }
- (void)setHighlighted:(BOOL)h { [super setHighlighted:h]; [self setNeedsDisplay]; }
- (void)setCaption:(NSString *)s { _caption = [s copy]; [self setNeedsDisplay]; }
- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGRect b = CGRectInset(self.bounds, 4, 4);
    CGContextSaveGState(c);
    CGContextSetShadowWithColor(c, CGSizeMake(0, 2), 5, [UIColor colorWithWhite:0 alpha:0.6].CGColor);
    [RRRGB(30, 26, 22) setFill]; CGContextFillRect(c, b);
    CGContextRestoreGState(c);
    CGContextSaveGState(c);
    CGContextClipToRect(c, b);
    if (self.image) {
        CGSize is = self.image.size;
        CGFloat k = MIN(b.size.width / is.width, b.size.height / is.height);
        CGRect r = CGRectMake(b.origin.x + (b.size.width - is.width * k) / 2, b.origin.y + (b.size.height - is.height * k) / 2, is.width * k, is.height * k);
        [self.image drawInRect:r];
    }
    CGContextRestoreGState(c);
    BOOL play = self.kind == RRMediaVideo;
    if (play || self.progress >= 0) {
        CGPoint m = CGPointMake(CGRectGetMidX(b), CGRectGetMidY(b));
        CGRect disc = CGRectMake(m.x - 30, m.y - 30, 60, 60);
        CGContextSaveGState(c);
        CGContextAddEllipseInRect(c, disc); CGContextClip(c);
        RRFillGradient(c, disc, [UIColor colorWithWhite:0.25 alpha:self.highlighted ? 0.95 : 0.75], [UIColor colorWithWhite:0 alpha:self.highlighted ? 0.95 : 0.8]);
        CGContextRestoreGState(c);
        [[UIColor colorWithWhite:1 alpha:0.85] set]; CGContextSetLineWidth(c, 2); CGContextStrokeEllipseInRect(c, CGRectInset(disc, 1, 1));
        if (self.progress >= 0) {
            CGContextSetLineWidth(c, 4); [RRRGB(246, 142, 62) set];
            CGContextAddArc(c, m.x, m.y, 25, -M_PI / 2, -M_PI / 2 + 2 * M_PI * MAX(0.02, MIN(1, self.progress)), 0);
            CGContextStrokePath(c);
        } else {
            [[UIColor whiteColor] setFill];
            CGContextMoveToPoint(c, m.x - 8, m.y - 13); CGContextAddLineToPoint(c, m.x + 14, m.y); CGContextAddLineToPoint(c, m.x - 8, m.y + 13); CGContextFillPath(c);
        }
    }
    if (self.caption.length) {
        CGRect bar = CGRectMake(b.origin.x, CGRectGetMaxY(b) - 24, b.size.width, 24);
        [[UIColor colorWithWhite:0 alpha:0.65] setFill]; CGContextFillRect(c, bar);
        RRDrawText(self.caption, CGRectMake(bar.origin.x + 8, bar.origin.y + 4, bar.size.width - 16, 16), [UIFont boldSystemFontOfSize:12], [UIColor whiteColor], nil, 0, NSTextAlignmentCenter);
    }
}
@end

#pragma mark - web page

@interface RRWebController () <RRScreen, UIWebViewDelegate>
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, strong) UIWebView *web;
@property (nonatomic, copy) NSString *heading;
@end

@implementation RRWebController
- (id)initWithURL:(NSURL *)url title:(NSString *)title { if ((self = [super init])) { self.url = url; self.heading = title; } return self; }
- (NSString *)rrTitle { return self.heading.length ? self.heading : self.url.host; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.web = [[UIWebView alloc] initWithFrame:self.view.bounds];
    self.web.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.web.scalesPageToFit = YES;
    self.web.backgroundColor = RRRGB(236, 232, 222);
    [self.view addSubview:self.web];
    [self.web loadRequest:[NSURLRequest requestWithURL:self.url]];
}
@end

#pragma mark - post screen

@interface RRPostController () <RRScreen, UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) RRPost *post;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray *comments;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, strong) RRStarButton *star;
@property (nonatomic, strong) RRMediaView *media;
@property (nonatomic, strong) UIView *header;
@property (nonatomic, strong) UIView *rightItem;
@property (nonatomic, strong) RRVideo *videoJob;
@property (nonatomic, strong) UIImage *fullImage;
@property (nonatomic, copy) NSString *mediaNote;
@property (nonatomic) BOOL loadingComments;
@end

@implementation RRPostController

- (id)initWithPost:(RRPost *)post { if ((self = [super init])) self.post = post; return self; }

- (NSString *)rrTitle { return self.post.sub.length ? [@"r/" stringByAppendingString:self.post.sub] : @"Post"; }
- (UIView *)rrRightView { return self.rightItem; }

- (void)dealloc { [self.videoJob cancel]; [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    UIView *v = self.view;
    self.table = [[UITableView alloc] initWithFrame:v.bounds style:UITableViewStylePlain];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.backgroundColor = [UIColor colorWithPatternImage:RRLinenImage()];
    self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.table.dataSource = self; self.table.delegate = self;
    [v addSubview:self.table];

    self.star = [[RRStarButton alloc] initWithFrame:CGRectMake(0, 0, 34, 30)];
    self.star.on = [RRSaved contains:self.post.pid];
    [self.star addTarget:self action:@selector(toggleStar) forControlEvents:UIControlEventTouchUpInside];
    self.rightItem = self.star;

    self.status = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 320, 70)];
    self.status.backgroundColor = [UIColor clearColor]; self.status.textAlignment = NSTextAlignmentCenter; self.status.numberOfLines = 4;
    self.status.font = [UIFont fontWithName:@"HelveticaNeue-Italic" size:14]; self.status.textColor = RRRGB(84, 94, 112);
    self.status.shadowColor = [UIColor colorWithWhite:1 alpha:0.8]; self.status.shadowOffset = CGSizeMake(0, 1);
    self.status.text = @"Loading comments…";

    [self buildHeader];
    [self loadMedia];
#ifdef RR_PREVIEW
    if (getenv("RR_PLAY") && self.post.media == RRMediaVideo) [self performSelector:@selector(playVideo) withObject:nil afterDelay:1];
#endif
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(feedStatus:) name:RRFeedStatusNotification object:nil];
    self.loadingComments = YES;
    [RRFeed loadCommentsFor:self.post done:^(RRPost *p, NSArray *cs, NSString *err) {
        self.loadingComments = NO;
        if (err) { self.status.text = [NSString stringWithFormat:@"Couldn't load comments.\n%@", err]; return; }
        self.comments = cs;
        [self buildHeader];     /* the feed may have supplied the post's text */
        self.status.text = cs.count ? @"" : @"No comments yet.";
        [self.table reloadData];
    }];
}

- (void)feedStatus:(NSNotification *)n {
    NSString *t = [n.userInfo objectForKey:@"text"];
    if (self.loadingComments) { self.status.text = t ?: @"Loading comments…"; }
}

- (void)toggleStar { self.star.on = [RRSaved toggle:self.post]; }

#pragma mark header

- (UILabel *)labelWithText:(NSString *)t font:(UIFont *)f color:(UIColor *)col frame:(CGRect)fr {
    UILabel *l = [[UILabel alloc] initWithFrame:fr];
    l.backgroundColor = [UIColor clearColor]; l.numberOfLines = 0; l.text = t; l.font = f; l.textColor = col;
    return l;
}

- (CGFloat)mediaHeight {
    switch (self.post.media) {
        case RRMediaImage: case RRMediaGif: case RRMediaVideo: case RRMediaGallery: case RRMediaLink: {
            UIImage *im = self.fullImage ?: [RRMedia cachedImage:self.post.thumb maxPixel:640];
            if (self.post.media == RRMediaLink) return self.post.thumb.length ? 120 : 0;
            if (im && im.size.width > 0) return MIN(420, MAX(150, PAPER_W * im.size.height / im.size.width)) + 8;
            return 220;
        }
        default: return 0;
    }
}

- (void)buildHeader {
    RRPost *p = self.post;
    UIView *h = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 10)];
    h.backgroundColor = [UIColor clearColor];
    CGFloat y = 12;
    UIFont *tf = [UIFont fontWithName:@"HelveticaNeue-Bold" size:18];
    CGFloat th = RRTextHeight(p.title, tf, PAPER_W - 8, 200);
    [h addSubview:[self labelWithText:p.title font:tf color:RRInk() frame:CGRectMake(SIDE + 4, y, PAPER_W - 8, th)]];
    y += th + 6;
    NSMutableArray *bits = [NSMutableArray array];
    if (p.author.length) [bits addObject:[@"u/" stringByAppendingString:p.author]];
    [bits addObject:RRTimeAgo(p.created)];
    if (p.domain.length) [bits addObject:p.domain];
    [h addSubview:[self labelWithText:[bits componentsJoinedByString:@"  ·  "] font:[UIFont fontWithName:@"HelveticaNeue" size:12] color:RRSoftInk() frame:CGRectMake(SIDE + 4, y, PAPER_W - 8, 16)]];
    y += 24;

    CGFloat mh = [self mediaHeight];
    if (mh > 0) {
        if (!self.media) {
            self.media = [[RRMediaView alloc] init];
            [self.media addTarget:self action:@selector(mediaTapped) forControlEvents:UIControlEventTouchUpInside];
            self.media.image = [RRMedia cachedImage:p.thumb maxPixel:640];
        }
        self.media.kind = p.media;
        self.media.frame = CGRectMake(SIDE - 4, y, PAPER_W + 8, mh);
        if (p.media == RRMediaGallery) self.media.caption = @"Gallery — only the cover picture is available";
        else if (p.media == RRMediaLink) self.media.caption = p.domain;
        if (self.mediaNote.length) self.media.caption = self.mediaNote;
        [h addSubview:self.media];
        y += mh + 6;
    }
    if (p.text.length) {
        UIFont *bf = [UIFont fontWithName:@"HelveticaNeue" size:15];
        CGFloat bh = RRTextHeight(p.text, bf, PAPER_W - 8, 6000);
        [h addSubview:[self labelWithText:p.text font:bf color:RRInk() frame:CGRectMake(SIDE + 4, y, PAPER_W - 8, bh)]];
        y += bh + 10;
    }
    UILabel *cl = [self labelWithText:@"COMMENTS" font:[UIFont fontWithName:@"HelveticaNeue-Bold" size:12] color:RRSoftInk() frame:CGRectMake(SIDE + 4, y, PAPER_W, 16)];
    [h addSubview:cl];
    y += 22;
    h.frame = CGRectMake(0, 0, 320, y);
    self.header = h;
    self.table.tableHeaderView = h;
}

#pragma mark media

- (void)loadMedia {
    RRPost *p = self.post;
    if (p.media == RRMediaImage) {
        [RRMedia image:p.link maxPixel:1280 done:^(UIImage *img, NSString *err) {
            if (!img) { self.mediaNote = @"Couldn't load the picture"; [self buildHeader]; return; }
            self.fullImage = img; self.media.image = img; [self buildHeader];
        }];
    } else if (p.media == RRMediaGif) {
        [RRMedia animated:p.link maxPixel:360 done:^(UIImage *img, NSString *err) {
            if (!img) { self.mediaNote = @"Couldn't load the gif"; [self buildHeader]; return; }
            self.fullImage = img;
            [self buildHeader];
            UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectInset(self.media.bounds, 4, 4)];
            iv.contentMode = UIViewContentModeScaleAspectFit; iv.image = img; iv.userInteractionEnabled = NO;
            iv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [self.media addSubview:iv];
            [iv startAnimating];
        }];
    } else if (p.thumb.length) {
        [RRMedia image:p.thumb maxPixel:640 done:^(UIImage *img, NSString *err) {
            if (!img) return;
            self.media.image = img;
            if (!self.fullImage) { self.fullImage = img; [self buildHeader]; }
        }];
    }
}

- (void)mediaTapped {
    RRPost *p = self.post;
    switch (p.media) {
        case RRMediaImage:
            [self presentViewer:[[RRViewer alloc] initWithURL:p.link animated:NO placeholder:self.fullImage]];
            break;
        case RRMediaGif:
            [self presentViewer:[[RRViewer alloc] initWithURL:p.link animated:YES placeholder:nil]];
            break;
        case RRMediaVideo:
            [self playVideo];
            break;
        case RRMediaLink: {
            NSURL *u = [NSURL URLWithString:p.link];
            if (u) [[RRRootController shared] push:[[RRWebController alloc] initWithURL:u title:p.domain]];
            break;
        }
        default: break;
    }
}

- (void)presentViewer:(RRViewer *)v { [[RRRootController shared] presentViewController:v animated:YES completion:nil]; }

- (void)playVideo {
    if (self.videoJob) {   /* tap again while preparing: cancel */
        [self.videoJob cancel]; self.videoJob = nil; self.media.progress = -1; self.mediaNote = nil; self.media.caption = nil;
        return;
    }
    self.media.progress = 0; self.media.caption = @"Downloading video — tap to cancel";
    self.videoJob = [RRVideo prepare:self.post.mediaURL progress:^(float f, NSString *stage) {
        self.media.progress = f; self.media.caption = [stage stringByAppendingString:@" — tap to cancel"];
    } done:^(NSString *path, NSString *err) {
        self.videoJob = nil;
        self.media.progress = -1;
        if (err) { self.mediaNote = [@"Couldn't play: " stringByAppendingString:err]; self.media.caption = self.mediaNote; return; }
        self.mediaNote = nil; self.media.caption = nil;
        MPMoviePlayerViewController *mp = [[MPMoviePlayerViewController alloc] initWithContentURL:[NSURL fileURLWithPath:path]];
        [[RRRootController shared] presentMoviePlayerViewControllerAnimated:mp];
    }];
}

#pragma mark table

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.comments.count; }

- (CGFloat)tableView:(UITableView *)t heightForRowAtIndexPath:(NSIndexPath *)ip {
    RRComment *c = [self.comments objectAtIndex:ip.row];
    if (c.heightWidth != 320) { c.height = [RRCommentView heightFor:c width:320]; c.heightWidth = 320; }
    return c.height;
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    RRCommentCell *cell = [t dequeueReusableCellWithIdentifier:@"c"];
    if (!cell) cell = [[RRCommentCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"c"];
    cell.card.comment = [self.comments objectAtIndex:ip.row];
    [cell.card setNeedsDisplay];
    return cell;
}

- (UIView *)tableView:(UITableView *)t viewForFooterInSection:(NSInteger)s { return self.status; }
- (CGFloat)tableView:(UITableView *)t heightForFooterInSection:(NSInteger)s { return self.status.text.length ? 80 : 20; }

@end
