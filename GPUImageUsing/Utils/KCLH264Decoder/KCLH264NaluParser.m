//
//  KCLH264NaluParser.m
//  KCLiveSDK
//
//  Created by Chentao on 2017/12/6.
//  Copyright © 2017年 Chentao. All rights reserved.
//

#import "KCLH264NaluParser.h"
#import "KCLLogger.h"
#import "KCLDataWriter.h"
#import "KCLDataReader.h"
#import "KCLUtilityMacro.h"

static const uint8_t kclLStartCodeLength = 4;
static const uint8_t kclLStartCode[] = { 0x00, 0x00, 0x00, 0x01 };

static const uint8_t kclSStartCodeLength = 3;
static const uint8_t kclSStartCode[] = { 0x00, 0x00, 0x01 };

@interface KCLH264NaluParser ()
@end

@implementation KCLH264NaluParser {
    NSMutableData *_dataBuffer;
    NSMutableData *_bigNaluPacketData;

    //    NSTimeInterval starttime;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _dataBuffer = [[NSMutableData alloc] init];
        _bigNaluPacketData = [[NSMutableData alloc] init];
    }
    return self;
}

- (void)pushData:(uint8_t *)data size:(NSUInteger)size {
    [_dataBuffer appendBytes:data length:size];
    NSUInteger dataBufferLength = _dataBuffer.length;
    if (dataBufferLength >= kclLStartCodeLength) {
        // int startCodeLength = kclLStartCodeLength;

        KCLH264Nalu *nalu = [self subNalu:_dataBuffer startCode:kclLStartCode startCodeLength:kclLStartCodeLength];
        if (!nalu) {
            // startCodeLength = kclSStartCodeLength;
            nalu = [self subNalu:_dataBuffer startCode:kclSStartCode startCodeLength:kclSStartCodeLength];
        }
        if (nalu && nalu.naluData.length > 0) {
            _dataBuffer = [[NSMutableData alloc] initWithData:[_dataBuffer subdataWithRange:NSMakeRange(nalu.naluData.length, dataBufferLength - nalu.naluData.length)]];
            if (!nalu.bad) {
                [self reorganizationNalu:nalu];
            }
        }
    }
}

- (KCLH264Nalu *)subNalu:(NSData *)sourceData startCode:(uint8_t *)startCode startCodeLength:(uint8_t)startCodeLength {
    NSUInteger location = sourceData.length - startCodeLength;

    BOOL equalStartCode = [self isEqualStartCode:startCode startCodeLength:startCodeLength targetData:(uint8_t *)(sourceData.bytes + location)];

    if (equalStartCode) {
        KCLH264Nalu *nalu = [[KCLH264Nalu alloc] init];
        nalu.nextStartCodeLength = startCodeLength;
        if (0 != location) {
            NSData *targetData = [sourceData subdataWithRange:NSMakeRange(0, location)];

            if (targetData.length > kclSStartCodeLength) {
                BOOL equalSStartCode = [self isEqualStartCode:kclSStartCode startCodeLength:kclSStartCodeLength targetData:(uint8_t *)targetData.bytes];
                if (equalSStartCode) {
                    nalu.startCodeLength = kclSStartCodeLength;
                } else {
                    if (targetData.length > kclLStartCodeLength) {
                        BOOL equalLStartCode = [self isEqualStartCode:kclLStartCode startCodeLength:kclLStartCodeLength targetData:(uint8_t *)targetData.bytes];
                        if (equalLStartCode) {
                            nalu.startCodeLength = kclLStartCodeLength;
                        }
                    } else {
                        nalu.bad = YES;
                        KCLLogError(@"bad nalu");
                    }
                }
            } else {
                nalu.bad = YES;
                KCLLogError(@"bad nalu");
            }

            nalu.naluData = targetData;
            return nalu;
        }
        return nalu;
    }
    return nil;
}

- (void)reorganizationNalu:(KCLH264Nalu *)nalu {
    KCLH264Nalu *naluPacket = [self naluConvertToNaluPacketData:nalu];
    switch (naluPacket.naluType) {
        case 6:
        case 7:
        case 8: {
            if (self.delegate) {
                [self.delegate h264NaluParser:self receiveNalu:naluPacket];
            }
            break;
        }
        default: {
            [_bigNaluPacketData appendData:naluPacket.naluData];
            if (kclLStartCodeLength == naluPacket.nextStartCodeLength) {
                if (self.delegate) {
                    KCLH264Nalu *bigNalu = [[KCLH264Nalu alloc] init];
                    bigNalu.naluData = _bigNaluPacketData;
                    bigNalu.naluType = naluPacket.naluType;
                    [self.delegate h264NaluParser:self receiveNalu:bigNalu];
                }
                _bigNaluPacketData = [[NSMutableData alloc] init];
            }
            break;
        }
    }
}

- (KCLH264Nalu *)naluConvertToNaluPacketData:(KCLH264Nalu *)nalu {
    uint32_t naluPacketDataSize = (uint32_t)(nalu.naluData.length - nalu.startCodeLength);
    uint8_t *pNaluPacketDataSize = (uint8_t *)(&naluPacketDataSize);

    NSMutableData *naluPacketData = [[NSMutableData alloc] init];
    // KCLDataWriter *naluPacketDataWriter = [[KCLDataWriter alloc] initWithData:naluPacketData];

    ///////////////////
    uint8_t dataSize[4] = { 0 };
    dataSize[0] = *(pNaluPacketDataSize + 3);
    dataSize[1] = *(pNaluPacketDataSize + 2);
    dataSize[2] = *(pNaluPacketDataSize + 1);
    dataSize[3] = *(pNaluPacketDataSize + 0);

    [naluPacketData appendBytes:dataSize length:4];
    ///////////////////

    NSData *sourceNaluData = [nalu.naluData subdataWithRange:NSMakeRange(nalu.startCodeLength, naluPacketDataSize)];
    [naluPacketData appendData:sourceNaluData];

    uint8_t *_pointer = (uint8_t *)sourceNaluData.bytes;

    int naluType = (_pointer[0] & 0x1F);

    KCLH264Nalu *newNalu = [[KCLH264Nalu alloc] init];
    newNalu.startCodeLength = nalu.startCodeLength;
    newNalu.naluData = naluPacketData;
    newNalu.naluType = naluType;
    newNalu.nextStartCodeLength = nalu.nextStartCodeLength;
    return newNalu;
}

- (BOOL)isEqualStartCode:(uint8_t *)startCode startCodeLength:(uint8_t)startCodeLength targetData:(uint8_t *)targetData {
    BOOL equalStartCode = YES;

    uint8_t *_pointer = targetData;

    size_t _poz = 0;

    while (_poz <= (startCodeLength - 1)) {
        uint8_t *ptr1 = _pointer + _poz;
        uint8_t *ptr2 = startCode + _poz;

        _poz += byteLength;

        uint8_t ptrValue1 = *(uint8_t *)ptr1;
        uint8_t ptrValue2 = *(uint8_t *)ptr2;

        if (ptrValue1 != ptrValue2) {
            equalStartCode = NO;
            break;
        }
    }
    return equalStartCode;
}

- (void)clear {
    _dataBuffer = [[NSMutableData alloc] init];
    _bigNaluPacketData = [[NSMutableData alloc] init];
}

@end
