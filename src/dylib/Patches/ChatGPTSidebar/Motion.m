#import "Transcript.h"

// One easing for everything, so the chat moves as one piece.
static CAMediaTimingFunction *DPChatEase(void) { return [CAMediaTimingFunction functionWithControlPoints:0.2 :0.8 :0.2 :1]; }

static BOOL DPChatStill(void) { return NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion; }

void DPChatFade(CALayer *layer, CFTimeInterval duration) {
    if (!layer || DPChatStill()) return;
    CATransition *fade = [CATransition animation];
    fade.type = kCATransitionFade;
    fade.duration = duration;
    fade.timingFunction = DPChatEase();
    [layer addAnimation:fade forKey:@"DPChatFade"];
}

void DPChatAppear(CALayer *layer, CFTimeInterval duration, CFTimeInterval delay, CGFloat rise) {
    if (!layer || DPChatStill()) return;
    CFTimeInterval begin = [layer convertTime:CACurrentMediaTime() fromLayer:nil] + delay;
    CABasicAnimation *opacity = [CABasicAnimation animationWithKeyPath:@"opacity"];
    opacity.fromValue = @0;
    opacity.toValue = @1;
    // Layers of flipped views still count y up, so a positive shift starts the view lower.
    CABasicAnimation *move = [CABasicAnimation animationWithKeyPath:@"transform.translation.y"];
    move.fromValue = @(-rise);
    move.toValue = @0;
    CAAnimationGroup *group = [CAAnimationGroup animation];
    group.animations = rise ? @[opacity, move] : @[opacity];
    group.duration = duration;
    group.beginTime = begin;
    group.fillMode = kCAFillModeBackwards;
    group.timingFunction = DPChatEase();
    [layer addAnimation:group forKey:@"DPChatAppear"];
}

// Breathes while ChatGPT is thinking, as Dia's own placeholder does.
void DPChatPulse(CALayer *layer, BOOL on) {
    if (!layer) return;
    if (!on || DPChatStill()) return [layer removeAnimationForKey:@"DPChatPulse"];
    if ([layer animationForKey:@"DPChatPulse"]) return;
    CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
    pulse.fromValue = @1;
    pulse.toValue = @0.4;
    pulse.duration = 0.9;
    pulse.autoreverses = YES;
    pulse.repeatCount = HUGE_VALF;
    pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [layer addAnimation:pulse forKey:@"DPChatPulse"];
}

// Shows a picture of what was there, fading out over what replaced it.
void DPChatFadeAway(NSView *over, NSImage *picture, NSRect frame, CFTimeInterval duration) {
    if (!picture || !over.layer || DPChatStill()) return;
    CALayer *ghost = [CALayer layer];
    ghost.frame = frame;
    ghost.contents = picture;
    ghost.contentsGravity = kCAGravityResize;
    ghost.zPosition = 100;
    [over.layer addSublayer:ghost];
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{ [ghost removeFromSuperlayer]; }];
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @1;
    fade.toValue = @0;
    fade.duration = duration;
    fade.timingFunction = DPChatEase();
    ghost.opacity = 0;
    [ghost addAnimation:fade forKey:@"DPChatFadeAway"];
    [CATransaction commit];
}

NSImage *DPChatPicture(NSView *view) {
    if (!view.window || NSIsEmptyRect(view.bounds)) return nil;
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    NSImage *picture = [[NSImage alloc] initWithSize:view.bounds.size];
    [picture addRepresentation:rep];
    return picture;
}
