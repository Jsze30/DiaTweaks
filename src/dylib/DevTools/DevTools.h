#import "StdPatch/StdPatch.h"

void DPInstallDevTools(void);
NSString *DPDescribeViews(NSView *root);
NSString *DPBesideDylib(NSString *name);
void DPTraceLayoutLoops(void);
void DPTraceTo(NSString *path);
void DPTrace(NSString *spec);
void DPTraceMark(NSString *text);
void DPUntrace(void);
