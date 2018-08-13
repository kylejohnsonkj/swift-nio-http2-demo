//
//  headers.swift
//  myserver
//
//  Created by Kyle Johnson on 8/8/18.
//

import NIO
import NIOHTTP1
import NIOHTTP2

import Foundation

let plainTextHeader: HTTPHeaders = {
    var headers = HTTPHeaders()
    headers.add(name: "content-type", value: "text/plain")
    return headers
}()

let jsonHeader: HTTPHeaders = {
    var headers = HTTPHeaders()
    headers.add(name: "content-type", value: "application/json")
    return headers
}()
