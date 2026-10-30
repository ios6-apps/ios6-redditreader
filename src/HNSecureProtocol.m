#import "HNSecureProtocol.h"
#include "HNTLS.h"

static NSString *const kHandled = @"HNSecureProtocolHandled";

@interface HNSecureProtocol ()
@property (nonatomic, strong) NSThread *clientThread;
@property (nonatomic, assign) HNConn *conn;
@property (atomic, assign) BOOL cancelled;
@end

/* ---- tiny HTTP/1.1 reader on top of the TLS connection ---- */

@interface HNReader : NSObject {
    HNConn *_c;
    NSMutableData *_buf;
    BOOL _eof;
}
- (id)initWithConn:(HNConn *)c;
- (NSData *)readUntilHeaderEnd;          // returns the header block (without the blank line); leftover stays buffered
- (NSData *)readUpTo:(NSUInteger)n;      // up to n bytes, nil at end of stream
- (NSData *)readLine;                    // a line without CRLF, nil at end of stream
@end

@implementation HNReader
- (id)initWithConn:(HNConn *)c { if ((self = [super init])) { _c = c; _buf = [NSMutableData data]; } return self; }
- (BOOL)fill {
    if (_eof) return NO;
    unsigned char tmp[8192];
    int n = hn_tls_read(_c, tmp, sizeof tmp);
    if (n < 0) NSLog(@"HNTLS: read error -0x%04x", -n);
    if (n <= 0) { _eof = YES; return NO; }
    [_buf appendBytes:tmp length:(NSUInteger)n];
    return YES;
}
- (NSData *)readUntilHeaderEnd {
    static const char sep[4] = { '\r', '\n', '\r', '\n' };
    for (;;) {
        NSRange r = [_buf rangeOfData:[NSData dataWithBytes:sep length:4] options:0 range:NSMakeRange(0, _buf.length)];
        if (r.location != NSNotFound) {
            NSData *h = [_buf subdataWithRange:NSMakeRange(0, r.location)];
            [_buf replaceBytesInRange:NSMakeRange(0, r.location + 4) withBytes:NULL length:0];
            return h;
        }
        if (_buf.length > 64 * 1024 || ![self fill]) return nil;
    }
}
- (NSData *)readUpTo:(NSUInteger)n {
    if (!_buf.length && ![self fill]) return nil;
    NSUInteger k = MIN(n, _buf.length);
    NSData *d = [_buf subdataWithRange:NSMakeRange(0, k)];
    [_buf replaceBytesInRange:NSMakeRange(0, k) withBytes:NULL length:0];
    return d;
}
- (NSData *)readLine {
    static const char crlf[2] = { '\r', '\n' };
    for (;;) {
        NSRange r = [_buf rangeOfData:[NSData dataWithBytes:crlf length:2] options:0 range:NSMakeRange(0, _buf.length)];
        if (r.location != NSNotFound) {
            NSData *l = [_buf subdataWithRange:NSMakeRange(0, r.location)];
            [_buf replaceBytesInRange:NSMakeRange(0, r.location + 2) withBytes:NULL length:0];
            return l;
        }
        if (_buf.length > 16 * 1024 || ![self fill]) return nil;
    }
}
@end

@implementation HNSecureProtocol

+ (void)install {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"cacert" ofType:@"pem"];
    NSData *pem = path ? [NSData dataWithContentsOfFile:path] : nil;
    if (pem.length) {
        int n = hn_tls_set_roots((const char *)pem.bytes, pem.length);
        NSLog(@"HNTLS: loaded %d root certificates", n);
        if (n > 0) [NSURLProtocol registerClass:self];
    } else NSLog(@"HNTLS: cacert.pem missing, using the system TLS");
}

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *s = [[[request URL] scheme] lowercaseString];
    return [s isEqualToString:@"https"] && [request URL].host.length && ![NSURLProtocol propertyForKey:kHandled inRequest:request];
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }

- (void)startLoading {
    self.clientThread = [NSThread currentThread];
    NSURLRequest *rq = self.request;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{ [self run:rq]; });
}
- (void)stopLoading {
    self.cancelled = YES;
    HNConn *c = self.conn;
    if (c) hn_tls_cancel(c);
}

/* the client wants its callbacks on the thread that started the load */
- (void)onClient:(void (^)(void))block {
    if (self.cancelled) return;
    [self performSelector:@selector(runBlock:) onThread:self.clientThread withObject:[block copy] waitUntilDone:NO];
}
- (void)runBlock:(void (^)(void))block { if (!self.cancelled) block(); }

- (void)failWith:(NSString *)why code:(NSInteger)code {
    NSLog(@"HNTLS: %@ failed: %@", self.request.URL.host, why);
    NSError *e = [NSError errorWithDomain:NSURLErrorDomain code:code userInfo:
                  [NSDictionary dictionaryWithObjectsAndKeys:why, NSLocalizedDescriptionKey, self.request.URL, NSURLErrorFailingURLErrorKey, nil]];
    [self onClient:^{ [self.client URLProtocol:self didFailWithError:e]; }];
}

static NSString *trim(NSString *s) { return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]; }

- (NSData *)requestBytes:(NSURLRequest *)rq {
    NSURL *url = rq.URL;
    NSString *abs = [url absoluteString];
    NSRange sch = [abs rangeOfString:@"://"];
    NSString *rest = [abs substringFromIndex:sch.location + 3];
    NSRange slash = [rest rangeOfString:@"/"];
    NSString *path = slash.location == NSNotFound ? @"/" : [rest substringFromIndex:slash.location];
    NSRange q = [path rangeOfString:@"?"], h = [path rangeOfString:@"#"];
    if (h.location != NSNotFound && (q.location == NSNotFound || h.location < q.location)) path = [path substringToIndex:h.location];
    else if (h.location != NSNotFound) path = [path substringToIndex:h.location];
    if ([path hasPrefix:@"?"]) path = [@"/" stringByAppendingString:path];

    NSData *body = rq.HTTPBody;
    if (!body && rq.HTTPBodyStream) {
        NSMutableData *all = [NSMutableData data];
        NSInputStream *in = rq.HTTPBodyStream; [in open];
        uint8_t tmp[4096]; NSInteger n;
        while ((n = [in read:tmp maxLength:sizeof tmp]) > 0) [all appendBytes:tmp length:(NSUInteger)n];
        [in close];
        body = all;
    }
    NSString *method = rq.HTTPMethod.length ? rq.HTTPMethod : @"GET";
    NSMutableString *head = [NSMutableString stringWithFormat:@"%@ %@ HTTP/1.1\r\n", method, path];
    NSNumber *port = url.port;
    [head appendFormat:@"Host: %@\r\n", (port && [port intValue] != 443) ? [NSString stringWithFormat:@"%@:%@", url.host, port] : url.host];

    NSMutableDictionary *hs = [NSMutableDictionary dictionary];
    for (NSString *k in [rq allHTTPHeaderFields]) [hs setObject:[[rq allHTTPHeaderFields] objectForKey:k] forKey:[k lowercaseString]];
    for (NSString *skip in [NSArray arrayWithObjects:@"host", @"connection", @"accept-encoding", @"content-length", @"cookie", @"keep-alive", nil]) [hs removeObjectForKey:skip];
    for (NSString *k in hs) [head appendFormat:@"%@: %@\r\n", k, [hs objectForKey:k]];
    if (![hs objectForKey:@"user-agent"]) [head appendString:@"User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 6_1_3 like Mac OS X) AppleWebKit/536.26 (KHTML, like Gecko) Version/6.0 Mobile/10B329 Safari/8536.25\r\n"];
    if (![hs objectForKey:@"accept"]) [head appendString:@"Accept: */*\r\n"];
    [head appendString:@"Accept-Encoding: identity\r\nConnection: close\r\n"];
    if (rq.HTTPShouldHandleCookies) {
        NSArray *cs = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL:url];
        if (cs.count) [head appendFormat:@"Cookie: %@\r\n", [[NSHTTPCookie requestHeaderFieldsWithCookies:cs] objectForKey:@"Cookie"]];
    }
    if (body.length || [method isEqualToString:@"POST"] || [method isEqualToString:@"PUT"]) [head appendFormat:@"Content-Length: %lu\r\n", (unsigned long)body.length];
    [head appendString:@"\r\n"];
    NSMutableData *out = [[head dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    if (body.length) [out appendData:body];
    return out;
}

- (void)run:(NSURLRequest *)rq {
    @autoreleasepool {
        NSURL *url = rq.URL;
        int port = url.port ? [url.port intValue] : 443;
        char err[200] = "";
        HNConn *c = hn_tls_open([url.host UTF8String], port, (int)MAX(rq.timeoutInterval, 15), err, sizeof err);
        if (!c) {
            NSString *why = [NSString stringWithUTF8String:err];
            [self failWith:why code:[why hasPrefix:@"cannot"] ? NSURLErrorCannotConnectToHost : NSURLErrorSecureConnectionFailed];
            return;
        }
        self.conn = c;
        if (self.cancelled) { self.conn = NULL; hn_tls_close(c); return; }

        NSData *req = [self requestBytes:rq];
        if (hn_tls_write(c, req.bytes, req.length) != 0) { [self failWith:@"could not send the request" code:NSURLErrorNetworkConnectionLost]; goto done; }

        {
            HNReader *rd = [[HNReader alloc] initWithConn:c];
            NSInteger status = 0; NSString *version = @"HTTP/1.1"; NSMutableDictionary *fields = nil;
            for (;;) {   /* skip 1xx responses */
                NSData *hd = [rd readUntilHeaderEnd];
                if (!hd) { [self failWith:@"the server closed the connection" code:NSURLErrorNetworkConnectionLost]; goto done; }
                NSString *text = [[NSString alloc] initWithData:hd encoding:NSUTF8StringEncoding] ?: [[NSString alloc] initWithData:hd encoding:NSISOLatin1StringEncoding];
                NSArray *lines = [text componentsSeparatedByString:@"\r\n"];
                NSArray *st = [[lines objectAtIndex:0] componentsSeparatedByString:@" "];
                if (st.count < 2) { [self failWith:@"bad response" code:NSURLErrorBadServerResponse]; goto done; }
                version = [st objectAtIndex:0]; status = [[st objectAtIndex:1] integerValue];
                fields = [NSMutableDictionary dictionary];
                for (NSUInteger i = 1; i < lines.count; i++) {
                    NSString *ln = [lines objectAtIndex:i];
                    NSRange col = [ln rangeOfString:@":"];
                    if (col.location == NSNotFound) continue;
                    NSString *k = trim([ln substringToIndex:col.location]), *v = trim([ln substringFromIndex:col.location + 1]);
                    NSString *old = nil;
                    for (NSString *ek in fields) if ([ek caseInsensitiveCompare:k] == NSOrderedSame) { old = ek; break; }
                    if (old) [fields setObject:[NSString stringWithFormat:@"%@, %@", [fields objectForKey:old], v] forKey:old];
                    else [fields setObject:v forKey:k];
                }
                if (status >= 200 || status == 101) break;
            }

            NSString *(^field)(NSString *) = ^NSString *(NSString *name) {
                for (NSString *k in fields) if ([k caseInsensitiveCompare:name] == NSOrderedSame) return [fields objectForKey:k];
                return nil;
            };

            if (rq.HTTPShouldHandleCookies && field(@"Set-Cookie")) {
                NSArray *cs = [NSHTTPCookie cookiesWithResponseHeaderFields:[NSDictionary dictionaryWithObject:field(@"Set-Cookie") forKey:@"Set-Cookie"] forURL:url];
                [[NSHTTPCookieStorage sharedHTTPCookieStorage] setCookies:cs forURL:url mainDocumentURL:rq.mainDocumentURL];
            }

            NSString *loc = field(@"Location");
            if (loc.length && (status == 301 || status == 302 || status == 303 || status == 307 || status == 308)) {
                NSURL *dest = [NSURL URLWithString:loc relativeToURL:url];
                NSMutableURLRequest *next = [rq mutableCopy];
                next.URL = [dest absoluteURL];
                if (status != 307 && status != 308 && ![rq.HTTPMethod isEqualToString:@"HEAD"]) { next.HTTPMethod = @"GET"; next.HTTPBody = nil; next.HTTPBodyStream = nil; }
                NSHTTPURLResponse *resp = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:status HTTPVersion:version headerFields:fields];
                [self onClient:^{ [self.client URLProtocol:self wasRedirectedToRequest:next redirectResponse:resp]; }];
                goto done;
            }

            NSHTTPURLResponse *resp = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:status HTTPVersion:version headerFields:fields];
            [self onClient:^{ [self.client URLProtocol:self didReceiveResponse:resp cacheStoragePolicy:NSURLCacheStorageNotAllowed]; }];

            BOOL noBody = [rq.HTTPMethod isEqualToString:@"HEAD"] || status == 204 || status == 304;
            NSString *te = [field(@"Transfer-Encoding") lowercaseString];
            NSString *cl = field(@"Content-Length");
            void (^deliver)(NSData *) = ^(NSData *d) { if (d.length) [self onClient:^{ [self.client URLProtocol:self didLoadData:d]; }]; };
            BOOL ok = YES;
            if (noBody) {
            } else if (te.length && [te rangeOfString:@"chunked"].location != NSNotFound) {
                for (;;) {
                    NSData *ln = [rd readLine];
                    if (!ln) { ok = NO; break; }
                    NSString *sz = [[NSString alloc] initWithData:ln encoding:NSASCIIStringEncoding];
                    NSRange semi = [sz rangeOfString:@";"];
                    if (semi.location != NSNotFound) sz = [sz substringToIndex:semi.location];
                    unsigned long long n = strtoull([trim(sz) UTF8String], NULL, 16);
                    if (n == 0) break;
                    while (n > 0) {
                        NSData *d = [rd readUpTo:(NSUInteger)MIN(n, 32768ULL)];
                        if (!d) { ok = NO; break; }
                        n -= d.length; deliver(d);
                    }
                    if (!ok) break;
                    [rd readLine];   /* the CRLF after the chunk */
                }
            } else if (cl.length) {
                unsigned long long left = strtoull([cl UTF8String], NULL, 10);
                while (left > 0) {
                    NSData *d = [rd readUpTo:(NSUInteger)MIN(left, 32768ULL)];
                    if (!d) { ok = NO; NSLog(@"HNTLS: eof with %llu of %@ still missing", left, cl); break; }
                    left -= d.length; deliver(d);
                }
            } else {
                NSData *d;
                while ((d = [rd readUpTo:32768])) deliver(d);
            }
            if (self.cancelled) goto done;
            if (!ok) NSLog(@"HNTLS: %@ status=%ld te=%@ cl=%@ delivered-mismatch", url.host, (long)status, te, cl);
            if (ok) [self onClient:^{ [self.client URLProtocolDidFinishLoading:self]; }];
            else [self failWith:@"the connection dropped while loading" code:NSURLErrorNetworkConnectionLost];
        }
    done:
        self.conn = NULL;
        hn_tls_close(c);
    }
}
@end
