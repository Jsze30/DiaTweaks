#import "Transcript.h"

static NSFont *DPChatFont(CGFloat size, NSFontWeight weight, BOOL italic) {
    NSFont *font = [NSFont systemFontOfSize:size weight:weight];
    if (!italic) return font;
    NSFontDescriptor *slanted = [font.fontDescriptor fontDescriptorWithSymbolicTraits:font.fontDescriptor.symbolicTraits | NSFontDescriptorTraitItalic];
    return [NSFont fontWithDescriptor:slanted size:size] ?: font;
}

NSColor *DPChatCodeFill(void) { return [NSColor.labelColor colorWithAlphaComponent:0.06]; }

NSAttributedString *DPChatInline(NSString *text, CGFloat size, NSFontWeight weight, NSDictionary *base) {
    NSMutableDictionary *plain = [base mutableCopy];
    plain[NSFontAttributeName] = DPChatFont(size, weight, NO);
    static NSCharacterSet *marks;
    static NSAttributedStringMarkdownParsingOptions *options;
    static NSCache<NSString *, NSAttributedString *> *cache;
    if (!options) {
        cache = [NSCache new];
        cache.countLimit = 1000;
        marks = [NSCharacterSet characterSetWithCharactersInString:@"*_`[~<\\&"];
        options = [NSAttributedStringMarkdownParsingOptions new];
        options.interpretedSyntax = NSAttributedStringMarkdownInterpretedSyntaxInlineOnlyPreservingWhitespace;
        options.failurePolicy = NSAttributedStringMarkdownParsingFailureReturnPartiallyParsedIfPossible;
    }
    // Streaming re-renders every line many times, so remember what each one parsed to.
    BOOL marked = [text rangeOfCharacterFromSet:marks].location != NSNotFound;
    NSAttributedString *parsed = marked ? [cache objectForKey:text] : nil;
    if (marked && !parsed) {
        parsed = [[NSAttributedString alloc] initWithMarkdownString:text options:options baseURL:nil error:nil];
        if (parsed) [cache setObject:parsed forKey:text];
    }
    if (!parsed) return [[NSAttributedString alloc] initWithString:text attributes:plain];
    NSMutableAttributedString *out = [[NSMutableAttributedString alloc] initWithString:parsed.string attributes:plain];
    [parsed enumerateAttributesInRange:NSMakeRange(0, parsed.length) options:0 usingBlock:^(NSDictionary *attributes, NSRange range, BOOL *stop) {
        NSInlinePresentationIntent intent = [attributes[NSInlinePresentationIntentAttributeName] unsignedIntegerValue];
        NSMutableDictionary *styled = [plain mutableCopy];
        if (intent & NSInlinePresentationIntentCode) {
            styled[NSFontAttributeName] = [NSFont monospacedSystemFontOfSize:size - 1 weight:weight];
            styled[NSBackgroundColorAttributeName] = DPChatCodeFill();
        } else styled[NSFontAttributeName] = DPChatFont(size, intent & NSInlinePresentationIntentStronglyEmphasized ? MAX(weight, NSFontWeightSemibold) : weight,
                                                        intent & NSInlinePresentationIntentEmphasized);
        if (intent & NSInlinePresentationIntentStrikethrough) styled[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
        if (attributes[NSLinkAttributeName]) styled[NSLinkAttributeName] = attributes[NSLinkAttributeName];
        [out setAttributes:styled range:range];
    }];
    return out;
}
