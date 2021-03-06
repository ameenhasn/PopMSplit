//
//  POPAppDelegate.m
//  PopMSplit
//
//  Created by Kevin Scardina on 4/27/12.
//  Copyright (c) 2012 __PopMedic__. All rights reserved.
//

#import "POPAppDelegate.h"

@implementation POPAppDelegate

@synthesize playBtn = _playBtn;
@synthesize seekSlider = _seekSlider;
@synthesize movieView = _movieView;
@synthesize splitInfo = _splitInfo;
@synthesize infoLabel = _infoLabel;
@synthesize marks = _marks;
@synthesize splitWnd = _splitWnd;
@synthesize splitOutput = _splitOutput;
@synthesize convertCB = _convertCB;
@synthesize convertToBtn = _convertToBtn;
@synthesize outputDirectoryBtn = _outputDirectoryBtn;
@synthesize outputFilenameMaskField = _outputFilenameMaskField;
@synthesize outputDirectoryRB = _outputDirectoryRB;
@synthesize outputDirectoryText = _outputDirectoryText;
@synthesize splitTable = _splitTable;
@synthesize splitStartStopBtn = _splitStartStopBtn;
@synthesize closeSplitBtn = _closeSplitBtn;
@synthesize aboutWnd = _aboutWnd;
@synthesize prefWnd = _prefWnd;
@synthesize splitProgIndicator = _splitProgIndicator;
@synthesize audioCB = _audioCB;
@synthesize videoCB = _videoCB;
@synthesize window = _window;
@synthesize movie;
@synthesize playing;
@synthesize rate;
@synthesize slideTimer;
@synthesize splitInfoThread;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Insert code here to initialize your application
    [self setPlaying:NO];
    [self setMovie:nil];
    [self setRate:0.0];
    [self setSlideTimer:nil];
    splitDS = nil;
    splitting = false;
    [[self splitOutput] setEditable:NO];
    [[self splitOutput] setContinuousSpellCheckingEnabled:NO];
    
    NSString *errorDesc = nil;
    NSPropertyListFormat format;
    NSString *plistPath = [[NSBundle mainBundle] pathForResource:@"data" ofType:@"plist"];
    NSData* plistXML = [[NSFileManager defaultManager] contentsAtPath:plistPath];
    NSDictionary* temp = (NSDictionary*)[NSPropertyListSerialization
                                         propertyListFromData:plistXML 
                                         mutabilityOption:NSPropertyListMutableContainersAndLeaves 
                                         format:&format 
                                         errorDescription:&errorDesc];
    if(!temp)
    {
        NSLog(@"Error reading plist: %@, format %d", errorDesc, (int)format);
    }
    outputMask = [temp objectForKey:@"output-mask"];
    [[self outputFilenameMaskField] setStringValue:outputMask];
    
    outputDir = [temp objectForKey:@"output-directory"];
    if([outputDir compare:@"Same as source." options:NSCaseInsensitiveSearch] == NSOrderedSame)
    {
        [[self outputDirectoryRB] selectCellWithTag:1];
    }
    else{
        [[self outputDirectoryRB] selectCellWithTag:2];
        [[self outputDirectoryText] setStringValue:outputDir];
    }
}

-(NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    NSString *error;
    NSString *plistPath = [[NSBundle mainBundle] pathForResource:@"data" ofType:@"plist"];
    NSDictionary* plistDict = [NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects: outputDir, outputMask, nil] forKeys:[NSArray arrayWithObjects:@"output-directory", @"output-mask", nil]];
    NSData* plistData = [NSPropertyListSerialization dataWithPropertyList:plistDict 
                                                                   format:NSPropertyListXMLFormat_v1_0 
                                                                  options:NSPropertyListMutableContainersAndLeaves
                                                                    error:(NSError**)&error];
    if(plistData)
    {
        [plistData writeToFile:plistPath atomically:YES];
    }
    else {
        NSLog(@"%@", error);
    }
    return NSTerminateNow;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return YES;
}

- (void)awakeFromNib
{
    [[self window] makeKeyAndOrderFront:nil];
}

- (IBAction)selectSource:(id)sender
{
    NSOpenPanel* oDlg = [NSOpenPanel openPanel];
    [oDlg setCanChooseFiles:YES];
    [oDlg setCanCreateDirectories:NO];
    [oDlg beginSheetModalForWindow:[self window] completionHandler:^(NSInteger result) {
        if (result == NSFileHandlingPanelOKButton)
        {
            NSArray* urls = [oDlg URLs];
            url = [urls objectAtIndex:0];
            NSString* fn = [url absoluteString];
            [[self infoLabel] setStringValue:fn];
            QTMovie *nm = [QTMovie movieWithURL:url error:nil];
            if(nm)
            {
                [self setMovie:nm];
                [[self movieView] setMovie:[self movie]];
                [[self seekSlider] setMinValue:0];
                [[self seekSlider] setMaxValue:(double)[[self movie] duration].timeValue];
                [[self seekSlider] setFloatValue:0.0];
            }
            [[self marks] removeAllItems];
            [[self marks] addItemWithTitle:@"Split Marks:"];
        }
    }];
}

- (IBAction)play:(id)sender {
    if ([self movie] == nil)
    {
        [self selectSource:sender];
    }
    else if([self playing])
    {
        [[self movie] stop];
        [self setPlaying:NO];
        [self setRate:0.0];
        [[self playBtn] setImage:[NSImage imageNamed:@"play.png"]];
        [self stopSliderTimer];
    }
    else 
    {
        
        [[self movie] play];
        [self setPlaying:YES];
        [self setRate:1.0];
        [[self playBtn] setImage:[NSImage imageNamed:@"pause.png"]];
        [self startSliderTimer];
    }
}

- (IBAction)stop:(id)sender {
    while ([self movie] == nil)
    {
        [self selectSource:sender];
    }
    if([self playing])
    {
        [self play:sender];
    }
    [[self movie] gotoBeginning];
    [[self seekSlider] setFloatValue:0.0];
    [[self infoLabel] setStringValue:[NSString stringWithFormat:@"Rate: %.0fx; At: %.2f; Of: %.2f", [self rate], (float)[[self movie] currentTime].timeValue/100, (float)[[self movie] duration].timeValue/100]];
}

- (IBAction)back:(id)sender {
    if([self playing])
    {
        float r = [self rate] - 1;
        if (r == 0.0) r = -1.0;
        [self setRate:r];
        [[self movie] setRate: [self rate]];
    }
        
}

- (IBAction)forward:(id)sender {
    if([self playing])
    {
        float r = [self rate] + 1;
        [self setRate:r];
        [[self movie] setRate: [self rate]];
    }
}

- (IBAction)addSplit:(id)sender {
    if([self movie] != nil)
    {
        NSString *nt = QTStringFromTime([[self movie] currentTime]);
        [[self marks] addItemWithTitle:nt];
        [[self marks] selectItemWithTitle:nt];
    }
}

- (IBAction)removeSplit:(id)sender {
    NSMenuItem* mi = [[self marks] selectedItem];
    int idx = [[self marks] indexOfItem:mi];
    if(idx != 0)
    {
        [[self marks] removeItemAtIndex:idx];
    }
}

- (IBAction)seek:(id)sender {
    if([movie duration].timeValue > 0)
    {
        QTTime qtt = QTMakeTime((long)(long)[[self seekSlider] floatValue], [[self movie] currentTime].timeScale);
        [[self movie] setCurrentTime:qtt];
        [[self infoLabel] setStringValue:[NSString stringWithFormat:@"Rate: %.0fx; At: %@; Of: %@", [self rate], QTStringFromTime([[self movie] currentTime]), QTStringFromTime([[self movie] duration])]];
    }
}

- (IBAction)about:(id)sender {
    [NSApp beginSheet: [self aboutWnd] modalForWindow: [self window] modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
}

- (IBAction)gotoMark:(id)sender {
    NSMenuItem* mi = [[self marks] selectedItem];
    int idx = [[self marks] indexOfItem:mi];
    if(idx != 0)
    {
        NSMenuItem* mi = [[self marks] selectedItem];
        QTTime qtt = QTTimeFromString(mi.title);
        [[self movie] setCurrentTime:qtt];
        [[self seekSlider] setFloatValue:(float)qtt.timeValue];
    }
}

- (IBAction)split:(id)sender {
    if([[self movie] duration].timeValue > 0)
    {
        if(splitDS == nil)
        {
            splitDS = [[NSMutableArray alloc] init];
        }
        
        [splitDS removeAllObjects];
        NSArray *mrkMis = [[[self marks] itemArray] sortedArrayUsingFunction:qttsSort context:NULL];
        float stf = 0.0;
        float enf = 0.0;
        float lnf = 0.0;
        long ts = 0;
        for(int i = 1; i <= [mrkMis count]; i++)
        {
            if(i == [mrkMis count])
            {
                ts = [movie duration].timeScale;
                enf = [movie duration].timeValue;
                lnf = enf - stf;
            }
            else
            {
                QTTime qtt = QTTimeFromString([[mrkMis objectAtIndex:i] title]);
                ts = qtt.timeScale;
                enf = qtt.timeValue;
                lnf = enf - stf;
            }
            NSString* sts = QTStringFromTime(QTMakeTime((long)(long)stf, ts));
            NSString* lns = QTStringFromTime(QTMakeTime((long)(long)lnf, ts));
            
            NSString *stfs = [NSString stringWithFormat: @"%@.%02d", [[sts substringFromIndex:2] substringToIndex:8], (([[[sts substringFromIndex:11] substringToIndex:2] intValue]*3)/10)];
            NSString *lnfs = [NSString stringWithFormat: @"%@.%02d", [[lns substringFromIndex:2] substringToIndex:8], (([[[lns substringFromIndex:11] substringToIndex:2] intValue]*3)/10)];
            
            NSString* fn;
            NSString* fn_fmt = [[outputMask stringByReplacingOccurrencesOfString:@"%fn%" withString:[[[url relativePath] lastPathComponent] stringByDeletingPathExtension]] stringByReplacingOccurrencesOfString:@"%i%" withString:@"%d"];
            if([[self outputDirectoryRB] selectedTag] == 1) 
            {
                fn = [[[[[url relativePath] stringByDeletingLastPathComponent] stringByAppendingPathComponent:[NSString stringWithFormat:fn_fmt, i]] stringByAppendingString:@"."] stringByAppendingString:[url pathExtension]];
            }
            else {
                fn = [outputDir stringByAppendingPathComponent:[[[NSString stringWithFormat:fn_fmt, i] stringByAppendingString: @"."]stringByAppendingString:[url pathExtension]]];
            }
            
            [splitDS addObject:[[NSMutableArray alloc] initWithObjects:stfs, lnfs, fn, nil]];
            stf = enf;
        }
        
        [[self splitTable] reloadData];
        splitting = false;
        [NSApp beginSheet: [self splitWnd] modalForWindow: [self window] modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
    }
}

- (IBAction)closeSplitWnd:(id)sender
{
    [NSApp endSheet:[self splitWnd]];
    [[self splitWnd] orderOut:self];
}

- (IBAction)splitStartStop:(id)sender {
    NSTask* task = nil;

    if(splitting)
    {
        if(tasksIdx < [tasks count])
        {
            task = (NSTask*)[tasks objectAtIndex:tasksIdx];
            [task terminate];
        }
        splitting = false;
        [[self splitStartStopBtn] setImage:[NSImage imageNamed:@"play"]];
        [[self splitProgIndicator] setHidden:YES];
    }
    else 
    {
        tasks = [[NSMutableArray alloc] init];
        taskLens = [[NSMutableArray alloc] init];
        tasksIdx = 0; 
        totalLength = runningLength = oldRunLength = 0;
        
        for(int i = 0; i < [splitDS count]; i++)
        {
            totalLength += [self secsFromTimeStr:(NSString*)[[splitDS objectAtIndex:i] objectAtIndex:1]];
            [taskLens addObject:[NSNumber numberWithFloat:totalLength]];
            NSLog(@"%d: totalLength = %f", i, totalLength);
            NSString* fn = (NSString*)[[splitDS objectAtIndex:i] objectAtIndex:2];
            task = [[NSTask alloc] init];
            [task setLaunchPath:[[NSBundle mainBundle] pathForResource:@"ffmpeg" ofType:nil]];
            NSMutableArray* tmpma = [NSMutableArray arrayWithObjects:  
                                     @"-ss", (NSString*)[[splitDS objectAtIndex:i] objectAtIndex:0], 
                                     @"-t", (NSString*)[[splitDS objectAtIndex:i] objectAtIndex:1],
                                     @"-i", [url relativePath], @"-y", nil];
            
            if ([[self audioCB] state] == NSOnState && [[self videoCB] state] == NSOnState) {
                if([[self convertCB] state] == NSOnState) {
                    [tmpma addObject:@"-same_quant"];
                    [tmpma addObject:@"-ac"];
                    [tmpma addObject:@"2"];
                    NSString* c2 = [[[self convertToBtn] selectedItem] title];
                    if([c2 compare:@"flv" options:NSCaseInsensitiveSearch] == NSOrderedSame)
                    {
                        [tmpma addObject:@"-ar"];
                        [tmpma addObject:@"44100"];
                    }
                    fn = [[fn stringByDeletingPathExtension] stringByAppendingPathExtension:[[[self convertToBtn] selectedItem] title]];
                }
                else {
                    [tmpma addObject:@"-vcodec"];
                    [tmpma addObject:@"copy"];
                    //[tmpma addObject:@"-acodec"];
                    //[tmpma addObject:@"copy"];
                }
            }
            if ([[self audioCB] state] == NSOnState && [[self videoCB] state] == NSOffState) {
                [tmpma addObject:@"-vn"];
                [tmpma addObject:@"-ac"];
                [tmpma addObject:@"2"];
                fn = [[fn stringByDeletingPathExtension] stringByAppendingPathExtension:@"mp3"];            }
            if ([[self videoCB] state] == NSOnState && [[self audioCB] state] == NSOffState) {
                if([[self convertCB] state] == NSOnState) {
                    [tmpma addObject:@"-same_quant"];
                    fn = [[fn stringByDeletingPathExtension] stringByAppendingPathExtension:[[[self convertToBtn] selectedItem] title]];
                }
                else {
                    [tmpma addObject:@"-vcodec"];
                    [tmpma addObject:@"copy"];
                }
                [tmpma addObject:@"-an"];
            }
            [tmpma addObject:@"-threads"];
            [tmpma addObject:@"0"];
            [tmpma addObject:fn];
            
            [task setStandardOutput:[NSPipe pipe]];
            [task setStandardError:[task standardOutput]];
            [task setArguments:tmpma];
            if ([[NSFileManager defaultManager] fileExistsAtPath:fn])
            {
                if(NSRunAlertPanel(@"File Exists", [NSString stringWithFormat:@"File %@ exists.", fn], @"Replace", @"Skip", nil) == NSAlertDefaultReturn)
                {
                    [tasks addObject:task];
                }
            }
            else
            {
                [tasks addObject:task];
            }
            task = nil;
        }
        if([tasks count] > 0)
        {
            allSplitInfo = @"";
            [[self splitProgIndicator] setHidden:NO];
            [[self splitProgIndicator] setIndeterminate:NO];
            [[self splitProgIndicator] setMinValue:0];
            [[self splitProgIndicator] setMaxValue:totalLength];
            splitting = true;
            [[self splitStartStopBtn] setImage:[NSImage imageNamed:@"stop"]];
            [[self closeSplitBtn] setEnabled:NO];
            [self runCurrentTask];
        }
    }
}

- (void)taskExited
{
    NSTask* task = (NSTask*)[tasks objectAtIndex:tasksIdx];
    [[NSNotificationCenter defaultCenter]
     removeObserver:self
     name:NSFileHandleReadCompletionNotification 
     object:[[task standardOutput] fileHandleForReading]];
    [[self splitInfoThread] cancel];
    
    if(splitting)
    {
        [[self splitOutput] setString:[[[self splitOutput] string] stringByAppendingString:allSplitInfo]];
        [task waitUntilExit];
        if([task terminationStatus] == 0)
        {
            [[self splitOutput] setString:[[[self splitOutput] string] stringByAppendingString:[NSString stringWithFormat:@"Task %@ completed successfully.\n\n", [[task arguments] componentsJoinedByString:@" "]]]];
        }
        else
        {
            [[self splitOutput] setString:[[[self splitOutput] string] stringByAppendingString:[NSString stringWithFormat:@"Task %@ FAILED.\n\n", [[task arguments] componentsJoinedByString:@" "]]]];
        }
    }
    else 
    {
        [[self splitOutput] setString:[[[self splitOutput] string] stringByAppendingString:[NSString stringWithFormat:@"Task %@ cancelled.\nWhy you living me baby???\n\n", [[task arguments] componentsJoinedByString:@" "]]]];
    }
    [[self splitOutput] scrollToEndOfDocument:nil];
    tasksIdx += 1;
    if(tasksIdx < [tasks count] && splitting)
    {
        [self runCurrentTask];
    }
    else
    {
        [tasks removeAllObjects];
        [taskLens removeAllObjects];
        tasks = nil;
        taskLens = nil;
        [[self splitProgIndicator] setHidden:YES];
        splitting = false;
        [[self splitInfo] setStringValue:@""];
        [[self splitStartStopBtn] setImage:[NSImage imageNamed:@"play"]];
        [[self closeSplitBtn] setEnabled:YES];
    }
}

-(void) taskReadStdOut:(NSNotification*)noti
{
    NSError *error;
    NSData* data = [[noti userInfo] objectForKey:NSFileHandleNotificationDataItem];
    if([data length])
    {
        NSString* sd = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        allSplitInfo = [allSplitInfo stringByAppendingString:sd];
        sd = nil;
        
        allSplitInfo = [allSplitInfo stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        NSString* s = @"";
        if ([allSplitInfo rangeOfString:@"\n" options:NSBackwardsSearch].location != NSNotFound) {
            s = [[allSplitInfo substringFromIndex:[allSplitInfo rangeOfString:@"\n" options:NSBackwardsSearch].location+1] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\n"]];
        }
        if([s rangeOfString:@"frame=" options:NSBackwardsSearch].location != NSNotFound)
        {
            s = [s substringFromIndex:[s rangeOfString:@"frame=" options:NSBackwardsSearch].location];
            
            NSRegularExpression* rx = [NSRegularExpression regularExpressionWithPattern:@"[0-9]{2}\\:[0-9]{2}\\:[0-9]{2}\\.{0,1}[0-9]{0,2}" options:NSRegularExpressionCaseInsensitive error:&error];
            
            runningLength = [self secsFromTimeStr:[s substringWithRange:[rx rangeOfFirstMatchInString:s options:0 range:NSMakeRange(0, [s length])]]] + oldRunLength;
            
            [[self splitProgIndicator] setDoubleValue:runningLength];
            NSLog(@"pos = %f/%f", runningLength, totalLength);
        }
        if(s != nil && s != @"")
        {
            if([s length] > 100)
            {
                s = [s substringFromIndex:[s length] - 99];
            }
            [[self splitInfo] setStringValue:s];
        }
    }
    else {
        [self taskExited];
    }
    [[noti object] readInBackgroundAndNotify];
}

-(void) runCurrentTask
{
    NSLog(@"%d: Running Task", tasksIdx);
    if(tasksIdx > 0) oldRunLength = [[taskLens objectAtIndex:tasksIdx-1] floatValue];
    else oldRunLength = runningLength;
    runningLength = 0;
    NSTask* task = (NSTask*)[tasks objectAtIndex:tasksIdx];
    [[NSNotificationCenter defaultCenter]
     addObserver:self 
     selector:@selector(taskReadStdOut:) 
     name:NSFileHandleReadCompletionNotification 
     object:[[task standardOutput] fileHandleForReading]
     ];
    [[[task standardOutput] fileHandleForReading] readInBackgroundAndNotify];
    
    [[self splitOutput] setString:[[[self splitOutput] string] stringByAppendingString:[NSString stringWithFormat:@"Running task %@...\n", [[task arguments] componentsJoinedByString:@" "]]]];
    
    [task launch];
}

- (IBAction)aboutCloseBtnClick:(id)sender {
    [NSApp endSheet:[self aboutWnd]];
    [[self aboutWnd] orderOut:self];
}

- (IBAction)prefWndShow:(id)sender {
    [NSApp beginSheet: [self prefWnd] modalForWindow: [self window] modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
}

- (IBAction)prefCloseBtnClick:(id)sender {
    outputMask = [[self outputFilenameMaskField] stringValue];
    if([[self outputDirectoryRB] selectedTag] == 1)
    {
        outputDir = @"Same as source.";
    }
    else 
    {
        outputDir = [[self outputDirectoryText] stringValue];
    }
    
    [NSApp endSheet:[self prefWnd]];
    [[self prefWnd] orderOut:self];
}

- (IBAction)removeSegBtnClick:(id)sender {
    NSInteger selIdx = [[self splitTable] selectedRow];
    if([splitDS count] > 0 && selIdx < [splitDS count])
    {
        [splitDS removeObjectAtIndex:selIdx];
        [[self splitTable] reloadData];
    }
}

- (IBAction)convertToClick:(id)sender {
    [[self convertToBtn] setEnabled:([[self convertCB] state] == NSOnState)];
}

- (IBAction)outputDirectoryBtnClick:(id)sender {
    NSOpenPanel* oDlg = [NSOpenPanel openPanel];
    [oDlg setCanChooseFiles:NO];
    [oDlg setCanChooseDirectories:YES];
    [oDlg setCanCreateDirectories:YES];
    if([oDlg runModal] == NSFileHandlingPanelOKButton)
    {
        NSString* fn = [[oDlg directoryURL] relativePath];
        [[self outputDirectoryText] setStringValue:fn];
    }
}

- (IBAction)outputDirectoryRBChange:(id)sender {
}

- (IBAction)helpClick:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://www.popmedic.com/popmsplit/#doc-banner-ref"]];
}


NSInteger qttsSort(id qtts1, id qtts2, void *context)
{
    NSMenuItem *m1 = (NSMenuItem*)qtts1;
    NSMenuItem *m2 = (NSMenuItem*)qtts2;
    QTTime qtt1 = QTTimeFromString([m1 title]);
    QTTime qtt2 = QTTimeFromString([m2 title]);
    float f1 = qtt1.timeValue;
    float f2 = qtt2.timeValue;
    if(f1<f2) return NSOrderedAscending;
    else if (f1>f2) return NSOrderedDescending;
    else return NSOrderedSame;
}
- (void)refreshSlider:(NSTimer*)theTimer
{
    [[self seekSlider] setFloatValue:(float)[[self movie] currentTime].timeValue];
    [[self infoLabel] setStringValue:[NSString stringWithFormat:@"Rate: %.0fx; At: %@; Of: %@", [self rate], QTStringFromTime([[self movie] currentTime]), QTStringFromTime([[self movie] duration])]];
}

- (void)startSliderTimer
{
    
    [self stopSliderTimer];
    [self setSlideTimer:[NSTimer timerWithTimeInterval:0.5 target:self selector:@selector(refreshSlider:) userInfo:nil repeats:YES]];
    NSRunLoop *rl = [NSRunLoop currentRunLoop];
    [rl addTimer:[self slideTimer] forMode:NSDefaultRunLoopMode];
}

- (void)stopSliderTimer
{
    if([self slideTimer] != nil)
    {
        [[self slideTimer] invalidate];
        [self setSlideTimer:nil];
    }
}

- (int)numberOfRowsInTableView:(NSTableView *)aTableView
{
    if(splitDS != nil)
    {
        return splitDS.count;
    }
    return 0;
}

- (id)tableView:(NSTableView*)aTableView 
objectValueForTableColumn:(NSTableColumn*)aTableColumn 
row:(NSInteger)rowIndex
{
    NSString *sci = (NSString*)[aTableColumn identifier];
    NSUInteger ci = (NSUInteger)[sci integerValue];
    NSArray* row = [splitDS objectAtIndex:rowIndex];
    return [row objectAtIndex:ci];
}

- (void)tableView:(NSTableView*)aTableView 
   setObjectValue:(id)anObject 
   forTableColumn:(NSTableColumn *)aTableColumn 
              row:(NSInteger)rowIndex
{
    NSString* v = (NSString*)anObject;
    if(v != nil)
    {
        NSString *sci = (NSString*)[aTableColumn identifier];
        NSUInteger ci = (NSUInteger)[sci integerValue];
        NSMutableArray* row = [splitDS objectAtIndex:rowIndex];
        [row replaceObjectAtIndex:ci withObject:v];
    }
}

-(float) secsFromTimeStr:(NSString*)str
{
    NSArray *tokens = [str componentsSeparatedByString:@":"];
    float rtn = 0;
    for(int i = 0; i < [tokens count]; i++)
    {
        rtn = 60*rtn + [[tokens objectAtIndex:i] floatValue];
    }
    return rtn;
}
@end
