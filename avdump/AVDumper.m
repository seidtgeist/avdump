//
//  AVDumper.m
//  avdump
//
//  Created by Stephan Seidt on 11/27/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "AVDumper.h"

extern AVFormatContext *oc;
extern AVStream *video_st;

extern AVFrame *alloc_picture(enum PixelFormat pix_fmt, int width, int height);
extern void write_video_frame(AVFormatContext *oc, AVStream *st, AVFrame* frame);

@implementation AVDumper

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    // shorter&sufficient? http://stackoverflow.com/questions/4499160/how-to-convert-cmsamplebuffer-uiimage-into-ffmpegs-avpicture
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer); 
    size_t width = CVPixelBufferGetWidth(imageBuffer); 
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8, bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGImageRef quartzImage = CGBitmapContextCreateImage(context); 
    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
    CGContextRelease(context); 
    CGColorSpaceRelease(colorSpace);
    
//    NSLog(@"Sample buffer %@", quartzImage);

    AVFrame *pFrame = alloc_picture(PIX_FMT_BGRA, 640, 480);
    avpicture_fill((AVPicture*)pFrame, baseAddress, PIX_FMT_BGRA, 640, 480);

    write_video_frame(oc, video_st, pFrame);
    
    CGImageRelease(quartzImage);
}

@end
