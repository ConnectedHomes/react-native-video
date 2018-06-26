//
//  RCTAssetResourceLoaderDelegate.m
//  RCTVideo
//
//  Created by Vyacheslav Pogorelskiy on 20/06/2018.
//  Copyright (c) 2013 British Gas. All rights reserved.
//

#import "RCTAssetResourceLoaderDelegate.h"

typedef NS_ENUM(NSInteger, RCTResponseErrorCode) {
    RCTResponseErrorCodeRedirect = 302,
    RCTResponseErrorCodeBadRequest = 400,
    RCTResponseErrorCodeNotFound = 404
};

static NSString *const aesKeyPrefix = @"#EXT-X-KEY:METHOD=AES-128,URI=\"";
static NSString *const customMasterPlaylistScheme = @"mplp";
static NSString *const customPlaylistScheme = @"cplp";
static NSString *const customKeyScheme = @"ckey";
static NSString *const redirectScheme = @"rdtp";
static NSString *const httpsScheme = @"https";

@interface RCTAssetResourceLoaderDelegate ()

@property (assign, nonatomic) NSInteger errorCode;
@property (strong, nonatomic) dispatch_queue_t delegateQueue;

@end

@implementation RCTAssetResourceLoaderDelegate

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.delegateQueue = dispatch_queue_create("AssetResourceLoaderDelegateQueue", NULL);
    }
    return self;
}

#pragma mark - AVAssetResourceLoaderDelegate

- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)loadingRequest {
    
    NSString* scheme = loadingRequest.request.URL.scheme;
    if ([self isMasterPlaylistSchemeValid:scheme]) {
        [self handleMasterPlaylistRequest:loadingRequest];
        return YES;
    }
    
    if ([self isChildPlaylistSchemeValid:scheme]) {
        [self handleChildPlaylistRequest:loadingRequest];
        return YES;
    }
    
    if ([self isCustomKeySchemeValid:scheme]) {
        [self handleCustomKeyRequest:loadingRequest];
        return YES;
    }
    
    if ([self isRedirectSchemeValid:scheme]) {
        [self handleRedirectRequest:loadingRequest];
        return YES;
    }
    
    return NO;
}

#pragma mark - Working with Data

-(void)reportErrorWithCode:(RCTResponseErrorCode)errorCode forRequest:(AVAssetResourceLoadingRequest*)loadingRequest {
    self.errorCode = errorCode;
    
    NSError* responseError = [NSError errorWithDomain:NSURLErrorDomain
                                                 code:errorCode
                                             userInfo:nil];
    [loadingRequest finishLoadingWithError:responseError];
}

-(NSURL*)changeSchemeOf:(AVAssetResourceLoadingRequest*)loadingRequest from:(NSString*)from to:(NSString*)to {
    NSString *urlString = loadingRequest.request.URL.absoluteString;
    urlString = [urlString stringByReplacingOccurrencesOfString:from withString:to];
    
    return [NSURL URLWithString:urlString ];
}

-(void)getDataFrom:(NSURL*)url withRequest:(AVAssetResourceLoadingRequest*)loadingRequest modifyBlock:(NSData* (^)(NSData* data))modifyBlock {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    
    [request setAllHTTPHeaderFields:self.headers];
    
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:request
                                                               completionHandler:^(NSData *data, NSURLResponse *urlREsponse, NSError * error)
                                  {
                                      NSHTTPURLResponse *response = (NSHTTPURLResponse*)urlREsponse;
                                      if (response.statusCode == 200 && data != nil) {
                                          // Modify the data if block was passed.
                                          NSData *modifiedData = modifyBlock ? modifyBlock(data) : data;
                                          if (!modifiedData) {
                                              [weakSelf reportErrorWithCode:RCTResponseErrorCodeBadRequest forRequest:loadingRequest];
                                              return;
                                          }
                                          
                                          // Pass the data to the resource loader.
                                          [loadingRequest.dataRequest respondWithData:modifiedData];
                                          [loadingRequest finishLoading];
                                      } else {
                                          RCTResponseErrorCode errorCode = RCTResponseErrorCodeBadRequest;
                                          if (response.statusCode == RCTResponseErrorCodeNotFound) {
                                              errorCode = RCTResponseErrorCodeNotFound;
                                          }
                                          [weakSelf reportErrorWithCode:errorCode forRequest:loadingRequest];
                                      }
                                  }];
    
    [task resume];
}

#pragma mark - Master playlist handlers

-(BOOL)isMasterPlaylistSchemeValid:(NSString*)scheme {
    return  [scheme isEqualToString:customMasterPlaylistScheme];
}

-(NSURL*)generateMasterPlaylistUrl:(AVAssetResourceLoadingRequest*)loadingRequest {
    return [self changeSchemeOf:loadingRequest
                           from:customMasterPlaylistScheme
                             to:httpsScheme];
}

/**
 *  The delegate handler, handles the received request:
 *
 *  1) Verifies its a master playlist request, otherwise report an error.
 *  2) Generates the new URL
 *  3) Send a request, modify the received m3u8 file - change child playlist schemes.
 *  4) Create a reponse with the new URL and report success.
**/
-(void)handleMasterPlaylistRequest:(AVAssetResourceLoadingRequest*)loadingRequest {
    NSURL *url = [self generateMasterPlaylistUrl:loadingRequest];
    if (url) {
        __weak typeof(self) weakSelf = self;
        [self getDataFrom:url
              withRequest:loadingRequest
              modifyBlock:^NSData *(NSData *data) {
                  return [weakSelf modifyReceivedMasterPlaylist:data];
              }];
    } else {
        [self reportErrorWithCode:RCTResponseErrorCodeBadRequest forRequest:loadingRequest];
    }
}

-(NSData*)modifyReceivedMasterPlaylist:(NSData*)playlist {
    // Modify the https:// scheme of child playlists to be custom playlist one.
    NSString *m3u8Playlist = [[NSString alloc] initWithData:playlist encoding:NSUTF8StringEncoding];
    m3u8Playlist = [m3u8Playlist stringByReplacingOccurrencesOfString:httpsScheme withString:customPlaylistScheme];
    
    return [m3u8Playlist dataUsingEncoding:NSUTF8StringEncoding];
}

#pragma mark - Child playlist handlers

-(BOOL)isChildPlaylistSchemeValid:(NSString*)scheme {
    return [scheme isEqualToString:customPlaylistScheme];
}

-(NSURL*)generateChildPlaylistUrl:(AVAssetResourceLoadingRequest*)loadingRequest {
    return [self changeSchemeOf:loadingRequest
                           from:customPlaylistScheme
                             to:httpsScheme];
}

/**
 *  The delegate handler, handles the received request:
 *
 *  1) Verifies its a child playlist request, otherwise report an error.
 *  2) Generates the new URL
 *  3) Send a request, modify the received m3u8 file - change AES key and ts files schemes.
 *  4) Create a reponse with the new URL and report success.
**/
-(void)handleChildPlaylistRequest:(AVAssetResourceLoadingRequest*)loadingRequest {
    NSURL *url = [self generateChildPlaylistUrl:loadingRequest];
    if (url) {
        __weak typeof(self) weakSelf = self;
        [self getDataFrom:url
              withRequest:loadingRequest
              modifyBlock:^NSData *(NSData *data) {
                  return [weakSelf modifyReceivedChildPlaylist:data];
              }];
    } else {
        [self reportErrorWithCode:RCTResponseErrorCodeBadRequest forRequest:loadingRequest];
    }
}

-(NSData*)modifyReceivedChildPlaylist:(NSData*)playlist {
    NSString *m3u8Playlist = [[NSString alloc] initWithData:playlist encoding:NSUTF8StringEncoding];
    
    // 1. Modify the aes key
    NSString *fromString = [aesKeyPrefix stringByAppendingString:httpsScheme];
    NSString *toString = [aesKeyPrefix stringByAppendingString:customKeyScheme];
    m3u8Playlist = [m3u8Playlist stringByReplacingOccurrencesOfString:fromString
                                                           withString:toString];
    // 2. Then modify all https:// phrases
    fromString = [httpsScheme stringByAppendingString:@"://"];
    toString = [redirectScheme stringByAppendingString:@"://"];
    m3u8Playlist = [m3u8Playlist stringByReplacingOccurrencesOfString:fromString
                                                           withString:toString];
    
    return [m3u8Playlist dataUsingEncoding:NSUTF8StringEncoding];
}

#pragma mark - AES Key Handlers

-(BOOL)isCustomKeySchemeValid:(NSString*)scheme {
    return [scheme isEqualToString:customKeyScheme];
}

-(NSURL*)generateAESKeyUrl:(AVAssetResourceLoadingRequest*)loadingRequest {
    return [self changeSchemeOf:loadingRequest
                           from:customKeyScheme
                             to:httpsScheme];
}

-(void)handleCustomKeyRequest:(AVAssetResourceLoadingRequest*)loadingRequest {
    NSURL *url = [self generateAESKeyUrl:loadingRequest];
    if (url) {
        [self getDataFrom:url
              withRequest:loadingRequest
              modifyBlock:nil];
    } else {
        [self reportErrorWithCode:RCTResponseErrorCodeBadRequest forRequest:loadingRequest];
    }
}

#pragma mark - Redirection of requests

-(BOOL)isRedirectSchemeValid:(NSString*)scheme {
    return [scheme isEqualToString:redirectScheme];;
}

/**
 * Replace the redirect scheme with https scheme, add the headers.
**/
-(NSURLRequest*)generateRedirectRequest:(NSURLRequest*)sourceUrlRequest {
    NSString *urlString = sourceUrlRequest.URL.absoluteString;
    urlString = [urlString stringByReplacingOccurrencesOfString:redirectScheme withString:httpsScheme];
    
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *redirectRequest = [NSMutableURLRequest requestWithURL:url];
    
    redirectRequest.allHTTPHeaderFields = sourceUrlRequest.allHTTPHeaderFields;
    
    return redirectRequest;
}

/**
 *  The delegate handler, handles the received request:
 *
 *  1) Verifies its a redirect request, otherwise report an error.
 *  2) Generates the new URL
 *  3) Create a reponse with the new URL and report success.
**/
-(void)handleRedirectRequest:(AVAssetResourceLoadingRequest*)loadingRequest {
    NSURLRequest *request = loadingRequest.request;
    
    NSURLRequest *redirectRequest = [self generateRedirectRequest:request];
    
    NSURL *url = redirectRequest.URL;
    
    if (redirectRequest && url) {
        loadingRequest.redirect = redirectRequest;
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:url
                                                                  statusCode:RCTResponseErrorCodeRedirect
                                                                 HTTPVersion:nil
                                                                headerFields:nil];
        loadingRequest.response = response;
        [loadingRequest finishLoading];
    } else {
        [self reportErrorWithCode:RCTResponseErrorCodeBadRequest forRequest:loadingRequest];
    }
}

@end
