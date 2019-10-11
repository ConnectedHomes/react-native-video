//
//  RCTAssetResourceLoaderDelegate.h
//  RCTVideo
//
//  Created by Vyacheslav Pogorelskiy on 20/06/2018.
//  Copyright (c) 2013 British Gas. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

/**
 * https://developer.apple.com/library/content/samplecode/sc1791/Introduction/Intro.html
 *
 * In order to have authentication with the requests for m3u8 playlists and AES key
 * we need to route the requests and handle them ourselves. It's not possible to add custom headers
 * or modify the requests which the resource loader executes.
 * This is why we route the requests that we need to modify and return the fetched response to the resource loader.
 *
 * The correct steps to start HLS are:
 * 1. Fetch master m3u8 playlist with scheme 'mplp' (add auth header), replace childs' schemes.
 * The player automatically decides which child playlist to use depending on the network conditions.
 * 2. Fetch the child playlists, replace AES key and ts files schemes.
 * The player automatically tries to send a request for the correct AES key.
 * 3. Fetch AES key for specific playlist with scheme 'ckey' (add auth header).
 * The player automatically asks for the ts files associated with a playlist.
 * 4. After intercepting the requests for ts files, fail each with redirect error and give the correct urls to the player to handle.
 * Because it does know how to handle them.
**/

@interface RCTAssetResourceLoaderDelegate : NSObject <AVAssetResourceLoaderDelegate>
@property (strong, nonatomic) NSString *accessToken;
@property (strong, nonatomic) NSString *accessTokenHeaderKey;
@property (readonly, nonatomic) dispatch_queue_t delegateQueue;
@property (readonly, nonatomic) NSError *error;
@end
