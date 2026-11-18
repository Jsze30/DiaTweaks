#import "Patches/CommandBar/TabRows.h"

@interface NSObject (DPDiffable)
- (id)snapshot;
- (NSArray *)itemIdentifiers;
- (NSIndexPath *)indexPathForItemIdentifier:(id)identifier;
@end

typedef NS_ENUM(NSInteger, DPRowHiding) { DPRowPending, DPRowKept, DPRowClosing };
static NSMutableDictionary<NSString *, NSNumber *> *DPHiddenRows;  // Tab ID: DPRowHiding.

// Dia names a tab's row TabList.TabListView.CollectionViewItem.tab(<tab ID>).
static NSString *DPRowTab(id row) {
    NSString *name = [row description];
    NSRange open = [name rangeOfString:@".tab("];
    if (open.location == NSNotFound || ![name hasSuffix:@")"]) return nil;
    return [name substringWithRange:NSMakeRange(NSMaxRange(open), name.length - NSMaxRange(open) - 1)];
}

static void DPRelayoutRows(void) {
    for (NSCollectionView *list in DPFindViews(DPDiaTabListCollection)) [list.collectionViewLayout invalidateLayout];
}

static void DPShowTabRow(NSString *tabID) {
    if (!tabID || !DPHiddenRows[tabID] || DPHiddenRows[tabID].integerValue == DPRowClosing) return;
    [DPHiddenRows removeObjectForKey:tabID];
    DPRelayoutRows();
}

static void DPSettleTabRow(NSString *tabID) {
    if (tabID && DPHiddenRows[tabID].integerValue == DPRowPending) DPShowTabRow(tabID);
}

void DPShowTabRowSoon(NSString *tabID) {
    dispatch_async(dispatch_get_main_queue(), ^{ DPShowTabRow(tabID); });
}

void DPSettleTabRowSoon(NSString *tabID) {
    dispatch_async(dispatch_get_main_queue(), ^{ DPSettleTabRow(tabID); });
}

static void DPHideTabRow(NSString *tabID, DPRowHiding hiding) {
    if (!tabID) return;
    BOOL shown = !DPHiddenRows[tabID];
    DPHiddenRows[tabID] = @(hiding);
    if (shown) DPRelayoutRows();
}

void DPKeepTabRowHidden(NSString *tabID) { DPHideTabRow(tabID, DPRowKept); }
void DPHideClosingTabRow(NSString *tabID) { DPHideTabRow(tabID, DPRowClosing); }

static NSMutableSet<NSString *> *DPRowTabs(id snapshot) {
    NSMutableSet<NSString *> *tabs = [NSMutableSet set];
    for (id row in [snapshot itemIdentifiers]) {
        NSString *tab = DPRowTab(row);
        if (tab) [tabs addObject:tab];
    }
    return tabs;
}

static void DPSource_apply(id self, SEL _cmd, id snapshot, BOOL animate, void (^completion)(void)) {
    NSSet<NSString *> *now = NSThread.isMainThread ? DPRowTabs(snapshot) : nil, *before = now.count ? DPRowTabs([self snapshot]) : nil;
    for (NSString *tab in before)
        if (![now containsObject:tab] && DPHiddenRows[tab].integerValue == DPRowClosing) [DPHiddenRows removeObjectForKey:tab];
    for (NSString *tab in now) {
        if (DPHiddenRows[tab] || [before containsObject:tab] || !DPHidesNewTabRow(tab)) continue;
        DPHiddenRows[tab] = @(DPRowPending);
        // In case its page never opens to settle it.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ DPSettleTabRow(tab); });
    }
    DPCallOriginal(DPSource_apply, self, snapshot, animate, completion);
}

static id DPRowSource(NSCollectionView *list) {
    __unsafe_unretained id *source = (__unsafe_unretained id *)DPIvar(list.dataSource, "_impl");
    return source && [*source respondsToSelector:@selector(indexPathForItemIdentifier:)] ? *source : nil;
}

static NSIndexPath *DPRowPath(NSCollectionView *list, BOOL (^match)(NSString *tabID)) {
    id snapshot = [DPRowSource(list) snapshot];
    for (id row in [snapshot itemIdentifiers]) {
        NSString *tab = DPRowTab(row);
        if (tab && match(tab)) return [snapshot indexPathForItemIdentifier:row];
    }
    return nil;
}

static NSCollectionViewLayoutAttributes *DPLayout_item(NSCollectionViewLayout *self, SEL _cmd, NSIndexPath *path);

// The hidden row and the space Dia gives it.
static NSIndexPath *DPGap(NSCollectionViewLayout *layout, NSRect *gap) {
    if (!DPHiddenRows.count) return nil;
    NSIndexPath *path = DPRowPath(layout.collectionView, ^BOOL(NSString *tabID) { return DPHiddenRows[tabID] != nil; });
    SEL item = @selector(layoutAttributesForItemAtIndexPath:);
    NSCollectionViewLayoutAttributes *row = path ? ((id (*)(id, SEL, id))DPOriginalIMP(layout, item, (IMP)DPLayout_item))(layout, item, path) : nil;
    if (!row || NSHeight(row.frame) <= 0) return nil;
    *gap = row.frame;
    return path;
}

static NSCollectionViewLayoutAttributes *DPClosedUp(NSCollectionViewLayoutAttributes *attributes, NSIndexPath *hidden, NSRect gap) {
    if (!attributes) return nil;
    BOOL row = attributes.representedElementCategory == NSCollectionElementCategoryItem && [attributes.indexPath isEqual:hidden];
    NSRect frame = attributes.frame;
    BOOL below = NSMinY(frame) >= NSMinY(gap) + 0.5, around = !below && NSMaxY(frame) >= NSMaxY(gap) - 0.5;
    if (!row && !below && !around) return attributes;
    attributes = [attributes copy];
    if (row) {
        attributes.hidden = YES;
        attributes.alpha = 0;
    } else if (below) {
        attributes.frame = NSOffsetRect(frame, 0, -NSHeight(gap));
    } else {
        frame.size.height = MAX(0, NSHeight(frame) - NSHeight(gap));  // A group the row sits in.
        attributes.frame = frame;
    }
    return attributes;
}

static NSCollectionViewLayoutAttributes *DPLayout_item(NSCollectionViewLayout *self, SEL _cmd, NSIndexPath *path) {
    NSRect gap;
    NSIndexPath *hidden = DPGap(self, &gap);
    NSCollectionViewLayoutAttributes *attributes = DPCallOriginal(DPLayout_item, self, path);
    return hidden ? DPClosedUp(attributes, hidden, gap) : attributes;
}

static NSCollectionViewLayoutAttributes *DPLayout_appearing(NSCollectionViewLayout *self, SEL _cmd, NSIndexPath *path) {
    NSRect gap;
    NSIndexPath *hidden = DPGap(self, &gap);
    NSCollectionViewLayoutAttributes *attributes = DPCallOriginal(DPLayout_appearing, self, path);
    return hidden ? DPClosedUp(attributes, hidden, gap) : attributes;
}

static NSArray *DPLayout_elements(NSCollectionViewLayout *self, SEL _cmd, NSRect rect) {
    NSRect gap;
    NSIndexPath *hidden = DPGap(self, &gap);
    if (!hidden) return DPCallOriginal(DPLayout_elements, self, rect);
    NSRect reach = rect;
    reach.size.height += NSHeight(gap);  // Rows just below move up into it.
    NSMutableArray *shown = [NSMutableArray array];
    for (NSCollectionViewLayoutAttributes *attributes in DPCallOriginal(DPLayout_elements, self, reach)) {
        NSCollectionViewLayoutAttributes *each = DPClosedUp(attributes, hidden, gap);
        // Left out, the hidden row gets no view to draw or take clicks.
        if (!each.hidden && NSIntersectsRect(each.frame, rect)) [shown addObject:each];
    }
    return shown;
}

static NSSize DPLayout_size(NSCollectionViewLayout *self, SEL _cmd) {
    NSRect gap;
    NSSize size = DPCallOriginal(DPLayout_size, self);
    if (DPGap(self, &gap)) size.height = MAX(0, size.height - NSHeight(gap));
    return size;
}

BOOL DPTabRowShown(NSWindow *window, NSString *tabID) {
    for (NSCollectionView *list in DPFindViews(DPDiaTabListCollection)) {
        if (list.window != window) continue;
        NSIndexPath *path = DPRowPath(list, ^BOOL(NSString *each) { return [each isEqual:tabID]; });
        NSCollectionViewLayoutAttributes *row = path ? [list.collectionViewLayout layoutAttributesForItemAtIndexPath:path] : nil;
        if (row && !row.hidden && row.alpha > 0) return YES;
    }
    return NO;
}

void DPInstallTabRows(void) {
    DPHiddenRows = [NSMutableDictionary dictionary];
    DPHook("__NSDiffableDataSource", @selector(applyDifferencesFromSnapshot:animatingDifferences:completion:), (IMP)DPSource_apply);
    DPHook(DPDiaTabListLayout, @selector(layoutAttributesForItemAtIndexPath:), (IMP)DPLayout_item);
    DPHook(DPDiaTabListLayout, @selector(initialLayoutAttributesForAppearingItemAtIndexPath:), (IMP)DPLayout_appearing);
    DPHook(DPDiaTabListLayout, @selector(layoutAttributesForElementsInRect:), (IMP)DPLayout_elements);
    DPHook(DPDiaTabListLayout, @selector(collectionViewContentSize), (IMP)DPLayout_size);
}
