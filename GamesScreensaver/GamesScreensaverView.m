//
//  GamesScreensaverView.m
//  GamesScreensaver
//
//  Created by orta therox on 06/05/2013.
//  Copyright (c) 2013 Orta. All rights reserved.
//

#import "GamesScreensaverView.h"
#import "HCYoutubeParser.h"
#import <QuickTime/QuickTime.h>
#import <QTKit/QTKit.h>
#import "NSFileManager+DirectoryLocations.h"
#import "NSUserDefaults+ScreenSaverDefaults.h"
#import "AFDownloadRequestOperation.h"
#import "DDProgressView.h"
#import "NSString+MD5.h"
#import "ScreenSaverConfig.h"

static const CGSize ThumbnailSize = { 320.0, 260.0 };
static const CGSize ProgressSize = { 300.0, 20.0 };
static const CGSize LabelSize = { 300.0, 48.0 };

static NSString *ProgressDefault = @"ProgressDefault";
static NSString *FileMD5Default = @"FileMD5Default";
static NSString *YoutubeURLDefault = @"YoutubeURLDefault";
static NSString *MovieNameDefault = @"MovieNameDefault";
static NSString *MuteDefault = @"MuteDefault";

static AFDownloadRequestOperation *DownloadRequest;

@implementation GamesScreensaverView {
    NSString *_currentVideoPath;
    NSString *_currentVideoURL;
    NSString *_currentMovieName;

    NSInteger _numberOfFailedRequests;
    BOOL _isPreview;

    DDProgressView *_progressView;
    NSImageView *_thumbnailImageView;
    QTMovieView *_movieView;
    QTMovie *_movie;
    NSTextField *_infoLabel;

    ScreenSaverConfig *_config;
}

- (id)initWithFrame:(NSRect)frame isPreview:(BOOL)isPreview {
    self = [super initWithFrame:frame isPreview:isPreview];

    if (self) {
        [self setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
        [self setAutoresizesSubviews:YES];
        _isPreview = isPreview;
        _config = [[ScreenSaverConfig alloc] init];
    }
    return self;
}


- (void)startAnimation {
    [super startAnimation];

    NSString *md5Filename = [[NSUserDefaults userDefaults] stringForKey:FileMD5Default];
    if (md5Filename) {
        _currentVideoURL = [[NSUserDefaults userDefaults] stringForKey:YoutubeURLDefault];
        _currentVideoPath = [self appSupportPathWithFilename:md5Filename];
    }

    if ([[NSFileManager defaultManager] fileExistsAtPath:_currentVideoPath]){
        [self playDownloadedFileAtPath:_currentVideoPath];
    } else {
        [self getNextVideo];
    }
}

- (void)stopAnimation {
    [super stopAnimation];
    [DownloadRequest cancel];
    
    if (_movieView) {
        NSString *time = QTStringFromTime(_movie.currentTime);
        [[NSUserDefaults userDefaults] setValue:time forKey:ProgressDefault];
        [[NSUserDefaults userDefaults] synchronize];

        [_movie stop];
    }
}

- (void)setupPreview {
    NSTextField *textField = [[NSTextField alloc] initWithFrame:self.bounds];
    [textField setStringValue:@"NO PREVIEW"];
    [self addSubview:textField];
}

- (void)getNextVideo {
    if (!_currentVideoPath || !_currentVideoURL) {

        // If we have both of the above then skip finding
        // a new one from the JSON.

        NSArray *json = [_config appMetadata];
        NSInteger categoryIndex = arc4random() % json.count;
        NSDictionary *category = json[categoryIndex];

        //    NSString *console = category[@"console"];
        NSArray *movies = category[@"movies"];
        NSInteger movieIndex = arc4random() % movies.count;
        NSDictionary *movie = movies[movieIndex];

        _currentMovieName = movie[@"name"];
        _currentVideoURL = movie[@"url"];
        _currentVideoPath = [self appSupportPathWithFilename:[_currentMovieName MD5Hash]];

        [[NSUserDefaults userDefaults] setObject:_currentMovieName forKey:MovieNameDefault];
        [[NSUserDefaults userDefaults] setObject:[_currentMovieName MD5Hash] forKey:FileMD5Default];
        [[NSUserDefaults userDefaults] synchronize];

    }

    NSURL *youtubeURL = [NSURL URLWithString:_currentVideoURL];
    [HCYoutubeParser thumbnailForYoutubeURL:youtubeURL thumbnailSize:YouTubeThumbnailDefaultMaxQuality completeBlock:^(NSImage *image, NSError *error) {
        [self addThumbnailWithImage:image];
    }];

    if (!_isPreview) {

        [HCYoutubeParser h264videosWithYoutubeURL:youtubeURL completeBlock:^(NSDictionary *videoDictionary, NSError *error) {
            NSString *key = nil;
            for (NSString *potentialKey in _config.availableYoutubeSizes.reverseObjectEnumerator) {
                if(videoDictionary[potentialKey]){
                    key = potentialKey;
                }
            }

            NSString *youtubeMP4URL = videoDictionary[key];
            NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:youtubeMP4URL]];

            DownloadRequest = [[AFDownloadRequestOperation alloc] initWithRequest:request targetPath:_currentVideoPath shouldResume:YES];
            [DownloadRequest setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
                [self removeProgressIndicator];
                [self removeThumbnailImage];
                [self playDownloadedFileAtPath:_currentVideoPath];

            } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                if ([operation isCancelled]) return;

                if (_numberOfFailedRequests != 5) {
                    [self getNextVideo];
                }
                _numberOfFailedRequests++;
            }];

            [DownloadRequest setProgressiveDownloadProgressBlock:^(AFDownloadRequestOperation *operation, NSInteger bytesRead, long long totalBytesRead, long long totalBytesExpected, long long totalBytesReadForFile, long long totalBytesExpectedToReadForFile) {
                _progressView.progress = totalBytesReadForFile / (CGFloat)totalBytesExpectedToReadForFile;

                NSString *doneString = [self humanStringFromBytes:totalBytesReadForFile];
                NSString *todoString = [self humanStringFromBytes:totalBytesExpectedToReadForFile];
                NSString *labelString = [NSString stringWithFormat:@"%@ (%@/%@)", _currentMovieName, doneString, todoString];
                [_infoLabel setStringValue:labelString];
            }];

            [self addProgressIndicatorToView];
            [self addMovieLabel];
            [DownloadRequest start];
        }];
    }
}

- (void)addProgressIndicatorToView {
    [self removeProgressIndicator];

    CGFloat margin = 16;
    CGRect progressRect = CGRectMake(CGRectGetWidth(self.bounds)/2 - ProgressSize.width/2,
                                     CGRectGetHeight(self.bounds)/2 - ProgressSize.height - ThumbnailSize.height / 2 - margin,
                                     ProgressSize.width, ProgressSize.height);

    _progressView = [[DDProgressView alloc] initWithFrame:progressRect];
    [self addSubview:_progressView];
}

- (void)removeProgressIndicator {
    [_progressView removeFromSuperview];
    _progressView = nil;
}

- (void)addThumbnailWithImage:(NSImage *)image {
    [self removeThumbnailImage];

    CGRect imageRect = CGRectMake(CGRectGetWidth(self.bounds)/2 - ThumbnailSize.width/2,
                                  CGRectGetHeight(self.bounds)/2 - ThumbnailSize.height/2,
                                  ThumbnailSize.width, ThumbnailSize.height);

    _thumbnailImageView = [[NSImageView alloc] initWithFrame:imageRect];
    [_thumbnailImageView setImage:image];
    [self addSubview:_thumbnailImageView];
}

- (void)removeThumbnailImage {
    [_thumbnailImageView removeFromSuperview];
    _thumbnailImageView = nil;
}

- (void)addMovieLabel {
    [self removeLabel];
    CGFloat margin = 56 + ProgressSize.height;
    CGRect labelRect = CGRectMake(CGRectGetWidth(self.bounds)/2 - LabelSize.width/2,
                                  CGRectGetHeight(self.bounds)/2 - ProgressSize.height - ThumbnailSize.height / 2 - margin,
                                  LabelSize.width, LabelSize.height);

    _infoLabel = [[NSTextField alloc] initWithFrame:labelRect];
    [_infoLabel setStringValue:@""];
    [_infoLabel setBackgroundColor:[NSColor blackColor]];
    [_infoLabel setTextColor:[NSColor whiteColor]];
    [_infoLabel setBordered:NO];
    [_infoLabel setAlignment:NSCenterTextAlignment];
    [self addSubview:_infoLabel];
}

- (void)removeLabel {
    [_infoLabel removeFromSuperview];
    _infoLabel = nil;
}

- (void)playDownloadedFileAtPath:(NSString *)path {
    [_movieView removeFromSuperview];
    [_movie stop];

    _movieView = [[QTMovieView alloc] initWithFrame:self.bounds];
    [_movieView setControllerVisible:NO];
    _movieView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _movieView.autoresizesSubviews = YES;
    _movieView.preservesAspectRatio = YES;

    NSError *error = nil;
    _movie = [QTMovie movieWithFile:path error:&error];
    if (error) {
        NSLog(@"%@ ", error.localizedDescription);
    }
    [_movieView setMovie:_movie];

    [self addSubview:_movieView];

    if (!_isPreview) {
        [_movieView play:self];
    }

    BOOL muted = [[NSUserDefaults userDefaults] boolForKey:MuteDefault];
    if (muted) {
        [_movie setVolume:0];
    }

    NSString *timeString = [[NSUserDefaults userDefaults] stringForKey:ProgressDefault];
    if (timeString) {
        [_movie setCurrentTime: QTTimeFromString(timeString)];
    }

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(movieEnded) name:QTMovieDidEndNotification object:_movie];
}

-(void)setMuted:(BOOL)muted {
    CGFloat volume = (muted) ? 0 : 1;
    _movie.volume = volume;
}

- (void)movieEnded {
    NSError *error = nil;
    [[NSFileManager defaultManager] removeItemAtPath:_currentVideoPath error:&error];
    if (error) {
        NSLog(@"Error %@", error.localizedDescription);
        return;
    }

    _currentVideoURL = nil;
    _currentVideoPath = nil;

    [[NSUserDefaults userDefaults] removeObjectForKey:MovieNameDefault];
    [[NSUserDefaults userDefaults] removeObjectForKey:FileMD5Default];
    [[NSUserDefaults userDefaults] removeObjectForKey:ProgressDefault];

    [[NSUserDefaults userDefaults] synchronize];

    [_movieView removeFromSuperview];
    [self getNextVideo];
}

- (NSString *)appSupportPathWithFilename:(NSString *)filename {
    NSString *filePath = [[NSFileManager defaultManager] applicationSupportDirectory];
    NSString *fileWithExtention = [NSString stringWithFormat:@"%@.mp4", filename];
    return [filePath stringByAppendingPathComponent:fileWithExtention];
}

- (void)animateOneFrame {
    return;
}

- (BOOL)hasConfigureSheet {
    return YES;
}

- (NSWindow *)configureSheet {
    return [_config configureWindow];
}

- (NSString *)humanStringFromBytes:(double)bytes {
    if (bytes < 0) {
        bytes *= -1;
    }

    static const char units[] = { '\0', 'k', 'M', 'G', 'T', 'P', 'E', 'Z', 'Y' };
    static int maxUnits = sizeof units - 1;

    int multiplier = 1000;
    int exponent = 0;

    while (bytes >= multiplier && exponent < maxUnits) {
        bytes /= multiplier;
        exponent++;
    }

    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    [formatter setMaximumFractionDigits:0];
    // Beware of reusing this format string. -[NSString stringWithFormat] ignores \0, *printf does not.
    return [NSString stringWithFormat:@"%@ %cB", [formatter stringFromNumber: @(bytes)], units[exponent]];
}


@end
