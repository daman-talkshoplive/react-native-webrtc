//
//  WebRTCModule+Daily.m
//  react-native-webrtc
//
//  Created by daily-co on 7/10/20.
//

#import "WebRTCModule.h"
#import "WebRTCModule+DailyAudioMode.h"
#import "WebRTCModule+DailyDevicesManager.h"

#import <objc/runtime.h>
#import <WebRTC/RTCAudioSession.h>
#import <WebRTC/RTCAudioSessionConfiguration.h>

@interface WebRTCModule (Daily) <RTCAudioSessionDelegate>

// Expects to only be accessed on captureSessionQueue
@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong, readonly) dispatch_queue_t captureSessionQueue;

@end

@implementation WebRTCModule (Daily)

#pragma mark - enableNoOpRecordingEnsuringBackgroundContinuity

- (AVCaptureSession *)captureSession {
  return objc_getAssociatedObject(self, @selector(captureSession));
}

- (void)setCaptureSession:(AVCaptureSession *)captureSession {
  objc_setAssociatedObject(self, @selector(captureSession), captureSession, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (dispatch_queue_t)captureSessionQueue {
  dispatch_queue_t queue = objc_getAssociatedObject(self, @selector(captureSessionQueue));
  if (!queue) {
    queue = dispatch_queue_create("com.daily.noopcapturesession", DISPATCH_QUEUE_SERIAL);
    objc_setAssociatedObject(self, @selector(captureSessionQueue), queue, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  }
  return queue;
}

- (void)audioSession:(RTCAudioSession *)audioSession willSetActive:(BOOL)active {
  // Stop audio recording before RTCAudioSession becomes active, to defend
  // against the capture session interfering with WebRTC-managed audio session.
  dispatch_sync(self.captureSessionQueue, ^{
    [self.captureSession stopRunning];
    self.captureSession = nil;
  });
}

RCT_EXPORT_METHOD(enableNoOpRecordingEnsuringBackgroundContinuity:(BOOL)enable) {
  // Listen for RTCAudioSession becoming active, so we can stop recording.
  // We only need to record until WebRTC audio unit spins up, to keep the app
  // alive in the background. Recording for longer is wasteful and seems to
  // interfere with the WebRTC-managed audio session's activation.
  [RTCAudioSession.sharedInstance removeDelegate:self];
  if (enable) {
    [RTCAudioSession.sharedInstance addDelegate:self];
  }

  dispatch_async(self.captureSessionQueue, ^{
    if (enable) {
      if (self.captureSession) {
        return;
      }
      AVCaptureSession *captureSession = [self configuredCaptureSession];
      [captureSession startRunning];
      self.captureSession = captureSession;
    }
    else {
      [self.captureSession stopRunning];
      self.captureSession = nil;
    }
  });
}

// Expects to be invoked from captureSessionQueue
- (AVCaptureSession *)configuredCaptureSession {
  AVCaptureSession *captureSession = [[AVCaptureSession alloc] init];
  // Note: we *used* to have the following line:
  // captureSession.automaticallyConfiguresApplicationAudioSession = NO;
  // The original reason for it was to "prevent configuration 'thrashing' once
  // WebRTC audio unit takes the reins." As of 2023-08-23, I (kompfner) haven't
  // observed any audio misbehavior as a result of removing this line. Keeping
  // this line, on the other hand, was causing the no-op recording to error on
  // start, which in turn meant that your app would not stay alive in the
  // background if you joined a call with your cam and mic initially off.
  AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
  if (!audioDevice) {
    return nil;
  }
  NSError *inputError;
  AVCaptureDeviceInput *audioInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:&inputError];
  if (inputError) {
    return nil;
  }
  if ([captureSession canAddInput:audioInput]) {
    [captureSession addInput:audioInput];
  }
  else {
    return nil;
  }
  AVCaptureAudioDataOutput *audioOutput = [[AVCaptureAudioDataOutput alloc] init];
  if ([captureSession canAddOutput:audioOutput]) {
    [captureSession addOutput:audioOutput];
  }
  else {
    return nil;
  }
  return captureSession;
}

#pragma mark - setDailyAudioMode

- (void)audioSession:(RTCAudioSession *)audioSession didSetActive:(BOOL)active {
  // The audio session has become active either for the first time or again
  // after being reset by WebRTC's audio module (for example, after a Wifi -> LTE
  // switch), so (re-)apply the currently chosen audio mode to the session.
  [self applyAudioMode:self.audioMode toSession:audioSession];
}

RCT_EXPORT_METHOD(setDailyAudioMode:(NSString *)audioMode) {
  // Validate input
  if (![@[AUDIO_MODE_VIDEO_CALL, AUDIO_MODE_VOICE_CALL, AUDIO_MODE_IDLE] containsObject:audioMode]) {
    NSLog(@"[Daily] invalid argument to setDailyAudioMode: %@", audioMode);
    return;
  }

  [self setAudioMode: audioMode];

  // Apply the chosen audio mode right away if the audio session is already
  // active. Otherwise, it will be applied when the session becomes active.
  RTCAudioSession *audioSession = RTCAudioSession.sharedInstance;
  NSLog(@"[Daily] setDailyAudioMode: %@", audioMode);
  if (audioSession.isActive) {
    [self applyAudioMode:audioMode toSession:audioSession];
  }
}

- (void)applyAudioMode:(NSString *)audioMode toSession:(RTCAudioSession *)audioSession {
  NSLog(@"[Daily] applyAudioMode: %@", audioMode);
  // Do nothing if we're attempting to "unset" the in-call audio mode (for now
  // it doesn't seem like there's anything to do).
  if ([audioMode isEqualToString:AUDIO_MODE_IDLE]) {
    return;
  }

  if ([audioMode isEqualToString:AUDIO_MODE_USER_SPECIFIED_ROUTE]) {
    // Invoking to restore to the user chosen device
    [self setAudioDevice:self.userSelectedDevice];
    return;
  }

  // Ducking other apps' audio implicitly enables allowing mixing audio with
  // other apps, which allows this app to stay alive in the backgrounnd during
  // a call (assuming it has the voip background mode set).
  AVAudioSessionCategoryOptions categoryOptions = (AVAudioSessionCategoryOptionAllowBluetooth |
                                                   AVAudioSessionCategoryOptionMixWithOthers);
  if ([audioMode isEqualToString:AUDIO_MODE_VIDEO_CALL]) {
    categoryOptions |= AVAudioSessionCategoryOptionDefaultToSpeaker;
  }
  NSString *mode = ([audioMode isEqualToString:AUDIO_MODE_VIDEO_CALL] ?
                    AVAudioSessionModeVideoChat :
                    AVAudioSessionModeVoiceChat);
  [self configureAudioSession:AVAudioSession.sharedInstance audioMode:mode categoryOptions:categoryOptions];
}

@end
