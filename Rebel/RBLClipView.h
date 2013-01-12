//
//  RBLClipView.h
//  Rebel
//
//  Created by Justin Spahr-Summers on 2012-09-14.
//  Copyright (c) 2012 GitHub. All rights reserved.
//  Update with smooth scrolling by Jonathan Willing, with logic from TwUI.
//

#import <QuartzCore/QuartzCore.h>

// A faster NSClipView based on CAScrollLayer. Scrolling not of a touch device
// will automatically have a deceleration applied to it.
//
// This view should be set as the scroll view's contentView as soon as possible
// after the scroll view is initialized. For some reason, scroll bars will
// disappear on 10.7 (but not 10.8) unless hasHorizontalScroller and
// hasVerticalScroller are set _after_ the contentView.
@interface RBLClipView : NSClipView

// The backing layer for this view.
@property (nonatomic, strong) CAScrollLayer *layer;

// Whether the content in this view is opaque.
//
// Defaults to NO.
@property (nonatomic, getter = isOpaque) BOOL opaque;

// Calls -scrollRectToVisible:, optionally animated.
- (BOOL)scrollRectToVisible:(CGRect)rect animated:(BOOL)animated;

@end
