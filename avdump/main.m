
//  main.m
//  avdump
//
//  Created by Stephan Seidt on 11/27/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import <unistd.h>

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

#include <libavutil/mathematics.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>

#import "AVDumper.h"

/**
 * own defines
 */

#define BITRATE     400000
#define HEIGHT      480
#define OUTBUF_SIZE 200000
#define WIDTH       640

/**
 * from muxing.c
 */

#define STREAM_DURATION   10
#define STREAM_FRAME_RATE 25
#define STREAM_NB_FRAMES  ((int)(STREAM_DURATION * STREAM_FRAME_RATE))
#define STREAM_PIX_FMT PIX_FMT_YUV422P /* default pix_fmt */

static int sws_flags = SWS_BICUBIC;

AVFrame *picture, *tmp_picture;
uint8_t *video_outbuf;
int frame_count, video_outbuf_size;

/**
 * moved from main to global
 */
AVFormatContext *oc;
AVStream *video_st;

/* add a video output stream */
static AVStream *add_video_stream(AVFormatContext *oc, enum CodecID codec_id)
{
    AVCodecContext *c;
    AVStream *st;
    
    st = av_new_stream(oc, NULL);
    if (!st) {
        fprintf(stderr, "Could not alloc stream\n");
        exit(1);
    }
    
    c = st->codec;
    c->codec_id = codec_id;
    c->codec_type = AVMEDIA_TYPE_VIDEO;
    
    /* put sample parameters */
    c->bit_rate = BITRATE;
    /* resolution must be a multiple of two */
    c->width = WIDTH;
    c->height = HEIGHT;
    /* time base: this is the fundamental unit of time (in seconds) in terms
     of which frame timestamps are represented. for fixed-fps content,
     timebase should be 1/framerate and timestamp increments should be
     identically 1. */
    c->time_base.den = STREAM_FRAME_RATE;
    c->time_base.num = 1;
    c->gop_size = 12; /* emit one intra frame every twelve frames at most */
    c->pix_fmt = STREAM_PIX_FMT;
    if (c->codec_id == CODEC_ID_MPEG2VIDEO) {
        /* just for testing, we also add B frames */
        c->max_b_frames = 2;
    }
    if (c->codec_id == CODEC_ID_MPEG1VIDEO){
        /* Needed to avoid using macroblocks in which some coeffs overflow.
         This does not happen with normal video, it just happens here as
         the motion of the chroma plane does not match the luma plane. */
        c->mb_decision=2;
    }
    // some formats want stream headers to be separate
    if (oc->oformat->flags & AVFMT_GLOBALHEADER)
        c->flags |= CODEC_FLAG_GLOBAL_HEADER;
    
    return st;
}

extern AVFrame *alloc_picture(enum PixelFormat pix_fmt, int width, int height)
{
    AVFrame *picture;
    uint8_t *picture_buf;
    int size;
    
    picture = avcodec_alloc_frame();
    if (!picture)
        return NULL;
    size = avpicture_get_size(pix_fmt, width, height);
    picture_buf = av_malloc(size);
    if (!picture_buf) {
        av_free(picture);
        return NULL;
    }
    avpicture_fill((AVPicture *)picture, picture_buf,
                   pix_fmt, width, height);
    return picture;
}

static void open_video(AVFormatContext *oc, AVStream *st)
{
    AVCodec *codec;
    AVCodecContext *c;
    
    c = st->codec;
    
    /* find the video encoder */
    codec = avcodec_find_encoder(c->codec_id);
    if (!codec) {
        fprintf(stderr, "codec not found\n");
        exit(1);
    }
    
    /* open the codec */
    if (avcodec_open(c, codec) < 0) {
        fprintf(stderr, "could not open codec\n");
        exit(1);
    }
    
    video_outbuf = NULL;
    if (!(oc->oformat->flags & AVFMT_RAWPICTURE)) {
        /* allocate output buffer */
        /* XXX: API change will be done */
        /* buffers passed into lav* can be allocated any way you prefer,
         as long as they're aligned enough for the architecture, and
         they're freed appropriately (such as using av_free for buffers
         allocated with av_malloc) */
        video_outbuf_size = OUTBUF_SIZE;
        video_outbuf = av_malloc(video_outbuf_size);
    }
    
    /* allocate the encoded raw picture */
    picture = alloc_picture(c->pix_fmt, c->width, c->height);
    if (!picture) {
        fprintf(stderr, "Could not allocate picture\n");
        exit(1);
    }
    
    /* if the output format is not YUV420P, then a temporary YUV420P
     picture is needed too. It is then converted to the required
     output format */
    tmp_picture = NULL;
    if (c->pix_fmt != PIX_FMT_YUV420P) {
        tmp_picture = alloc_picture(PIX_FMT_YUV420P, c->width, c->height);
        if (!tmp_picture) {
            fprintf(stderr, "Could not allocate temporary picture\n");
            exit(1);
        }
    }
}

/* prepare a dummy image */
static void fill_yuv_image(AVFrame *pict, int frame_index, int width, int height)
{
    int x, y, i;
    
    i = frame_index;
    
    /* Y */
    for (y = 0; y < height; y++) {
        for (x = 0; x < width; x++) {
            pict->data[0][y * pict->linesize[0] + x] = x + y + i * 3;
        }
    }
    
    /* Cb and Cr */
    for (y = 0; y < height/2; y++) {
        for (x = 0; x < width/2; x++) {
            pict->data[1][y * pict->linesize[1] + x] = 128 + y + i * 2;
            pict->data[2][y * pict->linesize[2] + x] = 64 + x + i * 5;
        }
    }
}

extern void write_video_frame(AVFormatContext *oc, AVStream *st, AVFrame* frame)
{
    int out_size, ret;
    AVCodecContext *c;
    static struct SwsContext *img_convert_ctx;
    
    c = st->codec;
    
    if (frame_count >= STREAM_NB_FRAMES) {
        /* no more frame to compress. The codec has a latency of a few
         frames if using B frames, so we get the last frames by
         passing the same picture again */
    } else {
        if (c->pix_fmt != PIX_FMT_YUV420P) {
            /* as we only generate a YUV420P picture, we must convert it
             to the codec pixel format if needed */
            if (img_convert_ctx == NULL) {
                img_convert_ctx = sws_getContext(c->width, c->height,
                                                 PIX_FMT_BGRA,
                                                 c->width, c->height,
                                                 c->pix_fmt,
                                                 sws_flags, NULL, NULL, NULL);
                if (img_convert_ctx == NULL) {
                    fprintf(stderr, "Cannot initialize the conversion context\n");
                    exit(1);
                }
            }
            fill_yuv_image(tmp_picture, frame_count, c->width, c->height);
            sws_scale(img_convert_ctx, frame->data, frame->linesize,
                      0, c->height, picture->data, picture->linesize);
        } else {
            fill_yuv_image(picture, frame_count, c->width, c->height);
        }
    }
    
    
    if (oc->oformat->flags & AVFMT_RAWPICTURE) {
        /* raw video case. The API will change slightly in the near
         future for that. */
        AVPacket pkt;
        av_init_packet(&pkt);
        
        pkt.flags |= AV_PKT_FLAG_KEY;
        pkt.stream_index = st->index;
        pkt.data = (uint8_t *)picture;
        pkt.size = sizeof(AVPicture);
        
        ret = av_interleaved_write_frame(oc, &pkt);
    } else {
        /* encode the image */
        out_size = avcodec_encode_video(c, video_outbuf, video_outbuf_size, picture);
        /* if zero size, it means the image was buffered */
        if (out_size > 0) {
            AVPacket pkt;
            av_init_packet(&pkt);
            
            if (c->coded_frame->pts != AV_NOPTS_VALUE)
                pkt.pts= av_rescale_q(c->coded_frame->pts, c->time_base, st->time_base);
            if(c->coded_frame->key_frame)
                pkt.flags |= AV_PKT_FLAG_KEY;
            pkt.stream_index = st->index;
            pkt.data = video_outbuf;
            pkt.size = out_size;
            
            /* write the compressed frame in the media file */
            ret = av_interleaved_write_frame(oc, &pkt);
        } else {
            ret = 0;
        }
    }
    if (ret != 0) {
        fprintf(stderr, "Error while writing video frame\n");
        exit(1);
    }
    frame_count++;
}

static void close_video(AVFormatContext *oc, AVStream *st)
{
    avcodec_close(st->codec);
    av_free(picture->data[0]);
    av_free(picture);
    if (tmp_picture) {
        av_free(tmp_picture->data[0]);
        av_free(tmp_picture);
    }
    av_free(video_outbuf);
}

/**
 * end from muxing.c
 */

int main(int argc, const char * argv[]) {

    const char *filename;
    AVOutputFormat *fmt;

    av_register_all();

    filename = argv[1];

    /* allocate the output media context */
    avformat_alloc_output_context2(&oc, NULL, NULL, filename);
    if (!oc) {
        printf("Could not deduce output format from file extension: using MPEG2 Transport Stream.\n");
        avformat_alloc_output_context2(&oc, NULL, "mpegts", filename);
    }
    if (!oc) {
        exit(1);
    }
    fmt = oc->oformat;

    video_st = NULL;
    if (fmt->video_codec != CODEC_ID_NONE)
        video_st = add_video_stream(oc, fmt->video_codec);

//    av_dump_format(oc, 0, filename, 1);

    if (video_st)
        open_video(oc, video_st);

    if (!(fmt->flags & AVFMT_NOFILE)) {
        if (avio_open(&oc->pb, filename, AVIO_FLAG_WRITE) < 0) {
            fprintf(stderr, "Could not open '%s'\n", filename);
            exit(1);
        }
    }

    av_write_header(oc);

//    av_write_trailer(oc);
//
//    if (video_st)
//        close_video(oc, video_st);
//
//    for(i = 0; i < oc->nb_streams; i++) {
//        av_freep(&oc->streams[i]->codec);
//        av_freep(&oc->streams[i]);
//    }
//
//    if (!(fmt->flags & AVFMT_NOFILE)) {
//        /* close the output file */
//        avio_close(oc->pb);
//    }
//
//    /* free the stream */
//    av_free(oc);

    @autoreleasepool {
        AVDumper                 *avDumper;
        NSError                  *error;
        AVCaptureSession         *session;
        AVCaptureDevice          *videoDevice;
        AVCaptureDeviceInput     *videoDeviceInput;
//        AVCaptureScreenInput     *screenInput;
        AVCaptureVideoDataOutput *videoDataOutput;

        avDumper = [[AVDumper alloc] init];

        session = [[AVCaptureSession alloc] init];

        videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
        [session addOutput:videoDataOutput];
        
        videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
        [session addInput:videoDeviceInput];
        
//        screenInput = [[AVCaptureScreenInput alloc] initWithDisplayID:0];
//        [session addInput:screenInput];

        [session startRunning];

        dispatch_queue_t queue = dispatch_queue_create("myQueue", NULL);
        [videoDataOutput setSampleBufferDelegate:avDumper queue:queue];
        dispatch_release(queue);

        videoDataOutput.videoSettings = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA]
                                                                    forKey:(id)kCVPixelBufferPixelFormatTypeKey];

        AVCaptureConnection *connection = [videoDataOutput connectionWithMediaType:AVMediaTypeVideo];
        connection.videoMinFrameDuration = CMTimeMake(1, STREAM_FRAME_RATE);
        
        while (YES) {}
    }

    return 0;
}

