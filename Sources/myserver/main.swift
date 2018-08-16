// This example server currently does not know how to negotiate HTTP/2. That will come in a future enhancement. For now, you can
// hit it with curl like so: curl -vu 'user:pass' --http2-prior-knowledge http://localhost:8889/

import NIO
import NIOHTTP1
import NIOHTTP2

import Foundation

final class HTTP1TestServer: ChannelInboundHandler {
    
    public typealias InboundIn = HTTPServerRequestPart
    public typealias OutboundOut = HTTPServerResponsePart
    
    var method: HTTPMethod!
    var uri: String!
    var headers: HTTPHeaders!
    var body = ""

    public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
        
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
                sendResponse(ctx, response: responseForCode(.badRequest, "unable to retrieve valid response"))
                return
            }
            
            // basic authentication
            guard let base64Encoded = headers["authorization"].joined().components(separatedBy: .whitespaces).last,
                let decodedData = Data(base64Encoded: base64Encoded),
                let decodedAuth = String(data: decodedData, encoding: .utf8),
                let _ = authorizedUsers.filter({ $0.auth == decodedAuth }).first else {
                    sendResponse(ctx, response: Response(statusCode: .unauthorized, headers: headerUnauthorized, body: ""))
                    return
            }
            
            let clientRequest = Request(method: method, uri: uri, body: body)
            let path = clientRequest.uri
            
            // handle root path
            guard path != "/" else {
                sendResponse(ctx, response: responseForCode(.ok, "congrats, you got it working!"))
                return
            }
            
            let matchingRoutes = routes.filter {
                String(path[..<path.index(path.startIndex, offsetBy: $0.request.uri.count)]) == $0.request.uri
                    && clientRequest.method == $0.request.method
            }
            
            guard matchingRoutes.count == 1, let route = matchingRoutes.first else {
                matchingRoutes.count == 0 ? sendResponse(ctx, response: responseForCode(.notFound, "route not found"))
                    : sendResponse(ctx, response: responseForCode(.internalServerError, "route inconclusive"))
                return
            }
            
            let response = route.handler(clientRequest)
            sendResponse(ctx, response: response)
        }
    }
    
    private func sendResponse(_ ctx: ChannelHandlerContext, response: Response) {
        ctx.channel.getOption(option: HTTP2StreamChannelOptions.streamID).then { (streamID) -> EventLoopFuture<Void> in
            var headers = response.headers
            headers.add(name: "content-length", value: "\(response.body.count)")
            headers.add(name: "x-stream-id", value: "\(streamID.networkStreamID!)")
            headers.add(name: "etag", value: md5(response.body))
            ctx.channel.write(self.wrapOutboundOut(HTTPServerResponsePart.head(HTTPResponseHead(version: .init(major: 2, minor: 0), status: response.statusCode, headers: headers))), promise: nil)
            
            var buffer = ctx.channel.allocator.buffer(capacity: 12)
            buffer.write(string: response.body)
            ctx.channel.write(self.wrapOutboundOut(HTTPServerResponsePart.body(.byteBuffer(buffer))), promise: nil)
            
            return ctx.channel.writeAndFlush(self.wrapOutboundOut(HTTPServerResponsePart.end(nil)))
        }.whenComplete {
            ctx.close(promise: nil)
        }
    }
}

// First argument is the program path
let arguments = CommandLine.arguments
let arg1 = arguments.dropFirst().first
let arg2 = arguments.dropFirst().dropFirst().first
let arg3 = arguments.dropFirst().dropFirst().dropFirst().first

let defaultHost = "::1"
let defaultPort: Int = 8889
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

let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
let bootstrap = ServerBootstrap(group: group)
    // Specify backlog and enable SO_REUSEADDR for the server itself
    .serverChannelOption(ChannelOptions.backlog, value: 256)
    .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
    
    // Set the handlers that are applied to the accepted Channels
    .childChannelInitializer { channel in
        return channel.pipeline.add(handler: HTTP2Parser(mode: .server)).then {
            let multiplexer = HTTP2StreamMultiplexer { (channel, streamID) -> EventLoopFuture<Void> in
                return channel.pipeline.add(handler: HTTP2ToHTTP1ServerCodec(streamID: streamID)).then { () -> EventLoopFuture<Void> in
                    channel.pipeline.add(handler: HTTP1TestServer())
                }
            }
            
            return channel.pipeline.add(handler: multiplexer)
        }
    }
    
    // Enable TCP_NODELAY and SO_REUSEADDR for the accepted Channels
    .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
    .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
    .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)

defer {
    try! group.syncShutdownGracefully()
}

print("htdocs = \(htdocs)")

let channel = try { () -> Channel in
    switch bindTarget {
    case .ip(let host, let port):
        return try bootstrap.bind(host: host, port: port).wait()
    case .unixDomainSocket(let path):
        return try bootstrap.bind(unixDomainSocketPath: path).wait()
    }
}()

print("Server started and listening on \(channel.localAddress!), htdocs path \(htdocs)")

// This will never unblock as we don't close the ServerChannel
try channel.closeFuture.wait()

print("Server closed")

