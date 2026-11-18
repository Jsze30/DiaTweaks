#import "Transcript.h"

// Dia's compact chat: 14pt text on 23pt lines, 12pt between blocks and 5pt between list items, lists and quotes indented 24pt and 23pt.
static const CGFloat DPChatBlockGap = 12, DPChatItemGap = 5, DPChatListIndent = 24, DPChatQuoteIndent = 23;

NSDictionary *DPChatLine(NSFont *font, CGFloat height, NSMutableParagraphStyle *style) {
    style.minimumLineHeight = style.maximumLineHeight = height;
    // TextKit puts a tall line's extra room above the text; CSS splits it evenly, so lift the baseline by half.
    return @{NSParagraphStyleAttributeName: style, NSBaselineOffsetAttributeName: @((height - font.ascender + font.descender) / 2)};
}

// `marker` is where a list item's marker ends, measured from `indent`; its text starts a list indent in.
static NSMutableParagraphStyle *DPChatParagraph(CGFloat before, CGFloat indent, CGFloat marker) {
    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
    style.paragraphSpacingBefore = before;
    style.firstLineHeadIndent = indent;
    style.headIndent = marker ? indent + DPChatListIndent : indent;
    style.tabStops = !marker ? @[] : @[[[NSTextTab alloc] initWithTextAlignment:NSTextAlignmentRight location:indent + marker options:@{}],
                                       [[NSTextTab alloc] initWithTextAlignment:NSTextAlignmentLeft location:indent + DPChatListIndent options:@{}]];
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
    NSFont *body = [NSFont systemFontOfSize:size];
    CGFloat line = round(size * 23 / 14);
    NSTextBlock *code = nil;
    BOOL gap = NO, listed = NO, titled = NO;
    NSUInteger leads[8], depth = 0;  // the indent of each open list level
    for (NSString *text in [markdown componentsSeparatedByString:@"\n"]) {
        NSString *trimmed = [text stringByTrimmingCharactersInSet:space];
        if ([trimmed hasPrefix:@"```"]) {
            gap = out.length > 0;
            if (!code && out.length) {
                // A block's margin takes its fill, so the space above it comes from the paragraph before.
                NSRange last = [out.string paragraphRangeForRange:NSMakeRange(out.length - 1, 0)];
                NSMutableParagraphStyle *style = [[out attribute:NSParagraphStyleAttributeName atIndex:last.location effectiveRange:NULL] mutableCopy];
                style.paragraphSpacing = DPChatBlockGap;
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
        NSRange all = NSMakeRange(0, text.length);
        NSTextCheckingResult *item = code ? nil : [list firstMatchInString:text options:0 range:all];
        NSTextCheckingResult *title = code || item ? nil : [heading firstMatchInString:text options:0 range:all];
        CGFloat before = !out.length ? 0 : item && listed ? DPChatItemGap : gap || titled || (title && out.length) ? DPChatBlockGap : 0;
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
            [out appendAttributedString:[[NSAttributedString alloc] initWithString:text.length ? text : @" " attributes:base]];
        } else if (item) {
            NSUInteger lead = [[text substringWithRange:[item rangeAtIndex:1]] stringByReplacingOccurrencesOfString:@"\t" withString:@"    "].length;
            if (!listed) depth = 0;
            while (depth && leads[depth - 1] > lead) depth--;
            if ((!depth || leads[depth - 1] < lead) && depth < 8) leads[depth++] = lead;
            NSString *marker = [text substringWithRange:[item rangeAtIndex:2]];
            BOOL bullet = marker.length == 1 && !isdigit([marker characterAtIndex:0]);
            // WebKit draws a 4.5pt disc whose right edge is 16pt in, and ends a number a space short of the text.
            NSMutableParagraphStyle *style = DPChatParagraph(before, MIN(depth - 1, 4) * DPChatListIndent, DPChatListIndent - size * (bullet ? 0.49 : 0.27));
            [base addEntriesFromDictionary:DPChatLine(body, line, style)];
            NSMutableDictionary *dot = [base mutableCopy];
            dot[NSFontAttributeName] = bullet ? [NSFont systemFontOfSize:size weight:NSFontWeightBlack] : body;
            [out appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\t%@\t", bullet ? @"•" : marker] attributes:dot]];
            [out appendAttributedString:DPChatInline([text substringWithRange:[item rangeAtIndex:3]], size, NSFontWeightRegular, base)];
        } else if (title) {
            NSUInteger level = MIN([title rangeAtIndex:1].length, 4) - 1;
            CGFloat sizes[] = {22, 17, 16, 15};
            NSFontWeight weights[] = {NSFontWeightMedium, NSFontWeightSemibold, NSFontWeightSemibold, NSFontWeightMedium};
            [base addEntriesFromDictionary:DPChatLine([NSFont systemFontOfSize:sizes[level]], ceil(sizes[level] * 1.3), DPChatParagraph(before, 0, 0))];
            [out appendAttributedString:DPChatInline([text substringWithRange:[title rangeAtIndex:2]], sizes[level], weights[level], base)];
        } else {
            BOOL quote = [trimmed hasPrefix:@">"];
            while ([trimmed hasPrefix:@">"]) trimmed = [[trimmed substringFromIndex:1] stringByTrimmingCharactersInSet:space];
            if (quote) base[NSForegroundColorAttributeName] = NSColor.secondaryLabelColor;
            [base addEntriesFromDictionary:DPChatLine(body, line, DPChatParagraph(before, quote ? DPChatQuoteIndent : 0, 0))];
            [out appendAttributedString:DPChatInline(trimmed, size, NSFontWeightRegular, base)];
        }
        gap = NO;
        listed = item != nil;
        titled = title != nil;
    }
    return out;
}
