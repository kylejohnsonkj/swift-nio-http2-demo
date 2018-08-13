//
//  components.swift
//  myserver
//
//  Created by Kyle Johnson on 8/8/18.
//

import NIO
import NIOHTTP1
import NIOHTTP2

import Foundation

struct Request {
    let method: HTTPMethod
    let uri: String
    let body: String
}

extension Request: Equatable {
    static func ==(lhs: Request, rhs: Request) -> Bool {
        return lhs.method == rhs.method && lhs.uri == rhs.uri && lhs.body == rhs.body
    }
}

struct Response {
    let statusCode: HTTPResponseStatus
    let headers: HTTPHeaders
    let body: String
}

func responseForError(_ message: String) -> Response {
    return Response(statusCode: .internalServerError, headers: plainTextHeader, body: message)
}

struct Route {
    let request: Request
    let handler: (Request) -> Response
}

extension Route {
    init(_ method: HTTPMethod, _ uri: String, _ handler: @escaping (Request) -> Response) {
        self.request = Request(method: method, uri: uri, body: "")
        self.handler = handler
    }
}

let routes = [
//    Route(request: Request(method: .GET, uri: "/person", body: ""), handler: PersonResource().get),
//    Route(request: Request(method: .PUT, uri: "/person", body: ""), handler: PersonResource().create)
//    Route(.PUT, "/person", PersonResource().create)
    Route(.GET, "/person", PersonResource().get), Route(.PUT, "/person", PersonResource().create),

]
