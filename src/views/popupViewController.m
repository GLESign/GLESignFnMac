

#import "./popupViewController.h"
#import "../FnOverlayWindow.h"
#import "../globals.h"
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <SafariServices/SafariServices.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>

static UIVisualEffectView *FnMakePill(CGRect frame) {
  UIBlurEffect *blur = [UIBlurEffect
      effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
  UIVisualEffectView *pill = [[UIVisualEffectView alloc] initWithEffect:blur];
  pill.frame = frame;
  pill.layer.cornerRadius = frame.size.height / 2.0;
  pill.layer.masksToBounds = YES;

  pill.layer.borderWidth = 0.5;
  pill.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.12].CGColor;
  return pill;
}

static void FnAnimatePress(UIView *v, BOOL down) {
  CGFloat scale = down ? 0.88 : 1.0;
  [UIView animateWithDuration:down ? 0.10 : 0.22
                        delay:0
       usingSpringWithDamping:down ? 1.0 : 0.55
        initialSpringVelocity:down ? 0 : 0.6
                      options:UIViewAnimationOptionBeginFromCurrentState
                   animations:^{
                     v.transform = CGAffineTransformMakeScale(scale, scale);
                   }
                   completion:nil];
}

@interface FnCustomControlsView : UIView
@property(nonatomic, weak) AVPlayer *player;
@property(nonatomic, strong) UIVisualEffectView *barPill;
@property(nonatomic, strong) UIButton *playPauseButton;
@property(nonatomic, strong) UIButton *skipBackButton;
@property(nonatomic, strong) UIButton *skipForwardButton;
@property(nonatomic, strong) UISlider *scrubber;
@property(nonatomic, strong) UILabel *timeLabel;
@property(nonatomic, strong) UILabel *remainLabel;
@property(nonatomic, strong) id timeObserver;
@property(nonatomic, assign) BOOL scrubbing;
@property(nonatomic, assign) BOOL videoDidFinish;
@property(nonatomic, assign) NSInteger lastDisplayedSecond;
- (void)attachToPlayer:(AVPlayer *)player;
- (void)detachFromPlayer;
- (void)syncPlayPauseButton;
- (void)togglePlayPause;
@end

@implementation FnCustomControlsView

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (!self)
    return self;
  self.backgroundColor = [UIColor clearColor];

  self.barPill = FnMakePill(self.bounds);
  self.barPill.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [self addSubview:self.barPill];

  UIImageSymbolConfiguration *skipCfg = [UIImageSymbolConfiguration
      configurationWithPointSize:15
                          weight:UIImageSymbolWeightMedium];
  UIImageSymbolConfiguration *playCfg = [UIImageSymbolConfiguration
      configurationWithPointSize:18
                          weight:UIImageSymbolWeightMedium];

  self.skipBackButton = [UIButton buttonWithType:UIButtonTypeSystem];
  [self.skipBackButton setImage:[UIImage systemImageNamed:@"gobackward.5"
                                        withConfiguration:skipCfg]
                       forState:UIControlStateNormal];
  self.skipBackButton.tintColor = [UIColor whiteColor];
  [self.skipBackButton addTarget:self
                          action:@selector(skipBack)
                forControlEvents:UIControlEventTouchUpInside];
  [self.skipBackButton
             addTarget:self
                action:@selector(btnPressDown:)
      forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
  [self.skipBackButton
             addTarget:self
                action:@selector(btnPressUp:)
      forControlEvents:UIControlEventTouchUpInside |
                       UIControlEventTouchUpOutside |
                       UIControlEventTouchCancel | UIControlEventTouchDragExit];
  [self.barPill.contentView addSubview:self.skipBackButton];

  self.playPauseButton = [UIButton buttonWithType:UIButtonTypeSystem];
  [self.playPauseButton setImage:[UIImage systemImageNamed:@"play.fill"
                                         withConfiguration:playCfg]
                        forState:UIControlStateNormal];
  self.playPauseButton.tintColor = [UIColor whiteColor];
  [self.playPauseButton addTarget:self
                           action:@selector(togglePlayPause)
                 forControlEvents:UIControlEventTouchUpInside];
  [self.playPauseButton
             addTarget:self
                action:@selector(btnPressDown:)
      forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
  [self.playPauseButton
             addTarget:self
                action:@selector(btnPressUp:)
      forControlEvents:UIControlEventTouchUpInside |
                       UIControlEventTouchUpOutside |
                       UIControlEventTouchCancel | UIControlEventTouchDragExit];
  [self.barPill.contentView addSubview:self.playPauseButton];

  self.skipForwardButton = [UIButton buttonWithType:UIButtonTypeSystem];
  [self.skipForwardButton setImage:[UIImage systemImageNamed:@"goforward.5"
                                           withConfiguration:skipCfg]
                          forState:UIControlStateNormal];
  self.skipForwardButton.tintColor = [UIColor whiteColor];
  [self.skipForwardButton addTarget:self
                             action:@selector(skipForward)
                   forControlEvents:UIControlEventTouchUpInside];
  [self.skipForwardButton
             addTarget:self
                action:@selector(btnPressDown:)
      forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
  [self.skipForwardButton
             addTarget:self
                action:@selector(btnPressUp:)
      forControlEvents:UIControlEventTouchUpInside |
                       UIControlEventTouchUpOutside |
                       UIControlEventTouchCancel | UIControlEventTouchDragExit];
  [self.barPill.contentView addSubview:self.skipForwardButton];

  UIView *div = [[UIView alloc] init];
  div.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.15];
  div.tag = 77;
  [self.barPill.contentView addSubview:div];

  self.timeLabel = [[UILabel alloc] init];
  self.timeLabel.text = @"0:00";
  self.timeLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.75];
  self.timeLabel.font =
      [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightMedium];
  self.timeLabel.textAlignment = NSTextAlignmentRight;
  [self.barPill.contentView addSubview:self.timeLabel];

  self.scrubber = [[UISlider alloc] init];
  self.scrubber.minimumValue = 0.0;
  self.scrubber.maximumValue = 1.0;
  self.scrubber.value = 0.0;
  self.scrubber.minimumTrackTintColor = [UIColor colorWithRed:0.3
                                                        green:0.65
                                                         blue:1.0
                                                        alpha:1.0];
  self.scrubber.maximumTrackTintColor = [UIColor colorWithWhite:1.0 alpha:0.22];
  self.scrubber.thumbTintColor = [UIColor whiteColor];
  UITapGestureRecognizer *scrubTap = [[UITapGestureRecognizer alloc]
      initWithTarget:self
              action:@selector(handleScrubberTap:)];
  [self.scrubber addGestureRecognizer:scrubTap];
  [self.scrubber addTarget:self
                    action:@selector(scrubberBegan:)
          forControlEvents:UIControlEventTouchDown];
  [self.scrubber addTarget:self
                    action:@selector(scrubberChanged:)
          forControlEvents:UIControlEventValueChanged];
  [self.scrubber addTarget:self
                    action:@selector(scrubberEnded:)
          forControlEvents:UIControlEventTouchUpInside |
                           UIControlEventTouchUpOutside];
  [self.barPill.contentView addSubview:self.scrubber];

  self.remainLabel = [[UILabel alloc] init];
  self.remainLabel.text = @"-0:00";
  self.remainLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.45];
  self.remainLabel.font =
      [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightMedium];
  self.remainLabel.textAlignment = NSTextAlignmentLeft;
  [self.barPill.contentView addSubview:self.remainLabel];

  return self;
}

- (void)layoutSubviews {
  [super layoutSubviews];
  CGFloat W = self.bounds.size.width;
  CGFloat H = self.bounds.size.height;
  CGFloat mid = H / 2.0;
  CGFloat pad = 16.0;

  CGFloat btnH = H - 10;
  CGFloat skipW = 38.0;
  CGFloat ppW = 44.0;
  CGFloat gap = 4.0;

  self.skipBackButton.frame = CGRectMake(pad, mid - btnH / 2, skipW, btnH);
  self.playPauseButton.frame =
      CGRectMake(pad + skipW + gap, mid - btnH / 2, ppW, btnH);
  self.skipForwardButton.frame =
      CGRectMake(pad + skipW + gap + ppW + gap, mid - btnH / 2, skipW, btnH);

  CGFloat transportRight = pad + skipW + gap + ppW + gap + skipW;

  UIView *div = [self.barPill.contentView viewWithTag:77];
  div.frame = CGRectMake(transportRight + 10, 10, 0.5, H - 20);

  CGFloat timW = 40.0;
  CGFloat remW = 46.0;
  CGFloat scrubX = transportRight + 24 + timW + 6;
  CGFloat scrubW = W - scrubX - remW - 10 - pad;

  self.timeLabel.frame = CGRectMake(transportRight + 24, mid - 10, timW, 20);
  self.scrubber.frame = CGRectMake(scrubX, mid - 10, scrubW, 20);
  self.remainLabel.frame = CGRectMake(scrubX + scrubW + 6, mid - 10, remW, 20);
}

- (void)handleScrubberTap:(UITapGestureRecognizer *)tap {
  CGPoint pt = [tap locationInView:self.scrubber];
  CGFloat pct = MAX(0.0, MIN(1.0, pt.x / self.scrubber.bounds.size.width));
  [self.scrubber setValue:pct animated:NO];
  [self seekToFraction:pct];
}

- (void)seekToFraction:(float)pct {
  CMTime dur = self.player.currentItem.duration;
  if (!CMTIME_IS_NUMERIC(dur))
    return;
  CMTime target =
      CMTimeMakeWithSeconds(pct * CMTimeGetSeconds(dur), NSEC_PER_SEC);
  [self.player seekToTime:target
          toleranceBefore:kCMTimeZero
           toleranceAfter:kCMTimeZero];
}

- (void)attachToPlayer:(AVPlayer *)player {
  self.player = player;
  self.videoDidFinish = NO;
  __weak typeof(self) weak = self;
  CMTime interval = CMTimeMakeWithSeconds(0.25, NSEC_PER_SEC);
  self.timeObserver =
      [player addPeriodicTimeObserverForInterval:interval
                                           queue:dispatch_get_main_queue()
                                      usingBlock:^(CMTime time) {
                                        [weak tickTime:time];
                                      }];
  [player.currentItem addObserver:self
                       forKeyPath:@"status"
                          options:NSKeyValueObservingOptionNew
                          context:nil];
  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(playerItemDidReachEnd:)
             name:AVPlayerItemDidPlayToEndTimeNotification
           object:player.currentItem];
}

- (void)playerItemDidReachEnd:(NSNotification *)notification {
  self.videoDidFinish = YES;
  [self syncPlayPauseButton];
}

- (void)detachFromPlayer {
  if (self.timeObserver && self.player)
    [self.player removeTimeObserver:self.timeObserver];
  self.timeObserver = nil;
  @try {
    [self.player.currentItem removeObserver:self forKeyPath:@"status"];
  } @catch (NSException *e) {
  }
  [[NSNotificationCenter defaultCenter]
      removeObserver:self
                name:AVPlayerItemDidPlayToEndTimeNotification
              object:self.player.currentItem];
  self.player = nil;
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
  if ([keyPath isEqualToString:@"status"] &&
      self.player.currentItem.status == AVPlayerItemStatusReadyToPlay) {
    dispatch_async(dispatch_get_main_queue(), ^{
      CMTime dur = self.player.currentItem.duration;
      self.remainLabel.text = [NSString
          stringWithFormat:@"-%@", [self formatTime:CMTimeGetSeconds(dur)]];
      self.scrubber.value = 0.0;
    });
  }
}

- (void)tickTime:(CMTime)time {
  NSTimeInterval cur = CMTimeGetSeconds(time);

  NSInteger curSec = (NSInteger)cur;
  if (curSec != self.lastDisplayedSecond) {
    self.lastDisplayedSecond = curSec;
    self.timeLabel.text = [self formatTime:cur];
    CMTime dur = self.player.currentItem.duration;
    if (!self.scrubbing && CMTIME_IS_NUMERIC(dur) &&
        CMTimeGetSeconds(dur) > 0) {
      NSTimeInterval rem = CMTimeGetSeconds(dur) - cur;
      self.remainLabel.text =
          [NSString stringWithFormat:@"-%@", [self formatTime:rem]];
    }
  }
  if (!self.scrubbing) {
    CMTime dur = self.player.currentItem.duration;
    if (CMTIME_IS_NUMERIC(dur) && CMTimeGetSeconds(dur) > 0) {
      self.scrubber.value = (float)(cur / CMTimeGetSeconds(dur));
    }
  }
  [self syncPlayPauseButton];
}

- (NSString *)formatTime:(NSTimeInterval)s {
  if (isnan(s) || isinf(s) || s < 0)
    return @"0:00";
  NSInteger total = (NSInteger)s;
  NSInteger sec = total % 60;
  NSInteger min = (total / 60) % 60;
  NSInteger hr = total / 3600;
  if (hr > 0)
    return [NSString
        stringWithFormat:@"%ld:%02ld:%02ld", (long)hr, (long)min, (long)sec];
  return [NSString stringWithFormat:@"%ld:%02ld", (long)min, (long)sec];
}

- (void)syncPlayPauseButton {
  UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration
      configurationWithPointSize:18
                          weight:UIImageSymbolWeightMedium];
  NSString *name;
  if (self.videoDidFinish) {
    name = @"arrow.counterclockwise";
  } else {
    name = (self.player.rate > 0) ? @"pause.fill" : @"play.fill";
  }
  [self.playPauseButton setImage:[UIImage systemImageNamed:name
                                         withConfiguration:cfg]
                        forState:UIControlStateNormal];
}

- (void)togglePlayPause {
  if (self.videoDidFinish) {

    self.videoDidFinish = NO;
    [self.player seekToTime:kCMTimeZero
            toleranceBefore:kCMTimeZero
             toleranceAfter:kCMTimeZero
          completionHandler:^(BOOL finished) {
            if (finished)
              [self.player play];
          }];
  } else if (self.player.rate > 0) {
    [self.player pause];
  } else {
    [self.player play];
  }
  [self syncPlayPauseButton];
}

- (void)skipBack {
  CMTime t = CMTimeSubtract(self.player.currentTime,
                            CMTimeMakeWithSeconds(5, NSEC_PER_SEC));
  if (CMTimeGetSeconds(t) < 0)
    t = kCMTimeZero;
  [self.player seekToTime:t
          toleranceBefore:kCMTimeZero
           toleranceAfter:kCMTimeZero];
}

- (void)skipForward {
  CMTime t = CMTimeAdd(self.player.currentTime,
                       CMTimeMakeWithSeconds(5, NSEC_PER_SEC));
  CMTime dur = self.player.currentItem.duration;
  if (CMTIME_IS_NUMERIC(dur) && CMTimeCompare(t, dur) > 0)
    t = dur;
  [self.player seekToTime:t
          toleranceBefore:kCMTimeZero
           toleranceAfter:kCMTimeZero];
}

- (void)scrubberBegan:(UISlider *)s {
  self.scrubbing = YES;

  UIView *parent = self.superview;
  if ([parent respondsToSelector:@selector(cancelHideTimer)]) {
    [parent performSelector:@selector(cancelHideTimer)];
  }
}
- (void)scrubberChanged:(UISlider *)s {
  CMTime dur = self.player.currentItem.duration;
  if (!CMTIME_IS_NUMERIC(dur))
    return;
  NSTimeInterval totalSecs = CMTimeGetSeconds(dur);
  NSTimeInterval cur = s.value * totalSecs;
  NSTimeInterval rem = totalSecs - cur;
  self.timeLabel.text = [self formatTime:cur];
  self.remainLabel.text =
      [NSString stringWithFormat:@"-%@", [self formatTime:rem]];

  CMTime target = CMTimeMakeWithSeconds(cur, NSEC_PER_SEC);
  CMTime tol = CMTimeMakeWithSeconds(0.1, NSEC_PER_SEC);
  [self.player seekToTime:target toleranceBefore:tol toleranceAfter:tol];
}
- (void)scrubberEnded:(UISlider *)s {

  [self seekToFraction:s.value];
  self.scrubbing = NO;

  UIView *parent = self.superview;
  if ([parent respondsToSelector:@selector(scheduleHide)]) {
    [parent performSelector:@selector(scheduleHide)];
  }
}

- (void)btnPressDown:(UIButton *)btn {
  FnAnimatePress(btn, YES);
}
- (void)btnPressUp:(UIButton *)btn {
  FnAnimatePress(btn, NO);
}

@end

@interface FnCustomPlayerView : UIView
@property(nonatomic, strong) AVPlayer *player;
@property(nonatomic, strong) AVPlayerLayer *playerLayer;
@property(nonatomic, strong) FnCustomControlsView *controlsBar;
@property(nonatomic, strong) UIVisualEffectView *closeButton;
@property(nonatomic, strong) NSTimer *hideTimer;
@property(nonatomic, assign) BOOL controlsVisible;
- (instancetype)initWithPlayer:(AVPlayer *)player
                 dismissTarget:(id)target
                        action:(SEL)action;
- (void)showControlsAnimated:(BOOL)animated;
- (void)hideControlsAnimated:(BOOL)animated;
- (void)scheduleHide;
@end

@implementation FnCustomPlayerView

- (instancetype)initWithPlayer:(AVPlayer *)player
                 dismissTarget:(id)target
                        action:(SEL)action {
  self = [super initWithFrame:CGRectZero];
  if (!self)
    return self;
  self.backgroundColor = [UIColor blackColor];
  self.player = player;

  self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:player];
  self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;

  self.playerLayer.contentsGravity = kCAGravityResizeAspect;
  self.playerLayer.drawsAsynchronously = YES;
  [self.layer addSublayer:self.playerLayer];

  CGFloat barH = 44.0;
  self.controlsBar =
      [[FnCustomControlsView alloc] initWithFrame:CGRectMake(0, 0, 100, barH)];
  self.controlsBar.layer.shadowColor = [UIColor blackColor].CGColor;
  self.controlsBar.layer.shadowOpacity = 0.35;
  self.controlsBar.layer.shadowRadius = 12.0;
  self.controlsBar.layer.shadowOffset = CGSizeMake(0, 4);
  [self addSubview:self.controlsBar];
  [self.controlsBar attachToPlayer:player];

  CGFloat closeS = 44.0;
  self.closeButton = FnMakePill(CGRectMake(20, 16, closeS, closeS));
  self.closeButton.layer.shadowColor = [UIColor blackColor].CGColor;
  self.closeButton.layer.shadowOpacity = 0.3;
  self.closeButton.layer.shadowRadius = 6.0;
  self.closeButton.layer.shadowOffset = CGSizeMake(0, 2);

  UIImageSymbolConfiguration *closeCfg = [UIImageSymbolConfiguration
      configurationWithPointSize:16
                          weight:UIImageSymbolWeightSemibold];
  UIImageView *xIcon =
      [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"xmark"
                                                 withConfiguration:closeCfg]];
  xIcon.tintColor = [UIColor colorWithWhite:1.0 alpha:0.85];
  xIcon.contentMode = UIViewContentModeCenter;
  xIcon.frame = self.closeButton.contentView.bounds;
  xIcon.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  xIcon.tag = 998;
  [self.closeButton.contentView addSubview:xIcon];

  UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
  closeBtn.frame = self.closeButton.contentView.bounds;
  closeBtn.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [closeBtn addTarget:target
                action:action
      forControlEvents:UIControlEventTouchUpInside];
  [closeBtn addTarget:self
                action:@selector(closePressDown)
      forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
  [closeBtn addTarget:self
                action:@selector(closePressUp)
      forControlEvents:UIControlEventTouchUpInside |
                       UIControlEventTouchUpOutside |
                       UIControlEventTouchCancel | UIControlEventTouchDragExit];
  [self.closeButton.contentView addSubview:closeBtn];
  [self addSubview:self.closeButton];

  UITapGestureRecognizer *videoTap = [[UITapGestureRecognizer alloc]
      initWithTarget:self
              action:@selector(handleVideoTap:)];
  videoTap.cancelsTouchesInView = NO;
  [self addGestureRecognizer:videoTap];

  if (@available(iOS 13.4, *)) {
    UIHoverGestureRecognizer *hover = [[UIHoverGestureRecognizer alloc]
        initWithTarget:self
                action:@selector(handleHover:)];
    [self addGestureRecognizer:hover];
  }

  self.controlsVisible = YES;
  self.controlsBar.alpha = 1.0;
  self.closeButton.alpha = 1.0;
  [self scheduleHide];

  return self;
}

- (void)closePressDown {
  UIView *icon = [self.closeButton viewWithTag:998];
  [UIView animateWithDuration:0.10
                        delay:0
       usingSpringWithDamping:1.0
        initialSpringVelocity:0
                      options:UIViewAnimationOptionBeginFromCurrentState
                   animations:^{
                     icon.transform = CGAffineTransformMakeScale(0.78, 0.78);
                     icon.alpha = 0.4;
                   }
                   completion:nil];
}
- (void)closePressUp {
  UIView *icon = [self.closeButton viewWithTag:998];
  [UIView animateWithDuration:0.22
                        delay:0
       usingSpringWithDamping:0.55
        initialSpringVelocity:0.6
                      options:UIViewAnimationOptionBeginFromCurrentState
                   animations:^{
                     icon.transform = CGAffineTransformIdentity;
                     icon.alpha = 0.85;
                   }
                   completion:nil];
}

- (void)layoutSubviews {
  [super layoutSubviews];
  self.playerLayer.frame = self.bounds;

  CGFloat inset = 20.0;
  CGFloat barH = 44.0;
  CGFloat closeS = 44.0;

  CGFloat barY = self.bounds.size.height - barH - 16.0;
  self.controlsBar.frame =
      CGRectMake(inset, barY, self.bounds.size.width - inset * 2, barH);
  self.controlsBar.layer.shadowPath =
      [UIBezierPath bezierPathWithRoundedRect:self.controlsBar.bounds
                                 cornerRadius:barH / 2.0]
          .CGPath;

  self.closeButton.frame = CGRectMake(inset, 16.0, closeS, closeS);
  self.closeButton.layer.cornerRadius = closeS / 2.0;
}

- (void)handleHover:(UIHoverGestureRecognizer *)hover {
  if (@available(iOS 13.4, *)) {
    UIGestureRecognizerState s = hover.state;
    if (s == UIGestureRecognizerStateBegan ||
        s == UIGestureRecognizerStateChanged) {
      if (!self.controlsVisible)
        [self showControlsAnimated:YES];
      [self scheduleHide];
    } else if (s == UIGestureRecognizerStateEnded ||
               s == UIGestureRecognizerStateCancelled) {
      [self.hideTimer invalidate];
      self.hideTimer = nil;
      if (self.controlsVisible)
        [self hideControlsAnimated:YES];
    }
  }
}

- (void)handleVideoTap:(UITapGestureRecognizer *)tap {
  CGPoint pt = [tap locationInView:self];
  if (CGRectContainsPoint(self.controlsBar.frame, pt))
    return;
  [self.controlsBar togglePlayPause];
  [self showControlsAnimated:YES];
  [self scheduleHide];
}

- (void)showControlsAnimated:(BOOL)animated {
  self.controlsVisible = YES;

  [self.controlsBar.layer removeAnimationForKey:@"fnOpacity"];
  [self.closeButton.layer removeAnimationForKey:@"fnOpacity"];
  if (animated) {

    CGFloat fromAlpha = self.controlsBar.layer.presentationLayer
                            ? self.controlsBar.layer.presentationLayer.opacity
                            : 0.0;
    CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"opacity"];
    a.fromValue = @(fromAlpha);
    a.toValue = @1.0;
    a.duration = 0.20;
    a.timingFunction =
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    a.removedOnCompletion = YES;
    [self.controlsBar.layer addAnimation:a forKey:@"fnOpacity"];
    [self.closeButton.layer addAnimation:a forKey:@"fnOpacity"];
  }
  self.controlsBar.layer.opacity = 1.0;
  self.closeButton.layer.opacity = 1.0;
  self.controlsBar.alpha = 1.0;
  self.closeButton.alpha = 1.0;
}

- (void)hideControlsAnimated:(BOOL)animated {
  self.controlsVisible = NO;
  [self.hideTimer invalidate];
  self.hideTimer = nil;

  [self.controlsBar.layer removeAnimationForKey:@"fnOpacity"];
  [self.closeButton.layer removeAnimationForKey:@"fnOpacity"];
  if (animated) {

    CGFloat fromAlpha = self.controlsBar.layer.presentationLayer
                            ? self.controlsBar.layer.presentationLayer.opacity
                            : 1.0;
    CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"opacity"];
    a.fromValue = @(fromAlpha);
    a.toValue = @0.0;
    a.duration = 0.28;
    a.timingFunction =
        [CAMediaTimingFunction functionWithControlPoints:0.4:0.0:0.6:1.0];
    a.removedOnCompletion = YES;
    [self.controlsBar.layer addAnimation:a forKey:@"fnOpacity"];
    [self.closeButton.layer addAnimation:a forKey:@"fnOpacity"];
  }
  self.controlsBar.layer.opacity = 0.0;
  self.closeButton.layer.opacity = 0.0;
  self.controlsBar.alpha = 0.0;
  self.closeButton.alpha = 0.0;
}

- (void)cancelHideTimer {
  [self.hideTimer invalidate];
  self.hideTimer = nil;
}

- (void)scheduleHide {
  [self.hideTimer invalidate];
  self.hideTimer = [NSTimer scheduledTimerWithTimeInterval:1.5
                                                    target:self
                                                  selector:@selector(autoHide)
                                                  userInfo:nil
                                                   repeats:NO];
}

- (void)autoHide {
  if (self.controlsBar.scrubbing) {
    [self scheduleHide];
    return;
  }
  if (self.player.rate > 0)
    [self hideControlsAnimated:YES];
  else
    [self scheduleHide];
}

- (void)dealloc {
  [self.hideTimer invalidate];
  [self.controlsBar detachFromPlayer];
}

@end

@interface FnVideoPlayerPopup : NSObject

@property(nonatomic, strong) UIWindow *videoWindow;
@property(nonatomic, strong) UIView *overlayView;
@property(nonatomic, strong) UIView *playerContainer;
@property(nonatomic, strong) AVPlayer *player;
@property(nonatomic, strong) FnCustomPlayerView *customPlayerView;
@property(nonatomic, strong) UIActivityIndicatorView *bufferingSpinner;

+ (instancetype)shared;
+ (instancetype)sharedInstance;
- (void)presentWithURL:(NSURL *)url inWindow:(UIWindow *)sourceWindow;
- (void)dismiss;
- (void)layoutResizeHandles:(UIView *)container;
- (void)addResizeHandlesToContainer:(UIView *)container;
- (void)handleDrag:(UIPanGestureRecognizer *)gr;
- (void)handleResize:(UIPanGestureRecognizer *)gr;
- (void)pushNSCursor:(NSString *)selName;
- (void)popNSCursor;

@end

@interface FnPassthroughView : UIView
@end
@implementation FnPassthroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
  UIView *hit = [super hitTest:point withEvent:event];
  return (hit == self) ? nil : hit;
}
@end

@interface FnVideoRootViewController : UIViewController
@end

@implementation FnVideoRootViewController

- (BOOL)prefersPointerLocked {
  return NO;
}

- (void)loadView {
  FnPassthroughView *v = [[FnPassthroughView alloc] init];
  self.view = v;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  [super touchesBegan:touches withEvent:event];
}

- (NSArray<UIKeyCommand *> *)keyCommands {
  return @[ [UIKeyCommand keyCommandWithInput:UIKeyInputEscape
                                modifierFlags:0
                                       action:@selector(handleEsc:)] ];
}

- (void)handleEsc:(UIKeyCommand *)command {
  [[FnVideoPlayerPopup sharedInstance] dismiss];
}
@end

@implementation FnVideoPlayerPopup

+ (instancetype)sharedInstance {
  static FnVideoPlayerPopup *sharedInstance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sharedInstance = [[FnVideoPlayerPopup alloc] init];
  });
  return sharedInstance;
}

+ (instancetype)shared {
  return [self sharedInstance];
}

- (void)presentWithURL:(NSURL *)url inWindow:(UIWindow *)sourceWindow {

  if (!self.videoWindow) {
    UIWindowScene *scene = (UIWindowScene *)sourceWindow.windowScene;
    if (!scene)
      return;

    self.videoWindow = [[FnOverlayWindow alloc] initWithWindowScene:scene];
    self.videoWindow.windowLevel = UIWindowLevelAlert + 10;
    self.videoWindow.backgroundColor = [UIColor clearColor];

    FnVideoRootViewController *rootVC =
        [[FnVideoRootViewController alloc] init];
    self.videoWindow.rootViewController = rootVC;

    [self setupPersistentUI];
  }

  UIView *wrapper =
      objc_getAssociatedObject(self.playerContainer, "shadowWrapper");
  UIView *animTarget = wrapper ?: self.playerContainer;
  [animTarget.layer removeAllAnimations];

  CGFloat W = 1000, H = W * 9.0 / 16.0;
  UIWindowScene *ws = (UIWindowScene *)self.videoWindow.windowScene;
  CGRect sb = ws ? ws.effectiveGeometry.coordinateSpace.bounds
                 : self.videoWindow.bounds;
  animTarget.transform = CGAffineTransformIdentity;
  animTarget.frame = CGRectMake(floor((sb.size.width - W) / 2.0),
                                floor((sb.size.height - H) / 2.0), W, H);
  if (wrapper)
    wrapper.layer.shadowPath =
        [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, W, H)
                                   cornerRadius:12]
            .CGPath;
  self.playerContainer.frame = CGRectMake(0, 0, W, H);
  [self layoutResizeHandles:wrapper ?: self.playerContainer];

  [self.customPlayerView.controlsBar detachFromPlayer];
  AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
  item.preferredForwardBufferDuration = 10.0;
  [self.player replaceCurrentItemWithPlayerItem:item];
  [self.customPlayerView.controlsBar attachToPlayer:self.player];
  self.customPlayerView.controlsBar.scrubber.value = 0.0;
  [self.customPlayerView showControlsAnimated:NO];

  self.videoWindow.hidden = NO;
  animTarget.alpha = 0.0;
  animTarget.transform = CGAffineTransformMakeScale(0.8, 0.8);
  [UIView animateWithDuration:0.38
      delay:0
      usingSpringWithDamping:0.72
      initialSpringVelocity:0.3
      options:UIViewAnimationOptionAllowUserInteraction
      animations:^{
        animTarget.transform = CGAffineTransformIdentity;
        animTarget.alpha = 1.0;
      }
      completion:^(BOOL finished) {
        [self.player play];
      }];
}

- (void)setupPersistentUI {

  self.overlayView = [[UIView alloc] initWithFrame:self.videoWindow.bounds];
  self.overlayView.backgroundColor = [UIColor clearColor];
  self.overlayView.alpha = 1.0;
  self.overlayView.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  self.overlayView.userInteractionEnabled = NO;
  [self.videoWindow.rootViewController.view addSubview:self.overlayView];

  CGFloat w = 1000;
  CGFloat h = w * 9.0 / 16.0;
  UIWindowScene *scene = (UIWindowScene *)self.videoWindow.windowScene;
  CGRect screenBounds = scene ? scene.effectiveGeometry.coordinateSpace.bounds
                              : self.videoWindow.bounds;

  CGFloat ox = floor((screenBounds.size.width - w) / 2.0);
  CGFloat oy = floor((screenBounds.size.height - h) / 2.0);
  UIView *shadowWrapper =
      [[UIView alloc] initWithFrame:CGRectMake(ox, oy, w, h)];
  shadowWrapper.backgroundColor = [UIColor clearColor];
  shadowWrapper.layer.shadowColor = [UIColor blackColor].CGColor;
  shadowWrapper.layer.shadowOpacity = 0.55;
  shadowWrapper.layer.shadowRadius = 20;
  shadowWrapper.layer.shadowOffset = CGSizeMake(0, 6);
  shadowWrapper.layer.shadowPath =
      [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, w, h)
                                 cornerRadius:12]
          .CGPath;
  [self.videoWindow.rootViewController.view addSubview:shadowWrapper];

  self.playerContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
  self.playerContainer.backgroundColor = [UIColor blackColor];
  self.playerContainer.layer.cornerRadius = 12;
  self.playerContainer.layer.masksToBounds = YES;
  self.playerContainer.layer.borderWidth = 1.0;
  self.playerContainer.layer.borderColor =
      [UIColor colorWithWhite:0.2 alpha:1.0].CGColor;
  [shadowWrapper addSubview:self.playerContainer];

  objc_setAssociatedObject(self.playerContainer, "shadowWrapper", shadowWrapper,
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);

  UIPanGestureRecognizer *drag =
      [[UIPanGestureRecognizer alloc] initWithTarget:self
                                              action:@selector(handleDrag:)];
  drag.minimumNumberOfTouches = 1;
  [self.playerContainer addGestureRecognizer:drag];

  [self addResizeHandlesToContainer:shadowWrapper];

  self.player = [[AVPlayer alloc] init];
  self.player.allowsExternalPlayback = NO;

  self.customPlayerView =
      [[FnCustomPlayerView alloc] initWithPlayer:self.player
                                   dismissTarget:self
                                          action:@selector(dismiss)];
  self.customPlayerView.frame = self.playerContainer.bounds;
  self.customPlayerView.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [self.playerContainer addSubview:self.customPlayerView];

  self.bufferingSpinner = [[UIActivityIndicatorView alloc]
      initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
  self.bufferingSpinner.color = [UIColor whiteColor];
  self.bufferingSpinner.center =
      CGPointMake(self.playerContainer.bounds.size.width / 2,
                  self.playerContainer.bounds.size.height / 2);
  self.bufferingSpinner.autoresizingMask =
      UIViewAutoresizingFlexibleTopMargin |
      UIViewAutoresizingFlexibleBottomMargin |
      UIViewAutoresizingFlexibleLeftMargin |
      UIViewAutoresizingFlexibleRightMargin;
  self.bufferingSpinner.hidesWhenStopped = YES;
  [self.playerContainer addSubview:self.bufferingSpinner];

  [self.player addObserver:self
                forKeyPath:@"timeControlStatus"
                   options:NSKeyValueObservingOptionNew
                   context:nil];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
  if (object == self.player && [keyPath isEqualToString:@"timeControlStatus"]) {
    if (self.player.timeControlStatus ==
        AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate) {

      dispatch_after(
          dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
          dispatch_get_main_queue(), ^{
            if (self.player.timeControlStatus ==
                AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate) {
              [self.bufferingSpinner startAnimating];
              [self.playerContainer bringSubviewToFront:self.bufferingSpinner];
            }
          });
    } else {

      [self.bufferingSpinner stopAnimating];
    }
  }
}

- (void)dismiss {
  [self dismissAnimated:YES];
}

- (void)dismissAnimated:(BOOL)animated {
  [self.player pause];
  [self.player replaceCurrentItemWithPlayerItem:nil];

  UIView *wrapper =
      objc_getAssociatedObject(self.playerContainer, "shadowWrapper");
  UIView *animTarget = wrapper ?: self.playerContainer;

  if (animated) {
    [UIView animateWithDuration:0.25
        delay:0
        usingSpringWithDamping:0.85
        initialSpringVelocity:0.2
        options:UIViewAnimationOptionAllowUserInteraction
        animations:^{
          animTarget.transform = CGAffineTransformMakeScale(0.88, 0.88);
          animTarget.alpha = 0.0;
        }
        completion:^(BOOL finished) {
          self.videoWindow.hidden = YES;
          animTarget.transform = CGAffineTransformIdentity;
          animTarget.alpha = 1.0;
        }];
  } else {
    self.videoWindow.hidden = YES;
  }
}

- (void)handleDrag:(UIPanGestureRecognizer *)gr {
  UIView *container = self.playerContainer;
  UIView *wrapper = objc_getAssociatedObject(container, "shadowWrapper");
  UIView *parent = wrapper ? wrapper.superview : container.superview;
  UIView *moving = wrapper ?: container;
  if (!parent)
    return;

  CGPoint delta = [gr translationInView:parent];
  CGRect f = moving.frame;
  f.origin.x += delta.x;
  f.origin.y += delta.y;

  CGRect sb = parent.bounds;
  f.origin.x = MAX(0, MIN(sb.size.width - f.size.width, f.origin.x));
  f.origin.y = MAX(0, MIN(sb.size.height - f.size.height, f.origin.y));

  moving.frame = f;
  [gr setTranslation:CGPointZero inView:parent];
}

- (void)addResizeHandlesToContainer:(UIView *)container {
  NSArray *configs = @[
    @[ @1, @"resizeUpDownCursor" ],
    @[ @2, @"resizeUpDownCursor" ],
    @[ @4, @"resizeLeftRightCursor" ],
    @[ @8, @"resizeLeftRightCursor" ],
    @[ @5, @"_windowResizeNorthWestSouthEastCursor" ],
    @[ @9, @"_windowResizeNorthEastSouthWestCursor" ],
    @[ @6, @"_windowResizeNorthEastSouthWestCursor" ],
    @[ @10, @"_windowResizeNorthWestSouthEastCursor" ],
  ];
  for (NSArray *cfg in configs) {
    UIView *handle = [[UIView alloc] initWithFrame:CGRectZero];
    handle.backgroundColor = [UIColor clearColor];
    handle.tag = [cfg[0] integerValue];
    objc_setAssociatedObject(handle, "nsCursorSel", cfg[1],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIPanGestureRecognizer *rp = [[UIPanGestureRecognizer alloc]
        initWithTarget:self
                action:@selector(handleResize:)];
    [handle addGestureRecognizer:rp];
    if (@available(iOS 13.4, *)) {
      UIHoverGestureRecognizer *hover = [[UIHoverGestureRecognizer alloc]
          initWithTarget:self
                  action:@selector(handleResizeHandleHover:)];
      [handle addGestureRecognizer:hover];
    }
    [container addSubview:handle];
  }
  [self layoutResizeHandles:container];
}

- (void)pushNSCursor:(NSString *)selName {
  Class cls = NSClassFromString(@"NSCursor");
  if (!cls)
    return;
  SEL getSel = NSSelectorFromString(selName);
  IMP getImp = [cls methodForSelector:getSel];
  if (!getImp)
    return;
  id cursor = ((id(*)(id, SEL))getImp)(cls, getSel);
  if (!cursor)
    return;
  SEL pushSel = NSSelectorFromString(@"push");
  IMP pushImp = [cursor methodForSelector:pushSel];
  if (pushImp)
    ((void (*)(id, SEL))pushImp)(cursor, pushSel);
}

- (void)popNSCursor {
  Class cls = NSClassFromString(@"NSCursor");
  if (!cls)
    return;
  SEL popSel = NSSelectorFromString(@"pop");
  IMP popImp = [cls methodForSelector:popSel];
  if (popImp)
    ((void (*)(id, SEL))popImp)(cls, popSel);
}

- (void)handleResizeHandleHover:(UIHoverGestureRecognizer *)hover
    API_AVAILABLE(ios(13.4)) {
  UIView *handle = hover.view;
  NSString *cursorSel = objc_getAssociatedObject(handle, "nsCursorSel");
  if (hover.state == UIGestureRecognizerStateBegan) {
    [self pushNSCursor:cursorSel];
  } else if (hover.state == UIGestureRecognizerStateEnded ||
             hover.state == UIGestureRecognizerStateCancelled) {
    [self popNSCursor];
  }
}

- (void)layoutResizeHandles:(UIView *)container {
  CGFloat e = 16.0;
  CGFloat w = container.bounds.size.width;
  CGFloat h = container.bounds.size.height;
  for (UIView *handle in container.subviews) {
    if (handle.tag == 0)
      continue;
    NSInteger t = handle.tag;
    BOOL top = (t & 1) != 0;
    BOOL bottom = (t & 2) != 0;
    BOOL left = (t & 4) != 0;
    BOOL right = (t & 8) != 0;
    CGFloat x = left ? 0 : (right ? w - e : e);
    CGFloat y = top ? 0 : (bottom ? h - e : e);
    CGFloat fw = (left || right) ? e : w - e * 2;
    CGFloat fh = (top || bottom) ? e : h - e * 2;
    handle.frame = CGRectMake(x, y, fw, fh);
  }
}

- (void)handleResize:(UIPanGestureRecognizer *)gr {
  UIView *handle = (UIView *)gr.view;
  UIView *wrapper = handle.superview;
  UIView *parent = wrapper.superview;
  if (!parent)
    return;

  static CGRect startFrame;
  if (gr.state == UIGestureRecognizerStateBegan) {
    startFrame = wrapper.frame;
    return;
  }

  CGPoint delta = [gr translationInView:parent];
  CGRect f = startFrame;
  NSInteger t = handle.tag;
  BOOL top = (t & 1) != 0;
  BOOL bottom = (t & 2) != 0;
  BOOL left = (t & 4) != 0;
  BOOL right = (t & 8) != 0;

  static const CGFloat kAspect = 16.0 / 9.0;
  if (left || right) {
    if (left) {
      f.origin.x += delta.x;
      f.size.width -= delta.x;
    }
    if (right) {
      f.size.width += delta.x;
    }
    f.size.height = f.size.width / kAspect;
    if (top)
      f.origin.y = startFrame.origin.y + startFrame.size.height - f.size.height;
  } else {
    if (top) {
      f.origin.y += delta.y;
      f.size.height -= delta.y;
    }
    if (bottom) {
      f.size.height += delta.y;
    }
    f.size.width = f.size.height * kAspect;
    if (left)
      f.origin.x = startFrame.origin.x + startFrame.size.width - f.size.width;
  }

  CGFloat minW = 400, minH = 225;
  if (f.size.width < minW) {
    f.size.width = minW;
    f.size.height = minW / kAspect;
  }
  if (f.size.height < minH) {
    f.size.height = minH;
    f.size.width = minH * kAspect;
  }

  CGRect sb = parent.bounds;
  f.origin.x = MAX(0, MIN(sb.size.width - f.size.width, f.origin.x));
  f.origin.y = MAX(0, MIN(sb.size.height - f.size.height, f.origin.y));

  wrapper.frame = f;
  wrapper.layer.shadowPath =
      [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, f.size.width,
                                                         f.size.height)
                                 cornerRadius:12]
          .CGPath;
  self.playerContainer.frame = CGRectMake(0, 0, f.size.width, f.size.height);
  [self layoutResizeHandles:wrapper];

  FnCustomPlayerView *pv = (FnCustomPlayerView *)self.customPlayerView;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  pv.playerLayer.frame = pv.bounds;
  [CATransaction commit];
  [pv setNeedsLayout];
  [pv layoutIfNeeded];
}

@end

static NSString *const kFnVideoAssetURL =
    @"https://github.com/KohlerVG/FnMacTweak/releases/download/v2-assets/"
    @"Quick.Start.Video.mp4";

@interface FnVideoCardView : UIView
@property(nonatomic, strong) UIView *thumbnailContainer;
@property(nonatomic, strong) UIButton *playButton;
@property(nonatomic, strong) UIImageView *thumbnailView;
@end

@implementation FnVideoCardView

- (void)pausePlayback {
  [[FnVideoPlayerPopup shared] dismiss];
}

- (void)generateThumbnail:(NSURL *)url {

  NSDictionary *opts = @{AVURLAssetPreferPreciseDurationAndTimingKey : @NO};
  AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:opts];
  AVAssetImageGenerator *gen =
      [[AVAssetImageGenerator alloc] initWithAsset:asset];
  gen.appliesPreferredTrackTransform = YES;

  gen.requestedTimeToleranceBefore = CMTimeMakeWithSeconds(3.0, 600);
  gen.requestedTimeToleranceAfter = CMTimeMakeWithSeconds(3.0, 600);

  [gen generateCGImageAsynchronouslyForTime:kCMTimeZero
                          completionHandler:^(CGImageRef _Nullable image,
                                              CMTime actualTime,
                                              NSError *_Nullable error) {
                            if (image) {
                              UIImage *thumb = [UIImage imageWithCGImage:image];
                              dispatch_async(dispatch_get_main_queue(), ^{
                                self.thumbnailView.image = thumb;
                                self.thumbnailView.hidden = NO;
                              });
                            } else {

                            }
                          }];
}

- (instancetype)initWithTitle:(NSString *)title
                  description:(NSString *)desc
                        width:(CGFloat)w {

  CGFloat pad = 12.0;
  CGFloat inner = w - pad * 2;
  CGFloat videoH = inner * 9.0 / 16.0;
  CGFloat gap = 6.0;

  UILabel *tmp = [[UILabel alloc] init];
  tmp.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
  tmp.numberOfLines = 0;
  tmp.text = desc;
  CGFloat descH = [tmp sizeThatFits:CGSizeMake(inner, CGFLOAT_MAX)].height;
  CGFloat totalH = pad + 16 + gap + descH + gap + videoH + pad;

  self = [super initWithFrame:CGRectMake(0, 0, w, totalH)];
  if (!self)
    return nil;

  self.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
  self.layer.cornerRadius = 10;
  self.layer.borderWidth = 0.5;
  self.layer.borderColor = [UIColor colorWithWhite:0.28 alpha:1.0].CGColor;

  CGFloat y = pad;
  UILabel *tl = [[UILabel alloc] initWithFrame:CGRectMake(pad, y, inner, 16)];
  tl.text = title;
  tl.textColor = [UIColor whiteColor];
  tl.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
  [self addSubview:tl];
  y += 16 + gap;

  UILabel *dl =
      [[UILabel alloc] initWithFrame:CGRectMake(pad, y, inner, descH)];
  dl.text = desc;
  dl.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
  dl.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
  dl.numberOfLines = 0;
  [self addSubview:dl];
  y += descH + gap;

  self.thumbnailContainer =
      [[UIView alloc] initWithFrame:CGRectMake(pad, y, inner, videoH)];
  self.thumbnailContainer.backgroundColor = [UIColor blackColor];
  self.thumbnailContainer.layer.cornerRadius = 6;
  self.thumbnailContainer.layer.masksToBounds = YES;
  [self addSubview:self.thumbnailContainer];

  self.thumbnailView =
      [[UIImageView alloc] initWithFrame:self.thumbnailContainer.bounds];
  self.thumbnailView.contentMode = UIViewContentModeScaleAspectFill;
  self.thumbnailView.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  self.thumbnailView.hidden = YES;
  [self.thumbnailContainer addSubview:self.thumbnailView];

  self.playButton = [UIButton buttonWithType:UIButtonTypeCustom];
  self.playButton.frame = CGRectMake(0, 0, 80, 80);
  self.playButton.center = CGPointMake(inner / 2, videoH / 2);
  self.playButton.tintColor = [UIColor whiteColor];
  UIImageSymbolConfiguration *playCfg = [UIImageSymbolConfiguration
      configurationWithPointSize:80
                          weight:UIImageSymbolWeightRegular];
  UIImage *playImg = [UIImage systemImageNamed:@"play.circle.fill"
                             withConfiguration:playCfg];
  [self.playButton setImage:playImg forState:UIControlStateNormal];
  self.playButton.contentVerticalAlignment =
      UIControlContentVerticalAlignmentFill;
  self.playButton.contentHorizontalAlignment =
      UIControlContentHorizontalAlignmentFill;

  [self.playButton addTarget:self
                      action:@selector(launchPopup)
            forControlEvents:UIControlEventTouchUpInside];
  [self.playButton
             addTarget:self
                action:@selector(playBtnDown)
      forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
  [self.playButton
             addTarget:self
                action:@selector(playBtnUp)
      forControlEvents:UIControlEventTouchUpInside |
                       UIControlEventTouchUpOutside |
                       UIControlEventTouchCancel | UIControlEventTouchDragExit];
  self.playButton.hidden = NO;
  [self.thumbnailContainer addSubview:self.playButton];

  [self generateThumbnail:[NSURL URLWithString:kFnVideoAssetURL]];

  return self;
}

- (void)playBtnDown {
  CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"opacity"];
  a.toValue = @0.45;
  a.duration = 0.08;
  a.fillMode = kCAFillModeForwards;
  a.removedOnCompletion = NO;
  a.timingFunction =
      [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
  [self.playButton.layer addAnimation:a forKey:@"playPress"];
  self.playButton.layer.opacity = 0.45;
}

- (void)playBtnUp {
  [self.playButton.layer removeAnimationForKey:@"playPress"];
  CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"opacity"];
  a.fromValue = @(self.playButton.layer.presentationLayer.opacity);
  a.toValue = @1.0;
  a.duration = 0.14;
  a.timingFunction =
      [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
  a.removedOnCompletion = YES;
  [self.playButton.layer addAnimation:a forKey:@"playRelease"];
  self.playButton.layer.opacity = 1.0;
}

- (void)launchPopup {

  UIWindow *gameWindow = nil;
  UIView *v = self;
  while (v && ![v isKindOfClass:[UIWindow class]])
    v = v.superview;
  gameWindow = (UIWindow *)v;

  NSURL *remoteURL = [NSURL URLWithString:kFnVideoAssetURL];
  [[FnVideoPlayerPopup shared] presentWithURL:remoteURL inWindow:gameWindow];
}

@end

static void loadSettings() {
  NSDictionary *settings =
      [[NSUserDefaults standardUserDefaults] dictionaryForKey:kSettingsKey];
  if (settings) {
    BASE_XY_SENSITIVITY = [settings[kBaseXYKey] floatValue] ?: 6.4f;
    MACOS_TO_PC_SCALE = [settings[kScaleKey] floatValue] ?: 20.0f;
    GYRO_MULTIPLIER = [settings[kGyroMultiplierKey] floatValue] ?: 100.0f;
    GCMOUSE_DIRECT_KEY = settings[kGCMouseDirectKey] ? (GCKeyCode)[settings[kGCMouseDirectKey] intValue] : 53;
    if (GCMOUSE_DIRECT_KEY == 50 || GCMOUSE_DIRECT_KEY == 0) GCMOUSE_DIRECT_KEY = 53;

    recalculateSensitivities();
  }

  loadKeyRemappings();
}

static BOOL isMouseInputCode(GCKeyCode keyCode) {
  return (keyCode == MOUSE_BUTTON_LEFT ||
          keyCode == MOUSE_BUTTON_RIGHT ||
          keyCode >= MOUSE_BUTTON_MIDDLE);
}

static NSString *getKeyName(GCKeyCode keyCode) {
  if (keyCode == 0) return @"-";

  if (keyCode == MOUSE_BUTTON_LEFT) return @"🖱️ L";
  if (keyCode == MOUSE_BUTTON_RIGHT) return @"🖱️ R";
  if (keyCode == MOUSE_BUTTON_MIDDLE) return @"🖱️ Middle";
  if (keyCode == MOUSE_BUTTON_AUX_BASE) return @"🖱️ M4";
  if (keyCode == MOUSE_BUTTON_AUX_BASE + 1) return @"🖱️ M5";
  if (keyCode >= MOUSE_BUTTON_AUX_BASE && keyCode <= MOUSE_BUTTON_AUX_MAX) {
      return [NSString stringWithFormat:@"AUX %d", (int)(keyCode - MOUSE_BUTTON_AUX_BASE + 1)];
  }
  if (keyCode == MOUSE_SCROLL_UP) return @"🖱️ Scroll ↑";
  if (keyCode == MOUSE_SCROLL_DOWN) return @"🖱️ Scroll ↓";
  if (keyCode == MOUSE_SCROLL_LEFT) return @"🖱️ Scroll ←";
  if (keyCode == MOUSE_SCROLL_RIGHT) return @"🖱️ Scroll →";

  if (keyCode == 53) return @"`";

  if (keyCode == GCKeyCodeReturnOrEnter) return @"Enter";
  if (keyCode == GCKeyCodeSpacebar) return @"Space";
  if (keyCode == GCKeyCodeDeleteOrBackspace) return @"Backspace";
  if (keyCode == GCKeyCodeEscape) return @"Esc";
  if (keyCode == GCKeyCodeTab) return @"Tab";
  if (keyCode == GCKeyCodeLeftShift) return @"L-Shift";
  if (keyCode == GCKeyCodeRightShift) return @"R-Shift";
  if (keyCode == GCKeyCodeLeftControl) return @"L-Ctrl";
  if (keyCode == GCKeyCodeRightControl) return @"R-Ctrl";
  if (keyCode == GCKeyCodeLeftAlt) return @"L-Alt";
  if (keyCode == GCKeyCodeRightAlt) return @"R-Alt";
  if (keyCode == GCKeyCodeLeftGUI) return @"L-Cmd";
  if (keyCode == GCKeyCodeRightGUI) return @"R-Cmd";
  if (keyCode == GCKeyCodeCapsLock) return @"Caps";
  if (keyCode == GCKeyCodeUpArrow) return @"↑";
  if (keyCode == GCKeyCodeDownArrow) return @"↓";
  if (keyCode == GCKeyCodeLeftArrow) return @"←";
  if (keyCode == GCKeyCodeRightArrow) return @"→";
  if (keyCode == GCKeyCodeF1) return @"F1";
  if (keyCode == GCKeyCodeF2) return @"F2";
  if (keyCode == GCKeyCodeF3) return @"F3";
  if (keyCode == GCKeyCodeF4) return @"F4";
  if (keyCode == GCKeyCodeF5) return @"F5";
  if (keyCode == GCKeyCodeF6) return @"F6";
  if (keyCode == GCKeyCodeF7) return @"F7";
  if (keyCode == GCKeyCodeF8) return @"F8";
  if (keyCode == GCKeyCodeF9) return @"F9";
  if (keyCode == GCKeyCodeF10) return @"F10";
  if (keyCode == GCKeyCodeF11) return @"F11";
  if (keyCode == GCKeyCodeF12) return @"F12";

  if (keyCode == GCKeyCodeOne) return @"1";
  if (keyCode == GCKeyCodeTwo) return @"2";
  if (keyCode == GCKeyCodeThree) return @"3";
  if (keyCode == GCKeyCodeFour) return @"4";
  if (keyCode == GCKeyCodeFive) return @"5";
  if (keyCode == GCKeyCodeSix) return @"6";
  if (keyCode == GCKeyCodeSeven) return @"7";
  if (keyCode == GCKeyCodeEight) return @"8";
  if (keyCode == GCKeyCodeNine) return @"9";
  if (keyCode == GCKeyCodeZero) return @"0";

  if (keyCode >= GCKeyCodeKeyA && keyCode <= GCKeyCodeKeyZ) {
      return [NSString stringWithFormat:@"%c", (char)('A' + (int)(keyCode - GCKeyCodeKeyA))];
  }

  if (keyCode == 45) return @"-";
  if (keyCode == 46) return @"=";
  if (keyCode == 47) return @"[";
  if (keyCode == 48) return @"]";
  if (keyCode == 49) return @"\\";
  if (keyCode == 51) return @";";
  if (keyCode == 52) return @"'";
  if (keyCode == 54) return @",";
  if (keyCode == 55) return @".";
  if (keyCode == 56) return @"/";

  if (keyCode == 41) return @"Esc";
  if (keyCode == 225) return @"Shift";
  if (keyCode == 224) return @"Ctrl";
  if (keyCode == 226) return @"Alt";
  if (keyCode == 227) return @"Cmd";
  if (keyCode == 57) return @"Caps";

  return [NSString stringWithFormat:@"Code %d", (int)keyCode];
}

@interface popupViewController ()

@property(nonatomic, strong) UITextField *gyroMultiplierField;
@property(nonatomic, strong) UITextField *scaleField;
@property(nonatomic, strong) UIButton *directKeyButton;
@property(nonatomic, strong) UILabel *feedbackLabel;
@property(nonatomic, strong) UIScrollView *scrollView;

@property(nonatomic, assign) float originalGyroMultiplier;
@property(nonatomic, assign) float originalScale;
@property(nonatomic, assign) GCKeyCode originalDirectKey;
@property(nonatomic, assign) GCKeyCode stagedDirectKey;

@property(nonatomic, strong) NSMutableArray *keyRemapRows;
@property(nonatomic, strong) UIButton *addRemapButton;
@property(nonatomic, strong) UIButton *currentCapturingButton;
@property(nonatomic, assign) GCKeyCode currentCapturingSourceKey;
@property(nonatomic, assign) BOOL isCapturingKey;

@property(nonatomic, assign) CGFloat sensitivityContentHeight;
@property(nonatomic, assign) CGFloat keyRemapContentHeight;
@property(nonatomic, assign) CGFloat quickStartContentHeight;
@property(nonatomic, assign) CGFloat controllerContentHeight;

@property(nonatomic, assign) CGPoint dragStartPoint;

@property(nonatomic, strong) UIButton *closeButton;
@property(nonatomic, strong) UIView *closeX;

@property(nonatomic, strong) NSArray *cachedFortniteActions;
@property(nonatomic, strong) NSDictionary *actionToDefaultKeyMap;

@property(nonatomic, strong) NSData *exportData;
@property(nonatomic, strong) NSString *exportFileName;

- (void)saveButtonTapped:(UIButton *)sender;
- (void)applyDefaultsTapped:(UIButton *)sender;
- (void)switchToTab:(PopupTab)tab;
- (void)stageMouseButtonKeybind:(int)mouseCode forAction:(NSString *)actionName;
- (void)clearMouseBindingForAction:(NSString *)actionName;
- (void)updateDirectKeyButtonStyle;
- (void)updateSensitivityFieldBorders;
- (void)updateSensitivityDiscardButton;
- (void)sensitivityFieldChanged:(UITextField *)sender;
- (void)resetSectionTapped:(UIButton *)sender;
- (void)resetDirectKeyTapped;
- (NSString *)findAnyConflictDescriptionForCode:(int)code;
- (void)resolveConflictForCode:(int)code;
@end

@implementation popupViewController

- (BOOL)prefersPointerLocked {
  return NO;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  loadSettings();

  self.keyRemapRows = [NSMutableArray array];
  self.isCapturingKey = NO;

  self.stagedKeybinds = [NSMutableDictionary dictionary];
  self.stagedControllerMappings = [NSMutableDictionary dictionary];
  self.stagedVCtrlRemappings = [NSMutableArray arrayWithArray:vctrlRemappings ?: @[]];

  self.originalGyroMultiplier = GYRO_MULTIPLIER;
  self.originalScale = MACOS_TO_PC_SCALE;
  self.originalDirectKey = GCMOUSE_DIRECT_KEY;
  self.stagedDirectKey = GCMOUSE_DIRECT_KEY;

  self.cachedFortniteActions = @[
    @{@"action" : @"Sprint", @"default" : @(225)},
    @{@"action" : @"Crouch", @"default" : @(224)},
    @{@"action" : @"Auto Walk", @"default" : @(46)},
    @{@"action" : @"Harvesting Tool", @"default" : @(9)},
    @{@"action" : @"Use", @"default" : @(8)},
    @{@"action" : @"Reload", @"default" : @(21)},
    @{@"action" : @"Weapon Slot 1", @"default" : @(30)},
    @{@"action" : @"Weapon Slot 2", @"default" : @(31)},
    @{@"action" : @"Weapon Slot 3", @"default" : @(32)},
    @{@"action" : @"Weapon Slot 4", @"default" : @(33)},
    @{@"action" : @"Weapon Slot 5", @"default" : @(34)},
    @{@"action" : @"Build", @"default" : @(20)},
    @{@"action" : @"Edit", @"default" : @(10)},
    @{@"action" : @"Wall", @"default" : @(29)},
    @{@"action" : @"Floor", @"default" : @(27)},
    @{@"action" : @"Stairs", @"default" : @(6)},
    @{@"action" : @"Roof", @"default" : @(25)},
    @{@"action" : @"Trap", @"default" : @(11)},
    @{@"action" : @"Inventory Toggle", @"default" : @(226)},
    @{@"action" : @"Emote", @"default" : @(5)},
    @{@"action" : @"Chat", @"default" : @(40)},
    @{@"action" : @"Push To Talk", @"default" : @(23)},
    @{@"action" : @"Map", @"default" : @(16)},
    @{@"action" : @"Escape", @"default" : @(41)}
  ];

  NSMutableDictionary *tempMap = [NSMutableDictionary dictionary];
  for (NSDictionary *actionInfo in self.cachedFortniteActions) {
    tempMap[actionInfo[@"action"]] = actionInfo[@"default"];
  }
  self.actionToDefaultKeyMap = [tempMap copy];

  self.view.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];

  self.view.layer.cornerRadius = 12;
  self.view.layer.borderWidth = 0.5;
  self.view.layer.borderColor =
      [UIColor colorWithWhite:0.25 alpha:0.8].CGColor;
  self.view.layer.masksToBounds = YES;

  UIView *titleBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 330, 40)];
  titleBar.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.15];
  [self.view addSubview:titleBar];

  UILabel *titleLabel =
      [[UILabel alloc] initWithFrame:CGRectMake(60, 0, 210, 40)];
  titleLabel.text = @"FnMacTweak";
  titleLabel.textColor = [UIColor whiteColor];
  titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
  titleLabel.textAlignment = NSTextAlignmentCenter;
  [titleBar addSubview:titleLabel];

  self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
  self.closeButton.frame = CGRectMake(12, 12, 16, 16);
  self.closeButton.backgroundColor = [UIColor colorWithRed:1.0
                                                     green:0.23
                                                      blue:0.19
                                                     alpha:1.0];
  self.closeButton.layer.cornerRadius = 8;
  self.closeButton.layer.borderWidth = 0.5;
  self.closeButton.layer.borderColor =
      [UIColor colorWithRed:0.25 green:0.0 blue:0.0 alpha:1.0].CGColor;
  [self.closeButton addTarget:self
                       action:@selector(closeButtonTapped)
             forControlEvents:UIControlEventTouchUpInside];

  UIImageSymbolConfiguration *xConfig = [UIImageSymbolConfiguration
      configurationWithPointSize:9
                          weight:UIImageSymbolWeightBlack];
  UIImage *xImage = [[UIImage systemImageNamed:@"xmark"]
      imageByApplyingSymbolConfiguration:xConfig];

  UIImageView *xImageView = [[UIImageView alloc] initWithImage:xImage];
  xImageView.frame = CGRectMake(0, 0, 16, 16);
  xImageView.contentMode = UIViewContentModeCenter;
  xImageView.tintColor =
      [UIColor colorWithRed:0.25
                      green:0.0
                       blue:0.0
                      alpha:1.0];
  xImageView.alpha = 0;
  self.closeX = (UILabel *)xImageView;
  [self.closeButton addSubview:xImageView];

  UIHoverGestureRecognizer *hoverGesture = [[UIHoverGestureRecognizer alloc]
      initWithTarget:self
              action:@selector(closeButtonHover:)];
  [self.closeButton addGestureRecognizer:hoverGesture];

  [titleBar addSubview:self.closeButton];

  CGFloat pillW = 44.0;
  CGFloat pillH = 16.0;
  CGFloat pillX = 330.0 - 12.0 - pillW;
  CGFloat pillY = (40.0 - pillH) / 2.0;
  UIView *versionPill = [[UIView alloc] initWithFrame:CGRectMake(pillX, pillY, pillW, pillH)];
  versionPill.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
  versionPill.layer.cornerRadius = pillH / 2.0;
  versionPill.layer.borderWidth = 0.5;
  versionPill.layer.borderColor = [UIColor colorWithWhite:0.45 alpha:1.0].CGColor;
  UILabel *versionLabel = [[UILabel alloc] initWithFrame:versionPill.bounds];
  versionLabel.text = @"v4.0.0";
  versionLabel.textColor = [UIColor colorWithWhite:0.72 alpha:1.0];
  versionLabel.font = [UIFont systemFontOfSize:9 weight:UIFontWeightMedium];
  versionLabel.textAlignment = NSTextAlignmentCenter;
  [versionPill addSubview:versionLabel];
  [titleBar addSubview:versionPill];

  UIPanGestureRecognizer *panGesture =
      [[UIPanGestureRecognizer alloc] initWithTarget:self
                                              action:@selector(handlePan:)];
  [titleBar addGestureRecognizer:panGesture];

  UIView *tabBar = [[UIView alloc] initWithFrame:CGRectMake(0, 40, 330, 50)];
  tabBar.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.1];
  [self.view addSubview:tabBar];

  self.segmentedContainer =
      [[UIView alloc] initWithFrame:CGRectMake(42, 10, 245, 30)];
  self.segmentedContainer.backgroundColor = [UIColor colorWithWhite:0.15
                                                              alpha:0.6];
  self.segmentedContainer.layer.cornerRadius = 6;
  self.segmentedContainer.layer.borderWidth = 0.5;
  self.segmentedContainer.layer.borderColor =
      [UIColor colorWithWhite:0.3 alpha:0.3].CGColor;
  [tabBar addSubview:self.segmentedContainer];

  self.tabIndicator = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 49, 30)];
  self.tabIndicator.backgroundColor = [UIColor colorWithWhite:0.25 alpha:0.8];
  self.tabIndicator.layer.cornerRadius = 6;
  [self.segmentedContainer addSubview:self.tabIndicator];

  self.sensitivityTabButton = [UIButton buttonWithType:UIButtonTypeSystem];
  self.sensitivityTabButton.frame = CGRectMake(0, 0, 49, 30);
  [self.sensitivityTabButton setTitle:@"🖱️" forState:UIControlStateNormal];
  self.sensitivityTabButton.titleLabel.font = [UIFont systemFontOfSize:22];
  self.sensitivityTabButton.layer.cornerRadius = 6;
  self.sensitivityTabButton.clipsToBounds = YES;
  self.sensitivityTabButton.backgroundColor = [UIColor clearColor];
  [self.sensitivityTabButton addTarget:self
                                action:@selector(sensitivityTabTapped)
                      forControlEvents:UIControlEventTouchUpInside];
  [self.segmentedContainer addSubview:self.sensitivityTabButton];

  self.controllerTabButton = [UIButton buttonWithType:UIButtonTypeSystem];
  self.controllerTabButton.frame = CGRectMake(98, 0, 49, 30);
  [self.controllerTabButton setTitle:@"🎮" forState:UIControlStateNormal];
  self.controllerTabButton.titleLabel.font = [UIFont systemFontOfSize:22];
  self.controllerTabButton.layer.cornerRadius = 6;
  self.controllerTabButton.clipsToBounds = YES;
  self.controllerTabButton.backgroundColor = [UIColor clearColor];
  [self.controllerTabButton addTarget:self
                               action:@selector(controllerTabTapped)
                     forControlEvents:UIControlEventTouchUpInside];
  [self.segmentedContainer addSubview:self.controllerTabButton];

  self.keyRemapTabButton = [UIButton buttonWithType:UIButtonTypeSystem];
  self.keyRemapTabButton.frame = CGRectMake(49, 0, 49, 30);
  [self.keyRemapTabButton setTitle:@"⌨️" forState:UIControlStateNormal];
  self.keyRemapTabButton.titleLabel.font = [UIFont systemFontOfSize:22];
  self.keyRemapTabButton.layer.cornerRadius = 6;
  self.keyRemapTabButton.clipsToBounds = YES;
  self.keyRemapTabButton.backgroundColor = [UIColor clearColor];
  [self.keyRemapTabButton addTarget:self
                             action:@selector(keyRemapTabTapped)
                   forControlEvents:UIControlEventTouchUpInside];
  [self.segmentedContainer addSubview:self.keyRemapTabButton];

  self.containerTabButton = [UIButton buttonWithType:UIButtonTypeSystem];
  self.containerTabButton.frame = CGRectMake(147, 0, 49, 30);
  [self.containerTabButton setTitle:@"🔗" forState:UIControlStateNormal];
  self.containerTabButton.titleLabel.font = [UIFont systemFontOfSize:22];
  self.containerTabButton.layer.cornerRadius = 6;
  self.containerTabButton.clipsToBounds = YES;
  self.containerTabButton.backgroundColor = [UIColor clearColor];
  [self.containerTabButton addTarget:self
                               action:@selector(containerTabTapped)
                     forControlEvents:UIControlEventTouchUpInside];
  [self.segmentedContainer addSubview:self.containerTabButton];

  self.quickStartTabButton = [UIButton buttonWithType:UIButtonTypeSystem];
  self.quickStartTabButton.frame = CGRectMake(196, 0, 49, 30);
  [self.quickStartTabButton setTitle:@"❓" forState:UIControlStateNormal];
  self.quickStartTabButton.titleLabel.font = [UIFont systemFontOfSize:22];
  self.quickStartTabButton.layer.cornerRadius = 6;
  self.quickStartTabButton.clipsToBounds = YES;
  self.quickStartTabButton.backgroundColor = [UIColor clearColor];
  [self.quickStartTabButton addTarget:self
                               action:@selector(quickStartTabTapped)
                     forControlEvents:UIControlEventTouchUpInside];
  [self.segmentedContainer addSubview:self.quickStartTabButton];

  self.scrollView =
      [[UIScrollView alloc] initWithFrame:CGRectMake(0, 90, 330, 510)];
  self.scrollView.backgroundColor = [UIColor clearColor];
  self.scrollView.showsVerticalScrollIndicator = YES;
  self.scrollView.bounces = YES;
  self.scrollView.alwaysBounceVertical = YES;
  self.scrollView.delaysContentTouches = NO;
  self.scrollView.canCancelContentTouches = YES;
  self.scrollView.userInteractionEnabled = YES;
  [self.view addSubview:self.scrollView];

  [self createSensitivityTab];
  [self createKeyRemapTab];
  [self createContainerTab];
  [self createQuickStartTab];
  [self createControllerTab];

}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];

  if (self.currentTab == 0 && self.sensitivityTab.superview == nil) {
    [self switchToTab:PopupTabSensitivity];
  }
}

- (void)switchToQuickStartTab {
  [self switchToTab:PopupTabQuickStart];
}

- (void)createSensitivityTab {
  self.sensitivityTab =
      [[UIView alloc] initWithFrame:CGRectMake(0, 0, 330, 800)];
  self.sensitivityTab.backgroundColor = [UIColor clearColor];

  CGFloat y = 16;
  CGFloat leftMargin = 20;
  CGFloat rightMargin = 20;
  CGFloat contentWidth = 330 - leftMargin - rightMargin;

  UILabel *title = [[UILabel alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 24)];
  title.text = @"Sensitivity";
  title.textColor = [UIColor whiteColor];
  title.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
  title.textAlignment = NSTextAlignmentCenter;
  [self.sensitivityTab addSubview:title];

  y += 32;
  UIView *descriptionBanner = [[UIView alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 58)];
  descriptionBanner.backgroundColor =
      [UIColor colorWithRed:0.2
                      green:0.6
                       blue:0.3
                      alpha:0.2];
  descriptionBanner.layer.cornerRadius = 8;
  [self.sensitivityTab addSubview:descriptionBanner];

  UILabel *descriptionLabel =
      [[UILabel alloc] initWithFrame:CGRectMake(8, 10, contentWidth - 16, 38)];
  descriptionLabel.text =
      @"Fine-tune gyro aiming sensitivity and manage mouse input settings";
  descriptionLabel.textColor = [UIColor colorWithRed:0.6
                                               green:1.0
                                                blue:0.7
                                               alpha:1.0];
  descriptionLabel.font = [UIFont systemFontOfSize:13
                                            weight:UIFontWeightMedium];
  descriptionLabel.textAlignment = NSTextAlignmentCenter;
  descriptionLabel.numberOfLines = 2;
  [descriptionBanner addSubview:descriptionLabel];
  y += 74;

  self.applySensitivityButton = [UIButton buttonWithType:UIButtonTypeSystem];
  self.applySensitivityButton.frame =
      CGRectMake(leftMargin, y, contentWidth, 32);
  self.applySensitivityButton.backgroundColor =
      [UIColor colorWithRed:0.0 green:0.47 blue:1.0 alpha:0.85];
  [self.applySensitivityButton setTitle:@"Apply Changes"
                               forState:UIControlStateNormal];
  [self.applySensitivityButton setTitleColor:[UIColor whiteColor]
                                    forState:UIControlStateNormal];
  self.applySensitivityButton.titleLabel.font =
      [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
  self.applySensitivityButton.layer.cornerRadius = 6;
  self.applySensitivityButton.layer.borderWidth = 0.5;
  self.applySensitivityButton.layer.borderColor =
      [UIColor colorWithRed:0.0 green:0.4 blue:0.9 alpha:0.6].CGColor;
  [self.applySensitivityButton addTarget:self
                                  action:@selector(saveButtonTapped:)
                        forControlEvents:UIControlEventTouchUpInside];
  self.applySensitivityButton.alpha = 0.5;
  self.applySensitivityButton.enabled = NO;
  [self.sensitivityTab addSubview:self.applySensitivityButton];
  y += 38;

  self.discardSensitivityButton = [UIButton buttonWithType:UIButtonTypeSystem];
  self.discardSensitivityButton.frame =
      CGRectMake(leftMargin, y, contentWidth, 32);
  self.discardSensitivityButton.backgroundColor =
      [UIColor colorWithRed:1.0 green:0.9 blue:0.3 alpha:1.0];
  [self.discardSensitivityButton setTitle:@"Discard Changes"
                                 forState:UIControlStateNormal];
  [self.discardSensitivityButton setTitleColor:[UIColor blackColor]
                                      forState:UIControlStateNormal];
  self.discardSensitivityButton.titleLabel.font =
      [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
  self.discardSensitivityButton.layer.cornerRadius = 6;
  self.discardSensitivityButton.layer.borderWidth = 0.5;
  self.discardSensitivityButton.layer.borderColor =
      [UIColor colorWithRed:0.9 green:0.8 blue:0.2 alpha:0.6].CGColor;
  [self.discardSensitivityButton addTarget:self
                                    action:@selector(discardSensitivityChangesTapped)
                          forControlEvents:UIControlEventTouchUpInside];
  self.discardSensitivityButton.alpha = 0.3;
  self.discardSensitivityButton.enabled = NO;
  [self.sensitivityTab addSubview:self.discardSensitivityButton];
  y += 38;

  UIButton *resetAllButton = [UIButton buttonWithType:UIButtonTypeSystem];
  resetAllButton.frame = CGRectMake(leftMargin, y, contentWidth, 32);
  resetAllButton.backgroundColor =
      [UIColor colorWithRed:0.6 green:0.2 blue:0.2 alpha:0.5];
  [resetAllButton setTitle:@"Reset All to Defaults"
                  forState:UIControlStateNormal];
  [resetAllButton setTitleColor:[UIColor colorWithRed:1.0
                                                green:0.7
                                                 blue:0.7
                                                alpha:1.0]
                       forState:UIControlStateNormal];
  resetAllButton.titleLabel.font =
      [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
  resetAllButton.layer.cornerRadius = 6;
  resetAllButton.layer.borderWidth = 0.5;
  resetAllButton.layer.borderColor =
      [UIColor colorWithRed:0.5 green:0.25 blue:0.25 alpha:0.5].CGColor;
  [resetAllButton addTarget:self
                     action:@selector(resetAllSensitivityTapped)
           forControlEvents:UIControlEventTouchUpInside];
  [self.sensitivityTab addSubview:resetAllButton];
  y += 50;

  UILabel *sensHeader = [[UILabel alloc] initWithFrame:CGRectMake(leftMargin, y, contentWidth, 20)];
  sensHeader.text = @"SENSITIVITY";
  sensHeader.textColor = [UIColor colorWithRed:0.5 green:0.7 blue:1.0 alpha:1.0];
  sensHeader.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
  [self.sensitivityTab addSubview:sensHeader];
  y += 24;

  UIView *gyroRow = [[UIView alloc] initWithFrame:CGRectMake(leftMargin, y, contentWidth, 30)];
  [self.sensitivityTab addSubview:gyroRow];

  UIButton *resetGyroBtn = [UIButton buttonWithType:UIButtonTypeSystem];
  resetGyroBtn.frame = CGRectMake(0, 5, 20, 20);
  [resetGyroBtn setTitle:@"↪️" forState:UIControlStateNormal];
  resetGyroBtn.titleLabel.font = [UIFont systemFontOfSize:14];
  resetGyroBtn.accessibilityLabel = @"gyroMultiplierField:100.0";
  resetGyroBtn.accessibilityHint = @"Gyro Sensitivity";
  [resetGyroBtn addTarget:self action:@selector(resetSectionTapped:) forControlEvents:UIControlEventTouchUpInside];
  [gyroRow addSubview:resetGyroBtn];

  UILabel *gyroLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, 5, contentWidth - 140, 20)];
  gyroLabel.text = @"Gyro Sensitivity";
  gyroLabel.textColor = [UIColor colorWithWhite:0.85 alpha:1.0];
  gyroLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
  [gyroRow addSubview:gyroLabel];

  self.gyroMultiplierField = [[UITextField alloc] initWithFrame:CGRectMake(contentWidth - 110, 3, 110, 24)];
  self.gyroMultiplierField.backgroundColor = [UIColor colorWithWhite:0.22 alpha:1.0];
  self.gyroMultiplierField.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
  self.gyroMultiplierField.layer.cornerRadius = 4;
  self.gyroMultiplierField.textAlignment = NSTextAlignmentCenter;
  self.gyroMultiplierField.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
  self.gyroMultiplierField.keyboardType = UIKeyboardTypeDecimalPad;
  self.gyroMultiplierField.text = [NSString stringWithFormat:@"%.1f", GYRO_MULTIPLIER];
  [self.gyroMultiplierField addTarget:self action:@selector(sensitivityFieldChanged:) forControlEvents:UIControlEventEditingChanged];
  [gyroRow addSubview:self.gyroMultiplierField];

  y += 36;

  UIView *directRow = [[UIView alloc] initWithFrame:CGRectMake(leftMargin, y, contentWidth, 30)];
  [self.sensitivityTab addSubview:directRow];

  UIButton *resetDirectButton = [UIButton buttonWithType:UIButtonTypeSystem];
  resetDirectButton.frame = CGRectMake(0, 5, 20, 20);
  [resetDirectButton setTitle:@"↪️" forState:UIControlStateNormal];
  resetDirectButton.titleLabel.font = [UIFont systemFontOfSize:14];
  [resetDirectButton addTarget:self action:@selector(resetDirectKeyTapped) forControlEvents:UIControlEventTouchUpInside];
  [directRow addSubview:resetDirectButton];

  UILabel *directTitle = [[UILabel alloc] initWithFrame:CGRectMake(24, 5, contentWidth - 140, 20)];
  directTitle.text = @"GCMouseInput Toggle";
  directTitle.textColor = [UIColor colorWithWhite:0.85 alpha:1.0];
  directTitle.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
  [directRow addSubview:directTitle];

  self.directKeyButton = [UIButton buttonWithType:UIButtonTypeSystem];
  self.directKeyButton.frame = CGRectMake(contentWidth - 110, 3, 110, 24);
  self.directKeyButton.backgroundColor = [UIColor colorWithWhite:0.22 alpha:1.0];
  self.directKeyButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];

  GCKeyCode currentDirect = self.stagedDirectKey;
  NSString *keyStr = getKeyName(currentDirect);
  [self.directKeyButton setTitle:(keyStr.length > 0 ? keyStr : @"-") forState:UIControlStateNormal];
  [self.directKeyButton addTarget:self action:@selector(mouseButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
  [directRow addSubview:self.directKeyButton];

  [self updateDirectKeyButtonStyle];

  y += 40;

  self.feedbackLabel = [[UILabel alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 0)];
  self.feedbackLabel.textAlignment = NSTextAlignmentCenter;
  self.feedbackLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
  self.feedbackLabel.alpha = 0;
  [self.sensitivityTab addSubview:self.feedbackLabel];

  self.sensitivityContentHeight = y;
  self.sensitivityTab.frame = CGRectMake(0, 0, 330, y);

  [self updateSensitivityFieldBorders];
}

- (void)createKeyRemapTab {
  self.keyRemapTab = [[UIView alloc]
      initWithFrame:CGRectMake(0, 0, 330,
                               2000)];

  CGFloat y = 16;
  CGFloat leftMargin = 20;
  CGFloat rightMargin = 20;
  CGFloat contentWidth = 330 - leftMargin - rightMargin;

  UILabel *title = [[UILabel alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 24)];
  title.text = @"Key Bindings";
  title.textColor = [UIColor whiteColor];
  title.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
  title.textAlignment = NSTextAlignmentCenter;
  [self.keyRemapTab addSubview:title];
  y += 32;

  UIView *descriptionBanner = [[UIView alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 58)];
  descriptionBanner.backgroundColor =
      [UIColor colorWithRed:0.2
                      green:0.6
                       blue:0.3
                      alpha:0.2];
  descriptionBanner.layer.cornerRadius = 8;
  [self.keyRemapTab addSubview:descriptionBanner];

  UILabel *descriptionLabel =
      [[UILabel alloc] initWithFrame:CGRectMake(8, 10, contentWidth - 16, 38)];
  descriptionLabel.text =
      @"Customize Fortnite controls and create advanced key remaps";
  descriptionLabel.textColor = [UIColor colorWithRed:0.6
                                               green:1.0
                                                blue:0.7
                                               alpha:1.0];
  descriptionLabel.font = [UIFont systemFontOfSize:13
                                            weight:UIFontWeightMedium];
  descriptionLabel.textAlignment = NSTextAlignmentCenter;
  descriptionLabel.numberOfLines = 2;
  [descriptionBanner addSubview:descriptionLabel];
  y += 74;

  self.applyChangesButton = [UIButton buttonWithType:UIButtonTypeSystem];
  self.applyChangesButton.frame = CGRectMake(leftMargin, y, contentWidth, 32);
  self.applyChangesButton.backgroundColor = [UIColor colorWithRed:0.0
                                                            green:0.47
                                                             blue:1.0
                                                            alpha:0.85];
  [self.applyChangesButton setTitle:@"Apply Changes (0)"
                           forState:UIControlStateNormal];
  [self.applyChangesButton setTitleColor:[UIColor whiteColor]
                                forState:UIControlStateNormal];
  self.applyChangesButton.titleLabel.font =
      [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
  self.applyChangesButton.layer.cornerRadius = 6;
  self.applyChangesButton.layer.borderWidth = 0.5;
  self.applyChangesButton.layer.borderColor =
      [UIColor colorWithRed:0.0 green:0.4 blue:0.9 alpha:0.6].CGColor;
  self.applyChangesButton.layer.shadowColor =
      [UIColor colorWithRed:0.0 green:0.3 blue:0.8 alpha:1.0].CGColor;
  self.applyChangesButton.layer.shadowOffset = CGSizeMake(0, 1);
  self.applyChangesButton.layer.shadowOpacity = 0.2;
  self.applyChangesButton.layer.shadowRadius = 1;
  self.applyChangesButton.enabled = NO;
  self.applyChangesButton.alpha = 0.5;
  [self.applyChangesButton addTarget:self
                              action:@selector(applyKeybindChangesTapped)
                    forControlEvents:UIControlEventTouchUpInside];
  [self.keyRemapTab addSubview:self.applyChangesButton];
  y += 38;

  self.discardKeybindsButton = [UIButton buttonWithType:UIButtonTypeSystem];
  self.discardKeybindsButton.frame =
      CGRectMake(leftMargin, y, contentWidth, 32);
  self.discardKeybindsButton.backgroundColor = [UIColor colorWithRed:1.0
                                                               green:0.9
                                                                blue:0.3
                                                               alpha:1.0];
  [self.discardKeybindsButton setTitle:@"Discard Changes (0)"
                              forState:UIControlStateNormal];
  [self.discardKeybindsButton setTitleColor:[UIColor blackColor]
                                   forState:UIControlStateNormal];
  self.discardKeybindsButton.titleLabel.font =
      [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
  self.discardKeybindsButton.layer.cornerRadius = 6;
  self.discardKeybindsButton.layer.borderWidth = 0.5;
  self.discardKeybindsButton.layer.borderColor =
      [UIColor colorWithRed:0.9 green:0.8 blue:0.2 alpha:0.6].CGColor;
  self.discardKeybindsButton.layer.shadowColor =
      [UIColor colorWithRed:0.8 green:0.7 blue:0.0 alpha:1.0].CGColor;
  self.discardKeybindsButton.layer.shadowOffset = CGSizeMake(0, 1);
  self.discardKeybindsButton.layer.shadowOpacity = 0.2;
  self.discardKeybindsButton.layer.shadowRadius = 1;
  self.discardKeybindsButton.enabled = NO;
  self.discardKeybindsButton.alpha = 0.3;
  [self.discardKeybindsButton addTarget:self
                                 action:@selector(discardKeybindChangesTapped)
                       forControlEvents:UIControlEventTouchUpInside];
  [self.keyRemapTab addSubview:self.discardKeybindsButton];
  y += 38;

  UIButton *resetAllButton = [UIButton buttonWithType:UIButtonTypeSystem];
  resetAllButton.frame = CGRectMake(leftMargin, y, contentWidth, 32);
  resetAllButton.backgroundColor = [UIColor colorWithRed:0.6
                                                   green:0.2
                                                    blue:0.2
                                                   alpha:0.5];
  [resetAllButton setTitle:@"Reset All to Defaults"
                  forState:UIControlStateNormal];
  [resetAllButton setTitleColor:[UIColor colorWithRed:1.0
                                                green:0.7
                                                 blue:0.7
                                                alpha:1.0]
                       forState:UIControlStateNormal];
  resetAllButton.titleLabel.font =
      [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
  resetAllButton.layer.cornerRadius = 6;
  resetAllButton.layer.borderWidth = 0.5;
  resetAllButton.layer.borderColor =
      [UIColor colorWithRed:0.5 green:0.25 blue:0.25 alpha:0.5].CGColor;
  [resetAllButton addTarget:self
                     action:@selector(resetAllKeybindsTapped)
           forControlEvents:UIControlEventTouchUpInside];
  [self.keyRemapTab addSubview:resetAllButton];
  y += 50;

  UIView *keybindsContainer =
      [[UIView alloc] initWithFrame:CGRectMake(leftMargin, y, contentWidth, 0)];
  keybindsContainer.tag = 9998;
  [self.keyRemapTab addSubview:keybindsContainer];

  CGFloat rowY = 0;

  NSArray *keybindCategories = @[
    @{
      @"title" : @"MOVEMENT",
      @"binds" : @[
        @{@"action" : @"Sprint", @"default" : @(225)},
        @{@"action" : @"Crouch", @"default" : @(224)},
        @{@"action" : @"Auto Walk", @"default" : @(46)}
      ]
    },
    @{
      @"title" : @"COMBAT",
      @"binds" : @[
        @{@"action" : @"Harvesting Tool", @"default" : @(9)},
        @{@"action" : @"Use", @"default" : @(8)},
        @{@"action" : @"Reload", @"default" : @(21)},
        @{@"action" : @"Weapon Slot 1", @"default" : @(30)},
        @{@"action" : @"Weapon Slot 2", @"default" : @(31)},
        @{@"action" : @"Weapon Slot 3", @"default" : @(32)},
        @{@"action" : @"Weapon Slot 4", @"default" : @(33)},
        @{@"action" : @"Weapon Slot 5", @"default" : @(34)}
      ]
    },
    @{
      @"title" : @"BUILDING",
      @"binds" : @[
        @{@"action" : @"Build", @"default" : @(20)},
        @{@"action" : @"Edit", @"default" : @(10)},
        @{@"action" : @"Wall", @"default" : @(29)},
        @{@"action" : @"Floor", @"default" : @(27)},
        @{@"action" : @"Stairs", @"default" : @(6)},
        @{@"action" : @"Roof", @"default" : @(25)},
        @{@"action" : @"Trap", @"default" : @(11)}
      ]
    },
    @{
      @"title" : @"INVENTORY",
      @"binds" : @[
        @{@"action" : @"Inventory", @"default" : @(43)},
        @{@"action" : @"Inventory Toggle", @"default" : @(226)}
      ]
    },
    @{
      @"title" : @"COMMUNICATION",
      @"binds" : @[
        @{@"action" : @"Emote", @"default" : @(5)},
        @{@"action" : @"Chat", @"default" : @(40)},
        @{@"action" : @"Push To Talk", @"default" : @(23)}
      ]
    },
    @{
      @"title" : @"NAVIGATION",
      @"binds" : @[
        @{@"action" : @"Map", @"default" : @(16)},
        @{@"action" : @"Escape", @"default" : @(41)}
      ]
    }
  ];

  for (NSDictionary *category in keybindCategories) {

    UILabel *categoryLabel =
        [[UILabel alloc] initWithFrame:CGRectMake(0, rowY, contentWidth, 20)];
    categoryLabel.text = category[@"title"];
    categoryLabel.textColor = [UIColor colorWithRed:0.5
                                              green:0.7
                                               blue:1.0
                                              alpha:1.0];
    categoryLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    categoryLabel.textAlignment = NSTextAlignmentLeft;
    [keybindsContainer addSubview:categoryLabel];
    rowY += 24;

    for (NSDictionary *bind in category[@"binds"]) {
      UIView *row = [self
          createFortniteKeybindRowWithAction:bind[@"action"]
                                  defaultKey:[bind[@"default"] integerValue]
                                    readOnly:[bind[@"readonly"] boolValue]
                                         atY:rowY
                                       width:contentWidth];
      [keybindsContainer addSubview:row];
      rowY += 36;
    }

    rowY += 8;
  }

  CGRect containerFrame = keybindsContainer.frame;
  containerFrame.size.height = rowY;
  keybindsContainer.frame = containerFrame;
  y += rowY + 16;

  UIView *divider = [[UIView alloc]
      initWithFrame:CGRectMake(leftMargin + 40, y, contentWidth - 80, 1)];
  divider.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.5];
  [self.keyRemapTab addSubview:divider];
  y += 16;

  UILabel *advancedLabel = [[UILabel alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 20)];
  advancedLabel.text = @"Advanced Custom Remaps";
  advancedLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
  advancedLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
  advancedLabel.textAlignment = NSTextAlignmentCenter;
  [self.keyRemapTab addSubview:advancedLabel];
  y += 28;

  UIView *remapContainer =
      [[UIView alloc] initWithFrame:CGRectMake(leftMargin, y, contentWidth, 0)];
  remapContainer.tag = 9999;
  [self.keyRemapTab addSubview:remapContainer];

  [self refreshKeyRemapRows];

  CGFloat containerHeight = remapContainer.frame.size.height;
  y += containerHeight + 16;

  self.addRemapButton = [UIButton buttonWithType:UIButtonTypeSystem];
  self.addRemapButton.frame = CGRectMake(leftMargin, y, contentWidth, 32);
  self.addRemapButton.backgroundColor = [UIColor colorWithWhite:0.25 alpha:0.5];
  [self.addRemapButton setTitle:@"+ Add Custom Remap"
                       forState:UIControlStateNormal];
  [self.addRemapButton setTitleColor:[UIColor whiteColor]
                            forState:UIControlStateNormal];
  self.addRemapButton.titleLabel.font =
      [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
  self.addRemapButton.layer.cornerRadius = 6;
  self.addRemapButton.layer.borderWidth = 0.5;
  self.addRemapButton.layer.borderColor =
      [UIColor colorWithWhite:0.4 alpha:0.4].CGColor;
  [self.addRemapButton addTarget:self
                          action:@selector(addKeyRemapTapped)
                forControlEvents:UIControlEventTouchUpInside];
  [self.keyRemapTab addSubview:self.addRemapButton];
  y += 32;

  UILabel *keyRemapFeedbackLabel = [[UILabel alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 0)];
  keyRemapFeedbackLabel.textAlignment = NSTextAlignmentCenter;
  keyRemapFeedbackLabel.font = [UIFont systemFontOfSize:13
                                                 weight:UIFontWeightSemibold];
  keyRemapFeedbackLabel.alpha = 0;
  keyRemapFeedbackLabel.tag = 8888;
  [self.keyRemapTab addSubview:keyRemapFeedbackLabel];
  y += 20;

  self.keyRemapContentHeight = y;

  [self recalculateKeyRemapContentHeight];
}

- (void)refreshKeyRemapRows {
  UIView *container = [self.keyRemapTab viewWithTag:9999];
  if (!container)
    return;

  for (UIView *subview in container.subviews) {
    [subview removeFromSuperview];
  }
  [self.keyRemapRows removeAllObjects];

  CGFloat y = 0;
  CGFloat contentWidth = 290;

  NSDictionary *mouseFortniteBindings = [[NSUserDefaults standardUserDefaults]
      dictionaryForKey:@"mouseFortniteBindings"];

  for (NSNumber *sourceKey in keyRemappings) {

    if ([sourceKey integerValue] >= MOUSE_BUTTON_MIDDLE) {
      if (mouseFortniteBindings[[sourceKey stringValue]] != nil) {
        continue;
      }
    }

    NSNumber *targetKey = keyRemappings[sourceKey];

    UIView *row = [self createKeyRemapRowWithSourceKey:[sourceKey integerValue]
                                             targetKey:[targetKey integerValue]
                                                   atY:y
                                                 width:contentWidth];
    [container addSubview:row];
    [self.keyRemapRows addObject:row];
    y += 50;
  }

  CGRect frame = container.frame;
  frame.size.height = y;
  container.frame = frame;

  [self repositionKeyRemapButtons];
}

- (void)repositionKeyRemapButtons {
  UIView *container = [self.keyRemapTab viewWithTag:9999];
  if (!container)
    return;

  CGFloat y = container.frame.origin.y + container.frame.size.height + 16;

  CGRect addFrame = self.addRemapButton.frame;
  addFrame.origin.y = y;
  self.addRemapButton.frame = addFrame;
  y += 46;

  UILabel *feedbackLabel = [self.keyRemapTab viewWithTag:8888];
  if (feedbackLabel) {
    CGRect feedbackFrame = feedbackLabel.frame;
    feedbackFrame.origin.y = y;
    feedbackLabel.frame = feedbackFrame;
    y += 30;
  }

  [self recalculateKeyRemapContentHeight];
}

- (UIView *)createKeyRemapRowWithSourceKey:(GCKeyCode)sourceKey
                                 targetKey:(GCKeyCode)targetKey
                                       atY:(CGFloat)y
                                     width:(CGFloat)width {
  UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0, y, width, 44)];
  row.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.6];
  row.layer.cornerRadius = 8;
  row.layer.borderWidth = 0.5;
  row.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:0.4].CGColor;

  UIButton *sourceButton = [UIButton buttonWithType:UIButtonTypeSystem];
  sourceButton.frame = CGRectMake(10, 7, 80, 30);
  sourceButton.backgroundColor = [UIColor colorWithWhite:0.28 alpha:0.7];
  [sourceButton setTitle:getKeyName(sourceKey) forState:UIControlStateNormal];
  [sourceButton setTitleColor:[UIColor whiteColor]
                     forState:UIControlStateNormal];
  sourceButton.titleLabel.font = [UIFont systemFontOfSize:13
                                                   weight:UIFontWeightMedium];
  sourceButton.layer.cornerRadius = 5;
  sourceButton.layer.borderWidth = 0.5;
  sourceButton.layer.borderColor =
      [UIColor colorWithWhite:0.35 alpha:0.5].CGColor;
  sourceButton.tag = sourceKey;
  [sourceButton addTarget:self
                   action:@selector(changeSourceKeyTapped:)
         forControlEvents:UIControlEventTouchUpInside];
  [row addSubview:sourceButton];

  UILabel *arrow = [[UILabel alloc] initWithFrame:CGRectMake(95, 7, 30, 30)];
  arrow.text = @"→";
  arrow.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
  arrow.font = [UIFont systemFontOfSize:18 weight:UIFontWeightLight];
  arrow.textAlignment = NSTextAlignmentCenter;
  [row addSubview:arrow];

  UIButton *targetButton = [UIButton buttonWithType:UIButtonTypeSystem];
  targetButton.frame = CGRectMake(130, 7, 80, 30);
  targetButton.backgroundColor = [UIColor colorWithWhite:0.32 alpha:0.7];
  [targetButton setTitle:getKeyName(targetKey) forState:UIControlStateNormal];
  [targetButton setTitleColor:[UIColor whiteColor]
                     forState:UIControlStateNormal];
  targetButton.titleLabel.font = [UIFont systemFontOfSize:13
                                                   weight:UIFontWeightMedium];
  targetButton.layer.cornerRadius = 5;
  targetButton.layer.borderWidth = 0.5;
  targetButton.layer.borderColor =
      [UIColor colorWithWhite:0.38 alpha:0.5].CGColor;
  targetButton.tag = sourceKey;
  [targetButton addTarget:self
                   action:@selector(changeTargetKeyTapped:)
         forControlEvents:UIControlEventTouchUpInside];
  [row addSubview:targetButton];

  UIButton *deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
  deleteButton.frame = CGRectMake(220, 7, 60, 30);
  deleteButton.backgroundColor = [UIColor colorWithRed:0.4
                                                 green:0.2
                                                  blue:0.2
                                                 alpha:0.6];
  [deleteButton setTitle:@"Delete" forState:UIControlStateNormal];
  [deleteButton setTitleColor:[UIColor colorWithRed:1.0
                                              green:0.7
                                               blue:0.7
                                              alpha:1.0]
                     forState:UIControlStateNormal];
  deleteButton.titleLabel.font = [UIFont systemFontOfSize:12
                                                   weight:UIFontWeightMedium];
  deleteButton.layer.cornerRadius = 5;
  deleteButton.layer.borderWidth = 0.5;
  deleteButton.layer.borderColor =
      [UIColor colorWithRed:0.5 green:0.25 blue:0.25 alpha:0.5].CGColor;
  deleteButton.tag = sourceKey;
  [deleteButton addTarget:self
                   action:@selector(deleteKeyRemapTapped:)
         forControlEvents:UIControlEventTouchUpInside];
  [row addSubview:deleteButton];

  return row;
}

- (UIView *)createFortniteKeybindRowWithAction:(NSString *)action
                                    defaultKey:(GCKeyCode)defaultKey
                                      readOnly:(BOOL)readOnly
                                           atY:(CGFloat)y
                                         width:(CGFloat)width {
  UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0, y, width, 30)];

  UIButton *resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
  resetButton.frame = CGRectMake(0, 5, 20, 20);
  [resetButton setTitle:@"↪️" forState:UIControlStateNormal];
  resetButton.titleLabel.font = [UIFont systemFontOfSize:14];
  resetButton.accessibilityLabel = action;
  resetButton.tag = defaultKey;
  [resetButton addTarget:self
                  action:@selector(resetKeybindTapped:)
        forControlEvents:UIControlEventTouchUpInside];
  [row addSubview:resetButton];

  UILabel *actionLabel =
      [[UILabel alloc] initWithFrame:CGRectMake(24, 5, width - 140, 20)];
  actionLabel.text = action;
  actionLabel.textColor = [UIColor colorWithWhite:0.85 alpha:1.0];
  actionLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
  actionLabel.textAlignment = NSTextAlignmentLeft;
  [row addSubview:actionLabel];

  GCKeyCode currentKey = [self getCurrentKeyForAction:action
                                           defaultKey:defaultKey];
  BOOL isStaged = [self.stagedKeybinds objectForKey:action] != nil;
  BOOL isCustomSaved = [self isActionCustomSaved:action defaultKey:defaultKey];
  BOOL isUnbound = (currentKey == 0);

  UIButton *keyButton = [UIButton buttonWithType:UIButtonTypeSystem];
  keyButton.frame = CGRectMake(width - 110, 3, 110, 24);
  keyButton.backgroundColor = [UIColor colorWithWhite:0.22 alpha:1.0];
  keyButton.layer.cornerRadius = 4;
  keyButton.accessibilityLabel = action;
  keyButton.tag = defaultKey;
  keyButton.enabled = !readOnly;

  UIColor *borderColor;
  if (isUnbound) {

    [keyButton setTitle:@"[Unbound]" forState:UIControlStateNormal];
    [keyButton setTitleColor:[UIColor colorWithRed:1.0
                                             green:0.3
                                              blue:0.3
                                             alpha:1.0]
                    forState:UIControlStateNormal];
    borderColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:1.0];
  } else if (isStaged) {

    [keyButton setTitle:getKeyName(currentKey) forState:UIControlStateNormal];
    [keyButton setTitleColor:[UIColor colorWithRed:1.0
                                             green:0.9
                                              blue:0.2
                                             alpha:1.0]
                    forState:UIControlStateNormal];
    borderColor = [UIColor colorWithRed:0.8 green:0.7 blue:0.0 alpha:1.0];
  } else if (isCustomSaved) {

    [keyButton setTitle:getKeyName(currentKey) forState:UIControlStateNormal];
    [keyButton setTitleColor:[UIColor whiteColor]
                    forState:UIControlStateNormal];
    borderColor = [UIColor colorWithWhite:0.65 alpha:1.0];
  } else {

    [keyButton setTitle:getKeyName(currentKey) forState:UIControlStateNormal];
    [keyButton setTitleColor:[UIColor colorWithWhite:0.6 alpha:1.0]
                    forState:UIControlStateNormal];
    borderColor = [UIColor colorWithWhite:0.35 alpha:1.0];
  }

  if (readOnly) {
    keyButton.alpha = 0.5;
  } else {
    [keyButton addTarget:self
                  action:@selector(fortniteKeybindTapped:)
        forControlEvents:UIControlEventTouchUpInside];
  }

  keyButton.titleLabel.font = [UIFont systemFontOfSize:12
                                                weight:UIFontWeightSemibold];
  [row addSubview:keyButton];
  setShapeBorder(keyButton, 4, 0.5, borderColor);

  return row;
}

- (GCKeyCode)getCurrentKeyForAction:(NSString *)action
                         defaultKey:(GCKeyCode)defaultKey {

  NSNumber *stagedKey = self.stagedKeybinds[action];
  if (stagedKey) {
    return [stagedKey integerValue];
  }

  NSNumber *savedKey = [self getSavedKeyForAction:action];
  if (savedKey) {
    return [savedKey integerValue];
  }

  NSDictionary *mouseBindings = [[NSUserDefaults standardUserDefaults]
      dictionaryForKey:@"mouseFortniteBindings"];
  for (NSString *codeString in mouseBindings) {
    if ([[mouseBindings objectForKey:codeString] integerValue] ==
        (NSInteger)defaultKey)
      return (GCKeyCode)[codeString intValue];
  }

  return defaultKey;
}

- (BOOL)isActionCustomSaved:(NSString *)action
                 defaultKey:(GCKeyCode)defaultKey {
  NSNumber *savedKey = [self getSavedKeyForAction:action];
  if (savedKey && [savedKey integerValue] != defaultKey)
    return YES;

  NSDictionary *mouseBindings = [[NSUserDefaults standardUserDefaults]
      dictionaryForKey:@"mouseFortniteBindings"];
  for (NSString *codeString in mouseBindings) {
    if ([[mouseBindings objectForKey:codeString] integerValue] ==
        (NSInteger)defaultKey)
      return YES;
  }
  return NO;
}

- (NSNumber *)getSavedKeyForAction:(NSString *)action {

  NSDictionary *savedBindings = [[NSUserDefaults standardUserDefaults]
      dictionaryForKey:@"fortniteKeybinds"];
  return savedBindings[action];
}

- (void)fortniteKeybindTapped:(UIButton *)sender {
  NSString *actionName = sender.accessibilityLabel;

  UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:actionName
                       message:@"Press any key or click a mouse button to bind it"
                preferredStyle:UIAlertControllerStyleAlert];

  [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

  ignoreNextLeftClickCount = 1;
  [self presentViewController:alert animated:YES completion:^{
    __weak typeof(self) weakSelf = self;

    void (^handleCapturedInput)(int) = ^(int code) {
      dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        keyCaptureCallback = nil;
        mouseButtonCaptureCallback = nil;

        [strongSelf.presentedViewController dismissViewControllerAnimated:YES completion:^{
          NSString *conflict = [strongSelf findAnyConflictDescriptionForCode:code];
          if (conflict) {
            UIAlertController *cnf = [UIAlertController
                alertControllerWithTitle:@"Key Conflict"
                                 message:[NSString stringWithFormat:@"%@ is already bound to %@. Continue?", getKeyName((GCKeyCode)code), (NSString *)conflict]
                          preferredStyle:UIAlertControllerStyleAlert];
            [cnf addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [cnf addAction:[UIAlertAction actionWithTitle:@"Continue Anyway" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
              [strongSelf resolveConflictForCode:code];
              [strongSelf stageKeybindChange:actionName newKey:(GCKeyCode)code];
              [strongSelf refreshFortniteKeybindButtonForAction:actionName];
            }]];
            [strongSelf presentViewController:cnf animated:YES completion:nil];
          } else {
            [strongSelf stageKeybindChange:actionName newKey:(GCKeyCode)code];
            [strongSelf refreshFortniteKeybindButtonForAction:actionName];
          }
        }];
      });
    };

    keyCaptureCallback = ^(GCKeyCode kc) {
        if (kc == 57) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) return;
                UIAlertController *err = [UIAlertController
                    alertControllerWithTitle:@"Invalid Key"
                                     message:@"Caps Lock is reserved for Typing Mode"
                              preferredStyle:UIAlertControllerStyleAlert];
                [err addAction:[UIAlertAction actionWithTitle:@"OK"
                                                        style:UIAlertActionStyleDefault
                                                      handler:nil]];
                [strongSelf presentViewController:err animated:YES completion:nil];
            });
            return;
        }
        handleCapturedInput((int)kc);
    };
    mouseButtonCaptureCallback = ^(int mc) { handleCapturedInput(mc); };
  }];
}

- (void)resolveConflictForCode:(int)code {
  if (code == 0) return;

  BOOL keyboardChanged = NO;
  BOOL controllerChanged = NO;
  BOOL sensitivityChanged = NO;

  NSString *fnAction = [self findActionUsingKey:(GCKeyCode)code excludingAction:nil];
  if (fnAction) {
    self.stagedKeybinds[fnAction] = @(0);
    [self refreshFortniteKeybindButtonForAction:fnAction];
    keyboardChanged = YES;
  }

  for (NSInteger i = 0; i < FnCtrlButtonCount; i++) {

    int currentMapping = 0;
    if (self.stagedControllerMappings[@(i)]) {
      currentMapping = [self.stagedControllerMappings[@(i)] intValue];
    } else {
      currentMapping = controllerMappingArray[i];
    }

    if (currentMapping == code) {
      self.stagedControllerMappings[@(i)] = @(0);
      controllerChanged = YES;
    }
  }
  if (controllerChanged) {
    [self refreshControllerBindRows];
    [self updateControllerApplyButton];
  }

  if (keyboardChanged) {
    [self updateApplyChangesButton];
  }

  BOOL remapsChanged = NO;
  for (NSNumber *srcKey in [keyRemappings allKeys]) {
    if ([srcKey integerValue] == code) {
      [keyRemappings removeObjectForKey:srcKey];
      remapsChanged = YES;
    }
    else if ([keyRemappings[srcKey] integerValue] == code) {
      [keyRemappings removeObjectForKey:srcKey];
      remapsChanged = YES;
    }
  }
  if (remapsChanged) {
    saveKeyRemappings();
    [self refreshKeyRemapRows];
  }

  GCKeyCode currentDirect = (self.stagedDirectKey != 0) ? self.stagedDirectKey : self.originalDirectKey;
  if ((int)currentDirect == code) {
    self.stagedDirectKey = 0;
    self.originalDirectKey = 0;
    [self updateDirectKeyButtonStyle];
    [self.directKeyButton setTitle:@"-" forState:UIControlStateNormal];
    sensitivityChanged = YES;
  }
  if (sensitivityChanged) {
    [self updateSensitivityDiscardButton];
  }

  if (keyboardChanged) {
    [self applyKeybindChangesTapped];
  }
  if (controllerChanged) {
    [self applyControllerChangesTapped];
  }
  if (sensitivityChanged) {
    [self saveButtonTapped:nil];
  }
}

- (NSString *)findActionUsingKey:(GCKeyCode)keyCode
                 excludingAction:(NSString *)excludeAction {

  NSArray *allActions = [self getAllFortniteActions];

  for (NSDictionary *actionInfo in allActions) {
    NSString *action = actionInfo[@"action"];
    if ([action isEqualToString:excludeAction])
      continue;

    GCKeyCode defaultKey = [actionInfo[@"default"] integerValue];
    GCKeyCode currentKey = [self getCurrentKeyForAction:action
                                             defaultKey:defaultKey];

    if (currentKey == keyCode) {
      return action;
    }
  }

  return nil;
}

- (NSString *)findCustomRemapUsingKey:(GCKeyCode)keyCode {

  NSNumber *targetKey = keyRemappings[@(keyCode)];
  if (targetKey) {
    return [NSString stringWithFormat:@"%@ → %@", getKeyName(keyCode),
                                      getKeyName([targetKey integerValue])];
  }

  for (NSNumber *sourceKey in keyRemappings) {
    NSNumber *target = keyRemappings[sourceKey];
    if ([target integerValue] == keyCode) {
      return [NSString stringWithFormat:@"%@ → %@",
                                        getKeyName([sourceKey integerValue]),
                                        getKeyName(keyCode)];
    }
  }

  return nil;
}

- (NSString *)findControllerMappingUsingKey:(int)keyCode {
  NSArray *ctrlButtonNames = @[
    @"Left Trigger", @"Right Trigger", @"Left Shoulder", @"Right Shoulder",
    @"Button A", @"Button B", @"Button X", @"Button Y",
    @"Left Stick Click", @"Right Stick Click", @"Menu", @"Options",
    @"D-Pad Up", @"D-Pad Down", @"D-Pad Left", @"D-Pad Right",
    @"Left Stick Up", @"Left Stick Down", @"Left Stick Left", @"Left Stick Right",
    @"Right Stick Up", @"Right Stick Down", @"Right Stick Left", @"Right Stick Right"
  ];

  for (NSNumber *btnIdxNum in self.stagedControllerMappings) {
    if ([self.stagedControllerMappings[btnIdxNum] intValue] == keyCode) {
      NSInteger idx = [btnIdxNum integerValue];
      if (idx >= 0 && idx < ctrlButtonNames.count) {
        return [NSString stringWithFormat:@"Controller %@", ctrlButtonNames[idx]];
      }
      return @"Controller Mapping";
    }
  }

  for (int i = 0; i < FnCtrlButtonCount; i++) {

    if (self.stagedControllerMappings[@(i)] == nil) {
      if (controllerMappingArray[i] == keyCode) {
        if (i >= 0 && i < ctrlButtonNames.count) {
           return [NSString stringWithFormat:@"Controller %@", ctrlButtonNames[i]];
        }
        return @"Controller Mapping";
      }
    }
  }

  return nil;
}

- (NSString *)findAnyConflictDescriptionForCode:(int)code {
    if (code == 0) return nil;

    NSString *fnConflict = [self findActionUsingKey:(GCKeyCode)code excludingAction:nil];
    if (fnConflict) return fnConflict;

    if (keyRemappings[@(code)]) {
        return [NSString stringWithFormat:@"Custom Remap (Source)"];
    }

    for (NSNumber *src in keyRemappings) {
        if ([keyRemappings[src] intValue] == code) {
            return [NSString stringWithFormat:@"Custom Remap (Target)"];
        }
    }

    NSString *ctrlConflict = [self findControllerMappingUsingKey:code];
    if (ctrlConflict) return ctrlConflict;

    if (self.stagedDirectKey != 0 && (int)self.stagedDirectKey == code) {
        return @"Sensitivity GCMouseInput Toggle";
    }

    return nil;
}

- (NSString *)findFortniteActionUsingKey:(GCKeyCode)keyCode {
  NSArray *allActions = [self getAllFortniteActions];

  for (NSDictionary *actionInfo in allActions) {
    NSString *action = actionInfo[@"action"];
    GCKeyCode defaultKey = [actionInfo[@"default"] integerValue];
    GCKeyCode currentKey = [self getCurrentKeyForAction:action
                                             defaultKey:defaultKey];

    if (currentKey == keyCode) {
      return action;
    }
  }

  return nil;
}

- (NSArray *)getAllFortniteActions {
  return self.cachedFortniteActions;
}

- (void)refreshFortniteKeybindButtonForAction:(NSString *)action {

  void (^applyStyle)(UIButton *) = ^(UIButton *btn) {
    GCKeyCode defKey = (GCKeyCode)btn.tag;
    GCKeyCode currentKey = [self getCurrentKeyForAction:action defaultKey:defKey];
    BOOL isStaged = [self.stagedKeybinds objectForKey:action] != nil;
    BOOL isCustomSaved = [self isActionCustomSaved:action defaultKey:defKey];
    BOOL isUnbound = (currentKey == 0);
    UIColor *borderColor;
    if (isUnbound) {
      [btn setTitle:@"[Unbound]" forState:UIControlStateNormal];
      [btn setTitleColor:[UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:1.0]
               forState:UIControlStateNormal];
      borderColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:1.0];
    } else if (isStaged) {
      [btn setTitle:getKeyName(currentKey) forState:UIControlStateNormal];
      [btn setTitleColor:[UIColor colorWithRed:1.0 green:0.9 blue:0.2 alpha:1.0]
               forState:UIControlStateNormal];
      borderColor = [UIColor colorWithRed:0.8 green:0.7 blue:0.0 alpha:1.0];
    } else if (isCustomSaved) {
      [btn setTitle:getKeyName(currentKey) forState:UIControlStateNormal];
      [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
      borderColor = [UIColor colorWithWhite:0.65 alpha:1.0];
    } else {
      [btn setTitle:getKeyName(currentKey) forState:UIControlStateNormal];
      [btn setTitleColor:[UIColor colorWithWhite:0.6 alpha:1.0]
               forState:UIControlStateNormal];
      borderColor = [UIColor colorWithWhite:0.35 alpha:1.0];
    }
    setShapeBorder(btn, 4, 0.5, borderColor);
  };

  for (UIView *container in self.keyRemapTab.subviews) {
    for (UIView *row in container.subviews) {
      for (UIView *child in row.subviews) {
        if (![child isKindOfClass:[UIButton class]]) continue;
        UIButton *btn = (UIButton *)child;

        if (btn.frame.size.width < 50) continue;
        if ([btn.accessibilityLabel isEqualToString:action]) {
          applyStyle(btn);
          return;
        }
      }
    }
  }
}

- (void)stageKeybindChange:(NSString *)action newKey:(GCKeyCode)newKey {

  [self resolveConflictForCode:(int)newKey];

  GCKeyCode currentEffective = [self getCurrentKeyForAction:action defaultKey:0];
  if (currentEffective == newKey) {
    [self.stagedKeybinds removeObjectForKey:action];
  } else {

    self.stagedKeybinds[action] = @(newKey);
  }

  [self updateApplyChangesButton];
}

- (void)updateApplyChangesButton {
  NSInteger changeCount = self.stagedKeybinds.count;

  [self.applyChangesButton
      setTitle:[NSString
                   stringWithFormat:@"Apply Changes (%ld)", (long)changeCount]
      forState:UIControlStateNormal];
  [self.discardKeybindsButton
      setTitle:[NSString
                   stringWithFormat:@"Discard Changes (%ld)", (long)changeCount]
      forState:UIControlStateNormal];

  if (changeCount > 0) {

    self.applyChangesButton.enabled = YES;
    self.discardKeybindsButton.enabled = YES;
    [UIView animateWithDuration:0.2
                     animations:^{
                       self.applyChangesButton.alpha = 1.0;
                       self.discardKeybindsButton.alpha =
                           1.0;
                     }];
  } else {

    self.applyChangesButton.enabled = NO;
    self.discardKeybindsButton.enabled = NO;
    [UIView animateWithDuration:0.2
                     animations:^{
                       self.applyChangesButton.alpha = 0.5;
                       self.discardKeybindsButton.alpha =
                           0.3;
                     }];
  }
}

- (void)applyKeybindChangesTapped {
  if (self.stagedKeybinds.count == 0)
    return;

  NSMutableDictionary *savedBindings = [[[NSUserDefaults standardUserDefaults]
      dictionaryForKey:@"fortniteKeybinds"] mutableCopy];
  if (!savedBindings)
    savedBindings = [NSMutableDictionary dictionary];

  for (NSString *action in self.stagedKeybinds) {
    NSNumber *newKey = self.stagedKeybinds[action];

    NSNumber *defaultKeyNum = self.actionToDefaultKeyMap[action];
    GCKeyCode defaultKey = defaultKeyNum ? [defaultKeyNum integerValue] : 0;

    if ([newKey integerValue] == defaultKey) {
      [savedBindings removeObjectForKey:action];
    } else {
      savedBindings[action] = newKey;
    }
  }

  [[NSUserDefaults standardUserDefaults] setObject:savedBindings
                                            forKey:@"fortniteKeybinds"];

  loadFortniteKeybinds();

  [self.stagedKeybinds removeAllObjects];

  [self refreshFortniteKeybinds];
  [self updateApplyChangesButton];

  [self showFeedback:@"Keybinds Applied & Saved"
               color:[UIColor colorWithRed:0.3 green:0.9 blue:0.3 alpha:1.0]];
}

- (void)discardKeybindChangesTapped {
  if (self.stagedKeybinds.count == 0)
    return;

  [self.stagedKeybinds removeAllObjects];

  [self refreshFortniteKeybinds];
  [self updateApplyChangesButton];

  [self showFeedback:@"Changes Discarded"
               color:[UIColor colorWithRed:1.0 green:0.9 blue:0.3 alpha:1.0]];
}

- (void)resetKeybindTapped:(UIButton *)sender {
  NSString *action = sender.accessibilityLabel;
  GCKeyCode defaultKey = sender.tag;

  NSString *conflictAction = [self findActionUsingKey:defaultKey
                                      excludingAction:action];

  if (conflictAction) {

    NSString *message = [NSString
        stringWithFormat:@"Resetting %@ to %@ will conflict with %@. Continue?",
                         action, getKeyName(defaultKey), conflictAction];
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Key Conflict"
                         message:message
                  preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert
        addAction:[UIAlertAction
                      actionWithTitle:@"Reset Anyway"
                                style:UIAlertActionStyleDestructive
                              handler:^(UIAlertAction *_Nonnull alertAction) {
                                [self performResetForAction:action
                                                 defaultKey:defaultKey];
                              }]];

    [self presentViewController:alert animated:YES completion:nil];
  } else {

    [self performResetForAction:action defaultKey:defaultKey];
  }
}

- (void)stageMouseButtonKeybind:(int)mouseCode
                      forAction:(NSString *)actionName {

  GCKeyCode defaultKey = 0;
  for (NSDictionary *info in self.cachedFortniteActions) {
    if ([info[@"action"] isEqualToString:actionName]) {
      defaultKey = [info[@"default"] integerValue];
      break;
    }
  }
  if (defaultKey == 0)
    return;

  GCKeyCode effectiveKey = [self getCurrentKeyForAction:actionName
                                             defaultKey:defaultKey];

  if (effectiveKey >= MOUSE_BUTTON_MIDDLE)
    effectiveKey = defaultKey;
  if (effectiveKey == 0)
    return;

  [self clearMouseBindingForAction:actionName];

  [keyRemappings removeObjectForKey:@(mouseCode)];

  keyRemappings[@(mouseCode)] = @(effectiveKey);
  saveKeyRemappings();

  NSMutableDictionary *mouseBindings = [[[NSUserDefaults standardUserDefaults]
      dictionaryForKey:@"mouseFortniteBindings"] mutableCopy];
  if (!mouseBindings)
    mouseBindings = [NSMutableDictionary dictionary];
  mouseBindings[[@(mouseCode) stringValue]] =
      @(defaultKey);
  [[NSUserDefaults standardUserDefaults] setObject:mouseBindings
                                            forKey:@"mouseFortniteBindings"];
  [[NSUserDefaults standardUserDefaults] synchronize];

  self.stagedKeybinds[actionName] = @(mouseCode);
  [self updateApplyChangesButton];
}

- (void)clearMouseBindingForAction:(NSString *)actionName {
  NSMutableDictionary *mouseBindings = [[[NSUserDefaults standardUserDefaults]
      dictionaryForKey:@"mouseFortniteBindings"] mutableCopy];
  if (!mouseBindings)
    return;

  NSMutableArray *toRemove = [NSMutableArray array];
  for (NSString *codeString in mouseBindings) {

    GCKeyCode storedDefault =
        (GCKeyCode)[[mouseBindings objectForKey:codeString] integerValue];
    GCKeyCode actionDefault = 0;
    for (NSDictionary *info in self.cachedFortniteActions) {
      if ([info[@"action"] isEqualToString:actionName]) {
        actionDefault = [info[@"default"] integerValue];
        break;
      }
    }
    if (storedDefault == actionDefault && actionDefault != 0) {
      [toRemove addObject:codeString];

      int mouseCode = [codeString intValue];
      [keyRemappings removeObjectForKey:@(mouseCode)];
    }
  }
  if (toRemove.count == 0)
    return;
  for (NSString *key in toRemove)
    [mouseBindings removeObjectForKey:key];
  [[NSUserDefaults standardUserDefaults] setObject:mouseBindings
                                            forKey:@"mouseFortniteBindings"];
  [[NSUserDefaults standardUserDefaults] synchronize];
  saveKeyRemappings();
}

- (void)performResetForAction:(NSString *)action
                   defaultKey:(GCKeyCode)defaultKey {

  [self.stagedKeybinds removeObjectForKey:action];

  [self clearMouseBindingForAction:action];

  NSMutableDictionary *savedBindings = [[[NSUserDefaults standardUserDefaults]
      dictionaryForKey:@"fortniteKeybinds"] mutableCopy];
  if (savedBindings) {
    [savedBindings removeObjectForKey:action];
    [[NSUserDefaults standardUserDefaults] setObject:savedBindings
                                              forKey:@"fortniteKeybinds"];
  }

  loadFortniteKeybinds();

  [self refreshFortniteKeybinds];
  [self updateApplyChangesButton];

  [self showFeedback:[NSString stringWithFormat:@"%@ reset to %@", action,
                                                getKeyName(defaultKey)]
               color:[UIColor colorWithRed:0.3 green:0.9 blue:0.3 alpha:1.0]];
}

- (void)resetAllKeybindsTapped {
  UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:@"Reset All Keybinds?"
                       message:@"This will clear all custom keybinds and "
                               @"restore Fortnite defaults"
                preferredStyle:UIAlertControllerStyleAlert];

  [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];
  [alert
      addAction:[UIAlertAction
                    actionWithTitle:@"Reset All"
                              style:UIAlertActionStyleDestructive
                            handler:^(UIAlertAction *_Nonnull action) {

                              [self.stagedKeybinds removeAllObjects];

                              [[NSUserDefaults standardUserDefaults]
                                  removeObjectForKey:@"fortniteKeybinds"];

                              [[NSUserDefaults standardUserDefaults]
                                  removeObjectForKey:@"mouseFortniteBindings"];

                              [[NSUserDefaults standardUserDefaults]
                                  removeObjectForKey:kKeyRemapKey];

                              [keyRemappings removeAllObjects];

                              loadFortniteKeybinds();

                              loadKeyRemappings();

                              [self refreshFortniteKeybinds];
                              [self refreshKeyRemapRows];
                              [self updateApplyChangesButton];

                              [self
                                  showFeedback:@"All keybinds reset to defaults"
                                         color:[UIColor colorWithRed:0.3
                                                               green:0.9
                                                                blue:0.3
                                                               alpha:1.0]];
                            }]];

  [self presentViewController:alert animated:YES completion:nil];
}

- (void)refreshFortniteKeybinds {
  UIView *container = [self.keyRemapTab viewWithTag:9998];
  if (!container)
    return;

  for (UIView *subview in container.subviews) {
    [subview removeFromSuperview];
  }

  CGFloat rowY = 0;
  CGFloat contentWidth = 290;

  NSArray *keybindCategories = @[
    @{
      @"title" : @"MOVEMENT",
      @"binds" : @[
        @{@"action" : @"Sprint", @"default" : @(225)},
        @{@"action" : @"Crouch", @"default" : @(224)},
        @{@"action" : @"Auto Walk", @"default" : @(46)}
      ]
    },
    @{
      @"title" : @"COMBAT",
      @"binds" : @[
        @{@"action" : @"Harvesting Tool", @"default" : @(9)},
        @{@"action" : @"Use", @"default" : @(8)},
        @{@"action" : @"Reload", @"default" : @(21)},
        @{@"action" : @"Weapon Slot 1", @"default" : @(30)},
        @{@"action" : @"Weapon Slot 2", @"default" : @(31)},
        @{@"action" : @"Weapon Slot 3", @"default" : @(32)},
        @{@"action" : @"Weapon Slot 4", @"default" : @(33)},
        @{@"action" : @"Weapon Slot 5", @"default" : @(34)}
      ]
    },
    @{
      @"title" : @"BUILDING",
      @"binds" : @[
        @{@"action" : @"Build", @"default" : @(20)},
        @{@"action" : @"Edit", @"default" : @(10)},
        @{@"action" : @"Wall", @"default" : @(29)},
        @{@"action" : @"Floor", @"default" : @(27)},
        @{@"action" : @"Stairs", @"default" : @(6)},
        @{@"action" : @"Roof", @"default" : @(25)},
        @{@"action" : @"Trap", @"default" : @(11)}
      ]
    },
    @{
      @"title" : @"INVENTORY",
      @"binds" : @[
        @{@"action" : @"Inventory", @"default" : @(43)},
        @{@"action" : @"Inventory Toggle", @"default" : @(226)}
      ]
    },
    @{
      @"title" : @"COMMUNICATION",
      @"binds" : @[
        @{@"action" : @"Emote", @"default" : @(5)},
        @{@"action" : @"Chat", @"default" : @(40)},
        @{@"action" : @"Push To Talk", @"default" : @(23)}
      ]
    },
    @{
      @"title" : @"NAVIGATION",
      @"binds" : @[
        @{@"action" : @"Map", @"default" : @(16)},
        @{@"action" : @"Escape", @"default" : @(41)}
      ]
    }
  ];

  for (NSDictionary *category in keybindCategories) {

    UILabel *categoryLabel =
        [[UILabel alloc] initWithFrame:CGRectMake(0, rowY, contentWidth, 20)];
    categoryLabel.text = category[@"title"];
    categoryLabel.textColor = [UIColor colorWithRed:0.5
                                              green:0.7
                                               blue:1.0
                                              alpha:1.0];
    categoryLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    categoryLabel.textAlignment = NSTextAlignmentLeft;
    [container addSubview:categoryLabel];
    rowY += 24;

    for (NSDictionary *bind in category[@"binds"]) {
      UIView *row = [self
          createFortniteKeybindRowWithAction:bind[@"action"]
                                  defaultKey:[bind[@"default"] integerValue]
                                    readOnly:[bind[@"readonly"] boolValue]
                                         atY:rowY
                                       width:contentWidth];
      [container addSubview:row];
      rowY += 36;
    }

    rowY += 8;
  }

  CGRect frame = container.frame;
  frame.size.height = rowY;
  container.frame = frame;

  [self recalculateKeyRemapContentHeight];
}

- (void)recalculateKeyRemapContentHeight {

  if (!self.addRemapButton)
    return;

  CGFloat y = self.addRemapButton.frame.origin.y;
  y += 32;
  y += 20;

  self.keyRemapContentHeight = y;

  CGRect tabFrame = self.keyRemapTab.frame;
  tabFrame.size.height = self.keyRemapContentHeight;
  self.keyRemapTab.frame = tabFrame;

  if (self.currentTab == PopupTabKeyRemap) {
    self.scrollView.contentSize = CGSizeMake(330, self.keyRemapContentHeight);
  }
}

- (void)sensitivityTabTapped {
  [self switchToTab:PopupTabSensitivity];
}

- (void)switchToControllerTab {
  [self switchToTab:PopupTabController];
}

- (void)controllerTabTapped {
  [self switchToTab:PopupTabController];
}

- (void)keyRemapTabTapped {
  [self switchToTab:PopupTabKeyRemap];
}

- (void)containerTabTapped {
  [self switchToTab:PopupTabContainer];
}

- (void)createContainerTab {
  self.containerTab = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 330, 510)];
  self.containerTab.backgroundColor = [UIColor clearColor];

  CGFloat y = 16;
  CGFloat leftMargin = 20;
  CGFloat rightMargin = 20;
  CGFloat contentWidth = 330 - leftMargin - rightMargin;

  UILabel *title = [[UILabel alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 24)];
  title.text = @"Container Settings";
  title.textColor = [UIColor whiteColor];
  title.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
  title.textAlignment = NSTextAlignmentCenter;
  [self.containerTab addSubview:title];
  y += 32;

  UIView *instructionBanner = [[UIView alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 76)];
  instructionBanner.backgroundColor = [UIColor colorWithRed:0.6
                                                      green:0.2
                                                       blue:0.8
                                                      alpha:0.2];
  instructionBanner.layer.cornerRadius = 8;
  [self.containerTab addSubview:instructionBanner];

  UILabel *instruction =
      [[UILabel alloc] initWithFrame:CGRectMake(8, 10, contentWidth - 16, 56)];
  instruction.text = @"Link tweak to your game container\nSelect Fortnite data "
                     @"folder below\nApp will restart after selection";
  instruction.textColor = [UIColor colorWithRed:0.8
                                          green:0.6
                                           blue:1.0
                                          alpha:1.0];
  instruction.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
  instruction.textAlignment = NSTextAlignmentCenter;
  instruction.numberOfLines = 3;
  [instructionBanner addSubview:instruction];
  y += 92;

  UIButton *folderButton = [UIButton buttonWithType:UIButtonTypeSystem];
  folderButton.frame = CGRectMake(leftMargin, y, contentWidth, 44);
  folderButton.backgroundColor = [UIColor colorWithRed:0.5
                                                 green:0.2
                                                  blue:0.7
                                                 alpha:0.85];
  [folderButton setTitle:@"Select Fortnite Data Folder"
                forState:UIControlStateNormal];
  [folderButton setTitleColor:[UIColor whiteColor]
                     forState:UIControlStateNormal];
  folderButton.titleLabel.font = [UIFont systemFontOfSize:13
                                                   weight:UIFontWeightMedium];
  folderButton.layer.cornerRadius = 6;
  folderButton.layer.borderWidth = 0.5;
  folderButton.layer.borderColor =
      [UIColor colorWithRed:0.4 green:0.15 blue:0.6 alpha:0.6].CGColor;

  folderButton.layer.shadowColor =
      [UIColor colorWithRed:0.4 green:0.1 blue:0.6 alpha:1.0].CGColor;
  folderButton.layer.shadowOffset = CGSizeMake(0, 1);
  folderButton.layer.shadowOpacity = 0.2;
  folderButton.layer.shadowRadius = 1;
  folderButton.userInteractionEnabled = YES;
  [folderButton addTarget:self
                   action:@selector(selectFolderTapped:)
         forControlEvents:UIControlEventTouchUpInside];
  [self.containerTab addSubview:folderButton];
  y += 44;
  y += 16;

  UIView *divider1 = [[UIView alloc]
      initWithFrame:CGRectMake(leftMargin + 40, y, contentWidth - 80, 1)];
  divider1.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.5];
  [self.containerTab addSubview:divider1];
  y += 16;

  UILabel *importExportLabel = [[UILabel alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 20)];
  importExportLabel.text = @"Settings Import/Export";
  importExportLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
  importExportLabel.font = [UIFont systemFontOfSize:13
                                             weight:UIFontWeightMedium];
  importExportLabel.textAlignment = NSTextAlignmentCenter;
  [self.containerTab addSubview:importExportLabel];
  y += 28;

  UILabel *importExportDesc = [[UILabel alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 32)];
  importExportDesc.text = @"Share your sensitivity and keybind settings";
  importExportDesc.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
  importExportDesc.font = [UIFont systemFontOfSize:11
                                            weight:UIFontWeightMedium];
  importExportDesc.textAlignment = NSTextAlignmentCenter;
  importExportDesc.numberOfLines = 2;
  [self.containerTab addSubview:importExportDesc];
  y += 40;

  UIButton *exportButton = [UIButton buttonWithType:UIButtonTypeSystem];
  exportButton.frame = CGRectMake(leftMargin, y, contentWidth, 36);
  exportButton.backgroundColor = [UIColor colorWithRed:0.0
                                                 green:0.47
                                                  blue:1.0
                                                 alpha:0.85];
  [exportButton setTitle:@"Export Settings 📤" forState:UIControlStateNormal];
  [exportButton setTitleColor:[UIColor whiteColor]
                     forState:UIControlStateNormal];
  exportButton.titleLabel.font = [UIFont systemFontOfSize:13
                                                   weight:UIFontWeightSemibold];
  exportButton.layer.cornerRadius = 6;
  exportButton.layer.borderWidth = 0.5;
  exportButton.layer.borderColor =
      [UIColor colorWithRed:0.0 green:0.4 blue:0.9 alpha:0.6].CGColor;
  exportButton.layer.shadowColor =
      [UIColor colorWithRed:0.0 green:0.3 blue:0.8 alpha:1.0].CGColor;
  exportButton.layer.shadowOffset = CGSizeMake(0, 1);
  exportButton.layer.shadowOpacity = 0.2;
  exportButton.layer.shadowRadius = 1;
  [exportButton addTarget:self
                   action:@selector(exportSettings)
         forControlEvents:UIControlEventTouchUpInside];
  [self.containerTab addSubview:exportButton];
  y += 42;

  UIButton *importButton = [UIButton buttonWithType:UIButtonTypeSystem];
  importButton.frame = CGRectMake(leftMargin, y, contentWidth, 36);
  importButton.backgroundColor = [UIColor colorWithRed:0.2
                                                 green:0.8
                                                  blue:0.3
                                                 alpha:0.85];
  [importButton setTitle:@"Import Settings 📥" forState:UIControlStateNormal];
  [importButton setTitleColor:[UIColor blackColor]
                     forState:UIControlStateNormal];
  importButton.titleLabel.font = [UIFont systemFontOfSize:13
                                                   weight:UIFontWeightSemibold];
  importButton.layer.cornerRadius = 6;
  importButton.layer.borderWidth = 0.5;
  importButton.layer.borderColor =
      [UIColor colorWithRed:0.15 green:0.6 blue:0.25 alpha:0.6].CGColor;
  importButton.layer.shadowColor =
      [UIColor colorWithRed:0.1 green:0.6 blue:0.2 alpha:1.0].CGColor;
  importButton.layer.shadowOffset = CGSizeMake(0, 1);
  importButton.layer.shadowOpacity = 0.2;
  importButton.layer.shadowRadius = 1;
  [importButton addTarget:self
                   action:@selector(importSettings)
         forControlEvents:UIControlEventTouchUpInside];
  [self.containerTab addSubview:importButton];
  y += 36;

  UILabel *containerFeedbackLabel = [[UILabel alloc]
      initWithFrame:CGRectMake(leftMargin, y - 36, contentWidth, 24)];
  containerFeedbackLabel.textAlignment = NSTextAlignmentCenter;
  containerFeedbackLabel.font = [UIFont systemFontOfSize:13
                                                  weight:UIFontWeightSemibold];
  containerFeedbackLabel.alpha = 0;
  containerFeedbackLabel.tag = 8889;
  [self.containerTab addSubview:containerFeedbackLabel];
  y += 16;

  UIView *divider2 = [[UIView alloc]
      initWithFrame:CGRectMake(leftMargin + 40, y, contentWidth - 80, 1)];
  divider2.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.5];
  [self.containerTab addSubview:divider2];
  y += 16;

  UILabel *windowSettingsLabel = [[UILabel alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 20)];
  windowSettingsLabel.text = @"Window Settings";
  windowSettingsLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
  windowSettingsLabel.font = [UIFont systemFontOfSize:13
                                               weight:UIFontWeightMedium];
  windowSettingsLabel.textAlignment = NSTextAlignmentCenter;
  [self.containerTab addSubview:windowSettingsLabel];
  y += 28;

  UIView *borderlessRow = [[UIView alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 48)];
  borderlessRow.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.05];
  borderlessRow.layer.cornerRadius = 8;
  [self.containerTab addSubview:borderlessRow];

  UILabel *borderlessLabel =
      [[UILabel alloc] initWithFrame:CGRectMake(16, 0, contentWidth - 80, 48)];
  borderlessLabel.text = @"Borderless Windowed";
  borderlessLabel.textColor = [UIColor whiteColor];
  borderlessLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
  [borderlessRow addSubview:borderlessLabel];

  UISwitch *borderlessSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];

  borderlessSwitch.center = CGPointMake(contentWidth - 42, 24);
  borderlessSwitch.onTintColor = [UIColor colorWithRed:0.0
                                                 green:0.47
                                                  blue:1.0
                                                 alpha:1.0];
  borderlessSwitch.on = isBorderlessModeEnabled;
  [borderlessSwitch addTarget:self
                       action:@selector(borderlessToggleChanged:)
             forControlEvents:UIControlEventValueChanged];
  [borderlessRow addSubview:borderlessSwitch];
  y += 48 + 20;

  self.containerTab.frame = CGRectMake(0, 0, 330, y);
}

- (void)createQuickStartTab {
  CGFloat w = 330.0;
  CGFloat leftMargin = 20.0;
  CGFloat contentWidth = w - leftMargin * 2;

  self.quickStartTab = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 10)];
  self.quickStartTab.backgroundColor = [UIColor clearColor];

  UIView *content = self.quickStartTab;

  CGFloat y = 16;

  UILabel *header = [[UILabel alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 24)];
  header.text = @"Quick Start Guide";
  header.textColor = [UIColor whiteColor];
  header.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
  header.textAlignment = NSTextAlignmentCenter;
  [content addSubview:header];
  y += 32;

  UILabel *tmpLabel = [[UILabel alloc] init];
  tmpLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
  tmpLabel.numberOfLines = 0;
  tmpLabel.text =
      @"Watch this short tutorial to get up and running with FnMacTweak.";
  CGFloat textH =
      [tmpLabel sizeThatFits:CGSizeMake(contentWidth - 16, CGFLOAT_MAX)].height;
  CGFloat bannerH = textH + 20;

  UIView *instructionBanner = [[UIView alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, bannerH)];
  instructionBanner.backgroundColor = [UIColor colorWithRed:0.35
                                                      green:0.35
                                                       blue:0.40
                                                      alpha:0.35];
  instructionBanner.layer.cornerRadius = 8;
  [content addSubview:instructionBanner];

  UILabel *instruction = [[UILabel alloc]
      initWithFrame:CGRectMake(8, 10, contentWidth - 16, textH)];
  instruction.text =
      @"Watch this short tutorial to get up and running with FnMacTweak.";
  instruction.textColor = [UIColor colorWithWhite:0.80 alpha:1.0];
  instruction.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
  instruction.textAlignment = NSTextAlignmentCenter;
  instruction.numberOfLines = 0;
  [instructionBanner addSubview:instruction];
  y += bannerH + 16;

  UIView *div = [[UIView alloc]
      initWithFrame:CGRectMake(leftMargin + 40, y, contentWidth - 80, 1)];
  div.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.5];
  [content addSubview:div];
  y += 16;

  FnVideoCardView *card1 = [[FnVideoCardView alloc]
      initWithTitle:@"Setup Video"
        description:
            @"How to configure Fortnite in-game and Tweak settings"
              width:contentWidth];
  card1.tag = 201;
  card1.frame =
      CGRectMake(leftMargin, y, contentWidth, card1.bounds.size.height);
  [content addSubview:card1];
  y += card1.bounds.size.height + 16;

  UIView *spacer = [[UIView alloc]
      initWithFrame:CGRectMake(leftMargin + 40, y, contentWidth - 80, 1)];
  spacer.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.5];
  [content addSubview:spacer];
  y += 16;

  CGFloat gutter  = 8.0;
  CGFloat cellW   = (contentWidth - gutter) / 2.0;
  CGFloat cellPad = 10.0;
  CGFloat badgeH  = 26.0;
  CGFloat innerCW = cellW - cellPad * 2;

  CGFloat typingModeCellH = 72.0;
  UIView *typingModeCell = [[UIView alloc] initWithFrame:CGRectMake(leftMargin, y, contentWidth, typingModeCellH)];
  typingModeCell.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.6];
  typingModeCell.layer.cornerRadius = 8;
  typingModeCell.layer.borderWidth = 0.5;
  typingModeCell.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:0.4].CGColor;
  [self.quickStartTab addSubview:typingModeCell];

  UILabel *typingTitle = [[UILabel alloc] initWithFrame:CGRectMake(cellPad, 10, contentWidth - cellPad*2, 16)];
  typingTitle.text = @"Typing Mode (Raw Input)";
  typingTitle.textColor = [UIColor whiteColor];
  typingTitle.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
  [typingModeCell addSubview:typingTitle];

  UILabel *capsBadge = [[UILabel alloc] initWithFrame:CGRectMake(cellPad, 34, 74, 26)];
  capsBadge.text = @"Caps Lock";
  capsBadge.textColor = [UIColor whiteColor];
  capsBadge.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
  capsBadge.textAlignment = NSTextAlignmentCenter;
  capsBadge.backgroundColor = [UIColor colorWithWhite:0.28 alpha:0.9];
  capsBadge.layer.cornerRadius = 5;
  capsBadge.layer.borderWidth = 0.5;
  capsBadge.layer.borderColor = [UIColor colorWithWhite:0.45 alpha:0.6].CGColor;
  capsBadge.clipsToBounds = YES;
  [typingModeCell addSubview:capsBadge];

  UILabel *typingDesc = [[UILabel alloc] initWithFrame:CGRectMake(cellPad + 82, 30, contentWidth - (cellPad + 82) - cellPad, 36)];
  typingDesc.text = @"Toggles raw keyboard input. Syncs with your keyboard's light.";
  typingDesc.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
  typingDesc.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
  typingDesc.numberOfLines = 2;
  [typingModeCell addSubview:typingDesc];

  y += typingModeCellH + 12;

  UILabel *tmpP = [[UILabel alloc] init];
  tmpP.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
  tmpP.numberOfLines = 0;
  tmpP.text = @"Press P to open the settings pane.";
  CGFloat pDescH = [tmpP sizeThatFits:CGSizeMake(innerCW, CGFLOAT_MAX)].height;

  UILabel *tmpL = [[UILabel alloc] init];
  tmpL.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
  tmpL.numberOfLines = 0;
  tmpL.text = @"Press L to lock or unlock the cursor.";
  CGFloat lDescH = [tmpL sizeThatFits:CGSizeMake(innerCW, CGFLOAT_MAX)].height;

  CGFloat titleH = 16.0;
  CGFloat descH  = MAX(pDescH, lDescH);
  CGFloat cellH  = cellPad + titleH + 8 + badgeH + 8 + descH + cellPad;

  UIView *openCell = [[UIView alloc] initWithFrame:CGRectMake(leftMargin, y, cellW, cellH)];
  openCell.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.6];
  openCell.layer.cornerRadius = 8;
  openCell.layer.borderWidth = 0.5;
  openCell.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:0.4].CGColor;
  [content addSubview:openCell];

  UILabel *openTitle = [[UILabel alloc] initWithFrame:CGRectMake(cellPad, cellPad, innerCW, titleH)];
  openTitle.text = @"Opening Settings";
  openTitle.textColor = [UIColor whiteColor];
  openTitle.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
  [openCell addSubview:openTitle];

  UILabel *pBadge = [[UILabel alloc] initWithFrame:CGRectMake(cellPad, cellPad + titleH + 8, 28, badgeH)];
  pBadge.text = @"P";
  pBadge.textColor = [UIColor whiteColor];
  pBadge.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
  pBadge.textAlignment = NSTextAlignmentCenter;
  pBadge.backgroundColor = [UIColor colorWithWhite:0.28 alpha:0.9];
  pBadge.layer.cornerRadius = 5;
  pBadge.layer.borderWidth = 0.5;
  pBadge.layer.borderColor = [UIColor colorWithWhite:0.45 alpha:0.6].CGColor;
  pBadge.clipsToBounds = YES;
  [openCell addSubview:pBadge];

  UILabel *openDesc = [[UILabel alloc] initWithFrame:CGRectMake(cellPad, cellPad + titleH + 8 + badgeH + 8, innerCW, descH)];
  openDesc.text = @"Press P to open the settings pane.";
  openDesc.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
  openDesc.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
  openDesc.numberOfLines = 0;
  [openCell addSubview:openDesc];

  UIView *lockCell = [[UIView alloc] initWithFrame:CGRectMake(leftMargin + cellW + gutter, y, cellW, cellH)];
  lockCell.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.6];
  lockCell.layer.cornerRadius = 8;
  lockCell.layer.borderWidth = 0.5;
  lockCell.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:0.4].CGColor;
  [content addSubview:lockCell];

  UILabel *lockTitle = [[UILabel alloc] initWithFrame:CGRectMake(cellPad, cellPad, innerCW, titleH)];
  lockTitle.text = @"Lock / Unlock Cursor";
  lockTitle.textColor = [UIColor whiteColor];
  lockTitle.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
  [lockCell addSubview:lockTitle];

  UILabel *lBadge = [[UILabel alloc] initWithFrame:CGRectMake(cellPad, cellPad + titleH + 8, 28, badgeH)];
  lBadge.text = @"L";
  lBadge.textColor = [UIColor whiteColor];
  lBadge.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
  lBadge.textAlignment = NSTextAlignmentCenter;
  lBadge.backgroundColor = [UIColor colorWithWhite:0.28 alpha:0.9];
  lBadge.layer.cornerRadius = 5;
  lBadge.layer.borderWidth = 0.5;
  lBadge.layer.borderColor = [UIColor colorWithWhite:0.45 alpha:0.6].CGColor;
  lBadge.clipsToBounds = YES;
  [lockCell addSubview:lBadge];

  UILabel *lockDesc = [[UILabel alloc] initWithFrame:CGRectMake(cellPad, cellPad + titleH + 8 + badgeH + 8, innerCW, descH)];
  lockDesc.text = @"Press L to lock or unlock the cursor.";
  lockDesc.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
  lockDesc.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
  lockDesc.numberOfLines = 0;
  [lockCell addSubview:lockDesc];

  y += cellH + 20;

  self.quickStartContentHeight = y;

  CGRect f = self.quickStartTab.frame;
  f.size.height = y;
  self.quickStartTab.frame = f;
}

- (void)quickStartTabTapped {
  [self pauseQuickStartVideos];
  [self switchToTab:PopupTabQuickStart];
}

- (void)pauseQuickStartVideos {
  FnVideoCardView *card1 =
      (FnVideoCardView *)[self.quickStartTab viewWithTag:201];
  [card1 pausePlayback];
}

static NSString *getControllerButtonName(NSInteger idx) {
  switch (idx) {
    case FnCtrlButtonA:         return @"Button A  (Cross)";
    case FnCtrlButtonB:         return @"Button B  (Circle)";
    case FnCtrlButtonX:         return @"Button X  (Square)";
    case FnCtrlButtonY:         return @"Button Y  (Triangle)";
    case FnCtrlDpadUp:          return @"D-Pad ↑";
    case FnCtrlDpadDown:        return @"D-Pad ↓";
    case FnCtrlDpadLeft:        return @"D-Pad ←";
    case FnCtrlDpadRight:       return @"D-Pad →";
    case FnCtrlL1:              return @"L1  (LB)";
    case FnCtrlR1:              return @"R1  (RB)";
    case FnCtrlL2:              return @"L2  (LT)";
    case FnCtrlR2:              return @"R2  (RT)";
    case FnCtrlL3:              return @"L3  (LS Click)";
    case FnCtrlR3:              return @"R3  (RS Click)";
    case FnCtrlOptions:         return @"Options / Menu (Start)";
    case FnCtrlShare:           return @"Share / View (Select)";
    case FnCtrlHome:            return @"Home (Xbox / PS)";
    case FnCtrlLeftStickUp:     return @"Left Stick ↑";
    case FnCtrlLeftStickDown:   return @"Left Stick ↓";
    case FnCtrlLeftStickLeft:   return @"Left Stick ←";
    case FnCtrlLeftStickRight:  return @"Left Stick →";
    case FnCtrlRightStickUp:    return @"Right Stick ↑";
    case FnCtrlRightStickDown:  return @"Right Stick ↓";
    case FnCtrlRightStickLeft:  return @"Right Stick ←";
    case FnCtrlRightStickRight: return @"Right Stick →";
    default: return @"Unknown";
  }
}

- (UIView *)createControllerBindRowForIndex:(NSInteger)btnIdx
                                        atY:(CGFloat)y
                                      width:(CGFloat)width {
  UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0, y, width, 30)];

  UIButton *resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
  resetButton.frame = CGRectMake(0, 5, 20, 20);
  [resetButton setTitle:@"↪️" forState:UIControlStateNormal];
  resetButton.titleLabel.font = [UIFont systemFontOfSize:14];
  resetButton.accessibilityLabel = getControllerButtonName(btnIdx);
  resetButton.tag = 7500 + btnIdx;
  [resetButton addTarget:self
                  action:@selector(controllerBindResetTapped:)
        forControlEvents:UIControlEventTouchUpInside];
  [row addSubview:resetButton];

  UILabel *actionLabel =
      [[UILabel alloc] initWithFrame:CGRectMake(24, 5, width - 140, 20)];
  actionLabel.text = getControllerButtonName(btnIdx);
  actionLabel.textColor = [UIColor colorWithWhite:0.85 alpha:1.0];
  actionLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
  actionLabel.textAlignment = NSTextAlignmentLeft;
  [row addSubview:actionLabel];

  int savedCode  = controllerMappingArray[btnIdx];
  BOOL isStaged  = self.stagedControllerMappings[@(btnIdx)] != nil;
  int stagedCode = isStaged ? [self.stagedControllerMappings[@(btnIdx)] intValue] : 0;
  int currentCode = isStaged ? stagedCode : savedCode;
  BOOL isCustomSaved = !isStaged && (savedCode != 0);

  UIButton *keyButton = [UIButton buttonWithType:UIButtonTypeSystem];
  keyButton.frame = CGRectMake(width - 110, 3, 110, 24);
  keyButton.backgroundColor = [UIColor colorWithWhite:0.22 alpha:1.0];
  keyButton.layer.cornerRadius = 4;
  keyButton.accessibilityLabel = getControllerButtonName(btnIdx);
  keyButton.tag = 7000 + btnIdx;

  UIColor *borderColor;
  if (isStaged && currentCode != 0) {

    [keyButton setTitle:getKeyName((GCKeyCode)currentCode) forState:UIControlStateNormal];
    [keyButton setTitleColor:[UIColor colorWithRed:1.0 green:0.9 blue:0.2 alpha:1.0]
                    forState:UIControlStateNormal];
    borderColor = [UIColor colorWithRed:0.8 green:0.7 blue:0.0 alpha:1.0];
  } else if (isCustomSaved) {

    [keyButton setTitle:getKeyName((GCKeyCode)currentCode) forState:UIControlStateNormal];
    [keyButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    borderColor = [UIColor colorWithWhite:0.65 alpha:1.0];
  } else {

    [keyButton setTitle:@"—" forState:UIControlStateNormal];
    [keyButton setTitleColor:[UIColor colorWithWhite:0.6 alpha:1.0]
                    forState:UIControlStateNormal];
    borderColor = [UIColor colorWithWhite:0.35 alpha:1.0];
  }

  keyButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
  [row addSubview:keyButton];
  setShapeBorder(keyButton, 4, 0.5, borderColor);

  [keyButton addTarget:self
                action:@selector(controllerBindKeyTapped:)
      forControlEvents:UIControlEventTouchUpInside];
  return row;
}

- (void)createControllerTab {
  self.controllerTab = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 330, 2000)];

  CGFloat y            = 16;
  CGFloat leftMargin   = 20;
  CGFloat rightMargin  = 20;
  CGFloat contentWidth = 330 - leftMargin - rightMargin;

  UILabel *title = [[UILabel alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 24)];
  title.text = @"Controller Mapping";
  title.textColor = [UIColor whiteColor];
  title.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
  title.textAlignment = NSTextAlignmentCenter;
  [self.controllerTab addSubview:title];
  y += 32;

  UIView *banner = [[UIView alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 58)];
  banner.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.3 alpha:0.2];
  banner.layer.cornerRadius = 8;
  [self.controllerTab addSubview:banner];
  UILabel *bannerLabel = [[UILabel alloc]
      initWithFrame:CGRectMake(8, 10, contentWidth - 16, 38)];
  bannerLabel.text = @"Map keys or mouse buttons to controller inputs — source input is swallowed";
  bannerLabel.textColor = [UIColor colorWithRed:0.6 green:1.0 blue:0.7 alpha:1.0];
  bannerLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
  bannerLabel.textAlignment = NSTextAlignmentCenter;
  bannerLabel.numberOfLines = 2;
  [banner addSubview:bannerLabel];
  y += 74;

  self.applyControllerButton = [UIButton buttonWithType:UIButtonTypeSystem];
  self.applyControllerButton.frame = CGRectMake(leftMargin, y, contentWidth, 32);
  self.applyControllerButton.backgroundColor =
      [UIColor colorWithRed:0.0 green:0.47 blue:1.0 alpha:0.85];
  [self.applyControllerButton setTitle:@"Apply Changes (0)"
                               forState:UIControlStateNormal];
  [self.applyControllerButton setTitleColor:[UIColor whiteColor]
                                   forState:UIControlStateNormal];
  self.applyControllerButton.titleLabel.font =
      [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
  self.applyControllerButton.layer.cornerRadius = 6;
  self.applyControllerButton.layer.borderWidth = 0.5;
  self.applyControllerButton.layer.borderColor =
      [UIColor colorWithRed:0.0 green:0.4 blue:0.9 alpha:0.6].CGColor;
  self.applyControllerButton.layer.shadowColor =
      [UIColor colorWithRed:0.0 green:0.3 blue:0.8 alpha:1.0].CGColor;
  self.applyControllerButton.layer.shadowOffset = CGSizeMake(0, 1);
  self.applyControllerButton.layer.shadowOpacity = 0.2;
  self.applyControllerButton.layer.shadowRadius = 1;
  self.applyControllerButton.enabled = NO;
  self.applyControllerButton.alpha = 0.5;
  [self.applyControllerButton addTarget:self
                                 action:@selector(applyControllerChangesTapped)
                       forControlEvents:UIControlEventTouchUpInside];
  [self.controllerTab addSubview:self.applyControllerButton];
  y += 38;

  self.discardControllerButton = [UIButton buttonWithType:UIButtonTypeSystem];
  self.discardControllerButton.frame = CGRectMake(leftMargin, y, contentWidth, 32);
  self.discardControllerButton.backgroundColor =
      [UIColor colorWithRed:1.0 green:0.9 blue:0.3 alpha:1.0];
  [self.discardControllerButton setTitle:@"Discard Changes (0)"
                                 forState:UIControlStateNormal];
  [self.discardControllerButton setTitleColor:[UIColor blackColor]
                                     forState:UIControlStateNormal];
  self.discardControllerButton.titleLabel.font =
      [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
  self.discardControllerButton.layer.cornerRadius = 6;
  self.discardControllerButton.layer.borderWidth = 0.5;
  self.discardControllerButton.layer.borderColor =
      [UIColor colorWithRed:0.9 green:0.8 blue:0.2 alpha:0.6].CGColor;
  self.discardControllerButton.layer.shadowColor =
      [UIColor colorWithRed:0.8 green:0.7 blue:0.0 alpha:1.0].CGColor;
  self.discardControllerButton.layer.shadowOffset = CGSizeMake(0, 1);
  self.discardControllerButton.layer.shadowOpacity = 0.2;
  self.discardControllerButton.layer.shadowRadius = 1;
  self.discardControllerButton.enabled = NO;
  self.discardControllerButton.alpha = 0.3;
  [self.discardControllerButton addTarget:self
                                   action:@selector(discardControllerChangesTapped)
                         forControlEvents:UIControlEventTouchUpInside];
  [self.controllerTab addSubview:self.discardControllerButton];
  y += 38;

  UIButton *resetAllBtn = [UIButton buttonWithType:UIButtonTypeSystem];
  resetAllBtn.frame = CGRectMake(leftMargin, y, contentWidth, 32);
  resetAllBtn.backgroundColor = [UIColor colorWithRed:0.6 green:0.2 blue:0.2 alpha:0.5];
  [resetAllBtn setTitle:@"Reset All to Defaults" forState:UIControlStateNormal];
  [resetAllBtn setTitleColor:[UIColor colorWithRed:1.0 green:0.7 blue:0.7 alpha:1.0]
                    forState:UIControlStateNormal];
  resetAllBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
  resetAllBtn.layer.cornerRadius = 6;
  resetAllBtn.layer.borderWidth = 0.5;
  resetAllBtn.layer.borderColor =
      [UIColor colorWithRed:0.5 green:0.25 blue:0.25 alpha:0.5].CGColor;
  [resetAllBtn addTarget:self
                  action:@selector(resetAllControllerBindingsTapped)
        forControlEvents:UIControlEventTouchUpInside];
  [self.controllerTab addSubview:resetAllBtn];
  y += 50;

  NSArray *categories = @[
    @{ @"title": @"FACE BUTTONS",
       @"indices": @[@(FnCtrlButtonA), @(FnCtrlButtonB),
                     @(FnCtrlButtonX), @(FnCtrlButtonY)] },
    @{ @"title": @"D-PAD",
       @"indices": @[@(FnCtrlDpadUp), @(FnCtrlDpadDown),
                     @(FnCtrlDpadLeft), @(FnCtrlDpadRight)] },
    @{ @"title": @"BUMPERS & TRIGGERS",
       @"indices": @[@(FnCtrlL1), @(FnCtrlR1), @(FnCtrlL2), @(FnCtrlR2)] },
    @{ @"title": @"STICK CLICKS",
       @"indices": @[@(FnCtrlL3), @(FnCtrlR3)] },
    @{ @"title": @"SYSTEM BUTTONS",
       @"indices": @[@(FnCtrlShare), @(FnCtrlOptions), @(FnCtrlHome)] },
    @{ @"title": @"LEFT STICK",
       @"indices": @[@(FnCtrlLeftStickUp), @(FnCtrlLeftStickDown),
                     @(FnCtrlLeftStickLeft), @(FnCtrlLeftStickRight)] },
    @{ @"title": @"RIGHT STICK",
       @"indices": @[@(FnCtrlRightStickUp), @(FnCtrlRightStickDown),
                     @(FnCtrlRightStickLeft), @(FnCtrlRightStickRight)] },
  ];

  UIView *rowsContainer = [[UIView alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 0)];
  rowsContainer.tag = 6100;
  [self.controllerTab addSubview:rowsContainer];

  CGFloat rowY = 0;
  for (NSDictionary *cat in categories) {
    UILabel *catLabel = [[UILabel alloc]
        initWithFrame:CGRectMake(0, rowY, contentWidth, 20)];
    catLabel.text = cat[@"title"];
    catLabel.textColor = [UIColor colorWithRed:0.5 green:0.7 blue:1.0 alpha:1.0];
    catLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    [rowsContainer addSubview:catLabel];
    rowY += 24;
    for (NSNumber *idxNum in cat[@"indices"]) {
      UIView *row = [self createControllerBindRowForIndex:[idxNum integerValue]
                                                     atY:rowY
                                                   width:contentWidth];
      [rowsContainer addSubview:row];
      rowY += 36;
    }
    rowY += 8;
  }
  CGRect cf = rowsContainer.frame; cf.size.height = rowY; rowsContainer.frame = cf;
  y += rowY + 16;

  y += 16;
  UIView *dividerRow = [[UIView alloc] initWithFrame:CGRectMake(leftMargin + 40, y, contentWidth - 80, 1)];
  dividerRow.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.5];
  [self.controllerTab addSubview:dividerRow];
  y += 16;

  UILabel *vctrlTitle = [[UILabel alloc] initWithFrame:CGRectMake(leftMargin, y, contentWidth, 20)];
  vctrlTitle.text = @"Advanced Custom Remaps";
  vctrlTitle.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
  vctrlTitle.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
  vctrlTitle.textAlignment = NSTextAlignmentCenter;
  [self.controllerTab addSubview:vctrlTitle];
  y += 28;

  UIView *vctrlContainer = [[UIView alloc] initWithFrame:CGRectMake(leftMargin, y, contentWidth, 0)];
  vctrlContainer.tag = 6200;
  [self.controllerTab addSubview:vctrlContainer];

  UIButton *addVBtn = [UIButton buttonWithType:UIButtonTypeSystem];
  addVBtn.frame = CGRectMake(leftMargin, y, contentWidth, 32);
  addVBtn.backgroundColor = [UIColor colorWithWhite:0.25 alpha:0.5];
  [addVBtn setTitle:@"+ Add Custom Remap" forState:UIControlStateNormal];
  [addVBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
  addVBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
  addVBtn.layer.cornerRadius = 6;
  addVBtn.layer.borderWidth = 0.5;
  addVBtn.layer.borderColor = [UIColor colorWithWhite:0.4 alpha:0.4].CGColor;
  addVBtn.tag = 6201;
  [addVBtn addTarget:self action:@selector(addVCtrlRemapTapped) forControlEvents:UIControlEventTouchUpInside];
  [self.controllerTab addSubview:addVBtn];

  [self refreshVCtrlRemapRows];
}

- (void)controllerModeToggled:(UISwitch *)sw {
  isControllerModeEnabled = sw.isOn;
  saveControllerMappings();
}

- (void)stageControllerChange:(NSInteger)btnIdx inputCode:(int)code {

  self.stagedControllerMappings[@(btnIdx)] = @(code);
  [self updateControllerApplyButton];
}

- (void)updateControllerApplyButton {
  NSInteger count = self.stagedControllerMappings.count;
  [self.applyControllerButton
      setTitle:[NSString stringWithFormat:@"Apply Changes (%ld)", (long)count]
      forState:UIControlStateNormal];
  [self.discardControllerButton
      setTitle:[NSString stringWithFormat:@"Discard Changes (%ld)", (long)count]
      forState:UIControlStateNormal];
  if (count > 0) {
    self.applyControllerButton.enabled  = YES;
    self.discardControllerButton.enabled = YES;
    [UIView animateWithDuration:0.2 animations:^{
      self.applyControllerButton.alpha  = 1.0;
      self.discardControllerButton.alpha = 1.0;
    }];
  } else {
    self.applyControllerButton.enabled  = NO;
    self.discardControllerButton.enabled = NO;
    [UIView animateWithDuration:0.2 animations:^{
      self.applyControllerButton.alpha  = 0.5;
      self.discardControllerButton.alpha = 0.3;
    }];
  }
}

- (void)syncAndSaveVCtrlRemappings {
    [vctrlRemappings removeAllObjects];
    for (NSDictionary *remap in self.stagedVCtrlRemappings) {
        if ([remap[@"src"] intValue] >= 0) {
            [vctrlRemappings addObject:remap];
        }
    }
    saveControllerMappings();
    recookVCtrlRemappings();
}

- (void)addVCtrlRemapTapped {

  UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:@"Add Custom Remap"
                       message:@"Press a key or mouse button to use as source"
                preferredStyle:UIAlertControllerStyleAlert];

  [alert addAction:[UIAlertAction
                       actionWithTitle:@"Cancel"
                                 style:UIAlertActionStyleCancel
                                 handler:^(UIAlertAction *_Nonnull action) {
                                   keyCaptureCallback = nil;
                                   mouseButtonCaptureCallback = nil;
                                 }]];

  ignoreNextLeftClickCount = 1;

  [self presentViewController:alert
                     animated:YES
                   completion:^{
                     __weak typeof(self) weakSelf = self;

                     void (^handleCapturedSource)(GCKeyCode) = ^(GCKeyCode capturedCode) {
                       dispatch_async(dispatch_get_main_queue(), ^{
                         __strong typeof(weakSelf) strongSelf = weakSelf;
                         if (!strongSelf) return;

                         keyCaptureCallback = nil;
                         mouseButtonCaptureCallback = nil;

                         [strongSelf.presentedViewController dismissViewControllerAnimated:YES completion:^{
                             [strongSelf.stagedVCtrlRemappings addObject:@{@"src": @((int)capturedCode), @"dst": @(0)}];

                             [strongSelf syncAndSaveVCtrlRemappings];
                             [strongSelf refreshVCtrlRemapRows];
                             [strongSelf updateControllerApplyButton];
                         }];
                       });
                     };

                     keyCaptureCallback = ^(GCKeyCode keyCode) {
                       handleCapturedSource(keyCode);
                     };
                     mouseButtonCaptureCallback = ^(int buttonCode) {
                       handleCapturedSource((GCKeyCode)buttonCode);
                     };
                   }];
}

- (void)refreshVCtrlRemapRows {
  UIView *container = [self.controllerTab viewWithTag:6200];
  if (!container) return;
  for (UIView *v in container.subviews) [v removeFromSuperview];

  CGFloat rowY = 0;
  CGFloat width = container.frame.size.width;

  for (NSInteger i = 0; i < self.stagedVCtrlRemappings.count; i++) {
    NSDictionary *remap = self.stagedVCtrlRemappings[i];
    int src = [remap[@"src"] intValue];
    int dst = [remap[@"dst"] intValue];

    UIView *row = [self createVCtrlRemapRowAtIndex:i source:src target:dst atY:rowY width:width];
    [container addSubview:row];
    rowY += 50;
  }

  CGRect cf = container.frame;
  cf.size.height = rowY;
  container.frame = cf;

  UIButton *addVBtn = [self.controllerTab viewWithTag:6201];
  if (addVBtn) {
      CGRect af = addVBtn.frame;
      af.origin.y = container.frame.origin.y + container.frame.size.height + 16;
      addVBtn.frame = af;
  }

  CGFloat baseY = container.frame.origin.y;
  self.controllerContentHeight = baseY + rowY + 16 + 32 + 20;
  self.controllerTab.frame = CGRectMake(0, 0, 330, self.controllerContentHeight);

  if (self.currentTab == PopupTabController) {
    self.scrollView.contentSize = CGSizeMake(330, self.controllerContentHeight);
  }
}

- (UIView *)createVCtrlRemapRowAtIndex:(NSInteger)index source:(int)sourceCode target:(int)targetIdx atY:(CGFloat)y width:(CGFloat)width {
  UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0, y, width, 44)];
  row.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.6];
  row.layer.cornerRadius = 8;
  row.layer.borderWidth = 0.5;
  row.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:0.4].CGColor;

  UIButton *srcBtn = [UIButton buttonWithType:UIButtonTypeSystem];
  srcBtn.frame = CGRectMake(10, 7, 80, 30);
  srcBtn.backgroundColor = [UIColor colorWithWhite:0.28 alpha:0.7];
  srcBtn.layer.cornerRadius = 5;
  srcBtn.layer.borderWidth = 0.5;
  srcBtn.layer.borderColor = [UIColor colorWithWhite:0.35 alpha:0.5].CGColor;
  srcBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
  srcBtn.tag = index;

  NSString *name = (sourceCode < 0) ? @"???" : getKeyName((GCKeyCode)sourceCode);
  [srcBtn setTitle:name forState:UIControlStateNormal];
  [srcBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
  [srcBtn addTarget:self action:@selector(vctrlSourceTapped:) forControlEvents:UIControlEventTouchUpInside];
  [row addSubview:srcBtn];

  UILabel *arrow = [[UILabel alloc] initWithFrame:CGRectMake(95, 7, 25, 30)];
  arrow.text = @"→";
  arrow.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
  arrow.font = [UIFont systemFontOfSize:18 weight:UIFontWeightLight];
  arrow.textAlignment = NSTextAlignmentCenter;
  [row addSubview:arrow];

  UIButton *targetBtn = [UIButton buttonWithType:UIButtonTypeSystem];
  targetBtn.frame = CGRectMake(125, 7, 85, 30);
  targetBtn.backgroundColor = [UIColor colorWithWhite:0.32 alpha:0.7];
  targetBtn.layer.cornerRadius = 5;
  targetBtn.layer.borderWidth = 0.5;
  targetBtn.layer.borderColor = [UIColor colorWithWhite:0.38 alpha:0.5].CGColor;
  targetBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];

  NSArray *ctrlButtonNames = @[
    @"A", @"B", @"X", @"Y",
    @"D-Pad Up", @"D-Pad Down", @"D-Pad Left", @"D-Pad Right",
    @"L1", @"R1", @"L2", @"R2", @"L3", @"R3",
    @"Options", @"Share",
    @"LS Up", @"LS Down", @"LS Left", @"LS Right",
    @"RS Up", @"RS Down", @"RS Left", @"RS Right"
  ];

  NSString *btnName = (targetIdx >= 0 && targetIdx < ctrlButtonNames.count) ? ctrlButtonNames[targetIdx] : @"Unknown";
  [targetBtn setTitle:btnName forState:UIControlStateNormal];
  [targetBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];

  NSMutableArray *actions = [NSMutableArray array];
  for (int i = 0; i < ctrlButtonNames.count; i++) {
    NSString *name = ctrlButtonNames[i];
    [actions addObject:[UIAction actionWithTitle:name image:nil identifier:nil handler:^(__kindof UIAction * _Nonnull action) {
      if (index < self.stagedVCtrlRemappings.count) {
          NSMutableDictionary *dict = [self.stagedVCtrlRemappings[index] mutableCopy];
          dict[@"dst"] = @(i);
          self.stagedVCtrlRemappings[index] = dict;

          [self syncAndSaveVCtrlRemappings];
          [self refreshVCtrlRemapRows];
          [self updateControllerApplyButton];
      }
    }]];
  }
  targetBtn.menu = [UIMenu menuWithTitle:@"Select Controller Button" children:actions];
  targetBtn.showsMenuAsPrimaryAction = YES;
  targetBtn.tag = 9000 + index;
  [row addSubview:targetBtn];

  UIButton *delBtn = [UIButton buttonWithType:UIButtonTypeSystem];
  delBtn.frame = CGRectMake(220, 7, 60, 30);
  delBtn.backgroundColor = [UIColor colorWithRed:0.4 green:0.2 blue:0.2 alpha:0.6];
  [delBtn setTitle:@"Delete" forState:UIControlStateNormal];
  [delBtn setTitleColor:[UIColor colorWithRed:1.0 green:0.7 blue:0.7 alpha:1.0] forState:UIControlStateNormal];
  delBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
  delBtn.layer.cornerRadius = 5;
  delBtn.layer.borderWidth = 0.5;
  delBtn.layer.borderColor = [UIColor colorWithRed:0.5 green:0.3 blue:0.3 alpha:0.4].CGColor;
  [delBtn addTarget:self action:@selector(removeVCtrlRemapTapped:) forControlEvents:UIControlEventTouchUpInside];
  delBtn.tag = index;
  [row addSubview:delBtn];

  return row;
}

- (void)vctrlSourceTapped:(UIButton *)sender {
  NSInteger index = sender.tag;
  if (index >= self.stagedVCtrlRemappings.count) return;

  UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:@"Change Source Key"
                       message:@"Press a key or mouse button"
                preferredStyle:UIAlertControllerStyleAlert];

  [alert addAction:[UIAlertAction
                       actionWithTitle:@"Cancel"
                                 style:UIAlertActionStyleCancel
                                 handler:^(UIAlertAction *_Nonnull action) {
                                   keyCaptureCallback = nil;
                                   mouseButtonCaptureCallback = nil;
                                 }]];

  ignoreNextLeftClickCount = 1;

  [self presentViewController:alert
                     animated:YES
                   completion:^{
                     __weak typeof(self) weakSelf = self;
                     void (^handleCapturedInput)(int) = ^(int code) {
                       dispatch_async(dispatch_get_main_queue(), ^{
                         __strong typeof(weakSelf) strongSelf = weakSelf;
                         if (!strongSelf || index >= strongSelf.stagedVCtrlRemappings.count) return;

                         keyCaptureCallback = nil;
                         mouseButtonCaptureCallback = nil;

                         [strongSelf.presentedViewController dismissViewControllerAnimated:YES completion:^{
                             NSMutableDictionary *dict = [strongSelf.stagedVCtrlRemappings[index] mutableCopy];
                             dict[@"src"] = @(code);
                             strongSelf.stagedVCtrlRemappings[index] = dict;

                             [strongSelf syncAndSaveVCtrlRemappings];
                             [strongSelf refreshVCtrlRemapRows];
                             [strongSelf updateControllerApplyButton];
                         }];
                       });
                     };

                     keyCaptureCallback = ^(GCKeyCode keyCode) {
                       handleCapturedInput((int)keyCode);
                     };
                     mouseButtonCaptureCallback = ^(int buttonCode) {
                       handleCapturedInput(buttonCode);
                     };
                   }];
}

- (void)removeVCtrlRemapTapped:(UIButton *)sender {
  NSInteger index = sender.tag;
  if (index < self.stagedVCtrlRemappings.count) {
    [self.stagedVCtrlRemappings removeObjectAtIndex:index];
    [self syncAndSaveVCtrlRemappings];
    [self refreshVCtrlRemapRows];
    [self updateControllerApplyButton];
  }
}

- (void)applyControllerChangesTapped {
  if (self.stagedControllerMappings.count == 0) return;

  for (NSNumber *key in self.stagedControllerMappings) {
    NSInteger idx = [key integerValue];
    int code = [self.stagedControllerMappings[key] intValue];
    if (idx >= 0 && idx < FnCtrlButtonCount)
      controllerMappingArray[idx] = code;
  }
  [self.stagedControllerMappings removeAllObjects];

  saveControllerMappings();
  [self refreshControllerBindRows];
  [self refreshVCtrlRemapRows];
  [self updateControllerApplyButton];
  [self showFeedback:@"Controller Bindings Applied & Saved"
               color:[UIColor colorWithRed:0.3 green:0.9 blue:0.3 alpha:1.0]];
}

- (void)discardControllerChangesTapped {
  if (self.stagedControllerMappings.count == 0 && (self.stagedVCtrlRemappings.count == vctrlRemappings.count)) {

  }
  [self.stagedControllerMappings removeAllObjects];

  [self refreshControllerBindRows];
  [self refreshVCtrlRemapRows];
  [self updateControllerApplyButton];
  [self showFeedback:@"Changes Discarded"
               color:[UIColor colorWithRed:1.0 green:0.9 blue:0.3 alpha:1.0]];
}

- (void)resetAllControllerBindingsTapped {
  UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:@"Reset All Controller Bindings?"
                       message:@"This will clear all controller mappings and restore defaults"
                preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];
  [alert addAction:[UIAlertAction
      actionWithTitle:@"Reset All"
                style:UIAlertActionStyleDestructive
              handler:^(UIAlertAction *a) {

    memset(controllerMappingArray, 0, sizeof(controllerMappingArray));
    saveControllerMappings();

    [self.stagedVCtrlRemappings removeAllObjects];
    [self syncAndSaveVCtrlRemappings];

    [self.stagedControllerMappings removeAllObjects];

    [self refreshControllerBindRows];
    [self refreshVCtrlRemapRows];
    [self updateControllerApplyButton];
    [self showFeedback:@"All controller bindings reset to defaults"
                 color:[UIColor colorWithRed:0.3 green:0.9 blue:0.3 alpha:1.0]];
  }]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)controllerBindKeyTapped:(UIButton *)sender {
  NSInteger btnIdx = sender.tag - 7000;
  if (btnIdx < 0 || btnIdx >= FnCtrlButtonCount) return;
  NSString *btnName = getControllerButtonName(btnIdx);

  UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:btnName
                       message:@"Press any key or click a mouse button to bind it"
                preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction
      actionWithTitle:@"Cancel"
                style:UIAlertActionStyleCancel
              handler:^(UIAlertAction *a) {
    keyCaptureCallback        = nil;
    mouseButtonCaptureCallback = nil;
  }]];
  ignoreNextLeftClickCount = 1;

  [self presentViewController:alert animated:YES completion:^{
    __weak typeof(self) weakSelf = self;
    NSInteger capturedIdx = btnIdx;

    mouseButtonCaptureCallback = ^(int buttonCode) {
      dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        mouseButtonCaptureCallback = nil;
        keyCaptureCallback        = nil;
        [strongSelf.presentedViewController
            dismissViewControllerAnimated:YES
                               completion:^{

          [strongSelf stageControllerChange:capturedIdx inputCode:buttonCode];
          [strongSelf refreshControllerBindRows];
        }];
      });
    };

    keyCaptureCallback = ^(GCKeyCode keyCode) {
      dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        keyCaptureCallback        = nil;
        mouseButtonCaptureCallback = nil;
        [strongSelf.presentedViewController
            dismissViewControllerAnimated:YES
                                completion:^{
          if (keyCode == POPUP_KEY) {
            UIAlertController *err = [UIAlertController
                alertControllerWithTitle:@"Invalid Key"
                                 message:@"Cannot remap the Menu key (F1)"
                          preferredStyle:UIAlertControllerStyleAlert];
            [err addAction:[UIAlertAction actionWithTitle:@"OK"
                                                    style:UIAlertActionStyleDefault
                                                  handler:nil]];
            [strongSelf presentViewController:err animated:YES completion:nil];
            return;
          }
          if (keyCode == 57) {
            UIAlertController *err = [UIAlertController
                alertControllerWithTitle:@"Invalid Key"
                                 message:@"Caps Lock is reserved for Typing Mode"
                          preferredStyle:UIAlertControllerStyleAlert];
            [err addAction:[UIAlertAction actionWithTitle:@"OK"
                                                    style:UIAlertActionStyleDefault
                                                  handler:nil]];
            [strongSelf presentViewController:err animated:YES completion:nil];
            return;
          }

          [strongSelf stageControllerChange:capturedIdx inputCode:(int)keyCode];
          [strongSelf refreshControllerBindRows];
        }];
      });
    };
  }];
}

- (void)refreshControllerBindRows {
  UIView *container = [self.controllerTab viewWithTag:6100];
  if (!container) return;

  for (UIView *sub in [container.subviews copy]) {
    [sub removeFromSuperview];
  }

  CGFloat contentWidth = container.frame.size.width;
  NSArray *categories = @[
    @{ @"title": @"FACE BUTTONS",
       @"indices": @[@(FnCtrlButtonA), @(FnCtrlButtonB),
                     @(FnCtrlButtonX), @(FnCtrlButtonY)] },
    @{ @"title": @"D-PAD",
       @"indices": @[@(FnCtrlDpadUp), @(FnCtrlDpadDown),
                     @(FnCtrlDpadLeft), @(FnCtrlDpadRight)] },
    @{ @"title": @"BUMPERS & TRIGGERS",
       @"indices": @[@(FnCtrlL1), @(FnCtrlR1), @(FnCtrlL2), @(FnCtrlR2)] },
    @{ @"title": @"STICK CLICKS",
       @"indices": @[@(FnCtrlL3), @(FnCtrlR3)] },
    @{ @"title": @"SYSTEM BUTTONS",
       @"indices": @[@(FnCtrlShare), @(FnCtrlOptions), @(FnCtrlHome)] },
    @{ @"title": @"LEFT STICK",
       @"indices": @[@(FnCtrlLeftStickUp),    @(FnCtrlLeftStickDown),
                     @(FnCtrlLeftStickLeft),   @(FnCtrlLeftStickRight)] },
    @{ @"title": @"RIGHT STICK",
       @"indices": @[@(FnCtrlRightStickUp),   @(FnCtrlRightStickDown),
                     @(FnCtrlRightStickLeft),  @(FnCtrlRightStickRight)] },
  ];

  CGFloat rowY = 0;
  for (NSDictionary *cat in categories) {
    UILabel *catLabel = [[UILabel alloc]
        initWithFrame:CGRectMake(0, rowY, contentWidth, 20)];
    catLabel.text = cat[@"title"];
    catLabel.textColor = [UIColor colorWithRed:0.5 green:0.7 blue:1.0 alpha:1.0];
    catLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    catLabel.textAlignment = NSTextAlignmentLeft;
    [container addSubview:catLabel];
    rowY += 24;
    for (NSNumber *idxNum in cat[@"indices"]) {
      UIView *row = [self createControllerBindRowForIndex:[idxNum integerValue]
                                                     atY:rowY
                                                   width:contentWidth];
      [container addSubview:row];
      rowY += 36;
    }
    rowY += 8;
  }
  CGRect f = container.frame; f.size.height = rowY; container.frame = f;
}

- (void)controllerBindResetTapped:(UIButton *)sender {
  NSInteger btnIdx = sender.tag - 7500;
  if (btnIdx < 0 || btnIdx >= FnCtrlButtonCount) return;
  keyCaptureCallback        = nil;
  mouseButtonCaptureCallback = nil;

  controllerMappingArray[btnIdx] = 0;
  [self.stagedControllerMappings removeObjectForKey:@(btnIdx)];
  saveControllerMappings();
  [self refreshControllerBindRows];
  [self updateControllerApplyButton];
}

- (void)switchToTab:(PopupTab)tab {

  if (self.currentTab == PopupTabQuickStart && tab != PopupTabQuickStart) {
    [self pauseQuickStartVideos];
  }

  [self.sensitivityTab removeFromSuperview];
  [self.keyRemapTab removeFromSuperview];
  [self.containerTab removeFromSuperview];
  [self.quickStartTab removeFromSuperview];
  [self.controllerTab removeFromSuperview];

  self.currentTab = tab;

  [UIView animateWithDuration:0.3
                        delay:0
       usingSpringWithDamping:0.75
        initialSpringVelocity:0.8
                      options:UIViewAnimationOptionCurveEaseInOut
                   animations:^{
                     CGRect frame = self.tabIndicator.frame;
                     frame.origin.x = tab * 49;
                     self.tabIndicator.frame = frame;
                   }
                   completion:nil];

  if (tab == PopupTabSensitivity) {
    [self.scrollView addSubview:self.sensitivityTab];
    self.scrollView.contentSize =
        CGSizeMake(330, self.sensitivityContentHeight);
  } else if (tab == PopupTabKeyRemap) {
    [self.scrollView addSubview:self.keyRemapTab];
    self.scrollView.contentSize = CGSizeMake(330, self.keyRemapContentHeight);
  } else if (tab == PopupTabContainer) {
    [self.scrollView addSubview:self.containerTab];
    self.scrollView.contentSize = CGSizeMake(330, self.containerTab.frame.size.height);
  } else if (tab == PopupTabQuickStart) {
    [self.scrollView addSubview:self.quickStartTab];
    self.scrollView.contentSize = CGSizeMake(330, self.quickStartContentHeight);
  } else if (tab == PopupTabController) {
    [self.scrollView addSubview:self.controllerTab];
    self.scrollView.contentSize = CGSizeMake(330, self.controllerContentHeight);
  }

  [self.scrollView setContentOffset:CGPointZero animated:NO];
}

- (void)addKeyRemapTapped {

  UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:@"Add Custom Remap"
                       message:@"Press a key or mouse button to use as source"
                preferredStyle:UIAlertControllerStyleAlert];

  [alert addAction:[UIAlertAction
                       actionWithTitle:@"Cancel"
                                 style:UIAlertActionStyleCancel
                                 handler:^(UIAlertAction *_Nonnull action) {
                                   keyCaptureCallback = nil;
                                   mouseButtonCaptureCallback = nil;
                                 }]];

  ignoreNextLeftClickCount = 1;

  [self presentViewController:alert
                     animated:YES
                   completion:^{
                     __weak typeof(self) weakSelf = self;

                     void (^handleCapturedSource)(GCKeyCode) = ^(
                         GCKeyCode capturedCode) {
                       dispatch_async(dispatch_get_main_queue(), ^{
                         __strong typeof(weakSelf) strongSelf = weakSelf;
                         if (!strongSelf)
                           return;

                         keyCaptureCallback = nil;
                         mouseButtonCaptureCallback = nil;

                         [strongSelf.presentedViewController
                             dismissViewControllerAnimated:YES
                                                completion:nil];

                         if (capturedCode == POPUP_KEY) {
                           UIAlertController *errorAlert = [UIAlertController
                               alertControllerWithTitle:@"Invalid Key"
                                                message:@"Cannot remap the Menu key (F1)"
                                         preferredStyle:
                                             UIAlertControllerStyleAlert];
                           [errorAlert
                               addAction:
                                   [UIAlertAction
                                       actionWithTitle:@"OK"
                                                 style:UIAlertActionStyleDefault
                                               handler:nil]];
                           [strongSelf presentViewController:errorAlert
                                                    animated:YES
                                                  completion:nil];
                           return;
                         }

                         [strongSelf
                             showTargetKeyPickerForSourceKey:capturedCode];
                       });
                     };

                     keyCaptureCallback = ^(GCKeyCode keyCode) {
                       handleCapturedSource(keyCode);
                     };

                     mouseButtonCaptureCallback = ^(int buttonCode) {
                       handleCapturedSource((GCKeyCode)buttonCode);
                     };
                   }];
}

- (void)changeSourceKeyTapped:(UIButton *)sender {
  GCKeyCode oldSourceKey = sender.tag;

  UIAlertController *alert =
      [UIAlertController alertControllerWithTitle:@"Change Source Key"
                                          message:@"Press a key or mouse button"
                                   preferredStyle:UIAlertControllerStyleAlert];

  [alert addAction:[UIAlertAction
                       actionWithTitle:@"Cancel"
                                 style:UIAlertActionStyleCancel
                                 handler:^(UIAlertAction *_Nonnull action) {
                                   keyCaptureCallback = nil;
                                   mouseButtonCaptureCallback = nil;
                                 }]];

  ignoreNextLeftClickCount = 1;

  [self presentViewController:alert
                     animated:YES
                   completion:^{
                     __weak typeof(self) weakSelf = self;

                     void (^handleCaptured)(GCKeyCode) = ^(
                         GCKeyCode capturedCode) {
                       dispatch_async(dispatch_get_main_queue(), ^{
                         __strong typeof(weakSelf) strongSelf = weakSelf;
                         if (!strongSelf)
                           return;

                         keyCaptureCallback = nil;
                         mouseButtonCaptureCallback = nil;

                         [strongSelf.presentedViewController
                             dismissViewControllerAnimated:YES
                                                completion:nil];

                         if (capturedCode == POPUP_KEY) {
                           UIAlertController *errorAlert = [UIAlertController
                               alertControllerWithTitle:@"Invalid Key"
                                                message:@"Cannot remap the Menu key (F1)"
                                         preferredStyle:
                                             UIAlertControllerStyleAlert];
                           [errorAlert
                               addAction:
                                   [UIAlertAction
                                       actionWithTitle:@"OK"
                                                 style:UIAlertActionStyleDefault
                                               handler:nil]];
                           [strongSelf presentViewController:errorAlert
                                                    animated:YES
                                                  completion:nil];
                           return;
                         }

                         NSNumber *targetKey = keyRemappings[@(oldSourceKey)];
                         [keyRemappings removeObjectForKey:@(oldSourceKey)];
                         keyRemappings[@(capturedCode)] = targetKey;
                         saveKeyRemappings();
                         [strongSelf refreshKeyRemapRows];
                         [strongSelf
                             showFeedback:[NSString
                                              stringWithFormat:
                                                  @"Source changed: %@ → %@",
                                                  getKeyName(capturedCode),
                                                  getKeyName(
                                                      [targetKey integerValue])]
                                    color:[UIColor colorWithRed:0.3
                                                          green:0.9
                                                           blue:0.3
                                                          alpha:1.0]];
                       });
                     };

                     keyCaptureCallback = ^(GCKeyCode keyCode) {
                       handleCaptured(keyCode);
                     };
                     mouseButtonCaptureCallback = ^(int buttonCode) {
                       handleCaptured((GCKeyCode)buttonCode);
                     };
                   }];
}

- (void)changeTargetKeyTapped:(UIButton *)sender {
  GCKeyCode sourceKey = sender.tag;

  UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:@"Change Target Key"
                       message:[NSString stringWithFormat:
                                             @"Remapping: %@\nPress a keyboard "
                                             @"key for the target",
                                             getKeyName(sourceKey)]
                preferredStyle:UIAlertControllerStyleAlert];

  [alert addAction:[UIAlertAction
                       actionWithTitle:@"Cancel"
                                 style:UIAlertActionStyleCancel
                                 handler:^(UIAlertAction *_Nonnull action) {
                                   keyCaptureCallback = nil;
                                   mouseButtonCaptureCallback = nil;
                                 }]];

  ignoreNextLeftClickCount = 1;

  [self
      presentViewController:alert
                   animated:YES
                 completion:^{
                   __weak typeof(self) weakSelf = self;

                   keyCaptureCallback = ^(GCKeyCode keyCode) {
                     dispatch_async(dispatch_get_main_queue(), ^{
                       __strong typeof(weakSelf) strongSelf = weakSelf;
                       if (!strongSelf)
                         return;

                       keyCaptureCallback = nil;
                       mouseButtonCaptureCallback = nil;

                       [strongSelf.presentedViewController
                           dismissViewControllerAnimated:YES
                                              completion:nil];

                       if (keyCode == TRIGGER_KEY || keyCode == POPUP_KEY) {
                         UIAlertController *errorAlert = [UIAlertController
                             alertControllerWithTitle:@"Invalid Key"
                                              message:@"Cannot remap the Menu key (F1)"

                                       preferredStyle:
                                           UIAlertControllerStyleAlert];
                         [errorAlert
                             addAction:
                                 [UIAlertAction
                                     actionWithTitle:@"OK"
                                               style:UIAlertActionStyleDefault
                                             handler:nil]];
                         [strongSelf presentViewController:errorAlert
                                                  animated:YES
                                                completion:nil];
                         return;
                       }

                       if (isMouseInputCode(keyCode)) {
                         UIAlertController *errorAlert = [UIAlertController
                             alertControllerWithTitle:@"Invalid Target"
                                              message:@"Target must be a "
                                                      @"keyboard "
                                                      @"key, not a mouse button"
                                       preferredStyle:
                                           UIAlertControllerStyleAlert];
                         [errorAlert
                             addAction:
                                 [UIAlertAction
                                     actionWithTitle:@"OK"
                                               style:UIAlertActionStyleDefault
                                             handler:nil]];
                         [strongSelf presentViewController:errorAlert
                                                  animated:YES
                                                completion:nil];
                         return;
                       }

                       keyRemappings[@(sourceKey)] = @(keyCode);
                       saveKeyRemappings();
                       [strongSelf refreshKeyRemapRows];
                       [strongSelf
                           showFeedback:
                               [NSString
                                   stringWithFormat:@"Target changed: %@ → %@",
                                                    getKeyName(sourceKey),
                                                    getKeyName(keyCode)]
                                  color:[UIColor colorWithRed:0.3
                                                        green:0.9
                                                         blue:0.3
                                                        alpha:1.0]];
                     });
                   };

                 }];
}

- (void)deleteKeyRemapTapped:(UIButton *)sender {
  GCKeyCode sourceKey = sender.tag;
  NSNumber *targetKey = keyRemappings[@(sourceKey)];

  [keyRemappings removeObjectForKey:@(sourceKey)];

  saveKeyRemappings();

  [self refreshKeyRemapRows];

  [self showFeedback:[NSString
                         stringWithFormat:@"Removed: %@ → %@",
                                          getKeyName(sourceKey),
                                          getKeyName([targetKey integerValue])]
               color:[UIColor colorWithRed:0.3 green:0.9 blue:0.3 alpha:1.0]];
}

- (void)showTargetKeyPickerForSourceKey:(GCKeyCode)sourceKey {
  UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:@"Select Target Key"
                       message:[NSString stringWithFormat:
                                             @"Source: %@\nPress a keyboard "
                                             @"key for the target",
                                             getKeyName(sourceKey)]
                preferredStyle:UIAlertControllerStyleAlert];

  [alert addAction:[UIAlertAction
                       actionWithTitle:@"Cancel"
                                 style:UIAlertActionStyleCancel
                                 handler:^(UIAlertAction *_Nonnull action) {
                                   keyCaptureCallback = nil;
                                   mouseButtonCaptureCallback = nil;
                                 }]];

  ignoreNextLeftClickCount = 1;

  [self
      presentViewController:alert
                   animated:YES
                 completion:^{
                   __weak typeof(self) weakSelf = self;

                   keyCaptureCallback = ^(GCKeyCode keyCode) {
                     dispatch_async(dispatch_get_main_queue(), ^{
                       __strong typeof(weakSelf) strongSelf = weakSelf;
                       if (!strongSelf)
                         return;

                       keyCaptureCallback = nil;
                       mouseButtonCaptureCallback = nil;

                       [strongSelf.presentedViewController
                           dismissViewControllerAnimated:YES
                                              completion:nil];

                       if (keyCode == TRIGGER_KEY || keyCode == POPUP_KEY) {
                         UIAlertController *errorAlert = [UIAlertController
                             alertControllerWithTitle:@"Invalid Key"
                                              message:@"Cannot remap the Menu key (F1)"

                                       preferredStyle:
                                           UIAlertControllerStyleAlert];
                         [errorAlert
                             addAction:
                                 [UIAlertAction
                                     actionWithTitle:@"OK"
                                               style:UIAlertActionStyleDefault
                                             handler:nil]];
                         [strongSelf presentViewController:errorAlert
                                                  animated:YES
                                                completion:nil];
                         return;
                       }

                       if (isMouseInputCode(keyCode)) {
                         UIAlertController *errorAlert = [UIAlertController
                             alertControllerWithTitle:@"Invalid Target"
                                              message:@"Target must be a "
                                                      @"keyboard "
                                                      @"key, not a mouse button"
                                       preferredStyle:
                                           UIAlertControllerStyleAlert];
                         [errorAlert
                             addAction:
                                 [UIAlertAction
                                     actionWithTitle:@"OK"
                                               style:UIAlertActionStyleDefault
                                             handler:nil]];
                         [strongSelf presentViewController:errorAlert
                                                  animated:YES
                                                completion:nil];
                         return;
                       }

                       void (^createMapping)(void) = ^{
                         if (isMouseInputCode(sourceKey)) {
                           NSMutableDictionary *mouseBindings =
                               [[[NSUserDefaults standardUserDefaults]
                                   dictionaryForKey:@"mouseFortniteBindings"]
                                   mutableCopy];
                           if (mouseBindings &&
                               mouseBindings[[@(sourceKey) stringValue]]) {
                             [mouseBindings
                                 removeObjectForKey:[@(sourceKey) stringValue]];
                             [[NSUserDefaults standardUserDefaults]
                                 setObject:mouseBindings
                                    forKey:@"mouseFortniteBindings"];
                             [[NSUserDefaults standardUserDefaults]
                                 synchronize];
                           }
                         }

                         keyRemappings[@(sourceKey)] = @(keyCode);
                         saveKeyRemappings();
                         [strongSelf refreshKeyRemapRows];
                         [strongSelf
                             showFeedback:[NSString stringWithFormat:
                                                        @"Added: %@ → %@",
                                                        getKeyName(sourceKey),
                                                        getKeyName(keyCode)]
                                    color:[UIColor colorWithRed:0.3
                                                          green:0.9
                                                           blue:0.3
                                                          alpha:1.0]];
                       };

                       if (isMouseInputCode(sourceKey)) {
                         NSNumber *existingTarget = keyRemappings[@(sourceKey)];
                         if (existingTarget != nil &&
                             [existingTarget intValue] != 0 &&
                             [existingTarget intValue] != sourceKey) {
                           {
                             NSString *message = [NSString
                                 stringWithFormat:@"%@ is already mapped to "
                                                  @"%@. Saving will "
                                                  @"overwrite it. Continue?",
                                                  getKeyName(sourceKey),
                                                  getKeyName([existingTarget
                                                      intValue])];
                             UIAlertController *conflictAlert =
                                 [UIAlertController
                                     alertControllerWithTitle:@"Remap Conflict"
                                                      message:message
                                               preferredStyle:
                                                   UIAlertControllerStyleAlert];
                             [conflictAlert
                                 addAction:
                                     [UIAlertAction
                                         actionWithTitle:@"Cancel"
                                                   style:
                                                       UIAlertActionStyleCancel
                                                 handler:nil]];
                             [conflictAlert
                                 addAction:
                                     [UIAlertAction
                                         actionWithTitle:@"Continue Anyway"
                                                   style:
                                                       UIAlertActionStyleDestructive
                                                 handler:^(UIAlertAction
                                                               *_Nonnull a) {
                                                   createMapping();
                                                 }]];
                             [strongSelf presentViewController:conflictAlert
                                                      animated:YES
                                                    completion:nil];
                           }
                         } else {
                           createMapping();
                         }
                         return;
                       }

                       NSString *sourceConflict =
                           [strongSelf findFortniteActionUsingKey:sourceKey];
                       NSString *targetConflict =
                           [strongSelf findFortniteActionUsingKey:keyCode];

                       if (sourceConflict || targetConflict) {
                         NSMutableString *message = [NSMutableString string];
                         if (sourceConflict && targetConflict) {
                           [message
                               appendFormat:
                                   @"%@ is bound to %@ and %@ is bound to %@ "
                                   @"in Fortnite Keybinds. This custom remap "
                                   @"will override these keybinds. Continue?",
                                   getKeyName(sourceKey), sourceConflict,
                                   getKeyName(keyCode), targetConflict];
                         } else if (sourceConflict) {
                           [message appendFormat:
                                        @"%@ is bound to %@ in Fortnite "
                                        @"Keybinds. This custom remap will "
                                        @"override these keybinds. Continue?",
                                        getKeyName(sourceKey), sourceConflict];
                         } else {
                           [message appendFormat:
                                        @"%@ is bound to %@ in Fortnite "
                                        @"Keybinds. This custom remap will "
                                        @"override these keybinds. Continue?",
                                        getKeyName(keyCode), targetConflict];
                         }

                         UIAlertController *conflictAlert = [UIAlertController
                             alertControllerWithTitle:@"Key Conflict"
                                              message:message
                                       preferredStyle:
                                           UIAlertControllerStyleAlert];
                         [conflictAlert
                             addAction:
                                 [UIAlertAction
                                     actionWithTitle:@"Cancel"
                                               style:UIAlertActionStyleCancel
                                             handler:nil]];
                         [conflictAlert
                             addAction:
                                 [UIAlertAction
                                     actionWithTitle:@"Continue Anyway"
                                               style:
                                                   UIAlertActionStyleDestructive
                                             handler:^(
                                                 UIAlertAction *_Nonnull a) {
                                               createMapping();
                                             }]];
                         [strongSelf presentViewController:conflictAlert
                                                  animated:YES
                                                completion:nil];
                       } else {
                         createMapping();
                       }
                     });
                   };

                 }];
}

- (CGFloat)addSectionWithTitle:(NSString *)title
                      subtitle:(NSString *)subtitle
                           atY:(CGFloat)y
                        fields:(NSArray<NSDictionary *> *)fields
                      isDouble:(BOOL)isDouble
                        toView:(UIView *)parentView {
  CGFloat leftMargin = 20;
  CGFloat contentWidth = 290;

  CGFloat sectionHeight = isDouble ? 100 : 88;

  UIView *section = [[UIView alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, sectionHeight)];
  section.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.6];
  section.layer.cornerRadius = 8;
  section.layer.borderWidth = 0.5;
  section.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:0.4].CGColor;
  [parentView addSubview:section];

  UIButton *resetBtn = [UIButton buttonWithType:UIButtonTypeSystem];
  resetBtn.frame = CGRectMake(12, 9, 20, 20);
  [resetBtn setTitle:@"↪️" forState:UIControlStateNormal];
  resetBtn.titleLabel.font = [UIFont systemFontOfSize:14];
  NSMutableArray *pairs = [NSMutableArray array];
  for (NSDictionary *f in fields) {
    float resetVal = [f[@"default"] floatValue] ?: [f[@"value"] floatValue];
    [pairs addObject:[NSString
                         stringWithFormat:@"%@:%.1f", f[@"field"], resetVal]];
  }
  resetBtn.accessibilityLabel = [pairs componentsJoinedByString:@","];
  resetBtn.accessibilityHint = title;
  [resetBtn addTarget:self
                action:@selector(resetSectionTapped:)
      forControlEvents:UIControlEventTouchUpInside];
  [section addSubview:resetBtn];

  UILabel *titleLabel =
      [[UILabel alloc] initWithFrame:CGRectMake(36, 10, contentWidth - 48, 18)];
  titleLabel.text = title;
  titleLabel.textColor = [UIColor whiteColor];
  titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
  [section addSubview:titleLabel];

  UILabel *subtitleLabel =
      [[UILabel alloc] initWithFrame:CGRectMake(12, 30, contentWidth - 24, 14)];
  subtitleLabel.text = subtitle;
  subtitleLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
  subtitleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightRegular];
  [section addSubview:subtitleLabel];

  CGFloat fieldY = 48;
  CGFloat fieldSpacing = isDouble ? 12 : 0;
  CGFloat fieldWidth = isDouble ? (contentWidth - 36) / 2 : (contentWidth - 24);

  for (NSInteger i = 0; i < fields.count; i++) {
    NSDictionary *fieldInfo = fields[i];

    CGFloat fieldX = 12 + (i * (fieldWidth + fieldSpacing));

    if (isDouble) {
      UILabel *label = [[UILabel alloc]
          initWithFrame:CGRectMake(fieldX, fieldY, fieldWidth, 12)];
      label.text = fieldInfo[@"label"];
      label.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
      label.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
      label.textAlignment = NSTextAlignmentCenter;
      [section addSubview:label];
    }

    UITextField *field = [[UITextField alloc]
        initWithFrame:CGRectMake(fieldX, fieldY + (isDouble ? 14 : 0),
                                 fieldWidth, 24)];
    field.backgroundColor = [UIColor colorWithWhite:0.22 alpha:1.0];
    field.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    field.layer.cornerRadius = 4;
    field.borderStyle = UITextBorderStyleNone;
    field.keyboardType = UIKeyboardTypeDecimalPad;
    field.text =
        [NSString stringWithFormat:@"%.1f", [fieldInfo[@"value"] floatValue]];
    field.textAlignment = NSTextAlignmentCenter;
    field.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    field.delegate = self;

    [field addTarget:self
                  action:@selector(sensitivityFieldChanged:)
        forControlEvents:UIControlEventEditingChanged];

    [section addSubview:field];
    [self setValue:field forKey:fieldInfo[@"field"]];
    setShapeBorder(field, 4, 0.5, [UIColor colorWithWhite:0.35 alpha:1.0]);
  }

  return floor(y + sectionHeight + 8);
}

- (void)addDividerAtY:(CGFloat)y toView:(UIView *)parentView {
  y = floor(y);
  UIView *divider = [[UIView alloc] initWithFrame:CGRectMake(40, y, 250, 1)];
  divider.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.5];
  [parentView addSubview:divider];
}

- (void)closeButtonTapped {
  [self.view endEditing:YES];

  BOOL hasKeybindChanges = self.stagedKeybinds.count > 0;
  BOOL hasSensitivityChanges = [self hasSensitivityChanges];
  BOOL hasControllerChanges = self.stagedControllerMappings.count > 0;

  if (hasKeybindChanges || hasSensitivityChanges || hasControllerChanges) {
    NSMutableArray *changeTypes = [NSMutableArray array];
    if (hasKeybindChanges) [changeTypes addObject:@"keybind"];
    if (hasSensitivityChanges) [changeTypes addObject:@"sensitivity"];
    if (hasControllerChanges) [changeTypes addObject:@"controller"];

    NSString *typeStr;
    if (changeTypes.count == 1) {
      typeStr = changeTypes[0];
    } else if (changeTypes.count == 2) {
      typeStr = [NSString stringWithFormat:@"%@ and %@", changeTypes[0], changeTypes[1]];
    } else {
      typeStr = @"keybind, sensitivity, and controller";
    }

    NSString *message = [NSString stringWithFormat:@"You have unsaved %@ changes. What would you like to do?", typeStr];

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Unsaved Changes"
                         message:message
                  preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction
                         actionWithTitle:@"Save & Close"
                                   style:UIAlertActionStyleDefault
                                 handler:^(UIAlertAction *_Nonnull action) {

                                   if (hasSensitivityChanges) [self saveButtonTapped:nil];
                                   if (hasKeybindChanges) [self applyKeybindChangesTapped];
                                   if (hasControllerChanges) [self applyControllerChangesTapped];

                                   dispatch_after(
                                       dispatch_time(DISPATCH_TIME_NOW,
                                                     0.5 * NSEC_PER_SEC),
                                       dispatch_get_main_queue(), ^{
                                         extern BOOL isPopupVisible;
                                         extern UIWindow *popupWindow;
                                         isPopupVisible = NO;
                                         popupWindow.hidden = YES;
                                       });
                                 }]];

    [alert addAction:[UIAlertAction
                         actionWithTitle:@"Discard Changes"
                                   style:UIAlertActionStyleDestructive
                                 handler:^(UIAlertAction *_Nonnull action) {

                                   if (hasSensitivityChanges) {
                                     [self revertSensitivityChanges];
                                     [self updateSensitivityDiscardButton];
                                     [self updateSensitivityFieldBorders];
                                   }

                                   if (hasKeybindChanges) {
                                     [self.stagedKeybinds removeAllObjects];
                                     [self updateApplyChangesButton];
                                     [self refreshFortniteKeybinds];
                                   }

                                   if (hasControllerChanges) {
                                     [self.stagedControllerMappings removeAllObjects];
                                     [self updateControllerApplyButton];
                                     [self refreshControllerBindRows];
                                   }

                                   extern BOOL isPopupVisible;
                                   extern UIWindow *popupWindow;
                                   isPopupVisible = NO;
                                   popupWindow.hidden = YES;
                                 }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    [self presentViewController:alert animated:YES completion:nil];
  } else {

    isPopupVisible = NO;
    popupWindow.hidden = YES;
    [self pauseQuickStartVideos];
  }
}

- (BOOL)hasSensitivityChanges {
  float currentGyro = [self.gyroMultiplierField.text floatValue];

  float epsilon = 0.1f;

  return (fabsf(currentGyro - self.originalGyroMultiplier) > epsilon ||
          self.stagedDirectKey != self.originalDirectKey);
}

- (void)revertSensitivityChanges {
  self.gyroMultiplierField.text =
      [NSString stringWithFormat:@"%.1f", self.originalGyroMultiplier];

  GYRO_MULTIPLIER = self.originalGyroMultiplier;
  GCMOUSE_DIRECT_KEY = self.originalDirectKey;

  self.stagedDirectKey = self.originalDirectKey;

  NSString *keyStr = getKeyName(self.stagedDirectKey);
  [self.directKeyButton setTitle:(keyStr.length > 0 ? keyStr : @"-") forState:UIControlStateNormal];
  [self updateDirectKeyButtonStyle];

  recalculateSensitivities();
}

- (void)closeButtonHover:(UIHoverGestureRecognizer *)gesture {

  if (gesture.state == UIGestureRecognizerStateBegan ||
      gesture.state == UIGestureRecognizerStateChanged) {

    [UIView animateWithDuration:0.15
                     animations:^{
                       self.closeX.alpha = 1.0;
                     }];
  } else if (gesture.state == UIGestureRecognizerStateEnded ||
             gesture.state == UIGestureRecognizerStateCancelled) {

    [UIView animateWithDuration:0.15
                     animations:^{
                       self.closeX.alpha = 0.0;
                     }];
  }
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
  extern UIWindow *popupWindow;
  if (!popupWindow)
    return;

  UIWindowScene *scene = (UIWindowScene *)
      [[UIApplication sharedApplication].connectedScenes anyObject];
  CGRect screenBounds = scene ? scene.effectiveGeometry.coordinateSpace.bounds
                              : CGRectMake(0, 0, 390, 844);

  CGPoint delta = [gesture translationInView:nil];
  [gesture setTranslation:CGPointZero inView:nil];

  CGRect newFrame = popupWindow.frame;
  newFrame.origin.x += delta.x;
  newFrame.origin.y += delta.y;

  CGFloat minVisible = 40;
  newFrame.origin.x =
      MAX(-newFrame.size.width + minVisible,
          MIN(screenBounds.size.width - minVisible, newFrame.origin.x));
  newFrame.origin.y =
      MAX(-newFrame.size.height + minVisible,
          MIN(screenBounds.size.height - minVisible, newFrame.origin.y));

  popupWindow.frame = newFrame;
}

- (void)applyDefaultsTapped:(UIButton *)sender {
  self.gyroMultiplierField.text = @"100.0";

  GYRO_MULTIPLIER = 100.0f;

  self.stagedDirectKey = 0;
  GCMOUSE_DIRECT_KEY = 0;
  self.originalDirectKey = 0;

  recalculateSensitivities();

  NSDictionary *settings = @{
    kGyroMultiplierKey : @(GYRO_MULTIPLIER),
    kGCMouseDirectKey : @(GCMOUSE_DIRECT_KEY)
  };

  [[NSUserDefaults standardUserDefaults] setObject:settings
                                            forKey:kSettingsKey];

  self.originalGyroMultiplier = GYRO_MULTIPLIER;

  [self.directKeyButton setTitle:@"-" forState:UIControlStateNormal];
  [self updateDirectKeyButtonStyle];

  [self updateSensitivityFieldBorders];
  [self updateSensitivityDiscardButton];

  [self showFeedback:@"Defaults Applied & Saved"
               color:[UIColor colorWithRed:0.3 green:0.9 blue:0.3 alpha:1.0]];
}

- (void)resetAllSensitivityTapped {
  UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:@"Reset All Sensitivity?"
                       message:@"This will reset all sensitivity settings to "
                               @"recommended defaults"
                preferredStyle:UIAlertControllerStyleAlert];

  [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];
  [alert addAction:[UIAlertAction
                       actionWithTitle:@"Reset All"
                                 style:UIAlertActionStyleDestructive
                                 handler:^(UIAlertAction *_Nonnull action) {

                                   self.gyroMultiplierField.text = @"100.0";

                                   GYRO_MULTIPLIER = 100.0f;

                                   self.stagedDirectKey = 53;
                                   GCMOUSE_DIRECT_KEY = 53;
                                   self.originalDirectKey = 53;

                                   recalculateSensitivities();

                                   NSMutableDictionary *settings = [@{
                                     kGyroMultiplierKey : @(GYRO_MULTIPLIER),
                                     kGCMouseDirectKey : @(GCMOUSE_DIRECT_KEY)
                                   } mutableCopy];

                                   [[NSUserDefaults standardUserDefaults]
                                       setObject:settings
                                          forKey:kSettingsKey];

                                   self.originalGyroMultiplier = GYRO_MULTIPLIER;
                                   self.originalDirectKey = GCMOUSE_DIRECT_KEY;

                                   NSString *dKeyStr = getKeyName(53);
                                   [self.directKeyButton setTitle:(dKeyStr.length > 0 ? dKeyStr : @"-") forState:UIControlStateNormal];
                                   [self updateDirectKeyButtonStyle];

                                   [self updateSensitivityFieldBorders];
                                   [self updateSensitivityDiscardButton];

                                   [self showFeedback:@"All sensitivity reset to defaults"
                                                color:[UIColor colorWithRed:0.3 green:0.9 blue:0.3 alpha:1.0]];
                                 }]];

  [self presentViewController:alert animated:YES completion:nil];
}

- (void)saveButtonTapped:(UIButton *)sender {
  [self.view endEditing:YES];
  GYRO_MULTIPLIER = [self.gyroMultiplierField.text floatValue];
  GCMOUSE_DIRECT_KEY = self.stagedDirectKey;

  recalculateSensitivities();

  NSDictionary *settings = @{
    kGyroMultiplierKey : @(GYRO_MULTIPLIER),
    kGCMouseDirectKey : @(GCMOUSE_DIRECT_KEY)
  };

  [[NSUserDefaults standardUserDefaults] setObject:settings
                                            forKey:kSettingsKey];

  self.originalGyroMultiplier = GYRO_MULTIPLIER;
  self.originalDirectKey = GCMOUSE_DIRECT_KEY;

  [self updateSensitivityFieldBorders];
  [self updateSensitivityDiscardButton];

  [self showFeedback:@"Settings Saved"
               color:[UIColor colorWithRed:0.3 green:0.9 blue:0.3 alpha:1.0]];
}

- (void)showFeedback:(NSString *)message color:(UIColor *)color {

  CGFloat toastWidth = 240;
  CGFloat toastPadX = 16;
  CGFloat toastPadY = 14;

  NSString *fullText = [NSString stringWithFormat:@"%@ ✅", message];
  UILabel *messageLabel = [[UILabel alloc] init];
  messageLabel.text = fullText;
  messageLabel.textColor = color;
  messageLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
  messageLabel.textAlignment = NSTextAlignmentCenter;
  messageLabel.numberOfLines = 0;

  NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
  para.lineSpacing = 4;
  para.alignment = NSTextAlignmentCenter;
  NSAttributedString *attrText =
      [[NSAttributedString alloc] initWithString:fullText
                                      attributes:@{
                                        NSFontAttributeName : messageLabel.font,
                                        NSParagraphStyleAttributeName : para
                                      }];
  messageLabel.attributedText = attrText;

  CGFloat labelWidth = toastWidth - toastPadX * 2;
  CGFloat labelHeight =
      [messageLabel sizeThatFits:CGSizeMake(labelWidth, CGFLOAT_MAX)].height;
  CGFloat toastHeight = labelHeight + toastPadY * 2;

  CGFloat centerX = self.view.bounds.size.width / 2 - toastWidth / 2;
  CGFloat centerY = self.view.bounds.size.height / 2 - toastHeight / 2;

  UIView *toast = [[UIView alloc]
      initWithFrame:CGRectMake(centerX, centerY, toastWidth, toastHeight)];
  toast.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.95];
  toast.layer.cornerRadius = 12;
  toast.layer.borderWidth = 0.5;
  toast.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:0.8].CGColor;
  toast.alpha = 0;

  messageLabel.frame =
      CGRectMake(toastPadX, toastPadY, labelWidth, labelHeight);
  [toast addSubview:messageLabel];

  [self.view addSubview:toast];

  [UIView animateWithDuration:0.3
      animations:^{
        toast.alpha = 1.0;
      }
      completion:^(BOOL finished) {

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{
                         [UIView animateWithDuration:0.3
                             animations:^{
                               toast.alpha = 0;
                             }
                             completion:^(BOOL finished) {
                               [toast removeFromSuperview];
                             }];
                       });
      }];
}

- (BOOL)textField:(UITextField *)textField
    shouldChangeCharactersInRange:(NSRange)range
                replacementString:(NSString *)string {

  static NSCharacterSet *invalidChars = nil;
  if (!invalidChars) {
    NSCharacterSet *allowedChars =
        [NSCharacterSet characterSetWithCharactersInString:@"0123456789."];
    invalidChars = [allowedChars invertedSet];
  }

  if ([string rangeOfCharacterFromSet:invalidChars].location != NSNotFound) {
    return NO;
  }

  if ([textField.text containsString:@"."] && [string isEqualToString:@"."]) {
    return NO;
  }

  return YES;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)borderlessToggleChanged:(UISwitch *)sender {
  isBorderlessModeEnabled = sender.isOn;
  NSUserDefaults *prefs = tweakDefaults();
  [prefs setBool:isBorderlessModeEnabled forKey:kBorderlessWindowKey];
  [prefs synchronize];

  updateBorderlessMode();
}

- (void)selectFolderTapped:(UIButton *)sender {
  if (@available(iOS 14.0, *)) {
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc]
            initForOpeningContentTypes:@[ UTTypeFolder ]
                                asCopy:NO];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
  }
}

- (void)sensitivityFieldChanged:(UITextField *)textField {
  [self updateSensitivityDiscardButton];
  [self updateSensitivityFieldBorders];
}

- (void)updateSensitivityDiscardButton {
  int changeCount = 0;
  static float epsilon = 0.1f;

  if (self.gyroMultiplierField.text.length > 0 && fabsf([self.gyroMultiplierField.text floatValue] - self.originalGyroMultiplier) > epsilon)
    changeCount++;
  if (self.stagedDirectKey != self.originalDirectKey)
    changeCount++;

  [self.applySensitivityButton
      setTitle:[NSString stringWithFormat:@"Apply Changes (%d)", changeCount]
      forState:UIControlStateNormal];
  [self.discardSensitivityButton
      setTitle:[NSString stringWithFormat:@"Discard Changes (%d)", changeCount]
      forState:UIControlStateNormal];

  BOOL shouldEnable = (changeCount > 0);
  if (shouldEnable != self.applySensitivityButton.enabled) {
    self.discardSensitivityButton.enabled = shouldEnable;
    self.applySensitivityButton.enabled = shouldEnable;
    [UIView animateWithDuration:0.2
                     animations:^{
                       self.discardSensitivityButton.alpha =
                           shouldEnable ? 1.0 : 0.3;
                       self.applySensitivityButton.alpha =
                           shouldEnable ? 1.0 : 0.5;
                     }];
  }
}

static void setShapeBorder(UIView *view, CGFloat radius, CGFloat width,
                           UIColor *color) {
  static NSString *const kBorderLayerName = @"fnmt_border";

  for (CALayer *l in [view.layer.sublayers copy]) {
    if ([l.name isEqualToString:kBorderLayerName]) {
      [l removeFromSuperlayer];
      break;
    }
  }
  CAShapeLayer *border = [CAShapeLayer layer];
  border.name = kBorderLayerName;

  CGRect inset = CGRectInset(view.bounds, width / 2.0, width / 2.0);
  border.path = [UIBezierPath bezierPathWithRoundedRect:inset
                                           cornerRadius:radius - width / 2.0]
                    .CGPath;
  border.fillColor = UIColor.clearColor.CGColor;
  border.strokeColor = color.CGColor;
  border.lineWidth = width;
  [view.layer addSublayer:border];

  view.layer.borderWidth = 0;
  view.layer.cornerRadius = radius;
}

- (void)applyStyleToField:(UITextField *)field
                    saved:(float)savedVal
               defaultVal:(float)defaultVal
              currentText:(NSString *)currentText {
  float epsilon = 0.1f;
  float currentVal = [currentText floatValue];
  BOOL isUnsaved = fabsf(currentVal - savedVal) > epsilon;
  BOOL isNotDefault = fabsf(savedVal - defaultVal) > epsilon;

  field.layer.borderWidth = 0;

  if (isUnsaved) {
    field.backgroundColor = [UIColor colorWithWhite:0.22 alpha:1.0];
    field.textColor = [UIColor whiteColor];
    setShapeBorder(field, 4, 0.5,
                   [UIColor colorWithRed:1.0 green:0.9 blue:0.3 alpha:1.0]);
  } else if (isNotDefault) {
    field.backgroundColor = [UIColor colorWithWhite:0.22 alpha:1.0];
    field.textColor = [UIColor whiteColor];
    setShapeBorder(field, 4, 0.5, [UIColor colorWithWhite:0.65 alpha:1.0]);
  } else {
    field.backgroundColor = [UIColor colorWithWhite:0.22 alpha:1.0];
    field.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    setShapeBorder(field, 4, 0.5, [UIColor colorWithWhite:0.35 alpha:1.0]);
  }
}

- (void)updateDirectKeyButtonStyle {
  if (self.stagedDirectKey != self.originalDirectKey) {
    if (self.stagedDirectKey == 0) {

      [self.directKeyButton setTitleColor:[UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:1.0] forState:UIControlStateNormal];
      setShapeBorder(self.directKeyButton, 4, 0.5, [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:1.0]);
    } else {

      [self.directKeyButton setTitleColor:[UIColor colorWithRed:1.0 green:0.9 blue:0.2 alpha:1.0] forState:UIControlStateNormal];
      setShapeBorder(self.directKeyButton, 4, 0.5, [UIColor colorWithRed:0.8 green:0.7 blue:0.0 alpha:1.0]);
    }
  } else {
    if (self.stagedDirectKey == 53) {

      [self.directKeyButton setTitleColor:[UIColor colorWithWhite:0.6 alpha:1.0] forState:UIControlStateNormal];
      setShapeBorder(self.directKeyButton, 4, 0.5, [UIColor colorWithWhite:0.35 alpha:1.0]);
    } else {

      [self.directKeyButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
      setShapeBorder(self.directKeyButton, 4, 0.5, [UIColor colorWithWhite:0.65 alpha:1.0]);
    }
  }
}

- (void)updateSensitivityFieldBorders {
  [self applyStyleToField:self.gyroMultiplierField
                    saved:self.originalGyroMultiplier
               defaultVal:100.0f
              currentText:self.gyroMultiplierField.text];

  [self updateDirectKeyButtonStyle];
}

- (void)mouseButtonTapped:(UIButton *)sender {
  UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:@"Direct GCMouse Mode"
                       message:@"Press any key or mouse button to bind it"
                preferredStyle:UIAlertControllerStyleAlert];

  [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

  ignoreNextLeftClickCount = 1;
  [self presentViewController:alert animated:YES completion:^{
    __weak typeof(self) weakSelf = self;

    void (^handleCaptured)(int) = ^(int code) {
      dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        keyCaptureCallback = nil;
        mouseButtonCaptureCallback = nil;

        [strongSelf.presentedViewController dismissViewControllerAnimated:YES completion:^{

          NSString *conflict = [strongSelf findAnyConflictDescriptionForCode:code];
          if (conflict) {
            UIAlertController *cnf = [UIAlertController
                alertControllerWithTitle:@"Key Conflict"
                                 message:[NSString stringWithFormat:@"%@ is already bound to %@. Continue?", getKeyName((GCKeyCode)code), (NSString *)conflict]
                          preferredStyle:UIAlertControllerStyleAlert];
            [cnf addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [cnf addAction:[UIAlertAction actionWithTitle:@"Continue Anyway" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
              [strongSelf resolveConflictForCode:code];
              strongSelf.stagedDirectKey = (GCKeyCode)code;
              NSString *ks = getKeyName((GCKeyCode)code);
              [strongSelf.directKeyButton setTitle:(ks.length > 0 ? ks : @"-") forState:UIControlStateNormal];
              [strongSelf updateDirectKeyButtonStyle];
              [strongSelf updateSensitivityDiscardButton];
            }]];
            [strongSelf presentViewController:cnf animated:YES completion:nil];
          } else {
            strongSelf.stagedDirectKey = (GCKeyCode)code;
            NSString *ks = getKeyName((GCKeyCode)code);
            [strongSelf.directKeyButton setTitle:(ks.length > 0 ? ks : @"-") forState:UIControlStateNormal];
            [strongSelf updateDirectKeyButtonStyle];
            [strongSelf updateSensitivityDiscardButton];
          }
        }];
      });
    };

    keyCaptureCallback = ^(GCKeyCode kc) {
        if (kc == 57) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) return;
                UIAlertController *err = [UIAlertController
                    alertControllerWithTitle:@"Invalid Key"
                                     message:@"Caps Lock is reserved for Typing Mode"
                              preferredStyle:UIAlertControllerStyleAlert];
                [err addAction:[UIAlertAction actionWithTitle:@"OK"
                                                        style:UIAlertActionStyleDefault
                                                      handler:nil]];
                [strongSelf presentViewController:err animated:YES completion:nil];
            });
            return;
        }
        handleCaptured((int)kc);
    };
    mouseButtonCaptureCallback = ^(int mc) { handleCaptured(mc); };
  }];
}

- (void)resetDirectKeyTapped {
    self.stagedDirectKey = 53;
    NSString *keyStr = getKeyName(53);
    [self.directKeyButton setTitle:(keyStr.length > 0 ? keyStr : @"-") forState:UIControlStateNormal];
    [self updateDirectKeyButtonStyle];
    [self updateSensitivityDiscardButton];

    [self saveButtonTapped:nil];
}

- (void)discardSensitivityChangesTapped {
  [self.view endEditing:YES];
  if (![self hasSensitivityChanges])
    return;

  [self revertSensitivityChanges];

  [self updateSensitivityDiscardButton];
  [self updateSensitivityFieldBorders];

  [self showFeedback:@"Changes Discarded"
               color:[UIColor colorWithRed:1.0 green:0.9 blue:0.3 alpha:1.0]];
}

- (void)resetSectionTapped:(UIButton *)sender {
  NSString *encoded = sender.accessibilityLabel;
  if (!encoded || encoded.length == 0)
    return;

  NSString *sectionTitle = sender.accessibilityHint ?: @"Section";

  NSMutableDictionary *fieldMap = [NSMutableDictionary dictionary];
  if (self.gyroMultiplierField) [fieldMap setObject:self.gyroMultiplierField forKey:@"gyroMultiplierField"];

  NSMutableArray *defaultStrings = [NSMutableArray array];
  NSArray *pairs = [encoded componentsSeparatedByString:@","];
  for (NSString *pair in pairs) {

    NSRange colonRange = [pair rangeOfString:@":"];
    if (colonRange.location == NSNotFound)
      continue;
    NSString *fieldKey = [pair substringToIndex:colonRange.location];
    NSString *valStr = [pair substringFromIndex:colonRange.location + 1];
    float defaultVal = [valStr floatValue];

    UITextField *field = fieldMap[fieldKey];
    if (field) {
      field.text = [NSString stringWithFormat:@"%.1f", defaultVal];
      [defaultStrings
          addObject:[NSString stringWithFormat:@"%.1f", defaultVal]];
    }

    if ([fieldKey isEqualToString:@"scaleField"]) {
      MACOS_TO_PC_SCALE = defaultVal;
      self.originalScale = defaultVal;
    } else if ([fieldKey isEqualToString:@"gyroMultiplierField"]) {
      GYRO_MULTIPLIER = defaultVal;
      self.originalGyroMultiplier = defaultVal;
    }
  }

  recalculateSensitivities();
  NSDictionary *settings = @{
    kScaleKey : @(MACOS_TO_PC_SCALE),
    kGyroMultiplierKey : @(GYRO_MULTIPLIER),
    kGCMouseDirectKey : @(GCMOUSE_DIRECT_KEY)
  };
  [[NSUserDefaults standardUserDefaults] setObject:settings
                                            forKey:kSettingsKey];

  [self updateSensitivityDiscardButton];
  [self updateSensitivityFieldBorders];

  NSString *defaultsStr = [defaultStrings componentsJoinedByString:@" / "];
  NSString *feedback =
      [NSString stringWithFormat:@"%@ reset to %@", sectionTitle, defaultsStr];
  [self showFeedback:feedback
               color:[UIColor colorWithRed:0.3 green:0.9 blue:0.3 alpha:1.0]];
}

- (void)exportSettings {

  NSMutableDictionary *exportData = [NSMutableDictionary dictionary];

  exportData[@"sensitivity"] = @{
    @"scale" : @(MACOS_TO_PC_SCALE),
    @"gyroMultiplier" : @(GYRO_MULTIPLIER),
    @"gcmouseDirectKey" : @(GCMOUSE_DIRECT_KEY)
  };

  NSDictionary *fortniteBinds = [[NSUserDefaults standardUserDefaults]
      dictionaryForKey:@"fortniteKeybinds"];
  if (fortniteBinds && fortniteBinds.count > 0) {

    NSMutableDictionary *cleanedFortniteBinds =
        [NSMutableDictionary dictionary];
    for (NSString *action in fortniteBinds) {
      id value = fortniteBinds[action];
      if ([value isKindOfClass:[NSNumber class]]) {
        cleanedFortniteBinds[action] = value;
      } else if ([value isKindOfClass:[NSString class]]) {
        cleanedFortniteBinds[action] =
            @([value integerValue]);
      }
    }
    exportData[@"fortniteKeybinds"] = cleanedFortniteBinds;
  }

  NSDictionary *savedRemaps =
      [[NSUserDefaults standardUserDefaults] dictionaryForKey:kKeyRemapKey];
  if (savedRemaps && savedRemaps.count > 0) {
    exportData[@"customRemaps"] = savedRemaps;
  }

  NSDictionary *mouseFortniteBindings = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"mouseFortniteBindings"];
  if (mouseFortniteBindings) exportData[@"mouseFortniteBindings"] = mouseFortniteBindings;

  NSDictionary *ctrlMappings = [tweakDefaults() dictionaryForKey:kControllerMappingKey];
  if (ctrlMappings) exportData[@"controllerMappings"] = ctrlMappings;

  NSArray *vctrlRemaps = [tweakDefaults() arrayForKey:kVCtrlRemapKey];
  if (vctrlRemaps) exportData[@"vctrlRemappings"] = vctrlRemaps;

  exportData[@"version"] = @"1.0";
  exportData[@"exportDate"] = [[NSDate date] description];

  NSError *error = nil;
  NSData *jsonData =
      [NSJSONSerialization dataWithJSONObject:exportData
                                      options:NSJSONWritingPrettyPrinted
                                        error:&error];

  if (error || !jsonData) {
    [self showFeedback:@"Export Failed" color:[UIColor redColor]];
    return;
  }

  self.exportData = jsonData;

  NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
  formatter.dateFormat = @"yyyy-MM-dd_HH-mm-ss";
  NSString *timestamp = [formatter stringFromDate:[NSDate date]];
  self.exportFileName =
      [NSString stringWithFormat:@"FnMacTweak_Settings_%@.json", timestamp];

  NSString *tempPath = [NSTemporaryDirectory()
      stringByAppendingPathComponent:self.exportFileName];
  NSURL *tempURL = [NSURL fileURLWithPath:tempPath];

  BOOL writeSuccess = [self.exportData writeToURL:tempURL atomically:YES];
  if (!writeSuccess) {
    [self showFeedback:@"Export Failed" color:[UIColor redColor]];
    return;
  }

  if (@available(iOS 14.0, *)) {
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc]
            initForExportingURLs:@[ tempURL ]
                          asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
  }
}

- (void)importSettings {
  if (@available(iOS 14.0, *)) {

    NSArray *contentTypes = @[ UTTypeJSON ];
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc]
            initForOpeningContentTypes:contentTypes
                                asCopy:NO];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
  }
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
  if (urls.count == 0)
    return;

  NSURL *url = urls.firstObject;
  NSString *pathExtension = url.pathExtension.lowercaseString;

  if ([pathExtension isEqualToString:@"json"]) {

    if ([url startAccessingSecurityScopedResource]) {
      NSError *error = nil;
      NSData *jsonData = [NSData dataWithContentsOfURL:url
                                               options:0
                                                 error:&error];
      [url stopAccessingSecurityScopedResource];

      if (error || !jsonData) {
        [self showFeedback:@"Import Failed" color:[UIColor redColor]];
        return;
      }

      NSDictionary *importData =
          [NSJSONSerialization JSONObjectWithData:jsonData
                                          options:0
                                            error:&error];

      if (error || !importData) {
        [self showFeedback:@"Invalid Settings File" color:[UIColor redColor]];
        return;
      }

      if (importData[@"sensitivity"]) {
        NSDictionary *sensitivity = importData[@"sensitivity"];
        MACOS_TO_PC_SCALE = [sensitivity[@"scale"] floatValue] ?: 20.0f;
        GYRO_MULTIPLIER = [sensitivity[@"gyroMultiplier"] floatValue] ?: 100.0f;
        GCMOUSE_DIRECT_KEY = (GCKeyCode)[sensitivity[@"gcmouseDirectKey"] integerValue];

        recalculateSensitivities();
        NSDictionary *settings = @{
          kScaleKey : @(MACOS_TO_PC_SCALE),
          kGyroMultiplierKey : @(GYRO_MULTIPLIER),
          kGCMouseDirectKey : @(GCMOUSE_DIRECT_KEY)
        };
        [[NSUserDefaults standardUserDefaults] setObject:settings
                                                  forKey:kSettingsKey];

        self.scaleField.text = [NSString stringWithFormat:@"%.1f", MACOS_TO_PC_SCALE];
        self.gyroMultiplierField.text = [NSString stringWithFormat:@"%.1f", GYRO_MULTIPLIER];

        self.originalScale = MACOS_TO_PC_SCALE;
        self.originalGyroMultiplier = GYRO_MULTIPLIER;
        self.stagedDirectKey = GCMOUSE_DIRECT_KEY;
        self.originalDirectKey = GCMOUSE_DIRECT_KEY;

        NSString *keyStr = getKeyName(GCMOUSE_DIRECT_KEY);
        [self.directKeyButton setTitle:(keyStr.length > 0 ? keyStr : @"-") forState:UIControlStateNormal];
        [self updateDirectKeyButtonStyle];

        [self updateSensitivityDiscardButton];
        [self updateSensitivityFieldBorders];
      }

      if (importData[@"fortniteKeybinds"]) {
        NSDictionary *fortniteBinds = importData[@"fortniteKeybinds"];
        [[NSUserDefaults standardUserDefaults] setObject:fortniteBinds
                                                  forKey:@"fortniteKeybinds"];

        loadFortniteKeybinds();
        [self refreshFortniteKeybinds];
      }

      if (importData[@"customRemaps"]) {
        NSDictionary *customRemaps = importData[@"customRemaps"];
        [[NSUserDefaults standardUserDefaults] setObject:customRemaps
                                                  forKey:kKeyRemapKey];

        loadKeyRemappings();
        [self refreshKeyRemapRows];
        [self updateApplyChangesButton];
      }

      if (importData[@"mouseFortniteBindings"]) {
        [[NSUserDefaults standardUserDefaults] setObject:importData[@"mouseFortniteBindings"] forKey:@"mouseFortniteBindings"];
      }

      if (importData[@"controllerMappings"]) {
        [tweakDefaults() setObject:importData[@"controllerMappings"] forKey:kControllerMappingKey];
      }
      if (importData[@"vctrlRemappings"]) {
        [tweakDefaults() setObject:importData[@"vctrlRemappings"] forKey:kVCtrlRemapKey];
      }

      if (importData[@"fortniteRemapArray"]) {
        [[NSUserDefaults standardUserDefaults] setObject:importData[@"fortniteRemapArray"] forKey:@"fortniteRemapArray"];
      }
      if (importData[@"mouseButtonRemapArray"]) {
        [[NSUserDefaults standardUserDefaults] setObject:importData[@"mouseButtonRemapArray"] forKey:@"mouseButtonRemapArray"];
      }
      if (importData[@"mouseFortniteArray"]) {
        [[NSUserDefaults standardUserDefaults] setObject:importData[@"mouseFortniteArray"] forKey:@"mouseFortniteArray"];
      }

      loadKeyRemappings();
      loadFortniteKeybinds();
      loadControllerMappings();

      [self.stagedControllerMappings removeAllObjects];
      self.stagedVCtrlRemappings = [NSMutableArray arrayWithArray:vctrlRemappings ?: @[]];

      [self refreshFortniteKeybinds];
      [self refreshKeyRemapRows];
      [self refreshControllerBindRows];
      [self refreshVCtrlRemapRows];
      [self updateApplyChangesButton];
      [self updateControllerApplyButton];

      if (importData[@"keybinds"] && !importData[@"customRemaps"]) {
        NSDictionary *keybinds = importData[@"keybinds"];
        [[NSUserDefaults standardUserDefaults] setObject:keybinds
                                                  forKey:kKeyRemapKey];

        loadKeyRemappings();
        [self refreshKeyRemapRows];
        [self updateApplyChangesButton];
      }

      [[NSUserDefaults standardUserDefaults] synchronize];
      [self showFeedback:@"Settings Imported Successfully"
                   color:[UIColor colorWithRed:0.3
                                         green:0.9
                                          blue:0.3
                                         alpha:1.0]];
    } else {

      [self showFeedback:@"Settings Exported Successfully"
                   color:[UIColor colorWithRed:0.3
                                         green:0.9
                                          blue:0.3
                                         alpha:1.0]];
    }
  } else {

    if ([url startAccessingSecurityScopedResource]) {
      NSError *error = nil;
      NSURLBookmarkCreationOptions options =
          (NSURLBookmarkCreationOptions)(1 << 11);
      NSData *bookmark = [url bookmarkDataWithOptions:options
                       includingResourceValuesForKeys:nil
                                        relativeToURL:nil
                                                error:&error];

      if (bookmark) {
        [[NSUserDefaults standardUserDefaults]
            setObject:bookmark
               forKey:@"fnmactweak.datafolder"];

        [self showFeedback:@"Restarting..."
                     color:[UIColor colorWithRed:1.0
                                           green:0.5
                                            blue:0.0
                                           alpha:1.0]];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.5 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{
                         exit(0);
                       });
      }

      [url stopAccessingSecurityScopedResource];
    }
  }
}

- (void)documentPickerWasCancelled:
    (UIDocumentPickerViewController *)controller {

}

@end
