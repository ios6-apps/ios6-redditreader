#import "RRSubsController.h"
#import "RRListController.h"
#import "RRChrome.h"
#import "RRStyle.h"
#import "RRFeed.h"
#import "RRPrompt.h"

@interface RRSubsController () <RRScreen>
@property (nonatomic, strong) NSArray *names;
@end

@implementation RRSubsController

- (NSString *)rrTitle { return @"Subreddits"; }

- (UIView *)rrRightView {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(0, 0, 54, 30);
    b.layer.cornerRadius = 15; b.layer.borderWidth = 1; b.layer.borderColor = RRRGB(24, 30, 44).CGColor;
    CAGradientLayer *g = [CAGradientLayer layer];
    g.frame = b.bounds; g.cornerRadius = 15;
    g.colors = [NSArray arrayWithObjects:(id)RRRGB(152, 166, 190).CGColor, (id)RRRGB(76, 90, 118).CGColor, nil];
    [b.layer insertSublayer:g atIndex:0];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [b setTitle:@"Add" forState:UIControlStateNormal];
    [b addTarget:self action:@selector(add) forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = [UIColor colorWithPatternImage:RRLinenImage()];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.names = [RRSubs names];
}

- (void)add {
    [RRPrompt showTitle:@"Add subreddit" message:@"Name or link, for example pics or r/aww"
                 fields:[NSArray arrayWithObject:[NSDictionary dictionaryWithObjectsAndKeys:@"pics", @"placeholder", nil]]
                buttons:[NSArray arrayWithObjects:@"Cancel", @"Add", nil]
                handler:^(NSInteger i, NSArray *texts) {
        if (i == 0) return;
        NSString *n = [RRFeed cleanSubName:[texts objectAtIndex:0]];
        if (!n) { [RRPrompt showTitle:@"That doesn't look like a subreddit name" message:@"Use letters, numbers and underscores." fields:nil buttons:[NSArray arrayWithObject:@"OK"] handler:nil]; return; }
        [RRSubs add:n];
        self.names = [RRSubs names];
        [self.tableView reloadData];
    }];
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.names.count; }
- (CGFloat)tableView:(UITableView *)t heightForRowAtIndexPath:(NSIndexPath *)ip { return 54; }

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [t dequeueReusableCellWithIdentifier:@"s"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"s"];
        cell.backgroundColor = [UIColor clearColor];
        UIView *card = [[UIView alloc] init];
        card.tag = 7;
        card.layer.borderWidth = 0;
        CAGradientLayer *g = [CAGradientLayer layer];
        g.colors = [NSArray arrayWithObjects:(id)RRRGB(255, 255, 255).CGColor, (id)RRRGB(240, 243, 248).CGColor, nil];
        g.name = @"g";
        [card.layer insertSublayer:g atIndex:0];
        cell.backgroundView = nil;
        [cell.contentView addSubview:card];
        UILabel *l = [[UILabel alloc] init];
        l.tag = 8; l.backgroundColor = [UIColor clearColor]; l.font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:17]; l.textColor = RRInk();
        [card addSubview:l];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    CGFloat w = t.bounds.size.width;
    UIView *card = [cell.contentView viewWithTag:7];
    card.frame = CGRectMake(0, 0, w, 53);
    for (CALayer *l in card.layer.sublayers) if ([l.name isEqualToString:@"g"]) l.frame = card.bounds;
    UILabel *l = (UILabel *)[card viewWithTag:8];
    l.frame = CGRectMake(16, 0, w - 60, 53);
    l.text = [@"r/" stringByAppendingString:[self.names objectAtIndex:ip.row]];
    return cell;
}

- (BOOL)tableView:(UITableView *)t canEditRowAtIndexPath:(NSIndexPath *)ip { return YES; }

- (void)tableView:(UITableView *)t commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)ip {
    if (style != UITableViewCellEditingStyleDelete) return;
    [RRSubs remove:[self.names objectAtIndex:ip.row]];
    self.names = [RRSubs names];
    [t deleteRowsAtIndexPaths:[NSArray arrayWithObject:ip] withRowAnimation:UITableViewRowAnimationFade];
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    [[RRRootController shared] push:[[RRListController alloc] initWithSub:[self.names objectAtIndex:ip.row]]];
}

@end

#pragma mark - search

@interface RRSearchController () <RRScreen, UITextFieldDelegate>
@property (nonatomic, strong) UITextField *field;
@end

@implementation RRSearchController

- (NSString *)rrTitle { return @"Search"; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithPatternImage:RRLinenImage()];
    CGFloat w = self.view.bounds.size.width;
    self.field = [[UITextField alloc] initWithFrame:CGRectMake(12, 18, w - 24, 38)];
    self.field.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.field.borderStyle = UITextBorderStyleRoundedRect;
    self.field.placeholder = @"Search all of Reddit";
    self.field.returnKeyType = UIReturnKeySearch;
    self.field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.field.autocorrectionType = UITextAutocorrectionTypeNo;
    self.field.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.field.font = [UIFont systemFontOfSize:17];
    self.field.delegate = self;
    [self.view addSubview:self.field];
    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(24, 70, w - 48, 70)];
    hint.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    hint.backgroundColor = [UIColor clearColor]; hint.numberOfLines = 3; hint.textAlignment = NSTextAlignmentCenter;
    hint.font = [UIFont fontWithName:@"HelveticaNeue-Italic" size:14]; hint.textColor = RRRGB(96, 106, 124);
    hint.text = @"Reddit allows one request every 40 seconds without an account, so searches can take a moment.";
    [self.view addSubview:hint];
}

- (BOOL)textFieldShouldReturn:(UITextField *)f {
    NSString *q = [f.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!q.length) return NO;
    [f resignFirstResponder];
    [[RRRootController shared] push:[[RRListController alloc] initSearch:q]];
    return NO;
}
@end
