//
//  Home to all parsing/conversion alongside helpful generic functions.
//
//  utils.swift
//  myserver
//
//  Created by Kyle Johnson on 8/8/18.
//

import Foundation

// MARK: - URI parsing

func getRecord(from uri: String) -> String {
    guard let url = URL(string: uri) else {
        return ""
    }
    let components = url.path.components(separatedBy: "/").dropFirst()
    guard components.count > 1,
        let record = components.last else {
            return ""
    }
    return record
}

func getQuery(from uri: String) -> String {
    guard let url = URL(string: uri) else {
        return ""
    }
    return url.query ?? ""
}

func getParams(from query: String) -> [String: String] {
    let queries = query.trimmingCharacters(in: .whitespaces).split(separator: "&")
    let params: [String: String] = Dictionary(uniqueKeysWithValues: queries.map {(
        String($0.split(separator: "=", maxSplits: 1).first ?? "").removingPercentEncoding ?? "",
        String($0.split(separator: "=", maxSplits: 1).last ?? "").removingPercentEncoding ?? ""
    )})
    return params
}

// MARK: - Helpful generic functions

func getAllObjects<T: Codable>(forKey key: String) -> [T] {
    let emptyArray: [T] = []
    if UserDefaults.standard.value(forKey: key) as? Data == nil {
        UserDefaults.standard.set(try? PropertyListEncoder().encode(emptyArray), forKey: key)
    }
    guard let savedData = UserDefaults.standard.value(forKey: key) as? Data,
        let objects = try? PropertyListDecoder().decode(Array<T>.self, from: savedData) else {
            return emptyArray
    }
    return objects
}

func filterObjectsByParams<T: Codable>(_ objects: [T], params: [String: String]) -> [T] {
    guard !params.isEmpty else { return objects }
    return objects.filter { object in
        let properties = dictionaryRepresentation(object: object)
        return doesDictionaryContainAllValues(dict: properties, subDict: params)
    }
}

func getObjectsForRequest<T: Codable>(request: Request, key: String) -> (allObjects: [T], matchingObjects: [T]) {
    let record = getRecord(from: request.uri)
    let query = getQuery(from: request.uri)
    var params = getParams(from: query)
    
    if record != "" {
        params.updateValue(record, forKey: "id")
    }
    
    let allObjects: [T] = getAllObjects(forKey: key)
    let matchingObjects: [T] = filterObjectsByParams(allObjects, params: params)
    return (allObjects, matchingObjects)
}

// MARK: - Dictionary conversions

func dictionaryRepresentation(object: Any) -> [String: String] {
    let mirror = Mirror(reflecting: object)
    let properties: [String: String] = Dictionary(uniqueKeysWithValues: mirror.children.map { ($0.label ?? "", String(describing: $0.value)) })
    return properties
}

func doesDictionaryContainAllValues(dict: [String: String], subDict: [String: String]) -> Bool {
    let matchCount = subDict.filter { $0.value == dict[$0.key] }.count
    return matchCount == subDict.count
}

// MARK: - JSON parsing

func jsonResponseForValue<T: Codable>(_ value: T) -> Response {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    
    guard let jsonData = try? encoder.encode(value), let json = String(data: jsonData, encoding: String.Encoding.utf8) else {
        return Response(statusCode: .internalServerError, headers: headerPlainText, body: "failed to encode data")
    }
    return Response(statusCode: .ok, headers: headerJson, body: json)
}

func convertJsonToDict(json: String) -> [String: Any] {
    guard let jsonData = json.data(using: .utf8),
        let object = try? JSONSerialization.jsonObject(with: jsonData, options: []),
        let properties = object as? [String: Any] else {
            return [:]
    }
    return properties
}

// MARK: - Storage

func setValue<T: Codable>(_ objects: T, forKey key: String) {
    UserDefaults.standard.set(try? PropertyListEncoder().encode(objects), forKey: key)
}

func getLatestId(forKey key: String) -> Int {
    var id = UserDefaults.standard.integer(forKey: "\(key)-id")
    id += 1
    UserDefaults.standard.set(id, forKey: "\(key)-id")
    return id
}

