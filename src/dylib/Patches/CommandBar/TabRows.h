#import "StdPatch/StdPatch.h"

// The sidebar lays out no row for a hidden tab, and the rows after it close up.
// Dia's sidebar adds a tab's row before its page opens, so a new tab DPHidesNewTabRow names is hidden as the row is added, before anything draws.
// It shows again soon unless DPKeepTabRowHidden keeps it hidden until DPShowTabRowSoon.
BOOL DPHidesNewTabRow(NSString *tabID);
void DPKeepTabRowHidden(NSString *tabID);
void DPHideClosingTabRow(NSString *tabID);  // Until Dia takes its row out, which it animates after the tab closes.
void DPSettleTabRowSoon(NSString *tabID);
void DPShowTabRowSoon(NSString *tabID);
BOOL DPTabRowShown(NSWindow *window, NSString *tabID);
void DPInstallTabRows(void);
