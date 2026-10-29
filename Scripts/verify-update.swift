#!/usr/bin/env swift
import CryptoKit
import Darwin
import Foundation

let arguments = CommandLine.arguments

guard arguments.count == 4 else {
    FileHandle.standardError.write(Data("usage: verify-update.swift <zip> <signature> <public-key-base64>\n".utf8))
    exit(2)
}

let zipURL = URL(fileURLWithPath: arguments[1])
let signatureURL = URL(fileURLWithPath: arguments[2])

guard let keyData = Data(base64Encoded: arguments[3]) else {
    FileHandle.standardError.write(Data("public key is not base64\n".utf8))
    exit(3)
}

do {
    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    let archive = try Data(contentsOf: zipURL)
    let signature = try Data(contentsOf: signatureURL)

    guard signature.count == 64 else {
        FileHandle.standardError.write(Data("signature is \(signature.count) bytes, expected 64\n".utf8))
        exit(1)
    }

    guard publicKey.isValidSignature(signature, for: archive) else {
        FileHandle.standardError.write(Data("signature does not match the pinned public key\n".utf8))
        exit(1)
    }

    print("update signature OK (\(archive.count) bytes)")
} catch {
    FileHandle.standardError.write(Data("verification failed: \(error)\n".utf8))
    exit(1)
}
