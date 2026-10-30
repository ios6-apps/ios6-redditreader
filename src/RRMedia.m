#import "RRMedia.h"
#import <ImageIO/ImageIO.h>
#import <MobileCoreServices/MobileCoreServices.h>
#include <CommonCrypto/CommonDigest.h>
#include "RRMux.h"

static NSString *RRHash(NSString *s) {
    unsigned char h[CC_SHA1_DIGEST_LENGTH];
    NSData *d = [s dataUsingEncoding:NSUTF8StringEncoding];
    CC_SHA1(d.bytes, (CC_LONG)d.length, h);
    NSMutableString *o = [NSMutableString string];
    for (int i = 0; i < 12; i++) [o appendFormat:@"%02x", h[i]];
    return o;
}

static NSString *RRCacheDir(NSString *name) {
    NSString *dir = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    return dir;
}

#pragma mark - download

@interface RRDownload () <NSURLConnectionDataDelegate>
@property (nonatomic, strong) NSURLConnection *conn;
@property (nonatomic, strong) NSFileHandle *fh;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) void (^progress)(float);
@property (nonatomic, copy) void (^done)(NSString *);
@property (nonatomic) long long expected, got;
@property (nonatomic) NSInteger status;
@property (nonatomic) BOOL finished;
@end

@implementation RRDownload

+ (RRDownload *)fetch:(NSString *)url toFile:(NSString *)path progress:(void (^)(float))progress done:(void (^)(NSString *))done {
    RRDownload *d = [[RRDownload alloc] init];
    d.path = path; d.progress = progress; d.done = done;
    [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
    d.fh = [NSFileHandle fileHandleForWritingAtPath:path];
    NSMutableURLRequest *rq = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30];
    d.conn = [[NSURLConnection alloc] initWithRequest:rq delegate:d startImmediately:NO];
    [d.conn scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    [d.conn start];
    return d;
}

- (void)finish:(NSString *)err {
    if (self.finished) return;
    self.finished = YES;
    [self.fh closeFile]; self.fh = nil;
    if (err) { NSLog(@"RRDownload failed: %@ (%@)", err, self.conn.originalRequest.URL); [[NSFileManager defaultManager] removeItemAtPath:self.path error:NULL]; }
    void (^d)(NSString *) = self.done;
    self.done = nil; self.progress = nil; self.conn = nil;
    if (d) d(err);
}
- (void)cancel { [self.conn cancel]; self.done = nil; [self finish:@"cancelled"]; }
- (void)connection:(NSURLConnection *)c didReceiveResponse:(NSURLResponse *)r {
    self.status = [(NSHTTPURLResponse *)r statusCode];
    self.expected = r.expectedContentLength;
}
- (void)connection:(NSURLConnection *)c didReceiveData:(NSData *)data {
    if (self.status >= 400) return;
    [self.fh writeData:data];
    self.got += data.length;
    if (self.progress && self.expected > 0) self.progress((float)((double)self.got / self.expected));
}
- (void)connectionDidFinishLoading:(NSURLConnection *)c {
    [self finish:self.status >= 400 ? [NSString stringWithFormat:@"HTTP %ld", (long)self.status] : nil];
}
- (void)connection:(NSURLConnection *)c didFailWithError:(NSError *)e { [self finish:e.localizedDescription]; }
@end

#pragma mark - images

static NSCache *gMem;
static NSMutableDictionary *gWaiting;   /* url -> callbacks wanting the file */

@implementation RRMedia

+ (void)initialize { if (self == [RRMedia class]) { gMem = [[NSCache alloc] init]; gMem.totalCostLimit = 40 * 1024 * 1024; gWaiting = [NSMutableDictionary dictionary]; } }

+ (NSString *)keyFor:(NSString *)url px:(int)px { return [NSString stringWithFormat:@"%@|%d", url, px]; }

+ (NSString *)cachePathForURL:(NSString *)url { return [RRCacheDir(@"img") stringByAppendingPathComponent:RRHash(url)]; }

+ (UIImage *)cachedImage:(NSString *)url maxPixel:(int)px { return [gMem objectForKey:[self keyFor:url px:px]]; }

/* the file for a url: from disk, or downloaded once (several callers for the same url share one download) */
+ (void)file:(NSString *)url done:(void (^)(NSString *path, NSString *err))done {
    NSString *path = [RRCacheDir(@"img") stringByAppendingPathComponent:RRHash(url)];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) { done(path, nil); return; }
    NSMutableArray *w = [gWaiting objectForKey:url];
    if (w) { [w addObject:[done copy]]; return; }
    w = [NSMutableArray arrayWithObject:[done copy]];
    [gWaiting setObject:w forKey:url];
    NSString *tmp = [path stringByAppendingString:@".part"];
    [RRDownload fetch:url toFile:tmp progress:nil done:^(NSString *err) {
        if (!err) { [[NSFileManager defaultManager] removeItemAtPath:path error:NULL]; [[NSFileManager defaultManager] moveItemAtPath:tmp toPath:path error:NULL]; }
        NSArray *cbs = [gWaiting objectForKey:url];
        [gWaiting removeObjectForKey:url];
        for (void (^cb)(NSString *, NSString *) in cbs) cb(err ? nil : path, err);
    }];
}

static UIImage *RRDecode(NSString *path, int px, int index) {
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];
    if (!data) return nil;
    CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!src) return nil;
    NSDictionary *o = [NSDictionary dictionaryWithObjectsAndKeys:
                       (id)kCFBooleanTrue, (id)kCGImageSourceCreateThumbnailFromImageAlways,
                       (id)kCFBooleanTrue, (id)kCGImageSourceCreateThumbnailWithTransform,
                       [NSNumber numberWithInt:px], (id)kCGImageSourceThumbnailMaxPixelSize, nil];
    CGImageRef im = CGImageSourceCreateThumbnailAtIndex(src, index, (__bridge CFDictionaryRef)o);
    CFRelease(src);
    if (!im) return nil;
    UIImage *u = [UIImage imageWithCGImage:im];
    CGImageRelease(im);
    return u;
}

+ (void)image:(NSString *)url maxPixel:(int)px done:(RRImageBlock)done {
    if (!url.length) { done(nil, @"no image"); return; }
    NSString *key = [self keyFor:url px:px];
    UIImage *hit = [gMem objectForKey:key];
    if (hit) { done(hit, nil); return; }
    [self file:url done:^(NSString *path, NSString *err) {
        if (err) { done(nil, err); return; }
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            UIImage *u = RRDecode(path, px, 0);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (u) { [gMem setObject:u forKey:key cost:(NSUInteger)(u.size.width * u.scale * u.size.height * u.scale * 4)]; done(u, nil); }
                else { [[NSFileManager defaultManager] removeItemAtPath:path error:NULL]; done(nil, @"not a picture iOS can open"); }
            });
        });
    }];
}

+ (void)animated:(NSString *)url maxPixel:(int)px done:(RRImageBlock)done {
    [self file:url done:^(NSString *path, NSString *err) {
        if (err) { done(nil, err); return; }
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            UIImage *result = nil;
            @autoreleasepool {
                NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];
                CGImageSourceRef src = data ? CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL) : NULL;
                if (src) {
                    size_t n = CGImageSourceGetCount(src);
                    if (n < 2) result = RRDecode(path, px, 0);
                    else {
                        /* keep the decoded frames under about 40 MB: thin out long gifs, keeping the total running time */
                        UIImage *first = RRDecode(path, px, 0);
                        double frameBytes = first.size.width * first.scale * first.size.height * first.scale * 4;
                        size_t keep = (size_t)MAX(8.0, MIN(200.0, 40e6 / MAX(frameBytes, 1)));
                        size_t step = (n + keep - 1) / keep;
                        NSMutableArray *frames = [NSMutableArray array];
                        double total = 0;
                        for (size_t i = 0; i < n; i++) {
                            NSDictionary *p = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(src, i, NULL);
                            NSDictionary *g = [p objectForKey:(id)kCGImagePropertyGIFDictionary];
                            double d = [[g objectForKey:(id)kCGImagePropertyGIFUnclampedDelayTime] doubleValue];
                            if (d < 0.011) d = [[g objectForKey:(id)kCGImagePropertyGIFDelayTime] doubleValue];
                            if (d < 0.011) d = 0.1;
                            total += d;
                            if (i % step == 0) { UIImage *f = i == 0 ? first : RRDecode(path, px, (int)i); if (f) [frames addObject:f]; }
                        }
                        result = frames.count > 1 ? [UIImage animatedImageWithImages:frames duration:total] : first;
                    }
                    CFRelease(src);
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{ done(result, result ? nil : @"not a picture iOS can open"); });
        });
    }];
}

+ (void)sweepCaches {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        for (NSArray *spec in [NSArray arrayWithObjects:[NSArray arrayWithObjects:@"img", [NSNumber numberWithLongLong:80LL << 20], nil],
                                                         [NSArray arrayWithObjects:@"video", [NSNumber numberWithLongLong:200LL << 20], nil], nil]) {
            NSString *dir = RRCacheDir([spec objectAtIndex:0]);
            long long budget = [[spec objectAtIndex:1] longLongValue], total = 0;
            NSMutableArray *files = [NSMutableArray array];
            for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL]) {
                NSString *p = [dir stringByAppendingPathComponent:f];
                NSDictionary *a = [[NSFileManager defaultManager] attributesOfItemAtPath:p error:NULL];
                if ([f hasSuffix:@".part"]) { [[NSFileManager defaultManager] removeItemAtPath:p error:NULL]; continue; }
                total += [[a objectForKey:NSFileSize] longLongValue];
                [files addObject:[NSDictionary dictionaryWithObjectsAndKeys:p, @"p", [a objectForKey:NSFileModificationDate], @"d", [a objectForKey:NSFileSize], @"s", nil]];
            }
            [files sortUsingComparator:^NSComparisonResult(NSDictionary *x, NSDictionary *y) { return [[x objectForKey:@"d"] compare:[y objectForKey:@"d"]]; }];
            for (NSDictionary *f in files) {
                if (total <= budget) break;
                [[NSFileManager defaultManager] removeItemAtPath:[f objectForKey:@"p"] error:NULL];
                total -= [[f objectForKey:@"s"] longLongValue];
            }
        }
    });
}
@end

#pragma mark - video

@interface RRVideo ()
@property (nonatomic, strong) RRDownload *current;
@property (nonatomic) BOOL cancelled;
@property (nonatomic, copy) void (^progress)(float, NSString *);
@property (nonatomic, copy) void (^done)(NSString *, NSString *);
@end

/* picks the entries of a DASH manifest: BaseURL of each Representation with its width / mime type / bandwidth */
@interface RRMPD : NSObject <NSXMLParserDelegate>
@property (nonatomic, strong) NSMutableArray *videos, *audios;
@property (nonatomic, strong) NSMutableDictionary *rep;
@property (nonatomic, strong) NSMutableString *chars;
@end
@implementation RRMPD
- (id)init { if ((self = [super init])) { self.videos = [NSMutableArray array]; self.audios = [NSMutableArray array]; } return self; }
- (void)parser:(NSXMLParser *)p didStartElement:(NSString *)el namespaceURI:(NSString *)ns qualifiedName:(NSString *)q attributes:(NSDictionary *)a {
    self.chars = [NSMutableString string];
    if ([el isEqualToString:@"Representation"]) self.rep = [a mutableCopy];
}
- (void)parser:(NSXMLParser *)p foundCharacters:(NSString *)s { [self.chars appendString:s]; }
- (void)parser:(NSXMLParser *)p didEndElement:(NSString *)el namespaceURI:(NSString *)ns qualifiedName:(NSString *)q {
    if ([el isEqualToString:@"BaseURL"] && self.rep) [self.rep setObject:[self.chars copy] forKey:@"base"];
    if ([el isEqualToString:@"Representation"] && self.rep) {
        NSString *mime = [self.rep objectForKey:@"mimeType"];
        if ([self.rep objectForKey:@"base"]) [([mime hasPrefix:@"audio"] ? self.audios : self.videos) addObject:self.rep];
        self.rep = nil;
    }
}
@end

@implementation RRVideo

+ (RRVideo *)prepare:(NSString *)mediaURL progress:(void (^)(float, NSString *))progress done:(void (^)(NSString *, NSString *))done {
    RRVideo *v = [[RRVideo alloc] init];
    v.progress = progress; v.done = done;
    NSString *final = [[RRCacheDir(@"video") stringByAppendingPathComponent:RRHash(mediaURL)] stringByAppendingString:@".mp4"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:final]) {
        [[NSFileManager defaultManager] setAttributes:[NSDictionary dictionaryWithObject:[NSDate date] forKey:NSFileModificationDate] ofItemAtPath:final error:NULL];
        dispatch_async(dispatch_get_main_queue(), ^{ done(final, nil); });
        return v;
    }
    if ([[mediaURL pathExtension] length]) [v direct:mediaURL to:final];
    else [v dash:mediaURL to:final];
    return v;
}

- (void)cancel { self.cancelled = YES; [self.current cancel]; self.done = nil; self.progress = nil; }

- (void)report:(float)f stage:(NSString *)s { if (self.progress && !self.cancelled) self.progress(f, s); }
- (void)finish:(NSString *)path error:(NSString *)err {
    void (^d)(NSString *, NSString *) = self.done;
    self.done = nil;
    if (d && !self.cancelled) d(path, err);
}

- (void)direct:(NSString *)url to:(NSString *)final {
    NSString *tmp = [final stringByAppendingString:@".part"];
    self.current = [RRDownload fetch:url toFile:tmp progress:^(float f) { [self report:f stage:@"Downloading video"]; } done:^(NSString *err) {
        if (err) { [self finish:nil error:err]; return; }
        [[NSFileManager defaultManager] moveItemAtPath:tmp toPath:final error:NULL];
        [self finish:final error:nil];
    }];
}

- (void)dash:(NSString *)base to:(NSString *)final {
    NSString *tmp = [final stringByAppendingString:@".part"];
    [self report:0 stage:@"Looking up the video"];
    NSMutableURLRequest *rq = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[base stringByAppendingString:@"/DASHPlaylist.mpd"]] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30];
    [NSURLConnection sendAsynchronousRequest:rq queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *r, NSData *data, NSError *e) {
        if (self.cancelled) return;
        if (e || [(NSHTTPURLResponse *)r statusCode] != 200) { [self finish:nil error:e ? e.localizedDescription : @"The video isn't available (it may have been removed)"]; return; }
        RRMPD *m = [[RRMPD alloc] init];
        NSXMLParser *xp = [[NSXMLParser alloc] initWithData:data]; xp.delegate = m; [xp parse];
        if (!m.videos.count) { [self finish:nil error:@"No video stream found"]; return; }
        /* the biggest picture up to 480 wide is plenty for a 4-inch screen and keeps downloads small */
        NSDictionary *best = nil;
        for (NSDictionary *v in m.videos) {
            int w = [[v objectForKey:@"width"] intValue];
            if (w <= 480 && (!best || w > [[best objectForKey:@"width"] intValue])) best = v;
        }
        if (!best) best = [m.videos objectAtIndex:0];
        NSDictionary *aud = nil;
        for (NSDictionary *a in m.audios) if (!aud || [[a objectForKey:@"bandwidth"] intValue] > [[aud objectForKey:@"bandwidth"] intValue]) aud = a;
        NSString *vpath = [tmp stringByAppendingString:@".v"], *apath = [tmp stringByAppendingString:@".a"];
        NSString *vurl = [NSString stringWithFormat:@"%@/%@", base, [best objectForKey:@"base"]];
        NSString *aurl = aud ? [NSString stringWithFormat:@"%@/%@", base, [aud objectForKey:@"base"]] : nil;
        self.current = [RRDownload fetch:vurl toFile:vpath progress:^(float f) { [self report:f * 0.9f stage:@"Downloading video"]; } done:^(NSString *err) {
            if (err) { [self finish:nil error:err]; return; }
            void (^mux)(BOOL) = ^(BOOL haveAudio) {
                [self report:0.95f stage:@"Preparing"];
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    char msg[200];
                    NSString *failure = nil;
                    int rc = rr_mux([vpath fileSystemRepresentation], haveAudio ? [apath fileSystemRepresentation] : NULL, [tmp fileSystemRepresentation], msg, sizeof msg);
                    [[NSFileManager defaultManager] removeItemAtPath:vpath error:NULL];
                    [[NSFileManager defaultManager] removeItemAtPath:apath error:NULL];
                    if (rc) failure = [NSString stringWithFormat:@"Couldn't prepare the video (%s)", msg];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (failure) { [self finish:nil error:failure]; return; }
                        [[NSFileManager defaultManager] moveItemAtPath:tmp toPath:final error:NULL];
                        [self finish:final error:nil];
                    });
                });
            };
            if (!aurl) { mux(NO); return; }
            self.current = [RRDownload fetch:aurl toFile:apath progress:^(float f) { [self report:0.9f + f * 0.05f stage:@"Downloading sound"]; } done:^(NSString *aerr) {
                mux(!aerr);    /* a clip without sound is fine */
            }];
        }];
    }];
}
@end
