//
//  utils.swift
//  myserver
//
//  Created by Kyle Johnson on 8/8/18.
//

import Foundation

func getPathAndQuery(from uri: String) -> (String?, String?) {
    guard let url = URL(string: uri) else {
        return (nil, nil)
    }
    guard let query = url.query else {
        return (url.path, nil)
    }
    return (url.path, query)
}

func getParams(from query: String) -> [String: String] {
    let queries = query.trimmingCharacters(in: .whitespaces).split(separator: "&")
    let params: [String: String] = Dictionary(uniqueKeysWithValues: queries.map {
        (
            String($0.split(separator: "=", maxSplits: 1).first ?? "").removingPercentEncoding ?? "",
            String($0.split(separator: "=", maxSplits: 1).last ?? "").removingPercentEncoding ?? ""
        )
    })
    return params
}

func getAllObjects<T: Codable>(forKey key: String) -> [T]? {
    if UserDefaults.standard.value(forKey: key) as? Data == nil {
        let emptyArray: [T] = []
        UserDefaults.standard.set(try? PropertyListEncoder().encode(emptyArray), forKey: key)
    }
    guard let savedData = UserDefaults.standard.value(forKey: key) as? Data,
        let objects = try? PropertyListDecoder().decode(Array<T>.self, from: savedData) else {
            return nil
    }
    return objects
}

func createObject<T: Codable>(from json: String) -> T? {
    guard let data = json.data(using: .utf8),
        let object = try? JSONDecoder().decode(T.self, from: data) else {
            return nil
    }
    return object
}

func filterObjectsByParams<T: Codable>(_ objects: [T], params: [String: String]) -> [T] {
    guard !params.isEmpty else { return objects }
    var matchingObjects: [T] = []
    
    for object in objects {
        let mirror = Mirror(reflecting: object)
        
        for child in mirror.children {
            guard let label = child.label else { continue }
            let value = String(describing: child.value)
            
            var isMatch: Bool!
            for param in params {
                isMatch = true
                if param.key != label || param.value != value {
                    isMatch = false
                }
            }
            if isMatch {
                matchingObjects.append(object)
            }
        }
    }
    return matchingObjects
}

func setValue<T: Codable>(_ objects: T, forKey key: String) {
    UserDefaults.standard.set(try? PropertyListEncoder().encode(objects), forKey: key)
}

func jsonResponseForValue<T: Codable>(_ value: T) -> Response {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    if let jsonData = try? encoder.encode(value), let json = String(data: jsonData, encoding: String.Encoding.utf8) {
        return Response(statusCode: .ok, headers: jsonHeader, body: json)
    } else {
        return Response(statusCode: .internalServerError, headers: plainTextHeader, body: "Server Error: failed to encode data")
    }
}


