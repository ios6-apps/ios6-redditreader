#import "RRPrompt.h"
#import "RRStyle.h"

@interface RRPromptButton : UIControl
@property (nonatomic, copy) NSString *title;
@property (nonatomic) BOOL primary;
@end

@implementation RRPromptButton
- (id)initWithFrame:(CGRect)f { if ((self = [super initWithFrame:f])) self.backgroundColor = [UIColor clearColor]; return self; }
- (void)setHighlighted:(BOOL)h { [super setHighlighted:h]; [self setNeedsDisplay]; }
- (void)drawRect:(CGRect)r {
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGRect b = CGRectInset(self.bounds, 0.5, 0.5);
    BOOL on = self.highlighted;
    UIColor *top = self.primary ? (on ? RRRGB(190, 80, 10) : RRRGB(250, 150, 70)) : (on ? RRRGB(54, 42, 34) : RRRGB(130, 112, 96));
    UIColor *bot = self.primary ? (on ? RRRGB(150, 56, 0) : RRRGB(212, 86, 8)) : (on ? RRRGB(34, 26, 20) : RRRGB(64, 50, 40));
    RRGlossRoundRect(c, b, 7, top, bot, RRRGB(20, 12, 8));
    RRDrawText(self.title, CGRectMake(4, (b.size.height - 20) / 2, b.size.width - 8, 22), [UIFont fontWithName:@"HelveticaNeue-Bold" size:16], [UIColor whiteColor], [UIColor colorWithWhite:0 alpha:0.6], -1, NSTextAlignmentCenter);
}
@end

@interface RRPrompt () <UITextFieldDelegate>
@property (nonatomic, copy) RRPromptHandler handler;
@property (nonatomic, strong) NSMutableArray *inputs;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, copy) NSString *title, *message;
@end

@implementation RRPrompt

+ (void)showTitle:(NSString *)title message:(NSString *)message fields:(NSArray *)fields buttons:(NSArray *)buttons handler:(RRPromptHandler)handler {
    UIWindow *w = [[UIApplication sharedApplication] keyWindow] ?: [[[UIApplication sharedApplication] windows] lastObject];
    if (!w) return;
    RRPrompt *p = [[RRPrompt alloc] initWithFrame:w.bounds];
    p.title = title; p.message = message; p.handler = handler;
    [p build:fields buttons:buttons];
    [w addSubview:p];
    p.alpha = 0;
    [UIView animateWithDuration:0.18 animations:^{ p.alpha = 1; }];
    UITextField *first = [p.inputs firstObject];
    [first becomeFirstResponder];
}

- (void)build:(NSArray *)fields buttons:(NSArray *)buttons {
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    CGFloat pw = 280, y = 16;
    CGSize ms = [self.message sizeWithFont:[UIFont fontWithName:@"HelveticaNeue" size:14] constrainedToSize:CGSizeMake(pw - 36, 200) lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat ph = 16 + 24 + 8 + (self.message.length ? ms.height + 12 : 0) + fields.count * 42 + 46 + 16;
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake((self.bounds.size.width - pw) / 2, 54, pw, ph)];
    panel.backgroundColor = [UIColor clearColor];
    self.panel = panel;
    [self addSubview:panel];

    UIImageView *bg = [[UIImageView alloc] initWithFrame:panel.bounds];
    UIGraphicsBeginImageContextWithOptions(panel.bounds.size, NO, 0);
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGContextSaveGState(c);
    CGContextSetShadowWithColor(c, CGSizeMake(0, 4), 12, [UIColor colorWithWhite:0 alpha:0.8].CGColor);
    RRGlossRoundRect(c, CGRectInset(panel.bounds, 4, 4), 10, RRRGB(96, 74, 58), RRRGB(36, 26, 20), RRRGB(196, 168, 136));
    CGContextRestoreGState(c);
    bg.image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    [panel addSubview:bg];

    UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(18, y, pw - 36, 24)];
    t.text = self.title; t.textAlignment = NSTextAlignmentCenter; t.backgroundColor = [UIColor clearColor];
    t.font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:18]; t.textColor = RRRGB(240,244,250); t.shadowColor = [UIColor blackColor]; t.shadowOffset = CGSizeMake(0, -1);
    [panel addSubview:t];
    y += 24 + 8;
    if (self.message.length) {
        UILabel *m = [[UILabel alloc] initWithFrame:CGRectMake(18, y, pw - 36, ms.height)];
        m.text = self.message; m.numberOfLines = 0; m.textAlignment = NSTextAlignmentCenter; m.backgroundColor = [UIColor clearColor];
        m.font = [UIFont fontWithName:@"HelveticaNeue" size:14]; m.textColor = RRRGB(160,150,140);
        [panel addSubview:m];
        y += ms.height + 12;
    }
    self.inputs = [NSMutableArray array];
    for (NSDictionary *d in fields) {
        UITextField *f = [[UITextField alloc] initWithFrame:CGRectMake(18, y, pw - 36, 32)];
        f.borderStyle = UITextBorderStyleRoundedRect;
        f.text = [d objectForKey:@"text"]; f.placeholder = [d objectForKey:@"placeholder"];
        f.secureTextEntry = [[d objectForKey:@"secure"] boolValue];
        f.keyboardType = [[d objectForKey:@"url"] boolValue] ? UIKeyboardTypeURL : UIKeyboardTypeDefault;
        f.autocorrectionType = UITextAutocorrectionTypeNo;
        f.autocapitalizationType = UITextAutocapitalizationTypeNone;
        f.clearButtonMode = UITextFieldViewModeWhileEditing;
        f.returnKeyType = (f == nil) ? UIReturnKeyDefault : UIReturnKeyGo;
        f.font = [UIFont systemFontOfSize:16];
        f.delegate = self;
        [panel addSubview:f];
        [self.inputs addObject:f];
        y += 42;
    }
    CGFloat bw = (pw - 36 - 10 * (buttons.count - 1)) / buttons.count;
    for (NSUInteger i = 0; i < buttons.count; i++) {
        RRPromptButton *b = [[RRPromptButton alloc] initWithFrame:CGRectMake(18 + i * (bw + 10), y + 4, bw, 38)];
        b.title = [buttons objectAtIndex:i]; b.primary = i > 0; b.tag = i;
        [b addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
        [panel addSubview:b];
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)f {
    NSUInteger i = [self.inputs indexOfObject:f];
    if (i + 1 < self.inputs.count) { [[self.inputs objectAtIndex:i + 1] becomeFirstResponder]; return NO; }
    [self finish:1];
    return NO;
}

- (void)tapped:(UIControl *)b { [self finish:b.tag]; }

- (void)finish:(NSInteger)idx {
    NSMutableArray *texts = [NSMutableArray array];
    for (UITextField *f in self.inputs) [texts addObject:f.text ?: @""];
    RRPromptHandler h = self.handler;
    self.handler = nil;
    [self endEditing:YES];
    [UIView animateWithDuration:0.15 animations:^{ self.alpha = 0; } completion:^(BOOL done) { [self removeFromSuperview]; }];
    if (h) h(idx, texts);
}

@end
