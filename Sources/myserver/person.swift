//
//  person.swift
//  myserver
//
//  Created by Kyle Johnson on 8/8/18.
//

import Foundation

struct Person: Codable {
//    let id: Int  // sorted set
    let name: String
    let age: Int
}

extension Person: Equatable {
    static func ==(lhs: Person, rhs: Person) -> Bool {
        return lhs.name == rhs.name && lhs.age == rhs.age
    }
}

// TODO:
// make shorter response function for errors
// remove Person.self and specify in assignment of generic values
// add update, delete
// test using another data route besides person
// set etag by hash of response
// commit and submit to github

struct PersonResource {
    
    func get(request: Request) -> Response {
        
        let (path, query) = getPathAndQuery(from: request.uri)
        guard path != nil else {
            return responseForError("Server Error: failed to interpret URI")
        }
        
        // return persons matching query
        guard let persons: [Person] = getAllObjects(forKey: "persons") else {
            return responseForError("Server Error: failed to retrieve stored data")
        }
        
        if let query = query {
            let params = getParams(from: query)
            let matchingPersons: [Person] = filterObjectsByParams(persons, params: params)
            return jsonResponseForValue(matchingPersons)
        } else {
            return jsonResponseForValue(persons)
        }
    }
    
    // save json into persons array
    func create(request: Request) -> Response {
        
        // convert given json to Person object
        guard let person: Person = createObject(from: request.body) else {
            return responseForError("Server Error: failed to interpret JSON as type 'Person'")
        }
        
        // get array of existing persons
        guard var persons: [Person] = getAllObjects(forKey: "persons") else {
            return responseForError("Server Error: failed to retrieve stored data as Array<Person>")
        }
        
        // if person doesn't exist, add to array
        if !persons.contains(person) {
            persons.append(person)
            setValue(persons, forKey: "persons")
        }
        
        // return added person in response
        return jsonResponseForValue(person)
    }
}
