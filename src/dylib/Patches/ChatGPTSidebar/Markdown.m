#import "Transcript.h"

static NSMutableParagraphStyle *DPChatParagraph(CGFloat before, CGFloat indent, CGFloat hanging) {
    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
    style.lineHeightMultiple = 1.2;
    style.paragraphSpacingBefore = before;
    style.firstLineHeadIndent = indent;
    style.headIndent = indent + hanging;
    style.tabStops = hanging ? @[[[NSTextTab alloc] initWithTextAlignment:NSTextAlignmentLeft location:indent + hanging options:@{}]] : @[];
    return style;
}

NSAttributedString *DPChatMarkdown(NSString *markdown, CGFloat size) {
    static NSRegularExpression *list, *heading;
    if (!list) {
        list = [NSRegularExpression regularExpressionWithPattern:@"^([ \\t]*)([-*+]|\\d{1,3}[.)])[ \\t]+(.*)$" options:0 error:nil];
        heading = [NSRegularExpression regularExpressionWithPattern:@"^(#{1,6})[ \\t]+(.*?)[ \\t#]*$" options:0 error:nil];
    }
    NSMutableAttributedString *out = [NSMutableAttributedString new];
    NSCharacterSet *space = NSCharacterSet.whitespaceCharacterSet, *rule = [NSCharacterSet characterSetWithCharactersInString:@"-*_ "];
    NSTextBlock *code = nil;
    BOOL gap = NO, listed = NO;
    for (NSString *line in [markdown componentsSeparatedByString:@"\n"]) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:space];
        if ([trimmed hasPrefix:@"```"]) {
            gap = out.length > 0;
            if (!code && out.length) {
                // A block's margin takes its fill, so the space above it comes from the paragraph before.
                NSRange last = [out.string paragraphRangeForRange:NSMakeRange(out.length - 1, 0)];
                NSMutableParagraphStyle *style = [[out attribute:NSParagraphStyleAttributeName atIndex:last.location effectiveRange:NULL] mutableCopy];
                style.paragraphSpacing = 10;
                [out addAttribute:NSParagraphStyleAttributeName value:style range:last];
            }
            code = code ? nil : [NSTextBlock new];
            [code setValue:100 type:NSTextBlockPercentageValueType forDimension:NSTextBlockWidth];
            [code setWidth:10 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockPadding];
            [code setWidth:6 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockPadding edge:NSMinYEdge];
            code.backgroundColor = DPChatCodeFill();
            continue;
        }
        if (!code && (!trimmed.length || (trimmed.length >= 3 && ![trimmed stringByTrimmingCharactersInSet:rule].length))) {
            gap = gap || out.length;
            continue;
        }
        NSRange all = NSMakeRange(0, line.length);
        NSTextCheckingResult *item = code ? nil : [list firstMatchInString:line options:0 range:all];
        NSTextCheckingResult *title = code || item ? nil : [heading firstMatchInString:line options:0 range:all];
        CGFloat before = !out.length ? 0 : gap ? 10 : item && listed ? 4 : 0;
        if (out.length) {
            NSDictionary *last = [out attributesAtIndex:out.length - 1 effectiveRange:NULL];
            NSDictionary *end = @{NSParagraphStyleAttributeName: last[NSParagraphStyleAttributeName], NSFontAttributeName: last[NSFontAttributeName]};
            [out appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:end]];
        }
        NSMutableDictionary *base = [@{NSForegroundColorAttributeName: NSColor.labelColor} mutableCopy];
        if (code) {
            NSMutableParagraphStyle *style = DPChatParagraph(0, 0, 0);
            style.lineHeightMultiple = 1.15;
            style.textBlocks = @[code];
            base[NSParagraphStyleAttributeName] = style;
            base[NSFontAttributeName] = [NSFont monospacedSystemFontOfSize:size - 2 weight:NSFontWeightRegular];
            [out appendAttributedString:[[NSAttributedString alloc] initWithString:line.length ? line : @" " attributes:base]];
        } else if (item) {
            NSString *lead = [[line substringWithRange:[item rangeAtIndex:1]] stringByReplacingOccurrencesOfString:@"\t" withString:@"    "];
            NSString *marker = [line substringWithRange:[item rangeAtIndex:2]];
            marker = marker.length == 1 && !isdigit([marker characterAtIndex:0]) ? @"•" : marker;
            CGFloat indent = MIN(lead.length / 2, 4) * size * 1.4;
            base[NSParagraphStyleAttributeName] = DPChatParagraph(before, indent, size * 1.4);
            [out appendAttributedString:DPChatInline([NSString stringWithFormat:@"%@\t%@", marker, [line substringWithRange:[item rangeAtIndex:3]]],
                                                     size, NO, base)];
        } else if (title) {
            NSUInteger level = [title rangeAtIndex:1].length;
            base[NSParagraphStyleAttributeName] = DPChatParagraph(out.length ? before + 6 : 0, 0, 0);
            [out appendAttributedString:DPChatInline([line substringWithRange:[title rangeAtIndex:2]], size + MAX(0, 4 - (NSInteger)level), YES, base)];
        } else {
            BOOL quote = [trimmed hasPrefix:@">"];
            while ([trimmed hasPrefix:@">"]) trimmed = [[trimmed substringFromIndex:1] stringByTrimmingCharactersInSet:space];
            if (quote) base[NSForegroundColorAttributeName] = NSColor.secondaryLabelColor;
            base[NSParagraphStyleAttributeName] = DPChatParagraph(before, quote ? 12 : 0, 0);
            [out appendAttributedString:DPChatInline(trimmed, size, NO, base)];
        }
        gap = NO;
        listed = item != nil;
    }
    return out;
}
