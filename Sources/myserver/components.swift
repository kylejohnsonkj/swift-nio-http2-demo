//
//  API structure (Request, Response, Route) along with preset headers and user database.
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

// MARK: - Route
let routes = [
    Route(.GET, "/persons", PersonResource().get),
    Route(.PUT, "/persons", PersonResource().create),
    Route(.PATCH, "/persons", PersonResource().update),
    Route(.DELETE, "/persons", PersonResource().delete)
]

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

// MARK: - Request
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

// MARK: - Response
struct Response {
    let statusCode: HTTPResponseStatus
    let headers: HTTPHeaders
    let body: String
}

func responseForCode(_ statusCode: HTTPResponseStatus, _ message: String) -> Response {
    guard !message.isEmpty else {
        return Response(statusCode: statusCode, headers: headerPlainText, body: "")
    }
    return Response(statusCode: statusCode, headers: headerPlainText, body: "\(statusCode.reasonPhrase): \(message)")
}

func responseForCode(_ statusCode: HTTPResponseStatus) -> Response {
    return responseForCode(statusCode, "")
}

// MARK: - Headers
let headerPlainText: HTTPHeaders = {
    var headers = HTTPHeaders()
    headers.add(name: "content-type", value: "text/plain")
    return headers
}()

let headerJson: HTTPHeaders = {
    var headers = HTTPHeaders()
    headers.add(name: "content-type", value: "application/json")
    return headers
}()

let headerUnauthorized: HTTPHeaders = {
    var headers = HTTPHeaders()
    headers.add(name: "content-type", value: "text/plain")
    headers.add(name: "www-authenticate", value: "basic")
    return headers
}()

// MARK: - Auth
struct User {
    let user: String
    let pass: String
    
    var auth: String {
        return "\(user):\(pass)"
    }
}

let authorizedUsers = [
    User(user: "user", pass: "pass")
]

