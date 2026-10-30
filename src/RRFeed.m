#import "RRFeed.h"
#import "RRStyle.h"
#include <CommonCrypto/CommonDigest.h>

NSString *const RRFeedStatusNotification = @"RRFeedStatus";

static NSString *const kUA = @"ios6-reddit-reader/1.0 (personal use, atom feeds)";

#pragma mark - post

@implementation RRPost

- (NSString *)mediaURL {
    NSString *l = self.link;
    if (!l.length) return nil;
    NSURL *u = [NSURL URLWithString:l];
    NSString *host = [u.host lowercaseString], *ext = [[u.path pathExtension] lowercaseString];
    if ([host isEqualToString:@"v.redd.it"]) return [NSString stringWithFormat:@"https://v.redd.it%@", [u.path hasSuffix:@"/"] ? [u.path substringToIndex:u.path.length - 1] : u.path];
    if ([host isEqualToString:@"i.imgur.com"] && [ext isEqualToString:@"gifv"]) {   /* not stringByDeletingPathExtension: it would turn "https://" into "https:/" */
        NSRange r = [l rangeOfString:@".gifv" options:NSBackwardsSearch | NSCaseInsensitiveSearch];
        return r.location == NSNotFound ? l : [l stringByReplacingCharactersInRange:r withString:@".mp4"];
    }
    return l;
}

+ (RRPost *)postFromDict:(NSDictionary *)d {
    RRPost *p = [[RRPost alloc] init];
    p.pid = [d objectForKey:@"pid"]; p.title = [d objectForKey:@"title"]; p.author = [d objectForKey:@"author"]; p.sub = [d objectForKey:@"sub"];
    p.link = [d objectForKey:@"link"]; p.permalink = [d objectForKey:@"permalink"]; p.thumb = [d objectForKey:@"thumb"]; p.text = [d objectForKey:@"text"];
    p.created = [[d objectForKey:@"created"] doubleValue];
    [p classify];
    return p;
}

- (NSDictionary *)dictionary {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (self.pid) [d setObject:self.pid forKey:@"pid"];
    if (self.title) [d setObject:self.title forKey:@"title"];
    if (self.author) [d setObject:self.author forKey:@"author"];
    if (self.sub) [d setObject:self.sub forKey:@"sub"];
    if (self.link) [d setObject:self.link forKey:@"link"];
    if (self.permalink) [d setObject:self.permalink forKey:@"permalink"];
    if (self.thumb) [d setObject:self.thumb forKey:@"thumb"];
    if (self.text) [d setObject:self.text forKey:@"text"];
    [d setObject:[NSNumber numberWithDouble:self.created] forKey:@"created"];
    return d;
}

/* works out what the post's link is, and the domain to show */
- (void)classify {
    self.media = RRMediaNone;
    NSString *l = self.link;
    if (!l.length || [l rangeOfString:@"/comments/"].location != NSNotFound) { self.domain = self.sub ? [@"self." stringByAppendingString:self.sub] : nil; return; }
    NSURL *u = [NSURL URLWithString:l];
    NSString *host = [[u host] lowercaseString], *ext = [[u.path pathExtension] lowercaseString];
    self.domain = [host hasPrefix:@"www."] ? [host substringFromIndex:4] : host;
    if ([host isEqualToString:@"v.redd.it"]) self.media = RRMediaVideo;
    else if ([host hasSuffix:@"reddit.com"] && [u.path hasPrefix:@"/gallery/"]) self.media = RRMediaGallery;
    else if ([ext isEqualToString:@"gif"]) self.media = RRMediaGif;
    else if ([ext isEqualToString:@"gifv"] || [ext isEqualToString:@"mp4"] || [ext isEqualToString:@"mov"] || [ext isEqualToString:@"m4v"]) self.media = RRMediaVideo;
    else if ([ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"] || [ext isEqualToString:@"png"]) self.media = RRMediaImage;
    else if ([host isEqualToString:@"imgur.com"] && u.path.length > 2 && [u.path rangeOfString:@"/" options:0 range:NSMakeRange(1, u.path.length - 1)].location == NSNotFound) {
        self.link = [NSString stringWithFormat:@"https://i.imgur.com%@.jpg", u.path];   /* a single imgur page */
        self.media = RRMediaImage;
    } else self.media = RRMediaLink;
}
@end

@implementation RRComment
@end

#pragma mark - Atom parsing

@interface RRAtomParser : NSObject <NSXMLParserDelegate>
@property (nonatomic, strong) NSMutableArray *entries;
@property (nonatomic, strong) NSMutableDictionary *cur;
@property (nonatomic, strong) NSMutableString *chars;
@property (nonatomic, copy) NSString *feedTitle;
@property (nonatomic) BOOL inAuthor;
@end

@implementation RRAtomParser
- (id)init { if ((self = [super init])) { self.entries = [NSMutableArray array]; } return self; }
- (void)parser:(NSXMLParser *)p didStartElement:(NSString *)el namespaceURI:(NSString *)ns qualifiedName:(NSString *)q attributes:(NSDictionary *)a {
    self.chars = [NSMutableString string];
    if ([el isEqualToString:@"entry"]) { self.cur = [NSMutableDictionary dictionary]; return; }
    if (!self.cur) return;
    if ([el isEqualToString:@"author"]) self.inAuthor = YES;
    else if ([el isEqualToString:@"link"] && [a objectForKey:@"href"]) [self.cur setObject:[a objectForKey:@"href"] forKey:@"link"];
    else if ([el isEqualToString:@"category"] && [a objectForKey:@"term"]) [self.cur setObject:[a objectForKey:@"term"] forKey:@"sub"];
    else if (([el isEqualToString:@"media:thumbnail"] || [q isEqualToString:@"media:thumbnail"]) && [a objectForKey:@"url"]) [self.cur setObject:[a objectForKey:@"url"] forKey:@"thumb"];
}
- (void)parser:(NSXMLParser *)p foundCharacters:(NSString *)s { [self.chars appendString:s]; }
- (void)parser:(NSXMLParser *)p foundCDATA:(NSData *)d { [self.chars appendString:[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: @""]; }
- (void)parser:(NSXMLParser *)p didEndElement:(NSString *)el namespaceURI:(NSString *)ns qualifiedName:(NSString *)q {
    if ([el isEqualToString:@"entry"]) { if (self.cur) [self.entries addObject:self.cur]; self.cur = nil; return; }
    if (!self.cur) { if ([el isEqualToString:@"title"] && !self.feedTitle) self.feedTitle = [self.chars copy]; return; }
    if ([el isEqualToString:@"author"]) self.inAuthor = NO;
    else if ([el isEqualToString:@"name"] && self.inAuthor) [self.cur setObject:[self.chars stringByReplacingOccurrencesOfString:@"/u/" withString:@""] forKey:@"author"];
    else if ([el isEqualToString:@"title"]) [self.cur setObject:[self.chars copy] forKey:@"title"];
    else if ([el isEqualToString:@"id"]) [self.cur setObject:[self.chars copy] forKey:@"id"];
    else if ([el isEqualToString:@"content"]) [self.cur setObject:[self.chars copy] forKey:@"content"];
    else if ([el isEqualToString:@"updated"] || [el isEqualToString:@"published"]) [self.cur setObject:[self.chars copy] forKey:@"updated"];
}
@end

static NSTimeInterval RRParseDate(NSString *s) {
    if (s.length < 19) return 0;
    static NSDateFormatter *f;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        f = [[NSDateFormatter alloc] init];
        f.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        f.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        f.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss";
    });
    return [[f dateFromString:[s substringToIndex:19]] timeIntervalSince1970];   /* reddit always writes +00:00 */
}

/* the first piece of html that is the post's own text (reddit wraps markdown in <div class="md">) */
static NSString *RRMarkdownDiv(NSString *html) {
    NSRange a = [html rangeOfString:@"<div class=\"md\">"];
    if (a.location == NSNotFound) return nil;
    NSRange b = [html rangeOfString:@"</div><!-- SC_ON -->" options:0 range:NSMakeRange(a.location, html.length - a.location)];
    if (b.location == NSNotFound) b = [html rangeOfString:@"</div>" options:NSBackwardsSearch];
    if (b.location == NSNotFound || b.location < a.location + 16) return nil;
    return [html substringWithRange:NSMakeRange(a.location + 16, b.location - a.location - 16)];
}

static NSString *RRFirstHref(NSString *html, NSString *label) {
    NSString *needle = [NSString stringWithFormat:@">[%@]</a>", label];
    NSRange r = [html rangeOfString:needle];
    if (r.location == NSNotFound) return nil;
    NSRange h = [html rangeOfString:@"href=\"" options:NSBackwardsSearch range:NSMakeRange(0, r.location)];
    if (h.location == NSNotFound) return nil;
    NSUInteger s = h.location + 6;
    NSRange e = [html rangeOfString:@"\"" options:0 range:NSMakeRange(s, r.location - s)];
    return e.location == NSNotFound ? nil : [html substringWithRange:NSMakeRange(s, e.location - s)];
}

static NSString *RRUnescapeAttr(NSString *s) {
    return [[s stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"] stringByReplacingOccurrencesOfString:@"&#39;" withString:@"'"];
}

static RRPost *RRPostFromEntry(NSDictionary *e) {
    NSString *id_ = [e objectForKey:@"id"];
    if (![id_ hasPrefix:@"t3_"]) return nil;
    RRPost *p = [[RRPost alloc] init];
    p.pid = [id_ substringFromIndex:3];
    p.title = [e objectForKey:@"title"];
    p.author = [e objectForKey:@"author"];
    p.sub = [e objectForKey:@"sub"];
    p.created = RRParseDate([e objectForKey:@"updated"]);
    NSString *content = [e objectForKey:@"content"] ?: @"";
    p.permalink = RRFirstHref(content, @"comments") ?: [e objectForKey:@"link"];
    p.link = RRFirstHref(content, @"link");
    if (p.link) p.link = RRUnescapeAttr(p.link);
    NSString *th = [e objectForKey:@"thumb"];
    p.thumb = th ? RRUnescapeAttr(th) : nil;
    NSString *md = RRMarkdownDiv(content);
    p.text = md.length ? [RRPlainText(md) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : nil;
    if ([p.link hasPrefix:@"/"]) p.link = [@"https://www.reddit.com" stringByAppendingString:p.link];
    [p classify];
    return p;
}

#pragma mark - queue and cache

@interface RRRequest : NSObject
@property (nonatomic, copy) NSString *url;
@property (nonatomic) BOOL force;
@property (nonatomic) NSTimeInterval ttl;
@property (nonatomic, copy) void (^done)(NSData *data, NSString *error);
@property (nonatomic) int tries;
@end
@implementation RRRequest
@end

static NSMutableArray *gQueue;
static BOOL gBusy;
static NSTimeInterval gNextOK;

static NSString *RRCacheFile(NSString *url) {
    unsigned char h[CC_SHA1_DIGEST_LENGTH];
    NSData *d = [url dataUsingEncoding:NSUTF8StringEncoding];
    CC_SHA1(d.bytes, (CC_LONG)d.length, h);
    NSMutableString *s = [NSMutableString string];
    for (int i = 0; i < 10; i++) [s appendFormat:@"%02x", h[i]];
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).lastObject stringByAppendingPathComponent:@"feeds"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    return [dir stringByAppendingPathComponent:s];
}

static void RRStatus(NSString *text) {
    [[NSNotificationCenter defaultCenter] postNotificationName:RRFeedStatusNotification object:nil userInfo:text ? [NSDictionary dictionaryWithObject:text forKey:@"text"] : nil];
}

@implementation RRFeed

+ (void)enqueue:(RRRequest *)r {
    if (!gQueue) gQueue = [NSMutableArray array];
    NSString *file = RRCacheFile(r.url);
    NSDictionary *at = [[NSFileManager defaultManager] attributesOfItemAtPath:file error:NULL];
    NSData *cached = at ? [NSData dataWithContentsOfFile:file] : nil;
    if (cached && !r.force && -[[at fileModificationDate] timeIntervalSinceNow] < r.ttl) { dispatch_async(dispatch_get_main_queue(), ^{ r.done(cached, nil); }); return; }
    [gQueue addObject:r];
    [self pump];
}

+ (void)pump {
    if (gBusy || !gQueue.count) return;
    NSTimeInterval wait = gNextOK - [NSDate timeIntervalSinceReferenceDate];
    if (wait > 0.5) {
        RRStatus([NSString stringWithFormat:@"Reddit allows one request every 40 seconds without an account.\nNext one in %d s…", (int)ceil(wait)]);
        [self performSelector:@selector(pump) withObject:nil afterDelay:MIN(wait, 1.0)];
        return;
    }
    gBusy = YES;
    RRStatus(nil);
    RRRequest *r = [gQueue objectAtIndex:0];
    NSMutableURLRequest *rq = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:r.url] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30];
    [rq setValue:kUA forHTTPHeaderField:@"User-Agent"];
    [NSURLConnection sendAsynchronousRequest:rq queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *resp, NSData *data, NSError *err) {
        gBusy = NO;
        NSHTTPURLResponse *h = (NSHTTPURLResponse *)resp;
        NSInteger code = err ? 0 : h.statusCode;
        NSString *reset = [[h allHeaderFields] objectForKey:@"x-ratelimit-reset"] ?: [[h allHeaderFields] objectForKey:@"X-Ratelimit-Reset"];
        NSString *remain = [[h allHeaderFields] objectForKey:@"x-ratelimit-remaining"] ?: [[h allHeaderFields] objectForKey:@"X-Ratelimit-Remaining"];
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if ((reset && (code == 429 || [remain doubleValue] < 1)) || code == 429) gNextOK = now + (reset ? [reset doubleValue] : 30) + 1;
        if (code == 429 && ++r.tries < 4) { [self pump]; return; }          /* try again once Reddit's window is over */
        [gQueue removeObjectAtIndex:0];
        if (err || code != 200) {
            NSString *msg = err ? err.localizedDescription : (code == 429 ? @"Reddit is limiting requests, try again in a minute" : [NSString stringWithFormat:@"Reddit answered HTTP %ld", (long)code]);
            NSData *stale = [NSData dataWithContentsOfFile:RRCacheFile(r.url)];
            if (stale.length && code != 404 && code != 403) r.done(stale, nil); else r.done(nil, code == 404 || code == 403 ? [NSString stringWithFormat:@"Reddit says this is private, banned or doesn't exist (HTTP %ld)", (long)code] : msg);
        } else {
            [data writeToFile:RRCacheFile(r.url) atomically:YES];
            r.done(data, nil);
        }
        [self pump];
    }];
}

+ (NSArray *)parse:(NSData *)data title:(NSString **)title {
    RRAtomParser *ap = [[RRAtomParser alloc] init];
    NSXMLParser *xp = [[NSXMLParser alloc] initWithData:data];
    xp.delegate = ap;
    [xp parse];
    if (title) *title = ap.feedTitle;
    return ap.entries;
}

+ (void)loadURL:(NSString *)url force:(BOOL)force ttl:(NSTimeInterval)ttl after:(NSString *)after done:(RRPostsBlock)done {
    RRRequest *r = [[RRRequest alloc] init];
    r.url = url; r.force = force; r.ttl = ttl;
    r.done = ^(NSData *data, NSString *err) {
        if (err) { done(nil, nil, err); return; }
        NSMutableArray *posts = [NSMutableArray array];
        NSString *last = nil;
        for (NSDictionary *e in [self parse:data title:NULL]) {
            RRPost *p = RRPostFromEntry(e);
            if (p) { [posts addObject:p]; last = [@"t3_" stringByAppendingString:p.pid]; }
        }
        done(posts, posts.count >= 20 ? last : nil, posts.count ? nil : @"Nothing found here");
    };
    [self enqueue:r];
}

+ (void)loadPath:(NSString *)path period:(NSString *)period after:(NSString *)after force:(BOOL)force done:(RRPostsBlock)done {
    NSMutableString *u = [NSMutableString stringWithFormat:@"https://www.reddit.com/%@/.rss?limit=50", path];
    if ([path hasSuffix:@"/top"] || [path hasSuffix:@"/controversial"]) [u appendFormat:@"&t=%@", period.length ? period : @"day"];
    if (after.length) [u appendFormat:@"&after=%@", after];
    [self loadURL:u force:force ttl:after.length ? 3600 : 600 after:after done:done];
}

+ (void)searchQuery:(NSString *)q sort:(NSString *)sort done:(RRPostsBlock)done {
    NSString *enc = [q stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    enc = [enc stringByReplacingOccurrencesOfString:@"&" withString:@"%26"];
    enc = [enc stringByReplacingOccurrencesOfString:@"+" withString:@"%2B"];
    [self loadURL:[NSString stringWithFormat:@"https://www.reddit.com/search.rss?q=%@&sort=%@&limit=50", enc, sort ?: @"relevance"] force:NO ttl:600 after:nil done:done];
}

+ (void)loadCommentsFor:(RRPost *)post done:(RRCommentsBlock)done {
    NSString *base = post.permalink;
    if (!base.length) { done(post, nil, @"No comments link"); return; }
    NSRange q = [base rangeOfString:@"?"];
    if (q.location != NSNotFound) base = [base substringToIndex:q.location];
    if (![base hasSuffix:@"/"]) base = [base stringByAppendingString:@"/"];
    RRRequest *r = [[RRRequest alloc] init];
    r.url = [base stringByAppendingString:@".rss?limit=100&sort=top"];
    r.ttl = 900;
    r.done = ^(NSData *data, NSString *err) {
        if (err) { done(post, nil, err); return; }
        NSMutableArray *cs = [NSMutableArray array];
        for (NSDictionary *e in [self parse:data title:NULL]) {
            NSString *id_ = [e objectForKey:@"id"];
            NSString *content = [e objectForKey:@"content"] ?: @"";
            if ([id_ hasPrefix:@"t3_"]) {
                if (!post.text.length) { NSString *md = RRMarkdownDiv(content); if (md.length) post.text = [RRPlainText(md) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]; }
                continue;
            }
            RRComment *c = [[RRComment alloc] init];
            c.author = [e objectForKey:@"author"] ?: @"[deleted]";
            NSString *md = RRMarkdownDiv(content);
            c.text = [(md ?: content) length] ? [RRPlainText(md ?: content) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : @"";
            c.created = RRParseDate([e objectForKey:@"updated"]);
            [cs addObject:c];
        }
        done(post, cs, nil);
    };
    [self enqueue:r];
}

+ (NSString *)cleanSubName:(NSString *)s {
    s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    for (NSString *pre in [NSArray arrayWithObjects:@"https://www.reddit.com/", @"https://reddit.com/", @"reddit.com/", @"/r/", @"r/", nil])
        if ([s.lowercaseString hasPrefix:pre]) { s = [s substringFromIndex:pre.length]; if ([pre hasPrefix:@"http"] || [pre hasPrefix:@"reddit"]) { if ([s.lowercaseString hasPrefix:@"r/"]) s = [s substringFromIndex:2]; } break; }
    while ([s hasSuffix:@"/"]) s = [s substringToIndex:s.length - 1];
    NSRange sl = [s rangeOfString:@"/"];
    if (sl.location != NSNotFound) s = [s substringToIndex:sl.location];
    if (!s.length || s.length > 40) return nil;
    NSCharacterSet *bad = [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_+"] invertedSet];
    if ([s rangeOfCharacterFromSet:bad].location != NSNotFound) return nil;
    return s.lowercaseString;
}

@end

#pragma mark - saved posts and subreddits

@implementation RRSaved
+ (NSArray *)posts {
    NSMutableArray *a = [NSMutableArray array];
    for (NSDictionary *d in [[NSUserDefaults standardUserDefaults] arrayForKey:@"rr.saved"]) [a addObject:[RRPost postFromDict:d]];
    return a;
}
+ (BOOL)contains:(NSString *)pid {
    for (NSDictionary *d in [[NSUserDefaults standardUserDefaults] arrayForKey:@"rr.saved"]) if ([[d objectForKey:@"pid"] isEqualToString:pid]) return YES;
    return NO;
}
+ (BOOL)toggle:(RRPost *)p {
    if ([self contains:p.pid]) { [self remove:p.pid]; return NO; }
    NSMutableArray *a = [NSMutableArray arrayWithObject:[p dictionary]];
    [a addObjectsFromArray:[[NSUserDefaults standardUserDefaults] arrayForKey:@"rr.saved"]];
    [[NSUserDefaults standardUserDefaults] setObject:a forKey:@"rr.saved"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    return YES;
}
+ (void)remove:(NSString *)pid {
    NSMutableArray *a = [NSMutableArray array];
    for (NSDictionary *d in [[NSUserDefaults standardUserDefaults] arrayForKey:@"rr.saved"]) if (![[d objectForKey:@"pid"] isEqualToString:pid]) [a addObject:d];
    [[NSUserDefaults standardUserDefaults] setObject:a forKey:@"rr.saved"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
@end

@implementation RRSubs
+ (NSArray *)names {
    NSArray *a = [[NSUserDefaults standardUserDefaults] arrayForKey:@"rr.subs"];
    return a ?: [NSArray arrayWithObjects:@"pics", @"videos", @"gifs", @"aww", @"interestingasfuck", @"oddlysatisfying", @"worldnews", @"technology", @"todayilearned", @"funny", nil];
}
+ (void)add:(NSString *)name {
    NSMutableArray *a = [[self names] mutableCopy];
    if ([a containsObject:name]) return;
    [a addObject:name];
    [[NSUserDefaults standardUserDefaults] setObject:a forKey:@"rr.subs"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
+ (void)remove:(NSString *)name {
    NSMutableArray *a = [[self names] mutableCopy];
    [a removeObject:name];
    [[NSUserDefaults standardUserDefaults] setObject:a forKey:@"rr.subs"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
@end
