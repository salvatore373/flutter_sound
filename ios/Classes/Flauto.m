/*
 * flauto is a flutter_sound module.
 * flutter_sound is distributed with a MIT License
 *
 * Copyright (c) 2018 dooboolab
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 */

/*
 * flauto is a flutter_sound module.
 * Its purpose is to offer higher level functionnalities, using MediaService/MediaBrowser.
 * This module may use flutter_sound module, but flutter_sound module may not depends on this module.
 */

#import "flauto.h"
#import "FlutterSoundPlugin.h"
#import "Track.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>


 @implementation Flauto {
    NSURL *audioFileURL;
    Track *track;
 }
int PLAYING_STATE = 0;
int PAUSED_STATE = 1;
int STOPPED_STATE = 2;

FlutterMethodChannel* _flautoChannel;
BOOL includeAPFeatures = false;
Flauto* flautoModule; // Singleton

//+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar fluttterSoundModule: (FlutterSoundPlugin*)fluttterModule {
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel = [FlutterMethodChannel
      methodChannelWithName:@"flauto"
            binaryMessenger:[registrar messenger]];
  Flauto* instance = [[Flauto alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
  _flautoChannel = channel;
}

extern void flautoreg(NSObject<FlutterPluginRegistrar>* registrar)
{
        [Flauto registerWithRegistrar: registrar];
}

-(FlutterMethodChannel*) getChannel {
  return _flautoChannel;
}


- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
   if ([@"startPlayerFromTrack" isEqualToString:call.method]) {
            NSDictionary* trackDict = (NSDictionary*) call.arguments[@"track"];
            track = [[Track alloc] initFromDictionary:trackDict];
           
           BOOL canSkipForward = [call.arguments[@"canSkipForward"] boolValue];
           BOOL canSkipBackward = [call.arguments[@"canSkipBackward"] boolValue];
           [self startPlayer:canSkipForward canSkipBackward:canSkipBackward result:result];
  } else if ([@"stopPlayer" isEqualToString:call.method]) {
         [super stopPlayer:result];
  } else if ([@"initializeMediaPlayer" isEqualToString:call.method]) {
         BOOL includeAudioPlayerFeatures = [call.arguments[@"includeAudioPlayerFeatures"] boolValue];
         [self initializeMediaPlayer:includeAudioPlayerFeatures result:result];
  } else if ([@"releaseMediaPlayer" isEqualToString:call.method]) {
         [self releaseMediaPlayer:result];
  } else {
         [super handleMethodCall: call  result: result];
  }
}

- (void)startPlayer:(BOOL)canSkipForward canSkipBackward: (BOOL)canSkipBackward result: (FlutterResult)result {
    if(!track) {
        result([FlutterError errorWithCode:@"UNAVAILABLE"
                                   message:@"The track passed to startPlayer is not valid."
                                   details:nil]);
    }
    
    
    // Check whether the audio file is stored as a path to a file or a buffer
    if([track isUsingPath]) {
        // The audio file is stored as a path to a file
        
        NSString *path = track.path;
        
        bool isRemote = false;
        // Check whether a path was given
        if ([path class] == [NSNull class]) {
            // No path was given, get the path to a default sound
            audioFileURL = [NSURL fileURLWithPath:[GetDirectoryOfType_FlutterSound(NSCachesDirectory) stringByAppendingString:@"sound.aac"]];
        } else {
            // A path was given, then create a NSURL with it
            NSURL *remoteUrl = [NSURL URLWithString:path];
            
            // Check whether the URL points to a local or remote file
            if(remoteUrl && remoteUrl.scheme && remoteUrl.host){
                audioFileURL = remoteUrl;
                isRemote = true;
            } else {
                audioFileURL = [NSURL URLWithString:path];
            }
        }
        
        // Check whether the file path poits to a remote or local file
        if (isRemote) {
            NSURLSessionDataTask *downloadTask = [[NSURLSession sharedSession]
                                                  dataTaskWithURL:audioFileURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                                                      // NSData *data = [NSData dataWithContentsOfURL:audioFileURL];
                                                      
                                                      // The file to play has been downloaded, then initialize the audio player
                                                      // and start playing.
                                                      
                                                      // We must create a new Audio Player instance to be able to play a different Url
                                                      audioPlayer = [[AVAudioPlayer alloc] initWithData:data error:nil];
                                                      audioPlayer.delegate = self;
                                                      
                                                      // Able to play in silent mode
                                                      [[AVAudioSession sharedInstance]
                                                       setCategory: AVAudioSessionCategoryPlayback
                                                       error: nil];
                                                      // Able to play in background
                                                      [[AVAudioSession sharedInstance] setActive: YES error: nil];
                                                      dispatch_async(dispatch_get_main_queue(), ^{
                                                          [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
                                                      });
                                                      
                                                      [audioPlayer play];
                                                      [self startTimer];
                                                      NSString *filePath = self->audioFileURL.absoluteString;
                                                      result(filePath);
                                                  }];
            
            [downloadTask resume];
        } else {
            // Initialize the audio player with the file that the given path points to,
            // and start playing.
            
            // if (!audioPlayer) { // Fix sound distoring when playing recorded audio again.
            audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:audioFileURL error:nil];
            audioPlayer.delegate = self;
            // }
            
            // Able to play in silent mode
            [[AVAudioSession sharedInstance]
             setCategory: AVAudioSessionCategoryPlayback
             error: nil];
            
            [audioPlayer play];
            [self startTimer];
            NSString *filePath = audioFileURL.absoluteString;
            result(filePath);
        }
    } else {
        // The audio file is stored as a buffer
        FlutterStandardTypedData* dataBuffer = (FlutterStandardTypedData*) track.dataBuffer;
        NSData* bufferData = [dataBuffer data];
        audioPlayer = [[AVAudioPlayer alloc] initWithData: bufferData error: nil];
        audioPlayer.delegate = self;
        [[AVAudioSession sharedInstance] setCategory: AVAudioSessionCategoryPlayback error: nil];
        [audioPlayer play];
        [self startTimer];
        result(@"Playing from buffer");
    }
    
    // [LARPOUX]!!!isPlaying = true;
    NSNumber *playingState = [NSNumber numberWithInt:PLAYING_STATE];
    [ [self getChannel] invokeMethod:@"updatePlaybackState" arguments:playingState];
    
    // Display the notification with the media controls
    if (includeAPFeatures) {
      [self setupRemoteCommandCenter:canSkipForward   canSkipBackward:canSkipBackward result:result];
      [self setupNowPlaying:nil];
    }
}

// Give the system information about what the audio player
// is currently playing. Takes in the image to display in the
// notification to control the media playback.
- (void)setupNowPlaying:(MPMediaItemArtwork*)albumArt{
    // Initialize the MPNowPlayingInfoCenter
    
    MPNowPlayingInfoCenter *playingInfoCenter = [MPNowPlayingInfoCenter defaultCenter];
    NSMutableDictionary *songInfo = [[NSMutableDictionary alloc] init];
    
    // Check whether an album art was given
    if(albumArt == nil) {
        // No images were given, then retrieve the album art for the
        // current track and, when retrieved, update these
        // information again.
        dispatch_async(dispatch_get_main_queue(), ^{
            NSURL *url = [NSURL URLWithString:self->track.albumArt];
            
            UIImage *artworkImage = [UIImage imageWithData:[NSData dataWithContentsOfURL:url]];
            if(artworkImage)
            {
                MPMediaItemArtwork *albumArt = [[MPMediaItemArtwork alloc] initWithImage: artworkImage];
                
                [self setupNowPlaying:albumArt];
            }
        });
    } else {
        // An image was given, then display it among the track information
        [songInfo setObject:albumArt forKey:MPMediaItemPropertyArtwork];
    }
    
    NSNumber *progress = [NSNumber numberWithDouble: audioPlayer.currentTime];
    NSNumber *duration = [NSNumber numberWithDouble: audioPlayer.duration];
    
    [songInfo setObject:track.title forKey:MPMediaItemPropertyTitle];
    [songInfo setObject:track.author forKey:MPMediaItemPropertyArtist];
    [songInfo setObject:progress forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
    [songInfo setObject:duration forKey:MPMediaItemPropertyPlaybackDuration];
    // [LARPOUX]!!! /// [songInfo setObject:[NSNumber numberWithDouble:(isPlaying ? 1.0f : 0.0f)] forKey:MPNowPlayingInfoPropertyPlaybackRate];
    
    [playingInfoCenter setNowPlayingInfo:songInfo];
}

// Give the system information about what to do when the notification
// control buttons are pressed.
- (void)setupRemoteCommandCenter:(BOOL)canSkipForward canSkipBackward: (BOOL)canSkipBackward result: (FlutterResult)result {
    MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    [commandCenter.togglePlayPauseCommand setEnabled:YES];
    [commandCenter.nextTrackCommand setEnabled:canSkipForward];
    [commandCenter.previousTrackCommand setEnabled:canSkipBackward];
    
    [commandCenter.togglePlayPauseCommand addTargetWithHandler: ^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        if(true /* [LARPOUX]!!!isPlaying*/) {
            [self pausePlayer: result];
        } else {
            [self resumePlayer: result];
        }
        
        // [[MediaController sharedInstance] playOrPauseMusic];    // Begin playing the current track.
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    
    
    // [commandCenter.playCommand setEnabled:YES];
    // [commandCenter.pauseCommand setEnabled:YES];
    //   [commandCenter.playCommand addTargetWithHandler: ^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
    //       // [[MediaController sharedInstance] playOrPauseMusic];    // Begin playing the current track.
    //       [self resumePlayer:result];
    //       return MPRemoteCommandHandlerStatusSuccess;
    //   }];
    //
    //   [commandCenter.pauseCommand addTargetWithHandler: ^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
    //       // [[MediaController sharedInstance] playOrPauseMusic];    // Begin playing the current track.
    //       [self pausePlayer:result];
    //       return MPRemoteCommandHandlerStatusSuccess;
    //   }];
    
    [commandCenter.nextTrackCommand addTargetWithHandler: ^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        [[self getChannel] invokeMethod:@"skipForward" arguments:nil];
        // [[MediaController sharedInstance] fastForward];    // forward to next track.
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    
    [commandCenter.previousTrackCommand addTargetWithHandler: ^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        [[self getChannel] invokeMethod:@"skipBackward" arguments:nil];
        // [[MediaController sharedInstance] rewind];    // back to previous track.
        return MPRemoteCommandHandlerStatusSuccess;
    }];
}


-(void)initializeMediaPlayer:(BOOL)includeAudioPlayerFeatures result: (FlutterResult)result {
    // Set whether we have to include the audio player features
    includeAPFeatures = includeAudioPlayerFeatures;
    // No further initialization is needed for the iOS audio player, then exit
    // the method.
    result(@"The player had already been initialized.");
}

- (void)releaseMediaPlayer:(FlutterResult)result {
    // The code used to release all the media player resources is the same of the one needed
    // to stop the media playback. Then, use that one.
    //[LARPOUX]!!! // [self stopRecorder:result];
    result(@"The player has been successfully released");
}



// post fix with _FlutterSound to avoid conflicts with common libs including path_provider
static NSString* GetDirectoryOfType_FlutterSound(NSSearchPathDirectory dir) {
    NSArray* paths = NSSearchPathForDirectoriesInDomains(dir, NSUserDomainMask, YES);
    return [paths.firstObject stringByAppendingString:@"/"];
}

-(void)updateProgress:(NSTimer*) timer
{
    // Get the duration of the current audio file
    NSNumber *duration = [NSNumber numberWithDouble:audioPlayer.duration * 1000];
    // Get the current position in the current audio file
    NSNumber *currentTime = [NSNumber numberWithDouble:audioPlayer.currentTime * 1000];
    
    // If the duration is null but the timer was started, stop it
    if ([duration intValue] == 0 && timer != nil) {
        [self stopTimer];
        return;
    }
     
     // Compose a string containing the status of the playback with duration and current position
     NSString* status = [NSString stringWithFormat:@"{\"duration\": \"%@\", \"current_position\": \"%@\"}", [duration stringValue], [currentTime stringValue]];
     /*
      NSDictionary *status = @{
      @"duration" : [duration stringValue],
      @"current_position" : [currentTime stringValue],
      };
      */
     
     // Pass the string containing the status of the playback to the native code
     [[self getChannel] invokeMethod:@"updateProgress" arguments:status];
 }

/*
- (void) stopTimer{
    // Invalidate the timer if it is valid
    if (timer != nil) {
        [timer invalidate];
        timer = nil;
    }
}

- (void)startTimer
{
    dispatch_async(dispatch_get_main_queue(), ^{
        timer = [NSTimer scheduledTimerWithTimeInterval:subscriptionDuration
                                                       target:self
                                                     selector:@selector(updateProgress:)
                                                     userInfo:nil
                                                      repeats:YES];
    });
}

*/
@end