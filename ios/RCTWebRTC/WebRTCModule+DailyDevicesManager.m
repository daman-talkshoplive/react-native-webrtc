//
//  WebRTCModule+DailyDevicesManager.m
//  react-native-webrtc
//
//  Created by Filipi Fuchter on 08/03/22.
//

#import <objc/runtime.h>
#import "WebRTCModule.h"
#import "WebRTCModule+DailyDevicesManager.h"
#import "WebRTCModule+DailyAudioMode.h"

@implementation WebRTCModule (DailyDevicesManager)

static NSString const *DEVICE_KIND_VIDEO_INPUT = @"videoinput";
static NSString const *DEVICE_KIND_AUDIO = @"audio";
BOOL _isAudioSessionRouteChangeRegistered = NO;
BOOL _isAudioSessionInterruptionRegistered = NO;
BOOL _isAudioSessionMediaServicesWereLostRegistered = NO;
BOOL _isAudioSessionMediaServicesWereResetRegistered = NO;
id _audioSessionRouteChangeObserver = nil;
id _audioSessionInterruptionObserver = nil;
id _audioSessionMediaServicesWereLostObserver = nil;
id _audioSessionMediaServicesWereResetObserver = nil;

- (void)setUserSelectedDevice:(NSString *)userSelectedDevice {
  objc_setAssociatedObject(self,
                           @selector(userSelectedDevice),
                           userSelectedDevice,
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSString *)userSelectedDevice {
  return  objc_getAssociatedObject(self, @selector(userSelectedDevice));
}

RCT_EXPORT_METHOD(enumerateDevices:(RCTResponseSenderBlock)callback)
{
    NSLog(@"[Daily] enumerateDevice from DailyDevicesManager");
    NSMutableArray *devices = [NSMutableArray array];

    [self fillVideoInputDevices:devices];
    [self fillAudioDevices:devices];

    callback(@[devices]);
}

// Whenever any headphones plugged in, it becomes the default audio route even if there is also bluetooth device.
// And it overwrites the handset(iPhone) option, which means you cannot change to the handset(iPhone).
- (void)fillVideoInputDevices:(NSMutableArray *)devices {
    AVCaptureDeviceDiscoverySession *videoevicesSession
        = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[ AVCaptureDeviceTypeBuiltInWideAngleCamera ]
                                                                 mediaType:AVMediaTypeVideo
                                                                  position:AVCaptureDevicePositionUnspecified];
    for (AVCaptureDevice *device in videoevicesSession.devices) {
        NSString *position = @"unknown";
        if (device.position == AVCaptureDevicePositionBack) {
            position = @"environment";
        } else if (device.position == AVCaptureDevicePositionFront) {
            position = @"user";
        }
        NSString *label = @"Unknown video device";
        if (device.localizedName != nil) {
            label = device.localizedName;
        }
        [devices addObject:@{
                             @"facing": position,
                             @"deviceId": device.uniqueID,
                             @"groupId": @"",
                             @"label": label,
                             @"kind": DEVICE_KIND_VIDEO_INPUT,
                             }];
    }
}

- (void)fillAudioDevices:(NSMutableArray *)devices {
    NSString * wiredOrEarpieceLabel = self.hasWiredHeadset ? @"Wired headset" : @"Phone earpiece";
    [devices addObject:@{
                         @"deviceId": WIRED_OR_EARPIECE_DEVICE_ID,
                         @"groupId": @"",
                         @"label": wiredOrEarpieceLabel,
                         @"kind": DEVICE_KIND_AUDIO,
                         }];

    [devices addObject:@{
                         @"deviceId": SPEAKERPHONE_DEVICE_ID,
                         @"groupId": @"",
                         @"label": @"Speakerphone",
                         @"kind": DEVICE_KIND_AUDIO,
                         }];

    [devices addObject:@{
                         @"deviceId": USB_DEVICE_ID,
                         @"groupId": @"",
                         @"label": @"External Microphone",
                         @"kind": DEVICE_KIND_AUDIO,
                         }];

    if(!self.hasWiredHeadset){
        [devices addObject:@{
                         @"deviceId": BLUETOOTH_DEVICE_ID,
                         @"groupId": @"",
                         @"label": @"Bluetooth",
                         @"kind": DEVICE_KIND_AUDIO,
                         }];
    }
}

- (BOOL)hasWiredHeadset {
    AVAudioSession *audioSession = AVAudioSession.sharedInstance;
    NSArray<AVAudioSessionPortDescription *> *availableInputs = [audioSession availableInputs];
    for (AVAudioSessionPortDescription *device in availableInputs) {
        NSString* portType = device.portType;
        if([portType isEqualToString:AVAudioSessionPortHeadphones] ||
           [portType isEqualToString:AVAudioSessionPortHeadsetMic] ){
            return true;
        }
    }
    return false;
}

- (BOOL)hasBluetoothDevice {
    AVAudioSession *audioSession = AVAudioSession.sharedInstance;

    NSArray<AVAudioSessionPortDescription *> *availableInputs = [audioSession availableInputs];
    for (AVAudioSessionPortDescription *device in availableInputs) {
        if([self isBluetoothDevice:[device portType]]){
            return true;
        }
    }

    NSArray<AVAudioSessionPortDescription *> *outputs = [[audioSession currentRoute] outputs];
    for (AVAudioSessionPortDescription *device in outputs) {
        if([self isBluetoothDevice:[device portType]]){
            return true;
        }
    }
    return false;
}

- (BOOL)isBluetoothDevice:(NSString*)portType {
    BOOL isBluetooth;
    isBluetooth = ([portType isEqualToString:AVAudioSessionPortBluetoothA2DP] ||
                   [portType isEqualToString:AVAudioSessionPortBluetoothHFP]);
    if (@available(iOS 7.0, *)) {
        isBluetooth |= [portType isEqualToString:AVAudioSessionPortBluetoothLE];
    }
    return isBluetooth;
}

- (BOOL)isUSBDevice:(NSString*)portType {
    return [portType isEqualToString:AVAudioSessionPortUSBAudio];
}

- (BOOL)isBuiltInSpeaker:(NSString*)portType {
    return [portType isEqualToString:AVAudioSessionPortBuiltInSpeaker];
}

- (BOOL)isBuiltInEarpieceHeadset:(NSString*)portType {
    return ([portType isEqualToString:AVAudioSessionPortBuiltInReceiver] ||
            [portType isEqualToString:AVAudioSessionPortHeadphones] ||
            [portType isEqualToString:AVAudioSessionPortHeadsetMic] );
}

- (BOOL)isBuiltInMic:(NSString*)portType {
    return ([portType isEqualToString:AVAudioSessionPortBuiltInMic]);
}

RCT_EXPORT_METHOD(getAudioDevice: (RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    NSLog(@"[Daily] getAudioDevice");
    AVAudioSession *audioSession = AVAudioSession.sharedInstance;
    NSArray<AVAudioSessionPortDescription *> *currentRoutes = [[audioSession currentRoute] outputs];
    if([currentRoutes count] > 0){
        NSString* currentPortType = [currentRoutes[0] portType];
        NSLog(@"[Daily] currentPortType: %@", currentPortType);
        if ([self isUSBDevice:currentPortType]) {
            return resolve(USB_DEVICE_ID);
        } else if([self isBluetoothDevice:currentPortType]){
            return resolve(BLUETOOTH_DEVICE_ID);
        } else if([self isBuiltInSpeaker:currentPortType]){
            return resolve(SPEAKERPHONE_DEVICE_ID);
        } else if([self isBuiltInEarpieceHeadset:currentPortType]){
            return resolve(WIRED_OR_EARPIECE_DEVICE_ID);
        }
    }
    return resolve(SPEAKERPHONE_DEVICE_ID);
}

// Some reference links explaining how the audio from IOs works and sample code
// https://stephen-chen.medium.com/how-to-add-audio-device-action-sheet-to-your-ios-app-e6bc401ccdbc
// https://github.com/xialin/AudioSessionManager/blob/master/AudioSessionManager.m
RCT_EXPORT_METHOD(setAudioDevice:(NSString*)deviceId) {
    NSLog(@"[Daily] setAudioDevice: %@", deviceId);

    [self setAudioMode: AUDIO_MODE_USER_SPECIFIED_ROUTE];
    self.userSelectedDevice = deviceId;

    // Ducking other apps' audio implicitly enables allowing mixing audio with
    // other apps, which allows this app to stay alive in the backgrounnd during
    // a call (assuming it has the voip background mode set).
    // After iOS 16, we must also always keep the bluetooth option here, otherwise
    // we are not able to see the bluetooth devices on the list
    AVAudioSessionCategoryOptions categoryOptions = (AVAudioSessionCategoryOptionAllowBluetooth |
                                                     AVAudioSessionCategoryOptionMixWithOthers);
    NSString *mode = AVAudioSessionModeVoiceChat;

    // Earpiece: is default route for a call.
    // Speaker: the speaker is the default output audio for like music, video, ring tone.
    // Bluetooth: whenever a bluetooth device connected, the bluetooth device will become the default audio route.
    // Headphones: whenever any headphones plugged in, it becomes the default audio route even there is also bluetooth device.
    //  And it overwrites the handset(iPhone) option, which means you cannot change to the earpiece, bluetooth.
    if([SPEAKERPHONE_DEVICE_ID isEqualToString: deviceId]){
        NSLog(@"[Daily] configuring output to SPEAKER");
        categoryOptions |= AVAudioSessionCategoryOptionDefaultToSpeaker;
        mode = AVAudioSessionModeDefault;
    } else if ([USB_DEVICE_ID isEqualToString: deviceId]) {
        NSLog(@"[Daily] configuring output to USB Device");
        mode = AVAudioSessionModeVideoRecording;
    }

    AVAudioSession *audioSession = AVAudioSession.sharedInstance;
    [self configureAudioSession:audioSession audioMode:mode categoryOptions:categoryOptions];

    // Force to speaker. We only need to do that the cases a wired headset is connected, but we still want to force to speaker
    if([SPEAKERPHONE_DEVICE_ID isEqualToString: deviceId]){
        [audioSession overrideOutputAudioPort: AVAudioSessionPortOverrideSpeaker error: nil];
    } else if([WIRED_OR_EARPIECE_DEVICE_ID isEqualToString: deviceId]) {
        [audioSession overrideOutputAudioPort: AVAudioSessionPortOverrideNone error: nil];
        NSArray<AVAudioSessionPortDescription *> *availableInputs = [audioSession availableInputs];
        for (AVAudioSessionPortDescription *device in availableInputs) {
            if([self isBuiltInMic:[device portType]]){
                NSLog(@"[Daily] forcing preferred input to built in device");
                [audioSession setPreferredInput:device error:nil];
                return;
            }
        }
    }
//      else if ([USB_DEVICE_ID isEqualToString: deviceId]) {
//         NSLog(@"[Daily] configuring output to USB Device 2");
//         [audioSession overrideOutputAudioPort: AVAudioSessionPortUSBAudio error: nil];
//     }
}

- (void)configureAudioSession:(nonnull AVAudioSession *)audioSession
              audioMode:(nonnull NSString *)mode
              categoryOptions: (AVAudioSessionCategoryOptions) categoryOptions
{
    NSLog(@"[Daily] configureAudioSession to %@ with options %lu", mode, (unsigned long)categoryOptions);
    // We need to set the mode before set the category, because when setting the node It can automatically change the categories.
    // This way we can enforce the categories that we want later.
    [self audioSessionSetMode:mode toSession:audioSession];
    if ([mode isEqualToString: AVAudioSessionModeVideoRecording]) {
        [audioSession overrideOutputAudioPort: AVAudioSessionPortUSBAudio error: nil];
        [self audioSessionSetCategory:AVAudioSessionCategoryRecord toSession:audioSession options:categoryOptions];
    } else {
        [self audioSessionSetCategory:AVAudioSessionCategoryPlayAndRecord toSession:audioSession options:categoryOptions];
    }
}

- (void)audioSessionSetCategory:(NSString *)audioCategory
                      toSession:(AVAudioSession *)audioSession
                        options:(AVAudioSessionCategoryOptions)options
{
  @try {
    [audioSession setCategory:audioCategory
                  withOptions:options
                        error:nil];
    NSLog(@"[Daily] audioSession.setCategory: %@, withOptions: %lu success", audioCategory, (unsigned long)options);
  } @catch (NSException *e) {
    NSLog(@"[Daily] audioSession.setCategory: %@, withOptions: %lu fail: %@", audioCategory, (unsigned long)options, e.reason);
  }
}

- (void)audioSessionSetMode:(NSString *)audioMode
                  toSession:(AVAudioSession *)audioSession
{
  @try {
    [audioSession setMode:audioMode error:nil];
    NSLog(@"[Daily] audioSession.setMode(%@) success", audioMode);
  } @catch (NSException *e) {
    NSLog(@"[Daily] audioSession.setMode(%@) fail: %@", audioMode, e.reason);
  }
}

- (id)startObserve:(NSString *)name
            object:(id)object
             queue:(NSOperationQueue *)queue
             block:(void (^)(NSNotification *))block
{
    return [[NSNotificationCenter defaultCenter] addObserverForName:name
                                               object:object
                                                queue:queue
                                           usingBlock:block];
}

- (void)stopObserve:(id)observer
             name:(NSString *)name
           object:(id)object
{
    if (observer == nil) return;
    [[NSNotificationCenter defaultCenter] removeObserver:observer
                                                    name:name
                                                  object:object];
}

- (void)startAudioSessionRouteChangeNotification
{

        if (_isAudioSessionRouteChangeRegistered) {
            return;
        }
        NSLog(@"[Daily].startAudioSessionRouteChangeNotification()");

        // --- in case it didn't deallocate when ViewDidUnload
        [self stopObserve:_audioSessionRouteChangeObserver
                     name: AVAudioSessionRouteChangeNotification
                   object: nil];

        _audioSessionRouteChangeObserver = [self startObserve:AVAudioSessionRouteChangeNotification
                                                       object: nil
                                                        queue: nil
                                                        block:^(NSNotification *notification) {
            if (notification.userInfo == nil
                || ![notification.name isEqualToString:AVAudioSessionRouteChangeNotification]) {
                // NSLog(@"[Daily]===============%@", notification);
                return;
            }

            NSNumber *routeChangeType = [notification.userInfo objectForKey:@"AVAudioSessionRouteChangeReasonKey"];
            NSUInteger routeChangeTypeValue = [routeChangeType unsignedIntegerValue];

            // NSLog(@"[Daily]=======================%@", notification);
            switch (routeChangeTypeValue) {
                case AVAudioSessionRouteChangeReasonUnknown:
                    NSLog(@"[Daily].AudioRouteChange.Reason: Unknown");
                    break;
                case AVAudioSessionRouteChangeReasonNewDeviceAvailable:
                    NSLog(@"[Daily].AudioRouteChange.Reason----: NewDeviceAvailable");

                    break;
                case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:
                    NSLog(@"[Daily].AudioRouteChange.Reason----: OldDeviceUnavailable");
                    break;
                case AVAudioSessionRouteChangeReasonCategoryChange:
                    NSLog(@"[Daily].AudioRouteChange.Reason: AVAudioSessionRouteChangeReasonCategoryChange");
                    break;
                case AVAudioSessionRouteChangeReasonOverride:
                    NSLog(@"[Daily].AudioRouteChange.Reason: Override");
                    break;
                case AVAudioSessionRouteChangeReasonWakeFromSleep:
                    NSLog(@"[Daily].AudioRouteChange.Reason: WakeFromSleep");
                    break;
                case AVAudioSessionRouteChangeReasonNoSuitableRouteForCategory:
                    NSLog(@"[Daily].AudioRouteChange.Reason: NoSuitableRouteForCategory");
                    break;
                case AVAudioSessionRouteChangeReasonRouteConfigurationChange:
                    NSLog(@"[Daily].AudioRouteChange.Reason: AVAudioSessionRouteChangeReasonRouteConfigurationChange");
                    break;
                default:
                    NSLog(@"[Daily].AudioRouteChange.Reason: Unknown Value");
                    break;
            };
        }];

        _isAudioSessionRouteChangeRegistered = YES;
}

- (void)startAudioSessionInterruptionNotification
{
    if (_isAudioSessionInterruptionRegistered) {
        return;
    }
    NSLog(@"[Daily].startAudioSessionInterruptionNotification()");

    // --- in case it didn't deallocate when ViewDidUnload
    [self stopObserve:_audioSessionInterruptionObserver
                 name:AVAudioSessionInterruptionNotification
               object:nil];

    _audioSessionInterruptionObserver = [self startObserve:AVAudioSessionInterruptionNotification
                                                    object:nil
                                                     queue:nil
                                                     block:^(NSNotification *notification) {
        if (notification.userInfo == nil
                || ![notification.name isEqualToString:AVAudioSessionInterruptionNotification]) {
            return;
        }

        //NSUInteger rawValue = notification.userInfo[AVAudioSessionInterruptionTypeKey].unsignedIntegerValue;
        NSNumber *interruptType = [notification.userInfo objectForKey:@"AVAudioSessionInterruptionTypeKey"];
        if ([interruptType unsignedIntegerValue] == AVAudioSessionInterruptionTypeBegan) {
            NSLog(@"[Daily].AudioSessionInterruptionNotification: Began");
        } else if ([interruptType unsignedIntegerValue] == AVAudioSessionInterruptionTypeEnded) {
            NSLog(@"[Daily].AudioSessionInterruptionNotification: Ended");
        } else {
            NSLog(@"[Daily].AudioSessionInterruptionNotification: Unknown Value");
        }
        //NSLog(@"[Daily].AudioSessionInterruptionNotification: could not resolve notification");
    }];

    _isAudioSessionInterruptionRegistered = YES;
}

- (void)startAudioSessionMediaServicesWereLostNotification
{
    if (_isAudioSessionMediaServicesWereLostRegistered) {
        return;
    }

    NSLog(@"[Daily].startAudioSessionMediaServicesWereLostNotification()");

    // --- in case it didn't deallocate when ViewDidUnload
    [self stopObserve:_audioSessionMediaServicesWereLostObserver
                 name:AVAudioSessionMediaServicesWereLostNotification
               object:nil];

    _audioSessionMediaServicesWereLostObserver = [self startObserve:AVAudioSessionMediaServicesWereLostNotification
                                                             object:nil
                                                              queue:nil
                                                              block:^(NSNotification *notification) {
        // --- This notification has no userInfo dictionary.
        NSLog(@"[Daily].AudioSessionMediaServicesWereLostNotification: Media Services Were Lost");
    }];

    _isAudioSessionMediaServicesWereLostRegistered = YES;
}

- (void)startAudioSessionMediaServicesWereResetNotification
{
    if (_isAudioSessionMediaServicesWereResetRegistered) {
        return;
    }

    NSLog(@"[Daily].startAudioSessionMediaServicesWereResetNotification()");

    // --- in case it didn't deallocate when ViewDidUnload
    [self stopObserve:_audioSessionMediaServicesWereResetObserver
                 name:AVAudioSessionMediaServicesWereResetNotification
               object:nil];

    _audioSessionMediaServicesWereResetObserver = [self startObserve:AVAudioSessionMediaServicesWereResetNotification
                                                              object:nil
                                                               queue:nil
                                                               block:^(NSNotification *notification) {
        // --- This notification has no userInfo dictionary.
        NSLog(@"[Daily].AudioSessionMediaServicesWereResetNotification: Media Services Were Reset");
    }];

    _isAudioSessionMediaServicesWereResetRegistered = YES;
}

- (void)devicesChanged:(NSNotification *)notification {
    // Possible change reasons: AVAudioSessionRouteChangeReasonOldDeviceUnavailable AVAudioSessionRouteChangeReasonNewDeviceAvailable
    NSInteger changeReason = [[notification.userInfo objectForKey:AVAudioSessionRouteChangeReasonKey] integerValue];
    NSLog(@"[Daily] devicesChanged %zd", changeReason);

    // AVAudioSessionRouteDescription *oldRoute = [notification.userInfo objectForKey:AVAudioSessionRouteChangePreviousRouteKey];
    // NSString *oldOutput = [[oldRoute.outputs objectAtIndex:0] portType];
    // AVAudioSessionRouteDescription *newRoute = [audioSession currentRoute];
    // NSString *newOutput = [[newRoute.outputs objectAtIndex:0] portType];

    [self sendEventWithName:kEventMediaDevicesOnDeviceChange body:@{}];
}

RCT_EXPORT_METHOD(startMediaDevicesEventMonitor) {
    NSLog(@"[Daily] startMediaDevicesEventMonitor");
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(devicesChanged:) name:AVAudioSessionRouteChangeNotification object:nil];
}

RCT_EXPORT_METHOD(stopMediaDevicesEventMonitor) {
    NSLog(@"[Daily] stopMediaDevicesEventMonitor");
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVAudioSessionRouteChangeNotification object:nil];

    // Reset all related variables to their initial states
    _isAudioSessionRouteChangeRegistered = NO;
    _audioSessionRouteChangeObserver = nil;
    _isAudioSessionInterruptionRegistered = NO;
    _audioSessionInterruptionObserver = nil;
    _isAudioSessionMediaServicesWereLostRegistered = NO;
    _audioSessionMediaServicesWereLostObserver = nil;
    _isAudioSessionMediaServicesWereResetRegistered = NO;
    _audioSessionMediaServicesWereResetObserver = nil;
}

@end
