/**
 * Copyright (c) 2015-present, Peel Technologies, Inc.
 * All rights reserved.
 */

#import "RCTAssert.h"
#import "RCTBridge.h"
#import "RCTConvert.h"
#import "RCTEventDispatcher.h"
#import "RCTLog.h"
#import "TcpSockets.h"
#import "TcpSocketClient.h"

// offset native ids by 5000
#define COUNTER_OFFSET 5000

@implementation TcpSockets
{
    NSMutableDictionary<NSNumber *,TcpSocketClient *> *_clients;
    int _counter;
}

RCT_EXPORT_MODULE()

@synthesize bridge = _bridge;

-(void)dealloc
{
    for (NSNumber *cId in _clients.allKeys) {
        [self destroyClient:cId callback:nil];
    }
}

- (TcpSocketClient *)createSocket:(nonnull NSNumber*)cId
{
    if (!cId) {
        RCTLogError(@"%@.createSocket called with nil id parameter.", [self class]);
        return nil;
    }

    if (!_clients) {
        _clients = [NSMutableDictionary new];
    }

    if (_clients[cId]) {
        RCTLogError(@"%@.createSocket called twice with the same id.", [self class]);
        return nil;
    }

    _clients[cId] = [TcpSocketClient socketClientWithId:cId andConfig:self];

    return _clients[cId];
}

RCT_EXPORT_METHOD(connect:(nonnull NSNumber*)cId
                  host:(NSString *)host
                  port:(int)port
                  withOptions:(NSDictionary *)options)
{
    TcpSocketClient *client = _clients[cId];
    if (!client) {
      client = [self createSocket:cId];
    }

    NSError *error = nil;
    if (![client connect:host port:port withOptions:options error:&error])
    {
        [self onError:client withError:error];
        return;
    }
}

RCT_EXPORT_METHOD(write:(nonnull NSNumber*)cId
                  string:(NSString *)base64String
                  callback:(RCTResponseSenderBlock)callback) {
    TcpSocketClient* client = [self findClient:cId callback:callback];
    if (!client) return;

    // iOS7+
    // TODO: use https://github.com/nicklockwood/Base64 for compatibility with earlier iOS versions
    NSData *data = [[NSData alloc] initWithBase64EncodedString:base64String options:0];
    [client writeData:data callback:callback];
}

RCT_EXPORT_METHOD(end:(nonnull NSNumber*)cId
                  callback:(RCTResponseSenderBlock)callback) {
    [self endClient:cId callback:callback];
}

RCT_EXPORT_METHOD(destroy:(nonnull NSNumber*)cId
                 callback:(RCTResponseSenderBlock)callback) {
    [self destroyClient:cId callback:callback];
}

RCT_EXPORT_METHOD(listen:(nonnull NSNumber*)cId
                  host:(NSString *)host
                  port:(int)port)
{
    TcpSocketClient* client = _clients[cId];
    if (!client) {
      client = [self createSocket:cId];
    }

    NSError *error = nil;
    if (![client listen:host port:port error:&error])
    {
        [self onError:client withError:error];
        return;
    }
}

- (void)onConnect:(TcpSocketClient*) client
{
    [self.bridge.eventDispatcher sendDeviceEventWithName:[NSString stringWithFormat:@"tcp-%@-connect", client.id]
                                                    body:[client getAddress]];
}

-(void)onConnection:(TcpSocketClient *)client toClient:(NSNumber *)clientID {
    _clients[client.id] = client;

    [self.bridge.eventDispatcher sendDeviceEventWithName:[NSString stringWithFormat:@"tcp-%@-connection", clientID]
                                                    body:@{ @"id": client.id, @"address" : [client getAddress] }];
}

- (void)onData:(NSNumber *)clientID data:(NSData *)data
{
    NSString *base64String = [data base64EncodedStringWithOptions:0];
    [self.bridge.eventDispatcher sendDeviceEventWithName:[NSString stringWithFormat:@"tcp-%@-data", clientID]
                                                    body:base64String];
}

- (void)onClose:(TcpSocketClient*) client withError:(NSError *)err
{
    if (err) {
      [self onError:client withError:err];
    }

    [self.bridge.eventDispatcher sendDeviceEventWithName:[NSString stringWithFormat:@"tcp-%@-close", client.id]
                                                    body:err == nil ? @NO : @YES];

    client.clientDelegate = nil;
    [_clients removeObjectForKey:client.id];
}

- (void)onError:(TcpSocketClient*) client withError:(NSError *)err {
    NSString *msg = [err userInfo][@"NSLocalizedFailureReason"] ?: [err userInfo][@"NSLocalizedDescription"];
    [self.bridge.eventDispatcher sendDeviceEventWithName:[NSString stringWithFormat:@"tcp-%@-error", client.id]
                                                    body:msg];

}

-(TcpSocketClient*)findClient:(nonnull NSNumber*)cId callback:(RCTResponseSenderBlock)callback
{
    TcpSocketClient *client = _clients[cId];
    if (!client) {
        if (!callback) {
            RCTLogError(@"%@.missing callback parameter.", [self class]);
        } else {
            callback(@[[NSString stringWithFormat:@"no client found with id %@", cId]]);
        }

        return nil;
    }

    return client;
}

-(void)endClient:(nonnull NSNumber*)cId
           callback:(RCTResponseSenderBlock)callback
{
    TcpSocketClient* client = [self findClient:cId callback:callback];
    if (!client) return;

    [client end];

    if (callback) callback(@[]);
}

-(void)destroyClient:(nonnull NSNumber*)cId
             callback:(RCTResponseSenderBlock)callback
{
    TcpSocketClient* client = [self findClient:cId callback:nil];
    if (!client) return;

    [client destroy];
    [_clients removeObjectForKey:cId];
}

-(NSNumber*)getNextId {
    return @(_counter++ + COUNTER_OFFSET);
}

@end
