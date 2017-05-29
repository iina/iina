#import "NSObject+SPInvocationGrabbing.h"
#import <execinfo.h>

#pragma mark Invocation grabbing
@interface SPInvocationGrabber ()
@property (readwrite, retain, nonatomic) id object;
@property (readwrite, retain, nonatomic) NSInvocation *invocation;

@end

@implementation SPInvocationGrabber
- (id)initWithObject:(id)obj;
{
	return [self initWithObject:obj stacktraceSaving:YES];
}

-(id)initWithObject:(id)obj stacktraceSaving:(BOOL)saveStack;
{
	self.object = obj;

	if(saveStack)
		[self saveBacktrace];

	return self;
}
-(void)dealloc;
{
	free(frameStrings);
	self.object = nil;
	self.invocation = nil;
	[super dealloc];
}
@synthesize invocation = _invocation, object = _object;

@synthesize backgroundAfterForward, onMainAfterForward, waitUntilDone;
- (void)runInBackground;
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	@try {
		[self invoke];
	}
	@finally {
		[pool drain];
	}
}


- (void)forwardInvocation:(NSInvocation *)anInvocation {
	[anInvocation retainArguments];
	anInvocation.target = _object;
	self.invocation = anInvocation;
	
	if(backgroundAfterForward)
		[NSThread detachNewThreadSelector:@selector(runInBackground) toTarget:self withObject:nil];
	else if(onMainAfterForward)
        [self performSelectorOnMainThread:@selector(invoke) withObject:nil waitUntilDone:waitUntilDone];
}
- (NSMethodSignature *)methodSignatureForSelector:(SEL)inSelector {
	NSMethodSignature *signature = [super methodSignatureForSelector:inSelector];
	if (signature == NULL)
		signature = [_object methodSignatureForSelector:inSelector];
    
	return signature;
}

- (void)invoke;
{

	@try {
		[_invocation invoke];
	}
	@catch (NSException * e) {
		NSLog(@"SPInvocationGrabber's target raised %@:\n\t%@\nInvocation was originally scheduled at:", e.name, e);
		[self printBacktrace];
		printf("\n");
		[e raise];
	}

	self.invocation = nil;
	self.object = nil;
}

-(void)saveBacktrace;
{
  void *backtraceFrames[128];
  frameCount = backtrace(&backtraceFrames[0], 128);
  frameStrings = backtrace_symbols(&backtraceFrames[0], frameCount);
}
-(void)printBacktrace;
{
	for(int x = 3; x < frameCount; x++) {
		if(frameStrings[x] == NULL) { break; }
		printf("%s\n", frameStrings[x]);
	}
}
@end

@implementation NSObject (SPInvocationGrabbing)
-(id)grab;
{
	return [[[SPInvocationGrabber alloc] initWithObject:self] autorelease];
}
-(id)invokeAfter:(NSTimeInterval)delta;
{
	id grabber = [self grab];
	[NSTimer scheduledTimerWithTimeInterval:delta target:grabber selector:@selector(invoke) userInfo:nil repeats:NO];
	return grabber;
}
- (id)nextRunloop;
{
	return [self invokeAfter:0];
}
-(id)inBackground;
{
    SPInvocationGrabber *grabber = [self grab];
	grabber.backgroundAfterForward = YES;
	return grabber;
}
-(id)onMainAsync:(BOOL)async;
{
    SPInvocationGrabber *grabber = [self grab];
	grabber.onMainAfterForward = YES;
    grabber.waitUntilDone = !async;
	return grabber;
}

@end
