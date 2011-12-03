//
//  AVDumper.h
//  avdump
//
//  Created by Stephan Seidt on 11/27/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <libavcodec/avcodec.h>
#import <libavformat/avformat.h>

@interface AVDumper : NSObject<AVCaptureVideoDataOutputSampleBufferDelegate>

@end
