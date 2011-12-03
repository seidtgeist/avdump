# avdump

Is

- avc
- avcap
- avcapture

a bettername?

## Beautification / internals

- Functionality should be inside a class, main should only do the necessary
- Cli handling should be its own class

## cli ideas

Camera capture example:

    avdump --cam 1 --size 320x240 --fps 15
    
    # shorthand args
    avdump -c 1 -s 320x240 -f 15

Switch audio source (--audio?):

    avdump --audio 2

    # shorthand args
    avdump -a 2

Screen capture example:

    avdump --screen 1 --scale 0.5 --fps 1
    
    # shorthand args
    avdump -s 1 -scale 0.5 -f 1

Listing cams, audio ins & screens (--cam or --camera?):

  avdump --cam --audio --screen
  
  #shorthand args
  avdump -c -a -s

Default is video settings determined by AVFoundation, default output is stdout:

    avdump > file.out

File output possible via arg:

    avdump -f file.out

Choosing codecs: Not sure if this should be allowed. Maybe allow switching between raw and h264/aac via raw flag.

Verbose flag outputs capture source(s), frame grabs, human readable bitrate:

    avdump -v

Theoretically multiple AV streams can be dumped into a single MPEG2-TS container, i.e. for simultaneous video chat & screen capture.
