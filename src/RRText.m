#import <Foundation/Foundation.h>

/* The text helpers of RRStyle.h that need nothing but Foundation (kept apart so the tests can build them on the Mac). */

NSString *RRTimeAgo(NSTimeInterval t) {
    long d = (long)([[NSDate date] timeIntervalSince1970] - t);
    if (d < 60) return @"just now";
    if (d < 3600) return [NSString stringWithFormat:@"%ldm", d / 60];
    if (d < 86400) return [NSString stringWithFormat:@"%ldh", d / 3600];
    if (d < 86400 * 60) return [NSString stringWithFormat:@"%ldd", d / 86400];
    return [NSString stringWithFormat:@"%ldmo", d / (86400 * 30)];
}

static void appendCode(NSMutableString *s, unsigned code) {
    NSString *e = [[NSString alloc] initWithBytes:&code length:4 encoding:NSUTF32LittleEndianStringEncoding];
    if (e) [s appendString:e];
}

NSString *RRPlainText(NSString *html) {
    if (![html isKindOfClass:[NSString class]] || !html.length) return @"";
    NSMutableString *s = [NSMutableString stringWithCapacity:html.length];
    NSUInteger i = 0, n = html.length;
    while (i < n) {
        unichar ch = [html characterAtIndex:i];
        if (ch == '<') {
            NSRange r = [html rangeOfString:@">" options:0 range:NSMakeRange(i, n - i)];
            if (r.location == NSNotFound) break;
            NSString *tag = [[html substringWithRange:NSMakeRange(i + 1, r.location - i - 1)] lowercaseString];
            if ([tag isEqualToString:@"p"] || [tag hasPrefix:@"p "]) [s appendString:@"\n\n"];
            else if ([tag isEqualToString:@"li"]) [s appendString:@"\n• "];
            else if ([tag hasPrefix:@"br"] || [tag hasPrefix:@"pre"] || [tag isEqualToString:@"/pre"]) [s appendString:@"\n"];
            i = r.location + 1;
            continue;
        }
        if (ch == '&') {
            NSRange r = [html rangeOfString:@";" options:0 range:NSMakeRange(i, MIN((NSUInteger)10, n - i))];
            if (r.location != NSNotFound) {
                NSString *name = [html substringWithRange:NSMakeRange(i + 1, r.location - i - 1)];
                if ([name isEqualToString:@"amp"]) [s appendString:@"&"];
                else if ([name isEqualToString:@"lt"]) [s appendString:@"<"];
                else if ([name isEqualToString:@"gt"]) [s appendString:@">"];
                else if ([name isEqualToString:@"quot"]) [s appendString:@"\""];
                else if ([name isEqualToString:@"apos"]) [s appendString:@"'"];
                else if ([name isEqualToString:@"nbsp"]) [s appendString:@" "];
                else if ([name hasPrefix:@"#x"] || [name hasPrefix:@"#X"]) {
                    unsigned v = 0; [[NSScanner scannerWithString:[name substringFromIndex:2]] scanHexInt:&v]; appendCode(s, v);
                } else if ([name hasPrefix:@"#"]) appendCode(s, (unsigned)[[name substringFromIndex:1] intValue]);
                else { [s appendString:[html substringWithRange:NSMakeRange(i, r.location - i + 1)]]; }
                i = r.location + 1;
                continue;
            }
        }
        [s appendFormat:@"%C", ch];
        i++;
    }
    NSString *t = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([t rangeOfString:@"\n\n\n"].location != NSNotFound) t = [t stringByReplacingOccurrencesOfString:@"\n\n\n" withString:@"\n\n"];
    return t;
}
