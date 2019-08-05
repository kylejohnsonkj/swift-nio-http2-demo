//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2019 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation
import NIO
import NIOSSL
import NIOHTTP1
import NIOHTTP2

// basic auth credentials
let user = User(user: "user", pass: "pass")
let authorizedUsers = [user]

final class HTTP1TestServer: ChannelInboundHandler {
    public typealias InboundIn = HTTPServerRequestPart
    public typealias OutboundOut = HTTPServerResponsePart
    
    var method: HTTPMethod!
    var uri: String!
    var headers: HTTPHeaders!
    var body = ""
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch self.unwrapInboundIn(data) {
            
        case .head(let request):
            method = request.method
            uri = request.uri
            headers = request.headers
            
        case .body(var buffer):
            let body = buffer.readString(length: buffer.readableBytes) ?? ""
            self.body += body
            
        case .end( _):
            guard let method = self.method, let uri = self.uri else {
                sendResponse(context, response: responseForCode(.badRequest, "unable to retrieve valid response"))
                return
            }
            
            // basic authentication
            guard let base64Encoded = headers["authorization"].joined().components(separatedBy: .whitespaces).last,
                let decodedData = Data(base64Encoded: base64Encoded),
                let decodedAuth = String(data: decodedData, encoding: .utf8),
                let _ = authorizedUsers.filter({ $0.auth == decodedAuth }).first else {
                    sendResponse(context, response: Response(statusCode: .unauthorized, headers: headerUnauthorized, body: ""))
                    return
            }
            
            let clientRequest = Request(method: method, uri: uri, body: body)
            let path = clientRequest.uri
            
            // handle root path
            guard path != "/" else {
                sendResponse(context, response: responseForCode(.ok, "congrats, you got it working!"))
                return
            }
            
            let matchingRoutes = routes.filter {
                String(path[..<path.index(path.startIndex, offsetBy: $0.request.uri.count)]) == $0.request.uri
                    && clientRequest.method == $0.request.method
            }
            
            guard matchingRoutes.count == 1, let route = matchingRoutes.first else {
                matchingRoutes.count == 0 ? sendResponse(context, response: responseForCode(.notFound, "route not found"))
                    : sendResponse(context, response: responseForCode(.internalServerError, "route inconclusive"))
                return
            }
            
            let response = route.handler(clientRequest)
            sendResponse(context, response: response)
        }
    }
    
    private func sendResponse(_ context: ChannelHandlerContext, response: Response) {
        // Insert an event loop tick here. This more accurately represents real workloads in SwiftNIO, which will not
        // re-entrantly write their response frames.
        context.eventLoop.execute {
            context.channel.getOption(HTTP2StreamChannelOptions.streamID).flatMap { (streamID) -> EventLoopFuture<Void> in
                var headers = response.headers
                headers.add(name: "content-length", value: "\(response.body.count)")
                headers.add(name: "x-stream-id", value: "\(Int(streamID))")
                headers.add(name: "etag", value: md5(response.body))
                context.channel.write(self.wrapOutboundOut(
                    HTTPServerResponsePart.head(HTTPResponseHead(version: .init(major: 2, minor: 0), status: response.statusCode, headers: headers))
                ), promise: nil)
                
                var buffer = context.channel.allocator.buffer(capacity: 12)
                buffer.writeString(response.body)
                context.channel.write(self.wrapOutboundOut(HTTPServerResponsePart.body(.byteBuffer(buffer))), promise: nil)
                return context.channel.writeAndFlush(self.wrapOutboundOut(HTTPServerResponsePart.end(nil)))
            }.whenComplete { _ in
                context.close(promise: nil)
            }
        }
    }
}

final class ErrorHandler: ChannelInboundHandler {
    typealias InboundIn = Never
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("Server received error: \(error)")
        context.close(promise: nil)
    }
}

// First argument is the program path
let arguments = CommandLine.arguments
let arg1 = arguments.dropFirst().first
let arg2 = arguments.dropFirst().dropFirst().first
let arg3 = arguments.dropFirst().dropFirst().dropFirst().first

let defaultHost = "localhost"
let defaultPort: Int = 8888
let defaultHtdocs = "/dev/null/"

enum BindTo {
    case ip(host: String, port: Int)
    case unixDomainSocket(path: String)
}

let htdocs: String
let bindTarget: BindTo
switch (arg1, arg1.flatMap { Int($0) }, arg2, arg2.flatMap { Int($0) }, arg3) {
case (.some(let h), _ , _, .some(let p), let maybeHtdocs):
    /* second arg an integer --> host port [htdocs] */
    bindTarget = .ip(host: h, port: p)
    htdocs = maybeHtdocs ?? defaultHtdocs
case (_, .some(let p), let maybeHtdocs, _, _):
    /* first arg an integer --> port [htdocs] */
    bindTarget = .ip(host: defaultHost, port: p)
    htdocs = maybeHtdocs ?? defaultHtdocs
case (.some(let portString), .none, let maybeHtdocs, .none, .none):
    /* couldn't parse as number --> uds-path [htdocs] */
    bindTarget = .unixDomainSocket(path: portString)
    htdocs = maybeHtdocs ?? defaultHtdocs
default:
    htdocs = defaultHtdocs
    bindTarget = BindTo.ip(host: defaultHost, port: defaultPort)
}

// The following lines load the example private key/cert from HardcodedPrivateKeyAndCerts.swift .
// DO NOT USE THESE KEYS/CERTIFICATES IN PRODUCTION.
// For a real server, you would obtain a real key/cert and probably put them in files and load them with
//
//     NIOSSLPrivateKeySource.file("/path/to/private.key")
//     NIOSSLCertificateSource.file("/path/to/my.cert")

// Load the private key
let sslPrivateKey = try! NIOSSLPrivateKeySource.privateKey(NIOSSLPrivateKey(buffer: [Int8](samplePKCS8PemPrivateKey.utf8CString),
                                                                            format: .pem) { providePassword in
                                                                                providePassword("thisisagreatpassword".utf8)
})

// Load the certificate
let sslCertificate = try! NIOSSLCertificateSource.certificate(NIOSSLCertificate(buffer: [Int8](samplePemCert.utf8CString),
                                                                                format: .pem))

// Set up the TLS configuration, it's important to set the `applicationProtocols` to
// `NIOHTTP2SupportedALPNProtocols` which (using ALPN (https://en.wikipedia.org/wiki/Application-Layer_Protocol_Negotiation))
// advertises the support of HTTP/2 to the client.
let tlsConfiguration = TLSConfiguration.forServer(certificateChain: [sslCertificate],
                                                  privateKey: sslPrivateKey,
                                                  applicationProtocols: NIOHTTP2SupportedALPNProtocols)
// Configure the SSL context that is used by all SSL handlers.
let sslContext = try! NIOSSLContext(configuration: tlsConfiguration)

let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
let bootstrap = ServerBootstrap(group: group)
    // Specify backlog and enable SO_REUSEADDR for the server itself
    .serverChannelOption(ChannelOptions.backlog, value: 256)
    .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
    
    // Set the handlers that are applied to the accepted Channels
    .childChannelInitializer { channel in
        // First, we need an SSL handler because HTTP/2 is almost always spoken over TLS.
        channel.pipeline.addHandler(try! NIOSSLServerHandler(context: sslContext)).flatMap {
            // Right after the SSL handler, we can configure the HTTP/2 pipeline.
            channel.configureHTTP2Pipeline(mode: .server) { (streamChannel, streamID) -> EventLoopFuture<Void> in
                // For every HTTP/2 stream that the client opens, we put in the `HTTP2ToHTTP1ServerCodec` which
                // transforms the HTTP/2 frames to the HTTP/1 messages from the `NIOHTTP1` module.
                streamChannel.pipeline.addHandler(HTTP2ToHTTP1ServerCodec(streamID: streamID)).flatMap { () -> EventLoopFuture<Void> in
                    // And lastly, we put in our very basic HTTP server :).
                    streamChannel.pipeline.addHandler(HTTP1TestServer())
                }.flatMap { () -> EventLoopFuture<Void> in
                    streamChannel.pipeline.addHandler(ErrorHandler())
                }
            }
        }.flatMap { (_: HTTP2StreamMultiplexer) in
            return channel.pipeline.addHandler(ErrorHandler())
        }
}
    
    // Enable TCP_NODELAY and SO_REUSEADDR for the accepted Channels
    .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
    .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
    .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)

defer {
    try! group.syncShutdownGracefully()
}

let channel = try { () -> Channel in
    switch bindTarget {
    case .ip(let host, let port):
        return try bootstrap.bind(host: host, port: port).wait()
    case .unixDomainSocket(let path):
        return try bootstrap.bind(unixDomainSocketPath: path).wait()
    }
    }()

// MARK: - Usage
let baseUrl = "curl -kvu \(user.auth) https://\(defaultHost):\(defaultPort)"

print("Server started!")
print("Verify  ->  \(baseUrl)")

print("\nExample REST Method Usage")
print("GET     ->  \(baseUrl)/persons")
print("PUT     ->  \(baseUrl)/persons -XPUT -d '{\"name\":\"Kyle\",\"age\":22}'")
print("PATCH   ->  \(baseUrl)/persons/0 -XPATCH -d '{\"name\":\"Lyle\"}'")
print("DELETE  ->  \(baseUrl)/persons/0 -XDELETE")

// This will never unblock as we don't close the ServerChannel
try channel.closeFuture.wait()

print("Server closed")
