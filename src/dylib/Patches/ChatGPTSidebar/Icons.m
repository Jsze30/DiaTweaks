#import "Transcript.h"

// Phosphor icons (regular weight) as their strokes on the 256-unit grid: M/L draw lines, Z closes, R x y w h r adds a rounded rectangle.
static NSString *DPChatIconPath(NSString *name) {
    static NSDictionary<NSString *, NSString *> *paths;
    if (!paths) paths = @{
        @"copy": @"M168 168 L216 168 L216 40 L88 40 L88 88 M40 88 L168 88 L168 216 L40 216 Z",
        @"check": @"M40 144 L96 200 L224 72",
        @"x": @"M200 56 L56 200 M200 200 L56 56",
        @"browser": @"R 32 48 192 160 8 M32 96 L224 96",
        @"chat": @"R 32 56 192 144 8 M80 200 L45.15 230.11 L32 224 L32 192",
        @"arrows": @"M176 144 L208 176 L176 208 M48 176 L208 176 M80 112 L48 80 L80 48 M208 80 L48 80",
    };
    return paths[name];
}

NSImage *DPChatGlyph(NSString *name, CGFloat size) {
    NSArray<NSString *> *tokens = [DPChatIconPath(name) componentsSeparatedByString:@" "];
    NSImage *image = [NSImage imageWithSize:NSMakeSize(size, size) flipped:YES drawingHandler:^BOOL(NSRect rect) {
        NSAffineTransform *scale = [NSAffineTransform transform];
        [scale scaleBy:size / 256];
        [scale concat];
        NSBezierPath *path = [NSBezierPath bezierPath];
        path.lineWidth = 16;
        path.lineJoinStyle = NSLineJoinStyleRound;
        path.lineCapStyle = NSLineCapStyleRound;
        __block NSUInteger i = 0;
        while (i < tokens.count) {
            NSString *op = tokens[i++];
            CGFloat (^next)(void) = ^CGFloat { return tokens[i++].doubleValue; };
            if ([op isEqual:@"Z"]) [path closePath];
            else if ([op hasPrefix:@"R"]) {
                CGFloat x = next(), y = next(), w = next(), h = next(), r = next();
                [path appendBezierPathWithRoundedRect:NSMakeRect(x, y, w, h) xRadius:r yRadius:r];
            } else {
                NSPoint point = NSMakePoint([op substringFromIndex:1].doubleValue, next());
                [op hasPrefix:@"M"] ? [path moveToPoint:point] : [path lineToPoint:point];
            }
        }
        [NSColor.blackColor setStroke];
        [path stroke];
        return YES;
    }];
    image.template = YES;
    return image;
}
