#import "Transcript.h"

@interface DPChatDocument : NSView
@end

@implementation DPChatDocument
- (BOOL)isFlipped { return YES; }
@end

@implementation DPChatScroll
- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.drawsBackground = self.contentView.drawsBackground = NO;
    self.hasVerticalScroller = self.autohidesScrollers = YES;
    self.scrollerStyle = NSScrollerStyleOverlay;
    self.horizontalScrollElasticity = NSScrollElasticityNone;
    self.automaticallyAdjustsContentInsets = NO;
    self.documentView = [DPChatDocument new];
    self.pinned = YES;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(scrolled) name:NSScrollViewDidLiveScrollNotification object:self];
    [center addObserver:self selector:@selector(scrolled) name:NSScrollViewDidEndLiveScrollNotification object:self];
    return self;
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (CGFloat)end { return NSHeight(self.documentView.frame) + self.contentInsets.bottom - NSHeight(self.contentView.bounds); }

- (void)scrolled { self.pinned = NSMinY(self.contentView.bounds) >= self.end - 40; }

- (void)follow {
    if (!self.pinned) return;
    NSClipView *clip = self.contentView;
    NSRect end = [clip constrainBoundsRect:NSMakeRect(0, self.end, NSWidth(clip.bounds), NSHeight(clip.bounds))];
    if (NSMinY(end) == NSMinY(clip.bounds)) return;
    [clip scrollToPoint:end.origin];
    [self reflectScrolledClipView:clip];
}
@end
