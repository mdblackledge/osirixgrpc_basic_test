//
//  ServiceManager.m
//  ConsoleApp
//
//  Created by Richard Holbrey on 12/12/2020.
//

#import "gRPCServer.h"
#import "gRPCService.h"
#import "gRPCLog.h"

#include <string>

#include <grpcpp/grpcpp.h>
#include <grpcpp/health_check_service_interface.h>
#include <grpcpp/ext/proto_server_reflection_plugin.h>

// See https://philjordan.eu/article/mixing-objective-c-c++-and-objective-c++ for why this needs to be here.
@interface gRPCServer()
{
    std::unique_ptr<grpc::Server> server;
}
@end

@implementation gRPCServer

@synthesize address = _address;

-(void)dealloc
{
    [_address release];
    [lock release];
    [super dealloc];
}

-(id)initWithAddress:(NSString *)address
{
    self = [super init];
    if (!self) {
        gRPCLogError(@"Could not initialize server");
        return  nil;
    }
    lock = [[NSLock alloc] init];
    _address = [address retain];
    return self;
}

-(BOOL)active
{
    if (!serverThread)
    {
        return NO;
    }
    return [serverThread isExecuting];
}

-(void)endThreadNotification:(NSNotification *)notification
{
    if ([notification object] == serverThread)
    {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSThreadWillExitNotification object:serverThread];
        [serverThread release];
        serverThread = nil;
    }
}

-(void)start
{
    if ([self active])
    {
        gRPCLogError(@"Server cannot be started as already active.");
        return;
    }
    serverThread = [[NSThread alloc] initWithTarget:self selector:@selector(spawnInsecure) object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(endThreadNotification:) name:NSThreadWillExitNotification object:serverThread];
    [serverThread start];
}

-(void)shutdown
{
    if (![self active])
    {
        gRPCLogError(@"Server cannot be shut down as not active.");
        return;
    }
    [lock lock];
    server->Shutdown(); // This should end the spawned thread.
    [lock unlock];
}

// Always called as another thread.
-(void)spawnInsecure
{
    [lock lock];
    gRPCService service([gRPCCache objectCache]);
    [lock unlock];
    
    grpc::EnableDefaultHealthCheckService(true);
    grpc::reflection::InitProtoReflectionServerBuilderPlugin();
    
    grpc::ServerBuilder builder;
    [lock lock];
    builder.AddListeningPort([_address UTF8String], grpc::InsecureServerCredentials());
    [lock unlock];
    
    builder.RegisterService(&service);
    builder.SetMaxMessageSize(512 * 1024 * 1024);
    builder.SetMaxSendMessageSize(512 * 1024 * 1024);
    builder.SetMaxReceiveMessageSize(512 * 1024 * 1024);
    
    [lock lock];
    // See https://chromium.googlesource.com/external/github.com/grpc/grpc/+/chromium-deps/2016-07-19/examples/cpp/helloworld/greeter_async_server.cc
    server = builder.BuildAndStart();
    [lock unlock];
    
    @try {
        // Wait for the server to shutdown. Note that some other thread must be
        // responsible for shutting down the server for this call to ever return.
        server->Wait();
    }
    @catch (NSException *exception) {
        gRPCLogDefault([NSString stringWithFormat:@"Following error occurred: %@\nEnding server.", [exception description]]);
        return;
    }
}

@end
