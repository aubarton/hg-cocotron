#import "NSGraphicsStyle_uxtheme.h"
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/KGContext.h>
#import <AppKit/NSImage.h>
#import "Win32DeviceContextWindow.h"
#undef _WIN32_WINNT
#define _WIN32_WINNT 0x0501
#import <uxtheme.h>
#import <tmschema.h>

static void *functionWithName(const char *name){
   void              *result;
   static BOOL        lookForUxTheme=YES;
   static HANDLE      uxtheme=NULL;
   static NSMapTable *table=NULL;
   
   if(lookForUxTheme){
    if((uxtheme=LoadLibrary("UXTHEME"))!=NULL)
     table=NSCreateMapTable(NSObjectMapKeyCallBacks,NSNonOwnedPointerMapValueCallBacks,0);
     
    lookForUxTheme=NO;
   }
   
   if(table==NULL)
    result=NULL;
   else {
    NSString *string=[[NSString alloc] initWithCString:name];
    
    if((result=NSMapGet(table,string))==NULL){
     if((result=GetProcAddress(uxtheme,name))==NULL)
      NSLog(@"GetProcAddress(\"UXTHEME\",%s) FAILED",name);
     else
      NSMapInsert(table,string,result);
    }
    
    [string release];
   }
   
   return result;
}

static BOOL isThemeActive(){
   BOOL (*function)(void)=functionWithName("IsThemeActive");
   
   if(function==NULL)
    return NO;
    
   return function();
}

static HANDLE openThemeData(HWND window,LPCWSTR classList){
   HANDLE (*function)(HWND,LPCWSTR)=functionWithName("OpenThemeData");
   
   if(function==NULL)
    return NULL;
   
   return function(window,classList);
}

static void closeThemeData(HANDLE theme){
   HRESULT (*function)(HANDLE)=functionWithName("CloseThemeData");
   
   if(function==NULL)
    return;
   
   if(function(theme)!=S_OK)
    NSLog(@"CloseThemeData failed");
}

static BOOL getThemePartSize(HANDLE theme,HDC dc,int partId,int stateId,LPCRECT prc,THEME_SIZE eSize,SIZE *size){
   HRESULT (*function)(HANDLE,HDC,int,int,LPCRECT,THEME_SIZE,SIZE *)=functionWithName("GetThemePartSize");
   
   if(function==NULL)
    return NO;
   
   if(function(theme,dc,partId,stateId,prc,eSize,size)!=S_OK){
    NSLog(@"GetThemePartSize failed");
    return NO;
   }
   
   return YES;
}

static BOOL drawThemeBackground(HANDLE theme,HDC dc,int partId,int stateId,const RECT *rect,const RECT *clip){
   HRESULT (*function)(HANDLE,HDC,int,int,const RECT *,const RECT *)=functionWithName("DrawThemeBackground");
   
   if(function==NULL)
    return NO;
   
   if(function(theme,dc,partId,stateId,rect,clip)!=S_OK){
    NSLog(@"DrawThemeBackground(%x,%x,%d,%d,{%d %d %d %d}) failed",theme,dc,partId,stateId,rect->top,rect->left,rect->bottom,rect->right);
    return NO;
   }
   return YES;
}

@implementation NSGraphicsStyle(uxtheme)

+allocWithZone:(NSZone *)zone {
   if(isThemeActive())
    return NSAllocateObject([NSGraphicsStyle_uxtheme class],0,zone);
   
   return [super allocWithZone:zone];
}

@end

@implementation NSGraphicsStyle_uxtheme

-(HANDLE)themeForClassList:(LPCWSTR)classList deviceContext:(Win32DeviceContext *)deviceContext  {
   HWND windowHandle=[[deviceContext windowDeviceContext] windowHandle];
   
   if(windowHandle==NULL)
    return NULL;
    
   return openThemeData(windowHandle,classList);
}

static inline RECT transformToRECT(CGAffineTransform matrix,NSRect rect) {
   RECT    result;
   NSPoint point1=CGPointApplyAffineTransform(rect.origin,matrix);
   NSPoint point2=CGPointApplyAffineTransform(NSMakePoint(NSMaxX(rect),NSMaxY(rect)),matrix);

   if(point2.y<point1.y){
    float temp=point2.y;
    point2.y=point1.y;
    point1.y=temp;
   }

   result.top=point1.y;
   result.left=point1.x;
   result.bottom=point2.y;
   result.right=point2.x;
   
   return result;
}

-(BOOL)drawPartId:(int)partId stateId:(int)stateId classList:(LPCWSTR)classList inRect:(NSRect)rect {
   KGContext          *context=[[NSGraphicsContext currentContext] graphicsPort];
   Win32DeviceContext *deviceContext=(Win32DeviceContext *)[context renderingContext];
   HANDLE              theme;
   
   if((theme=[self themeForClassList:classList deviceContext:deviceContext])!=NULL){
    CGAffineTransform matrix;
    RECT tlbr;

// a crasher bug reveals itself if these stringWithFormat's are removed
// not sure what is going on yet.
    [NSString stringWithFormat:@"",rect.origin.x,rect.origin.y,rect.size.width,rect.size.height];
// more of the same, if we use [context ctm] it fails too. wtf.
    [context getCTM:&matrix];
    tlbr=transformToRECT(matrix,rect);
    [NSString stringWithFormat:@"",rect.origin.x,rect.origin.y,rect.size.width,rect.size.height];

    drawThemeBackground(theme,[deviceContext dc],partId,stateId,&tlbr,NULL);
       
    closeThemeData(theme);
    return YES;
   }
   return NO;
}

-(BOOL)drawButtonPartId:(int)partId stateId:(int)stateId inRect:(NSRect)rect {
   return [self drawPartId:partId stateId:stateId classList:L"BUTTON" inRect:rect];
}

-(void)drawPushButtonNormalInRect:(NSRect)rect {
   if(![self drawButtonPartId:BP_PUSHBUTTON stateId:PBS_NORMAL inRect:rect])
    [super drawPushButtonNormalInRect:rect];
}

-(void)drawPushButtonPressedInRect:(NSRect)rect {
   if(![self drawButtonPartId:BP_PUSHBUTTON stateId:PBS_PRESSED inRect:rect])
    [super drawPushButtonNormalInRect:rect];
}

-(void)drawButtonImage:(NSImage *)image inRect:(NSRect)rect enabled:(BOOL)enabled {
   BOOL worked=NO;

   if([[image name] isEqual:@"NSSwitch"])
    worked=[self drawButtonPartId:BP_CHECKBOX stateId:enabled?CBS_UNCHECKEDNORMAL:CBS_UNCHECKEDDISABLED inRect:rect];
   else if([[image name] isEqual:@"NSHighlightedSwitch"])
    worked=[self drawButtonPartId:BP_CHECKBOX stateId:enabled?CBS_CHECKEDNORMAL:CBS_CHECKEDDISABLED inRect:rect];
   else if([[image name] isEqual:@"NSRadioButton"])
    worked=[self drawButtonPartId:BP_RADIOBUTTON stateId:enabled?RBS_UNCHECKEDNORMAL:RBS_UNCHECKEDDISABLED inRect:rect];
   else if([[image name] isEqual:@"NSHighlightedRadioButton"])
    worked=[self drawButtonPartId:BP_RADIOBUTTON stateId:enabled?RBS_CHECKEDNORMAL:RBS_CHECKEDDISABLED inRect:rect];
   if(!worked)
    [super drawButtonImage:image inRect:rect enabled:enabled];
}

-(void)drawMenuSeparatorInRect:(NSRect)rect {
   if(![self drawPartId:MP_SEPARATOR stateId:MS_NORMAL classList:L"MENU" inRect:rect])
    [super drawMenuSeparatorInRect:rect];
}

-(void)drawMenuBranchArrowAtPoint:(NSPoint)point selected:(BOOL)selected {
   NSSize size=[self sizeOfMenuBranchArrow];
   NSRect rect=NSMakeRect(point.x,point.y,size.width,size.height);
   
   if(![self drawPartId:MP_CHEVRON stateId:selected?MS_SELECTED:MS_NORMAL classList:L"MENU" inRect:rect])
    [super drawMenuBranchArrowAtPoint:point selected:selected];
}

-(void)drawOutlineViewBranchInRect:(NSRect)rect expanded:(BOOL)expanded {
   if(![self drawPartId:TVP_GLYPH stateId:expanded?GLPS_OPENED:GLPS_CLOSED classList:L"TREEVIEW" inRect:rect])
    [super drawOutlineViewBranchInRect:rect expanded:expanded];
}

-(void)drawScrollerButtonInRect:(NSRect)rect enabled:(BOOL)enabled pressed:(BOOL)pressed vertical:(BOOL)vertical upOrLeft:(BOOL)upOrLeft {
   int stateId;
   
   if(vertical){
    if(upOrLeft)
     stateId=enabled?(pressed?ABS_UPPRESSED:ABS_UPNORMAL):ABS_UPDISABLED;
    else
     stateId=enabled?(pressed?ABS_DOWNPRESSED:ABS_DOWNNORMAL):ABS_DOWNDISABLED;
    }
   else {
    if(upOrLeft)
     stateId=enabled?(pressed?ABS_LEFTPRESSED:ABS_LEFTNORMAL):ABS_LEFTDISABLED;
    else
     stateId=enabled?(pressed?ABS_RIGHTPRESSED:ABS_RIGHTNORMAL):ABS_RIGHTDISABLED;
   }
   
   if(![self drawPartId:SBP_ARROWBTN stateId:stateId classList:L"SCROLLBAR" inRect:rect])
    [super drawScrollerButtonInRect:rect enabled:enabled pressed:pressed vertical:vertical upOrLeft:upOrLeft];
}

-(void)drawScrollerKnobInRect:(NSRect)rect vertical:(BOOL)vertical highlight:(BOOL)highlight {
   if(![self drawPartId:vertical?SBP_THUMBBTNVERT:SBP_THUMBBTNHORZ stateId:highlight?SCRBS_PRESSED:SCRBS_NORMAL classList:L"SCROLLBAR" inRect:rect])
    [super drawScrollerKnobInRect:rect vertical:vertical highlight:highlight];

   [self drawPartId:vertical?SBP_GRIPPERVERT:SBP_GRIPPERHORZ stateId:0 classList:L"SCROLLBAR" inRect:rect];
}

-(void)drawScrollerTrackInRect:(NSRect)rect vertical:(BOOL)vertical upOrLeft:(BOOL)upOrLeft {
   int partId=vertical?(upOrLeft?SBP_UPPERTRACKVERT:SBP_LOWERTRACKVERT):(upOrLeft?SBP_UPPERTRACKHORZ:SBP_LOWERTRACKHORZ);
   
   if(![self drawPartId:partId stateId:SCRBS_NORMAL classList:L"SCROLLBAR" inRect:rect])
    [super drawScrollerTrackInRect:rect vertical:vertical upOrLeft:upOrLeft];
}

-(void)drawTableViewHeaderInRect:(NSRect)rect highlighted:(BOOL)highlighted {
   if(![self drawPartId:HP_HEADERITEM stateId:highlighted?HIS_PRESSED:HIS_NORMAL classList:L"HEADER" inRect:rect])
    [super drawTableViewHeaderInRect:rect highlighted:highlighted];
}

-(void)drawTableViewCornerInRect:(NSRect)rect {
   if(![self drawPartId:HP_HEADERITEM stateId:HIS_NORMAL classList:L"HEADER" inRect:rect])
    [super drawTableViewCornerInRect:rect];
}

-(void)drawComboBoxButtonInRect:(NSRect)rect enabled:(BOOL)enabled bordered:(BOOL)bordered pressed:(BOOL)pressed {
   if(![self drawPartId:CP_DROPDOWNBUTTON stateId:enabled?(pressed?CBXS_PRESSED:CBXS_NORMAL):CBXS_DISABLED classList:L"COMBOBOX" inRect:rect])
    [super drawComboBoxButtonInRect:rect enabled:(BOOL)enabled bordered:bordered pressed:pressed];
}

-(void)drawSliderKnobInRect:(NSRect)rect vertical:(BOOL)vertical highlighted:(BOOL)highlighted {
   if(![self drawPartId:vertical?TKP_THUMBVERT:TKP_THUMB stateId:highlighted?TUS_PRESSED:TUS_NORMAL classList:L"TRACKBAR" inRect:rect])
    [super drawSliderKnobInRect:rect vertical:vertical highlighted:highlighted];
}

-(void)drawSliderTrackInRect:(NSRect)rect vertical:(BOOL)vertical {
   if(![self drawPartId:vertical?TKP_TRACKVERT:TKP_TRACK stateId:TRS_NORMAL classList:L"TRACKBAR" inRect:rect])
    [super drawSliderTrackInRect:rect vertical:vertical];
}

-(void)drawTabInRect:(NSRect)rect clipRect:(NSRect)clipRect color:(NSColor *)color selected:(BOOL)selected {
   if(![self drawPartId:TABP_TABITEM stateId:selected?TIS_SELECTED:TIS_NORMAL classList:L"TAB" inRect:rect])
    [super drawTabInRect:rect clipRect:clipRect color:color selected:selected];
}

-(void)drawTabPaneInRect:(NSRect)rect {
   if(![self drawPartId:TABP_PANE stateId:TIS_NORMAL classList:L"TAB" inRect:rect])
    [super drawTabPaneInRect:rect];
}

-(void)drawTextFieldBorderInRect:(NSRect)rect bezeledNotLine:(BOOL)bezeledNotLine {
   if(![self drawPartId:EP_EDITTEXT stateId:ETS_NORMAL classList:L"EDIT" inRect:rect])
    [super drawTextFieldBorderInRect:rect bezeledNotLine:bezeledNotLine];
}

//-(NSSize)sizeOfMenuBranchArrow;
//-(void)drawProgressIndicatorBezel:(NSRect)rect clipRect:(NSRect)clipRect bezeled:(BOOL)bezeled;
//-(void)drawSliderTickInRect:(NSRect)rect;
//-(void)drawStepperButtonInRect:(NSRect)rect clipRect:(NSRect)clipRect enabled:(BOOL)enabled highlighted:(BOOL)highlighted upNotDown:(BOOL)upNotDown;

@end