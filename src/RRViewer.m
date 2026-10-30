#import "RRViewer.h"
#import "RRMedia.h"
#import "RRStyle.h"
#import "RRChrome.h"
#import <AssetsLibrary/AssetsLibrary.h>

@interface RRViewer () <UIScrollViewDelegate>
@property (nonatomic, copy) NSString *url;
@property (nonatomic) BOOL gif;
@property (nonatomic, strong) UIImage *placeholder, *image;
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIImageView *iv;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *note;
@property (nonatomic, strong) UIButton *save, *close;
@end

@implementation RRViewer

- (id)initWithURL:(NSString *)url animated:(BOOL)gif placeholder:(UIImage *)placeholder {
    if ((self = [super init])) { self.url = url; self.gif = gif; self.placeholder = placeholder; }
    return self;
}

- (UIButton *)pill:(NSString *)title frame:(CGRect)f action:(SEL)a {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = f;
    b.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    b.layer.cornerRadius = 15; b.layer.borderWidth = 1; b.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
    b.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [b setTitle:title forState:UIControlStateNormal];
    [b addTarget:self action:a forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    CGRect b = self.view.bounds;
    self.scroll = [[UIScrollView alloc] initWithFrame:b];
    self.scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scroll.delegate = self;
    self.scroll.maximumZoomScale = 4;
    self.scroll.showsHorizontalScrollIndicator = NO; self.scroll.showsVerticalScrollIndicator = NO;
    [self.view addSubview:self.scroll];
    self.iv = [[UIImageView alloc] init];
    [self.scroll addSubview:self.iv];
    UITapGestureRecognizer *dbl = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTap:)];
    dbl.numberOfTapsRequired = 2;
    [self.scroll addGestureRecognizer:dbl];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    self.spinner.center = CGPointMake(b.size.width / 2, b.size.height / 2);
    self.spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [self.view addSubview:self.spinner];
    self.note = [[UILabel alloc] initWithFrame:CGRectMake(20, b.size.height / 2 + 30, b.size.width - 40, 60)];
    self.note.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    self.note.numberOfLines = 3; self.note.textAlignment = NSTextAlignmentCenter; self.note.backgroundColor = [UIColor clearColor];
    self.note.textColor = [UIColor colorWithWhite:0.8 alpha:1]; self.note.font = [UIFont systemFontOfSize:14];
    [self.view addSubview:self.note];

    self.close = [self pill:@"Done" frame:CGRectMake(10, 26, 64, 30) action:@selector(done)];
    self.save = [self pill:@"Save" frame:CGRectMake(b.size.width - 74, 26, 64, 30) action:@selector(saveToPhotos)];
    self.save.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    self.save.hidden = YES;
    [self.view addSubview:self.close]; [self.view addSubview:self.save];

    if (self.placeholder) [self setImage:self.placeholder];
    [self.spinner startAnimating];
    RRImageBlock cb = ^(UIImage *img, NSString *err) {
        [self.spinner stopAnimating];
        if (img) { [self setImage:img]; self.save.hidden = NO; }
        else if (!self.iv.image) self.note.text = [NSString stringWithFormat:@"Couldn't load the picture.\n%@", err ?: @""];
    };
    if (self.gif) [RRMedia animated:self.url maxPixel:480 done:cb]; else [RRMedia image:self.url maxPixel:2048 done:cb];
}

- (void)setImage:(UIImage *)img {
    _image = img;
    self.iv.image = img;
    [self fit];
}

- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; if (self.iv.image && self.scroll.zoomScale <= self.scroll.minimumZoomScale + 0.01) [self fit]; }

- (void)fit {
    UIImage *img = self.iv.image;
    if (!img) return;
    CGSize bs = self.scroll.bounds.size;
    self.scroll.zoomScale = 1;
    self.iv.frame = CGRectMake(0, 0, img.size.width, img.size.height);
    self.scroll.contentSize = img.size;
    CGFloat k = MIN(bs.width / img.size.width, bs.height / img.size.height);
    self.scroll.minimumZoomScale = k;
    self.scroll.maximumZoomScale = MAX(k * 4, 2);
    self.scroll.zoomScale = k;
    [self center];
}

- (void)center {
    CGSize bs = self.scroll.bounds.size;
    CGRect f = self.iv.frame;
    f.origin.x = f.size.width < bs.width ? (bs.width - f.size.width) / 2 : 0;
    f.origin.y = f.size.height < bs.height ? (bs.height - f.size.height) / 2 : 0;
    self.iv.frame = f;
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)s { return self.iv; }
- (void)scrollViewDidZoom:(UIScrollView *)s { [self center]; }

- (void)doubleTap:(UITapGestureRecognizer *)g {
    if (self.scroll.zoomScale > self.scroll.minimumZoomScale + 0.01) [self.scroll setZoomScale:self.scroll.minimumZoomScale animated:YES];
    else {
        CGPoint p = [g locationInView:self.iv];
        CGFloat z = MIN(self.scroll.maximumZoomScale, self.scroll.minimumZoomScale * 2.5);
        CGSize bs = self.scroll.bounds.size;
        [self.scroll zoomToRect:CGRectMake(p.x - bs.width / z / 2, p.y - bs.height / z / 2, bs.width / z, bs.height / z) animated:YES];
    }
}

- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)saveToPhotos {
    UIImage *img = self.image;
    if (!img) return;
    self.save.enabled = NO;
    /* the animated image would be stored as its first frame; the original file is better */
    NSData *data = nil;
    data = [NSData dataWithContentsOfFile:[RRMedia cachePathForURL:self.url]];
    ALAssetsLibrary *lib = [[ALAssetsLibrary alloc] init];
    void (^finished)(NSURL *, NSError *) = ^(NSURL *u, NSError *e) {
        self.save.enabled = YES;
        [self.save setTitle:e ? @"Failed" : @"Saved" forState:UIControlStateNormal];
        (void)lib;
    };
    if (data && !self.gif) [lib writeImageDataToSavedPhotosAlbum:data metadata:nil completionBlock:finished];
    else [lib writeImageToSavedPhotosAlbum:(self.gif ? [self.image.images firstObject] ?: img : img).CGImage orientation:(ALAssetOrientation)img.imageOrientation completionBlock:finished];
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)shouldAutorotate { return NO; }
- (NSUInteger)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }
@end
