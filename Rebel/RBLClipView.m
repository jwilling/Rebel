//
//  RBLClipView.m
//  Rebel
//
//  Created by Justin Spahr-Summers on 2012-09-14.
//  Copyright (c) 2012 GitHub. All rights reserved.
//  Update with smooth scrolling by Jonathan Willing, with logic from TwUI.
//

#import "RBLClipView.h"
#import "NSColor+RBLCGColorAdditions.h"

// The deceleration constant used for the ease-out curve in the animation.
static const CGFloat RBLClipViewDecelerationRate = 0.88;

@interface RBLClipView ()
// Used to drive the animation through repeated callbacks.
// A display link is used instead of a timer so that we don't get dropped frames and tearing.
@property (nonatomic, assign) CVDisplayLinkRef displayLink;

// Used to determine whether to animate in `scrollToPoint:`.
@property (nonatomic, assign) BOOL shouldAnimateOriginChange;

// Used when animating with the display link as the final origin for the animation.
@property (nonatomic, assign) CGPoint destinationOrigin;

// Return value is whether the display link is currently animating a scroll.
@property (nonatomic, readonly) BOOL animatingScroll;
@end

@implementation RBLClipView

#pragma mark Properties

@dynamic layer;

- (NSColor *)backgroundColor {
	return [NSColor rbl_colorWithCGColor:self.layer.backgroundColor];
}

- (void)setBackgroundColor:(NSColor *)color {
	self.layer.backgroundColor = color.rbl_CGColor;
}

- (BOOL)isOpaque {
	return self.layer.opaque;
}

- (void)setOpaque:(BOOL)opaque {
	self.layer.opaque = opaque;
}

#pragma mark Lifecycle

- (id)initWithFrame:(NSRect)frame {
	self = [super initWithFrame:frame];
	if (self == nil) return nil;
	
	self.layer = [CAScrollLayer layer];
	self.wantsLayer = YES;
	
	self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawNever;
	
	// Matches default NSClipView settings.
	self.backgroundColor = NSColor.clearColor;
	self.opaque = NO;
	
	return self;
}

- (void)dealloc {
	CVDisplayLinkRelease(_displayLink);
	[NSNotificationCenter.defaultCenter removeObserver:self];
}

#pragma mark View Heirarchy

- (void)viewWillMoveToWindow:(NSWindow *)newWindow {
	if (self.window != nil) {
		[NSNotificationCenter.defaultCenter removeObserver:self name:NSWindowDidChangeScreenNotification object:self.window];
	}
	
	[super viewWillMoveToWindow:newWindow];
	
	if (newWindow != nil) {
		[NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidChangeScreenNotification object:newWindow queue:nil usingBlock:^(NSNotification *note) {
			[self updateCVDisplay];
		}];
	}
}

#pragma mark Display link

static CVReturn RBLScrollingCallback(CVDisplayLinkRef displayLink, const CVTimeStamp *now, const CVTimeStamp *outputTime, CVOptionFlags flagsIn, CVOptionFlags *flagsOut, void *displayLinkContext) {
	__block CVReturn status;
	@autoreleasepool {
		RBLClipView *clipView = (__bridge id)displayLinkContext;
		dispatch_async(dispatch_get_main_queue(), ^{
			status = [clipView updateOrigin];
		});
	}
	
	return status;
}

- (CVDisplayLinkRef)displayLink {
	if (_displayLink == NULL) {
		CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
		CVDisplayLinkSetOutputCallback(_displayLink, &RBLScrollingCallback, (__bridge void *)self);
		[self updateCVDisplay];
	}
	
	return _displayLink;
}

- (void)updateCVDisplay {
	NSScreen *screen = self.window.screen;
	if (screen == nil) {
		NSDictionary *screenDictionary = [NSScreen.mainScreen deviceDescription];
		NSNumber *screenID = screenDictionary[@"NSScreenNumber"];
		CGDirectDisplayID displayID = screenID.unsignedIntValue;
		CVDisplayLinkSetCurrentCGDisplay(_displayLink, displayID);
	} else {
		CVDisplayLinkSetCurrentCGDisplay(_displayLink, kCGDirectMainDisplay);
	}
}

#pragma mark Scrolling

- (void)scrollToPoint:(NSPoint)newOrigin {
	NSEventType type = self.window.currentEvent.type;
	
	if (self.shouldAnimateOriginChange && type != NSScrollWheel) {
		// Occurs when `-scrollRectToVisible:animated:` has been called with an animated flag.
		self.destinationOrigin = newOrigin;
		[self beginScrolling];
	} else if (type == NSKeyDown || type == NSKeyUp || type == NSFlagsChanged) {
		// Occurs if a keyboard press has triggered a origin change. In this case we
		// want to explicitly enable and begin the animation.
		self.shouldAnimateOriginChange = YES;
		self.destinationOrigin = newOrigin;
		[self beginScrolling];
	} else {
		// For all other cases, we do not animate. We call `endScrolling` in case a previous animation
		// is still in progress, in which case we want to stop the display link from making further
		// callbacks, which would interfere with normal scrolling.
		[self endScrolling];
		[super scrollToPoint:newOrigin];
	}
}

- (BOOL)scrollRectToVisible:(NSRect)aRect animated:(BOOL)animated {
	self.shouldAnimateOriginChange = animated;
	return [super scrollRectToVisible:aRect];
}

- (void)beginScrolling {
	if (self.animatingScroll) {
		return;
	}
	
	CVDisplayLinkStart(self.displayLink);
}

- (void)endScrolling {
	if (!self.animatingScroll) {
		return;
	}
	
	CVDisplayLinkStop(self.displayLink);
	self.shouldAnimateOriginChange = NO;
}

- (BOOL)animatingScroll {
	return CVDisplayLinkIsRunning(self.displayLink);
}

- (CVReturn)updateOrigin {
	if (self.window == nil) {
		[self endScrolling];
		return kCVReturnError;
	}
	
	CGPoint o = self.bounds.origin;
	CGPoint lastOrigin = o;
	
	// Calculate the next origin on a basic ease-out curve.
	o.x = o.x * RBLClipViewDecelerationRate + self.destinationOrigin.x * (1 - RBLClipViewDecelerationRate);
	o.y = o.y * RBLClipViewDecelerationRate + self.destinationOrigin.y * (1 - RBLClipViewDecelerationRate);
	
	self.boundsOrigin = o;
	
	if (fabs(o.x - lastOrigin.x) < 0.1 && fabs(o.y - lastOrigin.y) < 0.1) {
		[self endScrolling];
		self.boundsOrigin = self.destinationOrigin;
		[self.enclosingScrollView flashScrollers];
	}
	
	return kCVReturnSuccess;
}

@end
