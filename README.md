# swift-nio-http2-demo
Project demonstrating the creation of a RESTful web service using apple/swift-nio-http2.

---
## Getting Started

Firstly, ensure nghttp2 is installed. You can do so via Homebrew.
```sh
$ brew install nghttp2
```
Next, clone the repository and open the .xcodeproj after it's generated.
```sh
$ git clone https://github.com/kylejohnsonkj/swift-nio-http2-demo.git
$ cd swift-nio-http2-demo/
$ swift package generate-xcodeproj
$ open myserver.xcodeproj/
```
Ensure **myserver** is selected as the scheme and that **My Mac** is set as the target device. The server is now ready to be built and run. Do so either through Xcode or by running `swift run` from within the project directory.

---
## Documentation

### Using cURL
Throughout this demo project we will be communicating with the server using cURL. After starting the server, you can verify everything is working correctly by using the following command.
```sh
$ curl -kvu user:pass https://localhost:8888
```

Note: This demo project supports HTTPS. Since we are using an example private key/cert to do this, the insecure (-k) flag must be included on all commands. I've also turned on verbose mode (-v) as well as basic authentication support (-u).

This server features all four methods to map CRUD (create, retrieve, update, delete) operations to HTTPS requests. The details of how to use these methods with the example **Person** object are demonstrated below.

---
### PUT (create)
Creates a person object from provided JSON data.
```sh
$ curl -kvu user:pass https://localhost:8888/persons -XPUT -d '{"name":"Kyle","age":22}'
```
All object properties must be included in JSON format for the object to be created (with the exception of id, which is generated by the server).

---
### GET (retrieve)
Retrieves all persons in JSON format matching the given query.
```sh
$ curl -kvu user:pass https://localhost:8888/persons
```
Supports queries for equality on all struct properties (ex. **/persons?id=0**, **/persons?name=Kyle**, **/persons?age=21**)

For multiple queries, tag on using "&" and include single quotes around the whole uri.
```sh
$ curl -kvu user:pass 'https://localhost:8888/persons?age=21&name=Kyle'
```

---
### PATCH (update)
```sh
$ curl -kvu user:pass https://localhost:8888/persons/0 -XPATCH -d '{"name":"Lyle"}'
```
All properties can be modified via JSON, with the exception of id, which is immutable.

Note: Only one resource can be updated per request. Resource count can be limited by querying or by supplying an object record like so: **/persons/{id}**

---
### DELETE
```sh
$ curl -kvu user:pass https://localhost:8888/persons/0 -XDELETE
```
Note: Similarly to PATCH, only one resource can be deleted per request. However, for convenience, if no query is specified (ex. **/persons**) the database will be reset.
