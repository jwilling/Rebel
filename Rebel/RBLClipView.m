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

const CGFloat RBLClipViewDecelerationRate = 0.88;

@interface RBLClipView()
@property (nonatomic) CVDisplayLinkRef displayLink;
@property (nonatomic) BOOL animate;
@property (nonatomic) CGPoint destination;
@property (nonatomic, readonly, getter = isScrolling) BOOL scrolling;
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
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}


#pragma mark Display link

static CVReturn RBLScrollingCallback(CVDisplayLinkRef displayLink, const CVTimeStamp* now, const CVTimeStamp* outputTime, CVOptionFlags flagsIn, CVOptionFlags* flagsOut, void* displayLinkContext) {
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
		CVDisplayLinkSetOutputCallback(_displayLink, &RBLScrollingCallback, (__bridge void *)(self));
		[self updateCVDisplay];
	}
	return _displayLink;
}

- (void)updateCVDisplay {
	NSScreen *screen = self.window.screen;
	if (screen) {
		NSDictionary* screenDictionary = [[NSScreen mainScreen] deviceDescription];
		NSNumber *screenID = [screenDictionary objectForKey:@"NSScreenNumber"];
		CGDirectDisplayID displayID = [screenID unsignedIntValue];
		CVDisplayLinkSetCurrentCGDisplay(_displayLink, displayID);
	} else {
		CVDisplayLinkSetCurrentCGDisplay(_displayLink, kCGDirectMainDisplay);
	}
}

#pragma mark Scrolling

- (void)scrollToPoint:(NSPoint)newOrigin {
	if (self.animate && (self.window.currentEvent.type != NSScrollWheel)) {
		self.destination = newOrigin;
		[self beginScrolling];
	} else {
		[self endScrolling];
		[super scrollToPoint:newOrigin];
	}
}

- (BOOL)scrollRectToVisible:(NSRect)aRect animated:(BOOL)animated {
	self.animate = animated;
	return [super scrollRectToVisible:aRect];
}

- (void)beginScrolling {
	if (self.isScrolling) {
		return;
	}
	
	CVDisplayLinkStart(self.displayLink);
}

- (void)endScrolling {
	if (!self.isScrolling)
		return;
	
	CVDisplayLinkStop(self.displayLink);
	self.animate = NO;
}

- (BOOL)isScrolling {
	return CVDisplayLinkIsRunning(self.displayLink);
}

- (CVReturn)updateOrigin {
	if(self.window == nil) {
		[self endScrolling];
		return kCVReturnError;
	}
	
	CGPoint o = self.bounds.origin;
	CGPoint lastOrigin = o;
	o.x = o.x * RBLClipViewDecelerationRate + self.destination.x * (1 - RBLClipViewDecelerationRate);
	o.y = o.y * RBLClipViewDecelerationRate + self.destination.y * (1 - RBLClipViewDecelerationRate);
	
	[self setBoundsOrigin:o];
	
	if((fabs(o.x - lastOrigin.x) < 0.1) && (fabs(o.y - lastOrigin.y) < 0.1)) {
		[self endScrolling];
		[self setBoundsOrigin:self.destination];
		[(NSScrollView *)self.superview flashScrollers];
	}
	
	return kCVReturnSuccess;
}

@end
