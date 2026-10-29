#!/usr/bin/env swift
import CryptoKit
import Darwin
import Foundation

let arguments = CommandLine.arguments

guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: sign-update.swift <zip> <signature>\n".utf8))
    exit(2)
}

let zipURL = URL(fileURLWithPath: arguments[1])
let signatureURL = URL(fileURLWithPath: arguments[2])

guard let encodedKey = ProcessInfo.processInfo.environment["BABYLOCK_UPDATE_SIGNING_KEY"],
      let keyData = Data(base64Encoded: encodedKey) else {
    FileHandle.standardError.write(Data("BABYLOCK_UPDATE_SIGNING_KEY is missing or not base64\n".utf8))
    exit(3)
}

do {
    let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
    let archive = try Data(contentsOf: zipURL)
    let signature = try privateKey.signature(for: archive)

    try signature.write(to: signatureURL, options: .atomic)
    print("signed \(zipURL.lastPathComponent) (\(archive.count) bytes)")
} catch {
    FileHandle.standardError.write(Data("signing failed: \(error)\n".utf8))
    exit(1)
}
