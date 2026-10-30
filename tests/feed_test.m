/* Tests for the parts of the app that need nothing but Foundation: the Atom feed parsing and post classification in RRFeed.m,
   and the text helpers in RRText.m. RRFeed.m is included rather than linked so the file-local helpers can be reached. */
#import "../src/RRFeed.m"

static int fails;
#define CHECK(cond, ...) do { if (!(cond)) { fails++; NSLog(@"FAIL line %d: %@", __LINE__, [NSString stringWithFormat:__VA_ARGS__]); } } while (0)
#define EQ(a, b) do { id _a = (a), _b = (b); if (!(_a == _b || [_a isEqual:_b])) { fails++; NSLog(@"FAIL line %d: %@ != %@", __LINE__, _a, _b); } } while (0)

/* an invented feed in the shape Reddit's .rss endpoints use */
static NSString *const kFeed =
@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
 "<feed xmlns=\"http://www.w3.org/2005/Atom\" xmlns:media=\"http://search.yahoo.com/mrss/\">\n"
 "<category term=\"pics\" label=\"r/pics\"/><updated>2026-10-29T12:30:00+00:00</updated><id>/r/pics/hot.rss</id><title>pics</title>\n"
 "<entry><author><name>/u/alice</name><uri>https://www.reddit.com/user/alice</uri></author><category term=\"pics\" label=\"r/pics\"/>\n"
 " <content type=\"html\">&lt;table&gt;&lt;tr&gt;&lt;td&gt;&lt;span&gt;&lt;a href=\"https://i.redd.it/cat.jpg?a=1&amp;amp;b=2\"&gt;[link]&lt;/a&gt;&lt;/span&gt; &lt;span&gt;&lt;a href=\"https://www.reddit.com/r/pics/comments/abc123/a_cat/\"&gt;[comments]&lt;/a&gt;&lt;/span&gt;&lt;/td&gt;&lt;/tr&gt;&lt;/table&gt;</content>\n"
 " <id>t3_abc123</id><media:thumbnail url=\"https://example.com/t.jpg?width=640&amp;crop=smart\"/>\n"
 " <link href=\"https://www.reddit.com/r/pics/comments/abc123/a_cat/\"/><updated>2026-10-29T12:00:00+00:00</updated><title>A cat &amp; a box</title></entry>\n"
 "<entry><author><name>/u/bob</name></author><category term=\"askreddit\" label=\"r/askreddit\"/>\n"
 " <content type=\"html\">&lt;!-- SC_OFF --&gt;&lt;div class=\"md\"&gt;&lt;p&gt;Fish &amp;amp; chips?&lt;/p&gt;&lt;ul&gt;&lt;li&gt;one&lt;/li&gt;&lt;li&gt;two &amp;#128512;&lt;/li&gt;&lt;/ul&gt;&lt;/div&gt;&lt;!-- SC_ON --&gt; &lt;span&gt;&lt;a href=\"https://www.reddit.com/r/askreddit/comments/def456/fish/\"&gt;[link]&lt;/a&gt;&lt;/span&gt; &lt;span&gt;&lt;a href=\"https://www.reddit.com/r/askreddit/comments/def456/fish/\"&gt;[comments]&lt;/a&gt;&lt;/span&gt;</content>\n"
 " <id>t3_def456</id><link href=\"https://www.reddit.com/r/askreddit/comments/def456/fish/\"/><updated>2026-10-29T11:00:00+00:00</updated><title>Fish?</title></entry>\n"
 "<entry><author><name>/u/carol</name></author><category term=\"videos\" label=\"r/videos\"/>\n"
 " <content type=\"html\">&lt;span&gt;&lt;a href=\"https://v.redd.it/xyz789\"&gt;[link]&lt;/a&gt;&lt;/span&gt; &lt;span&gt;&lt;a href=\"https://www.reddit.com/r/videos/comments/ghi789/clip/\"&gt;[comments]&lt;/a&gt;&lt;/span&gt;</content>\n"
 " <id>t3_ghi789</id><link href=\"https://www.reddit.com/r/videos/comments/ghi789/clip/\"/><updated>2026-10-29T10:00:00+00:00</updated><title>Clip</title></entry>\n"
 "<entry><author><name>/u/dave</name></author><id>t1_zzz</id><content type=\"html\">&lt;p&gt;a comment&lt;/p&gt;</content><updated>2026-10-29T10:00:00+00:00</updated><title>a comment</title></entry>\n"
 "</feed>";

static RRPost *classified(NSString *link) {
    RRPost *p = [[RRPost alloc] init];
    p.link = link; p.sub = @"test";
    [p classify];
    return p;
}

int main(void) {
    @autoreleasepool {
        /* feed parsing */
        NSString *title = nil;
        NSArray *entries = [RRFeed parse:[kFeed dataUsingEncoding:NSUTF8StringEncoding] title:&title];
        EQ(title, @"pics");
        CHECK(entries.count == 4, @"4 entries, got %lu", (unsigned long)entries.count);
        NSMutableArray *posts = [NSMutableArray array];
        for (NSDictionary *e in entries) { RRPost *p = RRPostFromEntry(e); if (p) [posts addObject:p]; }
        CHECK(posts.count == 3, @"comments (t1_) are not posts, got %lu posts", (unsigned long)posts.count);

        RRPost *cat = [posts objectAtIndex:0];
        EQ(cat.pid, @"abc123"); EQ(cat.title, @"A cat & a box"); EQ(cat.author, @"alice"); EQ(cat.sub, @"pics");
        EQ(cat.link, @"https://i.redd.it/cat.jpg?a=1&b=2");
        EQ(cat.permalink, @"https://www.reddit.com/r/pics/comments/abc123/a_cat/");
        EQ(cat.thumb, @"https://example.com/t.jpg?width=640&crop=smart");
        CHECK(cat.created == 1793275200, @"created %f", cat.created);
        CHECK(cat.media == RRMediaImage, @"image post, got %ld", (long)cat.media);
        EQ(cat.domain, @"i.redd.it");
        CHECK(cat.text == nil, @"no self text on a link post");

        RRPost *fish = [posts objectAtIndex:1];
        EQ(fish.text, @"Fish & chips?\n• one\n• two \U0001F600");
        CHECK(fish.media == RRMediaNone, @"a self post has no media");
        EQ(fish.domain, @"self.askreddit");

        RRPost *clip = [posts objectAtIndex:2];
        CHECK(clip.media == RRMediaVideo, @"v.redd.it is video");
        EQ(clip.mediaURL, @"https://v.redd.it/xyz789");

        /* a saved post survives the round trip through NSUserDefaults-style dictionaries */
        RRPost *again = [RRPost postFromDict:[cat dictionary]];
        EQ(again.pid, cat.pid); EQ(again.link, cat.link); EQ(again.title, cat.title); CHECK(again.media == RRMediaImage, @"classified again");

        /* link classification */
        CHECK(classified(@"https://i.imgur.com/a.gif").media == RRMediaGif, @"gif");
        CHECK(classified(@"https://i.imgur.com/a.gifv").media == RRMediaVideo, @"gifv is video");
        EQ(classified(@"https://i.imgur.com/a.gifv").mediaURL, @"https://i.imgur.com/a.mp4");
        CHECK(classified(@"https://example.com/clip.MP4").media == RRMediaVideo, @"extension case");
        CHECK(classified(@"https://example.com/p.jpeg").media == RRMediaImage, @"jpeg");
        CHECK(classified(@"https://www.reddit.com/gallery/abc").media == RRMediaGallery, @"gallery");
        RRPost *im = classified(@"https://imgur.com/AbCd123");
        CHECK(im.media == RRMediaImage, @"single imgur page is an image"); EQ(im.link, @"https://i.imgur.com/AbCd123.jpg");
        CHECK(classified(@"https://imgur.com/a/AbCd123").media == RRMediaLink, @"an imgur album stays a link");
        RRPost *news = classified(@"https://www.example.com/story");
        CHECK(news.media == RRMediaLink, @"article is a link"); EQ(news.domain, @"example.com");

        /* subreddit names */
        EQ([RRFeed cleanSubName:@"pics"], @"pics");
        EQ([RRFeed cleanSubName:@" r/Pics/ "], @"pics");
        EQ([RRFeed cleanSubName:@"/r/aww"], @"aww");
        EQ([RRFeed cleanSubName:@"https://www.reddit.com/r/Space/hot"], @"space");
        EQ([RRFeed cleanSubName:@"reddit.com/r/space"], @"space");
        EQ([RRFeed cleanSubName:@"news+worldnews"], @"news+worldnews");
        CHECK([RRFeed cleanSubName:@""] == nil, @"empty");
        CHECK([RRFeed cleanSubName:@"two words"] == nil, @"space");
        CHECK([RRFeed cleanSubName:@"bad!name"] == nil, @"punctuation");
        CHECK([RRFeed cleanSubName:[@"" stringByPaddingToLength:41 withString:@"a" startingAtIndex:0]] == nil, @"too long");

        /* html to text */
        EQ(RRPlainText(@"<p>one</p><p>two</p>"), @"one\n\ntwo");
        EQ(RRPlainText(@"a<br>b<br/>c"), @"a\nb\nc");
        EQ(RRPlainText(@"&lt;tag&gt; &quot;q&quot; &#39;s&#39; &#x41;&#66; &nbsp;x &unknown; 5 &gt 3"), @"<tag> \"q\" 's' AB  x &unknown; 5 &gt 3");
        EQ(RRPlainText(@"<p>a</p>\n\n\n\n<p>b</p>"), @"a\n\nb");
        EQ(RRPlainText(@"x < y"), @"x");   /* an unterminated tag swallows the rest rather than crashing */
        EQ(RRPlainText(nil), @"");
        EQ(RRPlainText((id)@42), @"");

        /* relative times */
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        EQ(RRTimeAgo(now - 5), @"just now"); EQ(RRTimeAgo(now - 5 * 60 - 1), @"5m"); EQ(RRTimeAgo(now - 3 * 3600 - 1), @"3h");
        EQ(RRTimeAgo(now - 2 * 86400 - 1), @"2d"); EQ(RRTimeAgo(now - 90 * 86400), @"3mo");
    }
    NSLog(fails ? @"feed_test: %d FAILED" : @"feed_test: all ok", fails);
    return fails != 0;
}
